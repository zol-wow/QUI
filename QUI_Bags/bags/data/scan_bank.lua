---------------------------------------------------------------------------
-- Bags data layer: bank scanner.
-- Character bank tabs (bag IDs 6–11) persist on the character record;
-- warband/account tabs (12–16) persist on the shared warband record.
-- Tab metadata (name/icon/depositFlags) comes from C_Bank and is overlaid
-- onto each scanned tab. A locked account bank (FetchBankLockedReason ~= nil)
-- suppresses warband scanning entirely.
-- Drain snapshot-swaps its dirty sets and async re-marks are gated on load
-- success — same hazards and remedies as scan_bags.lua (see its comments).
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags

local ScanBank = {}
Bags.ScanBank = ScanBank

local CHAR_FIRST, CHAR_LAST = 6, 11
local WB_FIRST, WB_LAST = 12, 16

local dirtyChar, dirtyWarband = {}, {}
local hasDirty = false
local charMeta, warbandMeta = {}, {}   -- tabID → BankTabData
local warbandUnlocked = false

function ScanBank.IsCharTab(bagID)
    return bagID >= CHAR_FIRST and bagID <= CHAR_LAST
end

function ScanBank.IsWarbandTab(bagID)
    return bagID >= WB_FIRST and bagID <= WB_LAST
end

--- Refresh purchased-tab metadata from C_Bank; also captures warband money.
--- Call on BANKFRAME_OPENED / BANK_TABS_CHANGED / BANK_TAB_SETTINGS_UPDATED.
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
        local warband = Bags.Store.GetWarband()
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

--- Mark every purchased tab dirty (requires RefreshTabMetadata first).
function ScanBank.MarkAllDirty()
    for id in pairs(charMeta) do dirtyChar[id] = true; hasDirty = true end
    if warbandUnlocked then
        for id in pairs(warbandMeta) do dirtyWarband[id] = true; hasDirty = true end
    end
end

local function ReadTab(bagID, meta)
    local tab = Bags.ScanCommon.ReadContainer(bagID, Bags.ScanCommon.MakePendingHandler(bagID, ScanBank.MarkDirty))
    if meta then
        tab.name = meta.name
        tab.icon = meta.icon
        tab.depositFlags = meta.depositFlags
    end
    return tab
end

--- Re-read every dirty tab; publishes BankChanged / WarbandChanged per
--- surface. Returns true when anything was written.
function ScanBank.Drain()
    if not hasDirty then return false end
    local rec = Bags.Store.GetCurrentCharacter()
    local warband = Bags.Store.GetWarband()
    if not rec or not warband then return false end -- transient: marks preserved
    -- Snapshot-swap BEFORE reading (synchronous ITEM_DATA_LOAD_RESULT can
    -- re-mark a tab inside ReadContainer; see scan_bags.lua).
    local charScan, wbScan = dirtyChar, dirtyWarband
    dirtyChar, dirtyWarband = {}, {}
    hasDirty = false
    local changedChar, changedWb = {}, {}
    for bagID in pairs(charScan) do
        local tab = ReadTab(bagID, charMeta[bagID])
        local old = rec.bankTabs[bagID]
        -- size 0 while the cache has a sized tab = container unreadable
        -- (away from banker); keep the cache, drop the mark — the next
        -- BANKFRAME_OPENED full-scan refreshes it.
        if tab.size == 0 and old and old.size > 0 then
            -- skip: unreadable now
        else
            rec.bankTabs[bagID] = tab
            changedChar[#changedChar + 1] = bagID
        end
    end
    for bagID in pairs(wbScan) do
        local tab = ReadTab(bagID, warbandMeta[bagID])
        local old = warband.tabs[bagID]
        if tab.size == 0 and old and old.size > 0 then
            -- skip: unreadable now
        else
            warband.tabs[bagID] = tab
            changedWb[#changedWb + 1] = bagID
        end
    end
    if #changedChar > 0 then
        Bags.Bus.Publish("BankChanged", Bags.Store.GetCurrentCharacterKey(), changedChar)
    end
    if #changedWb > 0 then
        Bags.Bus.Publish("WarbandChanged", changedWb)
    end
    return (#changedChar + #changedWb) > 0
end
