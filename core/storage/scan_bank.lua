local ADDON_NAME, ns = ...
local Storage = ns.Storage or {}; ns.Storage = Storage

local ScanBank = {}
Storage.ScanBank = ScanBank

local CHAR_FIRST, CHAR_LAST = 6, 11
local WB_FIRST, WB_LAST = 12, 16

local dirtyChar, dirtyWarband = {}, {}
local hasDirty = false
local charMeta, warbandMeta = {}, {}
local warbandUnlocked = false

function ScanBank.IsCharTab(bagID)
    return bagID >= CHAR_FIRST and bagID <= CHAR_LAST
end

function ScanBank.IsWarbandTab(bagID)
    return bagID >= WB_FIRST and bagID <= WB_LAST
end

function ScanBank.RefreshTabMetadata()
    local charTabs = C_Bank.FetchPurchasedBankTabData(Enum.BankType.Character)
    if charTabs and #charTabs > 0 then
        charMeta = {}
        for i = 1, #charTabs do local t = charTabs[i]; charMeta[t.ID] = t end
    end
    warbandUnlocked = C_Bank.FetchBankLockedReason(Enum.BankType.Account) == nil
    if warbandUnlocked then
        local wbTabs = C_Bank.FetchPurchasedBankTabData(Enum.BankType.Account)
        if wbTabs and #wbTabs > 0 then
            warbandMeta = {}
            for i = 1, #wbTabs do local t = wbTabs[i]; warbandMeta[t.ID] = t end
        end
        local warband = Storage.Store.GetWarband()
        if warband then
            warband.money = C_Bank.FetchDepositedMoney(Enum.BankType.Account)
        end
    end
end

function ScanBank.MarkDirty(bagID)
    if ScanBank.IsCharTab(bagID) then
        dirtyChar[bagID] = true
        hasDirty = true
    elseif ScanBank.IsWarbandTab(bagID) and warbandUnlocked then
        dirtyWarband[bagID] = true
        hasDirty = true
    end
end

function ScanBank.MarkAllDirty()
    for id in pairs(charMeta) do dirtyChar[id] = true; hasDirty = true end
    if warbandUnlocked then
        for id in pairs(warbandMeta) do dirtyWarband[id] = true; hasDirty = true end
    end
end

local function ReadTab(bagID, meta)
    local tab = Storage.ScanCommon.ReadContainer(bagID, Storage.ScanCommon.MakePendingHandler(bagID, ScanBank.MarkDirty))
    if meta then
        tab.name = meta.name
        tab.icon = meta.icon
        tab.depositFlags = meta.depositFlags
    end
    return tab
end

function ScanBank.Drain()
    if not hasDirty then return false end
    local rec = Storage.Store.GetCurrentCharacter()
    local warband = Storage.Store.GetWarband()
    if not rec or not warband then return false end
    local charScan, wbScan = dirtyChar, dirtyWarband
    dirtyChar, dirtyWarband = {}, {}
    hasDirty = false
    local changedChar, changedWb = {}, {}
    for bagID in pairs(charScan) do
        local tab = ReadTab(bagID, charMeta[bagID])
        local old = rec.bankTabs[bagID]
        if tab.size == 0 and old and old.size > 0 then
        else
            rec.bankTabs[bagID] = tab
            changedChar[#changedChar + 1] = bagID
        end
    end
    for bagID in pairs(wbScan) do
        local tab = ReadTab(bagID, warbandMeta[bagID])
        local old = warband.tabs[bagID]
        if tab.size == 0 and old and old.size > 0 then
        else
            warband.tabs[bagID] = tab
            changedWb[#changedWb + 1] = bagID
        end
    end
    if #changedChar > 0 then
        Storage.Bus.Publish("BankChanged", Storage.Store.GetCurrentCharacterKey(), changedChar)
    end
    if #changedWb > 0 then
        Storage.Bus.Publish("WarbandChanged", changedWb)
    end
    return (#changedChar + #changedWb) > 0
end
