local addonName, ns = ...

if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
local SkinBase = ns.SkinBase
local GetCore = ns.Helpers.GetCore

local function IsSettingEnabled(key)
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings[key]
end

local RefreshBackdropColors = SkinBase.RefreshFrameBackdropColors
local SkinInteractionItem, SkinIconSelectorPopup

local function SkinInteractionSurface(frame)
    if not frame then return end
    SkinBase.StripTextures(frame)
    SkinBase.KillNineSlice(frame.NineSlice, true)
    local sr, sg, sb, sa = SkinBase.GetWindowColors()
    local r, g, b, a = SkinBase.GetDepthColor("SUBPANEL")
    SkinBase.CreateBackdrop(frame, sr, sg, sb, sa * 0.5, r, g, b, a, 5)
end

local function SkinBankItem(button)
    if not button or not IsSettingEnabled("skinBank") then return end
    SkinBase.ClampTextureHidden(button.Background, true)
    SkinInteractionItem(button)
    if not SkinBase.GetFrameData(button, "qBankItemHooked") then
        for _, method in ipairs({ "Refresh", "UpdateBackgroundForBankType" }) do
            if type(button[method]) == "function" then
                hooksecurefunc(button, method, SkinBankItem)
            end
        end
        SkinBase.SetFrameData(button, "qBankItemHooked", true)
    end
end

local function RefreshBankTab(button)
    if not button or not IsSettingEnabled("skinBank") then return end
    local r, g, b, a = SkinBase.GetWindowColors()
    if button:IsEnabled() and ((button.SelectedTexture and button.SelectedTexture:IsShown())
        or SkinBase.GetFrameData(button, "qBankTabHover")) then
        r, g, b, a = SkinBase.GetSkinColors()
    end
    SkinBase.SetBackdropColors(SkinBase.GetBackdrop(button), { r, g, b, a }, nil)
end

local function SkinBankTab(button)
    if not button or not IsSettingEnabled("skinBank") then return end
    SkinBase.ClampTextureHidden(button.Border, true)
    SkinBase.ClampTextureHidden(button.Background, true)
    local sr, sg, sb, sa, r, g, b, a = SkinBase.GetWindowColors()
    SkinBase.CreateBackdrop(button, sr, sg, sb, sa, r, g, b, a, 4)
    SkinBase.GetBackdrop(button):SetFrameLevel(math.max(0, button:GetFrameLevel() - 1))
    SkinBase.RoundIconTexture(button, button.Icon)
    SkinBase.RoundIconTexture(button, button.SearchOverlay)
    local ar, ag, ab = SkinBase.GetSkinColors()
    local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
    for _, texture in ipairs({ button.SelectedTexture, highlight }) do
        texture:SetTexture("Interface\\Buttons\\WHITE8x8")
        texture:SetVertexColor(ar, ag, ab, 0.15)
        SkinBase.RoundIconTexture(button, texture)
    end
    if not SkinBase.GetFrameData(button, "qBankTabHooked") then
        if type(button.RefreshVisuals) == "function" then
            hooksecurefunc(button, "RefreshVisuals", SkinBankTab)
        end
        button:HookScript("OnEnter", function(self)
            SkinBase.SetFrameData(self, "qBankTabHover", true)
            RefreshBankTab(self)
        end)
        local function clearHover(self)
            SkinBase.SetFrameData(self, "qBankTabHover", false)
            RefreshBankTab(self)
        end
        button:HookScript("OnLeave", clearHover)
        button:HookScript("OnHide", clearHover)
        SkinBase.SetFrameData(button, "qBankTabHooked", true)
    end
    RefreshBankTab(button)
end

local function SkinBankSettings(menu)
    if not menu or not IsSettingEnabled("skinBank") then return end
    SkinIconSelectorPopup(menu, "skinBank")
    local deposit = menu.DepositSettingsMenu
    if deposit then
        SkinBase.StripTextures(deposit)
        SkinBase.SkinDropdown(deposit.ExpansionFilterDropdown, { skinArrow = true })
        SkinBase.RefreshWidget(deposit.ExpansionFilterDropdown)
        for _, checkbox in ipairs(deposit.DepositSettingsCheckboxes or {}) do
            SkinBase.SkinCheckBox(checkbox)
            SkinBase.RefreshWidget(checkbox)
            SkinBase.LockFontObject(checkbox.Text, { fontOnly = true })
        end
        SkinBase.SkinFrameText(deposit, { recurse = true, chrome = true })
    end
    if not SkinBase.GetFrameData(menu, "qBankSettingsHooked") then
        menu:HookScript("OnShow", SkinBankSettings)
        if type(menu.Update) == "function" then
            hooksecurefunc(menu, "Update", SkinBankSettings)
        end
        SkinBase.SetFrameData(menu, "qBankSettingsHooked", true)
    end
end

local function SkinBankMoney(money)
    if not money or not IsSettingEnabled("skinBank") then return end
    SkinInteractionSurface(money.Border)
    if money.Border then
        SkinBase.GetBackdrop(money.Border):SetFrameLevel(math.max(0, money.Border:GetFrameLevel() - 1))
    end
    SkinBase.SkinFrameText(money.MoneyDisplay, { recurse = true })
    for _, button in ipairs({ money.WithdrawButton, money.DepositButton }) do
        SkinBase.SkinButton(button, { strip = true, font = true })
        SkinBase.RefreshWidget(button)
    end
    if not SkinBase.GetFrameData(money, "qBankMoneyHooked") then
        if type(money.Refresh) == "function" then hooksecurefunc(money, "Refresh", SkinBankMoney) end
        SkinBase.SetFrameData(money, "qBankMoneyHooked", true)
    end
end

local function SkinBankSort(button)
    if not button or not IsSettingEnabled("skinBank") then return end
    local sr, sg, sb, sa, r, g, b, a = SkinBase.GetWindowColors()
    SkinBase.CreateBackdrop(button, sr, sg, sb, sa, r, g, b, a, 4)
    SkinBase.GetBackdrop(button):SetFrameLevel(math.max(0, button:GetFrameLevel() - 1))
    SkinBase.RoundIconTexture(button, button:GetNormalTexture())
    SkinBase.RoundIconTexture(button, button:GetPushedTexture())
    local highlight = button:GetHighlightTexture()
    if highlight then
        highlight:SetTexture("Interface\\Buttons\\WHITE8x8")
        local ar, ag, ab = SkinBase.GetSkinColors()
        highlight:SetVertexColor(ar, ag, ab, 0.15)
        SkinBase.RoundIconTexture(button, highlight)
    end
    if not SkinBase.GetFrameData(button, "qBankSortHooked") then
        button:HookScript("OnEnter", function(self)
            SkinBase.SetFrameData(self, "qBankTabHover", true)
            RefreshBankTab(self)
        end)
        local function clearHover(self)
            SkinBase.SetFrameData(self, "qBankTabHover", false)
            RefreshBankTab(self)
        end
        button:HookScript("OnLeave", clearHover)
        button:HookScript("OnHide", clearHover)
        SkinBase.SetFrameData(button, "qBankSortHooked", true)
    end
    RefreshBankTab(button)
end

local function SkinBankConfirmation(frame)
    if not frame or not IsSettingEnabled("skinBank") then return end
    if not SkinBase.IsSkinned(frame) then
        SkinBase.SkinWindow(frame, { noClose = true, noButtonFonts = true })
        frame:HookScript("OnShow", SkinBankConfirmation)
        SkinBase.MarkSkinned(frame)
    end
    RefreshBackdropColors(frame)
    SkinBase.KillNineSlice(frame.Border, true)
    SkinBase.SkinFontString(frame.Text)
    local checkbox = frame.HidePopupCheckbox
    if checkbox then
        SkinBase.SkinFontString(checkbox.Label)
        SkinBase.SkinCheckBox(checkbox.Checkbox)
        SkinBase.RefreshWidget(checkbox.Checkbox)
    end
    for _, button in ipairs({ frame.AcceptButton, frame.CancelButton }) do
        SkinBase.SkinButton(button, { strip = true, font = true })
        SkinBase.RefreshWidget(button)
    end
end

local function SkinBankContents(frame)
    if not frame or not IsSettingEnabled("skinBank") then return end
    SkinBase.SkinEditBox(frame.BankItemSearchBox or _G.BankItemSearchBox)
    if frame.TabSystem and frame.TabSystem.tabs then
        SkinBase.SkinTabGroup(frame.TabSystem.tabs, frame, { resizeToText = true, dockBottom = true })
    end
    local panel = frame.BankPanel
    if not panel then return end
    SkinBase.KillNineSlice(panel.NineSlice, true)
    SkinBase.StripTextures(panel.EdgeShadows)
    if panel.itemButtonPool then
        for button in panel.itemButtonPool:EnumerateActive() do SkinBankItem(button) end
    end
    if panel.bankTabPool then
        for button in panel.bankTabPool:EnumerateActive() do SkinBankTab(button) end
    end
    SkinBankTab(panel.PurchaseTab)
    if not SkinBase.GetFrameData(panel, "qBankItemsHooked") then
        for _, method in ipairs({ "GenerateItemSlotsForSelectedTab", "RefreshBankTabs" }) do
            if type(panel[method]) == "function" then
                hooksecurefunc(panel, method, function() SkinBankContents(frame) end)
            end
        end
        SkinBase.SetFrameData(panel, "qBankItemsHooked", true)
    end
    SkinBankMoney(panel.MoneyFrame)
    SkinBankSort(panel.AutoSortButton)
    SkinBankConfirmation(_G.BankCleanUpConfirmationPopup)
    local deposit = panel.AutoDepositFrame
    if deposit then
        SkinBase.SkinButton(deposit.DepositButton, { strip = true, font = true })
        SkinBase.SkinCheckBox(deposit.IncludeReagentsCheckbox)
        SkinBase.RefreshWidget(deposit.DepositButton)
        local checkbox = deposit.IncludeReagentsCheckbox
        if checkbox then
            SkinBase.SkinFontString(checkbox.Text)
            SkinBase.LockFontObject(checkbox.Text, { fontOnly = true })
        end
    end
    SkinBankSettings(panel.TabSettingsMenu)
    for _, prompt in pairs(panel.Prompts or {}) do
        SkinInteractionSurface(prompt)
        SkinBase.SkinFrameText(prompt, { recurse = true })
        SkinBase.SkinFontString(prompt.Title)
        SkinBase.SkinFontString(prompt.PromptText)
        local cost = prompt.TabCostFrame
        SkinBase.SkinFontString(cost and cost.TabCost)
        SkinBase.SkinButton(cost and cost.PurchaseButton, { strip = true, font = true })
        SkinBase.RefreshWidget(cost and cost.PurchaseButton)
    end
end

local function SkinBank()
    if not IsSettingEnabled("skinBank") then return end
    local frame = _G.BankFrame
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinWindow(frame, { depth = 6 })
    SkinBankContents(frame)
    frame:HookScript("OnShow", SkinBankContents)
    SkinBase.MarkSkinned(frame)
end

local function RefreshBank()
    RefreshBackdropColors(_G.BankFrame)
    SkinBankContents(_G.BankFrame)
end
_G.QUI_RefreshBankColors = RefreshBank
if ns.Registry then
    ns.Registry:Register("skinBank", {
        refresh = RefreshBank,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

local function SkinMerchantIcon(button)
    if not button then return end
    SkinBase.ClampTextureHidden(button.GetNormalTexture and button:GetNormalTexture(), true)
    if button.GetRegions then
        for _, region in ipairs({ button:GetRegions() }) do
            if region.GetObjectType and region:GetObjectType() == "Texture"
                and region.GetDrawLayer and region:GetDrawLayer() == "BACKGROUND" then
                SkinBase.ClampTextureHidden(region, true)
            end
        end
    end
    local name = button.GetName and button:GetName()
    local icon = button.Icon or button.icon or (name and _G[name .. "IconTexture"])
    local border = SkinBase.SkinIcon(icon, { parent = button })
    SkinBase.ApplyChromeBackdrop(border, { radius = 4, withBackground = false })
    SkinBase.RoundIconTexture(button, icon)
    SkinBase.HandleIconBorder(button.IconBorder, border)
end

local function SkinMerchantContents(frame)
    if not frame or not IsSettingEnabled("skinMerchant") then return end
    local title = frame.GetTitleText and frame:GetTitleText() or frame.TitleText
    SkinBase.SkinFontString(title, { color = { 1, 1, 1, 1 } })
    SkinBase.SkinFontString(_G.MerchantPageText, { color = { 0.9, 0.9, 0.9, 1 } })
    SkinBase.ClampTextureHidden(_G.MerchantFrameBottomLeftBorder, true)
    SkinBase.ClampTextureHidden(_G.BuybackBG, true)
    for _, name in ipairs({ "MerchantMoneyBg", "MerchantExtraCurrencyBg" }) do
        SkinBase.StripTextures(_G[name])
        SkinBase.KillNineSlice(_G[name] and _G[name].NineSlice, true)
    end
    for _, name in ipairs({ "MerchantMoneyInset", "MerchantExtraCurrencyInset" }) do
        SkinInteractionSurface(_G[name])
    end
    for i = 1, math.max(12, _G.MERCHANT_ITEMS_PER_PAGE or 12) do
        local row = _G["MerchantItem" .. i]
        if row then
            SkinBase.StripTextures(row)
            SkinBase.CreateBackdrop(row, nil, nil, nil, nil, nil, nil, nil, nil, 4)
            SkinBase.SkinFontString(row.Name or _G["MerchantItem" .. i .. "Name"], { fontOnly = true })
            SkinMerchantIcon(row.ItemButton or _G["MerchantItem" .. i .. "ItemButton"])
        end
    end
    local buyback = _G.MerchantBuyBackItem
    if buyback then
        SkinBase.StripTextures(buyback)
        SkinBase.CreateBackdrop(buyback, nil, nil, nil, nil, nil, nil, nil, nil, 4)
        SkinMerchantIcon(buyback.ItemButton or _G.MerchantBuyBackItemItemButton)
    end
    for _, name in ipairs({ "MerchantRepairAllButton", "MerchantRepairItemButton",
        "MerchantGuildBankRepairButton", "MerchantSellAllJunkButton" }) do
        SkinMerchantIcon(_G[name])
    end
    SkinBase.SkinTabGroup(SkinBase.CollectNumberedTabs("MerchantFrame", 2), frame,
        { resizeToText = true, dockBottom = true })
end

local function SkinMerchant()
    if not IsSettingEnabled("skinMerchant") then return end
    local frame = _G.MerchantFrame
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinWindow(frame, { tabs = SkinBase.CollectNumberedTabs("MerchantFrame", 2) })
    SkinBase.SkinDropdown(frame.FilterDropdown, { skinArrow = true })
    if _G.MerchantPrevPageButton then SkinBase.SkinNextPrevButton(_G.MerchantPrevPageButton, "prev") end
    if _G.MerchantNextPageButton then SkinBase.SkinNextPrevButton(_G.MerchantNextPageButton, "next") end
    SkinMerchantContents(frame)
    frame:HookScript("OnShow", SkinMerchantContents)
    if _G.MerchantFrame_Update and not SkinBase.GetFrameData(frame, "qMerchantContentsHooked") then
        hooksecurefunc("MerchantFrame_Update", function() SkinMerchantContents(frame) end)
        SkinBase.SetFrameData(frame, "qMerchantContentsHooked", true)
    end
    SkinBase.MarkSkinned(frame)
end

local function RefreshMerchant()
    RefreshBackdropColors(_G.MerchantFrame)
    SkinMerchantContents(_G.MerchantFrame)
end
_G.QUI_RefreshMerchantColors = RefreshMerchant
if ns.Registry then
    ns.Registry:Register("skinMerchant", {
        refresh = RefreshMerchant,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

local GOSSIP_CODE_REMAP = { ["000000"] = "ffffff", ["414141"] = "7b8489" }

local function GossipReplaceCode(code)
    return "|cFF" .. (GOSSIP_CODE_REMAP[string.lower(code)] or code)
end

local function GossipForceTextColor(fontString, r, g, b)
    if r ~= 1 or g ~= 1 or b ~= 1 then
        fontString:SetTextColor(1, 1, 1)
    end
end

local function GossipStripText(button, text)
    if not text or text == "" then return end
    local startText = text
    local iconText, iconCount = string.gsub(text, ":32:32:0:0", ":32:32:0:0:64:64:5:59:5:59")
    if iconCount > 0 then text = iconText end
    local colorText, colorCount = string.gsub(text, "|c[fF][fF](%x%x%x%x%x%x)", GossipReplaceCode)
    if colorCount > 0 then text = colorText end
    if startText ~= text then button:SetFormattedText("%s", text, true) end
end

local function GossipStripFormatted(button, textFormat, text, skip)
    if skip or not text or text == "" then return end
    local colorText, colorCount = string.gsub(textFormat, "|c[fF][fF](%x%x%x%x%x%x)", GossipReplaceCode)
    if colorCount > 0 then button:SetFormattedText(colorText, text, true) end
end

local function GossipColorRow(row)
    if not row then return end
    local greetingText = row.GreetingText
    if greetingText and not SkinBase.GetFrameData(greetingText, "qGossipColored") then
        greetingText:SetTextColor(1, 1, 1)
        hooksecurefunc(greetingText, "SetTextColor", GossipForceTextColor)
        SkinBase.SetFrameData(greetingText, "qGossipColored", true)
    end
    local fs = row.GetFontString and row:GetFontString()
    if fs and row.GetObjectType and row:GetObjectType() == "Button" then
        SkinBase.SkinButton(row, { strip = false, font = false, radius = 4, belowChildren = true })
        SkinBase.RefreshWidget(row)
    end
    if fs and not SkinBase.GetFrameData(fs, "qGossipColored") then
        fs:SetTextColor(1, 1, 1)
        hooksecurefunc(fs, "SetTextColor", GossipForceTextColor)
        GossipStripText(row, row.GetText and row:GetText())
        hooksecurefunc(row, "SetText", GossipStripText)
        if row.SetFormattedText then
            hooksecurefunc(row, "SetFormattedText", GossipStripFormatted)
        end
        SkinBase.SetFrameData(fs, "qGossipColored", true)
    end
end

local function SkinFriendshipBar(bar)
    if not bar then return end
    for _, key in ipairs({ "BarBorder", "BarRingBackground", "BarCircle" }) do
        SkinBase.ClampTextureHidden(bar[key], true)
    end
    for _, region in ipairs({ bar:GetRegions() }) do
        if region:GetObjectType() == "Texture" and region:GetDrawLayer() == "BACKGROUND" then
            region:SetAlpha(0)
        end
    end
    ns.Helpers.ApplyBarStyle(bar, "Interface\\Buttons\\WHITE8x8")
    SkinBase.RoundBarTexture(bar, bar:GetStatusBarTexture())
    local sr, sg, sb, sa, r, g, b, a = SkinBase.GetWindowColors()
    SkinBase.CreateBackdrop(bar, sr, sg, sb, sa, r, g, b, a, 3)
    SkinBase.GetBackdrop(bar):SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
end

local function SkinGossipContents(frame)
    if not IsSettingEnabled("skinGossip") or not frame then return end
    SkinBase.ClampTextureHidden(frame.Background, true)
    local greeting = frame.GreetingPanel
    if greeting then
        SkinBase.StripTextures(greeting)
        SkinBase.SkinButton(greeting.GoodbyeButton, { strip = true, font = true })
        SkinBase.RefreshWidget(greeting.GoodbyeButton)
        SkinBase.SkinTrimScrollBar(greeting.ScrollBar)
        if greeting.ScrollBox and type(greeting.ScrollBox.ForEachFrame) == "function" then
            greeting.ScrollBox:ForEachFrame(GossipColorRow)
        end
    end
    SkinFriendshipBar(frame.FriendshipStatusBar)
end

local function SkinGossip()
    if not IsSettingEnabled("skinGossip") then return end
    local frame = _G.GossipFrame
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinWindow(frame)
    local greeting = frame.GreetingPanel
    if greeting then
        if greeting.ScrollBar then SkinBase.SkinTrimScrollBar(greeting.ScrollBar) end
        if greeting.ScrollBox and SkinBase.HookScrollBoxRowFonts then
            SkinBase.HookScrollBoxRowFonts(greeting.ScrollBox, 3)
            if SkinBase.HookScrollBoxAcquired then
                SkinBase.HookScrollBoxAcquired(greeting.ScrollBox, GossipColorRow, { sync = true })
            end
        end
    end
    SkinGossipContents(frame)
    frame:HookScript("OnShow", SkinGossipContents)
    if type(frame.HandleShow) == "function" then
        hooksecurefunc(frame, "HandleShow", SkinGossipContents)
    end
    local bar = frame.FriendshipStatusBar
    if bar and type(bar.Update) == "function" then
        hooksecurefunc(bar, "Update", function()
            if IsSettingEnabled("skinGossip") then SkinFriendshipBar(bar) end
        end)
    end
    SkinBase.MarkSkinned(frame)
end

local function RefreshGossip()
    local frame = _G.GossipFrame
    RefreshBackdropColors(frame)
    if SkinBase.IsSkinned(frame) then SkinGossipContents(frame) end
end
if ns.Registry then
    ns.Registry:Register("skinGossip", {
        refresh = RefreshGossip,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

local function IsQuestOwned(widget)
    local frame = _G.QuestFrame
    for _ = 1, 8 do
        if not widget then return false end
        if widget == frame then return true end
        widget = widget.GetParent and widget:GetParent()
    end
    return false
end

SkinInteractionItem = function(button, opts)
    if not button then return end
    SkinBase.SkinButton(button, { strip = false, font = false, radius = 4, belowChildren = true })
    SkinBase.RefreshWidget(button)
    SkinBase.SkinFontString(button.Name, { fontOnly = true })
    SkinBase.SkinFontString(button.Count, { fontOnly = true })
    local icon = button.Icon or button.icon
    local border = SkinBase.SkinIcon(icon, { parent = button, crop = opts and opts.crop })
    SkinBase.ApplyChromeBackdrop(border, { radius = 4, withBackground = false })
    SkinBase.RoundIconTexture(button, icon)
    local nativeBorder = button.IconBorder
    SkinBase.HandleIconBorder(nativeBorder, border)
    if nativeBorder and border then
        local function reset()
            local r, g, b, a = SkinBase.GetWindowColors()
            SkinBase.SetBackdropColors(border, { r, g, b, a }, nil)
        end
        if not SkinBase.GetFrameData(nativeBorder, "qQuestDefaultBorder") then
            hooksecurefunc(nativeBorder, "Hide", reset)
            hooksecurefunc(nativeBorder, "SetShown", function(_, shown) if not shown then reset() end end)
            SkinBase.SetFrameData(nativeBorder, "qQuestDefaultBorder", true)
        end
        if nativeBorder:IsShown() then
            local r, g, b, a = nativeBorder:GetVertexColor()
            SkinBase.SetBackdropColors(border, { r, g, b, a }, nil)
        else
            reset()
        end
    end
end

local function StyleQuestRewardName(button)
    local frame = _G.QuestFrame
    if not IsSettingEnabled("skinQuest") or not frame or not button or not IsQuestOwned(button)
        or (frame.IsForbidden and frame:IsForbidden())
        or (button.IsForbidden and button:IsForbidden()) then return end
    local nameFrame = button.NameFrame
    local backdrop = SkinBase.GetBackdrop(button)
    if not nameFrame or not backdrop then return end
    SkinBase.ClampTextureHidden(nameFrame, true)
    local r, g, b, a = SkinBase.GetWindowColors()
    if nameFrame:IsShown() then
        local nr, ng, nb, na = nameFrame:GetVertexColor()
        if nr and ng and nb and (nr ~= 1 or ng ~= 1 or nb ~= 1) then
            r, g, b, a = nr, ng, nb, na or 1
        end
    end
    SkinBase.SetBackdropColors(backdrop, { r, g, b, a }, nil)
    if not SkinBase.GetFrameData(nameFrame, "qQuestNameHooked") then
        for _, method in ipairs({ "SetVertexColor", "Show", "Hide", "SetShown" }) do
            hooksecurefunc(nameFrame, method, function() StyleQuestRewardName(button) end)
        end
        SkinBase.SetFrameData(nameFrame, "qQuestNameHooked", true)
    end
end

local function SkinQuestReward(button, opts)
    local frame = _G.QuestFrame
    if not IsSettingEnabled("skinQuest") or not frame or not button
        or (frame.IsForbidden and frame:IsForbidden())
        or (button.IsForbidden and button:IsForbidden()) then return end
    if IsQuestOwned(button) then
        SkinInteractionItem(button, opts)
        StyleQuestRewardName(button)
    end
end

local function SkinQuestSelection(button)
    local frame, highlight = _G.QuestFrame, _G.QuestInfoItemHighlight
    if not IsSettingEnabled("skinQuest") or not frame or not highlight or not IsQuestOwned(highlight)
        or (frame.IsForbidden and frame:IsForbidden())
        or (highlight.IsForbidden and highlight:IsForbidden()) then return end
    if button and button.type ~= "choice" then return end
    if not button then
        local _, relative = highlight:GetPoint(1)
        button = relative
    end
    if not button or button.type ~= "choice" or not IsQuestOwned(button)
        or (button.IsForbidden and button:IsForbidden()) then return end
    for _, region in ipairs({ highlight:GetRegions() }) do
        if region:IsObjectType("Texture") then SkinBase.ClampTextureHidden(region, true) end
    end
    local r, g, b = SkinBase.GetSkinColors()
    SkinBase.CreateBackdrop(highlight, r, g, b, 1, r, g, b, 0.12, 4)
    local backdrop = SkinBase.GetBackdrop(highlight)
    backdrop:ClearAllPoints()
    backdrop:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    backdrop:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
end

local function SkinQuestRewardPool(rewards, key)
    if not rewards or not IsQuestOwned(rewards) then return end
    local pool = rewards[key]
    if not pool or type(pool.EnumerateActive) ~= "function" then return end
    local function styleActive()
        if not IsSettingEnabled("skinQuest") then return end
        for button in pool:EnumerateActive() do
            if not (button.IsForbidden and button:IsForbidden()) then
                SkinQuestReward(button, key == "reputationRewardPool" and { crop = false } or nil)
                if key == "reputationRewardPool" and IsQuestOwned(button)
                    and not (_G.QuestFrame.IsForbidden and _G.QuestFrame:IsForbidden()) then
                    SkinBase.SkinFontString(button.RewardAmount, { fontOnly = true })
                    SkinBase.LockFontObject(button.RewardAmount, { fontOnly = true })
                end
                if key == "followerRewardPool" and IsQuestOwned(button)
                    and not (_G.QuestFrame.IsForbidden and _G.QuestFrame:IsForbidden()) then
                    SkinBase.ClampTextureHidden(button.BG, true)
                    for _, portraitKey in ipairs({ "PortraitFrame", "AdventuresFollowerPortraitFrame" }) do
                        local portrait = button[portraitKey]
                        if portrait and not (portrait.IsForbidden and portrait:IsForbidden()) then
                            SkinBase.SkinFrameText(portrait, { recurse = true })
                            SkinBase.LockFrameTextObjects(portrait, 2)
                        end
                    end
                end
                if key == "spellRewardPool" and IsQuestOwned(button)
                    and not (_G.QuestFrame.IsForbidden and _G.QuestFrame:IsForbidden()) then
                    for _, region in ipairs({ button:GetRegions() }) do
                        local name = region.GetName and region:GetName()
                        if region:GetObjectType() == "Texture" and name and name:match("SpellBorder$") then
                            SkinBase.ClampTextureHidden(region, true)
                        end
                    end
                end
            end
        end
    end
    styleActive()
    if type(pool.Acquire) == "function" and not SkinBase.GetFrameData(pool, "qQuestRewardPoolHooked") then
        hooksecurefunc(pool, "Acquire", styleActive)
        SkinBase.SetFrameData(pool, "qQuestRewardPoolHooked", true)
    end
end

local function StyleQuestSpellHeader(header)
    local frame = _G.QuestFrame
    if not IsSettingEnabled("skinQuest") or not frame or not header or not IsQuestOwned(header)
        or (frame.IsForbidden and frame:IsForbidden())
        or (header.IsForbidden and header:IsForbidden())
        or SkinBase.GetFrameData(header, "qQuestHeaderRefreshing") then return end
    SkinBase.SetFrameData(header, "qQuestHeaderRefreshing", true)
    SkinBase.SkinFontString(header, { fontOnly = true })
    header:SetVertexColor(0.92, 0.92, 0.92, 1)
    SkinBase.SetFrameData(header, "qQuestHeaderRefreshing", false)
    if not SkinBase.GetFrameData(header, "qQuestHeaderHooked") then
        hooksecurefunc(header, "SetVertexColor", StyleQuestSpellHeader)
        hooksecurefunc(header, "SetFontObject", StyleQuestSpellHeader)
        SkinBase.SetFrameData(header, "qQuestHeaderHooked", true)
    end
end

local function SkinQuestSpellHeaders(rewards)
    if not rewards or not IsQuestOwned(rewards) then return end
    local pool = rewards.spellHeaderPool
    if not pool or type(pool.EnumerateActive) ~= "function" then return end
    local function styleActive()
        for header in pool:EnumerateActive() do StyleQuestSpellHeader(header) end
    end
    styleActive()
    if type(pool.Acquire) == "function" and not SkinBase.GetFrameData(pool, "qQuestHeaderPoolHooked") then
        hooksecurefunc(pool, "Acquire", styleActive)
        SkinBase.SetFrameData(pool, "qQuestHeaderPoolHooked", true)
    end
end

local function SkinQuestTitleReward(title)
    local frame = _G.QuestFrame
    if not IsSettingEnabled("skinQuest") or not frame or not title or not IsQuestOwned(title)
        or (frame.IsForbidden and frame:IsForbidden())
        or (title.IsForbidden and title:IsForbidden()) then return end
    local icon, right = title.Icon, title.FrameRight
    if not icon or not right then return end
    for _, key in ipairs({ "FrameLeft", "FrameCenter", "FrameRight" }) do
        SkinBase.ClampTextureHidden(title[key], true)
    end
    local sr, sg, sb, sa, r, g, b, a = SkinBase.GetWindowColors()
    SkinBase.CreateBackdrop(title, sr, sg, sb, sa, r, g, b, a, 4)
    local backdrop = SkinBase.GetBackdrop(title)
    backdrop:ClearAllPoints()
    backdrop:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
    backdrop:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", 0, 0)
    backdrop:SetFrameLevel(math.max(0, title:GetFrameLevel() - 1))
    SkinBase.RoundIconTexture(title, icon)
    local border = SkinBase.SkinIcon(icon, { parent = title, crop = false, border = { sr, sg, sb, sa } })
    SkinBase.ApplyChromeBackdrop(border, { radius = 4, withBackground = false, borderColor = { sr, sg, sb, sa } })
    SkinBase.SkinFontString(title.Name, { fontOnly = true })
    SkinBase.LockFontObject(title.Name, { fontOnly = true })
end

local function SkinQuestBonusRewards(rewards)
    local frame = _G.QuestFrame
    if not IsSettingEnabled("skinQuest") or not frame or not rewards or not IsQuestOwned(rewards)
        or (frame.IsForbidden and frame:IsForbidden())
        or (rewards.IsForbidden and rewards:IsForbidden()) then return end
    for _, key in ipairs({ "HonorFrame", "ArtifactXPFrame", "WarModeBonusFrame", "SkillPointFrame" }) do
        local button = rewards[key]
        if button and not (button.IsForbidden and button:IsForbidden()) then
            SkinQuestReward(button, { crop = false })
            SkinBase.SkinFontString(button.ValueText, { fontOnly = true })
            SkinBase.LockFontObject(button.ValueText, { fontOnly = true })
        end
    end
    for _, key in ipairs({ "XPFrame", "MoneyFrame" }) do
        local reward = rewards[key]
        if reward and not (reward.IsForbidden and reward:IsForbidden()) then
            SkinBase.SkinFrameText(reward, { recurse = true })
            SkinBase.LockFrameTextObjects(reward, 3)
            if key == "XPFrame" then
                SkinBase.SkinFontString(reward.ReceiveText, { color = { 0.92, 0.92, 0.92, 1 } })
            end
        end
    end
end

local function SkinQuestPortrait()
    local scene = _G.QuestModelScene
    if not scene or not IsQuestOwned(scene) then return end
    SkinBase.SkinWindow(scene, { noClose = true, noButtonFonts = true })
    SkinBase.GetBackdrop(scene):SetFrameLevel(math.max(0, scene:GetFrameLevel() - 1))
    for _, key in ipairs({ "ModelBackground", "ModelNameDivider", "ModelNameBackground", "ShadowOverlay" }) do
        SkinBase.ClampTextureHidden(scene[key], true)
    end
    local text = scene.ModelTextFrame
    if text then
        SkinBase.ClampTextureHidden(text.TextBackground, true)
        local sr, sg, sb, sa, r, g, b, a = SkinBase.GetWindowColors()
        SkinBase.CreateBackdrop(text, sr, sg, sb, sa, r, g, b, a, 5)
        SkinBase.GetBackdrop(text):SetFrameLevel(math.max(0, text:GetFrameLevel() - 1))
    end
    if scene.ModelNameDivider then
        local caption = SkinBase.GetFrameData(scene, "qQuestCaption")
        if not caption then
            caption = CreateFrame("Frame", nil, scene)
            caption:SetAllPoints(scene.ModelNameDivider)
            caption:SetFrameLevel(math.max(0, scene:GetFrameLevel() - 1))
            caption:EnableMouse(false)
            SkinBase.SetFrameData(scene, "qQuestCaption", caption)
        end
        local sr, sg, sb, sa, r, g, b, a = SkinBase.GetWindowColors()
        SkinBase.CreateBackdrop(caption, sr, sg, sb, sa, r, g, b, a, 4)
    end
    SkinBase.SkinFontString(_G.QuestNPCModelNameText)
    SkinBase.SkinFontString(_G.QuestNPCModelText)
end

local function SkinQuestRequiredMoney()
    local frame, money = _G.QuestFrame, _G.QuestProgressRequiredMoneyFrame
    if not IsSettingEnabled("skinQuest") or not frame or not money or not IsQuestOwned(money)
        or (money.IsForbidden and money:IsForbidden())
        or (frame.IsForbidden and frame:IsForbidden()) then return end
    SkinBase.SkinFrameText(money, { recurse = true })
    for _, key in ipairs({ "GoldButton", "SilverButton", "CopperButton" }) do
        local button = money[key]
        if button and not (button.IsForbidden and button:IsForbidden())
            and type(button.SetNormalFontObject) == "function"
            and not SkinBase.GetFrameData(button, "qQuestMoneyFontHooked") then
            hooksecurefunc(button, "SetNormalFontObject", SkinQuestRequiredMoney)
            SkinBase.SetFrameData(button, "qQuestMoneyFontHooked", true)
        end
    end
end

local function SkinQuestContents()
    if not IsSettingEnabled("skinQuest") then return end
    for _, name in ipairs({ "QuestFrameRewardPanel", "QuestFrameProgressPanel",
        "QuestFrameDetailPanel", "QuestFrameGreetingPanel" }) do
        local panel = _G[name]
        if panel then
            for _, key in ipairs({ "Bg", "MaterialTopLeft", "MaterialTopRight",
                "MaterialBotLeft", "MaterialBotRight", "SealMaterialBG" }) do
                SkinBase.ClampTextureHidden(panel[key], true)
            end
        end
    end
    for _, name in ipairs({ "QuestRewardScrollFrame", "QuestProgressScrollFrame",
        "QuestDetailScrollFrame", "QuestGreetingScrollFrame", "QuestNPCModelTextScrollFrame" }) do
        local scroll = _G[name]
        if scroll then SkinBase.SkinTrimScrollBar(scroll.ScrollBar or _G[name .. "ScrollBar"]) end
    end
    for _, name in ipairs({ "GreetingText", "CurrentQuestsText", "AvailableQuestsText",
        "QuestProgressTitleText", "QuestProgressText", "QuestProgressRequiredItemsText" }) do
        SkinBase.SkinFontString(_G[name])
    end
    local frame = _G.QuestFrame
    if frame then SkinFriendshipBar(frame.FriendshipStatusBar) end
    local greeting = _G.QuestFrameGreetingPanel
    local pool = greeting and greeting.titleButtonPool
    if pool and type(pool.EnumerateActive) == "function" then
        for row in pool:EnumerateActive() do GossipColorRow(row) end
    end
    for index = 1, 6 do SkinQuestReward(_G["QuestProgressItem" .. index]) end
    SkinQuestRequiredMoney()
    if type(_G.GetQuestMoneyToGet) == "function" and type(_G.GetMoney) == "function" then
        local insufficient = _G.GetQuestMoneyToGet() > _G.GetMoney()
        SkinBase.SkinFontString(_G.QuestProgressRequiredMoneyText,
            { color = insufficient and { 1, 0.2, 0.2, 1 } or { 1, 1, 1, 1 } })
    end
    SkinQuestPortrait()
    local info = _G.QuestInfoFrame
    if info and IsQuestOwned(_G.QuestInfoTitleHeader) then
        for _, name in ipairs({ "QuestInfoTitleHeader", "QuestInfoDescriptionHeader", "QuestInfoObjectivesHeader",
            "QuestInfoDescriptionText", "QuestInfoObjectivesText", "QuestInfoGroupSize", "QuestInfoRewardText" }) do
            SkinBase.SkinFontString(_G[name])
        end
        for _, name in ipairs({ "QuestRewardScrollChildFrame", "QuestProgressScrollChildFrame",
            "QuestDetailScrollChildFrame", "QuestGreetingScrollChildFrame" }) do
            SkinBase.SkinFrameText(_G[name], { recurse = true })
        end
        local rewards = info.rewardsFrame
        if rewards then
            for _, key in ipairs({ "Header", "ItemChooseText", "ItemReceiveText", "PlayerTitleText",
                "QuestSessionBonusReward" }) do
                SkinBase.SkinFontString(rewards[key])
            end
            for _, button in pairs(rewards.RewardButtons or {}) do SkinQuestReward(button) end
            SkinQuestRewardPool(rewards, "spellRewardPool")
            SkinQuestRewardPool(rewards, "reputationRewardPool")
            SkinQuestRewardPool(rewards, "followerRewardPool")
            SkinQuestSpellHeaders(rewards)
            SkinQuestTitleReward(rewards.TitleFrame)
            SkinQuestBonusRewards(rewards)
            SkinQuestSelection()
        end
    end
end

local function SkinQuest()
    if not IsSettingEnabled("skinQuest") then return end
    local frame = _G.QuestFrame
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinWindow(frame, { depth = 5, noButtonFonts = true })
    for _, name in ipairs({ "QuestFrameCompleteQuestButton", "QuestFrameGoodbyeButton", "QuestFrameCompleteButton",
        "QuestFrameDeclineButton", "QuestFrameAcceptButton", "QuestFrameGreetingGoodbyeButton" }) do
        SkinBase.SkinButton(_G[name], { strip = true, font = true })
    end
    SkinQuestContents()
    frame:HookScript("OnShow", SkinQuestContents)
    for _, name in ipairs({ "QuestFrameRewardPanel", "QuestFrameProgressPanel",
        "QuestFrameDetailPanel", "QuestFrameGreetingPanel" }) do
        local panel = _G[name]
        if panel then panel:HookScript("OnShow", SkinQuestContents) end
    end
    for _, name in ipairs({ "QuestFrame_SetMaterial", "QuestInfo_Display", "QuestFrameProgressPanel_OnShow",
        "QuestFrameGreetingPanel_OnShow", "QuestFrameDetailPanel_OnShow", "QuestFrameRewardPanel_OnShow",
        "QuestFrameProgressItems_Update", "QuestFrame_ShowQuestPortrait", "QuestFrame_UpdatePortraitText" }) do
        if type(_G[name]) == "function" then hooksecurefunc(name, SkinQuestContents) end
    end
    if type(_G.QuestInfoItem_OnClick) == "function" then
        hooksecurefunc("QuestInfoItem_OnClick", SkinQuestSelection)
    end
    if type(_G.QuestInfo_GetRewardButton) == "function" then
        hooksecurefunc("QuestInfo_GetRewardButton", function(rewards, index)
            SkinQuestReward(rewards.RewardButtons and rewards.RewardButtons[index])
        end)
    end
    local bar = frame.FriendshipStatusBar
    if bar and type(bar.Update) == "function" then hooksecurefunc(bar, "Update", SkinQuestContents) end
    SkinBase.MarkSkinned(frame)
end

local function RefreshQuest()
    RefreshBackdropColors(_G.QuestFrame)
    if SkinBase.IsSkinned(_G.QuestFrame) then SkinQuestContents() end
end
if ns.Registry then
    ns.Registry:Register("skinQuest", {
        refresh = RefreshQuest,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

local function RefreshGuildBankTab(button)
    local backdrop = SkinBase.GetBackdrop(button)
    if not backdrop then return end
    local r, g, b, a = SkinBase.GetWindowColors()
    if button:GetChecked() then r, g, b, a = SkinBase.GetSkinColors() end
    SkinBase.SetBackdropColors(backdrop, { r, g, b, a }, nil)
end

local function RefreshGuildIcon(button)
    local backdrop = SkinBase.GetBackdrop(button)
    if not backdrop then return end
    local r, g, b, a = SkinBase.GetWindowColors()
    if SkinBase.GetFrameData(button, "qGuildIconHover")
        or (button.SelectedTexture and button.SelectedTexture:IsShown()) then
        r, g, b, a = SkinBase.GetSkinColors()
    end
    SkinBase.SetBackdropColors(backdrop, { r, g, b, a }, nil)
end

local function SkinGuildIcon(button)
    if not button then return end
    local icon = button.Icon
    for _, region in ipairs({ button:GetRegions() }) do
        if region:GetObjectType() == "Texture" and region ~= icon
            and region ~= button.SelectedTexture and region ~= button.Highlight then
            SkinBase.ClampTextureHidden(region, true)
        end
    end
    SkinBase.ClampTextureHidden(button.SelectedTexture, true)
    SkinBase.ClampTextureHidden(button.Highlight, true)
    local sr, sg, sb, sa, r, g, b, a = SkinBase.GetWindowColors()
    SkinBase.CreateBackdrop(button, sr, sg, sb, sa, r, g, b, a, 4)
    SkinBase.GetBackdrop(button):SetFrameLevel(math.max(0, button:GetFrameLevel() - 1))
    SkinBase.RoundIconTexture(button, icon)
    if not SkinBase.GetFrameData(button, "qGuildIconStyled") then
        button:HookScript("OnEnter", function(self)
            SkinBase.SetFrameData(self, "qGuildIconHover", true)
            RefreshGuildIcon(self)
        end)
        button:HookScript("OnLeave", function(self)
            SkinBase.SetFrameData(self, "qGuildIconHover", false)
            RefreshGuildIcon(self)
        end)
        if type(button.UpdateSelectedTexture) == "function" then
            hooksecurefunc(button, "UpdateSelectedTexture", RefreshGuildIcon)
        end
        SkinBase.SetFrameData(button, "qGuildIconStyled", true)
    end
    RefreshGuildIcon(button)
end

SkinIconSelectorPopup = function(popup, settingKey)
    if not popup then return end
    settingKey = settingKey or SkinBase.GetFrameData(popup, "qIconSelectorSetting")
    if not IsSettingEnabled(settingKey) then return end
    local box = popup.BorderBox
    if not SkinBase.IsSkinned(popup) then
        SkinBase.SkinWindow(popup, { noButtonFonts = true })
        SkinBase.SetFrameData(popup, "qIconSelectorSetting", settingKey)
        popup:HookScript("OnShow", function(self) SkinIconSelectorPopup(self, settingKey) end)
        if type(popup.Update) == "function" then
            hooksecurefunc(popup, "Update", function(self) SkinIconSelectorPopup(self, settingKey) end)
        end
        local selector = popup.IconSelector
        if selector and type(selector.RunSetup) == "function" then
            hooksecurefunc(selector, "RunSetup", function(_, button)
                if IsSettingEnabled(settingKey) then SkinGuildIcon(button) end
            end)
        end
        SkinBase.MarkSkinned(popup)
    end
    SkinBase.RefreshFrameBackdropColors(popup)
    SkinBase.ClampTextureHidden(popup.BG, true)
    if box then
        SkinBase.KillNineSlice(box.NineSlice, true)
        SkinBase.StripTextures(box)
        SkinBase.SkinEditBox(box.IconSelectorEditBox)
        SkinBase.RefreshWidget(box.IconSelectorEditBox)
        SkinBase.SkinDropdown(box.IconTypeDropdown, { skinArrow = true })
        SkinBase.RefreshWidget(box.IconTypeDropdown)
        SkinBase.SkinButton(box.OkayButton, { strip = true, font = true })
        SkinBase.SkinButton(box.CancelButton, { strip = true, font = true })
        SkinBase.RefreshWidget(box.OkayButton)
        SkinBase.RefreshWidget(box.CancelButton)
        SkinBase.SkinFrameText(box, { recurse = true })
        local area = box.SelectedIconArea
        local text = area and area.SelectedIconText
        if text then
            SkinBase.SkinFontString(text.SelectedIconHeader)
            SkinBase.LockFontObject(text.SelectedIconDescription, { fontOnly = true })
        end
        SkinGuildIcon(area and area.SelectedIconButton)
    end
    local selector = popup.IconSelector
    if selector then
        SkinBase.SkinTrimScrollBar(selector.ScrollBar)
        SkinBase.ForEachScrollBoxFrame(selector.ScrollBox, SkinGuildIcon)
    end
end

local function SkinGuildBankMoney(frame)
    if not IsSettingEnabled("skinGuildBank") or not frame then return end
    local footer = frame.MoneyFrameBG
    if footer then
        SkinInteractionSurface(footer)
        SkinBase.GetBackdrop(footer):SetFrameLevel(math.max(0, footer:GetFrameLevel() - 1))
        SkinBase.SkinFontString(footer.LimitLabel)
        SkinBase.SkinFontString(footer.UnlimitedLabel)
    end
    local buy = frame.BuyInfo
    if buy then
        SkinBase.SkinFontString(buy.TabText)
        SkinBase.SkinFontString(buy.PurchasedText)
        SkinBase.RefreshWidget(buy.PurchaseButton)
    end
    SkinBase.SkinFontString(_G.GuildBankFrameTabCost)
    SkinBase.RefreshWidget(frame.WithdrawButton)
    for _, name in ipairs({ "GuildBankMoneyFrame", "GuildBankWithdrawMoneyFrame", "GuildBankFrameTabCostMoneyFrame" }) do
        SkinBase.SkinFrameText(_G[name], { recurse = true })
    end
end

local function SkinGuildBankContents(frame)
    if not IsSettingEnabled("skinGuildBank") or not frame then return end
    for _, column in ipairs(frame.Columns or {}) do
        for _, button in ipairs(column.Buttons or {}) do SkinInteractionItem(button) end
    end
    for _, tab in ipairs(frame.BankTabs or {}) do
        SkinBase.StripTextures(tab)
        local button = tab.Button
        if button then
            SkinBase.SkinButton(button, { strip = false, font = false, radius = 4, belowChildren = true })
            SkinBase.RefreshWidget(button)
            SkinBase.RoundIconTexture(button, button.IconTexture)
            SkinBase.SkinFontString(button.Count, { fontOnly = true })
            SkinBase.ClampTextureHidden(button.GetCheckedTexture and button:GetCheckedTexture(), true)
            if not SkinBase.GetFrameData(button, "qGuildTabChecked") then
                hooksecurefunc(button, "SetChecked", RefreshGuildBankTab)
                button:HookScript("OnLeave", RefreshGuildBankTab)
                SkinBase.SetFrameData(button, "qGuildTabChecked", true)
            end
            RefreshGuildBankTab(button)
        end
    end
    for _, key in ipairs({ "TabTitleBG", "TabTitleBGLeft", "TabTitleBGRight",
        "TabLimitBG", "TabLimitBGLeft", "TabLimitBGRight", "RedMarbleBG", "BlackBG" }) do
        SkinBase.ClampTextureHidden(frame[key], true)
    end
    SkinBase.SkinFontString(frame.TabTitle)
    SkinBase.SkinFontString(frame.LimitLabel)
    SkinBase.SkinFontString(frame.ErrorMessage, { fontOnly = true })
    local info = frame.Info
    if info then
        SkinBase.SkinTrimScrollBar(info.ScrollFrame and info.ScrollFrame.ScrollBar)
        SkinBase.SkinFrameText(info, { recurse = true })
    end
    SkinBase.SkinTrimScrollBar(frame.Log and frame.Log.ScrollBar)
    SkinBase.SkinFontString(frame.Log and frame.Log.MessageFrame, { fontOnly = true })
    SkinIconSelectorPopup(_G.GuildBankPopupFrame, "skinGuildBank")
    SkinBase.SkinFrameText(frame.BuyInfo, { recurse = true })
    SkinGuildBankMoney(frame)
end

local function SkinGuildBank()
    if not IsSettingEnabled("skinGuildBank") then return end
    local frame = _G.GuildBankFrame
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinWindow(frame, { tabs = SkinBase.CollectNumberedTabs("GuildBankFrame", 4), noButtonFonts = true })
    SkinBase.SkinButton(frame.DepositButton, { strip = true, font = true })
    SkinBase.SkinButton(frame.WithdrawButton, { strip = true, font = true })
    SkinBase.SkinButton(frame.BuyInfo and frame.BuyInfo.PurchaseButton, { strip = true, font = true })
    SkinBase.SkinButton(frame.Info and frame.Info.SaveButton, { strip = true, font = true })
    SkinBase.SkinEditBox(_G.GuildItemSearchBox)
    SkinBase.SkinEditBox(_G.GuildBankTabInfoEditBox)
    SkinGuildBankContents(frame)
    frame:HookScript("OnShow", SkinGuildBankContents)
    for _, key in ipairs({ "Update", "UpdateTabs", "UpdateFiltered", "UpdateTabInfo" }) do
        if type(frame[key]) == "function" then hooksecurefunc(frame, key, SkinGuildBankContents) end
    end
    for _, key in ipairs({ "UpdateTabBuyingInfo", "UpdateWithdrawMoney" }) do
        if type(frame[key]) == "function" then hooksecurefunc(frame, key, SkinGuildBankMoney) end
    end
    for _, name in ipairs({ "GuildBankFrame_UpdateLog", "GuildBankFrame_UpdateMoneyLog" }) do
        if type(_G[name]) == "function" then
            hooksecurefunc(name, function() SkinGuildBankContents(frame) end)
        end
    end
    SkinBase.MarkSkinned(frame)
end

local function RefreshGuildBank()
    local frame = _G.GuildBankFrame
    RefreshBackdropColors(frame)
    if SkinBase.IsSkinned(frame) then SkinGuildBankContents(frame) end
end
_G.QUI_RefreshGuildBankColors = RefreshGuildBank
if ns.Registry then
    ns.Registry:Register("skinGuildBank", {
        refresh = RefreshGuildBank,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

local function SkinTrainerRow(row)
    if not row or not IsSettingEnabled("skinTrainer") then return end
    local icon = row.icon
    for _, region in ipairs({ row:GetRegions() }) do
        if region ~= icon and region ~= row.lock and region ~= row.disabledBG
            and region.GetObjectType and region:GetObjectType() == "Texture" then
            SkinBase.ClampTextureHidden(region, true)
        end
    end
    local sr, sg, sb, sa = SkinBase.GetWindowColors()
    local r, g, b, a = SkinBase.GetDepthColor("ROW")
    SkinBase.CreateBackdrop(row, sr, sg, sb, sa * 0.5, r, g, b, a, 4)
    if row.selectedTex and row.selectedTex:IsShown() then
        local ar, ag, ab, aa = SkinBase.GetSkinColors()
        SkinBase.SetBackdropColors(SkinBase.GetBackdrop(row), { ar, ag, ab, aa }, nil)
    end
    SkinBase.GetBackdrop(row):SetFrameLevel(math.max(0, row:GetFrameLevel() - 1))
    SkinBase.RoundIconTexture(row, icon)
    SkinBase.SkinFontString(row.name, { fontOnly = true })
    SkinBase.SkinFontString(row.subText, { fontOnly = true })
    SkinBase.SkinFrameText(row.money, { recurse = true })
end

local function SkinTrainerRank()
    local bar = _G.ClassTrainerStatusBar
    if not bar or not IsSettingEnabled("skinTrainer") then return end
    local r, g, b, a = bar:GetStatusBarColor()
    SkinBase.SkinStatusBar(bar, { backdrop = false, color = { r, g, b, a } })
    for _, suffix in ipairs({ "Left", "Right", "Middle", "Background" }) do
        SkinBase.ClampTextureHidden(_G["ClassTrainerStatusBar" .. suffix], true)
    end
    SkinBase.RoundBarTexture(bar, bar:GetStatusBarTexture())
    local sr, sg, sb, sa, br, bg, bb, ba = SkinBase.GetWindowColors()
    SkinBase.CreateBackdrop(bar, sr, sg, sb, sa, br, bg, bb, ba, 3)
    SkinBase.GetBackdrop(bar):SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
    SkinBase.SkinFontString(bar.rankText, { fontOnly = true })
end

local function SkinTrainerContents(frame)
    if not frame or not IsSettingEnabled("skinTrainer") then return end
    local scrollBox = frame.ScrollBox
    if scrollBox and type(scrollBox.ForEachFrame) == "function" then
        scrollBox:ForEachFrame(SkinTrainerRow)
    end
    SkinTrainerRow(frame.skillStepButton)
    SkinBase.SkinFrameText(_G.ClassTrainerFrameMoneyFrame, { recurse = true })
    SkinBase.RefreshWidget(_G.ClassTrainerTrainButton)
    SkinBase.SkinDropdown(frame.FilterDropdown, { skinArrow = true })
    SkinBase.RefreshWidget(frame.FilterDropdown)
    SkinBase.SkinTrimScrollBar(frame.ScrollBar)
    SkinTrainerRank()
end

local function SkinTrainer()
    if not IsSettingEnabled("skinTrainer") then return end
    local frame = _G.ClassTrainerFrame
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinWindow(frame, { noButtonFonts = true })
    SkinBase.SkinDropdown(frame.FilterDropdown, { skinArrow = true })
    SkinBase.SkinButton(_G.ClassTrainerTrainButton, { strip = true, font = true })
    SkinBase.SkinTrimScrollBar(frame.ScrollBar)
    SkinInteractionSurface(frame.bottomInset)
    SkinBase.ClampTextureHidden(frame.BG)
    SkinBase.HookScrollBoxAcquired(frame.ScrollBox, SkinTrainerRow, { sync = true })
    if type(_G.ClassTrainerFrame_InitServiceButton) == "function" then
        hooksecurefunc("ClassTrainerFrame_InitServiceButton", SkinTrainerRow)
    end
    if type(_G.ClassTrainerFrame_Update) == "function" then
        hooksecurefunc("ClassTrainerFrame_Update", function() SkinTrainerContents(frame) end)
    end
    SkinTrainerContents(frame)
    frame:HookScript("OnShow", SkinTrainerContents)
    SkinBase.MarkSkinned(frame)
end

local function RefreshTrainer()
    local frame = _G.ClassTrainerFrame
    RefreshBackdropColors(frame)
    if SkinBase.IsSkinned(frame) then SkinTrainerContents(frame) end
end
if ns.Registry then
    ns.Registry:Register("skinTrainer", {
        refresh = RefreshTrainer,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

local function SkinMacroContents(frame)
    if not IsSettingEnabled("skinMacro") or not frame then return end
    local selector = frame.MacroSelector
    if selector then
        SkinBase.SkinTrimScrollBar(selector.ScrollBar)
        SkinBase.ForEachScrollBoxFrame(selector.ScrollBox, function(button)
            SkinGuildIcon(button)
            SkinBase.SkinFontString(button.Name, { fontOnly = true })
        end)
    end
    for _, name in ipairs({ "MacroEditButton", "MacroCancelButton", "MacroSaveButton",
        "MacroDeleteButton", "MacroNewButton", "MacroExitButton" }) do SkinBase.RefreshWidget(_G[name]) end
    SkinGuildIcon(frame.SelectedMacroButton)
    SkinBase.ClampTextureHidden(_G.MacroFrameSelectedMacroBackground, true)
    SkinBase.SkinFontString(_G.MacroFrameSelectedMacroName, { fontOnly = true })
    SkinBase.SkinFontString(_G.MacroFrameEnterMacroText)
    SkinBase.SkinFontString(_G.MacroFrameCharLimitText, { fontOnly = true })
    SkinIconSelectorPopup(_G.MacroPopupFrame, "skinMacro")
end

local function SkinMacro()
    if not IsSettingEnabled("skinMacro") then return end
    local frame = _G.MacroFrame
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinWindow(frame, { tabs = SkinBase.CollectNumberedTabs("MacroFrame", 2), noButtonFonts = true })
    for _, name in ipairs({ "MacroEditButton", "MacroCancelButton", "MacroSaveButton", "MacroDeleteButton", "MacroNewButton", "MacroExitButton" }) do
        SkinBase.SkinButton(_G[name], { strip = true, font = true })
    end
    SkinBase.StripTextures(frame)
    SkinBase.StripTextures(frame.Inset)
    local editor = _G.MacroFrameTextBackground
    if editor then
        SkinBase.KillNineSlice(editor.NineSlice, true)
        SkinBase.StripTextures(editor)
        local sr, sg, sb, sa = SkinBase.GetWindowColors()
        local r, g, b, a = SkinBase.GetDepthColor("SUBPANEL")
        SkinBase.CreateBackdrop(editor, sr, sg, sb, sa * 0.5, r, g, b, a, 5)
    end
    if frame.MacroSelector then SkinBase.SkinTrimScrollBar(frame.MacroSelector.ScrollBar) end
    if _G.MacroFrameScrollFrame then SkinBase.SkinTrimScrollBar(_G.MacroFrameScrollFrame.ScrollBar) end
    SkinBase.SkinFontString(_G.MacroFrameText, { fontOnly = true })
    SkinMacroContents(frame)
    frame:HookScript("OnShow", SkinMacroContents)
    if type(frame.Update) == "function" then hooksecurefunc(frame, "Update", SkinMacroContents) end
    local selector = frame.MacroSelector
    if selector and type(selector.RunSetup) == "function" then
        hooksecurefunc(selector, "RunSetup", function(_, button)
            if IsSettingEnabled("skinMacro") then
                SkinGuildIcon(button)
                SkinBase.SkinFontString(button.Name, { fontOnly = true })
            end
        end)
    end
    SkinBase.MarkSkinned(frame)
end

local function RefreshMacro()
    local frame = _G.MacroFrame
    RefreshBackdropColors(frame)
    if SkinBase.IsSkinned(frame) then SkinMacroContents(frame) end
end
if ns.Registry then
    ns.Registry:Register("skinMacro", {
        refresh = RefreshMacro,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

SkinBase.OnAddOnLoaded("Blizzard_UIPanels_Game", function()
    SkinBank()
    SkinMerchant()
    SkinGossip()
    SkinQuest()
end, 0)

SkinBase.OnAddOnLoaded("Blizzard_GuildBankUI", SkinGuildBank, 0)
SkinBase.OnAddOnLoaded("Blizzard_TrainerUI", SkinTrainer, 0)
SkinBase.OnAddOnLoaded("Blizzard_MacroUI", SkinMacro, 0)
