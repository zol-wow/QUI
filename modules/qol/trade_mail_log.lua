local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local GetSettings = Helpers.CreateDBGetter("general")

local MAX_ENTRIES = 300

local function Cfg()
    local s = GetSettings()
    return s and s.tradeMailLog or nil
end

local function Enabled(subKey)
    local cfg = Cfg()
    if not cfg or not cfg.enabled then return false end
    if subKey and cfg[subKey] == false then return false end
    return true
end

local function GetLog()
    local db = ns.Addon and ns.Addon.db
    local g = db and db.global
    if not g then return nil end
    if type(g.tradeMailLog) ~= "table" then g.tradeMailLog = {} end
    if type(g.tradeMailLog.entries) ~= "table" then g.tradeMailLog.entries = {} end
    return g.tradeMailLog.entries
end

local function AddEntry(entry)
    local entries = GetLog()
    if not entries then return end
    entry.time = entry.time or time()
    entry.who = UnitName("player")
    table.insert(entries, 1, entry)
    for i = #entries, MAX_ENTRIES + 1, -1 do
        table.remove(entries, i)
    end
end

local tradeState

local function TradeItemSlots()
    local maxSlots = MAX_TRADE_ITEMS or 7
    if TRADE_ENCHANT_SLOT and maxSlots == TRADE_ENCHANT_SLOT then
        maxSlots = maxSlots - 1
    end
    return math.max(maxSlots, 1)
end

local function SnapshotTradeItems(isTarget)
    local items = {}
    for i = 1, TradeItemSlots() do
        local name, _, count
        if isTarget then
            name, _, count = GetTradeTargetItemInfo(i)
        else
            name, _, count = GetTradePlayerItemInfo(i)
        end
        if name then
            local link = isTarget and GetTradeTargetItemLink(i) or GetTradePlayerItemLink(i)
            items[#items + 1] = { link = link or name, count = count or 1 }
        end
    end
    return items
end

local function UpdateTradeSnapshot()
    if not tradeState then return end
    tradeState.gave = SnapshotTradeItems(false)
    tradeState.got = SnapshotTradeItems(true)
    tradeState.gaveMoney = GetPlayerTradeMoney and GetPlayerTradeMoney() or 0
    tradeState.gotMoney = GetTargetTradeMoney and GetTargetTradeMoney() or 0
end

local function StartTrade()
    local partner = GetUnitName and GetUnitName("NPC", true) or nil
    if not partner or partner == "" then partner = UNKNOWN or "Unknown" end
    tradeState = {
        kind = "trade",
        partner = partner,
        zone = GetRealZoneText and GetRealZoneText() or "",
        playerAccepted = 0,
        targetAccepted = 0,
    }
    UpdateTradeSnapshot()
end

local function HasTradeContent(state)
    return (state.gaveMoney or 0) > 0 or (state.gotMoney or 0) > 0
        or #(state.gave or {}) > 0 or #(state.got or {}) > 0
end

local function FinishTrade()
    local state = tradeState
    tradeState = nil
    if not state then return end
    state.completed = state.playerAccepted == 1 and state.targetAccepted == 1
    if HasTradeContent(state) or state.completed then
        AddEntry(state)
    end
end

local pendingSend

local function CaptureSendMail()
    if not Enabled("logSentMail") then return end
    local nameBox = _G.SendMailNameEditBox
    local subjectBox = _G.SendMailSubjectEditBox
    if not nameBox then return end
    local entry = {
        kind = "mailSent",
        partner = nameBox:GetText() or "",
        subject = subjectBox and subjectBox:GetText() or "",
        gaveMoney = GetSendMailMoney and GetSendMailMoney() or 0,
        cod = GetSendMailCOD and GetSendMailCOD() or 0,
        gave = {},
    }
    for i = 1, (ATTACHMENTS_MAX_SEND or 12) do
        if HasSendMailItem and HasSendMailItem(i) then
            local itemName, _, _, count = GetSendMailItem(i)
            local link = GetSendMailItemLink and GetSendMailItemLink(i) or itemName
            if itemName then
                entry.gave[#entry.gave + 1] = { link = link or itemName, count = count or 1 }
            end
        end
    end
    pendingSend = entry
end

local loggedInbox = {}

local function LogInboxMail(index)
    if not Enabled("logReceivedMail") then return end
    if not index or not GetInboxHeaderInfo then return end
    local _, _, sender, subject, money, cod, _, itemCount = GetInboxHeaderInfo(index)
    if not sender then return end
    local dedupeKey = tostring(index) .. "|" .. tostring(sender) .. "|" .. tostring(subject)
    if loggedInbox[dedupeKey] then return end
    loggedInbox[dedupeKey] = true

    local entry = {
        kind = "mailReceived",
        partner = sender,
        subject = subject or "",
        gotMoney = money or 0,
        cod = cod or 0,
        got = {},
    }
    if (itemCount or 0) > 0 and GetInboxItem then
        for i = 1, (ATTACHMENTS_MAX_RECEIVE or ATTACHMENTS_MAX_SEND or 12) do
            local itemName, _, _, count = GetInboxItem(index, i)
            if itemName then
                local link = GetInboxItemLink and GetInboxItemLink(index, i) or itemName
                entry.got[#entry.got + 1] = { link = link or itemName, count = count or 1 }
            end
        end
    end
    AddEntry(entry)
end

local function Coins(amount)
    if not amount or amount <= 0 then return nil end
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        return C_CurrencyInfo.GetCoinTextureString(amount)
    end
    return tostring(amount) .. "c"
end

local function ItemsText(items)
    if not items or #items == 0 then return nil end
    local parts = {}
    for _, item in ipairs(items) do
        local text = item.link or "?"
        if (item.count or 1) > 1 then text = text .. "x" .. item.count end
        parts[#parts + 1] = text
    end
    return table.concat(parts, " ")
end

local function DescribeEntry(entry)
    local when = date("%m-%d %H:%M", entry.time or 0)
    local pieces = { "|cff60A5FA[" .. when .. "]|r" }
    if entry.kind == "trade" then
        pieces[#pieces + 1] = (entry.completed and "|cff40C060Trade|r" or "|cffC04040Trade (cancelled)|r")
            .. " " .. ns.L["with"] .. " " .. (entry.partner or "?")
        local gave = ItemsText(entry.gave)
        local gaveMoney = Coins(entry.gaveMoney)
        if gave or gaveMoney then
            pieces[#pieces + 1] = "|cffFF8080" .. ns.L["gave:"] .. "|r "
                .. table.concat({ gave, gaveMoney }, " ")
        end
        local got = ItemsText(entry.got)
        local gotMoney = Coins(entry.gotMoney)
        if got or gotMoney then
            pieces[#pieces + 1] = "|cff80FF80" .. ns.L["got:"] .. "|r "
                .. table.concat({ got, gotMoney }, " ")
        end
    elseif entry.kind == "mailSent" then
        pieces[#pieces + 1] = "|cffFFD080" .. ns.L["Mail to"] .. "|r " .. (entry.partner or "?")
        if entry.subject and entry.subject ~= "" then
            pieces[#pieces + 1] = '"' .. entry.subject .. '"'
        end
        local gave = ItemsText(entry.gave)
        if gave then pieces[#pieces + 1] = gave end
        local gaveMoney = Coins(entry.gaveMoney)
        if gaveMoney then pieces[#pieces + 1] = gaveMoney end
        local cod = Coins(entry.cod)
        if cod then pieces[#pieces + 1] = "COD " .. cod end
    elseif entry.kind == "mailReceived" then
        pieces[#pieces + 1] = "|cff80D0FF" .. ns.L["Mail from"] .. "|r " .. (entry.partner or "?")
        if entry.subject and entry.subject ~= "" then
            pieces[#pieces + 1] = '"' .. entry.subject .. '"'
        end
        local got = ItemsText(entry.got)
        if got then pieces[#pieces + 1] = got end
        local gotMoney = Coins(entry.gotMoney)
        if gotMoney then pieces[#pieces + 1] = gotMoney end
        local cod = Coins(entry.cod)
        if cod then pieces[#pieces + 1] = "COD " .. cod end
    end
    return table.concat(pieces, " ")
end

SLASH_QUILOG1 = "/quilog"
SlashCmdList["QUILOG"] = function(msg)
    local entries = GetLog()
    if not entries or #entries == 0 then
        print("|cff60A5FAQUI:|r " .. ns.L["Trade & mail log is empty."])
        return
    end
    local n = math.min(tonumber(msg) or 10, #entries)
    print(("|cff60A5FAQUI Trade & Mail Log|r — %d/%d:"):format(n, #entries))
    for i = n, 1, -1 do
        print(DescribeEntry(entries[i]))
    end
end

local hooksInstalled = false
local function InstallMailHooks()
    if hooksInstalled then return end
    if type(_G.SendMailFrame_SendMail) ~= "function" then return end
    hooksInstalled = true
    hooksecurefunc("SendMailFrame_SendMail", CaptureSendMail)
    hooksecurefunc("InboxFrame_OnClick", function(_, index)
        LogInboxMail(index)
    end)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("TRADE_SHOW")
frame:RegisterEvent("TRADE_CLOSED")
frame:RegisterEvent("TRADE_ACCEPT_UPDATE")
frame:RegisterEvent("TRADE_UPDATE")
frame:RegisterEvent("TRADE_PLAYER_ITEM_CHANGED")
frame:RegisterEvent("TRADE_TARGET_ITEM_CHANGED")
frame:RegisterEvent("TRADE_MONEY_CHANGED")
frame:RegisterEvent("PLAYER_TRADE_MONEY")
frame:RegisterEvent("MAIL_SHOW")
frame:RegisterEvent("MAIL_SEND_SUCCESS")
frame:RegisterEvent("MAIL_FAILED")
frame:RegisterEvent("MAIL_CLOSED")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "TRADE_SHOW" then
        if Enabled("logTrades") then StartTrade() end
    elseif event == "TRADE_ACCEPT_UPDATE" then
        if tradeState then
            local playerAccepted, targetAccepted = ...
            tradeState.playerAccepted = playerAccepted or 0
            tradeState.targetAccepted = targetAccepted or 0
            UpdateTradeSnapshot()
        end
    elseif event == "TRADE_CLOSED" then
        FinishTrade()
    elseif event == "MAIL_SHOW" then
        InstallMailHooks()
        wipe(loggedInbox)
    elseif event == "MAIL_SEND_SUCCESS" then
        if pendingSend then
            AddEntry(pendingSend)
            pendingSend = nil
        end
    elseif event == "MAIL_FAILED" or event == "MAIL_CLOSED" then
        pendingSend = nil
    else
        if tradeState then UpdateTradeSnapshot() end
    end
end)
