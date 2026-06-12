-- tests/unit/storage_collector_test.lua
-- Verifies the always-on collection driver (core/storage/collector.lua):
-- login store init (NOT enabled-gated — collection is a core service),
-- deferred event registration + full scan, the coalesced next-frame drain
-- scheduler, and the data-event routing the driver took over from bags.lua.
-- Run: lua tests/unit/storage_collector_test.lua
-- luacheck: globals QUI_StorageDB
local loader = dofile("tests/helpers/load_storage_data.lua")
loader.InstallBaseStubs()
_G.C_Container.GetContainerNumSlots = function() return 0 end
_G.C_Container.GetContainerItemInfo = function() return nil end
_G.C_Bank.FetchPurchasedBankTabData = function() return nil end
_G.C_Bank.FetchBankLockedReason = function() return nil end
_G.C_Bank.FetchDepositedMoney = function() return 0 end
_G.Enum.PlayerInteractionType = { Merchant = 5, MailInfo = 17, GuildBanker = 10 }

-- Frame stub capturing registration + scripts.
local registered, scripts = {}, {}
local frame = {}
function frame.RegisterEvent(_, ev) registered[ev] = true end
function frame.UnregisterEvent(_, ev) registered[ev] = nil end
function frame.SetScript(_, which, fn) scripts[which] = fn end
_G.CreateFrame = function() return frame end

local ns = loader.LoadAll()
-- Capture the login + first-frame deferrals so the test drives startup
-- deterministically (the collector loads pre-login in production).
local loginCallback
ns.WhenLoggedIn = function(fn) loginCallback = fn end
local firstFrameQueue = {}
ns.RunAfterFirstFrame = function(fn) firstFrameQueue[#firstFrameQueue + 1] = fn end

local chunk = assert(loadfile("core/storage/collector.lua"))
chunk("QUI", ns)
local Storage = ns.Storage

-- Capture the login-deferred reputations full scan (scheduled in the
-- first-frame block, which is drained at line "for _, fn in firstFrameQueue").
local repFullScans = 0
assert(Storage.ScanReputations, "scan_reputations must load before the collector")
local realScheduleFullScan = Storage.ScanReputations.ScheduleFullScan
Storage.ScanReputations.ScheduleFullScan = function() repFullScans = repFullScans + 1 end

-- Test 1: before login, IsRunning() is false and RequestDrain is inert.
assert(type(loginCallback) == "function", "collector must register startup via ns.WhenLoggedIn")
assert(Storage.IsRunning() == false, "IsRunning must be false before login")
Storage.RequestDrain()
assert(scripts.OnUpdate == nil, "RequestDrain must be a no-op before the driver is running")

-- Test 2: login init runs unconditionally (collection is a core service —
-- there is NO enabled gate; the store must exist for a future alts module
-- even when the bags UI is disabled), then defers registration + full scan.
loginCallback()
assert(QUI_StorageDB ~= nil and QUI_StorageDB.version == Storage.Store.SCHEMA_VERSION,
       "login must initialize the store unconditionally")
assert(Storage.Store.GetCurrentCharacter() ~= nil, "login must ensure the current character record")
assert(Storage.IsRunning() == true, "IsRunning must be true once login init completes")
assert(not registered["BAG_UPDATE"], "events must not register before first paint")
assert(#firstFrameQueue >= 1, "registration + full scan must defer past first frame")
for _, fn in ipairs(firstFrameQueue) do fn() end
assert(registered["BAG_UPDATE"] and registered["BAG_UPDATE_DELAYED"]
       and registered["BAG_CONTAINER_UPDATE"]
       and registered["BANKFRAME_OPENED"]
       and registered["BANK_TABS_CHANGED"]
       and registered["BANK_TAB_SETTINGS_UPDATED"]
       and registered["PLAYERBANKSLOTS_CHANGED"]
       and registered["PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED"]
       and registered["PLAYER_MONEY"] and registered["PLAYER_GUILD_UPDATE"]
       and registered["ACCOUNT_MONEY"] and registered["ITEM_DATA_LOAD_RESULT"]
       and registered["PLAYER_LOGOUT"],
       "core inventory/money scan events must register after first paint")
assert(registered["PLAYER_INTERACTION_MANAGER_FRAME_SHOW"]
       and registered["PLAYER_INTERACTION_MANAGER_FRAME_HIDE"]
       and registered["GUILDBANKFRAME_OPENED"] and registered["GUILDBANKFRAME_CLOSED"]
       and registered["GUILDBANKBAGSLOTS_CHANGED"]
       and registered["GUILDBANK_ITEM_LOCK_CHANGED"]
       and registered["GUILDBANK_UPDATE_TABS"]
       and registered["GUILDBANK_UPDATE_MONEY"]
       and registered["GUILDBANK_UPDATE_WITHDRAWMONEY"],
       "guild-bank scan/session events must register")
assert(registered["MAIL_SHOW"] and registered["MAIL_CLOSED"]
       and registered["MAIL_INBOX_UPDATE"]
       and registered["PLAYER_EQUIPMENT_CHANGED"]
       and registered["CURRENCY_DISPLAY_UPDATE"]
       and registered["AUCTION_HOUSE_SHOW"] and registered["AUCTION_HOUSE_CLOSED"]
       and registered["OWNED_AUCTIONS_UPDATED"],
       "breadth scan events must register")
-- The collector owns NO UI/takeover events.
assert(not registered["BANKFRAME_CLOSED"], "BANKFRAME_CLOSED is a UI event (bags.lua), not the collector")
assert(not registered["ITEM_LOCK_CHANGED"] and not registered["BAG_UPDATE_COOLDOWN"]
       and not registered["EQUIPMENT_SETS_CHANGED"]
       and not registered["PLAYER_REGEN_DISABLED"]
       and not registered["GUILDBANKLOG_UPDATE"] and not registered["ADDON_LOADED"],
       "UI/ops events must NOT register on the collector frame")
scripts.OnUpdate(frame) -- run the deferred full-scan drain so later sections start clean

-- Test 3: drain coalescing — two requests, one OnUpdate, self-clears.
local drains = 0
local realDrainBags, realDrainBank = Storage.ScanBags.Drain, Storage.ScanBank.Drain
Storage.ScanBags.Drain = function() drains = drains + 1; return false end
Storage.ScanBank.Drain = function() return false end
Storage.RequestDrain()
Storage.RequestDrain() -- coalesced
assert(scripts.OnUpdate, "drain must schedule an OnUpdate")
scripts.OnUpdate(frame)
assert(drains == 1, "drain ran " .. drains .. " times, expected 1")
assert(scripts.OnUpdate == nil, "OnUpdate must self-clear")
Storage.ScanBags.Drain, Storage.ScanBank.Drain = realDrainBags, realDrainBank

-- Test 4: inventory event routing reaches the scanners + store.
_G.C_Bank.FetchPurchasedBankTabData = function(bankType)
    if bankType == Enum.BankType.Character then
        return { { ID = 6, bankType = bankType, name = "T", icon = 1, depositFlags = 0 } }
    end
end
scripts.OnEvent(frame, "BANKFRAME_OPENED")     -- metadata + marks tab 6
scripts.OnEvent(frame, "BAG_UPDATE", 0)        -- marks backpack in the bag scanner
scripts.OnEvent(frame, "BAG_UPDATE", 6)        -- bank-tab ID routes to the bank scanner
scripts.OnEvent(frame, "BAG_UPDATE_DELAYED")
assert(scripts.OnUpdate ~= nil, "a drain must be scheduled")
scripts.OnUpdate(frame)
local rec = Storage.Store.GetCurrentCharacter()
assert(rec.bags[0] ~= nil, "BAG_UPDATE(0) must reach the bag scanner and write the store")
assert(rec.bankTabs[6] ~= nil and rec.bankTabs[6].name == "T",
       "BAG_UPDATE(6)/BANKFRAME_OPENED must reach the bank scanner with metadata")

-- Test 5: money events. PLAYER_MONEY caches; ACCOUNT_MONEY publishes only.
local moneyPings = 0
Storage.Bus.Subscribe("MoneyChanged", function() moneyPings = moneyPings + 1 end)
scripts.OnEvent(frame, "PLAYER_MONEY")
assert(moneyPings == 1, "PLAYER_MONEY must publish MoneyChanged")
rec.details.money = 12345
scripts.OnEvent(frame, "ACCOUNT_MONEY")
assert(moneyPings == 2, "ACCOUNT_MONEY must publish MoneyChanged")
assert(rec.details.money == 12345, "ACCOUNT_MONEY must not write the character money cache")

-- Test 6: ITEM_DATA_LOAD_RESULT forwards (itemID, success) to item_info.
local loadResults = {}
local realOnLoad = Storage.ItemInfo.OnItemDataLoadResult
Storage.ItemInfo.OnItemDataLoadResult = function(id, ok) loadResults[#loadResults + 1] = { id, ok } end
scripts.OnEvent(frame, "ITEM_DATA_LOAD_RESULT", 12345, true)
assert(#loadResults == 1 and loadResults[1][1] == 12345 and loadResults[1][2] == true,
       "ITEM_DATA_LOAD_RESULT must forward (itemID, success) to ItemInfo.OnItemDataLoadResult")
Storage.ItemInfo.OnItemDataLoadResult = realOnLoad

-- Test 7: PLAYER_LOGOUT stamps lastSeen on the current record.
rec.details.lastSeen = nil
scripts.OnEvent(frame, "PLAYER_LOGOUT")
assert(type(rec.details.lastSeen) == "number", "PLAYER_LOGOUT must stamp details.lastSeen")

-- Test 8: guild-bank session routing. The collector owns the scan session on
-- BOTH the GuildBanker interaction edge and the legacy events.
local guildScan = {}
Storage.ScanGuild.OnGuildBankOpened = function() guildScan[#guildScan + 1] = "open" end
Storage.ScanGuild.OnGuildBankClosed = function() guildScan[#guildScan + 1] = "close" end
Storage.ScanGuild.MarkDirty = function() guildScan[#guildScan + 1] = "dirty" end
scripts.OnEvent(frame, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.GuildBanker)
assert(guildScan[#guildScan] == "open", "GuildBanker interaction SHOW must open the scan session")
scripts.OnEvent(frame, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.Merchant)
assert(guildScan[#guildScan] == "open", "a non-GuildBanker interaction must not touch the guild scanner")
scripts.OnEvent(frame, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", Enum.PlayerInteractionType.GuildBanker)
assert(guildScan[#guildScan] == "close", "GuildBanker interaction HIDE must close the scan session")
scripts.OnEvent(frame, "GUILDBANKFRAME_OPENED")
assert(guildScan[#guildScan] == "open", "legacy GUILDBANKFRAME_OPENED must open the scan session")
scripts.OnEvent(frame, "GUILDBANKFRAME_CLOSED")
assert(guildScan[#guildScan] == "close", "legacy GUILDBANKFRAME_CLOSED must close the scan session")
for _, ev in ipairs({ "GUILDBANKBAGSLOTS_CHANGED", "GUILDBANK_ITEM_LOCK_CHANGED", "GUILDBANK_UPDATE_TABS" }) do
    local before = #guildScan
    scripts.OnEvent(frame, ev)
    assert(guildScan[#guildScan] == "dirty" and #guildScan == before + 1,
           ev .. " must mark the guild bank dirty")
    assert(scripts.OnUpdate ~= nil, ev .. " must schedule a drain")
    scripts.OnUpdate(frame)
end
local guildMoney = 0
Storage.Bus.Subscribe("GuildMoneyChanged", function() guildMoney = guildMoney + 1 end)
scripts.OnEvent(frame, "GUILDBANK_UPDATE_MONEY")
scripts.OnEvent(frame, "GUILDBANK_UPDATE_WITHDRAWMONEY")
assert(guildMoney == 2, "guild money events must publish GuildMoneyChanged")

-- Test 9: breadth event routing (mail / equipped / currencies / auctions).
local breadth = {}
Storage.ScanMail.OnMailShow = function() breadth[#breadth + 1] = "mail-show" end
Storage.ScanMail.OnMailClosed = function() breadth[#breadth + 1] = "mail-closed" end
Storage.ScanMail.MarkDirty = function() breadth[#breadth + 1] = "mail-dirty" end
Storage.ScanEquipped.MarkDirty = function(slot) breadth[#breadth + 1] = { "equipped-dirty", slot } end
Storage.ScanCurrencies.OnDisplayUpdate = function(id) breadth[#breadth + 1] = { "currencies", id } end
Storage.ScanAuctions.OnAuctionHouseShow = function() breadth[#breadth + 1] = "ah-show" end
Storage.ScanAuctions.OnAuctionHouseClosed = function() breadth[#breadth + 1] = "ah-closed" end
Storage.ScanAuctions.MarkDirty = function() breadth[#breadth + 1] = "auctions-dirty" end
local function lastBreadth() return breadth[#breadth] end

scripts.OnEvent(frame, "MAIL_SHOW")
assert(lastBreadth() == "mail-show", "MAIL_SHOW must route to ScanMail.OnMailShow()")
assert(scripts.OnUpdate ~= nil, "MAIL_SHOW must schedule a drain"); scripts.OnUpdate(frame)
scripts.OnEvent(frame, "MAIL_INBOX_UPDATE")
assert(lastBreadth() == "mail-dirty", "MAIL_INBOX_UPDATE must route to ScanMail.MarkDirty()")
scripts.OnUpdate(frame)
scripts.OnEvent(frame, "MAIL_CLOSED")
assert(lastBreadth() == "mail-closed", "MAIL_CLOSED must route to ScanMail.OnMailClosed()")
scripts.OnEvent(frame, "PLAYER_EQUIPMENT_CHANGED", 16, false)
local l = lastBreadth()
assert(type(l) == "table" and l[1] == "equipped-dirty" and l[2] == 16,
       "PLAYER_EQUIPMENT_CHANGED must forward the slot to ScanEquipped.MarkDirty(slot)")
scripts.OnUpdate(frame)
scripts.OnEvent(frame, "CURRENCY_DISPLAY_UPDATE", 3008, 1500)
l = lastBreadth()
assert(type(l) == "table" and l[1] == "currencies" and l[2] == 3008,
       "CURRENCY_DISPLAY_UPDATE must forward the (nilable) ID to ScanCurrencies.OnDisplayUpdate")
scripts.OnUpdate(frame)
local ahChanges = {}
Storage.Bus.Subscribe("AuctionHouseChanged", function(_, open) ahChanges[#ahChanges + 1] = open end)
scripts.OnEvent(frame, "AUCTION_HOUSE_SHOW")
assert(lastBreadth() == "ah-show" and ahChanges[#ahChanges] == true,
       "AUCTION_HOUSE_SHOW must open the AH scanner and publish AuctionHouseChanged(true)")
scripts.OnEvent(frame, "OWNED_AUCTIONS_UPDATED")
assert(lastBreadth() == "auctions-dirty", "OWNED_AUCTIONS_UPDATED must route to ScanAuctions.MarkDirty()")
assert(scripts.OnUpdate ~= nil, "OWNED_AUCTIONS_UPDATED must schedule a drain"); scripts.OnUpdate(frame)
scripts.OnEvent(frame, "AUCTION_HOUSE_CLOSED")
assert(lastBreadth() == "ah-closed" and ahChanges[#ahChanges] == false,
       "AUCTION_HOUSE_CLOSED must close the AH scanner and publish AuctionHouseChanged(false)")

-- Test 10: character-basics events are registered.
assert(registered["PLAYER_LEVEL_UP"] and registered["PLAYER_XP_UPDATE"]
       and registered["UPDATE_EXHAUSTION"] and registered["PLAYER_AVG_ITEM_LEVEL_UPDATE"]
       and registered["PLAYER_SPECIALIZATION_CHANGED"] and registered["ZONE_CHANGED_NEW_AREA"]
       and registered["TIME_PLAYED_MSG"],
       "all seven character-basics events must register")

-- Test 11: PLAYER_LEVEL_UP routes to ScanCharacter.MarkAllDirty + RequestDrain.
local charDirty = 0
local realMarkAllDirty = Storage.ScanCharacter and Storage.ScanCharacter.MarkAllDirty
if Storage.ScanCharacter then
    Storage.ScanCharacter.MarkAllDirty = function() charDirty = charDirty + 1 end
end
scripts.OnEvent(frame, "PLAYER_LEVEL_UP")
assert(charDirty == 1, "PLAYER_LEVEL_UP must call ScanCharacter.MarkAllDirty()")
assert(scripts.OnUpdate ~= nil, "PLAYER_LEVEL_UP must schedule a drain")
scripts.OnUpdate(frame)
scripts.OnEvent(frame, "ZONE_CHANGED_NEW_AREA")
assert(charDirty == 2, "ZONE_CHANGED_NEW_AREA must dirty ScanCharacter")
scripts.OnUpdate(frame)
scripts.OnEvent(frame, "PLAYER_SPECIALIZATION_CHANGED", "party1")
assert(charDirty == 2, "party member spec change must NOT dirty ScanCharacter")
scripts.OnEvent(frame, "PLAYER_SPECIALIZATION_CHANGED", "player")
assert(charDirty == 3, "player spec change must dirty ScanCharacter")
scripts.OnUpdate(frame)
if realMarkAllDirty then Storage.ScanCharacter.MarkAllDirty = realMarkAllDirty end

-- Test 12: TIME_PLAYED_MSG forwards both payload args to ScanCharacter.OnTimePlayed.
local playedArgs
local realOnTimePlayed = Storage.ScanCharacter and Storage.ScanCharacter.OnTimePlayed
if Storage.ScanCharacter then
    Storage.ScanCharacter.OnTimePlayed = function(total, lvl) playedArgs = { total, lvl } end
end
scripts.OnEvent(frame, "TIME_PLAYED_MSG", 360000, 7200)
assert(playedArgs and playedArgs[1] == 360000 and playedArgs[2] == 7200,
       "TIME_PLAYED_MSG must forward (total, thisLevel) to ScanCharacter.OnTimePlayed")
if realOnTimePlayed then Storage.ScanCharacter.OnTimePlayed = realOnTimePlayed end

-- Test 13: professions events are registered.
assert(registered["SKILL_LINES_CHANGED"] and registered["TRADE_SKILL_LIST_UPDATE"],
       "professions events (SKILL_LINES_CHANGED, TRADE_SKILL_LIST_UPDATE) must register")

-- Test 14: SKILL_LINES_CHANGED routes to ScanProfessions.MarkAllDirty + drain.
local profDirty = 0
local realProfMark = Storage.ScanProfessions and Storage.ScanProfessions.MarkAllDirty
if Storage.ScanProfessions then
    Storage.ScanProfessions.MarkAllDirty = function() profDirty = profDirty + 1 end
end
scripts.OnEvent(frame, "SKILL_LINES_CHANGED")
assert(profDirty == 1, "SKILL_LINES_CHANGED must call ScanProfessions.MarkAllDirty()")
assert(scripts.OnUpdate ~= nil, "SKILL_LINES_CHANGED must schedule a drain")
scripts.OnUpdate(frame)
scripts.OnEvent(frame, "TRADE_SKILL_LIST_UPDATE")
assert(profDirty == 2, "TRADE_SKILL_LIST_UPDATE must dirty ScanProfessions")
assert(scripts.OnUpdate ~= nil, "TRADE_SKILL_LIST_UPDATE must schedule a drain")
scripts.OnUpdate(frame)
if realProfMark then Storage.ScanProfessions.MarkAllDirty = realProfMark end

-- Test 15: the login deferred block scheduled the reputations full scan
-- (the firstFrameQueue was drained right after login).
assert(repFullScans == 1, "login first-frame block must call ScanReputations.ScheduleFullScan once")
Storage.ScanReputations.ScheduleFullScan = realScheduleFullScan

-- Test 16: reputations events are registered.
assert(registered["FACTION_STANDING_CHANGED"] and registered["MAJOR_FACTION_RENOWN_LEVEL_CHANGED"],
       "reputations events (FACTION_STANDING_CHANGED, MAJOR_FACTION_RENOWN_LEVEL_CHANGED) must register")

-- Test 17: FACTION_STANDING_CHANGED forwards the factionID to
-- OnFactionStandingChanged + schedules a drain; the renown event too.
local repFactions = {}
local realRepOnChange = Storage.ScanReputations.OnFactionStandingChanged
Storage.ScanReputations.OnFactionStandingChanged = function(id) repFactions[#repFactions + 1] = id end
scripts.OnEvent(frame, "FACTION_STANDING_CHANGED", 2510, 12000)
assert(repFactions[#repFactions] == 2510,
       "FACTION_STANDING_CHANGED must forward factionID to OnFactionStandingChanged")
assert(scripts.OnUpdate ~= nil, "FACTION_STANDING_CHANGED must schedule a drain"); scripts.OnUpdate(frame)
scripts.OnEvent(frame, "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", 2600, 15, 14)
assert(repFactions[#repFactions] == 2600,
       "MAJOR_FACTION_RENOWN_LEVEL_CHANGED must forward majorFactionID to OnFactionStandingChanged")
scripts.OnUpdate(frame)
Storage.ScanReputations.OnFactionStandingChanged = realRepOnChange

-- Test 18: weeklies events are registered.
assert(registered["WEEKLY_REWARDS_UPDATE"] and registered["CHALLENGE_MODE_COMPLETED"]
       and registered["CHALLENGE_MODE_MAPS_UPDATE"]
       and registered["MYTHIC_PLUS_CURRENT_AFFIX_UPDATE"],
       "all four weeklies scan events must register")

-- Test 19: WEEKLY_REWARDS_UPDATE routes to ScanWeeklies.MarkAllDirty + drain.
-- Spot-check one event per scanner (all four share the same branch).
local weeklyDirty = 0
local realWeeklyMark = Storage.ScanWeeklies and Storage.ScanWeeklies.MarkAllDirty
if Storage.ScanWeeklies then
    Storage.ScanWeeklies.MarkAllDirty = function() weeklyDirty = weeklyDirty + 1 end
end
scripts.OnEvent(frame, "WEEKLY_REWARDS_UPDATE")
assert(weeklyDirty == 1, "WEEKLY_REWARDS_UPDATE must call ScanWeeklies.MarkAllDirty()")
assert(scripts.OnUpdate ~= nil, "WEEKLY_REWARDS_UPDATE must schedule a drain"); scripts.OnUpdate(frame)
scripts.OnEvent(frame, "CHALLENGE_MODE_COMPLETED")
assert(weeklyDirty == 2, "CHALLENGE_MODE_COMPLETED must dirty ScanWeeklies")
scripts.OnUpdate(frame)
if realWeeklyMark then Storage.ScanWeeklies.MarkAllDirty = realWeeklyMark end

-- Test 20: lockouts events are registered.
assert(registered["UPDATE_INSTANCE_INFO"] and registered["BOSS_KILL"],
       "lockouts scan events (UPDATE_INSTANCE_INFO, BOSS_KILL) must register")

-- Test 21: UPDATE_INSTANCE_INFO routes to ScanLockouts.MarkAllDirty + drain.
local lockoutDirty = 0
local realLockoutMark = Storage.ScanLockouts and Storage.ScanLockouts.MarkAllDirty
if Storage.ScanLockouts then
    Storage.ScanLockouts.MarkAllDirty = function() lockoutDirty = lockoutDirty + 1 end
end
scripts.OnEvent(frame, "UPDATE_INSTANCE_INFO")
assert(lockoutDirty == 1, "UPDATE_INSTANCE_INFO must call ScanLockouts.MarkAllDirty()")
assert(scripts.OnUpdate ~= nil, "UPDATE_INSTANCE_INFO must schedule a drain"); scripts.OnUpdate(frame)
scripts.OnEvent(frame, "BOSS_KILL")
assert(lockoutDirty == 2, "BOSS_KILL must dirty ScanLockouts")
scripts.OnUpdate(frame)
if realLockoutMark then Storage.ScanLockouts.MarkAllDirty = realLockoutMark end

-- Test 22: Tier-2 scanner gating honors the alts.scanners profile toggles
-- LIVE. ScannerEnabled caches its getter on first call, so the stub must be
-- present BEFORE the collector loads — re-load the collector into a fresh ns
-- with ns.Helpers.CreateDBGetter("alts") returning a controllable settings
-- table. (The earlier sections ran with no ns.Helpers — getter resolves to
-- false → all scanners enabled, which is the opt-out default.)
do
    local gateNS = loader.LoadAll()
    local gloginCallback
    gateNS.WhenLoggedIn = function(fn) gloginCallback = fn end
    gateNS.RunAfterFirstFrame = function() end

    -- Controllable scanners table; the collector reads it live each event.
    local altsSettings = { scanners = { reputations = false } }
    gateNS.Helpers = gateNS.Helpers or {}
    gateNS.Helpers.CreateDBGetter = function(moduleName)
        assert(moduleName == "alts", "collector must scope its getter to the alts module")
        return function() return altsSettings end
    end

    local gchunk = assert(loadfile("core/storage/collector.lua"))
    gchunk("QUI", gateNS)
    local GStorage = gateNS.Storage
    gloginCallback() -- mark running so RequestDrain/event routing is live

    local gscripts = scripts -- the shared frame stub captures the latest OnEvent
    -- (CreateFrame returns the same module-level `frame`; its scripts table is
    -- `scripts`, re-bound by the second collector load's SetScript calls.)

    -- reputations OFF: FACTION_STANDING_CHANGED must NOT reach the scanner.
    local repHits = 0
    GStorage.ScanReputations.OnFactionStandingChanged = function() repHits = repHits + 1 end
    gscripts.OnEvent(frame, "FACTION_STANDING_CHANGED", 2510, 12000)
    assert(repHits == 0, "reputations=false must gate FACTION_STANDING_CHANGED off")

    -- reputations TRUE: the same event now marks the scanner.
    altsSettings.scanners.reputations = true
    gscripts.OnEvent(frame, "FACTION_STANDING_CHANGED", 2510, 12000)
    assert(repHits == 1, "reputations=true must let FACTION_STANDING_CHANGED through")

    -- reputations flag ABSENT (nil): defaults ON (opt-out).
    altsSettings.scanners.reputations = nil
    gscripts.OnEvent(frame, "FACTION_STANDING_CHANGED", 2510, 12000)
    assert(repHits == 2, "absent reputations flag must default ON")

    -- whole scanners table absent: defaults ON.
    altsSettings.scanners = nil
    gscripts.OnEvent(frame, "FACTION_STANDING_CHANGED", 2510, 12000)
    assert(repHits == 3, "absent scanners table must default all scanners ON")

    -- weeklies + lockouts share the same gate.
    altsSettings.scanners = { weeklies = false, lockouts = false }
    local weekHits, lockHits = 0, 0
    GStorage.ScanWeeklies.MarkAllDirty = function() weekHits = weekHits + 1 end
    GStorage.ScanLockouts.MarkAllDirty = function() lockHits = lockHits + 1 end
    gscripts.OnEvent(frame, "WEEKLY_REWARDS_UPDATE")
    gscripts.OnEvent(frame, "UPDATE_INSTANCE_INFO")
    assert(weekHits == 0, "weeklies=false must gate WEEKLY_REWARDS_UPDATE off")
    assert(lockHits == 0, "lockouts=false must gate UPDATE_INSTANCE_INFO off")
    altsSettings.scanners.weeklies = true
    altsSettings.scanners.lockouts = true
    gscripts.OnEvent(frame, "WEEKLY_REWARDS_UPDATE")
    gscripts.OnEvent(frame, "UPDATE_INSTANCE_INFO")
    assert(weekHits == 1, "weeklies=true must let WEEKLY_REWARDS_UPDATE through")
    assert(lockHits == 1, "lockouts=true must let UPDATE_INSTANCE_INFO through")
end

print("OK: storage_collector_test")
