---------------------------------------------------------------------------
-- Bags views: the bank window. One grid per bank tab — character tabs
-- (bag IDs 6–11, cached on the character record) and warband tabs (12–16,
-- cached on the shared warband record) behind a tab strip under the header.
-- Two presentation modes:
--   LIVE   (at the banker, BankTakeover.IsLive()): full-interaction buttons
--          (ItemButtons.CreateLive, same SetID protocol as the bag window —
--          bank container IDs work identically), money deposit/withdraw,
--          auto-deposit, tab purchase and rename.
--   CACHED (browse anywhere): inert CreateCached/DressCached buttons,
--          live-only footer widgets hidden. The owner selector can point
--          this mode at ANY cached character's bankTabs (viewedCharacter);
--          warband tabs stay visible regardless — they're account-wide.
-- Data source is the Phase-1 cache; refresh is coalesced exactly like the
-- bag window (ScheduleRefresh owns the window's one-shot OnUpdate).
--
-- Close routing: the chassis onClose fires on ANY hide (X, ESC via
-- UISpecialFrames, cinematics), so the live-session close is routed from
-- there — BankTakeover.UserClosedWindow() no-ops when not live (server-
-- driven closes clear live first) and latches against re-entry.
---------------------------------------------------------------------------
-- luacheck: read globals ACCEPT CANCEL StaticPopup_OnClick BANK QUESTION_MARK_ICON MenuUtil bit
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags
local UIKit = ns.UIKit
local Helpers = ns.Helpers
local GetSettings = Helpers.CreateDBGetter("bags")

local BankWindow = {}
Bags.BankWindow = BankWindow

local CHAR_FIRST, CHAR_LAST = 6, 11   -- character bank tab bag IDs
local WB_FIRST, WB_LAST = 12, 16      -- warband (account) bank tab bag IDs
local SEGMENT_H = 22
local SEGMENT_GAP = 4
local TAB_H = 22
local TAB_GAP = 4
local TAB_STRIP_H = SEGMENT_H + SEGMENT_GAP + TAB_H + 6 -- reserved above grid

local win                 -- chassis window (lazy)
local liveMode = false    -- LIVE vs CACHED presentation
local viewedCharacter = nil -- nil = current character; key = offline browse
local activeBankType = Enum.BankType.Character
local selectedByBankType = {
    [Enum.BankType.Character] = nil,
    [Enum.BankType.Account] = nil,
}
local focusItemID = nil   -- search-everywhere landing flash (transient)
local tabButtons = {}     -- index → tab-strip button (pooled)
local liveHolders = {}    -- bagID → holder frame (live pool)
local liveButtons = {}    -- bagID → { [slot] = live button }
local cachedButtons = {}  -- bagID → { [slot] = cached button }
local searchText = ""
local matcher = nil
local searchTimer = nil
local hoverTabBagID = nil -- tab button under the cursor: its slots highlight

---------------------------------------------------------------------------
-- Pure: tab-strip assembly (headless-tested)
---------------------------------------------------------------------------

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
    if bankType == Enum.BankType.Account then return "Warband Bank" end
    return "Character Bank"
end

function BankWindow.BankTypeForFocus(opts)
    if opts and opts.warband then return Enum.BankType.Account end
    return Enum.BankType.Character
end

--- Assemble the ordered tab list from cache records.
--- rec: character record (uses rec.bankTabs[6..11]); warband: shared record
--- (uses warband.tabs[12..16]); opts: { canPurchaseChar, canPurchaseWarband,
--- viewChar, viewWarband } (live mode only — nil opts adds no purchase
--- markers). viewChar/viewWarband default to true when absent, so cached
--- mode (and existing pure tests) keep the browse-anywhere full list; false
--- drops that bank type's tabs AND its purchase marker.
--- Returns an array of { bagID, bankType, name, icon } for purchased tabs
--- (char tabs sorted first, then warband tabs), with a purchase marker
--- { purchase = true, bankType } appended after each type's own tabs.
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
        -- ≥2 real tabs → synthetic All entry leads the type (one tab has
        -- nothing to unify); selection sentinel is the string "all"
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

---------------------------------------------------------------------------
-- State helpers
---------------------------------------------------------------------------

-- The window's OnUpdate is owned exclusively by ScheduleRefresh (one-shot).
local ScheduleRefresh = Bags.Chassis.MakeScheduleRefresh(
    function() return win end,
    function() BankWindow.Refresh() end)

--- The character record the window renders: the viewed character's cached
--- record (offline browse), or the current character's. The warband record
--- is account-wide and never per-character — callers fetch it separately.
local function ViewedRecord()
    if viewedCharacter then
        return Bags.Store.GetCharacter(viewedCharacter)
    end
    return Bags.Store.GetCurrentCharacter()
end

local function GetTabRecord(bagID)
    -- "all" sentinel (and any other non-number) never maps to one tab
    if type(bagID) ~= "number" then return nil end
    if Bags.ScanBank.IsCharTab(bagID) then
        local rec = ViewedRecord()
        return rec and rec.bankTabs and rec.bankTabs[bagID] or nil
    end
    local warband = Bags.Store.GetWarband()
    return warband and warband.tabs and warband.tabs[bagID] or nil
end

local function GetSelectedBagID()
    return selectedByBankType[activeBankType]
end

local function SetSelectedBagID(bagID)
    selectedByBankType[activeBankType] = bagID
    -- the bag window's targeted-deposit catchers track the selected tab
    -- (GetSelectedLiveTab); a synthetic ping re-dresses them on tab switch
    Bags.Bus.Publish("BagsChanged", Bags.Store.GetCurrentCharacterKey(), {})
end

local function SetActiveBankType(bankType)
    activeBankType = bankType or Enum.BankType.Character
    if win and win:IsShown() then BankWindow.Refresh() end
    Bags.Bus.Publish("BagsChanged", Bags.Store.GetCurrentCharacterKey(), {})
end

--- Bank type of the SELECTED tab (footer money/auto-deposit context).
local function SelectedBankType()
    return activeBankType
end

--- Keep the selection when its tab still exists (the "all" sentinel stays
--- valid while its type has ≥2 real tabs), else fall back to the first
--- real tab in the list (nil when the cache has no tabs at all).
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
    -- Native server-side sort (ContainerDocumentation: SortBank(bankType)).
    -- The cross-tab QUI planner is parked for bank types: account-bank
    -- cross-tab cursor moves were rejected server-side in testing (sort
    -- stalled "before converging"); single-tab sorts keep the QUI planner.
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
        StartSortAllTabs() -- unified view: native whole-type sort
        return
    end
    Bags.SortExecutor.Start(SortScopeForBankType(activeBankType), nil, { tabID = tabID })
end

---------------------------------------------------------------------------
-- Popups (registered at click time, composer idiom)
---------------------------------------------------------------------------

local function ShowPurchasePopup(bankType)
    -- Doc: FetchNextPurchasableBankTabData(bankType) → PurchasableBankTabData
    -- { tabCost, canAfford, purchasePromptTitle/Body/Confirmation } or nil.
    local data = C_Bank.FetchNextPurchasableBankTabData(bankType)
    if not data then return end
    local cost = GetMoneyString and GetMoneyString(data.tabCost, true)
        or tostring(data.tabCost)
    -- No disabled state when not canAfford — the cost line is the signal;
    -- the purchase simply fails server-side if gold ran out meanwhile.
    StaticPopupDialogs["QUI_BANK_BUY_TAB"] = {
        text = (data.purchasePromptTitle or "") .. "\n"
            .. (data.purchasePromptBody or "") .. "\n\n" .. cost,
        button1 = ACCEPT,
        button2 = CANCEL,
        OnAccept = function()
            -- C_Bank.PurchaseBankTab has HasRestrictions (hardware-event
            -- rule): it must be called DIRECTLY from this OnAccept (the
            -- popup button's OnClick chain qualifies) — never deferred.
            C_Bank.PurchaseBankTab(bankType)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("QUI_BANK_BUY_TAB")
end

--- Argument shaping for C_Bank.UpdateBankTabSettings. Doc: tabName/tabIcon
--- are cstring (Nilable=false), depositFlags BagSlotFlags (Nilable=false);
--- BankTabData.icon is a fileID — cstring coerces the number, so the cached
--- fileID passes through. Blizzard's tab-settings menu falls back to
--- QUESTION_MARK_ICON when no icon is known; 0 is NOT a valid icon value.
function BankWindow.TabSettingsArgs(tab, text)
    local icon = tab.icon or QUESTION_MARK_ICON or "Interface\\Icons\\INV_Misc_QuestionMark"
    return text, icon, tab.depositFlags or 0
end

local function ShowRenamePopup(entry)
    -- Live-only (callers gate); cached metadata supplies the passthrough
    -- icon/depositFlags — fresh at the banker (BANKFRAME_OPENED refresh).
    local tab = GetTabRecord(entry.bagID)
    if not tab then return end
    local bankType, tabID = entry.bankType, entry.bagID
    StaticPopupDialogs["QUI_BANK_RENAME_TAB"] = {
        text = "Rename bank tab:",
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
            -- Doc: UpdateBankTabSettings(bankType, tabID, tabName, tabIcon,
            -- depositFlags) — all args required. Icon and depositFlags are
            -- passed through unchanged from the cache; a deposit-flags UI
            -- is deferred to a later phase.
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

-- Tab right-click: rename + the per-tab auto-deposit assignments Blizzard's
-- (hidden) bank UI normally owns. Flag bits per vendored
-- BagConstantsDocumentation Enum.BagSlotFlags (2..512); each toggle writes
-- C_Bank.UpdateBankTabSettings(bankType, tabID, name, icon, flags) and the
-- BANK_TAB_SETTINGS_UPDATED echo refreshes the cache.
local function ShowTabSettingsMenu(anchor, entry)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        ShowRenamePopup(entry)
        return
    end
    local F = Enum.BagSlotFlags or {}
    local FLAG_OPTIONS = {
        { flag = F.ClassEquipment or 2, label = "Equipment" },
        { flag = F.ClassConsumables or 4, label = "Consumables" },
        { flag = F.ClassProfessionGoods or 8, label = "Profession Goods" },
        { flag = F.ClassReagents or 128, label = "Reagents" },
        { flag = F.ClassJunk or 16, label = "Junk" },
        { flag = F.ClassQuestItems or 32, label = "Quest Items" },
        { flag = F.ExpansionCurrent or 256, label = "Current Expansion Only" },
        { flag = F.ExpansionLegacy or 512, label = "Legacy Expansion Only" },
    }
    MenuUtil.CreateContextMenu(anchor, function(_, root)
        root:CreateTitle((entry.name and entry.name ~= "") and entry.name or "Bank Tab")
        root:CreateButton("Rename...", function() ShowRenamePopup(entry) end)
        root:CreateTitle("Auto-Deposit Assignments")
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
                        (tab.name and tab.name ~= "") and tab.name or "Tab")
                    C_Bank.UpdateBankTabSettings(entry.bankType, entry.bagID,
                        name, icon, bit.bxor(tab.depositFlags or 0, o.flag))
                end)
        end
    end)
end

--- kind: "deposit" | "withdraw". Whole-gold input (v1), amount * 10000.
local function ShowMoneyPopup(kind, bankType)
    local depositing = (kind == "deposit")
    StaticPopupDialogs["QUI_BANK_MONEY"] = {
        text = depositing and "Deposit gold:" or "Withdraw gold:",
        button1 = ACCEPT,
        button2 = CANCEL,
        hasEditBox = true,
        maxLetters = 10,
        OnShow = function(self)
            local box = self.editBox or self.EditBox
            if box then box:SetText("") end
        end,
        OnAccept = function(self)
            local box = self.editBox or self.EditBox
            local text = box and box:GetText() or ""
            if not text:match("^%d+$") then return end
            local gold = tonumber(text)
            if not gold then return end
            gold = math.floor(gold)
            if gold <= 0 then return end -- numeric validation: reject <= 0
            local amount = gold * 10000  -- whole gold → copper
            -- Doc: Can*Money(bankType) → bool; *Money(bankType, amount).
            if depositing then
                if C_Bank.CanDepositMoney(bankType) then
                    C_Bank.DepositMoney(bankType, amount)
                end
            else
                if C_Bank.CanWithdrawMoney(bankType) then
                    C_Bank.WithdrawMoney(bankType, amount)
                end
            end
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
    StaticPopup_Show("QUI_BANK_MONEY")
end

---------------------------------------------------------------------------
-- Frame construction (lazy)
---------------------------------------------------------------------------

--- Tab-hover highlight: light up every rendered slot belonging to bagID
--- (nil clears). Sweeps the shown buttons directly — no re-render — and
--- PlaceGridButton applies the same state on refresh so a mid-hover
--- re-render can't strand or miss highlights.
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

local function CreateTabButton()
    local btn = Bags.Chassis.CreatePanelButton(win._tabStrip, true)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    UIKit.CreateBorderLines(btn)
    btn:SetScript("OnClick", function(self, mouseButton)
        local entry = self._entry
        if not entry then return end
        if entry.purchase then
            if mouseButton == "LeftButton" then
                ShowPurchasePopup(entry.bankType)
            end
            return
        end
        if entry.all then
            if mouseButton == "LeftButton" then
                activeBankType = entry.bankType or activeBankType
                SetSelectedBagID("all")
                BankWindow.Refresh()
            end
            return -- no rename on the synthetic All entry
        end
        if mouseButton == "RightButton" then
            -- rename + deposit assignments: live only
            if liveMode then ShowTabSettingsMenu(self, entry) end
            return
        end
        activeBankType = entry.bankType or activeBankType
        SetSelectedBagID(entry.bagID)
        -- leaving the All grid: drop the hover highlight (OnLeave won't
        -- fire while the cursor stays on the tab, and the single-tab view
        -- doesn't use it)
        ApplyTabHover(nil)
        BankWindow.Refresh()
    end)
    btn:SetScript("OnEnter", function(self)
        local entry = self._entry
        local tip = entry and (entry.purchase and "Purchase bank tab"
            or entry.all and "All tabs in one grid" or entry.name)
        if tip and tip ~= "" then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tip)
            if entry and not entry.purchase and not entry.all and liveMode then
                GameTooltip:AddLine("Right-click: rename + auto-deposit assignments.",
                    1, 1, 1, true)
            end
            GameTooltip:Show()
        end
        -- membership highlight: light up this tab's slots. Only meaningful
        -- on the unified All grid — a single open tab already shows just
        -- its own slots, so highlighting there is noise.
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
        title = BANK or "Bank",
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
            -- debounce: re-render at most once per 0.1s typing pause, not per
            -- keystroke (the timer resets while the user keeps typing)
            if searchTimer then searchTimer:Cancel() end
            searchTimer = C_Timer.NewTimer(0.1, function()
                searchTimer = nil
                ScheduleRefresh()
            end)
        end,
        onClose = function(w)
            w:SetScript("OnUpdate", nil)
            w._updateScheduled = false
            -- ANY hide of a live session (X, ESC, cinematic) must close the
            -- bank server-side. UserClosedWindow no-ops when not live —
            -- server-driven closes clear live BEFORE OnBankClosed → Hide().
            if Bags.BankTakeover and Bags.BankTakeover.IsLive() then
                Bags.BankTakeover.UserClosedWindow()
            end
        end,
        -- the X button routes through the sound path; the live-session close
        -- itself rides the OnHide → onClose chain above
        onUserClose = function() BankWindow.Hide() end,
        compactSearch = true,
        onChromeChanged = function() ScheduleRefresh() end,
    })

    -- bank-type segment + tab strip: both live at the top of the body; the
    -- grid renders below them (TAB_STRIP_H reserved in SetContentSize)
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

    -- footer (live mode only; hidden while browsing cached)
    win._bankMoney = win._footer:CreateFontString(nil, "ARTWORK")
    win._bankMoney:SetPoint("RIGHT", -8, 0)
    win._bankMoney:SetFont(Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, 12, "OUTLINE")
    -- Footer buttons: anchored dynamically per RenderFooter (the gold pair
    -- and Auto-Deposit hide on bank types that don't support them).
    win._depositBtn = CreateFooterButton("Deposit Gold", function()
        local bankType = SelectedBankType()
        if not C_Bank.CanDepositMoney(bankType) then return end
        ShowMoneyPopup("deposit", bankType)
    end, "Put gold into this bank's shared pool (the amount on the right).")
    win._withdrawBtn = CreateFooterButton("Withdraw Gold", function()
        local bankType = SelectedBankType()
        if not C_Bank.CanWithdrawMoney(bankType) then return end
        ShowMoneyPopup("withdraw", bankType)
    end, "Take gold out of this bank's shared pool.")
    win._autoBtn = CreateFooterButton("Auto-Deposit", function()
        local bankType = SelectedBankType()
        -- Doc: DoesBankTypeSupportAutoDeposit(bankType) → bool gates
        -- AutoDepositItemsIntoBank(bankType).
        if C_Bank.DoesBankTypeSupportAutoDeposit(bankType) then
            C_Bank.AutoDepositItemsIntoBank(bankType)
        end
    end, "Blizzard's assignment sweep: moves items from your bags into tabs"
        .. " according to each tab's auto-deposit assignments"
        .. " (right-click a tab to set those).")
    -- Deposit All: warband-tab-only (RenderFooter gates on the selected
    -- tab's bank type); Transfers.DepositAllToWarband needs the live
    -- session the footer's live-mode gate already guarantees
    win._depositAllBtn = CreateFooterButton("Deposit All", function()
        if not Bags.Transfers.IsRunning() then
            Bags.Transfers.DepositAllToWarband()
        end
    end, "Deposit everything in your bags that the warband bank accepts"
        .. " (soulbound items stay).")
    win._depositReagentsBtn = CreateFooterButton("Deposit Reagents", function()
        if not Bags.Transfers.IsRunning() then
            Bags.Transfers.DepositReagents(SelectedBankType())
        end
    end, "Deposit only crafting reagents from your bags into this bank.")

    -- header: Sort button left of the search box (tab-button construction:
    -- dark bg + centered label + QUI border lines recolored per Refresh;
    -- font set at creation like the footer texts). Live-mode only — the
    -- executor's bank scope needs an open session (Refresh gates shown).
    local sort = Bags.Chassis.CreatePanelButton(win._header, false)
    -- compact 18×18 icon button (Blizzard autosort atlas, vendored
    -- ContainerFrame.xml:314 / BankFrame.xml:264); tooltip carries the verb
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
                root:CreateButton("Sort all " .. BankWindow.BankTypeLabel(activeBankType)
                    .. " tabs (Blizzard sort)", StartSortAllTabs)
            end)
            return
        end
        StartSortSelectedTab()
    end)
    sort:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Sort this " .. BankWindow.BankTypeLabel(activeBankType)
            .. " tab — " .. Bags.Chassis.SortModeText())
        GameTooltip:AddLine("Right-click for sort options.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    sort:SetScript("OnLeave", function() GameTooltip:Hide() end)
    sort:Hide()
    win._sortBtn = sort

    -- header: owner selector right of the title; picking an alt renders
    -- their cached bank tabs (warband tabs stay — they're account-wide)
    win._ownerSelect = Bags.OwnerSelect.Attach(win, {
        title = "Characters",
        tooltip = "View another character's bank",
        listOwners = function()
            return Bags.OwnerSelect.BuildOwnerList(
                Bags.Store.ListCharacters(), Bags.Store.GetCurrentCharacterKey())
        end,
        current = function()
            return viewedCharacter or Bags.Store.GetCurrentCharacterKey()
        end,
        onSelect = function(key) BankWindow.SetViewedCharacter(key) end,
    })

    win:ApplyPosition()
    return win
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------

--- Lay out the tab strip from the assembled list; returns the strip width.
local function RenderTabStrip(tabs)
    for _, btn in ipairs(tabButtons) do btn:Hide() end
    local sr, sg, sb = Helpers.GetSkinColors()
    local selectedBagID = GetSelectedBagID()
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
            label = "All"
        elseif not entry.purchase then
            label = (entry.name and entry.name ~= "") and entry.name or "Tab"
        end
        btn._label:SetText(label)
        local w = entry.purchase and TAB_H
            or math.max(40, math.ceil(btn._label:GetStringWidth()) + 14)
        btn:SetSize(w, TAB_H)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", win._tabStrip, "TOPLEFT", x, 0)
        -- selected tab gets the full-strength accent border
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

--- Shared place+dress for one grid cell (single-tab and All render paths).
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
            result = (m ~= false) -- pending counts as visible
        else
            result = false -- empty slots dim while a search is active
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

-- Footer row metrics: 18px buttons with 2px top/bottom breathing room and
-- a 4px row gap make each row exactly 22px — one row reproduces the
-- chassis default FOOTER_H, so wide windows look unchanged.
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
    -- Doc: FetchDepositedMoney(bankType) → WOWMONEY (non-nilable).
    local money = C_Bank.FetchDepositedMoney(bankType)
    if GetMoneyString then
        win._bankMoney:SetText(GetMoneyString(money, true))
    else
        win._bankMoney:SetText(tostring(money))
    end
    win._bankMoney:Show()

    -- Visibility gates: hidden buttons (gold pair on a moneyless bank
    -- type, warband-only actions on the character bank) leave no gap.
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

    -- Row-wrap layout: buttons flow left-to-right and wrap to a new row
    -- when the window is too narrow, instead of running under the gold
    -- text. The gold text rides the right edge of the last button row when
    -- it fits beside those buttons, otherwise it gets its own row.
    local availW = win:GetWidth() - FOOTER_PAD_X * 2
    local moneyW = win._bankMoney:GetStringWidth() or 0
    local rows = { {} } -- rows of buttons; parallel rowW tracks used width
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
    -- center the gold text in its row (offset measured from footer center
    -- so the single-row case keeps the original RIGHT/-8 anchor exactly)
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

    -- tab list (purchase buttons are live-only; doc: CanPurchaseBankTab(bankType) → bool).
    -- rec follows the owner selector; the warband record is account-wide,
    -- so its tabs REMAIN visible while viewing another character offline.
    local rec = ViewedRecord()
    local warband = Bags.Store.GetWarband()
    local opts = { bankType = activeBankType }
    if liveMode then
        -- Doc: CanViewBank(bankType) → bool (AllowedWhenUntainted). A
        -- character-only banker can't view the warband side (and vice
        -- versa), so live mode drops unviewable tab types. Cached mode
        -- keeps the active bank-type split while browsing stored data.
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
    -- search-focus tab autoselect: when a navigation landed an item that
    -- isn't on the selected tab, jump to the first tab that holds it (char
    -- tabs first, then warband — FindTabForItem). One-shot per focus.
    -- The All view already shows every tab, so it never jumps away.
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

    -- header Sort: live-mode only (cached browsing has no session to move
    -- items in); border tracks the skin like the tab strip
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

    -- Pixel-snap iconSize/spacing to the window's physical pixel grid before
    -- layout (actionbars precedent: fractional physical-pixel cells make the
    -- renderer round each button's edges independently → uneven gaps at
    -- non-1.0 scales). Snapping at the source keeps every derived offset
    -- inherently pixel-aligned.
    local core = Helpers.GetCore()
    local snappedSize, snappedGap = appearance.iconSize, appearance.spacing
    local px = core and core.GetPixelSize and core:GetPixelSize(win) or nil
    if px and px > 0 then
        snappedSize = math.floor(appearance.iconSize / px + 0.5) * px
        snappedGap = math.floor(appearance.spacing / px + 0.5) * px
    end

    -- hide both pools (a mode/tab switch must not strand the other pool's
    -- buttons), then place + dress the selection: one tab, or — "all"
    -- sentinel — every purchased tab of the active type under per-tab
    -- section headers
    local selectedBagID = GetSelectedBagID()
    HideAllGridButtons()
    local cols = appearance.bankColumns or appearance.columns
    -- two-pass render: collect placements first so the centering offset
    -- (final width vs grid width) is known before any SetPoint
    local pending = {} -- { bagID, slot, entry, x, y }
    local gridW, gridH
    if selectedBagID == "all" then
        -- Unified flow: every tab's slots flatten into ONE continuous grid
        -- at DOUBLE the per-tab column count — width stays bounded and the
        -- merge halves the height versus stacking per-tab sections. Tab
        -- membership stays discoverable via the tab-hover highlight.
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

---------------------------------------------------------------------------
-- Public surface
---------------------------------------------------------------------------

-- Open/close sounds mirror the bag window's gate (only on the actual shown
-- transition) but use the main-menu pair so the bank is audibly distinct.
local function Show()
    EnsureWindow()
    local wasShown = win:IsShown()
    win:Show()
    if not wasShown and PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN then
        PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
    end
    BankWindow.Refresh()
end

--- At the banker (BankTakeover.OnBankOpened): live buttons + money row.
--- The session is always the current character's — drop any offline view.
function BankWindow.ShowLive()
    liveMode = true
    viewedCharacter = nil
    Show()
end

--- Browse anywhere: inert cached buttons, live-only widgets hidden.
--- Opens on your own cached bank; the owner selector switches from there.
function BankWindow.ShowCached()
    liveMode = false
    viewedCharacter = nil
    Show()
end

--- Owner-selector entry: nil/current key → back to your own bank (live
--- again only when a bank session is actually open); any other cached
--- character FORCES cached presentation even at a banker — the open
--- session can only operate on the current character's items, so live
--- buttons over an alt's cache would lie.
function BankWindow.SetViewedCharacter(key)
    if key == nil or key == Bags.Store.GetCurrentCharacterKey() then
        viewedCharacter = nil
        liveMode = Bags.BankTakeover ~= nil and Bags.BankTakeover.IsLive() or false
    else
        viewedCharacter = key
        liveMode = false
    end
    BankWindow.Refresh()
end

--- BANKFRAME_CLOSED (server-driven). v1: hide; a "stay open, fold back to
--- cached mode" refinement is a later phase.
function BankWindow.OnBankClosed()
    BankWindow.Hide()
end

function BankWindow.Hide()
    focusItemID = nil
    if win and win:IsShown() then
        win:Hide() -- OnHide → chassis onClose routes the live-session close
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_CLOSE then
            PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
        end
    end
end

--- First tab holding itemID: char tabs (ascending bag ID), then warband
--- tabs. Pure — drives the search-focus tab autoselect. → bagID or nil.
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

--- Search-everywhere navigation: open the right bank view (live at an open
--- session for the current character, cached otherwise; another character's
--- key forces their cached view) and pulse + tab-select the item. Focus is
--- transient — cleared on Hide and ~3s after landing.
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
    -- SetViewedCharacter resolves live-vs-cached and refreshes; route the
    -- not-yet-shown case through the public show paths first.
    if not BankWindow.IsShown() then
        if Bags.BankTakeover and Bags.BankTakeover.IsLive
            and Bags.BankTakeover.IsLive()
            and (ownerKey == nil or ownerKey == Bags.Store.GetCurrentCharacterKey()) then
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

--- The specific tab a live bank session is showing, or nil (window hidden,
--- cached browse, or the "all" view). → tabBagID, bankType. The bag
--- window's targeted right-click deposit reads this.
function BankWindow.GetSelectedLiveTab()
    if not (win and win:IsShown() and liveMode) then return nil end
    local sel = GetSelectedBagID()
    if type(sel) == "number" then return sel, activeBankType end
    return nil
end

function BankWindow.IsShown()
    return win ~= nil and win:IsShown()
end

--- The window frame, or nil before first show (the bank takeover keeps its
--- name-proxy opener; this accessor is for callers that need the real frame).
function BankWindow.GetFrame()
    return win
end

--- Profile switched while the module stays enabled: re-anchor + re-render.
function BankWindow.OnProfileChanged()
    if not win then return end
    win:ApplyPosition()
    if win:IsShown() then BankWindow.Refresh() end
end

-- data refresh: coalesced re-render on bank cache changes (tab metadata
-- changes — purchase, rename — also land here via the scanner's drain)
Bags.Bus.Subscribe("BankChanged", function()
    ScheduleRefresh()
end)

Bags.Bus.Subscribe("WarbandChanged", function()
    ScheduleRefresh()
end)

-- money freshness: the live footer re-fetches FetchDepositedMoney on any
-- money event (PLAYER_MONEY / PLAYER_GUILD_UPDATE / ACCOUNT_MONEY). Cached
-- mode renders no money row, so the ping is live-only; ScheduleRefresh
-- already no-ops while hidden.
Bags.Bus.Subscribe("MoneyChanged", function()
    if liveMode then ScheduleRefresh() end
end)
