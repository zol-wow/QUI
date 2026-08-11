-- luacheck: read globals MAX_GUILDBANK_TABS QueryGuildBankLog QueryGuildBankTab GetGuildBankTabCost
-- luacheck: read globals ACCEPT CANCEL BuyGuildBankTab SetGuildBankTabInfo StaticPopup_OnClick
-- luacheck: read globals DepositGuildBankMoney CanWithdrawGuildBankMoney WithdrawGuildBankMoney
-- luacheck: read globals UNKNOWN NORMAL_FONT_COLOR_CODE GUILD_BANK_LOG_TIME RecentTimeDate
-- luacheck: read globals GetNumGuildBankTransactions GetGuildBankTransaction
-- luacheck: read globals GUILDBANK_DEPOSIT_FORMAT GUILDBANK_WITHDRAW_FORMAT GetGuildBankTabInfo
-- luacheck: read globals GUILDBANK_MOVE_FORMAT GUILDBANK_LOG_QUANTITY
-- luacheck: read globals GUILDBANK_DEPOSIT_MONEY_FORMAT GUILDBANK_WITHDRAW_MONEY_FORMAT
-- luacheck: read globals GUILDBANK_REPAIR_MONEY_FORMAT GUILDBANK_WITHDRAWFORTAB_MONEY_FORMAT
-- luacheck: read globals GUILDBANK_GUILD_RENAME_PURCHASE GUILDBANK_GUILD_RENAME_REFUND
-- luacheck: read globals GetNumGuildBankMoneyTransactions GetGuildBankMoneyTransaction
-- luacheck: read globals GetDenominationsFromCopper GUILDBANK_BUYTAB_MONEY_FORMAT
-- luacheck: read globals GUILDBANK_UNLOCKTAB_FORMAT GUILDBANK_AWARD_MONEY_SUMMARY_FORMAT
-- luacheck: read globals CanEditGuildBankTabInfo SetCurrentGuildBankTab GUILD_BANK
-- luacheck: read globals GetGuildBankMoney GetGuildBankWithdrawMoney GetNumGuildBankTabs
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

local GuildWindow = {}
Bags.GuildWindow = GuildWindow

local MAX_TABS = MAX_GUILDBANK_TABS or 8
local TAB_H = 22
local TAB_GAP = 4
local TAB_STRIP_H = TAB_H + 6
local LOG_MODE_ROW_H = 20
local MIN_BODY_W = 320
local MIN_LOG_H = 240

local win
local liveMode = false
local viewedGuildKey = nil
local selectedTab = nil
local focusItemID = nil
local bodyMode = "grid"
local logMode = "item"
local tabButtons = {}
local liveButtons = {}
local cachedButtons = {}
local searchText = ""
local matcher = nil
local searchTimer = nil
local hoverTabIndex = nil

function GuildWindow.BuildTabList(rec, opts)
    local list = {}
    local tabs = rec and rec.tabs
    if tabs then
        for tab = 1, MAX_TABS do
            local t = tabs[tab]
            if t and not (opts and opts.liveViewable and opts.liveViewable[tab] == false) then
                list[#list + 1] = {
                    tab = tab, name = t.name, icon = t.icon,
                    withdrawals = t.withdrawals,
                }
            end
        end
        if #list > 1 then
            table.insert(list, 1, { all = true })
        end
    end
    if opts and opts.canPurchase then
        list[#list + 1] = { purchase = true }
    end
    return list
end

local ScheduleRefresh = Bags.Chassis.MakeScheduleRefresh(
    function() return win end,
    function() GuildWindow.Refresh() end)

local function ViewedGuildKey()
    return viewedGuildKey or Storage.Store.GetCurrentGuildKey()
end

local function GetGuildRecord()
    local key = ViewedGuildKey()
    return key and Storage.Store.GetGuild(key) or nil
end

local function EnsureSelection(tabs)
    local first, realTabs = nil, 0
    for _, entry in ipairs(tabs) do
        if not entry.purchase and not entry.all then
            realTabs = realTabs + 1
            first = first or entry.tab
            if entry.tab == selectedTab then return false end
        end
    end
    if selectedTab == "all" and realTabs > 1 then return false end
    local changed = selectedTab ~= first
    selectedTab = first
    return changed
end

local function QueryLog()
    if not liveMode then return end
    if logMode == "money" then
        QueryGuildBankLog(MAX_TABS + 1)
    elseif type(selectedTab) == "number" then
        QueryGuildBankLog(selectedTab)
    end
end

local function ShowPurchasePopup()
    local cost = GetGuildBankTabCost()
    if not cost then return end
    local costText = GetMoneyString and GetMoneyString(cost, true) or tostring(cost)
    StaticPopupDialogs["QUI_GUILDBANK_BUY_TAB"] = {
        text = ns.L["Purchase guild bank tab?"] .. "\n\n" .. costText,
        button1 = ACCEPT,
        button2 = CANCEL,
        OnAccept = function()
            BuyGuildBankTab()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("QUI_GUILDBANK_BUY_TAB")
end

local function ShowRenamePopup(entry)
    local rec = GetGuildRecord()
    local tab = rec and rec.tabs and rec.tabs[entry.tab]
    if not tab then return end
    local tabIndex = entry.tab
    StaticPopupDialogs["QUI_GUILDBANK_RENAME_TAB"] = {
        text = ns.L["Rename guild bank tab:"],
        button1 = ACCEPT,
        button2 = CANCEL,
        hasEditBox = true,
        maxLetters = 15,
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
            SetGuildBankTabInfo(tabIndex, text, tab.icon)
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
    StaticPopup_Show("QUI_GUILDBANK_RENAME_TAB")
end

local function ShowMoneyPopup(kind)
    Bags.Chassis.ShowMoneyPopup("QUI_GUILDBANK_MONEY", kind, function(depositing, amount)
        if depositing then
            DepositGuildBankMoney(amount)
        else
            if CanWithdrawGuildBankMoney() then
                WithdrawGuildBankMoney(amount)
            end
        end
    end)
end

local function ColorName(name)
    name = name or UNKNOWN or "Unknown"
    return (NORMAL_FONT_COLOR_CODE or "|cffffd200") .. name
        .. (FONT_COLOR_CODE_CLOSE or "|r")
end

local function LogTimeSuffix(year, month, day, hour)
    local recent = (TimeUtil and TimeUtil.GetRecentTimeDate) or RecentTimeDate
    if GUILD_BANK_LOG_TIME and recent then
        return GUILD_BANK_LOG_TIME:format(recent(year, month, day, hour))
    end
    return ""
end

local function RenderItemLog(smf)
    if type(selectedTab) ~= "number" then
        smf:AddMessage(ns.L["Select a tab to view its item log."])
        return
    end
    for i = 1, GetNumGuildBankTransactions(selectedTab) do
        local kind, name, itemLink, count, tab1, tab2, year, month, day, hour =
            GetGuildBankTransaction(selectedTab, i)
        name = ColorName(name)
        local msg
        if kind == "deposit" then
            msg = GUILDBANK_DEPOSIT_FORMAT and format(GUILDBANK_DEPOSIT_FORMAT, name, itemLink)
                or (name .. " deposited " .. tostring(itemLink))
        elseif kind == "withdraw" then
            msg = GUILDBANK_WITHDRAW_FORMAT and format(GUILDBANK_WITHDRAW_FORMAT, name, itemLink)
                or (name .. " withdrew " .. tostring(itemLink))
        elseif kind == "move" then
            local name1 = GetGuildBankTabInfo(tab1)
            local name2 = GetGuildBankTabInfo(tab2)
            msg = GUILDBANK_MOVE_FORMAT
                and format(GUILDBANK_MOVE_FORMAT, name, itemLink, count, name1, name2)
                or (name .. " moved " .. tostring(itemLink))
        end
        if msg then
            if kind ~= "move" and count and count > 1 then
                msg = msg .. (GUILDBANK_LOG_QUANTITY and format(GUILDBANK_LOG_QUANTITY, count)
                    or (" x" .. count))
            end
            smf:AddMessage(msg .. LogTimeSuffix(year, month, day, hour))
        end
    end
end

local function MoneyLogFormat(kind)
    if kind == "deposit" then return GUILDBANK_DEPOSIT_MONEY_FORMAT end
    if kind == "withdraw" then return GUILDBANK_WITHDRAW_MONEY_FORMAT end
    if kind == "repair" then return GUILDBANK_REPAIR_MONEY_FORMAT end
    if kind == "withdrawForTab" then return GUILDBANK_WITHDRAWFORTAB_MONEY_FORMAT end
    if kind == "buyRename" then return GUILDBANK_GUILD_RENAME_PURCHASE end
    if kind == "refundRename" then return GUILDBANK_GUILD_RENAME_REFUND end
    return nil
end

local function RenderMoneyLog(smf)
    for i = 1, GetNumGuildBankMoneyTransactions() do
        local kind, name, amount, year, month, day, hour = GetGuildBankMoneyTransaction(i)
        amount = amount or 0
        name = ColorName(name)
        local money = GetDenominationsFromCopper and GetDenominationsFromCopper(amount)
            or tostring(amount)
        local msg
        if kind == "buyTab" then
            if amount > 0 then
                msg = GUILDBANK_BUYTAB_MONEY_FORMAT
                    and GUILDBANK_BUYTAB_MONEY_FORMAT:format(name, money)
                    or (name .. " bought a tab for " .. money)
            else
                msg = GUILDBANK_UNLOCKTAB_FORMAT and GUILDBANK_UNLOCKTAB_FORMAT:format(name)
                    or (name .. " unlocked a tab")
            end
        elseif kind == "depositSummary" then
            msg = GUILDBANK_AWARD_MONEY_SUMMARY_FORMAT
                and GUILDBANK_AWARD_MONEY_SUMMARY_FORMAT:format(money)
                or ("Awarded " .. money)
        elseif kind then
            local fmt = MoneyLogFormat(kind)
            msg = fmt and fmt:format(name, money)
                or (name .. " " .. tostring(kind) .. " " .. money)
        end
        if msg then
            smf:AddMessage(msg .. LogTimeSuffix(year, month, day, hour))
        end
    end
end

local function RenderLog()
    local smf = win._logFrame
    smf:Clear()
    if logMode == "money" then
        RenderMoneyLog(smf)
    else
        RenderItemLog(smf)
    end
    smf:ScrollToBottom()
end

local function ApplyTabHover(tab)
    hoverTabIndex = tab
    local function sweep(pool)
        for poolTab, byTab in pairs(pool) do
            for _, btn in pairs(byTab) do
                if btn:IsShown() then
                    Bags.ItemButtons.SetBagHighlight(btn, tab ~= nil and poolTab == tab)
                end
            end
        end
    end
    sweep(liveButtons)
    sweep(cachedButtons)
end

local function CreateTabButton()
    local btn = Bags.Chassis.CreatePanelButton(win._tabStrip, true)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    UIKit.CreateBorderLines(btn)
    btn:SetScript("OnClick", function(self, mouseButton)
        local entry = self._entry
        if not entry then return end
        if entry.purchase then
            if mouseButton == "LeftButton" then
                ShowPurchasePopup()
            end
            return
        end
        if entry.all then
            if mouseButton == "LeftButton" then
                selectedTab = "all"
                GuildWindow.Refresh()
            end
            return
        end
        if mouseButton == "RightButton" then
            if liveMode and CanEditGuildBankTabInfo() then
                ShowRenamePopup(entry)
            end
            return
        end
        selectedTab = entry.tab
        if liveMode then
            SetCurrentGuildBankTab(entry.tab)
            QueryGuildBankTab(entry.tab)
            if bodyMode == "log" and logMode == "item" then
                QueryGuildBankLog(entry.tab)
            end
        end
        ApplyTabHover(nil)
        GuildWindow.Refresh()
    end)
    btn:SetScript("OnEnter", function(self)
        local entry = self._entry
        if not entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if entry.purchase then
            GameTooltip:SetText(ns.L["Purchase guild bank tab"])
        elseif entry.all then
            GameTooltip:SetText(ns.L["All tabs in one grid"])
        else
            local label = (entry.name and entry.name ~= "") and entry.name
                or ("Tab " .. tostring(entry.tab))
            GameTooltip:SetText(label)
            if liveMode then
                local _, _, isViewable, canDeposit, _, remainingWithdrawals =
                    GetGuildBankTabInfo(entry.tab)
                GameTooltip:AddLine(isViewable and ns.L["Viewable"] or ns.L["Not viewable"], 0.8, 0.8, 0.8)
                GameTooltip:AddLine(canDeposit and ns.L["Deposits allowed"] or ns.L["No deposits"], 0.8, 0.8, 0.8)
                if remainingWithdrawals == -1 then
                    GameTooltip:AddLine(ns.L["Withdrawals: no limit"], 0.8, 0.8, 0.8)
                elseif remainingWithdrawals then
                    GameTooltip:AddLine(ns.L["Withdrawals left: "] .. remainingWithdrawals, 0.8, 0.8, 0.8)
                end
            elseif entry.withdrawals then
                if entry.withdrawals == -1 then
                    GameTooltip:AddLine(ns.L["Withdrawals: no limit"], 0.8, 0.8, 0.8)
                else
                    GameTooltip:AddLine(ns.L["Withdrawals left: "] .. entry.withdrawals, 0.8, 0.8, 0.8)
                end
            end
        end
        GameTooltip:Show()
        if not entry.purchase and not entry.all and selectedTab == "all" then
            ApplyTabHover(entry.tab)
        end
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
        ApplyTabHover(nil)
    end)
    return btn
end

local function CreateTextButton(parent, label, onClick)
    local btn = Bags.Chassis.CreatePanelButton(parent, true)
    btn._label:SetText(label)
    btn:SetSize(math.max(40, math.ceil(btn._label:GetStringWidth()) + 12), 18)
    btn:SetScript("OnClick", onClick)
    return btn
end

local function EnsureWindow()
    if win then return win end
    win = Bags.Chassis.CreateWindow({
        name = "QUI_GuildBankWindow",
        title = GUILD_BANK or ns.L["Guild Bank"],
        getPosition = function()
            local s = GetSettings()
            return s and s.windows and s.windows.guildbank or nil
        end,
        setPosition = function(point, x, y)
            local s = GetSettings()
            if s and s.windows and s.windows.guildbank then
                s.windows.guildbank.point, s.windows.guildbank.x, s.windows.guildbank.y =
                    point, x, y
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
            if Bags.GuildTakeover and Bags.GuildTakeover.IsLive() then
                Bags.GuildTakeover.UserClosedWindow()
            end
        end,
        onUserClose = function() GuildWindow.Hide() end,
        compactSearch = true,
        onChromeChanged = function() ScheduleRefresh() end,
    })

    local strip = CreateFrame("Frame", nil, win._body)
    strip:SetPoint("TOPLEFT", 0, 0)
    strip:SetPoint("TOPRIGHT", 0, 0)
    strip:SetHeight(TAB_H)
    win._tabStrip = strip

    local log = CreateFrame("Frame", nil, win._body)
    log:SetPoint("TOPLEFT", 0, -TAB_STRIP_H)
    log:SetPoint("BOTTOMRIGHT", 0, 0)
    log:Hide()
    win._logPanel = log

    win._itemLogBtn = CreateTextButton(log, ns.L["Item Log"], function()
        logMode = "item"
        QueryLog()
        GuildWindow.Refresh()
    end)
    win._itemLogBtn:SetPoint("TOPLEFT", 0, 0)
    win._moneyLogBtn = CreateTextButton(log, ns.L["Money Log"], function()
        logMode = "money"
        QueryLog()
        GuildWindow.Refresh()
    end)
    win._moneyLogBtn:SetPoint("LEFT", win._itemLogBtn, "RIGHT", 4, 0)

    local smf = CreateFrame("ScrollingMessageFrame", nil, log)
    smf:SetPoint("TOPLEFT", 0, -LOG_MODE_ROW_H - 4)
    smf:SetPoint("BOTTOMRIGHT", 0, 0)
    smf:SetFontObject(ChatFontNormal)
    smf:SetJustifyH("LEFT")
    smf:SetFading(false)
    smf:SetMaxLines(128)
    smf:SetHyperlinksEnabled(true)
    smf:SetScript("OnHyperlinkClick", function(self, link, text, button)
        if SetItemRef then SetItemRef(link, text, button, self) end
    end)
    smf:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then self:ScrollUp() else self:ScrollDown() end
    end)
    win._logFrame = smf

    win._guildMoney = win._footer:CreateFontString(nil, "ARTWORK")
    win._guildMoney:SetPoint("RIGHT", -8, 0)
    CJKFont(win._guildMoney, Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, 12, "OUTLINE")
    win._withdrawLimit = win._footer:CreateFontString(nil, "ARTWORK")
    win._withdrawLimit:SetPoint("RIGHT", win._guildMoney, "LEFT", -12, 0)
    CJKFont(win._withdrawLimit, Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, 11, "OUTLINE")
    win._depositBtn = CreateTextButton(win._footer, ns.L["Deposit"], function()
        ShowMoneyPopup("deposit")
    end)
    win._depositBtn:SetPoint("LEFT", 8, 0)
    win._withdrawBtn = CreateTextButton(win._footer, ns.L["Withdraw"], function()
        if not CanWithdrawGuildBankMoney() then return end
        ShowMoneyPopup("withdraw")
    end)
    win._withdrawBtn:SetPoint("LEFT", win._depositBtn, "RIGHT", 4, 0)
    win._logsBtn = CreateTextButton(win._footer, ns.L["Logs"], function()
        bodyMode = (bodyMode == "log") and "grid" or "log"
        if bodyMode == "log" then QueryLog() end
        GuildWindow.Refresh()
    end)
    win._logsBtn:SetPoint("LEFT", win._withdrawBtn, "RIGHT", 4, 0)

    win._ownerSelect = Bags.OwnerSelect.Attach(win, {
        title = ns.L["Guilds"],
        tooltip = ns.L["View another guild bank"],
        listOwners = function()
            local cur = Storage.Store.GetCurrentGuildKey()
            if cur and not Storage.Store.GetGuild(cur) then cur = nil end
            return Bags.OwnerSelect.BuildOwnerList(Storage.Store.ListGuilds(), cur)
        end,
        current = ViewedGuildKey,
        onSelect = function(key)
            if Bags.GuildTakeover and Bags.GuildTakeover.IsLive()
                and key == Storage.Store.GetCurrentGuildKey() then
                GuildWindow.ShowLive()
            else
                GuildWindow.ShowCached(key)
            end
        end,
    })

    win:ApplyPosition()
    return win
end

local function RenderTabStrip(tabs)
    for _, btn in ipairs(tabButtons) do btn:Hide() end
    local sr, sg, sb = Helpers.GetSkinColors()
    local x = 0
    for i, entry in ipairs(tabs) do
        local btn = tabButtons[i]
        if not btn then
            btn = CreateTabButton()
            tabButtons[i] = btn
        end
        btn._entry = entry
        local label = "+"
        if entry.all then
            label = ns.L["All"]
        elseif not entry.purchase then
            label = (entry.name and entry.name ~= "") and entry.name
                or (ns.L["Tab"] .. " " .. tostring(entry.tab))
        end
        btn._label:SetText(label)
        local w = entry.purchase and TAB_H
            or math.max(40, math.ceil(btn._label:GetStringWidth()) + 14)
        btn:SetSize(w, TAB_H)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", win._tabStrip, "TOPLEFT", x, 0)
        local selected = (entry.all and selectedTab == "all")
            or (not entry.purchase and not entry.all and entry.tab == selectedTab)
        UIKit.UpdateBorderLines(btn, 1, sr, sg, sb, selected and 1 or 0.35)
        btn:Show()
        x = x + w + TAB_GAP
    end
    return x > 0 and (x - TAB_GAP) or 0
end

local function HideAllGridButtons()
    for _, byTab in pairs(liveButtons) do
        for _, btn in pairs(byTab) do btn:Hide() end
    end
    for _, byTab in pairs(cachedButtons) do
        for _, btn in pairs(byTab) do btn:Hide() end
    end
end

local function AcquireGridButton(tab, slot)
    local pool = liveMode and liveButtons or cachedButtons
    local byTab = pool[tab]
    if not byTab then byTab = {}; pool[tab] = byTab end
    local btn = byTab[slot]
    if not btn then
        btn = liveMode and Bags.ItemButtons.CreateGuildLive(win._body)
            or Bags.ItemButtons.CreateCached(win._body)
        byTab[slot] = btn
    end
    return btn
end

local function PlaceGridButton(tab, slot, entry, x, y, snappedSize)
    local btn = AcquireGridButton(tab, slot)
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
        Bags.ItemButtons.DressGuildLive(btn, tab, slot, entry, result)
    else
        Bags.ItemButtons.DressCached(btn, entry, result)
    end
    Bags.ItemButtons.SetFocusFlash(btn,
        focusItemID ~= nil and entry ~= nil and entry.itemID == focusItemID)
    Bags.ItemButtons.SetBagHighlight(btn,
        hoverTabIndex ~= nil and tab == hoverTabIndex)
    btn:Show()
end

local function RenderFooter()
    if not liveMode then
        win._guildMoney:Hide()
        win._withdrawLimit:Hide()
        win._depositBtn:Hide()
        win._withdrawBtn:Hide()
        win._logsBtn:Hide()
        return
    end
    local money = GetGuildBankMoney()
    if GetMoneyString then
        win._guildMoney:SetText(GetMoneyString(money, true))
    else
        win._guildMoney:SetText(tostring(money))
    end
    win._guildMoney:Show()
    if selectedTab == "all" then
        win._withdrawLimit:Hide()
    else
        local limit = GetGuildBankWithdrawMoney()
        if limit == -1 then
            win._withdrawLimit:SetText(ns.L["Limit: none"])
        elseif GetMoneyString then
            win._withdrawLimit:SetText(ns.L["Limit: "] .. GetMoneyString(limit, true))
        else
            win._withdrawLimit:SetText(ns.L["Limit: "] .. tostring(limit))
        end
        win._withdrawLimit:Show()
    end
    win._depositBtn:Show()
    win._withdrawBtn:Show()
    win._logsBtn._label:SetText(bodyMode == "log" and ns.L["Items"] or ns.L["Logs"])
    win._logsBtn:Show()
end

function GuildWindow.Refresh()
    if not win or not win:IsShown() then return end
    local s = GetSettings()
    local appearance = Bags.Chassis.ClampAppearance((s and s.appearance) or nil)

    local rec = GetGuildRecord()
    local opts = nil
    if liveMode then
        local viewable = {}
        for tab = 1, GetNumGuildBankTabs() do
            local _, _, isViewable = GetGuildBankTabInfo(tab)
            viewable[tab] = not not isViewable
        end
        opts = {
            liveViewable = viewable,
            canPurchase = GetGuildBankTabCost() ~= nil,
        }
    end
    local tabs = GuildWindow.BuildTabList(rec, opts)
    if focusItemID and selectedTab ~= "all" then
        local cur = rec and rec.tabs and selectedTab and rec.tabs[selectedTab]
        local found = false
        if cur and cur.slots then
            for _, e in pairs(cur.slots) do
                if e and e.itemID == focusItemID then found = true; break end
            end
        end
        if not found then
            local target = GuildWindow.FindTabForItem(rec, focusItemID)
            if target then selectedTab = target end
        end
    end
    if EnsureSelection(tabs) and liveMode and type(selectedTab) == "number" then
        SetCurrentGuildBankTab(selectedTab)
        QueryGuildBankTab(selectedTab)
    end
    local stripW = RenderTabStrip(tabs)

    local core = Helpers.GetCore()
    local snappedSize, snappedGap = appearance.iconSize, appearance.spacing
    local px = core and core.GetPixelSize and core:GetPixelSize(win) or nil
    if px and px > 0 then
        snappedSize = math.floor(appearance.iconSize / px + 0.5) * px
        snappedGap = math.floor(appearance.spacing / px + 0.5) * px
    end

    local cols = appearance.guildColumns or appearance.columns
    local renderAll = selectedTab == "all" and not (bodyMode == "log" and liveMode)
    local pending = {}
    local gridW, gridH
    if renderAll then
        local cells = {}
        for _, entry in ipairs(tabs) do
            if not entry.purchase and not entry.all then
                local t = rec and rec.tabs and rec.tabs[entry.tab]
                local size = t and t.size or 0
                for slot = 1, size do
                    cells[#cells + 1] = { tab = entry.tab, slot = slot,
                        entry = t.slots and t.slots[slot] or nil }
                end
            end
        end
        local layout = Bags.GridLayout.Compute(#cells, {
            columns = cols * 2, iconSize = snappedSize, spacing = snappedGap,
        })
        for i, c in ipairs(cells) do
            pending[#pending + 1] = { tab = c.tab, slot = c.slot,
                entry = c.entry,
                x = layout[i].x, y = layout[i].y - TAB_STRIP_H }
        end
        gridW, gridH = layout.width, layout.height
    else
        local tabRec = rec and rec.tabs and type(selectedTab) == "number"
            and rec.tabs[selectedTab] or nil
        local size = tabRec and tabRec.size or 0
        local slots = tabRec and tabRec.slots
        local layout = Bags.GridLayout.Compute(size, {
            columns = cols, iconSize = snappedSize, spacing = snappedGap,
        })
        for slot = 1, size do
            pending[#pending + 1] = { tab = selectedTab, slot = slot,
                entry = slots and slots[slot],
                x = layout[slot].x, y = layout[slot].y - TAB_STRIP_H }
        end
        gridW, gridH = layout.width, layout.height
    end

    win._ownerSelect:Update()
    local headerMinW = Bags.Chassis.MeasureHeaderWidth({
        win._title, win._ownerSelect, win._searchBox, win._close,
    }, { leftPad = 8, rightPad = 6, gap = 8 })
    local bodyW = math.max(gridW, stripW, headerMinW, MIN_BODY_W)
    local xOff = 0
    if bodyW > gridW and gridW > 0 then
        xOff = (bodyW - gridW) / 2
        if px and px > 0 then xOff = math.floor(xOff / px + 0.5) * px end
    end
    local bodyH = gridH
    if bodyMode == "log" then
        bodyH = math.max(bodyH, MIN_LOG_H)
    end
    win:SetContentSize(bodyW, TAB_STRIP_H + bodyH)

    HideAllGridButtons()
    if bodyMode == "log" and liveMode then
        win._logPanel:Show()
        RenderLog()
    else
        win._logPanel:Hide()
        for _, pl in ipairs(pending) do
            PlaceGridButton(pl.tab, pl.slot, pl.entry, pl.x + xOff, pl.y, snappedSize)
        end
    end

    RenderFooter()
end

local function Show()
    EnsureWindow()
    bodyMode = "grid"
    local wasShown = win:IsShown()
    win:Show()
    if not wasShown and PlaySound and SOUNDKIT and SOUNDKIT.GUILD_VAULT_OPEN then
        PlaySound(SOUNDKIT.GUILD_VAULT_OPEN)
    end
    GuildWindow.Refresh()
end

function GuildWindow.ShowLive()
    liveMode = true
    viewedGuildKey = nil
    Show()
end

function GuildWindow.ShowCached(guildKey)
    liveMode = false
    viewedGuildKey = guildKey
    Show()
end

function GuildWindow.OnBankClosed()
    GuildWindow.Hide()
end

function GuildWindow.Hide()
    focusItemID = nil
    if win and win:IsShown() then
        win:Hide()
        if PlaySound and SOUNDKIT and SOUNDKIT.GUILD_VAULT_CLOSE then
            PlaySound(SOUNDKIT.GUILD_VAULT_CLOSE)
        end
    end
end

function GuildWindow.FindTabForItem(rec, itemID)
    local map = rec and rec.tabs
    if not map then return nil end
    local ids = {}
    for tab in pairs(map) do ids[#ids + 1] = tab end
    table.sort(ids)
    for _, tab in ipairs(ids) do
        local t = map[tab]
        if t and t.slots then
            for _, e in pairs(t.slots) do
                if e and e.itemID == itemID then return tab end
            end
        end
    end
    return nil
end

function GuildWindow.FocusItem(itemID, guildKey)
    focusItemID = itemID
    if C_Timer and C_Timer.After then
        C_Timer.After(3, function()
            if focusItemID == itemID then
                focusItemID = nil
                ScheduleRefresh()
            end
        end)
    end
    local isCurrent = guildKey == nil or guildKey == Storage.Store.GetCurrentGuildKey()
    if isCurrent and Bags.GuildTakeover and Bags.GuildTakeover.IsLive
        and Bags.GuildTakeover.IsLive() then
        GuildWindow.ShowLive()
    else
        GuildWindow.ShowCached(isCurrent and nil or guildKey)
    end
end

function GuildWindow.IsShown()
    return win ~= nil and win:IsShown()
end

function GuildWindow.OnLogUpdate()
    if win and win:IsShown() and bodyMode == "log" and liveMode then
        RenderLog()
    end
end

function GuildWindow.GetFrame()
    return win
end

function GuildWindow.OnProfileChanged()
    if not win then return end
    win:ApplyPosition()
    if win:IsShown() then GuildWindow.Refresh() end
end

Storage.Bus.Subscribe("GuildChanged", function()
    ScheduleRefresh()
end)

Storage.Bus.Subscribe("GuildMoneyChanged", function()
    if liveMode then ScheduleRefresh() end
end)
