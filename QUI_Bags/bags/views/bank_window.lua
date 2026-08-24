-- luacheck: read globals ACCEPT CANCEL StaticPopup_OnClick BANK QUESTION_MARK_ICON MenuUtil bit
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags
local Storage = ns.Storage
local UIKit = ns.UIKit
local Helpers = ns.Helpers
local GetSettings = Helpers.CreateDBGetter("bags")

local function CJKFont(fs, p, s, f)
    if Bags.CJKFont then return Bags.CJKFont(fs, p, s, f) end
    fs:SetFont(p, s, f)
end

local BankWindow = {}
Bags.BankWindow = BankWindow

local CHAR_FIRST, CHAR_LAST = 6, 11
local WB_FIRST, WB_LAST = 12, 16
local SEGMENT_H = 22
local SEGMENT_GAP = 4
local TAB_H = 22
local TAB_GAP = 4
local TAB_STRIP_H = SEGMENT_H + SEGMENT_GAP + TAB_H + 6

local win
local liveMode = false
local viewedCharacter = nil
local activeBankType = Enum.BankType.Character
local selectedByBankType = {
    [Enum.BankType.Character] = nil,
    [Enum.BankType.Account] = nil,
}
local focusItemID = nil
local tabButtons = {}
local purchaseTabButton
local liveHolders = {}
local liveButtons = {}
local cachedButtons = {}
local searchText = ""
local matcher = nil
local searchTimer = nil
local hoverTabBagID = nil

function BankWindow.BankTypeForBagID(bagID)
    if bagID and bagID >= WB_FIRST and bagID <= WB_LAST then
        return Enum.BankType.Account
    end
    if bagID and bagID >= CHAR_FIRST and bagID <= CHAR_LAST then
        return Enum.BankType.Character
    end
    return nil
end

function BankWindow.BankTypeLabel(bankType)
    if bankType == Enum.BankType.Account then return ns.L["Warband Bank"] end
    return ns.L["Character Bank"]
end

function BankWindow.BankTypeForFocus(opts)
    if opts and opts.warband then return Enum.BankType.Account end
    return Enum.BankType.Character
end

function BankWindow.BuildTabList(rec, warband, opts)
    local list = {}
    local onlyBankType = opts and opts.bankType or nil
    local viewChar = (not onlyBankType or onlyBankType == Enum.BankType.Character)
        and (not opts or opts.viewChar ~= false)
    local viewWarband = (not onlyBankType or onlyBankType == Enum.BankType.Account)
        and (not opts or opts.viewWarband ~= false)
    if viewChar then
        local bankTabs = rec and rec.bankTabs
        local insertAt, added = #list + 1, 0
        for bagID = CHAR_FIRST, CHAR_LAST do
            local tab = bankTabs and bankTabs[bagID]
            if tab then
                added = added + 1
                list[#list + 1] = {
                    bagID = bagID, bankType = Enum.BankType.Character,
                    name = tab.name, icon = tab.icon,
                }
            end
        end
        if added > 1 then
            table.insert(list, insertAt, { all = true, bankType = Enum.BankType.Character })
        end
        if opts and opts.canPurchaseChar then
            list[#list + 1] = { purchase = true, bankType = Enum.BankType.Character }
        end
    end
    if viewWarband then
        local wbTabs = warband and warband.tabs
        local insertAt, added = #list + 1, 0
        for bagID = WB_FIRST, WB_LAST do
            local tab = wbTabs and wbTabs[bagID]
            if tab then
                added = added + 1
                list[#list + 1] = {
                    bagID = bagID, bankType = Enum.BankType.Account,
                    name = tab.name, icon = tab.icon,
                }
            end
        end
        if added > 1 then
            table.insert(list, insertAt, { all = true, bankType = Enum.BankType.Account })
        end
        if opts and opts.canPurchaseWarband then
            list[#list + 1] = { purchase = true, bankType = Enum.BankType.Account }
        end
    end
    return list
end

local ScheduleRefresh = Bags.Chassis.MakeScheduleRefresh(
    function() return win end,
    function() BankWindow.Refresh() end)

local function ViewedRecord()
    if viewedCharacter then
        return Storage.Store.GetCharacter(viewedCharacter)
    end
    return Storage.Store.GetCurrentCharacter()
end

local function GetTabRecord(bagID)
    if type(bagID) ~= "number" then return nil end
    if Storage.ScanBank.IsCharTab(bagID) then
        local rec = ViewedRecord()
        return rec and rec.bankTabs and rec.bankTabs[bagID] or nil
    end
    local warband = Storage.Store.GetWarband()
    return warband and warband.tabs and warband.tabs[bagID] or nil
end

local function GetSelectedBagID()
    return selectedByBankType[activeBankType]
end

local function SetSelectedBagID(bagID)
    selectedByBankType[activeBankType] = bagID
    Storage.Bus.Publish("BagsChanged", Storage.Store.GetCurrentCharacterKey(), {})
end

local function SetActiveBankType(bankType)
    activeBankType = bankType or Enum.BankType.Character
    if win and win:IsShown() then BankWindow.Refresh() end
    Storage.Bus.Publish("BagsChanged", Storage.Store.GetCurrentCharacterKey(), {})
end

local function SelectedBankType()
    return activeBankType
end

local function EnsureSelection(tabs)
    local selectedBagID = GetSelectedBagID()
    local first, realTabs = nil, 0
    for _, entry in ipairs(tabs) do
        if not entry.purchase and not entry.all then
            realTabs = realTabs + 1
            first = first or entry.bagID
            if entry.bagID == selectedBagID then return end
        end
    end
    if selectedBagID == "all" and realTabs > 1 then return end
    SetSelectedBagID(first)
end

local function SortScopeForBankType(bankType)
    return bankType == Enum.BankType.Account and "warbandBank" or "characterBank"
end

local function StartSortAllTabs()
    if Bags.SortExecutor.IsRunning() then return end
    if C_Container.SortBank then
        C_Container.SortBank(activeBankType)
    elseif activeBankType == Enum.BankType.Account and C_Container.SortAccountBankBags then
        C_Container.SortAccountBankBags()
    elseif C_Container.SortBankBags then
        C_Container.SortBankBags()
    end
end

local function StartSortSelectedTab()
    if Bags.SortExecutor.IsRunning() then return end
    local tabID = GetSelectedBagID()
    if not tabID then return end
    if tabID == "all" then
        StartSortAllTabs()
        return
    end
    Bags.SortExecutor.Start(SortScopeForBankType(activeBankType), nil, { tabID = tabID })
end

function BankWindow.TabSettingsArgs(tab, text)
    local icon = tab.icon or QUESTION_MARK_ICON or "Interface\\Icons\\INV_Misc_QuestionMark"
    return text, icon, tab.depositFlags or 0
end

local function ShowRenamePopup(entry)
    local tab = GetTabRecord(entry.bagID)
    if not tab then return end
    local bankType, tabID = entry.bankType, entry.bagID
    StaticPopupDialogs["QUI_BANK_RENAME_TAB"] = {
        text = ns.L["Rename bank tab:"],
        button1 = ACCEPT,
        button2 = CANCEL,
        hasEditBox = true,
        maxLetters = 31,
        OnShow = function(self)
            local box = self.editBox or self.EditBox
            if box then
                box:SetText(tab.name or "")
                box:HighlightText()
            end
        end,
        OnAccept = function(self)
            local box = self.editBox or self.EditBox
            local text = box and box:GetText()
            if not text or text == "" then return end
            C_Bank.UpdateBankTabSettings(bankType, tabID,
                BankWindow.TabSettingsArgs(tab, text))
        end,
        EditBoxOnEnterPressed = function(box)
            StaticPopup_OnClick(box:GetParent(), 1)
        end,
        EditBoxOnEscapePressed = function(box)
            box:GetParent():Hide()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("QUI_BANK_RENAME_TAB")
end

local function ShowTabSettingsMenu(anchor, entry)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        ShowRenamePopup(entry)
        return
    end
    local F = Enum.BagSlotFlags or {}
    local FLAG_OPTIONS = {
        { flag = F.ClassEquipment or 2, label = ns.L["Equipment"] },
        { flag = F.ClassConsumables or 4, label = ns.L["Consumables"] },
        { flag = F.ClassProfessionGoods or 8, label = ns.L["Profession Goods"] },
        { flag = F.ClassReagents or 128, label = ns.L["Reagents"] },
        { flag = F.ClassJunk or 16, label = ns.L["Junk"] },
        { flag = F.ClassQuestItems or 32, label = ns.L["Quest Items"] },
        { flag = F.ExpansionCurrent or 256, label = ns.L["Current Expansion Only"] },
        { flag = F.ExpansionLegacy or 512, label = ns.L["Legacy Expansion Only"] },
    }
    MenuUtil.CreateContextMenu(anchor, function(_, root)
        root:CreateTitle((entry.name and entry.name ~= "") and entry.name or ns.L["Bank Tab"])
        root:CreateButton(ns.L["Rename..."], function() ShowRenamePopup(entry) end)
        root:CreateTitle(ns.L["Auto-Deposit Assignments"])
        for _, o in ipairs(FLAG_OPTIONS) do
            root:CreateCheckbox(o.label,
                function()
                    local tab = GetTabRecord(entry.bagID)
                    return tab and bit.band(tab.depositFlags or 0, o.flag) ~= 0 or false
                end,
                function()
                    local tab = GetTabRecord(entry.bagID)
                    if not tab then return end
                    local name, icon = BankWindow.TabSettingsArgs(tab,
                        (tab.name and tab.name ~= "") and tab.name or ns.L["Tab"])
                    C_Bank.UpdateBankTabSettings(entry.bankType, entry.bagID,
                        name, icon, bit.bxor(tab.depositFlags or 0, o.flag))
                end)
        end
    end)
end

local function ShowMoneyPopup(kind, bankType)
    Bags.Chassis.ShowMoneyPopup("QUI_BANK_MONEY", kind, function(depositing, amount)
        if depositing then
            if C_Bank.CanDepositMoney(bankType) then
                C_Bank.DepositMoney(bankType, amount)
            end
        else
            if C_Bank.CanWithdrawMoney(bankType) then
                C_Bank.WithdrawMoney(bankType, amount)
            end
        end
    end)
end

local function ApplyTabHover(bagID)
    hoverTabBagID = bagID
    local function sweep(pool)
        for poolBagID, byBag in pairs(pool) do
            for _, btn in pairs(byBag) do
                if btn:IsShown() then
                    Bags.ItemButtons.SetBagHighlight(btn, bagID ~= nil and poolBagID == bagID)
                end
            end
        end
    end
    sweep(liveButtons)
    sweep(cachedButtons)
end

local function CreateTabButton(purchase)
    local template = purchase and "BankPanelPurchaseButtonScriptTemplate" or nil
    local btn = Bags.Chassis.CreatePanelButton(win._tabStrip, true, template)
    if purchase then
        btn:RegisterForClicks("LeftButtonUp")
    else
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end
    UIKit.CreateBorderLines(btn)
    if not purchase then
        btn:SetScript("OnClick", function(self, mouseButton)
            local entry = self._entry
            if not entry then return end
            if entry.all then
                if mouseButton == "LeftButton" then
                    activeBankType = entry.bankType or activeBankType
                    SetSelectedBagID("all")
                    BankWindow.Refresh()
                end
                return
            end
            if mouseButton == "RightButton" then
                if liveMode then ShowTabSettingsMenu(self, entry) end
                return
            end
            activeBankType = entry.bankType or activeBankType
            SetSelectedBagID(entry.bagID)
            ApplyTabHover(nil)
            BankWindow.Refresh()
        end)
    end
    btn:SetScript("OnEnter", function(self)
        local entry = self._entry
        local tip = entry and (entry.purchase and ns.L["Purchase bank tab"]
            or entry.all and ns.L["All tabs in one grid"] or entry.name)
        if tip and tip ~= "" then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tip)
            if entry and not entry.purchase and not entry.all and liveMode then
                GameTooltip:AddLine(ns.L["Right-click: rename + auto-deposit assignments."],
                    1, 1, 1, true)
            end
            GameTooltip:Show()
        end
        if entry and not entry.purchase and not entry.all
            and GetSelectedBagID() == "all" then
            ApplyTabHover(entry.bagID)
        end
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
        ApplyTabHover(nil)
    end)
    return btn
end

local function CreateBankTypeButton(label, bankType)
    local btn = Bags.Chassis.CreatePanelButton(win._bankTypeStrip, true)
    btn._label:SetText(label)
    btn._bankType = bankType
    btn:SetSize(math.max(88, math.ceil(btn._label:GetStringWidth()) + 16), SEGMENT_H)
    UIKit.CreateBorderLines(btn)
    btn:SetScript("OnClick", function()
        SetActiveBankType(bankType)
    end)
    return btn
end

local function CreateFooterButton(label, onClick, tooltip)
    local btn = Bags.Chassis.CreatePanelButton(win._footer, true)
    btn._label:SetText(label)
    btn:SetSize(math.max(40, math.ceil(btn._label:GetStringWidth()) + 12), 18)
    UIKit.CreateBorderLines(btn)
    btn:SetScript("OnClick", onClick)
    if tooltip then
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label)
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return btn
end

local function EnsureWindow()
    if win then return win end
    win = Bags.Chassis.CreateWindow({
        name = "QUI_BankWindow",
        title = BANK or ns.L["Bank"],
        getPosition = function()
            local s = GetSettings()
            return s and s.windows and s.windows.bank or nil
        end,
        setPosition = function(point, x, y)
            local s = GetSettings()
            if s and s.windows and s.windows.bank then
                s.windows.bank.point, s.windows.bank.x, s.windows.bank.y = point, x, y
            end
        end,
        onSearchChanged = function(text)
            searchText = text or ""
            matcher = (searchText ~= "") and Bags.Search.Compile(searchText) or nil
            if searchTimer then searchTimer:Cancel() end
            searchTimer = C_Timer.NewTimer(0.1, function()
                searchTimer = nil
                ScheduleRefresh()
            end)
        end,
        onClose = function(w)
            w:SetScript("OnUpdate", nil)
            w._updateScheduled = false
            if Bags.BankTakeover and Bags.BankTakeover.IsLive() then
                Bags.BankTakeover.UserClosedWindow()
            end
        end,
        onUserClose = function() BankWindow.Hide() end,
        compactSearch = true,
        onChromeChanged = function() ScheduleRefresh() end,
    })

    local bankTypeStrip = CreateFrame("Frame", nil, win._body)
    bankTypeStrip:SetPoint("TOPLEFT", 0, 0)
    bankTypeStrip:SetPoint("TOPRIGHT", 0, 0)
    bankTypeStrip:SetHeight(SEGMENT_H)
    win._bankTypeStrip = bankTypeStrip
    win._charBankBtn = CreateBankTypeButton(BankWindow.BankTypeLabel(Enum.BankType.Character),
        Enum.BankType.Character)
    win._charBankBtn:SetPoint("TOPLEFT", bankTypeStrip, "TOPLEFT", 0, 0)
    win._warbandBankBtn = CreateBankTypeButton(BankWindow.BankTypeLabel(Enum.BankType.Account),
        Enum.BankType.Account)
    win._warbandBankBtn:SetPoint("LEFT", win._charBankBtn, "RIGHT", SEGMENT_GAP, 0)

    local strip = CreateFrame("Frame", nil, win._body)
    strip:SetPoint("TOPLEFT", 0, -(SEGMENT_H + SEGMENT_GAP))
    strip:SetPoint("TOPRIGHT", 0, -(SEGMENT_H + SEGMENT_GAP))
    strip:SetHeight(TAB_H)
    win._tabStrip = strip

    win._bankMoney = win._footer:CreateFontString(nil, "ARTWORK")
    win._bankMoney:SetPoint("RIGHT", -8, 0)
    CJKFont(win._bankMoney, Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, 12, "OUTLINE")
    win._depositBtn = CreateFooterButton(ns.L["Deposit Gold"], function()
        local bankType = SelectedBankType()
        if not C_Bank.CanDepositMoney(bankType) then return end
        ShowMoneyPopup("deposit", bankType)
    end, ns.L["Put gold into this bank's shared pool (the amount on the right)."])
    win._withdrawBtn = CreateFooterButton(ns.L["Withdraw Gold"], function()
        local bankType = SelectedBankType()
        if not C_Bank.CanWithdrawMoney(bankType) then return end
        ShowMoneyPopup("withdraw", bankType)
    end, ns.L["Take gold out of this bank's shared pool."])
    win._autoBtn = CreateFooterButton(ns.L["Auto-Deposit"], function()
        local bankType = SelectedBankType()
        if C_Bank.DoesBankTypeSupportAutoDeposit(bankType) then
            C_Bank.AutoDepositItemsIntoBank(bankType)
        end
    end, ns.L["Blizzard's assignment sweep: moves items from your bags into tabs according to each tab's auto-deposit assignments (right-click a tab to set those)."])
    win._depositAllBtn = CreateFooterButton(ns.L["Deposit All"], function()
        if not Bags.Transfers.IsRunning() then
            Bags.Transfers.DepositAllToWarband()
        end
    end, ns.L["Deposit everything in your bags that the warband bank accepts (soulbound items stay)."])
    win._depositReagentsBtn = CreateFooterButton(ns.L["Deposit Reagents"], function()
        if not Bags.Transfers.IsRunning() then
            Bags.Transfers.DepositReagents(SelectedBankType())
        end
    end, ns.L["Deposit only crafting reagents from your bags into this bank."])

    local sort = Bags.Chassis.CreatePanelButton(win._header, false)
    sort._icon = sort:CreateTexture(nil, "ARTWORK")
    sort._icon:SetPoint("TOPLEFT", 1, -1)
    sort._icon:SetPoint("BOTTOMRIGHT", -1, 1)
    sort._icon:SetAtlas("bags-button-autosort-up")
    sort:SetSize(18, 18)
    sort:SetPoint("RIGHT", win._searchBox, "LEFT", -8, 0)
    UIKit.CreateBorderLines(sort)
    sort:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    sort:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            Bags.Chassis.ShowSortMenu(self, function(root)
                root:CreateButton(ns.L["Sort all"] .. " " .. BankWindow.BankTypeLabel(activeBankType)
                    .. " " .. ns.L["tabs (Blizzard sort)"], StartSortAllTabs)
            end)
            return
        end
        StartSortSelectedTab()
    end)
    sort:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(ns.L["Sort this"] .. " " .. BankWindow.BankTypeLabel(activeBankType)
            .. " " .. ns.L["tab"] .. " — " .. Bags.Chassis.SortModeText())
        GameTooltip:AddLine(ns.L["Right-click for sort options."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    sort:SetScript("OnLeave", function() GameTooltip:Hide() end)
    sort:Hide()
    win._sortBtn = sort

    win._ownerSelect = Bags.OwnerSelect.Attach(win, {
        title = ns.L["Characters"],
        tooltip = ns.L["View another character's bank"],
        listOwners = function()
            return Bags.OwnerSelect.BuildOwnerList(
                Storage.Store.ListCharacters(), Storage.Store.GetCurrentCharacterKey())
        end,
        current = function()
            return viewedCharacter or Storage.Store.GetCurrentCharacterKey()
        end,
        onSelect = function(key) BankWindow.SetViewedCharacter(key) end,
    })

    win:ApplyPosition()
    return win
end

local function RenderTabStrip(tabs)
    for _, btn in ipairs(tabButtons) do btn:Hide() end
    if purchaseTabButton then purchaseTabButton:Hide() end
    local sr, sg, sb = Helpers.GetSkinColors()
    local selectedBagID = GetSelectedBagID()
    local x = 0
    for i, entry in ipairs(tabs) do
        local btn
        if entry.purchase then
            purchaseTabButton = purchaseTabButton or CreateTabButton(true)
            btn = purchaseTabButton
            btn:SetAttribute("overrideBankType", entry.bankType)
        else
            btn = tabButtons[i]
            if not btn then
                btn = CreateTabButton(false)
                tabButtons[i] = btn
            end
        end
        btn._entry = entry
        local label = "+"
        if entry.all then
            label = ns.L["All"]
        elseif not entry.purchase then
            label = (entry.name and entry.name ~= "") and entry.name or ns.L["Tab"]
        end
        btn._label:SetText(label)
        local w = entry.purchase and TAB_H
            or math.max(40, math.ceil(btn._label:GetStringWidth()) + 14)
        btn:SetSize(w, TAB_H)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", win._tabStrip, "TOPLEFT", x, 0)
        local selected = (entry.all and selectedBagID == "all")
            or (not entry.purchase and not entry.all and entry.bagID == selectedBagID)
        UIKit.UpdateBorderLines(btn, 1, sr, sg, sb, selected and 1 or 0.35)
        btn:Show()
        x = x + w + TAB_GAP
    end
    return x > 0 and (x - TAB_GAP) or 0
end

local function RenderBankTypeSegment()
    local sr, sg, sb = Helpers.GetSkinColors()
    local totalW = 0
    local buttons = { win._charBankBtn, win._warbandBankBtn }
    for _, btn in ipairs(buttons) do
        local selected = btn._bankType == activeBankType
        UIKit.UpdateBorderLines(btn, 1, sr, sg, sb, selected and 1 or 0.35)
        btn:Show()
        totalW = totalW + btn:GetWidth()
    end
    return totalW + SEGMENT_GAP
end

local function HideAllGridButtons()
    for _, byBag in pairs(liveButtons) do
        for _, btn in pairs(byBag) do btn:Hide() end
    end
    for _, byBag in pairs(cachedButtons) do
        for _, btn in pairs(byBag) do btn:Hide() end
    end
end

local function AcquireGridButton(bagID, slot)
    if liveMode then
        local holder = liveHolders[bagID]
        if not holder then
            holder = Bags.ItemButtons.CreateHolder(win._body, bagID)
            liveHolders[bagID] = holder
        end
        local byBag = liveButtons[bagID]
        if not byBag then byBag = {}; liveButtons[bagID] = byBag end
        local btn = byBag[slot]
        if not btn then
            btn = Bags.ItemButtons.CreateLive(holder, bagID)
            btn:SetID(slot)
            byBag[slot] = btn
        end
        return btn
    end
    local byBag = cachedButtons[bagID]
    if not byBag then byBag = {}; cachedButtons[bagID] = byBag end
    local btn = byBag[slot]
    if not btn then
        btn = Bags.ItemButtons.CreateCached(win._body)
        byBag[slot] = btn
    end
    return btn
end

local function PlaceGridButton(bagID, slot, entry, x, y, snappedSize)
    local btn = AcquireGridButton(bagID, slot)
    btn:SetSize(snappedSize, snappedSize)
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", win._body, "TOPLEFT", x, y)
    local result = nil
    if matcher then
        local details = Bags.Details.Build(entry)
        if details then
            local m = matcher(details)
            result = (m ~= false)
        else
            result = false
        end
    end
    if liveMode then
        Bags.ItemButtons.Dress(btn, entry, result)
    else
        Bags.ItemButtons.DressCached(btn, entry, result)
    end
    Bags.ItemButtons.SetFocusFlash(btn,
        focusItemID ~= nil and entry ~= nil and entry.itemID == focusItemID)
    Bags.ItemButtons.SetBagHighlight(btn,
        hoverTabBagID ~= nil and bagID == hoverTabBagID)
    btn:Show()
end

local FOOTER_PAD_X = 8
local FOOTER_PAD_Y = 2
local FOOTER_GAP = 4
local FOOTER_ROW_H = 18

local function RenderFooter()
    if not liveMode then
        win._bankMoney:Hide()
        win._depositBtn:Hide()
        win._withdrawBtn:Hide()
        win._autoBtn:Hide()
        win._depositAllBtn:Hide()
        win._depositReagentsBtn:Hide()
        win:SetFooterHeight(FOOTER_ROW_H + FOOTER_PAD_Y * 2)
        return
    end
    local bankType = SelectedBankType()
    local money = C_Bank.FetchDepositedMoney(bankType)
    if GetMoneyString then
        win._bankMoney:SetText(GetMoneyString(money, true))
    else
        win._bankMoney:SetText(tostring(money))
    end
    win._bankMoney:Show()

    local sr, sg, sb = Helpers.GetSkinColors()
    local shown = {}
    local function gate(btn, show)
        if show then
            UIKit.UpdateBorderLines(btn, 1, sr, sg, sb, 0.35)
            btn:Show()
            shown[#shown + 1] = btn
        else
            btn:Hide()
        end
    end
    gate(win._depositBtn, C_Bank.CanDepositMoney(bankType) and true or false)
    gate(win._withdrawBtn, C_Bank.CanWithdrawMoney(bankType) and true or false)
    gate(win._autoBtn, C_Bank.DoesBankTypeSupportAutoDeposit(bankType) and true or false)
    gate(win._depositAllBtn, bankType == Enum.BankType.Account)
    gate(win._depositReagentsBtn, true)

    local availW = win:GetWidth() - FOOTER_PAD_X * 2
    local moneyW = win._bankMoney:GetStringWidth() or 0
    local rows = { {} }
    local rowW = { 0 }
    for _, btn in ipairs(shown) do
        local w = btn:GetWidth()
        local r = #rows
        local need = rowW[r] > 0 and (rowW[r] + FOOTER_GAP + w) or w
        if rowW[r] > 0 and need > availW then
            r = r + 1
            rows[r], rowW[r] = {}, 0
            need = w
        end
        rows[r][#rows[r] + 1] = btn
        rowW[r] = need
    end
    local moneyRow = #rows
    if rowW[moneyRow] > 0 and rowW[moneyRow] + FOOTER_GAP + moneyW > availW then
        moneyRow = moneyRow + 1
    end
    local totalRows = math.max(moneyRow, #rows)

    local rowStride = FOOTER_ROW_H + FOOTER_GAP
    for r, rowBtns in ipairs(rows) do
        local x = FOOTER_PAD_X
        local rowTop = FOOTER_PAD_Y + (r - 1) * rowStride
        for _, btn in ipairs(rowBtns) do
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", win._footer, "TOPLEFT", x, -rowTop)
            x = x + btn:GetWidth() + FOOTER_GAP
        end
    end
    local footerH = FOOTER_PAD_Y * 2 + totalRows * FOOTER_ROW_H
        + (totalRows - 1) * FOOTER_GAP
    local moneyCenter = FOOTER_PAD_Y + (moneyRow - 1) * rowStride + FOOTER_ROW_H / 2
    win._bankMoney:ClearAllPoints()
    win._bankMoney:SetPoint("RIGHT", win._footer, "RIGHT", -FOOTER_PAD_X,
        footerH / 2 - moneyCenter)
    win:SetFooterHeight(footerH)
end

function BankWindow.Refresh()
    if not win or not win:IsShown() then return end
    local s = GetSettings()
    local appearance = Bags.Chassis.ClampAppearance((s and s.appearance) or nil)

    local rec = ViewedRecord()
    local warband = Storage.Store.GetWarband()
    local opts = { bankType = activeBankType }
    if liveMode then
        local viewChar = C_Bank.CanViewBank(Enum.BankType.Character)
        local viewWarband = C_Bank.CanViewBank(Enum.BankType.Account)
        if activeBankType == Enum.BankType.Character and not viewChar and viewWarband then
            activeBankType = Enum.BankType.Account
        elseif activeBankType == Enum.BankType.Account and not viewWarband and viewChar then
            activeBankType = Enum.BankType.Character
        end
        opts = {
            canPurchaseChar = C_Bank.CanPurchaseBankTab(Enum.BankType.Character),
            canPurchaseWarband = C_Bank.CanPurchaseBankTab(Enum.BankType.Account),
            viewChar = viewChar,
            viewWarband = viewWarband,
            bankType = activeBankType,
        }
    end
    win._title:SetText(BankWindow.BankTypeLabel(activeBankType))
    local tabs = BankWindow.BuildTabList(rec, warband, opts)
    EnsureSelection(tabs)
    if focusItemID and GetSelectedBagID() ~= "all" then
        local selectedBagID = GetSelectedBagID()
        local cur = GetTabRecord(selectedBagID)
        local function tabHas(t)
            if not (t and t.slots) then return false end
            for _, e in pairs(t.slots) do
                if e and e.itemID == focusItemID then return true end
            end
            return false
        end
        if not tabHas(cur) then
            local target
            if activeBankType == Enum.BankType.Account then
                target = BankWindow.FindTabForItem(nil, warband, focusItemID)
            else
                target = BankWindow.FindTabForItem(rec, nil, focusItemID)
            end
            if target then SetSelectedBagID(target) end
        end
    end
    local segmentW = RenderBankTypeSegment()
    local stripW = RenderTabStrip(tabs)

    if liveMode then
        local sr, sg, sb = Helpers.GetSkinColors()
        UIKit.UpdateBorderLines(win._sortBtn, 1, sr, sg, sb, 0.35)
        win._sortBtn:Show()
    else
        win._sortBtn:Hide()
    end
    win._ownerSelect:Update()
    local headerMinW = Bags.Chassis.MeasureHeaderWidth({
        win._title, win._ownerSelect, win._sortBtn, win._searchBox, win._close,
    }, { leftPad = 8, rightPad = 6, gap = 8 })

    local core = Helpers.GetCore()
    local snappedSize, snappedGap = appearance.iconSize, appearance.spacing
    local px = core and core.GetPixelSize and core:GetPixelSize(win) or nil
    if px and px > 0 then
        snappedSize = math.floor(appearance.iconSize / px + 0.5) * px
        snappedGap = math.floor(appearance.spacing / px + 0.5) * px
    end

    local selectedBagID = GetSelectedBagID()
    HideAllGridButtons()
    local cols = appearance.bankColumns or appearance.columns
    local pending = {}
    local gridW, gridH
    if selectedBagID == "all" then
        local cells = {}
        for _, entry in ipairs(tabs) do
            if not entry.purchase and not entry.all then
                local t = GetTabRecord(entry.bagID)
                local size = t and t.size or 0
                for slot = 1, size do
                    cells[#cells + 1] = { bagID = entry.bagID, slot = slot,
                        entry = t.slots and t.slots[slot] or nil }
                end
            end
        end
        local layout = Bags.GridLayout.Compute(#cells, {
            columns = cols * 2, iconSize = snappedSize, spacing = snappedGap,
        })
        for i, c in ipairs(cells) do
            pending[#pending + 1] = { bagID = c.bagID, slot = c.slot,
                entry = c.entry,
                x = layout[i].x, y = layout[i].y - TAB_STRIP_H }
        end
        gridW, gridH = layout.width, layout.height
    else
        local tab = GetTabRecord(selectedBagID)
        local size = tab and tab.size or 0
        local slots = tab and tab.slots
        local layout = Bags.GridLayout.Compute(size, {
            columns = cols, iconSize = snappedSize, spacing = snappedGap,
        })
        for slot = 1, size do
            pending[#pending + 1] = { bagID = selectedBagID, slot = slot,
                entry = slots[slot],
                x = layout[slot].x, y = layout[slot].y - TAB_STRIP_H }
        end
        gridW, gridH = layout.width, layout.height
    end

    local finalW = math.max(gridW, stripW, segmentW, headerMinW)
    local xOff = 0
    if finalW > gridW and gridW > 0 then
        xOff = (finalW - gridW) / 2
        if px and px > 0 then xOff = math.floor(xOff / px + 0.5) * px end
    end
    for _, pl in ipairs(pending) do
        PlaceGridButton(pl.bagID, pl.slot, pl.entry, pl.x + xOff, pl.y, snappedSize)
    end
    win:SetContentSize(finalW, TAB_STRIP_H + gridH)

    RenderFooter()
end

local function Show()
    EnsureWindow()
    local wasShown = win:IsShown()
    win:Show()
    if not wasShown and PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN then
        PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
    end
    BankWindow.Refresh()
end

function BankWindow.ShowLive()
    liveMode = true
    viewedCharacter = nil
    Show()
end

function BankWindow.ShowCached()
    liveMode = false
    viewedCharacter = nil
    Show()
end

function BankWindow.SetViewedCharacter(key)
    if key == nil or key == Storage.Store.GetCurrentCharacterKey() then
        viewedCharacter = nil
        liveMode = Bags.BankTakeover ~= nil and Bags.BankTakeover.IsLive() or false
    else
        viewedCharacter = key
        liveMode = false
    end
    BankWindow.Refresh()
end

function BankWindow.OnBankClosed()
    BankWindow.Hide()
end

function BankWindow.Hide()
    focusItemID = nil
    if win and win:IsShown() then
        win:Hide()
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_CLOSE then
            PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
        end
    end
end

function BankWindow.FindTabForItem(rec, warband, itemID)
    local function scan(map)
        if not map then return nil end
        local ids = {}
        for bagID in pairs(map) do ids[#ids + 1] = bagID end
        table.sort(ids)
        for _, bagID in ipairs(ids) do
            local t = map[bagID]
            if t and t.slots then
                for _, e in pairs(t.slots) do
                    if e and e.itemID == itemID then return bagID end
                end
            end
        end
        return nil
    end
    return scan(rec and rec.bankTabs) or scan(warband and warband.tabs)
end

function BankWindow.FocusItem(itemID, ownerKey, opts)
    activeBankType = BankWindow.BankTypeForFocus(opts)
    focusItemID = itemID
    if C_Timer and C_Timer.After then
        C_Timer.After(3, function()
            if focusItemID == itemID then
                focusItemID = nil
                ScheduleRefresh()
            end
        end)
    end
    if not BankWindow.IsShown() then
        if Bags.BankTakeover and Bags.BankTakeover.IsLive
            and Bags.BankTakeover.IsLive()
            and (ownerKey == nil or ownerKey == Storage.Store.GetCurrentCharacterKey()) then
            BankWindow.ShowLive()
        else
            BankWindow.ShowCached()
        end
    end
    BankWindow.SetViewedCharacter(ownerKey)
end

function BankWindow.GetActiveBankType()
    return activeBankType
end

function BankWindow.GetSelectedLiveTab()
    if not (win and win:IsShown() and liveMode) then return nil end
    local sel = GetSelectedBagID()
    if type(sel) == "number" then return sel, activeBankType end
    return nil
end

function BankWindow.IsShown()
    return win ~= nil and win:IsShown()
end

function BankWindow.GetFrame()
    return win
end

function BankWindow.OnProfileChanged()
    if not win then return end
    win:ApplyPosition()
    if win:IsShown() then BankWindow.Refresh() end
end

Storage.Bus.Subscribe("BankChanged", function()
    ScheduleRefresh()
end)

Storage.Bus.Subscribe("WarbandChanged", function()
    ScheduleRefresh()
end)

Storage.Bus.Subscribe("MoneyChanged", function()
    if liveMode then ScheduleRefresh() end
end)
