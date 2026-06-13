---------------------------------------------------------------------------
-- Bags views: the player bag window (bags 0–5 in one grid).
-- Data source is the Phase-1 cache; refresh is coalesced: ScheduleRefresh
-- arms a one-shot OnUpdate that full-renders. Two presentation modes
-- (bank_window's split):
--   LIVE   (viewedCharacter == nil): full-interaction buttons over the
--          current character's bags; sort/sell-junk available.
--   CACHED (owner selector picked another character): inert CreateCached/
--          DressCached buttons over that character's cached bags; ops are
--          live-only (Sort/Sell Junk hidden), money/free come from the cache.
---------------------------------------------------------------------------
-- luacheck: read globals BAG_NAME_BACKPACK QUI_BagsToggleBank QUI_BagsToggleGuild
-- luacheck: read globals TradeFrame SendMailFrame AuctionHouseFrame C_AuctionHouse
-- luacheck: read globals PutItemInBag PickupBagFromSlot GetInventoryItemTexture GetInventoryItemQuality
-- luacheck: read globals ItemLocation
-- luacheck: read globals MenuUtil BAG_FILTER_CLEANUP SELL_ALL_JUNK_ITEMS_EXCLUDE_FLAG
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags
local UIKit = ns.UIKit
local Helpers = ns.Helpers
local GetSettings = Helpers.CreateDBGetter("bags")

local BagWindow = {}
Bags.BagWindow = BagWindow

local PLAYER_BAG_ORDER = { 0, 1, 2, 3, 4, 5 }

local CAT_HEADER_H = 18 -- category-mode section header row height
local BAG_SLOT_SIZE = 24 -- bag-slot strip button size

local win              -- chassis window (lazy)
local holders = {}     -- bagID → holder frame (live pool)
local buttons = {}     -- bagID → { [slot] = live button }
local cachedButtons = {}  -- bagID → { [slot] = cached button } (offline pool)
local catHeaderPool = {}  -- pooled category header fontstrings (category mode)
local viewedCharacter = nil -- nil = live current character; key = cached browse
local focusItemID = nil     -- search-everywhere landing flash (transient)
local searchText = ""
local matcher = nil
local searchTimer = nil
local selectMode = false    -- batch-send selection mode (live view only)
local selectedCells = {}    -- "bag:slot" → { bag, slot, itemID } snapshots

local function ClearSelection()
    selectMode = false
    for k in pairs(selectedCells) do selectedCells[k] = nil end
end

local function SelectedCount()
    local n = 0
    for _ in pairs(selectedCells) do n = n + 1 end
    return n
end

--- The selection-send destination: which open surface can take the batch.
--- Pure resolution lives in Transfers.ResolveSendDestination; this reads
--- the live surfaces (Blizzard frames are nil until their UIs load).
local function SendDestination()
    local bankType = nil
    if Bags.BankWindow and Bags.BankWindow.GetActiveBankType then
        bankType = Bags.BankWindow.GetActiveBankType()
    end
    return Bags.Transfers.ResolveSendDestination({
        bankLive = Bags.BankTakeover and Bags.BankTakeover.IsLive and Bags.BankTakeover.IsLive(),
        bankType = bankType,
        guildLive = Bags.GuildTakeover and Bags.GuildTakeover.IsLive and Bags.GuildTakeover.IsLive(),
        tradeOpen = TradeFrame and TradeFrame:IsShown() or false,
        mailSendOpen = SendMailFrame and SendMailFrame:IsShown() or false,
        merchantOpen = Bags.Junk and Bags.Junk.IsMerchantOpen and Bags.Junk.IsMerchantOpen() or false,
    })
end

--- Send the current selection to whatever destination is open (the footer
--- send button and the select-catcher right-click share this path).
local function SendSelection()
    local dest = SendDestination()
    if not dest or SelectedCount() == 0 then return end
    local cells = {}
    for _, c in pairs(selectedCells) do cells[#cells + 1] = c end
    table.sort(cells, function(a, b)
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
    Bags.Transfers.UseSelected(cells, dest, function(ok, reason)
        if not ok and reason == "busy" then
            print(Bags.OpsShared.PREFIX .. " another bag operation is already running.")
        end
        ClearSelection()
        BagWindow.Refresh()
    end)
end

--- Targeted deposit: right-click while a live bank session shows a SPECIFIC
--- tab routes the item into that tab (first free slot, plain cursor moves)
--- instead of the server's default first-available placement. Falls back to
--- the stock UseContainerItem deposit when the tab is full or the item
--- isn't warband-allowed.
local function DepositToSelectedTab(btn)
    local tabID, bankType = Bags.BankWindow.GetSelectedLiveTab()
    if not tabID then return end
    local bagID, slot = btn:GetBagID(), btn:GetID()
    local info = C_Container.GetContainerItemInfo(bagID, slot)
    if not info or info.isLocked then return end
    if bankType == Enum.BankType.Account then
        local loc = ItemLocation:CreateFromBagAndSlot(bagID, slot)
        if not C_Bank.IsItemAllowedInBankType(bankType, loc) then
            C_Container.UseContainerItem(bagID, slot, nil, bankType)
            return
        end
    end
    local target = nil
    local size = C_Container.GetContainerNumSlots(tabID) or 0
    for s = 1, size do
        if not C_Container.GetContainerItemInfo(tabID, s) then
            target = s
            break
        end
    end
    if not target then
        C_Container.UseContainerItem(bagID, slot, nil, bankType)
        return
    end
    ClearCursor()
    C_Container.PickupContainerItem(bagID, slot)
    C_Container.PickupContainerItem(tabID, target)
    ClearCursor()
end

--- Targeted auction post: right-click while the auction house is open stages
--- the item in the sell panel (AuctionHouseFrame:SetPostItem — the same call
--- the stock handler's AH branch makes). The stock branch only fires when a
--- sell screen is up (IsListingAuctions) or the item already passes
--- C_AuctionHouse.IsSellItemValid; everything else falls through to
--- UseContainerItem, which USES the item at the auctioneer (equips/eats it).
--- QUI always attempts the post instead: SetPostItem validates internally
--- (IsSellItemValid with displayError defaulted true, vendored
--- Blizzard_AuctionHouseFrame.lua:608) and surfaces the proper "can't
--- auction that" error rather than consuming the click as a use.
local function PostToAuctionHouse(btn)
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return end
    local bagID, slot = btn:GetBagID(), btn:GetID()
    local info = C_Container.GetContainerItemInfo(bagID, slot)
    if not info or info.isLocked then return end
    local loc = ItemLocation:CreateFromBagAndSlot(bagID, slot)
    if not loc or not loc:IsValid() then return end
    AuctionHouseFrame:SetPostItem(loc)
end

--- Live right-click route for the per-button catcher: bank-tab deposit or
--- auction post (Transfers.ResolveItemRightClickRoute keeps the priority
--- pure/testable). nil = catcher hidden, template OnClick owns the click.
local function RightClickRoute()
    return Bags.Transfers.ResolveItemRightClickRoute({
        bankTabSelected = Bags.BankWindow ~= nil
            and Bags.BankWindow.GetSelectedLiveTab ~= nil
            and Bags.BankWindow.GetSelectedLiveTab() ~= nil,
        auctionOpen = (AuctionHouseFrame ~= nil and AuctionHouseFrame:IsShown()) or false,
    })
end

--- Category-mode section headers: pooled FontStrings on the body. nil/empty
--- headers (flat mode) just hides the pool.
local function RenderCategoryHeaders(headers, xOff)
    for _, fs in ipairs(catHeaderPool) do fs:Hide() end
    if not headers then return end
    for i, h in ipairs(headers) do
        local fs = catHeaderPool[i]
        if not fs then
            fs = win._body:CreateFontString(nil, "ARTWORK")
            fs:SetFont(Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, 11, "OUTLINE")
            fs:SetJustifyH("LEFT")
            catHeaderPool[i] = fs
        end
        local sr, sg, sb = Helpers.GetSkinColors()
        fs:SetTextColor(sr, sg, sb)
        fs:SetText(h.title)
        fs:ClearAllPoints()
        -- header text sits in the upper portion of its CAT_HEADER_H row
        fs:SetPoint("TOPLEFT", win._body, "TOPLEFT", 1 + (xOff or 0), h.y - 2)
        fs:Show()
    end
end

-- The window's OnUpdate is owned exclusively by ScheduleRefresh (one-shot).
local ScheduleRefresh = Bags.Chassis.MakeScheduleRefresh(
    function() return win end,
    function() BagWindow.Refresh() end)

--- The record the window renders: the viewed character's cached record, or
--- the current character's (live mode) when no offline owner is selected.
local function ViewedRecord()
    if viewedCharacter then
        return Bags.Store.GetCharacter(viewedCharacter)
    end
    return Bags.Store.GetCurrentCharacter()
end

local function UpdateMoneyText()
    local money
    if viewedCharacter then
        -- offline: the viewed character's gold as of their last snapshot
        -- (details.money, refreshed by EnsureCurrentCharacter while they play)
        local rec = ViewedRecord()
        money = rec and rec.details and rec.details.money or 0
    else
        money = GetMoney()
    end
    if GetMoneyString then
        win._money:SetText(GetMoneyString(money, true))
    else
        win._money:SetText(tostring(money))
    end
end


--- appearance.hiddenBags: bags 1–4 the user folded out of the grid.
--- Display-only — scanning, search, and sort still cover hidden bags;
--- the backpack (0) and reagent bag (5, reagentDisplay-governed) never hide.
local function IsBagHidden(bagID)
    if bagID < 1 or bagID > 4 then return false end
    local s = GetSettings()
    local hb = s and s.appearance and s.appearance.hiddenBags
    return hb and hb[bagID] and true or false
end

--- Flip a held bag's hidden-from-grid flag and re-render (shared by the
--- bag-slot menu checkbox and the Alt+click shortcut).
local function ToggleBagHidden(bagID)
    local s = GetSettings()
    if s and s.appearance then
        s.appearance.hiddenBags = s.appearance.hiddenBags or {}
        -- toggle: true ↔ removed (false and nil both mean visible)
        s.appearance.hiddenBags[bagID] = (not s.appearance.hiddenBags[bagID]) or nil
    end
    BagWindow.Refresh()
end

local function EnsureWindow()
    if win then return win end
    win = Bags.Chassis.CreateWindow({
        name = "QUI_BagWindow",
        title = BAG_NAME_BACKPACK or "Bags",
        getPosition = function()
            local s = GetSettings()
            return s and s.windows and s.windows.bag or nil
        end,
        setPosition = function(point, x, y)
            local s = GetSettings()
            if s and s.windows and s.windows.bag then
                s.windows.bag.point, s.windows.bag.x, s.windows.bag.y = point, x, y
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
        end,
        -- the X button routes through the sound + opener-clearing path
        onUserClose = function() BagWindow.Hide() end,
        compactSearch = true,
        onChromeChanged = function() ScheduleRefresh() end,
    })

    -- footer: money + free slots
    win._money = win._footer:CreateFontString(nil, "ARTWORK")
    win._money:SetPoint("RIGHT", -8, 0)
    win._money:SetFont(Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, 12, "OUTLINE")
    win._free = win._footer:CreateFontString(nil, "ARTWORK")
    win._free:SetPoint("LEFT", 8, 0)
    win._free:SetFont(Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, 12, "OUTLINE")

    -- Bag-slot strip (equip/swap containers): bags 1-4 + reagent bag 5 as
    -- plain INSECURE buttons — the whole interaction is the stock
    -- MainMenuBarBagButtons idiom (vendored MainMenuBarBagButtons.lua:78-96):
    -- PutItemInBag(invSlot) places/swaps the cursor item, falling back to
    -- PickupBagFromSlot when the cursor is empty; bag swaps are blocked in
    -- combat, so clicks are combat-guarded. Live view only; dressed per
    -- Refresh (BAG_UPDATE → scan → BagsChanged covers equip changes).
    win._bagSlotButtons = {}
    for i = 1, 5 do
        local bagID = i
        local b = CreateFrame("Button", nil, win._body)
        b:SetSize(BAG_SLOT_SIZE, BAG_SLOT_SIZE)
        Bags.ItemButtons.AddSlotBackground(b)
        b._icon = b:CreateTexture(nil, "ARTWORK")
        b._icon:SetAllPoints()
        b._count = b:CreateFontString(nil, "OVERLAY")
        b._count:SetPoint("BOTTOMRIGHT", -1, 1)
        b._count:SetFont(Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, 10, "OUTLINE")
        UIKit.CreateBorderLines(b)
        b:RegisterForDrag("LeftButton")
        local function InvSlot()
            return C_Container.ContainerIDToInventoryID
                and C_Container.ContainerIDToInventoryID(bagID) or nil
        end
        -- Right-click: per-bag flag menu (house MenuUtil idiom, owner_select
        -- precedent). Only flags QUI actually honors: DisableAutoSort (sort
        -- executor skips the bag) + ExcludeJunkSell (junk seller skips it).
        -- Blizzard's gear-filter assignment is omitted on purpose — it only
        -- steers Blizzard's own sorter, which never runs under the takeover.
        local function ShowBagSlotMenu(anchor)
            if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
            MenuUtil.CreateContextMenu(anchor, function(_, root)
                root:CreateTitle(bagID == 5 and "Reagent Bag" or ("Bag " .. bagID))
                local function sortIgnored()
                    return C_Container.GetBagSlotFlag(bagID,
                        Enum.BagSlotFlags.DisableAutoSort) and true or false
                end
                root:CreateCheckbox(BAG_FILTER_CLEANUP or "Ignore This Bag",
                    sortIgnored, function()
                        C_Container.SetBagSlotFlag(bagID,
                            Enum.BagSlotFlags.DisableAutoSort, not sortIgnored())
                    end)
                local function junkExcluded()
                    return C_Container.GetBagSlotFlag(bagID,
                        Enum.BagSlotFlags.ExcludeJunkSell) and true or false
                end
                root:CreateCheckbox(SELL_ALL_JUNK_ITEMS_EXCLUDE_FLAG
                    or "Exclude Junk From Selling",
                    junkExcluded, function()
                        C_Container.SetBagSlotFlag(bagID,
                            Enum.BagSlotFlags.ExcludeJunkSell, not junkExcluded())
                    end)
                if bagID >= 1 and bagID <= 4 then
                    root:CreateCheckbox("Hide From Bag Window",
                        function() return IsBagHidden(bagID) end,
                        function() ToggleBagHidden(bagID) end)
                end
            end)
        end
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(self, mouseButton)
            if mouseButton == "RightButton" then
                ShowBagSlotMenu(self)
                return
            end
            if IsAltKeyDown() and bagID >= 1 and bagID <= 4 then
                ToggleBagHidden(bagID)
                return
            end
            if InCombatLockdown() then return end
            local inv = InvSlot()
            if not inv then return end
            if not PutItemInBag(inv) then
                PickupBagFromSlot(inv)
            end
        end)
        b:SetScript("OnDragStart", function()
            if InCombatLockdown() then return end
            local inv = InvSlot()
            if inv then PickupBagFromSlot(inv) end
        end)
        b:SetScript("OnReceiveDrag", function()
            if InCombatLockdown() then return end
            local inv = InvSlot()
            if inv then PutItemInBag(inv) end
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local inv = InvSlot()
            if not (inv and GameTooltip:SetInventoryItem("player", inv)) then
                GameTooltip:SetText(bagID == 5 and "Reagent Bag Slot" or "Bag Slot")
            end
            GameTooltip:AddLine("Drag a bag here (or click with one on the cursor) to equip it.",
                1, 1, 1, true)
            GameTooltip:AddLine("Right-click for sort/junk options.", 1, 1, 1, true)
            if bagID >= 1 and bagID <= 4 then
                GameTooltip:AddLine("Alt+click to hide/show this bag in the grid.", 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        win._bagSlotButtons[i] = b
    end

    -- Strip collapse toggle: writes the same appearance.showBagSlots the
    -- settings checkbox binds; stays visible while collapsed so the strip
    -- can come back without a settings round-trip.
    local stripToggle = CreateFrame("Button", nil, win._body)
    stripToggle:SetSize(14, 14)
    local stBg = stripToggle:CreateTexture(nil, "BACKGROUND")
    stBg:SetAllPoints()
    stBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    stBg:SetVertexColor(0, 0, 0, 0.35)
    UIKit.DisablePixelSnap(stBg)
    stripToggle._label = stripToggle:CreateFontString(nil, "ARTWORK")
    stripToggle._label:SetPoint("CENTER", 0, 0)
    stripToggle._label:SetFont(Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, 10, "OUTLINE")
    UIKit.CreateBorderLines(stripToggle)
    stripToggle:SetScript("OnClick", function()
        local s = GetSettings()
        if s and s.appearance then
            -- nil means "shown" (default true), so collapse writes false
            s.appearance.showBagSlots = s.appearance.showBagSlots == false
        end
        BagWindow.Refresh()
    end)
    stripToggle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Show/hide the bag-slot strip")
        GameTooltip:Show()
    end)
    stripToggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
    win._stripToggle = stripToggle

    -- header: Sort button left of the search box — compact 18×18 icon
    -- button (Blizzard autosort atlas, vendored ContainerFrame.xml:314);
    -- dark bg + QUI border lines recolored per Refresh like the tab strip
    local sort = CreateFrame("Button", nil, win._header)
    local sortBg = sort:CreateTexture(nil, "BACKGROUND")
    sortBg:SetAllPoints()
    sortBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    sortBg:SetVertexColor(0, 0, 0, 0.35)
    UIKit.DisablePixelSnap(sortBg)
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
                root:CreateButton("Stack reagents into reagent bag", function()
                    Bags.Transfers.FillReagentBag()
                end)
            end)
            return
        end
        if not Bags.SortExecutor.IsRunning() then
            Bags.SortExecutor.Start("bags")
        end
    end)
    sort:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Sort bags — " .. Bags.Chassis.SortModeText())
        GameTooltip:AddLine("Right-click for sort options.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    sort:SetScript("OnLeave", function() GameTooltip:Hide() end)
    win._sortBtn = sort

    -- header: Bank + Guild cached-browse buttons left of Sort (same
    -- construction, compact 18×18 glyph chips — tooltips carry the full
    -- names so the header stays narrower than the grid). They route through
    -- the shared toggles in bags.lua — live presentation at an open
    -- session, cached browse anywhere else.
    local function HeaderButton(label, anchorTo, tooltip, onClick)
        local btn = CreateFrame("Button", nil, win._header)
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        bg:SetVertexColor(0, 0, 0, 0.35)
        UIKit.DisablePixelSnap(bg)
        btn._label = btn:CreateFontString(nil, "ARTWORK")
        btn._label:SetPoint("CENTER", 0, 0)
        btn._label:SetFont(Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, 11, "OUTLINE")
        btn._label:SetText(label)
        btn:SetSize(18, 18)
        btn:SetPoint("RIGHT", anchorTo, "LEFT", -6, 0)
        UIKit.CreateBorderLines(btn)
        btn:SetScript("OnClick", onClick)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return btn
    end
    win._bankBtn = HeaderButton("$", sort,
        "Bank — live at a banker, cached browse anywhere",
        function() if QUI_BagsToggleBank then QUI_BagsToggleBank() end end)
    win._guildBtn = HeaderButton("G", win._bankBtn,
        "Guild bank — live at the vault, cached browse anywhere",
        function() if QUI_BagsToggleGuild then QUI_BagsToggleGuild() end end)
    win._selectBtn = HeaderButton("S", win._guildBtn,
        "Select mode: mark items, then send the batch to the open bank / guild bank / mail / trade / merchant. Click again to cancel.",
        function()
            if selectMode then ClearSelection() else selectMode = true end
            BagWindow.Refresh()
        end)

    -- footer: Sell Junk next to the free-slots text (bank CreateFooterButton
    -- construction). Hidden until Refresh shows it at an open merchant;
    -- SellJunk self-guards against an in-flight run ("running" refusal).
    local sell = CreateFrame("Button", nil, win._footer)
    local sellBg = sell:CreateTexture(nil, "BACKGROUND")
    sellBg:SetAllPoints()
    sellBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    sellBg:SetVertexColor(0, 0, 0, 0.35)
    UIKit.DisablePixelSnap(sellBg)
    sell._label = sell:CreateFontString(nil, "ARTWORK")
    sell._label:SetPoint("CENTER", 0, 0)
    sell._label:SetFont(Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, 11, "OUTLINE")
    sell._label:SetText("Sell Junk")
    sell:SetSize(math.max(40, math.ceil(sell._label:GetStringWidth()) + 12), 18)
    sell:SetPoint("LEFT", win._free, "RIGHT", 8, 0)
    sell:SetScript("OnClick", function()
        if Bags.Junk.IsMerchantOpen() then
            Bags.Junk.SellJunk()
        end
    end)
    sell:Hide()
    win._sellBtn = sell

    -- footer: batch send (Sell Junk construction), right of Sell Junk —
    -- both can show at a merchant. Hidden until Refresh shows it with a
    -- destination verb + count while a selection exists.
    local send = CreateFrame("Button", nil, win._footer)
    local sendBg = send:CreateTexture(nil, "BACKGROUND")
    sendBg:SetAllPoints()
    sendBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    sendBg:SetVertexColor(0, 0, 0, 0.35)
    UIKit.DisablePixelSnap(sendBg)
    send._label = send:CreateFontString(nil, "ARTWORK")
    send._label:SetPoint("CENTER", 0, 0)
    send._label:SetFont(Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, 11, "OUTLINE")
    send:SetPoint("LEFT", sell, "RIGHT", 8, 0)
    UIKit.CreateBorderLines(send)
    send:SetScript("OnClick", SendSelection)
    send:Hide()
    win._sendBtn = send

    -- currency bar: footer-adjacent row (settings-listed currencies);
    -- Refresh drives it and reserves its height via SetContentSize
    Bags.CurrencyBar.Attach(win)

    -- header: owner selector right of the title (the right side is the
    -- sort/search/close cluster); picking an alt renders their cached bags
    win._ownerSelect = Bags.OwnerSelect.Attach(win, {
        title = "Characters",
        tooltip = "View another character's bags",
        listOwners = function()
            return Bags.OwnerSelect.BuildOwnerList(
                Bags.Store.ListCharacters(), Bags.Store.GetCurrentCharacterKey())
        end,
        current = function()
            return viewedCharacter or Bags.Store.GetCurrentCharacterKey()
        end,
        onSelect = function(key) BagWindow.SetViewedCharacter(key) end,
    })

    for _, bagID in ipairs(PLAYER_BAG_ORDER) do
        holders[bagID] = Bags.ItemButtons.CreateHolder(win._body, bagID)
        buttons[bagID] = {}
    end

    win:ApplyPosition()
    return win
end

--- ordered flat list of { bagID, slot, entry } across bags 0..5 (incl.
--- empties) — from the viewed record, so cached mode walks the offline
--- character's bags through the exact same shape. Hidden bags contribute
--- nothing (so the free count and category buckets skip them too).
local function CollectSlots()
    local rec = ViewedRecord()
    local out = {}
    for _, bagID in ipairs(PLAYER_BAG_ORDER) do
        if not IsBagHidden(bagID) then
            local bag = rec and rec.bags and rec.bags[bagID]
            local size = bag and bag.size or 0
            for slot = 1, size do
                out[#out + 1] = { bagID = bagID, slot = slot, entry = bag.slots and bag.slots[slot] }
            end
        end
    end
    return out
end

function BagWindow.Refresh()
    if not win or not win:IsShown() then return end
    local s = GetSettings()
    local appearance = Bags.Chassis.ClampAppearance((s and s.appearance) or nil)

    local slots = CollectSlots()
    local live = (viewedCharacter == nil)
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

    -- new-item glow GUIDs, ONCE per cell (live bag window only): reused by
    -- the category engine's Recent bucket AND the dress call below, so the
    -- per-slot GUID read doesn't run twice per render
    if live and Bags.NewItems then
        for _, cell in ipairs(slots) do
            if cell.entry then
                cell._newGuid = Bags.NewItems.CheckSlot(cell.bagID, cell.slot, cell.entry)
            else
                cell._newGuid = nil
            end
        end
    end

    local free = 0
    for _, cell in ipairs(slots) do
        if not cell.entry then free = free + 1 end
    end

    -- layout-engine pick (grid_layout's promised interface seam): flat =
    -- positional grid incl. empty slots; categories = occupied cells
    -- bucketed under headers (empty slots live in the footer free-count)
    local categoriesMode = appearance.layoutMode == "categories"
    local gridOpts = {
        columns = appearance.columns, iconSize = snappedSize, spacing = snappedGap,
        headerHeight = CAT_HEADER_H,
    }
    local placed -- array of { cell, x, y }
    local catHeaders, contentW, contentH
    if categoriesMode then
        for _, cell in ipairs(slots) do
            cell.recent = cell._newGuid ~= nil
        end
        local groups = Bags.CategoryLayout.Group(slots, Bags.Details.Build)
        local cl = Bags.CategoryLayout.Compute(groups, gridOpts)
        placed, catHeaders = cl.buttons, cl.headers
        contentW, contentH = cl.width, cl.height
        -- an empty (or all-empty-slot) view still needs a sane window
        if contentW == 0 then
            local empty = Bags.GridLayout.Compute(0, gridOpts)
            contentW, contentH = empty.width, 0
        end
    else
        -- Flat mode: the reagent bag (bagID 5) renders per reagentDisplay —
        -- "separate" (own labeled section below the regular bags; its slots
        -- are otherwise indistinguishable in one merged grid), "merged", or
        -- "hidden". groupEmptySlots collapses each section's empty cells
        -- into one counter cell.
        local reagentMode = (appearance and appearance.reagentDisplay) or "separate"
        local mainCells, reagentCells = {}, {}
        for _, cell in ipairs(slots) do
            cell._freeCount = nil
            if cell.bagID == 5 and reagentMode == "separate" then
                reagentCells[#reagentCells + 1] = cell
            elseif not (cell.bagID == 5 and reagentMode == "hidden") then
                mainCells[#mainCells + 1] = cell
            end
        end
        if appearance and appearance.groupEmptySlots then
            local function collapse(cells)
                local out, firstEmpty, emptyN = {}, nil, 0
                for _, cell in ipairs(cells) do
                    if cell.entry then
                        out[#out + 1] = cell
                    else
                        emptyN = emptyN + 1
                        if not firstEmpty then
                            firstEmpty = cell
                            out[#out + 1] = cell
                        end
                    end
                end
                if firstEmpty and emptyN > 1 then firstEmpty._freeCount = emptyN end
                return out
            end
            mainCells = collapse(mainCells)
            reagentCells = collapse(reagentCells)
        end
        local layout = Bags.GridLayout.Compute(#mainCells, gridOpts)
        placed = {}
        for i, cell in ipairs(mainCells) do
            placed[i] = { cell = cell, x = layout[i].x, y = layout[i].y }
        end
        catHeaders = nil
        contentW, contentH = layout.width, layout.height
        if #reagentCells > 0 then
            local gapAbove = contentH > 0 and (snappedGap * 2) or 0
            local headerY = -(contentH + gapAbove)
            catHeaders = { { title = "Reagents", y = headerY } }
            local rl = Bags.GridLayout.Compute(#reagentCells, gridOpts)
            local cellTop = headerY - CAT_HEADER_H
            for i, cell in ipairs(reagentCells) do
                placed[#placed + 1] = { cell = cell, x = rl[i].x, y = cellTop + rl[i].y }
            end
            contentW = math.max(contentW, rl.width)
            contentH = contentH + gapAbove + CAT_HEADER_H + rl.height
        end
    end

    -- Bag-slot strip: live view only (cached browsing has no live inventory
    -- to swap), gated by appearance.showBagSlots; everything below shifts
    -- down by the strip's height.
    local stripH = 0
    local showStrip = live and (not appearance or appearance.showBagSlots ~= false)
    -- collapse toggle: live-only like the strip; renders in BOTH states
    -- (expanded: vertically centered on the strip row; collapsed: a slim
    -- 16px row of its own so the strip can be brought back in place)
    if win._stripToggle then
        if live then
            win._stripToggle._label:SetText(showStrip and "-" or "+")
            local tr, tg, tb = Helpers.GetSkinColors()
            UIKit.UpdateBorderLines(win._stripToggle, 1, tr, tg, tb, 0.35)
            win._stripToggle:ClearAllPoints()
            win._stripToggle:SetPoint("TOPLEFT", win._body, "TOPLEFT",
                0, showStrip and -((BAG_SLOT_SIZE - 14) / 2) or -1)
            win._stripToggle:Show()
        else
            win._stripToggle:Hide()
        end
    end
    if win._bagSlotButtons then
        for i, b in ipairs(win._bagSlotButtons) do
            if showStrip then
                local inv = C_Container.ContainerIDToInventoryID
                    and C_Container.ContainerIDToInventoryID(i) or nil
                local tex = inv and GetInventoryItemTexture("player", inv) or nil
                if tex then
                    b._icon:SetTexture(tex)
                    b._icon:Show()
                    local q = GetInventoryItemQuality("player", inv)
                    local qr, qg, qb = Bags.ItemButtons.GetQualityColor(q or 1)
                    UIKit.UpdateBorderLines(b, 1, qr, qg, qb, 1)
                    b._count:SetText(C_Container.GetContainerNumFreeSlots(i) or "")
                else
                    b._icon:Hide()
                    b._count:SetText("")
                    local er, eg, eb = Helpers.GetSkinColors()
                    UIKit.UpdateBorderLines(b, 1, er, eg, eb, 0.35)
                end
                b:SetAlpha(IsBagHidden(i) and 0.35 or 1)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", win._body, "TOPLEFT",
                    18 + (i - 1) * (BAG_SLOT_SIZE + 4), 0)
                b:Show()
            else
                b:Hide()
            end
        end
    end
    if showStrip then
        stripH = BAG_SLOT_SIZE + 8
        contentW = math.max(contentW, 18 + 5 * BAG_SLOT_SIZE + 4 * 4)
    elseif live then
        stripH = 16 -- slim row for the expand toggle
    end
    if stripH > 0 then
        for _, p in ipairs(placed) do p.y = p.y - stripH end
        if catHeaders then
            for _, h in ipairs(catHeaders) do h.y = h.y - stripH end
        end
        contentH = contentH + stripH
    end

    -- currency bar re-renders inside Refresh: its height joins the content
    -- accounting so an empty↔non-empty flip resizes the window cleanly
    local currencyH = win._currencyBar
        and win._currencyBar:Update(ViewedRecord(), viewedCharacter == nil) or 0
    win._ownerSelect:Update()

    -- Sort: live-mode only (the executor moves the CURRENT character's
    -- items — there's nothing to sort in an offline cache); border tracks
    -- the skin like the bank tab strip (UpdateBorderLines no-ops when
    -- unchanged)
    if live then
        local sr, sg, sb = Helpers.GetSkinColors()
        UIKit.UpdateBorderLines(win._sortBtn, 1, sr, sg, sb, 0.35)
        win._sortBtn:Show()
    else
        win._sortBtn:Hide()
    end

    -- Select + batch send: live-mode only (selection sends operate the
    -- CURRENT character's slots). The select button doubles as the cancel
    -- affordance; the send button appears once a destination is open and
    -- at least one slot is marked.
    if not live and selectMode then ClearSelection() end
    if live then
        -- armed select mode = full-strength border (the chip keeps its
        -- glyph; the tooltip explains the cancel affordance)
        local sr, sg, sb = Helpers.GetSkinColors()
        UIKit.UpdateBorderLines(win._selectBtn, 1, sr, sg, sb, selectMode and 1 or 0.35)
        win._selectBtn:Show()
    else
        win._selectBtn:Hide()
    end
    local headerMinW = Bags.Chassis.MeasureHeaderWidth({
        win._title, win._ownerSelect, win._selectBtn, win._guildBtn,
        win._bankBtn, win._sortBtn, win._searchBox, win._close,
    }, { leftPad = 8, rightPad = 6, gap = 8 })
    -- when the header still out-measures the grid (very low column counts),
    -- center the grid instead of leaving all the slack on the right
    local gridW = contentW
    contentW = math.max(contentW, headerMinW)
    local xOff = 0
    if contentW > gridW and gridW > 0 then
        xOff = (contentW - gridW) / 2
        if px and px > 0 then xOff = math.floor(xOff / px + 0.5) * px end
    end
    win:SetContentSize(contentW, contentH + currencyH)

    RenderCategoryHeaders(catHeaders, xOff)

    -- hide both pools (a mode switch must not strand the other pool's
    -- buttons), re-place the needed ones from the mode's pool
    for _, byBag in pairs(buttons) do
        for _, btn in pairs(byBag) do btn:Hide() end
    end
    for _, byBag in pairs(cachedButtons) do
        for _, btn in pairs(byBag) do btn:Hide() end
    end
    -- one route resolve per render (the dress loop below reads it per
    -- button); the catchers' own handlers re-resolve at click/hover time
    local rightClickRoute = RightClickRoute()
    for _, p in ipairs(placed) do
        local cell = p.cell
        local btn
        if live then
            local byBag = buttons[cell.bagID]
            btn = byBag[cell.slot]
            if not btn then
                btn = Bags.ItemButtons.CreateLive(holders[cell.bagID], cell.bagID)
                btn:SetID(cell.slot)
                -- Selection catcher: while select mode is armed (live view)
                -- a transparent overlay button above the slot captures the
                -- click and toggles the batch-send mark. The template's own
                -- OnClick is NEVER replaced or wrapped — an insecure wrapper
                -- taints the secure handler chain, and the protected
                -- UseContainerItem inside ContainerFrameItemButton_OnClick
                -- then hard-blocks (ADDON_ACTION_FORBIDDEN on right-click).
                -- The overlay is shown/hidden by the dress loop below as the
                -- mode flips; hidden, it eats no input.
                local catcher = CreateFrame("Button", nil, btn)
                catcher:SetAllPoints()
                catcher:SetFrameLevel(btn:GetFrameLevel() + 5)
                catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                catcher:SetScript("OnClick", function(_, mouseButton)
                    -- right-click sends the whole selection to the open
                    -- destination (same path as the footer send button)
                    if mouseButton == "RightButton" then
                        SendSelection()
                        return
                    end
                    local bagID, slot = btn:GetBagID(), btn:GetID()
                    local info = C_Container.GetContainerItemInfo(bagID, slot)
                    if info then -- empty slots aren't selectable
                        local key = bagID .. ":" .. slot
                        if selectedCells[key] then
                            selectedCells[key] = nil
                        else
                            selectedCells[key] = { bag = bagID, slot = slot, itemID = info.itemID }
                        end
                        BagWindow.Refresh()
                    end
                end)
                -- the catcher owns hover while armed, so it reproduces the
                -- item tooltip and adds the mode instructions
                catcher:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetBagItem(btn:GetBagID(), btn:GetID())
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Click: select / deselect.", 0.2, 0.82, 1, true)
                    local dest = SendDestination()
                    local n = SelectedCount()
                    if dest and n > 0 then
                        GameTooltip:AddLine(("Right-click: %s %d selected item%s."):format(
                            dest.verb:lower(), n, n == 1 and "" or "s"), 0.2, 0.82, 1, true)
                    end
                    GameTooltip:Show()
                end)
                catcher:SetScript("OnLeave", function() GameTooltip:Hide() end)
                catcher:Hide()
                btn._quiSelectCatcher = catcher
                -- Targeted right-click catcher: while a routed destination
                -- is open (live bank session showing a SPECIFIC tab, or the
                -- auction house — RightClickRoute) and select mode is off,
                -- right-clicks route the item there instead of the template
                -- fall-through. Left clicks/drags PASS THROUGH to the secure
                -- template button below (SimpleScriptRegionAPI
                -- SetPassThroughButtons — protected function but insecurely
                -- callable out of combat). In-combat creation must not even
                -- ATTEMPT the call: pcall catches the Lua error but cannot
                -- suppress the client's ADDON_ACTION_BLOCKED log — flag for
                -- the dress loop's out-of-combat retry instead.
                local dep = CreateFrame("Button", nil, btn)
                dep:SetAllPoints()
                dep:SetFrameLevel(btn:GetFrameLevel() + 4)
                dep:RegisterForClicks("RightButtonUp")
                if InCombatLockdown()
                    or not pcall(dep.SetPassThroughButtons, dep, "LeftButton") then
                    dep._quiPassThroughFailed = true
                end
                dep:SetScript("OnClick", function()
                    local route = RightClickRoute()
                    if route == "auction" then
                        PostToAuctionHouse(btn)
                    elseif route == "bankTab" then
                        DepositToSelectedTab(btn)
                    end
                end)
                dep:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetBagItem(btn:GetBagID(), btn:GetID())
                    GameTooltip:AddLine(" ")
                    if RightClickRoute() == "auction" then
                        -- mirror the context fade: a slot dimmed as
                        -- not-sellable must not advertise the sell click
                        local loc = ItemLocation:CreateFromBagAndSlot(
                            btn:GetBagID(), btn:GetID())
                        if loc and loc:IsValid()
                            and C_AuctionHouse.IsSellItemValid(loc, false) then
                            GameTooltip:AddLine("Right-click: sell at the auction house.",
                                0.2, 0.82, 1, true)
                        else
                            GameTooltip:AddLine("This item can't be put up for auction.",
                                0.6, 0.6, 0.6, true)
                        end
                    else
                        GameTooltip:AddLine("Right-click: deposit into the open bank tab.",
                            0.2, 0.82, 1, true)
                    end
                    GameTooltip:Show()
                end)
                dep:SetScript("OnLeave", function() GameTooltip:Hide() end)
                dep:Hide()
                btn._quiDepositCatcher = dep
                byBag[cell.slot] = btn
            end
        else
            local byBag = cachedButtons[cell.bagID]
            if not byBag then byBag = {}; cachedButtons[cell.bagID] = byBag end
            btn = byBag[cell.slot]
            if not btn then
                btn = Bags.ItemButtons.CreateCached(win._body)
                byBag[cell.slot] = btn
            end
        end
        btn:SetSize(snappedSize, snappedSize)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", win._body, "TOPLEFT", p.x + xOff, p.y)
        local result = nil
        if matcher then
            -- cached entries carry the same shape, so search works
            -- identically in both modes (Details.Build over cache slots)
            local details = Bags.Details.Build(cell.entry)
            if details then
                local m = matcher(details)
                result = (m ~= false) -- pending counts as visible
            else
                result = false -- empty slots dim while a search is active
            end
        end
        if live then
            -- new-item glow: live bag window only (bank/guild/cached never
            -- track); the GUID was resolved once in the precompute pass
            Bags.ItemButtons.Dress(btn, cell.entry, result, cell._newGuid)
        else
            Bags.ItemButtons.DressCached(btn, cell.entry, result)
        end
        if cell._freeCount then
            Bags.ItemButtons.SetFreeCount(btn, cell._freeCount)
        end
        Bags.ItemButtons.SetFocusFlash(btn,
            focusItemID ~= nil and cell.entry ~= nil and cell.entry.itemID == focusItemID)
        Bags.ItemButtons.SetSelectedOverlay(btn,
            live and selectMode and cell.entry ~= nil
            and selectedCells[cell.bagID .. ":" .. cell.slot] ~= nil)
        if btn._quiSelectCatcher then
            btn._quiSelectCatcher:SetShown(selectMode and live)
        end
        if btn._quiDepositCatcher then
            local dep = btn._quiDepositCatcher
            -- retry the pass-through arming if creation happened in combat
            if dep._quiPassThroughFailed and not InCombatLockdown() then
                if pcall(dep.SetPassThroughButtons, dep, "LeftButton") then
                    dep._quiPassThroughFailed = nil
                end
            end
            dep:SetShown(live and not selectMode
                and not dep._quiPassThroughFailed
                and cell.entry ~= nil
                and rightClickRoute ~= nil)
        end
        btn:Show()
    end

    win._free:SetText(free .. " free")
    UpdateMoneyText()

    -- Sell Junk visibility lives at the footer-text update point: shown only
    -- live at an open merchant with the setting on (MerchantChanged pings a
    -- refresh on both edges); ops are live-only, so cached mode hides it
    local junkCfg = s and s.behavior and s.behavior.junk
    if live and junkCfg and junkCfg.sellButton and Bags.Junk.IsMerchantOpen() then
        win._sellBtn:Show()
    else
        win._sellBtn:Hide()
    end

    local sendDest = live and selectMode and SelectedCount() > 0 and SendDestination() or nil
    if sendDest then
        win._sendBtn._label:SetText(sendDest.verb .. " (" .. SelectedCount() .. ")")
        win._sendBtn:SetSize(
            math.max(40, math.ceil(win._sendBtn._label:GetStringWidth()) + 12), 18)
        win._sendBtn:Show()
    else
        win._sendBtn:Hide()
    end
end

-- Open/close sounds: Blizzard's lived in ContainerFrame OnShow/OnHide, which
-- never run under takeover. Gate on the actual shown transition (OnShow/
-- OnHide parity) so redundant calls (e.g. ESC's CloseAllWindows sweep while
-- already closed) don't replay them.
function BagWindow.Show()
    EnsureWindow()
    local wasShown = win:IsShown()
    -- a fresh open always lands on your own (live) bags — offline browsing
    -- is a transient inspection, and the autoopen paths (merchant, mail)
    -- must never come up rendering an alt
    if not wasShown then viewedCharacter = nil end
    win:Show()
    if not wasShown and PlaySound and SOUNDKIT and SOUNDKIT.IG_BACKPACK_OPEN then
        PlaySound(SOUNDKIT.IG_BACKPACK_OPEN)
    end
    BagWindow.Refresh()
end

function BagWindow.Hide()
    focusItemID = nil
    ClearSelection()
    if win and win:IsShown() then
        win:Hide()
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_BACKPACK_CLOSE then
            PlaySound(SOUNDKIT.IG_BACKPACK_CLOSE)
        end
    end
end

--- Search-everywhere navigation: open (or keep) the window on the right
--- owner's view and pulse the slots holding itemID. ownerKey nil/current =
--- the live view. Focus is transient — it clears on Hide and ~3s after
--- landing (the timer triggers one clearing re-render).
function BagWindow.FocusItem(itemID, ownerKey)
    EnsureWindow()
    local wasShown = win:IsShown()
    if not wasShown then
        win:Show() -- raw show: Show() resets the viewed owner deliberately
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_BACKPACK_OPEN then
            PlaySound(SOUNDKIT.IG_BACKPACK_OPEN)
        end
    end
    if ownerKey == nil or ownerKey == Bags.Store.GetCurrentCharacterKey() then
        viewedCharacter = nil
    else
        viewedCharacter = ownerKey
    end
    focusItemID = itemID
    if C_Timer and C_Timer.After then
        C_Timer.After(3, function()
            if focusItemID == itemID then
                focusItemID = nil
                ScheduleRefresh()
            end
        end)
    end
    BagWindow.Refresh()
end

function BagWindow.Toggle()
    if win and win:IsShown() then BagWindow.Hide() else BagWindow.Show() end
end

function BagWindow.IsShown()
    return win ~= nil and win:IsShown()
end

--- Owner-selector entry: nil/current key → live mode (your own bags),
--- any other cached character → offline cached render from the store.
function BagWindow.SetViewedCharacter(key)
    if key == nil or key == Bags.Store.GetCurrentCharacterKey() then
        viewedCharacter = nil
    else
        viewedCharacter = key
    end
    BagWindow.Refresh()
end

--- Profile switched while the module stays enabled: re-anchor + re-render.
function BagWindow.OnProfileChanged()
    if not win then return end
    win:ApplyPosition()
    if win:IsShown() then BagWindow.Refresh() end
end

-- data refresh: re-render on cache changes (also re-evaluates pending search
-- fields, since item-data loads re-publish BagsChanged via the scanners;
-- GetExtended itself never requests a load; a name-pending term can stay
-- visible until the next bag activity — acceptable)
Bags.Bus.Subscribe("BagsChanged", function()
    ScheduleRefresh()
end)

-- money-only changes (repairs, flight paths) don't touch bags; update just
-- the footer. Live-only: cached mode shows the VIEWED character's stored
-- gold, which this event doesn't change.
Bags.Bus.Subscribe("MoneyChanged", function()
    if win and win:IsShown() and win._money and not viewedCharacter then
        UpdateMoneyText()
    end
end)

-- merchant open/close toggles the Sell Junk button; visibility is computed
-- in Refresh next to the footer-text update (ScheduleRefresh no-ops while
-- hidden — the autoopen path re-renders on show anyway)
Bags.Bus.Subscribe("MerchantChanged", function()
    ScheduleRefresh()
end)

-- auctioneer open/close flips the right-click sell-post catcher; same shape
-- as MerchantChanged, and the deferred refresh reads the live
-- AuctionHouseFrame:IsShown() a frame later, past any event-order ambiguity
Bags.Bus.Subscribe("AuctionHouseChanged", function()
    ScheduleRefresh()
end)

-- currency-scanner drains land on the currency bar; a full refresh (not a
-- bar-only update) keeps SetContentSize in step with bar visibility flips
Bags.Bus.Subscribe("CurrenciesChanged", function()
    ScheduleRefresh()
end)
