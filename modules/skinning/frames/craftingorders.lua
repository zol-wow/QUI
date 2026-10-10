local addonName, ns = ...

if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end

local GetCore = ns.Helpers.GetCore
local SkinBase = ns.SkinBase

local function IsEnabled()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings.skinCraftingOrders
end

local function skinRow(row)
    if not IsEnabled() or not row or (row.IsForbidden and row:IsForbidden()) then return end
    SkinBase.SkinScrollRow(row)
    SkinBase.LockPooledRowText(row, 4)
    for _, cell in ipairs(row.cells or {}) do
        if not (cell.IsForbidden and cell:IsForbidden()) then
            SkinBase.SkinFontString(cell.Text, { fontOnly = true })
            SkinBase.LockFontObject(cell.Text, { fontOnly = true })
            if cell.Icon then
                SkinBase.RoundIconTexture(cell, cell.Icon)
                local border = SkinBase.SkinIcon(cell.Icon, { parent = cell })
                if border then SkinBase.ApplyChromeBackdrop(border, { radius = 4, withBackground = false }) end
                SkinBase.ClampTextureHidden(cell.IconBorder, true)
            end
        end
    end
end

local function StyleOrderHeader(header)
    if not IsEnabled() or not header or (header.IsForbidden and header:IsForbidden()) then return end
    for _, key in ipairs({ "Left", "Middle", "Right" }) do
        SkinBase.ClampTextureHidden(header[key], true)
    end
    SkinBase.ClampTextureHidden(header.GetHighlightTexture and header:GetHighlightTexture(), true)
    SkinBase.ApplyButtonFontObjects(header)
    if type(header.Init) == "function" and not SkinBase.GetFrameData(header, "qOrderHeaderInitHooked") then
        hooksecurefunc(header, "Init", StyleOrderHeader)
        SkinBase.SetFrameData(header, "qOrderHeaderInitHooked", true)
    end
end

local function StyleOrderTableHeaders(owner)
    if not IsEnabled() or not owner or (owner.IsForbidden and owner:IsForbidden()) then return end
    local builder = owner.tableBuilder
    if not builder or type(builder.EnumerateHeaders) ~= "function" then return end
    for header in builder:EnumerateHeaders() do StyleOrderHeader(header) end
    if type(builder.ArrangeCells) == "function" and not SkinBase.GetFrameData(builder, "qOrderCellsArrangeHooked") then
        hooksecurefunc(builder, "ArrangeCells", function(_, row) skinRow(row) end)
        SkinBase.SetFrameData(builder, "qOrderCellsArrangeHooked", true)
    end
    if type(builder.Arrange) == "function" and not SkinBase.GetFrameData(builder, "qOrderHeaderArrangeHooked") then
        hooksecurefunc(builder, "Arrange", function() StyleOrderTableHeaders(owner) end)
        SkinBase.SetFrameData(builder, "qOrderHeaderArrangeHooked", true)
    end
end

local function RefreshOrderTableHeaders(frame)
    StyleOrderTableHeaders(frame.BrowseOrders)
    StyleOrderTableHeaders(frame.MyOrdersPage)
    StyleOrderTableHeaders(frame.Form and frame.Form.CurrentListings)
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
    SkinBase.SkinTabGroup(tabs, frame, { font = true, resizeToText = true, dockBottom = true })
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
            SkinBase.SkinDropdown(dropdown, { skinArrow = true, belowChildren = true })
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
            SkinBase.ForEachScrollBoxFrame(self, StyleCategoryRow)
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

local function StylePaymentControls(form)
    if not IsEnabled() or not form or (form.IsForbidden and form:IsForbidden()) then return end
    local payment = form.PaymentContainer
    if not payment or (payment.IsForbidden and payment:IsForbidden()) then return end
    local input = payment.TipMoneyInputFrame
    if input and not (input.IsForbidden and input:IsForbidden()) then
        for _, key in ipairs({ "GoldBox", "SilverBox", "CopperBox" }) do
            local field = input[key]
            if field and not (field.IsForbidden and field:IsForbidden()) then
                local icon = field.Icon
                local alpha = icon and icon:GetAlpha()
                SkinBase.SkinEditBox(field, { font = false })
                if icon and alpha then icon:SetAlpha(alpha) end
                SkinBase.SkinFontString(field, { fontOnly = true })
                SkinBase.LockFontObject(field, { fontOnly = true })
                SkinBase.SkinFontString(field.Text, { fontOnly = true })
                SkinBase.RefreshWidget(field)
            end
        end
    end
    for _, key in ipairs({ "Tip", "Duration", "TimeRemaining", "PostingFee", "TotalPrice" }) do
        local text = payment[key]
        if text then
            SkinBase.SkinFontString(text, { fontOnly = true })
            SkinBase.LockFontObject(text, { fontOnly = true })
            if NORMAL_FONT_COLOR and NORMAL_FONT_COLOR.GetRGB and text.GetTextColor then
                local nr, ng, nb = NORMAL_FONT_COLOR:GetRGB()
                local r, g, b, a = text:GetTextColor()
                if r == nr and g == ng and b == nb then text:SetTextColor(0.9, 0.9, 0.9, a or 1) end
            end
        end
    end
    for _, key in ipairs({ "TipMoneyDisplayFrame", "PostingFeeMoneyDisplayFrame", "TotalPriceMoneyDisplayFrame", "TimeRemainingDisplay" }) do
        SkinBase.SkinFrameText(payment[key], { recurse = true })
    end
    if not SkinBase.GetFrameData(form, "qOrdersPaymentHooked") then
        if type(form.UpdateTotalPrice) == "function" then hooksecurefunc(form, "UpdateTotalPrice", StylePaymentControls) end
        form:HookScript("OnShow", StylePaymentControls)
        SkinBase.SetFrameData(form, "qOrdersPaymentHooked", true)
    end
end

local function StyleOrderNotes(form)
    if not IsEnabled() or not form or (form.IsForbidden and form:IsForbidden()) then return end
    local payment = form.PaymentContainer
    local note = payment and payment.NoteEditBox
    if not note or (note.IsForbidden and note:IsForbidden()) then return end
    SkinBase.SkinEditBox(note, { font = false, borderAlpha = 0.5, bgAlpha = 0.8 })
    SkinBase.ClampTextureHidden(note.Border, true)
    SkinBase.RefreshWidget(note)
    local title = note.TitleBox and note.TitleBox.Title
    SkinBase.SkinFontString(title, { color = { 0.9, 0.9, 0.9, 1 } })
    local scrolling = note.ScrollingEditBox
    local edit = scrolling and scrolling.ScrollBox and scrolling.ScrollBox.EditBox
    if edit and not (edit.IsForbidden and edit:IsForbidden()) then
        SkinBase.SkinFontString(edit, { fontOnly = true })
        SkinBase.LockFontObject(edit, { fontOnly = true })
    end
end

local function StyleOrderAllocation(form)
    if not IsEnabled() or not form or (form.IsForbidden and form:IsForbidden()) then return end
    local checkbox = form.AllocateBestQualityCheckbox
    if not checkbox or (checkbox.IsForbidden and checkbox:IsForbidden()) then return end
    SkinBase.SkinCheckBox(checkbox)
    local backdrop = SkinBase.GetBackdrop(checkbox)
    if backdrop then
        backdrop:ClearAllPoints()
        backdrop:SetPoint("TOPLEFT", checkbox, "TOPLEFT", 5, -5)
        backdrop:SetPoint("BOTTOMRIGHT", checkbox, "BOTTOMRIGHT", -5, 5)
        SkinBase.ApplyChromeBackdrop(backdrop, { radius = 3, withBackground = true })
    end
    SkinBase.SkinFontString(checkbox.text, { fontOnly = true })
    SkinBase.LockFontObject(checkbox.text, { fontOnly = true })
    SkinBase.RefreshWidget(checkbox)
end

local function StyleOrderOutput(form)
    if not IsEnabled() or not form or (form.IsForbidden and form:IsForbidden()) then return end
    local output = form.OutputIcon
    if not output or (output.IsForbidden and output:IsForbidden()) or not output.Icon then return end
    if not SkinBase.GetFrameData(output, "qOrderOutputQualityHooked") and type(output.SetItemButtonQuality) == "function" then
        hooksecurefunc(output, "SetItemButtonQuality", function(_, quality)
            SkinBase.SetFrameData(output, "qOrderOutputQuality", quality)
            SkinBase.SetFrameData(output, "qOrderOutputQualityKnown", true)
            StyleOrderOutput(form)
        end)
        SkinBase.SetFrameData(output, "qOrderOutputQualityHooked", true)
    end
    local quality = SkinBase.GetFrameData(output, "qOrderOutputQuality")
    if not SkinBase.GetFrameData(output, "qOrderOutputQualityKnown") and output.IconBorder and output.IconBorder:IsShown() and output.IconBorder.GetAtlas and ColorManager and ColorManager.GetAtlasDataForAuctionHouseItemQuality then
        local atlas = output.IconBorder:GetAtlas()
        for value = 0, 8 do
            local data = ColorManager.GetAtlasDataForAuctionHouseItemQuality(value)
            if atlas and data and data.atlas == atlas then quality = value; break end
        end
    end
    local sr, sg, sb, sa = SkinBase.GetWindowColors()
    local data = quality and ColorManager and ColorManager.GetColorDataForItemQuality(quality)
    local color = data and data.color
    if color and color.GetRGBA then sr, sg, sb, sa = color:GetRGBA() end
    local icon = output.Icon
    if output.CircleMask and icon.RemoveMaskTexture then icon:RemoveMaskTexture(output.CircleMask) end
    SkinBase.RoundIconTexture(output, icon)
    local border = SkinBase.SkinIcon(icon)
    if border then
        SkinBase.SetFrameData(border, "chromeRadius", 4)
        SkinBase.SetBackdropColors(border, { sr, sg, sb, sa }, nil)
    end
    SkinBase.ClampTextureHidden(output.IconBorder, true)
    local highlight = output.GetHighlightTexture and output:GetHighlightTexture()
    if highlight then
        highlight:SetTexture("Interface\\Buttons\\WHITE8x8")
        highlight:ClearAllPoints()
        highlight:SetAllPoints(icon)
        highlight:SetVertexColor(sr, sg, sb, 0.15)
        SkinBase.RoundIconTexture(output, highlight)
    end
    SkinBase.SkinFontString(output.Count, { fontOnly = true })
    SkinBase.LockFontObject(output.Count, { fontOnly = true })
end

local function StyleOrderReagentLabels(form)
    if not IsEnabled() or not form or (form.IsForbidden and form:IsForbidden()) then return end
    local container = form.ReagentContainer
    if not container or (container.IsForbidden and container:IsForbidden()) then return end
    for _, key in ipairs({ "Reagents", "OptionalReagents" }) do
        local section = container[key]
        local label = section and not (section.IsForbidden and section:IsForbidden()) and section.Label
        if label and not (label.IsForbidden and label:IsForbidden()) then
            SkinBase.SkinFontString(label, { fontOnly = true })
            SkinBase.LockFontObject(label, { fontOnly = true })
            if NORMAL_FONT_COLOR and NORMAL_FONT_COLOR.GetRGB and label.GetTextColor then
                local nr, ng, nb = NORMAL_FONT_COLOR:GetRGB()
                local r, g, b, a = label:GetTextColor()
                if r == nr and g == ng and b == nb then label:SetTextColor(0.9, 0.9, 0.9, a or 1) end
            end
        end
    end
    SkinBase.SkinFontString(container.RecraftInfoText, { fontOnly = true })
    SkinBase.LockFontObject(container.RecraftInfoText, { fontOnly = true })
end

local function StyleOrderReagentSlot(slot)
    if not IsEnabled() or not slot or (slot.IsForbidden and slot:IsForbidden()) then return end
    local button = slot.Button
    if not button or (button.IsForbidden and button:IsForbidden()) or not button.Icon then return end
    if not SkinBase.GetFrameData(button, "qOrderReagentHooked") then
        if type(button.SetSlotQuality) == "function" then
            hooksecurefunc(button, "SetSlotQuality", function(_, quality)
                SkinBase.SetFrameData(button, "qOrderReagentQuality", quality)
                StyleOrderReagentSlot(slot)
            end)
        end
        for _, method in ipairs({ "Update", "SetModifyingRequired" }) do
            if type(button[method]) == "function" then
                hooksecurefunc(button, method, function() StyleOrderReagentSlot(slot) end)
            end
        end
        SkinBase.SetFrameData(button, "qOrderReagentHooked", true)
    end
    local quality = SkinBase.GetFrameData(button, "qOrderReagentQuality")
    if quality == nil and button.IconBorder and button.IconBorder:IsShown() and button.IconBorder.GetAtlas and ColorManager and ColorManager.GetAtlasDataForProfessionsItemQuality then
        local atlas = button.IconBorder:GetAtlas()
        for value = 0, 8 do
            local data = ColorManager.GetAtlasDataForProfessionsItemQuality(value)
            if atlas and data and data.atlas == atlas then quality = value; break end
        end
    end
    local sr, sg, sb, sa = SkinBase.GetWindowColors()
    if button.IconBorder and not button.IconBorder:IsShown() then quality = nil end
    local data = quality and ColorManager and ColorManager.GetColorDataForItemQuality(quality)
    local color = data and data.color
    if color and color.GetRGBA then sr, sg, sb, sa = color:GetRGBA() end
    SkinBase.RoundIconTexture(button, button.Icon)
    local border = SkinBase.SkinIcon(button.Icon, { parent = button })
    if border then
        SkinBase.SetFrameData(border, "chromeRadius", 4)
        SkinBase.SetBackdropColors(border, { sr, sg, sb, sa }, nil)
    end
    SkinBase.ClampTextureHidden(button.IconBorder, true)
    SkinBase.ClampTextureHidden(button.SlotBackground, true)
    SkinBase.ClampTextureHidden(button.CropFrame, true)
    local normal = button.GetNormalTexture and button:GetNormalTexture()
    local pushed = button.GetPushedTexture and button:GetPushedTexture()
    if normal then normal:SetAlpha(button.showLargeAddIcon and 1 or 0) end
    if pushed then pushed:SetAlpha(button.showLargeAddIcon and 1 or 0) end
    local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
    if highlight and not button.showLargeAddIcon then
        highlight:SetTexture("Interface\\Buttons\\WHITE8x8")
        highlight:ClearAllPoints()
        highlight:SetAllPoints(button.Icon)
        highlight:SetVertexColor(sr, sg, sb, 0.15)
        SkinBase.RoundIconTexture(button, highlight)
    end
    SkinBase.SkinFontString(slot.Name, { fontOnly = true })
    SkinBase.LockFontObject(slot.Name, { fontOnly = true })
    SkinBase.SkinFontString(button.Count, { fontOnly = true })
    SkinBase.LockFontObject(button.Count, { fontOnly = true })
    if slot.Checkbox then
        SkinBase.SkinCheckBox(slot.Checkbox)
        SkinBase.RefreshWidget(slot.Checkbox)
    end
end

local function StyleOrderQualityDialog(form)
    if not IsEnabled() or not form or (form.IsForbidden and form:IsForbidden()) then return end
    local dialog = form.QualityDialog
    if not dialog or (dialog.IsForbidden and dialog:IsForbidden()) then return end
    SkinBase.StripTextures(dialog)
    SkinBase.KillNineSlice(dialog.NineSlice, true)
    local sr, sg, sb, sa, br, bg, bb, ba = SkinBase.GetWindowColors()
    SkinBase.CreateBackdrop(dialog, sr, sg, sb, sa, br, bg, bb, ba, 8)
    local title = dialog.TitleText or (dialog.TitleContainer and dialog.TitleContainer.TitleText)
    SkinBase.SkinFontString(title, { fontOnly = true })
    SkinBase.LockFontObject(title, { fontOnly = true })
    SkinBase.SkinCloseButton(dialog.ClosePanelButton)
    for _, key in ipairs({ "AcceptButton", "CancelButton" }) do
        SkinBase.SkinButton(dialog[key], { font = true })
        SkinBase.RefreshWidget(dialog[key])
    end
    for index = 1, 3 do
        local container = dialog["Container" .. index]
        StyleOrderReagentSlot(container)
        local input = container and container.EditBox
        if input and not (input.IsForbidden and input:IsForbidden()) then
            SkinBase.SkinEditBox(input, { font = false })
            SkinBase.SkinFontString(input, { fontOnly = true })
            SkinBase.LockFontObject(input, { fontOnly = true })
            SkinBase.RefreshWidget(input)
            SkinBase.SkinNextPrevButton(input.DecrementButton, "prev")
            SkinBase.SkinNextPrevButton(input.IncrementButton, "next")
            SkinBase.RefreshWidget(input.DecrementButton)
            SkinBase.RefreshWidget(input.IncrementButton)
        end
    end
    if not SkinBase.GetFrameData(dialog, "qOrderQualityDialogHooked") then
        if type(dialog.Setup) == "function" then
            hooksecurefunc(dialog, "Setup", function() StyleOrderQualityDialog(form) end)
        end
        dialog:HookScript("OnShow", function() StyleOrderQualityDialog(form) end)
        SkinBase.SetFrameData(dialog, "qOrderQualityDialogHooked", true)
    end
end

local function StyleOrderReagentSlots(form)
    if not IsEnabled() or not form or (form.IsForbidden and form:IsForbidden()) then return end
    local pool = form.reagentSlotPool
    if pool and type(pool.EnumerateActive) == "function" then
        for slot in pool:EnumerateActive() do StyleOrderReagentSlot(slot) end
    end
    if not SkinBase.GetFrameData(form, "qOrderReagentSlotsHooked") then
        if type(form.UpdateReagentSlots) == "function" then hooksecurefunc(form, "UpdateReagentSlots", StyleOrderReagentSlots) end
        SkinBase.SetFrameData(form, "qOrderReagentSlotsHooked", true)
    end
end

local function StyleOrderUtilityButtons(form)
    if not IsEnabled() or not form or (form.IsForbidden and form:IsForbidden()) then return end
    local payment = form.PaymentContainer
    local listings = payment and not (payment.IsForbidden and payment:IsForbidden()) and payment.ViewListingsButton
    if listings and not (listings.IsForbidden and listings:IsForbidden()) then
        local textures = {}
        for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
            local texture = listings[getter] and listings[getter](listings)
            if texture then textures[texture] = texture:GetAlpha() end
        end
        SkinBase.SkinButton(listings, { font = false, belowChildren = true })
        for texture, alpha in pairs(textures) do texture:SetAlpha(alpha) end
        SkinBase.RefreshWidget(listings)
    end
    local recipient = form.OrderRecipientDisplay
    local social = recipient and not (recipient.IsForbidden and recipient:IsForbidden()) and recipient.SocialDropdown
    if social and not (social.IsForbidden and social:IsForbidden()) then
        local icon = social.icon
        local alpha = icon and icon:GetAlpha()
        SkinBase.SkinButton(social, { strip = true, font = false, belowChildren = true })
        if icon and alpha then icon:SetAlpha(alpha) end
        SkinBase.KillNineSlice(social.NineSlice, true)
        SkinBase.RefreshWidget(social)
    end
end

local function StyleOrderFormHeader(form)
    if not IsEnabled() or not form or (form.IsForbidden and form:IsForbidden()) then return end
    SkinBase.ClampTextureHidden(form.RecipeHeader, true)
    for _, key in ipairs({ "RecipeName", "RecraftRecipeName", "ProfessionText", "OrderStateText" }) do
        SkinBase.SkinFontString(form[key], { fontOnly = true })
        SkinBase.LockFontObject(form[key], { fontOnly = true })
    end
    local recipient = form.OrderRecipientDisplay
    if recipient and not (recipient.IsForbidden and recipient:IsForbidden()) then
        for _, key in ipairs({ "PostedTo", "Crafter", "CrafterValue" }) do
            SkinBase.SkinFontString(recipient[key], { fontOnly = true })
            SkinBase.LockFontObject(recipient[key], { fontOnly = true })
        end
    end
end

local function StyleOrderTracking(form)
    if not IsEnabled() or not form or (form.IsForbidden and form:IsForbidden()) then return end
    local tracking = form.TrackRecipeCheckbox
    if not tracking or (tracking.IsForbidden and tracking:IsForbidden()) then return end
    SkinBase.SkinFontString(tracking.Text, { fontOnly = true })
    SkinBase.LockFontObject(tracking.Text, { fontOnly = true })
    local checkbox = tracking.Checkbox
    if not checkbox or (checkbox.IsForbidden and checkbox:IsForbidden()) then return end
    SkinBase.SkinCheckBox(checkbox)
    local backdrop = SkinBase.GetBackdrop(checkbox)
    if backdrop then
        backdrop:ClearAllPoints()
        backdrop:SetPoint("TOPLEFT", checkbox, "TOPLEFT", 5, -5)
        backdrop:SetPoint("BOTTOMRIGHT", checkbox, "BOTTOMRIGHT", -5, 5)
        SkinBase.ApplyChromeBackdrop(backdrop, { radius = 3, withBackground = true })
    end
    SkinBase.RefreshWidget(checkbox)
end

local function StyleOrderListingsTitle(form)
    if not IsEnabled() or not form or (form.IsForbidden and form:IsForbidden()) then return end
    local listings = form.CurrentListings
    if not listings or (listings.IsForbidden and listings:IsForbidden()) then return end
    local container = listings.TitleContainer
    if not container or (container.IsForbidden and container:IsForbidden()) then return end
    SkinBase.SkinFontString(container.TitleText, { fontOnly = true })
    SkinBase.LockFontObject(container.TitleText, { fontOnly = true })
end

local function SkinForm(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not frame then return end

    local form = frame.Form
    if not form then return end
    StylePaymentControls(form)
    StyleOrderAllocation(form)
    StyleOrderOutput(form)
    StyleOrderReagentLabels(form)
    StyleOrderQualityDialog(form)
    StyleOrderReagentSlots(form)
    StyleOrderUtilityButtons(form)
    StyleOrderFormHeader(form)
    StyleOrderTracking(form)
    StyleOrderListingsTitle(form)

    if form.LeftPanelBackground then
        if form.LeftPanelBackground.NineSlice then form.LeftPanelBackground.NineSlice:Hide() end
        if form.LeftPanelBackground.Background then form.LeftPanelBackground.Background:SetAlpha(0) end
        local dr, dg, db, da = SkinBase.GetDepthColor("SUBPANEL")
        SkinBase.CreateBackdrop(form.LeftPanelBackground, sr, sg, sb, sa * 0.3, dr, dg, db, da, 6)
    end

    if form.RightPanelBackground then
        if form.RightPanelBackground.NineSlice then form.RightPanelBackground.NineSlice:Hide() end
        if form.RightPanelBackground.Background then form.RightPanelBackground.Background:SetAlpha(0) end
        local dr, dg, db, da = SkinBase.GetDepthColor("SUBPANEL")
        SkinBase.CreateBackdrop(form.RightPanelBackground, sr, sg, sb, sa * 0.3, dr, dg, db, da, 6)
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
            SkinBase.SkinDropdown(pc.DurationDropdown, { skinArrow = true })
        end
        StyleOrderNotes(form)
    end

    if form.MinimumQuality and form.MinimumQuality.Dropdown then
        SkinBase.SkinDropdown(form.MinimumQuality.Dropdown, { skinArrow = true })
    end
    if form.OrderRecipientDropdown then
        SkinBase.SkinDropdown(form.OrderRecipientDropdown, { skinArrow = true })
    end

    if form.OrderRecipientTarget then
        SkinBase.SkinEditBox(form.OrderRecipientTarget)
    end

    if form.CurrentListings then
        local listings = form.CurrentListings
        if listings.NineSlice then listings.NineSlice:Hide() end
        SkinBase.StripTextures(listings)
        SkinBase.CreateBackdrop(listings, sr, sg, sb, sa, bgr, bgg, bgb, bga, 6)

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

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetWindowColors()

    HideDecorations(frame)
    SkinBase.CreateBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga, 8)

    SkinBase.SkinCloseButton(frame.CloseButton or _G.ProfessionsCustomerOrdersFrameCloseButton)

    HookProfessionTableHeaderFonts()
    SkinTabs(frame)
    SkinBrowseOrders(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    SkinMyOrders(frame)
    SkinForm(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    RefreshOrderTableHeaders(frame)

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

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetWindowColors()

    RefreshOrderTableHeaders(frame)

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
        StylePaymentControls(form)
        StyleOrderAllocation(form)
        StyleOrderOutput(form)
        StyleOrderReagentLabels(form)
        StyleOrderQualityDialog(form)
        StyleOrderReagentSlots(form)
        StyleOrderUtilityButtons(form)
        StyleOrderFormHeader(form)
        StyleOrderTracking(form)
        StyleOrderListingsTitle(form)
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
            StyleOrderNotes(form)
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
