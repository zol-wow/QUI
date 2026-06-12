---------------------------------------------------------------------------
-- Core storage: callback bus.
-- Snapshot-on-publish + xpcall isolation (same semantics as the cdm
-- resolver bus). Publish frequency is scan-rate, not frame-rate, so the
-- closure wrapper cost is irrelevant — and it keeps stock-Lua test runs
-- identical to in-game behavior (stock xpcall forwards no trailing args).
--
-- Events (published by core/storage and module entries, consumed by anything):
--   "BagsChanged"    (charKey, changedBagIDs)
--   "BankChanged"    (charKey, changedTabIDs)
--   "WarbandChanged" (changedTabIDs)
--
-- Changed-array contract: SCANNER publishes always carry a NON-EMPTY
-- changed array (the scanners publish only after writing at least one
-- container). A literal {} is a SYNTHETIC re-dress ping (bags.lua's
-- lock/cooldown route) — "re-render yourself", no data changed. Consumers
-- that react to data movement (the sort executor) ignore empty arrays.
--   "MoneyChanged"     ()
--   "CharacterDeleted" (charKey)
--   "GuildChanged"     (guildKey, changedTabs)  -- scanner publishes after drain
--   "GuildDeleted"     (guildKey)
--   "GuildMoneyChanged" ()  -- GUILDBANK_UPDATE_MONEY / _WITHDRAWMONEY → window footer
--   "MerchantChanged"  (shown)  -- ops/junk.lua OnMerchant → Sell Junk button visibility
--   "AuctionHouseChanged" (shown) -- AH session open/close edge (collector) → bag window
--
-- Phase-6 cache-breadth events: their rescan unit is the WHOLE record
-- (payload-free triggering events), so they carry no changed array at all —
-- the {}-is-synthetic rule above stays true.
--   "MailChanged"       (charKey)  -- rec.mail rewritten (mailbox sessions)
--   "EquippedChanged"   (charKey)  -- rec.equipped slots rewritten
--   "CharacterChanged"  (charKey)  -- rec.details roster fields rewritten
--                       (money-only changes ride "MoneyChanged" instead —
--                       roster consumers subscribe to both)
--   "CurrenciesChanged" (charKey)  -- rec.currencies map rewritten
--   "ProfessionsChanged" (charKey) -- rec.professions list rewritten
--   "ReputationsChanged" (charKey) -- rec.reputations map rewritten
--   "WeekliesChanged"   (charKey)  -- rec.weeklies rewritten (vault/M+/keystone)
--   "LockoutsChanged"   (charKey)  -- rec.lockouts list rewritten
--   "AuctionsChanged"   (charKey)  -- rec.auctions rewritten (AH sessions)
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Storage = ns.Storage or {}; ns.Storage = Storage

local unpack = table.unpack or unpack

local Bus = {}
Storage.Bus = Bus

local subscribers = {}

function Bus.Subscribe(eventName, handler)
    local list = subscribers[eventName]
    if not list then list = {}; subscribers[eventName] = list end
    list[#list + 1] = handler
end

function Bus.Unsubscribe(eventName, handler)
    local list = subscribers[eventName]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == handler then table.remove(list, i); return end
    end
end

function Bus.Publish(eventName, ...)
    local list = subscribers[eventName]
    if not list then return end
    local n = #list
    if n == 0 then return end
    local snapshot = {}
    for i = 1, n do snapshot[i] = list[i] end
    local args, nargs = { ... }, select("#", ...)
    for i = 1, n do
        local fn = snapshot[i]
        xpcall(function() fn(eventName, unpack(args, 1, nargs)) end, geterrorhandler())
    end
end
