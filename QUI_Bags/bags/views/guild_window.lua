---------------------------------------------------------------------------
-- Bags views: the guild bank window. One 98-slot grid per guild tab
-- (tabs 1..MAX_GUILDBANK_TABS, cached on the per-guild record) behind a
-- tab strip under the header. Two presentation modes:
--   LIVE   (at the vault, GuildTakeover.IsLive()): cursor-API guild buttons
--          (ItemButtons.CreateGuildLive — _tab/_slot protocol, no bag IDs),
--          money deposit/withdraw with per-tab withdraw limits, tab
--          purchase and rename, item/money log panel.
--   CACHED (browse anywhere): inert CreateCached/DressCached buttons,
--          live-only footer widgets hidden, no log access (log data is
--          server-resident and only streams at the vault). The owner
--          selector / ShowCached(guildKey) can point this mode at ANY
--          cached guild record, not just the character's own.
-- Data source is the per-guild cache (scan_guild drains at the vault);
-- refresh is coalesced exactly like the bank window (ScheduleRefresh owns
-- the window's one-shot OnUpdate).
--
-- Close routing: the chassis onClose fires on ANY hide (X, ESC via
-- UISpecialFrames, cinematics), so the live-session close is routed from
-- there — GuildTakeover.UserClosedWindow() no-ops when not live and latches
-- against re-entry (same shape as the bank window).
---------------------------------------------------------------------------
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
local UIKit = ns.UIKit
local Helpers = ns.Helpers
local GetSettings = Helpers.CreateDBGetter("bags")

local GuildWindow = {}
Bags.GuildWindow = GuildWindow

-- MAX_GUILDBANK_TABS = 8 (vendored Blizzard_FrameXMLBase/Constants.lua:308);
-- the fallback keeps the pure BuildTabList headless-testable.
local MAX_TABS = MAX_GUILDBANK_TABS or 8
local TAB_H = 22
local TAB_GAP = 4
local TAB_STRIP_H = TAB_H + 6         -- reserved above the grid in the body
local LOG_MODE_ROW_H = 20             -- item/money switch row in the log panel
local MIN_BODY_W = 320                -- floor when the cache has no tabs yet
local MIN_LOG_H = 240                 -- log panel floor (grid height wins when bigger)

local win                  -- chassis window (lazy)
local liveMode = false     -- LIVE vs CACHED presentation
local viewedGuildKey = nil -- nil = current guild; key = offline browse
local selectedTab = nil    -- currently selected guild tab index (1..8)
local focusItemID = nil    -- search-everywhere landing flash (transient)
local bodyMode = "grid"    -- "grid" | "log" (footer Logs toggle; live only)
local logMode = "item"     -- "item" | "money" (log panel switch row)
local tabButtons = {}      -- index → tab-strip button (pooled)
local liveButtons = {}     -- tab → { [slot] = guild live button }
local cachedButtons = {}   -- tab → { [slot] = cached button }
local searchText = ""
local matcher = nil
local searchTimer = nil

---------------------------------------------------------------------------
-- Pure: tab-strip assembly (headless-tested)
---------------------------------------------------------------------------

--- Assemble the ordered tab list from the guild cache record.
--- rec: guild record (uses rec.tabs[1..MAX_TABS], scan_guild shape:
--- { size, slots, name, icon, withdrawals }); opts (live mode only):
--- { liveViewable = {[tab]=bool}, canPurchase }. liveViewable[tab] == false
--- drops that tab (live GetGuildBankTabInfo says non-viewable); absent keys
--- default to viewable, so cached mode (nil opts) keeps the browse-anywhere
--- full list. canPurchase appends a { purchase = true } marker last.
--- Returns an array of { tab, name, icon, withdrawals }.
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
    end
    if opts and opts.canPurchase then
        list[#list + 1] = { purchase = true }
    end
    return list
end

---------------------------------------------------------------------------
-- State helpers
---------------------------------------------------------------------------

-- The window's OnUpdate is owned exclusively by ScheduleRefresh (one-shot).
local function ScheduleRefresh()
    if win and win:IsShown() and not win._updateScheduled then
        win._updateScheduled = true
        win:SetScript("OnUpdate", function(self)
            self:SetScript("OnUpdate", nil)
            self._updateScheduled = false
            GuildWindow.Refresh()
        end)
    end
end

--- The guild record the window renders: the viewed guild (offline browse
--- via the owner selector / ShowCached key), falling back to the current
--- character's guild.
local function ViewedGuildKey()
    return viewedGuildKey or Bags.Store.GetCurrentGuildKey()
end

local function GetGuildRecord()
    local key = ViewedGuildKey()
    return key and Bags.Store.GetGuild(key) or nil
end

--- Keep the selection when its tab still exists, else fall back to the
--- first real tab in the list (nil when the cache has no tabs at all).
--- Returns true when the selection changed (caller re-syncs the server tab).
local function EnsureSelection(tabs)
    local first = nil
    for _, entry in ipairs(tabs) do
        if not entry.purchase then
            first = first or entry.tab
            if entry.tab == selectedTab then return false end
        end
    end
    local changed = selectedTab ~= first
    selectedTab = first
    return changed
end

--- Prime the server-side log for the current log mode. Item log is per
--- selected tab; money log rides the MAX_TABS+1 convention (vendored
--- Blizzard_GuildBankUI.lua:600-605). GUILDBANKLOG_UPDATE then routes to
--- OnLogUpdate via bags.lua.
local function QueryLog()
    if not liveMode then return end
    if logMode == "money" then
        QueryGuildBankLog(MAX_TABS + 1)
    elseif selectedTab then
        QueryGuildBankLog(selectedTab)
    end
end

---------------------------------------------------------------------------
-- Popups (registered at click time, composer idiom)
---------------------------------------------------------------------------

local function ShowPurchasePopup()
    -- GetGuildBankTabCost() → copper, nil when all tabs are bought
    -- (vendored Blizzard_GuildBankUI.lua:252-268); callers gate, this
    -- re-checks (cost can vanish between render and click).
    local cost = GetGuildBankTabCost()
    if not cost then return end
    local costText = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString
        and C_CurrencyInfo.GetCoinTextureString(cost) or tostring(cost)
    StaticPopupDialogs["QUI_GUILDBANK_BUY_TAB"] = {
        text = "Purchase guild bank tab?\n\n" .. costText,
        button1 = ACCEPT,
        button2 = CANCEL,
        OnAccept = function()
            -- BuyGuildBankTab() is called DIRECTLY from this OnAccept (the
            -- popup button's OnClick chain qualifies as the hardware event)
            -- — Blizzard's CONFIRM_BUY_GUILDBANK_TAB does exactly this
            -- (GameDialogDefs.lua:490-496); never defer it.
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
    -- Live-only, CanEditGuildBankTabInfo-gated (callers gate). The cached
    -- icon is passed through unchanged — SetGuildBankTabInfo(tab, name,
    -- icon) takes all three (vendored Blizzard_GuildBankUI.lua:901); an
    -- icon-picker UI is deferred (Blizzard uses the full IconSelector).
    local rec = GetGuildRecord()
    local tab = rec and rec.tabs and rec.tabs[entry.tab]
    if not tab then return end
    local tabIndex = entry.tab
    StaticPopupDialogs["QUI_GUILDBANK_RENAME_TAB"] = {
        text = "Rename guild bank tab:",
        button1 = ACCEPT,
        button2 = CANCEL,
        hasEditBox = true,
        maxLetters = 15, -- guild tab names cap shorter than bank tabs
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

--- kind: "deposit" | "withdraw". Whole-gold input (v1), amount * 10000.
local function ShowMoneyPopup(kind)
    local depositing = (kind == "deposit")
    StaticPopupDialogs["QUI_GUILDBANK_MONEY"] = {
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
            if depositing then
                -- no Can* API for guild deposits; Blizzard's GUILDBANK_DEPOSIT
                -- popup deposits unconditionally (GameDialogDefs.lua:471-489)
                DepositGuildBankMoney(amount)
            else
                if CanWithdrawGuildBankMoney() then
                    WithdrawGuildBankMoney(amount)
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
    StaticPopup_Show("QUI_GUILDBANK_MONEY")
end

---------------------------------------------------------------------------
-- Log rendering (live only; ScrollingMessageFrame — house precedent:
-- modules/chat/display_layer.lua:131; Blizzard's own guild log is one too,
-- Blizzard_GuildBankUI.xml:682)
---------------------------------------------------------------------------

local function ColorName(name)
    name = name or UNKNOWN or "Unknown"
    return (NORMAL_FONT_COLOR_CODE or "|cffffd200") .. name
        .. (FONT_COLOR_CODE_CLOSE or "|r")
end

local function LogTimeSuffix(year, month, day, hour)
    -- GUILD_BANK_LOG_TIME + RecentTimeDate (UIParent.lua:354) — the exact
    -- pair Blizzard appends (Blizzard_GuildBankUI.lua:775); plain fallback
    -- (no timestamp) when either global is missing.
    if GUILD_BANK_LOG_TIME and RecentTimeDate then
        return GUILD_BANK_LOG_TIME:format(RecentTimeDate(year, month, day, hour))
    end
    return ""
end

--- Item log for the selected tab (GetGuildBankTransaction shape and format
--- globals per vendored Blizzard_GuildBankUI.lua:748-778). Each format
--- global is guarded with a plain-text fallback.
local function RenderItemLog(smf)
    if not selectedTab then return end
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
            -- GetGuildBankTabInfo's first return is the tab name
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

-- transaction type → format global taking (name, money); buyTab and
-- depositSummary are special-cased below (different arities/branches).
-- Built lazily so missing globals fall through to the plain-text fallback.
local function MoneyLogFormat(kind)
    if kind == "deposit" then return GUILDBANK_DEPOSIT_MONEY_FORMAT end
    if kind == "withdraw" then return GUILDBANK_WITHDRAW_MONEY_FORMAT end
    if kind == "repair" then return GUILDBANK_REPAIR_MONEY_FORMAT end
    if kind == "withdrawForTab" then return GUILDBANK_WITHDRAWFORTAB_MONEY_FORMAT end
    if kind == "buyRename" then return GUILDBANK_GUILD_RENAME_PURCHASE end
    if kind == "refundRename" then return GUILDBANK_GUILD_RENAME_REFUND end
    return nil
end

--- Money log (GetGuildBankMoneyTransaction shape and format globals per
--- vendored Blizzard_GuildBankUI.lua:780-819).
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
                or (name .. " " .. tostring(kind) .. " " .. money) -- plain fallback
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

---------------------------------------------------------------------------
-- Frame construction (lazy)
---------------------------------------------------------------------------

local function CreateTabButton()
    local btn = CreateFrame("Button", nil, win._tabStrip)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(0, 0, 0, 0.35)
    UIKit.DisablePixelSnap(bg)
    btn._label = btn:CreateFontString(nil, "ARTWORK")
    btn._label:SetPoint("CENTER", 0, 0)
    btn._label:SetFont(Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, 11, "OUTLINE")
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
        if mouseButton == "RightButton" then
            -- rename: live only + permission-gated (Blizzard parity:
            -- CanEditGuildBankTabInfo at Blizzard_GuildBankUI.lua:628)
            if liveMode and CanEditGuildBankTabInfo() then
                ShowRenamePopup(entry)
            end
            return
        end
        selectedTab = entry.tab
        if liveMode then
            -- withdraw limits are per-tab server-side current-tab state:
            -- sync the server tab, then re-query its data
            SetCurrentGuildBankTab(entry.tab)
            QueryGuildBankTab(entry.tab)
            if bodyMode == "log" and logMode == "item" then
                QueryGuildBankLog(entry.tab)
            end
        end
        GuildWindow.Refresh()
    end)
    btn:SetScript("OnEnter", function(self)
        local entry = self._entry
        if not entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if entry.purchase then
            GameTooltip:SetText("Purchase guild bank tab")
        else
            local label = (entry.name and entry.name ~= "") and entry.name
                or ("Tab " .. tostring(entry.tab))
            GameTooltip:SetText(label)
            if liveMode then
                -- fresh per-tab meta at the vault: viewability, deposit
                -- permission, remaining withdrawals (-1 = unlimited)
                local _, _, isViewable, canDeposit, _, remainingWithdrawals =
                    GetGuildBankTabInfo(entry.tab)
                GameTooltip:AddLine(isViewable and "Viewable" or "Not viewable", 0.8, 0.8, 0.8)
                GameTooltip:AddLine(canDeposit and "Deposits allowed" or "No deposits", 0.8, 0.8, 0.8)
                if remainingWithdrawals == -1 then
                    GameTooltip:AddLine("Withdrawals: no limit", 0.8, 0.8, 0.8)
                elseif remainingWithdrawals then
                    GameTooltip:AddLine("Withdrawals left: " .. remainingWithdrawals, 0.8, 0.8, 0.8)
                end
            elseif entry.withdrawals then
                -- cached copy from the last vault visit
                if entry.withdrawals == -1 then
                    GameTooltip:AddLine("Withdrawals: no limit", 0.8, 0.8, 0.8)
                else
                    GameTooltip:AddLine("Withdrawals left: " .. entry.withdrawals, 0.8, 0.8, 0.8)
                end
            end
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return btn
end

local function CreateTextButton(parent, label, onClick)
    local btn = CreateFrame("Button", nil, parent)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(0, 0, 0, 0.35)
    UIKit.DisablePixelSnap(bg)
    btn._label = btn:CreateFontString(nil, "ARTWORK")
    btn._label:SetPoint("CENTER", 0, 0)
    btn._label:SetFont(Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, 11, "OUTLINE")
    btn._label:SetText(label)
    btn:SetSize(math.max(40, math.ceil(btn._label:GetStringWidth()) + 12), 18)
    btn:SetScript("OnClick", onClick)
    return btn
end

local function EnsureWindow()
    if win then return win end
    win = Bags.Chassis.CreateWindow({
        name = "QUI_GuildBankWindow",
        title = GUILD_BANK or "Guild Bank",
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
            -- vault server-side. UserClosedWindow no-ops when not live —
            -- server-driven closes clear live BEFORE OnBankClosed → Hide().
            if Bags.GuildTakeover and Bags.GuildTakeover.IsLive() then
                Bags.GuildTakeover.UserClosedWindow()
            end
        end,
        -- the X button routes through the sound path; the live-session close
        -- itself rides the OnHide → onClose chain above
        onUserClose = function() GuildWindow.Hide() end,
        compactSearch = true,
        onChromeChanged = function() ScheduleRefresh() end,
    })

    -- tab strip: header-adjacent row at the top of the body; the grid/log
    -- renders below it (TAB_STRIP_H reserved in SetContentSize)
    local strip = CreateFrame("Frame", nil, win._body)
    strip:SetPoint("TOPLEFT", 0, 0)
    strip:SetPoint("TOPRIGHT", 0, 0)
    strip:SetHeight(TAB_H)
    win._tabStrip = strip

    -- log panel (hidden until the footer Logs toggle; live only)
    local log = CreateFrame("Frame", nil, win._body)
    log:SetPoint("TOPLEFT", 0, -TAB_STRIP_H)
    log:SetPoint("BOTTOMRIGHT", 0, 0)
    log:Hide()
    win._logPanel = log

    win._itemLogBtn = CreateTextButton(log, "Item Log", function()
        logMode = "item"
        QueryLog()
        GuildWindow.Refresh()
    end)
    win._itemLogBtn:SetPoint("TOPLEFT", 0, 0)
    win._moneyLogBtn = CreateTextButton(log, "Money Log", function()
        logMode = "money"
        QueryLog()
        GuildWindow.Refresh()
    end)
    win._moneyLogBtn:SetPoint("LEFT", win._itemLogBtn, "RIGHT", 4, 0)

    -- ScrollingMessageFrame (house precedent: chat display_layer.lua:131)
    local smf = CreateFrame("ScrollingMessageFrame", nil, log)
    smf:SetPoint("TOPLEFT", 0, -LOG_MODE_ROW_H - 4)
    smf:SetPoint("BOTTOMRIGHT", 0, 0)
    smf:SetFontObject(ChatFontNormal)
    smf:SetJustifyH("LEFT")
    smf:SetFading(false)
    smf:SetMaxLines(128) -- the server caps guild logs well below this
    smf:SetHyperlinksEnabled(true)
    smf:SetScript("OnHyperlinkClick", function(self, link, text, button)
        if SetItemRef then SetItemRef(link, text, button, self) end
    end)
    smf:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then self:ScrollUp() else self:ScrollDown() end
    end)
    win._logFrame = smf

    -- footer (live mode only; hidden while browsing cached)
    win._guildMoney = win._footer:CreateFontString(nil, "ARTWORK")
    win._guildMoney:SetPoint("RIGHT", -8, 0)
    win._guildMoney:SetFont(Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, 12, "OUTLINE")
    win._withdrawLimit = win._footer:CreateFontString(nil, "ARTWORK")
    win._withdrawLimit:SetPoint("RIGHT", win._guildMoney, "LEFT", -12, 0)
    win._withdrawLimit:SetFont(Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, 11, "OUTLINE")
    win._depositBtn = CreateTextButton(win._footer, "Deposit", function()
        ShowMoneyPopup("deposit")
    end)
    win._depositBtn:SetPoint("LEFT", 8, 0)
    win._withdrawBtn = CreateTextButton(win._footer, "Withdraw", function()
        if not CanWithdrawGuildBankMoney() then return end
        ShowMoneyPopup("withdraw")
    end)
    win._withdrawBtn:SetPoint("LEFT", win._depositBtn, "RIGHT", 4, 0)
    win._logsBtn = CreateTextButton(win._footer, "Logs", function()
        bodyMode = (bodyMode == "log") and "grid" or "log"
        if bodyMode == "log" then QueryLog() end
        GuildWindow.Refresh()
    end)
    win._logsBtn:SetPoint("LEFT", win._withdrawBtn, "RIGHT", 4, 0)

    -- header: owner selector right of the title; picking another cached
    -- guild renders it offline. The "(current)" mark only applies when the
    -- character's own guild has a cache record — an uncached current guild
    -- is unselectable (nothing to render), so nil is passed instead.
    win._ownerSelect = Bags.OwnerSelect.Attach(win, {
        title = "Guilds",
        tooltip = "View another guild bank",
        listOwners = function()
            local cur = Bags.Store.GetCurrentGuildKey()
            if cur and not Bags.Store.GetGuild(cur) then cur = nil end
            return Bags.OwnerSelect.BuildOwnerList(Bags.Store.ListGuilds(), cur)
        end,
        current = ViewedGuildKey,
        onSelect = function(key)
            -- selecting your own guild while the vault session is open
            -- returns to live mode; everything else is an offline render
            if Bags.GuildTakeover and Bags.GuildTakeover.IsLive()
                and key == Bags.Store.GetCurrentGuildKey() then
                GuildWindow.ShowLive()
            else
                GuildWindow.ShowCached(key)
            end
        end,
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
    local x = 0
    for i, entry in ipairs(tabs) do
        local btn = tabButtons[i]
        if not btn then
            btn = CreateTabButton()
            tabButtons[i] = btn
        end
        btn._entry = entry
        local label = "+"
        if not entry.purchase then
            label = (entry.name and entry.name ~= "") and entry.name
                or ("Tab " .. tostring(entry.tab))
        end
        btn._label:SetText(label)
        local w = entry.purchase and TAB_H
            or math.max(40, math.ceil(btn._label:GetStringWidth()) + 14)
        btn:SetSize(w, TAB_H)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", win._tabStrip, "TOPLEFT", x, 0)
        -- selected tab gets the full-strength accent border
        local selected = (not entry.purchase) and entry.tab == selectedTab
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
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        win._guildMoney:SetText(C_CurrencyInfo.GetCoinTextureString(money))
    else
        win._guildMoney:SetText(tostring(money))
    end
    win._guildMoney:Show()
    -- per-tab withdraw limit for the server-side current tab;
    -- -1 = unlimited (plan-verified GetGuildBankWithdrawMoney contract)
    local limit = GetGuildBankWithdrawMoney()
    if limit == -1 then
        win._withdrawLimit:SetText("Limit: none")
    elseif C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        win._withdrawLimit:SetText("Limit: " .. C_CurrencyInfo.GetCoinTextureString(limit))
    else
        win._withdrawLimit:SetText("Limit: " .. tostring(limit))
    end
    win._withdrawLimit:Show()
    win._depositBtn:Show()
    win._withdrawBtn:Show()
    win._logsBtn._label:SetText(bodyMode == "log" and "Items" or "Logs")
    win._logsBtn:Show()
end

function GuildWindow.Refresh()
    if not win or not win:IsShown() then return end
    local s = GetSettings()
    local appearance = Bags.Chassis.ClampAppearance((s and s.appearance) or nil)

    -- tab list: cache-driven; live mode drops tabs the vault reports
    -- non-viewable and appends the purchase "+" while tabs remain buyable
    -- (GetGuildBankTabCost() ~= nil — nil means all bought)
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
    -- search-focus tab autoselect: jump to the first tab holding the focused
    -- item when the current selection doesn't (one-shot per focus).
    if focusItemID then
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
    if EnsureSelection(tabs) and liveMode and selectedTab then
        -- first render / selected tab vanished: re-sync the server tab so
        -- the footer's withdraw limit tracks what the grid shows
        SetCurrentGuildBankTab(selectedTab)
        QueryGuildBankTab(selectedTab)
    end
    local stripW = RenderTabStrip(tabs)

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

    local tabRec = rec and rec.tabs and selectedTab and rec.tabs[selectedTab] or nil
    local size = tabRec and tabRec.size or 0
    local slots = tabRec and tabRec.slots
    local layout = Bags.GridLayout.Compute(size, {
        columns = appearance.guildColumns or appearance.columns, iconSize = snappedSize, spacing = snappedGap,
    })
    win._ownerSelect:Update()
    local headerMinW = Bags.Chassis.MeasureHeaderWidth({
        win._title, win._ownerSelect, win._searchBox, win._close,
    }, { leftPad = 8, rightPad = 6, gap = 8 })
    local bodyW = math.max(layout.width, stripW, headerMinW, MIN_BODY_W)
    -- when the header/strip out-measures the grid, center the grid instead
    -- of leaving all the slack on the right (log panel stays full-width)
    local xOff = 0
    if bodyW > layout.width and layout.width > 0 then
        xOff = (bodyW - layout.width) / 2
        if px and px > 0 then xOff = math.floor(xOff / px + 0.5) * px end
    end
    local bodyH = layout.height
    if bodyMode == "log" then
        bodyH = math.max(bodyH, MIN_LOG_H) -- log stays readable with an empty cache
    end
    win:SetContentSize(bodyW, TAB_STRIP_H + bodyH)

    -- hide both pools (a mode/tab switch must not strand the other pool's
    -- buttons), then place + dress the selected tab's slots
    HideAllGridButtons()
    if bodyMode == "log" and liveMode then
        win._logPanel:Show()
        RenderLog()
    else
        win._logPanel:Hide()
        for slot = 1, size do
            local entry = slots[slot]
            local btn = AcquireGridButton(selectedTab, slot)
            btn:SetSize(snappedSize, snappedSize)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", win._body, "TOPLEFT",
                layout[slot].x + xOff, layout[slot].y - TAB_STRIP_H)
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
                Bags.ItemButtons.DressGuildLive(btn, selectedTab, slot, entry, result)
            else
                Bags.ItemButtons.DressCached(btn, entry, result)
            end
            Bags.ItemButtons.SetFocusFlash(btn,
                focusItemID ~= nil and entry ~= nil and entry.itemID == focusItemID)
            btn:Show()
        end
    end

    RenderFooter()
end

---------------------------------------------------------------------------
-- Public surface
---------------------------------------------------------------------------

-- Open/close sounds: the guild vault pair, Blizzard parity (vendored
-- Blizzard_GuildBankUI.lua:121,130; SoundKitConstants.lua:88-89), gated on
-- the actual shown transition like every other bags window.
local function Show()
    EnsureWindow()
    bodyMode = "grid" -- a fresh open always lands on the grid
    local wasShown = win:IsShown()
    win:Show()
    if not wasShown and PlaySound and SOUNDKIT and SOUNDKIT.GUILD_VAULT_OPEN then
        PlaySound(SOUNDKIT.GUILD_VAULT_OPEN)
    end
    GuildWindow.Refresh()
end

--- At the vault (GuildTakeover.OnOpened): cursor buttons + money/log row.
--- A live session is always the current character's guild — drop any
--- offline view key.
function GuildWindow.ShowLive()
    liveMode = true
    viewedGuildKey = nil
    Show()
end

--- Browse anywhere: inert cached buttons, live-only widgets hidden.
--- guildKey selects which cached guild to render (owner selector / future
--- callers); nil defaults to the current character's guild.
function GuildWindow.ShowCached(guildKey)
    liveMode = false
    viewedGuildKey = guildKey
    Show()
end

--- GUILDBANKFRAME_CLOSED (server-driven). v1: hide; a "stay open, fold back
--- to cached mode" refinement is a later phase (bank-window parity).
function GuildWindow.OnBankClosed()
    GuildWindow.Hide()
end

function GuildWindow.Hide()
    focusItemID = nil
    if win and win:IsShown() then
        win:Hide() -- OnHide → chassis onClose routes the live-session close
        if PlaySound and SOUNDKIT and SOUNDKIT.GUILD_VAULT_CLOSE then
            PlaySound(SOUNDKIT.GUILD_VAULT_CLOSE)
        end
    end
end

--- First tab index holding itemID (ascending; sparse slots). Pure — drives
--- the search-focus tab autoselect. → tab index or nil.
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

--- Search-everywhere navigation: open the right guild view (live only when
--- the vault session is open AND the target is the current guild) and
--- pulse + tab-select the item. Focus is transient — cleared on Hide and
--- ~3s after landing.
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
    local isCurrent = guildKey == nil or guildKey == Bags.Store.GetCurrentGuildKey()
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

--- GUILDBANKLOG_UPDATE (routed by bags.lua, gated IsShown there too): the
--- queried log data landed — re-render when the log panel is what's showing.
function GuildWindow.OnLogUpdate()
    if win and win:IsShown() and bodyMode == "log" and liveMode then
        RenderLog()
    end
end

--- The window frame, or nil before first show (the guild takeover keeps its
--- name-proxy opener; this accessor is for callers that need the real frame).
function GuildWindow.GetFrame()
    return win
end

--- Profile switched while the module stays enabled: re-anchor + re-render.
function GuildWindow.OnProfileChanged()
    if not win then return end
    win:ApplyPosition()
    if win:IsShown() then GuildWindow.Refresh() end
end

-- data refresh: coalesced re-render on guild cache changes (tab metadata —
-- purchase, rename — also lands here via the scanner's drain)
Bags.Bus.Subscribe("GuildChanged", function()
    ScheduleRefresh()
end)

-- money/limit freshness: GUILDBANK_UPDATE_MONEY / _WITHDRAWMONEY (routed by
-- bags.lua as GuildMoneyChanged). Cached mode renders no money row, so the
-- ping is live-only; ScheduleRefresh already no-ops while hidden.
Bags.Bus.Subscribe("GuildMoneyChanged", function()
    if liveMode then ScheduleRefresh() end
end)
