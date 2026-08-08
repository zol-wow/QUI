-- luacheck: read globals BAG_NAME_BACKPACK QUI_BagsToggleBank QUI_BagsToggleGuild
-- luacheck: read globals TradeFrame SendMailFrame AuctionHouseFrame C_AuctionHouse
-- luacheck: read globals PutItemInBag PickupBagFromSlot GetInventoryItemTexture GetInventoryItemQuality
-- luacheck: read globals ItemLocation
-- luacheck: read globals MenuUtil BAG_FILTER_CLEANUP SELL_ALL_JUNK_ITEMS_EXCLUDE_FLAG
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

local BagWindow = {}
Bags.BagWindow = BagWindow

local PLAYER_BAG_ORDER = { 0, 1, 2, 3, 4, 5 }

local CAT_HEADER_H = 18
local BAG_SLOT_SIZE = 24

local win
local holders = {}
local buttons = {}
local cachedButtons = {}
local catHeaderPool = {}
local viewedCharacter = nil
local focusItemID = nil
local searchText = ""
local matcher = nil
local searchTimer = nil
local selectMode = false
local selectedCells = {}

local repaint = {
    placed = nil,
    index = nil,
    sig = nil,
    live = nil,
    contentW = nil,
    contentH = nil,
    pendingFull = false,
    pendingDressAll = false,
    pendingBags = nil,
    pendingSearch = false,
    pendingCurrency = false,
}

local function ClearSelection()
    selectMode = false
    for k in pairs(selectedCells) do selectedCells[k] = nil end
end

local function SelectedCount()
    local n = 0
    for _ in pairs(selectedCells) do n = n + 1 end
    return n
end

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
            print(Bags.OpsShared.PREFIX .. " " .. ns.L["another bag operation is already running."])
        end
        ClearSelection()
        BagWindow.Refresh()
    end)
end

local function UpdateSendButton()
    if not win then return end
    local sendDest = viewedCharacter == nil and selectMode and SelectedCount() > 0
        and SendDestination() or nil
    if sendDest then
        win._sendBtn._label:SetText(sendDest.verb .. " (" .. SelectedCount() .. ")")
        win._sendBtn:SetSize(
            math.max(40, math.ceil(win._sendBtn._label:GetStringWidth()) + 12), 18)
        win._sendBtn:Show()
    else
        win._sendBtn:Hide()
    end
end

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
    local size = C_Container.GetContainerNumSlots(tabID) or 0
    local maxStack = C_Item.GetItemMaxStackSizeByID(info.itemID)
    local target = Bags.Transfers.ResolveDepositTargetSlot(size,
        function(s) return C_Container.GetContainerItemInfo(tabID, s) end,
        info.itemID, maxStack)
    if not target then
        C_Container.UseContainerItem(bagID, slot, nil, bankType)
        return
    end
    ClearCursor()
    C_Container.PickupContainerItem(bagID, slot)
    C_Container.PickupContainerItem(tabID, target)
    ClearCursor()
end

local function PostToAuctionHouse(btn)
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return end
    local bagID, slot = btn:GetBagID(), btn:GetID()
    local info = C_Container.GetContainerItemInfo(bagID, slot)
    if not info or info.isLocked then return end
    local loc = ItemLocation:CreateFromBagAndSlot(bagID, slot)
    if not loc or not loc:IsValid() then return end
    AuctionHouseFrame:SetPostItem(loc)
end

local function RightClickRoute()
    return Bags.Transfers.ResolveItemRightClickRoute({
        bankTabSelected = Bags.BankWindow ~= nil
            and Bags.BankWindow.GetSelectedLiveTab ~= nil
            and Bags.BankWindow.GetSelectedLiveTab() ~= nil,
        auctionOpen = (AuctionHouseFrame ~= nil and AuctionHouseFrame:IsShown()) or false,
    })
end

local function RenderCategoryHeaders(headers, xOff)
    for _, fs in ipairs(catHeaderPool) do fs:Hide() end
    if not headers then return end
    for i, h in ipairs(headers) do
        local fs = catHeaderPool[i]
        if not fs then
            fs = win._body:CreateFontString(nil, "ARTWORK")
            CJKFont(fs, Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, 11, "OUTLINE")
            fs:SetJustifyH("LEFT")
            catHeaderPool[i] = fs
        end
        local sr, sg, sb = Helpers.GetSkinColors()
        fs:SetTextColor(sr, sg, sb)
        fs:SetText(h.title)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", win._body, "TOPLEFT", 1 + (xOff or 0), h.y - 2)
        fs:Show()
    end
end

local RunScheduledRepaint
local ScheduleRefresh = Bags.Chassis.MakeScheduleRefresh(
    function() return win end,
    function() RunScheduledRepaint() end)

local function ViewedRecord()
    if viewedCharacter then
        return Storage.Store.GetCharacter(viewedCharacter)
    end
    return Storage.Store.GetCurrentCharacter()
end

local function UpdateMoneyText()
    local money
    if viewedCharacter then
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

local function IsBagHidden(bagID)
    if bagID < 1 or bagID > 4 then return false end
    local s = GetSettings()
    local hb = s and s.appearance and s.appearance.hiddenBags
    return hb and hb[bagID] and true or false
end

local function ToggleBagHidden(bagID)
    local s = GetSettings()
    if s and s.appearance then
        s.appearance.hiddenBags = s.appearance.hiddenBags or {}
        s.appearance.hiddenBags[bagID] = (not s.appearance.hiddenBags[bagID]) or nil
    end
    BagWindow.Refresh()
end

local function EnsureWindow()
    if win then return win end
    win = Bags.Chassis.CreateWindow({
        name = "QUI_BagWindow",
        title = BAG_NAME_BACKPACK or ns.L["Bags"],
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
            if searchTimer then searchTimer:Cancel() end
            searchTimer = C_Timer.NewTimer(0.1, function()
                searchTimer = nil
                repaint.pendingSearch = true
                ScheduleRefresh()
            end)
        end,
        onClose = function(w)
            w:SetScript("OnUpdate", nil)
            w._updateScheduled = false
        end,
        onUserClose = function() BagWindow.Hide() end,
        compactSearch = true,
        onChromeChanged = function() ScheduleRefresh() end,
    })

    win._money = win._footer:CreateFontString(nil, "ARTWORK")
    win._money:SetPoint("RIGHT", -8, 0)
    CJKFont(win._money, Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, 12, "OUTLINE")
    win._free = win._footer:CreateFontString(nil, "ARTWORK")
    win._free:SetPoint("LEFT", 8, 0)
    CJKFont(win._free, Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, 12, "OUTLINE")

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
        CJKFont(b._count, Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, 10, "OUTLINE")
        UIKit.CreateBorderLines(b)
        b:RegisterForDrag("LeftButton")
        local function InvSlot()
            return C_Container.ContainerIDToInventoryID
                and C_Container.ContainerIDToInventoryID(bagID) or nil
        end
        local function ShowBagSlotMenu(anchor)
            if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
            MenuUtil.CreateContextMenu(anchor, function(_, root)
                root:CreateTitle(bagID == 5 and ns.L["Reagent Bag"] or (ns.L["Bag"] .. " " .. bagID))
                local function sortIgnored()
                    return C_Container.GetBagSlotFlag(bagID,
                        Enum.BagSlotFlags.DisableAutoSort) and true or false
                end
                root:CreateCheckbox(BAG_FILTER_CLEANUP or ns.L["Ignore This Bag"],
                    sortIgnored, function()
                        C_Container.SetBagSlotFlag(bagID,
                            Enum.BagSlotFlags.DisableAutoSort, not sortIgnored())
                    end)
                local function junkExcluded()
                    return C_Container.GetBagSlotFlag(bagID,
                        Enum.BagSlotFlags.ExcludeJunkSell) and true or false
                end
                root:CreateCheckbox(SELL_ALL_JUNK_ITEMS_EXCLUDE_FLAG
                    or ns.L["Exclude Junk From Selling"],
                    junkExcluded, function()
                        C_Container.SetBagSlotFlag(bagID,
                            Enum.BagSlotFlags.ExcludeJunkSell, not junkExcluded())
                    end)
                if bagID >= 1 and bagID <= 4 then
                    root:CreateCheckbox(ns.L["Hide From Bag Window"],
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
                GameTooltip:SetText(bagID == 5 and ns.L["Reagent Bag Slot"] or ns.L["Bag Slot"])
            end
            GameTooltip:AddLine(ns.L["Drag a bag here (or click with one on the cursor) to equip it."],
                1, 1, 1, true)
            GameTooltip:AddLine(ns.L["Right-click for sort/junk options."], 1, 1, 1, true)
            if bagID >= 1 and bagID <= 4 then
                GameTooltip:AddLine(ns.L["Alt+click to hide/show this bag in the grid."], 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        win._bagSlotButtons[i] = b
    end

    local stripToggle = Bags.Chassis.CreatePanelButton(win._body)
    stripToggle:SetSize(14, 14)
    stripToggle._label = stripToggle:CreateFontString(nil, "ARTWORK")
    stripToggle._label:SetPoint("CENTER", 0, 0)
    CJKFont(stripToggle._label, Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, 10, "OUTLINE")
    UIKit.CreateBorderLines(stripToggle)
    stripToggle:SetScript("OnClick", function()
        local s = GetSettings()
        if s and s.appearance then
            s.appearance.showBagSlots = s.appearance.showBagSlots == false
        end
        BagWindow.Refresh()
    end)
    stripToggle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(ns.L["Show/hide the bag-slot strip"])
        GameTooltip:Show()
    end)
    stripToggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
    win._stripToggle = stripToggle

    local sort = Bags.Chassis.CreatePanelButton(win._header)
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
                root:CreateButton(ns.L["Stack reagents into reagent bag"], function()
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
        GameTooltip:SetText(ns.L["Sort bags"] .. " — " .. Bags.Chassis.SortModeText())
        GameTooltip:AddLine(ns.L["Right-click for sort options."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    sort:SetScript("OnLeave", function() GameTooltip:Hide() end)
    win._sortBtn = sort

    local function HeaderButton(label, anchorTo, tooltip, onClick)
        local btn = Bags.Chassis.CreatePanelButton(win._header, true)
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
        ns.L["Bank — live at a banker, cached browse anywhere"],
        function() if QUI_BagsToggleBank then QUI_BagsToggleBank() end end)
    win._guildBtn = HeaderButton("G", win._bankBtn,
        ns.L["Guild bank — live at the vault, cached browse anywhere"],
        function() if QUI_BagsToggleGuild then QUI_BagsToggleGuild() end end)
    win._selectBtn = HeaderButton("S", win._guildBtn,
        ns.L["Select mode: mark items, then send the batch to the open bank / guild bank / mail / trade / merchant. Click again to cancel."],
        function()
            if selectMode then ClearSelection() else selectMode = true end
            BagWindow.Refresh()
        end)

    local sell = Bags.Chassis.CreatePanelButton(win._footer, true)
    sell._label:SetText(ns.L["Sell Junk"])
    sell:SetSize(math.max(40, math.ceil(sell._label:GetStringWidth()) + 12), 18)
    sell:SetPoint("LEFT", win._free, "RIGHT", 8, 0)
    sell:SetScript("OnClick", function()
        if Bags.Junk.IsMerchantOpen() then
            Bags.Junk.SellJunk()
        end
    end)
    sell:Hide()
    win._sellBtn = sell

    local send = Bags.Chassis.CreatePanelButton(win._footer, true)
    send:SetPoint("LEFT", sell, "RIGHT", 8, 0)
    UIKit.CreateBorderLines(send)
    send:SetScript("OnClick", SendSelection)
    send:Hide()
    win._sendBtn = send

    Bags.CurrencyBar.Attach(win)

    win._ownerSelect = Bags.OwnerSelect.Attach(win, {
        title = ns.L["Characters"],
        tooltip = ns.L["View another character's bags"],
        listOwners = function()
            return Bags.OwnerSelect.BuildOwnerList(
                Storage.Store.ListCharacters(), Storage.Store.GetCurrentCharacterKey())
        end,
        current = function()
            return viewedCharacter or Storage.Store.GetCurrentCharacterKey()
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

local function SearchResultFor(cell)
    if not matcher then return nil end
    local details = Bags.Details.Build(cell.entry)
    if details then
        return matcher(details) ~= false
    end
    return false
end

local function DressPlacedCell(cell, btn, live, rightClickRoute)
    local result = SearchResultFor(cell)
    if live then
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
        if dep._quiPassThroughFailed and not InCombatLockdown() then
            if ns.SafeCallMethod("defer-ooc", dep, "SetPassThroughButtons", "LeftButton") then
                dep._quiPassThroughFailed = nil
            end
        end
        dep:SetShown(live and not selectMode
            and not dep._quiPassThroughFailed
            and cell.entry ~= nil
            and rightClickRoute ~= nil)
    end
end

local function UpdateFreeText(slots)
    local free = 0
    for _, cell in ipairs(slots) do
        if not cell.entry then free = free + 1 end
    end
    win._free:SetText(free .. " " .. ns.L["free"])
end

local function SignatureOpts(appearance)
    return {
        layoutMode = appearance.layoutMode,
        reagentDisplay = appearance.reagentDisplay,
        groupEmptySlots = appearance.groupEmptySlots and true or false,
        getRecent = function(cell) return cell._newGuid ~= nil end,
    }
end

local function ButtonFor(cell, live)
    local pool = live and buttons[cell.bagID] or cachedButtons[cell.bagID]
    return pool and pool[cell.slot]
end

function BagWindow.Refresh()
    if not win or not win:IsShown() then return end
    local s = GetSettings()
    local appearance = Bags.Chassis.ClampAppearance((s and s.appearance) or nil)

    local slots = CollectSlots()
    local live = (viewedCharacter == nil)
    local core = Helpers.GetCore()
    local snappedSize, snappedGap = appearance.iconSize, appearance.spacing
    local px = core and core.GetPixelSize and core:GetPixelSize(win) or nil
    if px and px > 0 then
        snappedSize = math.floor(appearance.iconSize / px + 0.5) * px
        snappedGap = math.floor(appearance.spacing / px + 0.5) * px
    end

    if live and Bags.NewItems then
        for _, cell in ipairs(slots) do
            if cell.entry then
                cell._newGuid = Bags.NewItems.CheckSlot(cell.bagID, cell.slot, cell.entry)
            else
                cell._newGuid = nil
            end
        end
    end

    local categoriesMode = appearance.layoutMode == "categories"
    local gridOpts = {
        columns = appearance.columns, iconSize = snappedSize, spacing = snappedGap,
        headerHeight = CAT_HEADER_H,
    }
    local placed
    local catHeaders, contentW, contentH
    if categoriesMode then
        for _, cell in ipairs(slots) do
            cell.recent = cell._newGuid ~= nil
        end
        local groups = Bags.CategoryLayout.Group(slots, Bags.Details.Build)
        local cl = Bags.CategoryLayout.Compute(groups, gridOpts)
        placed, catHeaders = cl.buttons, cl.headers
        contentW, contentH = cl.width, cl.height
        if contentW == 0 then
            local empty = Bags.GridLayout.Compute(0, gridOpts)
            contentW, contentH = empty.width, 0
        end
    else
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
            catHeaders = { { title = ns.L["Reagents"], y = headerY } }
            local rl = Bags.GridLayout.Compute(#reagentCells, gridOpts)
            local cellTop = headerY - CAT_HEADER_H
            for i, cell in ipairs(reagentCells) do
                placed[#placed + 1] = { cell = cell, x = rl[i].x, y = cellTop + rl[i].y }
            end
            contentW = math.max(contentW, rl.width)
            contentH = contentH + gapAbove + CAT_HEADER_H + rl.height
        end
    end

    local stripH = 0
    local showStrip = live and (not appearance or appearance.showBagSlots ~= false)
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
        stripH = 16
    end
    if stripH > 0 then
        for _, p in ipairs(placed) do p.y = p.y - stripH end
        if catHeaders then
            for _, h in ipairs(catHeaders) do h.y = h.y - stripH end
        end
        contentH = contentH + stripH
    end

    local currencyH = win._currencyBar
        and win._currencyBar:Update(ViewedRecord(), viewedCharacter == nil) or 0
    win._ownerSelect:Update()

    if live then
        local sr, sg, sb = Helpers.GetSkinColors()
        UIKit.UpdateBorderLines(win._sortBtn, 1, sr, sg, sb, 0.35)
        win._sortBtn:Show()
    else
        win._sortBtn:Hide()
    end

    if not live and selectMode then ClearSelection() end
    if live then
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
    local gridW = contentW
    contentW = math.max(contentW, headerMinW)
    local xOff = 0
    if contentW > gridW and gridW > 0 then
        xOff = (contentW - gridW) / 2
        if px and px > 0 then xOff = math.floor(xOff / px + 0.5) * px end
    end
    win:SetContentSize(contentW, contentH + currencyH)

    RenderCategoryHeaders(catHeaders, xOff)

    for _, byBag in pairs(buttons) do
        for _, btn in pairs(byBag) do btn:Hide() end
    end
    for _, byBag in pairs(cachedButtons) do
        for _, btn in pairs(byBag) do btn:Hide() end
    end
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
                local catcher = CreateFrame("Button", nil, btn)
                catcher:SetAllPoints()
                catcher:SetFrameLevel(btn:GetFrameLevel() + 5)
                catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                catcher:SetScript("OnClick", function(_, mouseButton)
                    if mouseButton == "RightButton" then
                        SendSelection()
                        return
                    end
                    local bagID, slot = btn:GetBagID(), btn:GetID()
                    local info = C_Container.GetContainerItemInfo(bagID, slot)
                    if info then
                        local key = bagID .. ":" .. slot
                        if selectedCells[key] then
                            selectedCells[key] = nil
                        else
                            selectedCells[key] = { bag = bagID, slot = slot, itemID = info.itemID }
                        end
                        Bags.ItemButtons.SetSelectedOverlay(btn, selectedCells[key] ~= nil)
                        UpdateSendButton()
                    end
                end)
                catcher:SetScript("OnEnter", function(self)
                    Bags.ItemButtons.DismissNewItemGlow(btn)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetBagItem(btn:GetBagID(), btn:GetID())
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(ns.L["Click: select / deselect."], 0.2, 0.82, 1, true)
                    local dest = SendDestination()
                    local n = SelectedCount()
                    if dest and n > 0 then
                        GameTooltip:AddLine((ns.L["Right-click: %s %d selected items."]):format(
                            dest.verb, n), 0.2, 0.82, 1, true)
                    end
                    GameTooltip:Show()
                end)
                catcher:SetScript("OnLeave", function() GameTooltip:Hide() end)
                catcher:Hide()
                btn._quiSelectCatcher = catcher
                local dep = CreateFrame("Button", nil, btn)
                dep:SetAllPoints()
                dep:SetFrameLevel(btn:GetFrameLevel() + 4)
                dep:RegisterForClicks("RightButtonUp")
                if InCombatLockdown()
                    or not ns.SafeCallMethod("defer-ooc", dep, "SetPassThroughButtons", "LeftButton") then
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
                    Bags.ItemButtons.DismissNewItemGlow(btn)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetBagItem(btn:GetBagID(), btn:GetID())
                    GameTooltip:AddLine(" ")
                    if RightClickRoute() == "auction" then
                        local loc = ItemLocation:CreateFromBagAndSlot(
                            btn:GetBagID(), btn:GetID())
                        if loc and loc:IsValid()
                            and C_AuctionHouse.IsSellItemValid(loc, false) then
                            GameTooltip:AddLine(ns.L["Right-click: sell at the auction house."],
                                0.2, 0.82, 1, true)
                        else
                            GameTooltip:AddLine(ns.L["This item can't be put up for auction."],
                                0.6, 0.6, 0.6, true)
                        end
                    else
                        GameTooltip:AddLine(ns.L["Right-click: deposit into the open bank tab."],
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
        DressPlacedCell(cell, btn, live, rightClickRoute)
        btn:Show()
    end

    UpdateFreeText(slots)
    UpdateMoneyText()

    local junkCfg = s and s.behavior and s.behavior.junk
    if live and junkCfg and junkCfg.sellButton and Bags.Junk.IsMerchantOpen() then
        win._sellBtn:Show()
    else
        win._sellBtn:Hide()
    end

    UpdateSendButton()

    repaint.placed = placed
    repaint.live = live
    repaint.sig = Bags.RefreshScope.LayoutSignature(slots,
        SignatureOpts(appearance), Bags.Details.Build)
    repaint.contentW, repaint.contentH = contentW, contentH
    local index = {}
    for _, p in ipairs(placed) do
        local byBag = index[p.cell.bagID]
        if not byBag then byBag = {}; index[p.cell.bagID] = byBag end
        byBag[p.cell.slot] = p
    end
    repaint.index = index
    repaint.pendingFull, repaint.pendingDressAll = false, false
    repaint.pendingBags, repaint.pendingSearch, repaint.pendingCurrency = nil, false, false
end

local function RedressCells(only)
    local live = viewedCharacter == nil
    local rec = ViewedRecord()
    local rightClickRoute = RightClickRoute()
    for _, p in ipairs(repaint.placed) do
        local cell = p.cell
        if not only or only[cell.bagID] then
            local bag = rec and rec.bags and rec.bags[cell.bagID]
            cell.entry = bag and bag.slots and bag.slots[cell.slot] or nil
            if live and Bags.NewItems then
                cell._newGuid = cell.entry
                    and Bags.NewItems.CheckSlot(cell.bagID, cell.slot, cell.entry) or nil
            end
            local btn = ButtonFor(cell, live)
            if btn then DressPlacedCell(cell, btn, live, rightClickRoute) end
        end
    end
end

local function SearchPass()
    local live = viewedCharacter == nil
    for _, p in ipairs(repaint.placed) do
        local btn = ButtonFor(p.cell, live)
        if btn then
            Bags.ItemButtons.SetSearchDim(btn, SearchResultFor(p.cell))
        end
    end
end

local function UpdateCurrencyBar()
    local currencyH = win._currencyBar
        and win._currencyBar:Update(ViewedRecord(), viewedCharacter == nil) or 0
    win:SetContentSize(repaint.contentW, repaint.contentH + currencyH)
end

local function UpdateBagSlotStripCounts()
    if not (win and win._bagSlotButtons) then return end
    for i, b in ipairs(win._bagSlotButtons) do
        if b:IsShown() and b._icon:IsShown() then
            b._count:SetText(C_Container.GetContainerNumFreeSlots(i) or "")
        end
    end
end

RunScheduledRepaint = function()
    local full = repaint.pendingFull
    local dressAll = repaint.pendingDressAll
    local bagSet = repaint.pendingBags
    local search = repaint.pendingSearch
    local currency = repaint.pendingCurrency
    repaint.pendingFull, repaint.pendingDressAll = false, false
    repaint.pendingBags, repaint.pendingSearch, repaint.pendingCurrency = nil, false, false
    if not (win and win:IsShown()) then return end
    local live = viewedCharacter == nil
    if full or not repaint.placed or repaint.live ~= live
        or not (dressAll or bagSet or search or currency) then
        BagWindow.Refresh()
        return
    end
    if bagSet and not live then
        dressAll, bagSet = true, nil
    end
    if bagSet then
        local s = GetSettings()
        local appearance = Bags.Chassis.ClampAppearance((s and s.appearance) or nil)
        local slots = CollectSlots()
        if Bags.NewItems then
            for _, cell in ipairs(slots) do
                if cell.entry then
                    cell._newGuid = Bags.NewItems.CheckSlot(cell.bagID, cell.slot, cell.entry)
                end
            end
        end
        local sig = Bags.RefreshScope.LayoutSignature(slots,
            SignatureOpts(appearance), Bags.Details.Build)
        if sig ~= repaint.sig then
            BagWindow.Refresh()
            return
        end
        RedressCells(dressAll and nil or bagSet)
        UpdateFreeText(slots)
        UpdateBagSlotStripCounts()
    elseif dressAll then
        RedressCells(nil)
    end
    if search then SearchPass() end
    if currency then UpdateCurrencyBar() end
end

function BagWindow.Show()
    EnsureWindow()
    local wasShown = win:IsShown()
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

function BagWindow.FocusItem(itemID, ownerKey)
    EnsureWindow()
    local wasShown = win:IsShown()
    if not wasShown then
        win:Show()
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_BACKPACK_OPEN then
            PlaySound(SOUNDKIT.IG_BACKPACK_OPEN)
        end
    end
    if ownerKey == nil or ownerKey == Storage.Store.GetCurrentCharacterKey() then
        viewedCharacter = nil
    else
        viewedCharacter = ownerKey
    end
    focusItemID = itemID
    if C_Timer and C_Timer.After then
        C_Timer.After(3, function()
            if focusItemID == itemID then
                focusItemID = nil
                repaint.pendingDressAll = true
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

function BagWindow.SetViewedCharacter(key)
    if key == nil or key == Storage.Store.GetCurrentCharacterKey() then
        viewedCharacter = nil
    else
        viewedCharacter = key
    end
    BagWindow.Refresh()
end

function BagWindow.OnProfileChanged()
    if not win then return end
    win:ApplyPosition()
    if win:IsShown() then BagWindow.Refresh() end
end

Storage.Bus.Subscribe("BagsChanged", function(_, _, changed)
    local scope = Bags.RefreshScope.Classify(changed)
    if scope == "full" then
        repaint.pendingFull = true
    elseif scope == "dress-all" then
        repaint.pendingDressAll = true
    else
        repaint.pendingBags = Bags.RefreshScope.UnionBags(repaint.pendingBags, changed)
    end
    ScheduleRefresh()
end)

Storage.Bus.Subscribe("MoneyChanged", function()
    if win and win:IsShown() and win._money and not viewedCharacter then
        UpdateMoneyText()
    end
end)

Storage.Bus.Subscribe("MerchantChanged", function()
    ScheduleRefresh()
end)

Storage.Bus.Subscribe("AuctionHouseChanged", function()
    ScheduleRefresh()
end)

Storage.Bus.Subscribe("CurrenciesChanged", function()
    repaint.pendingCurrency = true
    ScheduleRefresh()
end)
