-- tests/unit/bags_module_gate_test.lua
-- Verifies the module entry: enabled gate controls event registration,
-- drain scheduling coalesces, and Registry registration shape is right.
-- Run: lua tests/unit/bags_module_gate_test.lua
-- luacheck: globals QUI_StorageDB
local loader = dofile("tests/helpers/load_bags_data.lua")
loader.InstallBaseStubs()
_G.C_Container.GetContainerNumSlots = function() return 0 end
_G.C_Container.GetContainerItemInfo = function() return nil end
_G.C_Bank.FetchPurchasedBankTabData = function() return nil end
_G.C_Bank.FetchBankLockedReason = function() return nil end
_G.C_Bank.FetchDepositedMoney = function() return 0 end
_G.Enum.PlayerInteractionType = { Merchant = 5, MailInfo = 17 }

-- Frame stub capturing registration + scripts
local registered, scripts = {}, {}
local frame = {}
function frame.RegisterEvent(_, ev) registered[ev] = true end
function frame.UnregisterEvent(_, ev) registered[ev] = nil end
function frame.SetScript(_, which, fn) scripts[which] = fn end
_G.CreateFrame = function() return frame end

local settings = { enabled = false }
local registryDefs = {}
local ns = loader.LoadAll()
ns.Helpers = { CreateDBGetter = function() return function() return settings end end }
ns.Registry = { Register = function(_, name, def) registryDefs[name] = def end }
local firstFrameQueue = {}
ns.RunAfterFirstFrame = function(fn) firstFrameQueue[#firstFrameQueue + 1] = fn end
-- bags.lua is a LoadOnDemand sub-addon: it starts up via ns.WhenLoggedIn (which
-- fires immediately when already logged in), NOT a raw PLAYER_LOGIN event that
-- would never fire for a post-login LOD load. Capture the startup callback so
-- Test 2 can drive login deterministically.
local loginCallback
ns.WhenLoggedIn = function(fn) loginCallback = fn end

-- bags.lua wires the takeover/window/auto-open surfaces, which live outside
-- the data layer the loader covers — stub them and log the lifecycle calls.
local takeoverLog = {}
ns.Bags.Takeover = {
    Apply = function() takeoverLog[#takeoverLog + 1] = "apply" end,
    Revert = function() takeoverLog[#takeoverLog + 1] = "revert" end,
}
local logger = function(name) return function() takeoverLog[#takeoverLog + 1] = name end end
local bankLive = false
ns.Bags.BankTakeover = {
    Suppress      = logger("bank-suppress"),
    Revert        = logger("bank-revert"),
    OnBankOpened  = logger("bank-opened"),
    OnBankClosed  = logger("bank-closed"),
    IsLive        = function() return bankLive end,
}
local bagToggles = 0
ns.Bags.BagWindow  = {
    Hide    = logger("bag-window-hide"),
    IsShown = function() return false end,
    Toggle  = function() bagToggles = bagToggles + 1 end,
}
local searchWindowHides, searchToggles = 0, 0
ns.Bags.SearchWindow = {
    Hide   = function()
        searchWindowHides = searchWindowHides + 1
        takeoverLog[#takeoverLog + 1] = "search-window-hide"
    end,
    Toggle = function() searchToggles = searchToggles + 1 end,
}
local bankWindowHides = 0
local bankShows = {}
ns.Bags.BankWindow = {
    Hide            = function()
        bankWindowHides = bankWindowHides + 1
        takeoverLog[#takeoverLog + 1] = "bank-window-hide"
    end,
    IsShown         = function() return false end,
    ShowLive        = function() bankShows[#bankShows + 1] = "live" end,
    ShowCached      = function() bankShows[#bankShows + 1] = "cached" end,
    OnProfileChanged = function() end,
}
local guildWindowHides = 0
local guildWindowShown = false
local guildLogUpdates = 0
local guildShows = {}
ns.Bags.GuildWindow = {
    Hide            = function()
        guildWindowHides = guildWindowHides + 1
        takeoverLog[#takeoverLog + 1] = "guild-window-hide"
    end,
    IsShown         = function() return guildWindowShown end,
    ShowLive        = function() guildShows[#guildShows + 1] = "live" end,
    ShowCached      = function(key) guildShows[#guildShows + 1] = "cached:" .. tostring(key) end,
    OnLogUpdate     = function() guildLogUpdates = guildLogUpdates + 1 end,
    OnProfileChanged = function() end,
}
local guildTakeoverLog = {}
local function gtLogger(name)
    return function(...)
        guildTakeoverLog[#guildTakeoverLog + 1] = name
        takeoverLog[#takeoverLog + 1] = name
        -- OnAddonLoaded receives a name arg; capture it for the forward test
        if name == "guild-addon-loaded" then
            guildTakeoverLog[#guildTakeoverLog] = { "guild-addon-loaded", (...) }
        end
    end
end
local guildLive = false
ns.Bags.GuildTakeover = {
    Init          = gtLogger("guild-init"),
    Revert        = gtLogger("guild-revert"),
    OnOpened      = gtLogger("guild-opened"),
    OnClosed      = gtLogger("guild-closed"),
    OnAddonLoaded = gtLogger("guild-addon-loaded"),
    IsLive        = function() return guildLive end,
}
local guildScanLog = {}
ns.Bags.ScanGuild = {
    MarkDirty         = function() guildScanLog[#guildScanLog + 1] = "mark-dirty" end,
    Drain             = function() guildScanLog[#guildScanLog + 1] = "drain" end,
    OnGuildBankOpened = function() guildScanLog[#guildScanLog + 1] = "opened" end,
    OnGuildBankClosed = function() guildScanLog[#guildScanLog + 1] = "closed" end,
}
-- Phase-6 breadth scanners: stub over the loader-loaded real modules so the
-- routing/drainer/catch-up assertions below can observe the calls. These log
-- into their own list — takeoverLog ordering assertions must stay unaffected.
local breadthLog = {}
local function bLog(name)
    return function(...)
        breadthLog[#breadthLog + 1] = select("#", ...) > 0 and { name, (...) } or name
        return false
    end
end
ns.Bags.ScanMail = {
    OnMailShow   = bLog("mail-show"),
    OnMailClosed = bLog("mail-closed"),
    MarkDirty    = bLog("mail-dirty"),
    Drain        = bLog("mail-drain"),
}
ns.Bags.ScanEquipped = {
    MarkDirty    = bLog("equipped-dirty"),
    MarkAllDirty = bLog("equipped-mark-all"),
    Drain        = bLog("equipped-drain"),
}
ns.Bags.ScanCurrencies = {
    OnDisplayUpdate = bLog("currencies-update"),
    MarkAllDirty    = bLog("currencies-mark-all"),
    Drain           = bLog("currencies-drain"),
}
ns.Bags.ScanAuctions = {
    OnAuctionHouseShow   = bLog("ah-show"),
    OnAuctionHouseClosed = bLog("ah-closed"),
    MarkDirty            = bLog("auctions-dirty"),
    Drain                = bLog("auctions-drain"),
}
local function breadthHas(name)
    for _, v in ipairs(breadthLog) do
        if v == name or (type(v) == "table" and v[1] == name) then return true end
    end
    return false
end
local function breadthLast()
    return breadthLog[#breadthLog]
end
local interactions = {}
ns.Bags.AutoOpen = {
    OnInteraction = function(t, shown) interactions[#interactions + 1] = { t, shown } end,
}
local popupsShown = {}
_G.StaticPopupDialogs = {}
_G.StaticPopup_Show = function(which) popupsShown[#popupsShown + 1] = which end
_G.ReloadUI = function() end
_G.ACCEPT, _G.CANCEL = "Accept", "Cancel"
_G.SlashCmdList = {}

local chunk = assert(loadfile("QUI_Bags/bags/bags.lua"))
chunk("QUI", ns)

-- Test 1: Registry registration shape
local def = registryDefs.bags
assert(def and type(def.refresh) == "function", "bags not registered with refresh")
assert(def.group == "bags" and def.importCategories[1] == "bags", "registry def wrong")

-- Test 2: disabled at login → NO store init (header contract: disabled =
-- no scanning, no SV writes — QUI_StorageDB must stay untouched so a user
-- who never enables bags never grows a storage SV), no scan events.
-- LOD startup runs through the captured ns.WhenLoggedIn callback, not a raw
-- PLAYER_LOGIN event (which never fires for a post-login LOD load).
assert(type(loginCallback) == "function", "bags.lua must register startup via ns.WhenLoggedIn")
loginCallback()
assert(QUI_StorageDB == nil,
       "disabled module must not create QUI_StorageDB (no SV writes while dormant)")
assert(not registered["BAG_UPDATE"], "scan events must not register while disabled")
assert(ns.Bags.IsActive() == false, "IsActive must be false while disabled")

-- Test 3: enabling via refresh seeds the store, applies the takeover
-- IMMEDIATELY (a B-press in the deferral window must not open the Blizzard
-- bags), and defers event registration + full scan past first paint
settings.enabled = true
def.refresh()
assert(QUI_StorageDB ~= nil and QUI_StorageDB.version == ns.Bags.Store.SCHEMA_VERSION,
       "mid-session enable must initialize the store lazily")
assert(ns.Bags.Store.GetCurrentCharacter() ~= nil, "character record must exist after enable")
assert(ns.Bags.IsActive() == true, "IsActive must be true once scanning starts")
-- Takeover.Apply, BankTakeover.Suppress, AND GuildTakeover.Init must all
-- fire synchronously before first paint (same race rationale: a Banker or
-- guild-banker interaction in the deferral window must not pop Blizzard UI).
assert(takeoverLog[#takeoverLog - 2] == "apply"
       and takeoverLog[#takeoverLog - 1] == "bank-suppress"
       and takeoverLog[#takeoverLog] == "guild-init",
       "enable must apply Takeover, BankTakeover.Suppress, then GuildTakeover.Init synchronously, before first paint")
assert(#firstFrameQueue >= 1, "registration/full scan must defer past first frame")
assert(not registered["BAG_UPDATE"], "events must not register before first paint")
-- Count guild-init calls before and after the first-frame flush.
-- The fix re-calls GuildTakeover.Init inside the deferred callback to handle
-- the missed-ADDON_LOADED window (another addon may load Blizzard_GuildBankUI
-- during the ~0.5 s deferral, so Init must run again there).
local function countInits(log)
    local n = 0
    for _, v in ipairs(log) do
        if v == "guild-init" then n = n + 1 end
    end
    return n
end
local initsBeforeFlush = countInits(takeoverLog)
assert(initsBeforeFlush >= 1, "GuildTakeover.Init must fire synchronously (before first-frame flush)")
local appliesBeforeFlush = #takeoverLog
for _, fn in ipairs(firstFrameQueue) do fn() end
-- After the flush, Init must have been called one additional time (missed-ADDON_LOADED window fix).
assert(countInits(takeoverLog) >= initsBeforeFlush + 1,
       "GuildTakeover.Init must be called again inside the first-frame flush (missed-ADDON_LOADED guard)")
-- No other takeover calls (Apply / BankTakeover.Suppress) should have fired in the deferred block.
-- The extra guild-init call is expected; everything else must be unchanged.
local nonInitAddsAfterFlush = (#takeoverLog - appliesBeforeFlush) - (countInits(takeoverLog) - initsBeforeFlush)
assert(nonInitAddsAfterFlush == 0, "the deferred block must not re-apply Apply or BankTakeover.Suppress")
assert(registered["BAG_UPDATE"] and registered["BANKFRAME_OPENED"]
       and registered["BANKFRAME_CLOSED"]
       and registered["ITEM_DATA_LOAD_RESULT"]
       and registered["GUILDBANKFRAME_OPENED"]
       and registered["GUILDBANKFRAME_CLOSED"]
       and registered["GUILDBANKBAGSLOTS_CHANGED"]
       and registered["GUILDBANK_ITEM_LOCK_CHANGED"]
       and registered["GUILDBANK_UPDATE_TABS"]
       and registered["GUILDBANK_UPDATE_MONEY"]
       and registered["GUILDBANK_UPDATE_WITHDRAWMONEY"]
       and registered["GUILDBANKLOG_UPDATE"]
       and registered["ADDON_LOADED"],
       "scan events missing after first-frame flush (check guild bank events)")
assert(registered["PLAYER_INTERACTION_MANAGER_FRAME_SHOW"]
       and registered["PLAYER_INTERACTION_MANAGER_FRAME_HIDE"]
       and registered["ITEM_LOCK_CHANGED"]
       and registered["BAG_UPDATE_COOLDOWN"], "takeover UI events missing after first-frame flush")
-- Phase-6 breadth events must register with the same deferral
assert(registered["MAIL_SHOW"] and registered["MAIL_CLOSED"]
       and registered["MAIL_INBOX_UPDATE"]
       and registered["PLAYER_EQUIPMENT_CHANGED"]
       and registered["CURRENCY_DISPLAY_UPDATE"]
       and registered["AUCTION_HOUSE_SHOW"]
       and registered["AUCTION_HOUSE_CLOSED"]
       and registered["OWNED_AUCTIONS_UPDATED"],
       "breadth scan events missing after first-frame flush")
-- Deferred catch-up: equipped + currencies are login-fireable surfaces, so
-- the deferred block must MarkAllDirty them (mail/auctions wait for their
-- interactions — a catch-up there would wipe caches against closed surfaces)
assert(breadthHas("equipped-mark-all"), "deferred block must MarkAllDirty the equipped scanner")
assert(breadthHas("currencies-mark-all"), "deferred block must MarkAllDirty the currency scanner")
assert(not breadthHas("mail-dirty") and not breadthHas("mail-show"),
       "the deferred block must not touch the mail scanner")
assert(not breadthHas("auctions-dirty") and not breadthHas("ah-show"),
       "the deferred block must not touch the auction scanner")
scripts.OnUpdate(frame) -- run the deferred full-scan drain so later sections start clean
-- RequestDrain's drainer must include the four breadth scanners
assert(breadthHas("mail-drain") and breadthHas("equipped-drain")
       and breadthHas("currencies-drain") and breadthHas("auctions-drain"),
       "the coalesced drainer must drain all four breadth scanners")

-- Test 4: drain scheduling coalesces and clears
local drains = 0
local realDrainBags, realDrainBank = ns.Bags.ScanBags.Drain, ns.Bags.ScanBank.Drain
ns.Bags.ScanBags.Drain = function() drains = drains + 1; return false end
ns.Bags.ScanBank.Drain = function() return false end
ns.Bags.RequestDrain()
ns.Bags.RequestDrain() -- coalesced
assert(scripts.OnUpdate, "drain must schedule an OnUpdate")
scripts.OnUpdate(frame)
assert(drains == 1, "drain ran " .. drains .. " times, expected 1")
assert(scripts.OnUpdate == nil, "OnUpdate must self-clear")
ns.Bags.ScanBags.Drain, ns.Bags.ScanBank.Drain = realDrainBags, realDrainBank

-- Test 5: event routing actually reaches the scanners and the store
_G.C_Bank.FetchPurchasedBankTabData = function(bankType)
    if bankType == Enum.BankType.Character then
        return { { ID = 6, bankType = bankType, name = "T", icon = 1, depositFlags = 0 } }
    end
end
local openedBefore = #takeoverLog
scripts.OnEvent(frame, "BANKFRAME_OPENED")     -- metadata + marks tab 6, schedules drain
assert(takeoverLog[#takeoverLog] == "bank-opened",
       "BANKFRAME_OPENED must route to BankTakeover.OnBankOpened()")
scripts.OnEvent(frame, "BAG_UPDATE", 0)        -- marks backpack in the bag scanner
scripts.OnEvent(frame, "BAG_UPDATE", 6)        -- bank-tab ID routes to the bank scanner
scripts.OnEvent(frame, "BAG_UPDATE_DELAYED")
assert(scripts.OnUpdate ~= nil, "a drain must be scheduled")
scripts.OnUpdate(frame)
local rec = ns.Bags.Store.GetCurrentCharacter()
assert(rec.bags[0] ~= nil, "BAG_UPDATE(0) must reach the bag scanner and write the store")
assert(rec.bankTabs[6] ~= nil and rec.bankTabs[6].name == "T",
       "BAG_UPDATE(6)/BANKFRAME_OPENED must reach the bank scanner with metadata")
-- BANKFRAME_CLOSED must route to BankTakeover.OnBankClosed (scanner-neutral).
-- Transfers is nil here, so this dispatch also proves the existence guard on
-- the transfer-cancel route holds.
scripts.OnEvent(frame, "BANKFRAME_CLOSED")
assert(takeoverLog[#takeoverLog] == "bank-closed",
       "BANKFRAME_CLOSED must route to BankTakeover.OnBankClosed()")
-- BANKFRAME_CLOSED must also cancel an in-flight deposit queue: the queue
-- must not outlive the bank session (a post-close UseContainerItem would
-- USE the item instead of depositing it).
local bankCloseCancels = 0
ns.Bags.Transfers = { Cancel = function() bankCloseCancels = bankCloseCancels + 1 end }
scripts.OnEvent(frame, "BANKFRAME_CLOSED")
assert(bankCloseCancels == 1, "BANKFRAME_CLOSED must route to Transfers.Cancel()")
ns.Bags.Transfers = nil

-- Test 5b: takeover-phase event routing
-- Bags.Junk is not defined yet here: the merchant dispatch below proves the
-- existence guard holds before the ops file loads.
scripts.OnEvent(frame, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 5)
scripts.OnEvent(frame, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 5)
assert(#interactions == 2 and interactions[1][1] == 5 and interactions[1][2] == true
       and interactions[2][1] == 5 and interactions[2][2] == false,
       "interaction events must route to AutoOpen.OnInteraction(type, shown)")
-- Merchant interactions must ALSO notify Junk.OnMerchant(shown), both ways;
-- non-merchant interactions must not.
local merchantNotices = {}
ns.Bags.Junk = {
    OnMerchant = function(shown) merchantNotices[#merchantNotices + 1] = shown end,
}
scripts.OnEvent(frame, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
                Enum.PlayerInteractionType.Merchant)
scripts.OnEvent(frame, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
                Enum.PlayerInteractionType.Merchant)
assert(#merchantNotices == 2 and merchantNotices[1] == true and merchantNotices[2] == false,
       "merchant interaction must route to Junk.OnMerchant(true) then (false)")
scripts.OnEvent(frame, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
                Enum.PlayerInteractionType.MailInfo)
scripts.OnEvent(frame, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
                Enum.PlayerInteractionType.MailInfo)
assert(#merchantNotices == 2, "non-merchant interactions must not notify Junk")
assert(#interactions == 6, "AutoOpen must still see every interaction event")
ns.Bags.Junk = nil
local moneyPings = 0
ns.Bags.Bus.Subscribe("MoneyChanged", function() moneyPings = moneyPings + 1 end)
scripts.OnEvent(frame, "PLAYER_MONEY")
assert(moneyPings == 1, "PLAYER_MONEY must publish MoneyChanged")
-- ACCOUNT_MONEY (warband bank gold, no payload) must be registered, publish
-- MoneyChanged, and NOT touch the character record (warband gold is fetched
-- live by the renderer, never cached on the character)
assert(registered["ACCOUNT_MONEY"], "ACCOUNT_MONEY must be a registered scan event")
rec.details.money = 12345
scripts.OnEvent(frame, "ACCOUNT_MONEY")
assert(moneyPings == 2, "ACCOUNT_MONEY must publish MoneyChanged")
assert(rec.details.money == 12345, "ACCOUNT_MONEY must not write the character money cache")
-- ITEM_LOCK_CHANGED / BAG_UPDATE_COOLDOWN → synthetic BagsChanged, only
-- while the window is shown
local lockPings = 0
ns.Bags.Bus.Subscribe("BagsChanged", function() lockPings = lockPings + 1 end)
scripts.OnEvent(frame, "ITEM_LOCK_CHANGED", 0, 1)
scripts.OnEvent(frame, "BAG_UPDATE_COOLDOWN")
assert(lockPings == 0, "lock/cooldown changes must be ignored while the window is hidden")
ns.Bags.BagWindow.IsShown = function() return true end
scripts.OnEvent(frame, "ITEM_LOCK_CHANGED", 0, 1)
assert(lockPings == 1, "lock change must publish a synthetic BagsChanged when shown")
scripts.OnEvent(frame, "BAG_UPDATE_COOLDOWN")
assert(lockPings == 2, "cooldown update must publish a synthetic BagsChanged when shown")
ns.Bags.BagWindow.IsShown = function() return false end
-- the same route pings the BANK window (lock/cooldown re-dress) when shown
local bankLockPings = 0
ns.Bags.Bus.Subscribe("BankChanged", function() bankLockPings = bankLockPings + 1 end)
scripts.OnEvent(frame, "ITEM_LOCK_CHANGED", 6, 1)
assert(bankLockPings == 0, "no BankChanged ping while the bank window is hidden")
ns.Bags.BankWindow.IsShown = function() return true end
scripts.OnEvent(frame, "ITEM_LOCK_CHANGED", 6, 1)
scripts.OnEvent(frame, "BAG_UPDATE_COOLDOWN")
assert(bankLockPings == 2, "lock/cooldown must publish BankChanged when the bank window is shown")
ns.Bags.BankWindow.IsShown = function() return false end

-- Test 5d: guild bank event routing
-- GUILDBANKFRAME_OPENED → GuildTakeover.OnOpened
local guildOpenedBefore = #guildTakeoverLog
scripts.OnEvent(frame, "GUILDBANKFRAME_OPENED")
assert(guildTakeoverLog[#guildTakeoverLog] == "guild-opened",
       "GUILDBANKFRAME_OPENED must route to GuildTakeover.OnOpened()")
-- GUILDBANKFRAME_CLOSED → GuildTakeover.OnClosed
scripts.OnEvent(frame, "GUILDBANKFRAME_CLOSED")
assert(guildTakeoverLog[#guildTakeoverLog] == "guild-closed",
       "GUILDBANKFRAME_CLOSED must route to GuildTakeover.OnClosed()")

-- GUILDBANKBAGSLOTS_CHANGED / GUILDBANK_ITEM_LOCK_CHANGED / GUILDBANK_UPDATE_TABS
-- → ScanGuild.MarkDirty + RequestDrain
local dirtysBefore = #guildScanLog
scripts.OnEvent(frame, "GUILDBANKBAGSLOTS_CHANGED")
assert(guildScanLog[#guildScanLog] == "mark-dirty",
       "GUILDBANKBAGSLOTS_CHANGED must call ScanGuild.MarkDirty()")
assert(scripts.OnUpdate ~= nil, "GUILDBANKBAGSLOTS_CHANGED must schedule a drain")
scripts.OnUpdate(frame) -- flush
scripts.OnEvent(frame, "GUILDBANK_ITEM_LOCK_CHANGED")
assert(guildScanLog[#guildScanLog] == "mark-dirty",
       "GUILDBANK_ITEM_LOCK_CHANGED must call ScanGuild.MarkDirty()")
scripts.OnUpdate(frame) -- flush
scripts.OnEvent(frame, "GUILDBANK_UPDATE_TABS")
assert(guildScanLog[#guildScanLog] == "mark-dirty",
       "GUILDBANK_UPDATE_TABS must call ScanGuild.MarkDirty()")
scripts.OnUpdate(frame) -- flush

-- GUILDBANK_UPDATE_MONEY / _WITHDRAWMONEY → Bus.Publish("GuildMoneyChanged")
local guildMoneyPings = 0
ns.Bags.Bus.Subscribe("GuildMoneyChanged", function() guildMoneyPings = guildMoneyPings + 1 end)
scripts.OnEvent(frame, "GUILDBANK_UPDATE_MONEY")
assert(guildMoneyPings == 1, "GUILDBANK_UPDATE_MONEY must publish GuildMoneyChanged")
scripts.OnEvent(frame, "GUILDBANK_UPDATE_WITHDRAWMONEY")
assert(guildMoneyPings == 2, "GUILDBANK_UPDATE_WITHDRAWMONEY must publish GuildMoneyChanged")

-- GUILDBANKLOG_UPDATE → GuildWindow.OnLogUpdate, gated on IsShown
local logUpdatesBefore = guildLogUpdates
scripts.OnEvent(frame, "GUILDBANKLOG_UPDATE")
assert(guildLogUpdates == logUpdatesBefore,
       "GUILDBANKLOG_UPDATE must NOT call OnLogUpdate while the guild window is hidden")
guildWindowShown = true
scripts.OnEvent(frame, "GUILDBANKLOG_UPDATE")
assert(guildLogUpdates == logUpdatesBefore + 1,
       "GUILDBANKLOG_UPDATE must call GuildWindow.OnLogUpdate() when the window is shown")
guildWindowShown = false

-- ADDON_LOADED → GuildTakeover.OnAddonLoaded(arg1) — forward the name argument
scripts.OnEvent(frame, "ADDON_LOADED", "Blizzard_GuildBankUI")
local lastGTEntry = guildTakeoverLog[#guildTakeoverLog]
assert(type(lastGTEntry) == "table"
       and lastGTEntry[1] == "guild-addon-loaded"
       and lastGTEntry[2] == "Blizzard_GuildBankUI",
       "ADDON_LOADED must forward arg1 to GuildTakeover.OnAddonLoaded(arg1)")

-- Test 5g: phase-6 breadth event routing
-- MAIL_SHOW → ScanMail.OnMailShow + a scheduled drain (full scan at mailbox)
scripts.OnEvent(frame, "MAIL_SHOW")
assert(breadthLast() == "mail-show", "MAIL_SHOW must route to ScanMail.OnMailShow()")
assert(scripts.OnUpdate ~= nil, "MAIL_SHOW must schedule a drain")
scripts.OnUpdate(frame) -- flush
-- MAIL_INBOX_UPDATE → ScanMail.MarkDirty + drain
scripts.OnEvent(frame, "MAIL_INBOX_UPDATE")
assert(breadthHas("mail-dirty"), "MAIL_INBOX_UPDATE must route to ScanMail.MarkDirty()")
assert(scripts.OnUpdate ~= nil, "MAIL_INBOX_UPDATE must schedule a drain")
scripts.OnUpdate(frame) -- flush
-- MAIL_CLOSED → ScanMail.OnMailClosed (session end; no drain needed)
scripts.OnEvent(frame, "MAIL_CLOSED")
assert(breadthLast() == "mail-closed", "MAIL_CLOSED must route to ScanMail.OnMailClosed()")
-- PLAYER_EQUIPMENT_CHANGED(slot, hasCurrent) → forward the slot arg
scripts.OnEvent(frame, "PLAYER_EQUIPMENT_CHANGED", 16, false)
local last = breadthLast()
assert(type(last) == "table" and last[1] == "equipped-dirty" and last[2] == 16,
       "PLAYER_EQUIPMENT_CHANGED must forward equipmentSlot to ScanEquipped.MarkDirty(slot)")
assert(scripts.OnUpdate ~= nil, "PLAYER_EQUIPMENT_CHANGED must schedule a drain")
scripts.OnUpdate(frame) -- flush
-- CURRENCY_DISPLAY_UPDATE(currencyType?) → forward the (nilable) ID
scripts.OnEvent(frame, "CURRENCY_DISPLAY_UPDATE", 3008, 1500)
last = breadthLast()
assert(type(last) == "table" and last[1] == "currencies-update" and last[2] == 3008,
       "CURRENCY_DISPLAY_UPDATE must forward currencyType to ScanCurrencies.OnDisplayUpdate(id)")
assert(scripts.OnUpdate ~= nil, "CURRENCY_DISPLAY_UPDATE must schedule a drain")
scripts.OnUpdate(frame) -- flush
scripts.OnEvent(frame, "CURRENCY_DISPLAY_UPDATE") -- payload-free fire
last = breadthLast()
-- the handler forwards arg1 verbatim, so a payload-free fire arrives as an
-- explicit nil arg ({name} table) or a zero-arg call (bare name) — both fine
assert(last == "currencies-update"
       or (type(last) == "table" and last[1] == "currencies-update" and last[2] == nil),
       "payload-free CURRENCY_DISPLAY_UPDATE must still route (nil id)")
scripts.OnUpdate(frame) -- flush
-- AUCTION_HOUSE_SHOW/CLOSED → session gates; OWNED_AUCTIONS_UPDATED → dirty+drain
scripts.OnEvent(frame, "AUCTION_HOUSE_SHOW")
assert(breadthLast() == "ah-show", "AUCTION_HOUSE_SHOW must route to ScanAuctions.OnAuctionHouseShow()")
scripts.OnEvent(frame, "OWNED_AUCTIONS_UPDATED")
assert(breadthLast() == "auctions-dirty", "OWNED_AUCTIONS_UPDATED must route to ScanAuctions.MarkDirty()")
assert(scripts.OnUpdate ~= nil, "OWNED_AUCTIONS_UPDATED must schedule a drain")
scripts.OnUpdate(frame) -- flush
scripts.OnEvent(frame, "AUCTION_HOUSE_CLOSED")
assert(breadthLast() == "ah-closed", "AUCTION_HOUSE_CLOSED must route to ScanAuctions.OnAuctionHouseClosed()")

-- Test 5f: PLAYER_REGEN_DISABLED → ops combat aborts, existence-guarded.
-- The loader covers only the data layer, so none of SortExecutor/Transfers/
-- Junk exists here — the first dispatch proves the guards hold.
assert(registered["PLAYER_REGEN_DISABLED"],
       "PLAYER_REGEN_DISABLED must be a registered scan event")
scripts.OnEvent(frame, "PLAYER_REGEN_DISABLED") -- must not error without ops
local sortCombats, transferCombats, junkCombats = 0, 0, 0
ns.Bags.SortExecutor = { OnCombat = function() sortCombats = sortCombats + 1 end }
ns.Bags.Transfers    = { OnCombat = function() transferCombats = transferCombats + 1 end }
ns.Bags.Junk         = { OnCombat = function() junkCombats = junkCombats + 1 end }
scripts.OnEvent(frame, "PLAYER_REGEN_DISABLED")
assert(sortCombats == 1,
       "PLAYER_REGEN_DISABLED must route to SortExecutor.OnCombat()")
assert(transferCombats == 1,
       "PLAYER_REGEN_DISABLED must route to Transfers.OnCombat()")
assert(junkCombats == 1,
       "PLAYER_REGEN_DISABLED must route to Junk.OnCombat()")
ns.Bags.SortExecutor, ns.Bags.Transfers, ns.Bags.Junk = nil, nil, nil

-- Test 5e: refresh while already enabled + scanning (profile switch between
-- two enabled profiles) must re-anchor all three windows via OnProfileChanged
local profileMoves, bankProfileMoves, guildProfileMoves, searchProfileMoves = 0, 0, 0, 0
ns.Bags.BagWindow.OnProfileChanged    = function() profileMoves       = profileMoves + 1 end
ns.Bags.BankWindow.OnProfileChanged   = function() bankProfileMoves   = bankProfileMoves + 1 end
ns.Bags.GuildWindow.OnProfileChanged  = function() guildProfileMoves  = guildProfileMoves + 1 end
ns.Bags.SearchWindow.OnProfileChanged = function() searchProfileMoves = searchProfileMoves + 1 end
def.refresh()
assert(profileMoves == 1, "enabled→enabled refresh must call BagWindow.OnProfileChanged")
assert(bankProfileMoves == 1, "enabled→enabled refresh must call BankWindow.OnProfileChanged")
assert(guildProfileMoves == 1, "enabled→enabled refresh must call GuildWindow.OnProfileChanged")
assert(searchProfileMoves == 1, "enabled→enabled refresh must call SearchWindow.OnProfileChanged")
ns.Bags.BagWindow.OnProfileChanged    = nil
ns.Bags.BankWindow.OnProfileChanged   = nil
ns.Bags.GuildWindow.OnProfileChanged  = nil
ns.Bags.SearchWindow.OnProfileChanged = nil

-- Test 5h: /quibags slash routing (registered at load; gated on IsActive)
assert(_G.SLASH_QUIBAGS1 == "/quibags", "SLASH_QUIBAGS1 must be registered")
local slash = SlashCmdList["QUIBAGS"]
assert(type(slash) == "function", "SlashCmdList.QUIBAGS must be a function")
local printed = {}
local realPrint = _G.print
_G.print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
slash("")                                  -- bare → bag window
assert(bagToggles == 1, "/quibags must toggle the bag window")
slash("search")                            -- search → search-everywhere
assert(searchToggles == 1, "/quibags search must toggle the search window")
slash("  SEARCH  ")                        -- trims + case-folds
assert(searchToggles == 2, "/quibags must trim and lowercase its argument")
slash("bogus")                             -- anything else → usage, no toggles
assert(bagToggles == 1 and searchToggles == 2, "unknown args must not toggle")
assert(#printed >= 1, "unknown args must print usage")
_G.print = realPrint

-- Test 5i: cached bank/guild browsing away from live sessions. The toggles
-- (shared by /quibags bank|guild, the keybinds, and the bag-window header
-- buttons) prefer the LIVE presentation when the session is open and fall
-- back to the cached browse otherwise; shown windows just hide.
assert(type(_G.QUI_BagsToggleBank) == "function", "QUI_BagsToggleBank must exist")
assert(type(_G.QUI_BagsToggleGuild) == "function", "QUI_BagsToggleGuild must exist")
_G.QUI_BagsToggleBank()
assert(bankShows[#bankShows] == "cached", "away from a banker the toggle opens the CACHED bank view")
bankLive = true
_G.QUI_BagsToggleBank()
assert(bankShows[#bankShows] == "live", "at the banker the toggle opens the LIVE bank view")
bankLive = false
ns.Bags.BankWindow.IsShown = function() return true end
local hidesBefore = bankWindowHides
_G.QUI_BagsToggleBank()
assert(bankWindowHides == hidesBefore + 1, "a shown bank window must just hide")
ns.Bags.BankWindow.IsShown = function() return false end
_G.QUI_BagsToggleGuild()
assert(guildShows[#guildShows] == "cached:nil",
    "away from the vault the toggle opens the CACHED guild view (current guild)")
guildLive = true
_G.QUI_BagsToggleGuild()
assert(guildShows[#guildShows] == "live", "at the vault the toggle opens the LIVE guild view")
guildLive = false
-- slash routing
local bankShowsBefore, guildShowsBefore = #bankShows, #guildShows
slash("bank")
assert(#bankShows == bankShowsBefore + 1, "/quibags bank must run the bank toggle")
slash("guild")
assert(#guildShows == guildShowsBefore + 1, "/quibags guild must run the guild toggle")
-- keybind labels registered
assert(_G.BINDING_NAME_QUI_BAGS_TOGGLE_BANK ~= nil, "bank keybind label must be registered")
assert(_G.BINDING_NAME_QUI_BAGS_TOGGLE_GUILD ~= nil, "guild keybind label must be registered")

-- Test 5j: EQUIPMENT_SETS_CHANGED re-dresses shown windows (the set MARK is
-- dress-time state, not cache state — route like ITEM_LOCK_CHANGED's
-- synthetic pings, gated on each window being shown)
assert(registered["EQUIPMENT_SETS_CHANGED"],
    "EQUIPMENT_SETS_CHANGED must be a registered scan event")
local eqBagPings, eqBankPings = 0, 0
ns.Bags.Bus.Subscribe("BagsChanged", function() eqBagPings = eqBagPings + 1 end)
ns.Bags.Bus.Subscribe("BankChanged", function() eqBankPings = eqBankPings + 1 end)
scripts.OnEvent(frame, "EQUIPMENT_SETS_CHANGED")
assert(eqBagPings == 0 and eqBankPings == 0,
    "set changes must not ping while both windows are hidden")
ns.Bags.BagWindow.IsShown = function() return true end
ns.Bags.BankWindow.IsShown = function() return true end
scripts.OnEvent(frame, "EQUIPMENT_SETS_CHANGED")
assert(eqBagPings == 1 and eqBankPings == 1,
    "set changes must re-dress both shown windows")
ns.Bags.BagWindow.IsShown = function() return false end
ns.Bags.BankWindow.IsShown = function() return false end

-- Test 5k: /quibags clearnew → NewItems.ClearAllNew (existence-guarded —
-- the stub table is removed afterwards so later existence guards stay true)
local clearNews = 0
local hadNewItems = ns.Bags.NewItems
ns.Bags.NewItems = ns.Bags.NewItems or {}
local realClearAllNew = ns.Bags.NewItems.ClearAllNew
ns.Bags.NewItems.ClearAllNew = function() clearNews = clearNews + 1 end
slash("clearnew")
assert(clearNews == 1, "/quibags clearnew must route to NewItems.ClearAllNew")
if hadNewItems then
    ns.Bags.NewItems.ClearAllNew = realClearAllNew
else
    ns.Bags.NewItems = nil
end

-- Test 6: disabling via refresh unregisters and cancels scheduled drains
ns.Bags.RequestDrain()
assert(scripts.OnUpdate ~= nil, "precondition: a drain is scheduled")
local hiddenBeforeDisable = bankWindowHides
local guildHiddenBeforeDisable = guildWindowHides
-- ops must not outlive the module: disable must cancel a running sort and
-- transfer queue and reset the merchant flag (Junk.OnMerchant(false) also
-- cancels an in-flight sell). The stubs log into takeoverLog so the
-- ordering assertion below proves cancels land between hides and reverts.
ns.Bags.SortExecutor = { Cancel = logger("sort-cancel") }
ns.Bags.Transfers    = { Cancel = logger("transfer-cancel") }
ns.Bags.Junk = {
    OnMerchant = function(shown)
        takeoverLog[#takeoverLog + 1] = "junk-merchant:" .. tostring(shown)
    end,
}
settings.enabled = false
def.refresh()
ns.Bags.SortExecutor, ns.Bags.Transfers, ns.Bags.Junk = nil, nil, nil
assert(ns.Bags.IsActive() == false, "IsActive must drop to false on disable")
assert(not registered["BAG_UPDATE"], "scan events must unregister when disabled")
assert(not registered["BANKFRAME_CLOSED"], "BANKFRAME_CLOSED must unregister when disabled")
assert(not registered["GUILDBANKFRAME_OPENED"]
       and not registered["GUILDBANKFRAME_CLOSED"]
       and not registered["GUILDBANKBAGSLOTS_CHANGED"]
       and not registered["GUILDBANK_UPDATE_MONEY"]
       and not registered["GUILDBANKLOG_UPDATE"]
       and not registered["ADDON_LOADED"],
       "guild bank scan events must unregister when disabled")
assert(not registered["PLAYER_INTERACTION_MANAGER_FRAME_SHOW"]
       and not registered["ITEM_LOCK_CHANGED"]
       and not registered["BAG_UPDATE_COOLDOWN"],
       "takeover UI events must unregister when disabled")
assert(not registered["MAIL_SHOW"] and not registered["MAIL_CLOSED"]
       and not registered["MAIL_INBOX_UPDATE"]
       and not registered["PLAYER_EQUIPMENT_CHANGED"]
       and not registered["CURRENCY_DISPLAY_UPDATE"]
       and not registered["AUCTION_HOUSE_SHOW"]
       and not registered["AUCTION_HOUSE_CLOSED"]
       and not registered["OWNED_AUCTIONS_UPDATED"],
       "breadth scan events must unregister when disabled")
-- Scanner session flags must not outlive the module (ops-cancel precedent):
-- disable must close the mail + auction-house sessions so a stale at-mailbox
-- /at-AH flag can't let a post-re-enable drain wipe a cache against a
-- closed surface.
assert(breadthLast() == "ah-closed" or breadthHas("ah-closed"),
       "disable must reset the auction-house session flag")
do
    local mailClosedAfterDisable = false
    for i = #breadthLog, 1, -1 do
        local v = breadthLog[i]
        if v == "mail-closed" then mailClosedAfterDisable = true; break end
        if v == "mail-show" then break end
    end
    assert(mailClosedAfterDisable, "disable must reset the mail session flag")
end
-- disable must also close the guild-bank session so a stale at-guild-bank
-- flag can't let a post-re-enable drain clobber cached guild money/tab-1
-- away from the vault.
do
    local guildClosedAfterDisable = false
    for i = #guildScanLog, 1, -1 do
        if guildScanLog[i] == "closed" then guildClosedAfterDisable = true; break end
        if guildScanLog[i] == "opened" then break end
    end
    assert(guildClosedAfterDisable, "disable must reset the guild-bank session flag via ScanGuild.OnGuildBankClosed()")
end
assert(scripts.OnUpdate == nil, "disable must cancel the scheduled drain")
-- StopScanning order: ALL windows hide FIRST (their onClose must still see
-- IsLive() to route server-side closes), then the ops cancels (running
-- queues must not outlive the module; the merchant flag resets), then
-- Takeover.Revert, then BankTakeover.Revert, then GuildTakeover.Revert.
assert(takeoverLog[#takeoverLog - 9] == "bag-window-hide"
       and takeoverLog[#takeoverLog - 8] == "bank-window-hide"
       and takeoverLog[#takeoverLog - 7] == "guild-window-hide"
       and takeoverLog[#takeoverLog - 6] == "search-window-hide"
       and takeoverLog[#takeoverLog - 5] == "sort-cancel"
       and takeoverLog[#takeoverLog - 4] == "transfer-cancel"
       and takeoverLog[#takeoverLog - 3] == "junk-merchant:false"
       and takeoverLog[#takeoverLog - 2] == "revert"
       and takeoverLog[#takeoverLog - 1] == "bank-revert"
       and takeoverLog[#takeoverLog] == "guild-revert",
       "disable must hide windows, then cancel ops + reset the merchant flag, then revert the takeovers")
assert(bankWindowHides > hiddenBeforeDisable, "disable must hide the bank window")
assert(guildWindowHides > guildHiddenBeforeDisable, "disable must hide the guild window")
assert(searchWindowHides == 1, "disable must hide the search-everywhere window")
assert(#popupsShown == 0, "disable must be silent — no reload prompt (profile switches must not nag)")

-- Test 7: the slash command goes quiet while the module is disabled (no
-- window toggles against a reverted takeover; an explanatory print instead)
do
    local printed = {}
    local realPrint = _G.print
    _G.print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
    SlashCmdList["QUIBAGS"]("")
    SlashCmdList["QUIBAGS"]("search")
    _G.print = realPrint
    assert(bagToggles == 1 and searchToggles == 2,
        "/quibags must not toggle windows while the module is disabled")
    assert(#printed == 2, "disabled /quibags must explain itself")
end

print("OK: bags_module_gate_test")
