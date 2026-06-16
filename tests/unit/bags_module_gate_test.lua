-- tests/unit/bags_module_gate_test.lua
-- Verifies the bags module entry (UI-only after the collector split): the
-- enabled gate controls the UI lifecycle (takeover apply/revert, window
-- hides, UI-event registration), the UI OnEvent branches route correctly,
-- and Registry/slash/keybind registration shape is right. Collection itself
-- is a core service (core/storage/collector.lua) and is covered by
-- storage_collector_test.lua — this file asserts NOTHING about scanning.
-- Run: lua tests/unit/bags_module_gate_test.lua
-- luacheck: globals QUI_StorageDB
local loader = dofile("tests/helpers/load_bags_data.lua")
loader.InstallBaseStubs()
_G.C_Container.GetContainerNumSlots = function() return 0 end
_G.C_Container.GetContainerItemInfo = function() return nil end
_G.C_Bank.FetchPurchasedBankTabData = function() return nil end
_G.C_Bank.FetchBankLockedReason = function() return nil end
_G.C_Bank.FetchDepositedMoney = function() return 0 end
_G.Enum.PlayerInteractionType = { Merchant = 5, MailInfo = 17, GuildBanker = 10 }

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
;(dofile("tests/helpers/locale.lua"))(ns)
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

-- Test 2: disabled at login → the UI does NOT start (no takeover, no UI
-- events). The store/collection is a CORE service (collector.lua) and is NOT
-- this module's concern — bags.lua must not init the store and IsActive is
-- false. LOD startup runs through the captured ns.WhenLoggedIn callback.
assert(type(loginCallback) == "function", "bags.lua must register startup via ns.WhenLoggedIn")
loginCallback()
assert(QUI_StorageDB == nil, "bags.lua (UI) must not initialize the store — that is the collector's job")
assert(#takeoverLog == 0, "disabled module must not apply the takeover")
assert(not registered["BANKFRAME_OPENED"], "UI events must not register while disabled")
assert(ns.Bags.IsActive() == false, "IsActive must be false while disabled")

-- Test 3: enabling via refresh applies the takeover IMMEDIATELY (a B-press in
-- the deferral window must not open the Blizzard bags) and defers UI-event
-- registration past first paint. bags.lua must NOT touch the store.
settings.enabled = true
def.refresh()
assert(QUI_StorageDB == nil, "enabling the bags UI must not initialize the store (collector owns it)")
assert(ns.Bags.IsActive() == true, "IsActive must be true once the UI is live")
-- Takeover.Apply, BankTakeover.Suppress, AND GuildTakeover.Init must all
-- fire synchronously before first paint (same race rationale).
assert(takeoverLog[#takeoverLog - 2] == "apply"
       and takeoverLog[#takeoverLog - 1] == "bank-suppress"
       and takeoverLog[#takeoverLog] == "guild-init",
       "enable must apply Takeover, BankTakeover.Suppress, then GuildTakeover.Init synchronously, before first paint")
assert(#firstFrameQueue >= 1, "UI-event registration must defer past first frame")
assert(not registered["BANKFRAME_OPENED"], "UI events must not register before first paint")
-- Count guild-init calls before and after the first-frame flush: the deferred
-- block re-calls GuildTakeover.Init (missed-ADDON_LOADED window fix).
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
assert(countInits(takeoverLog) >= initsBeforeFlush + 1,
       "GuildTakeover.Init must be called again inside the first-frame flush (missed-ADDON_LOADED guard)")
local nonInitAddsAfterFlush = (#takeoverLog - appliesBeforeFlush) - (countInits(takeoverLog) - initsBeforeFlush)
assert(nonInitAddsAfterFlush == 0, "the deferred block must not re-apply Apply or BankTakeover.Suppress")
-- Only UI/takeover/ops events register on this frame; data-collection events
-- belong to the collector and must NOT appear here.
assert(registered["BANKFRAME_OPENED"] and registered["BANKFRAME_CLOSED"]
       and registered["PLAYER_INTERACTION_MANAGER_FRAME_SHOW"]
       and registered["PLAYER_INTERACTION_MANAGER_FRAME_HIDE"]
       and registered["ITEM_LOCK_CHANGED"] and registered["BAG_UPDATE_COOLDOWN"]
       and registered["EQUIPMENT_SETS_CHANGED"]
       and registered["PLAYER_REGEN_DISABLED"]
       and registered["GUILDBANKFRAME_OPENED"] and registered["GUILDBANKFRAME_CLOSED"]
       and registered["GUILDBANKLOG_UPDATE"] and registered["ADDON_LOADED"],
       "UI events missing after first-frame flush")
assert(not registered["BAG_UPDATE"] and not registered["BAG_UPDATE_DELAYED"]
       and not registered["ITEM_DATA_LOAD_RESULT"] and not registered["PLAYER_MONEY"]
       and not registered["MAIL_SHOW"] and not registered["CURRENCY_DISPLAY_UPDATE"]
       and not registered["GUILDBANKBAGSLOTS_CHANGED"] and not registered["GUILDBANK_UPDATE_MONEY"],
       "data-collection events must NOT register on the bags UI frame (collector owns them)")

-- Test 4: BANKFRAME_OPENED routes to BankTakeover.OnBankOpened() + auto-deposit
scripts.OnEvent(frame, "BANKFRAME_OPENED")
assert(takeoverLog[#takeoverLog] == "bank-opened",
       "BANKFRAME_OPENED must route to BankTakeover.OnBankOpened()")
local autoDeposits = 0
ns.Bags.Transfers = { AutoDepositReagentsOnOpen = function() autoDeposits = autoDeposits + 1 end }
scripts.OnEvent(frame, "BANKFRAME_OPENED")
assert(autoDeposits == 1, "BANKFRAME_OPENED must run Transfers.AutoDepositReagentsOnOpen()")
ns.Bags.Transfers = nil
-- BANKFRAME_CLOSED → BankTakeover.OnBankClosed (Transfers nil here proves the
-- existence guard on the transfer-cancel route holds)
scripts.OnEvent(frame, "BANKFRAME_CLOSED")
assert(takeoverLog[#takeoverLog] == "bank-closed",
       "BANKFRAME_CLOSED must route to BankTakeover.OnBankClosed()")
local bankCloseCancels = 0
ns.Bags.Transfers = { Cancel = function() bankCloseCancels = bankCloseCancels + 1 end }
scripts.OnEvent(frame, "BANKFRAME_CLOSED")
assert(bankCloseCancels == 1, "BANKFRAME_CLOSED must route to Transfers.Cancel()")
ns.Bags.Transfers = nil

-- Test 5: interaction routing (auto-open + junk + guild takeover)
scripts.OnEvent(frame, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 5)
scripts.OnEvent(frame, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 5)
assert(#interactions == 2 and interactions[1][1] == 5 and interactions[1][2] == true
       and interactions[2][1] == 5 and interactions[2][2] == false,
       "interaction events must route to AutoOpen.OnInteraction(type, shown)")
-- Merchant interactions must ALSO notify Junk.OnMerchant(shown), both ways;
-- non-merchant interactions must not. (Junk nil first proves the guard holds.)
scripts.OnEvent(frame, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.Merchant)
local merchantNotices = {}
ns.Bags.Junk = { OnMerchant = function(shown) merchantNotices[#merchantNotices + 1] = shown end }
scripts.OnEvent(frame, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.Merchant)
scripts.OnEvent(frame, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", Enum.PlayerInteractionType.Merchant)
assert(#merchantNotices == 2 and merchantNotices[1] == true and merchantNotices[2] == false,
       "merchant interaction must route to Junk.OnMerchant(true) then (false)")
scripts.OnEvent(frame, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.MailInfo)
scripts.OnEvent(frame, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", Enum.PlayerInteractionType.MailInfo)
assert(#merchantNotices == 2, "non-merchant interactions must not notify Junk")
ns.Bags.Junk = nil
-- GuildBanker interaction → GuildTakeover.OnOpened/OnClosed
local gtBefore = #guildTakeoverLog
scripts.OnEvent(frame, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.GuildBanker)
assert(guildTakeoverLog[#guildTakeoverLog] == "guild-opened",
       "GuildBanker interaction SHOW must route to GuildTakeover.OnOpened()")
scripts.OnEvent(frame, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", Enum.PlayerInteractionType.GuildBanker)
assert(guildTakeoverLog[#guildTakeoverLog] == "guild-closed",
       "GuildBanker interaction HIDE must route to GuildTakeover.OnClosed()")
assert(#guildTakeoverLog == gtBefore + 2, "GuildBanker interaction must route exactly two takeover calls")

-- Test 6: ITEM_LOCK_CHANGED / BAG_UPDATE_COOLDOWN / EQUIPMENT_SETS_CHANGED
-- → synthetic re-dress pings, only while the relevant window is shown.
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
local bankLockPings = 0
ns.Bags.Bus.Subscribe("BankChanged", function() bankLockPings = bankLockPings + 1 end)
scripts.OnEvent(frame, "ITEM_LOCK_CHANGED", 6, 1)
assert(bankLockPings == 0, "no BankChanged ping while the bank window is hidden")
ns.Bags.BankWindow.IsShown = function() return true end
scripts.OnEvent(frame, "ITEM_LOCK_CHANGED", 6, 1)
scripts.OnEvent(frame, "BAG_UPDATE_COOLDOWN")
assert(bankLockPings == 2, "lock/cooldown must publish BankChanged when the bank window is shown")
ns.Bags.BankWindow.IsShown = function() return false end
-- EQUIPMENT_SETS_CHANGED rides the same route
local eqBagPings, eqBankPings = 0, 0
ns.Bags.Bus.Subscribe("BagsChanged", function() eqBagPings = eqBagPings + 1 end)
ns.Bags.Bus.Subscribe("BankChanged", function() eqBankPings = eqBankPings + 1 end)
scripts.OnEvent(frame, "EQUIPMENT_SETS_CHANGED")
assert(eqBagPings == 0 and eqBankPings == 0, "set changes must not ping while both windows are hidden")
ns.Bags.BagWindow.IsShown = function() return true end
ns.Bags.BankWindow.IsShown = function() return true end
scripts.OnEvent(frame, "EQUIPMENT_SETS_CHANGED")
assert(eqBagPings == 1 and eqBankPings == 1, "set changes must re-dress both shown windows")
ns.Bags.BagWindow.IsShown = function() return false end
ns.Bags.BankWindow.IsShown = function() return false end

-- Test 7: guild bank UI routing (legacy events + log + ADDON_LOADED)
scripts.OnEvent(frame, "GUILDBANKFRAME_OPENED")
assert(guildTakeoverLog[#guildTakeoverLog] == "guild-opened",
       "GUILDBANKFRAME_OPENED must route to GuildTakeover.OnOpened()")
scripts.OnEvent(frame, "GUILDBANKFRAME_CLOSED")
assert(guildTakeoverLog[#guildTakeoverLog] == "guild-closed",
       "GUILDBANKFRAME_CLOSED must route to GuildTakeover.OnClosed()")
-- GUILDBANKLOG_UPDATE → GuildWindow.OnLogUpdate, gated on IsShown
local logBefore = guildLogUpdates
scripts.OnEvent(frame, "GUILDBANKLOG_UPDATE")
assert(guildLogUpdates == logBefore, "GUILDBANKLOG_UPDATE must NOT render while the guild window is hidden")
guildWindowShown = true
scripts.OnEvent(frame, "GUILDBANKLOG_UPDATE")
assert(guildLogUpdates == logBefore + 1, "GUILDBANKLOG_UPDATE must render when the guild window is shown")
guildWindowShown = false
-- ADDON_LOADED → GuildTakeover.OnAddonLoaded(arg1) — forward the name argument
scripts.OnEvent(frame, "ADDON_LOADED", "Blizzard_GuildBankUI")
local lastGTEntry = guildTakeoverLog[#guildTakeoverLog]
assert(type(lastGTEntry) == "table" and lastGTEntry[1] == "guild-addon-loaded"
       and lastGTEntry[2] == "Blizzard_GuildBankUI",
       "ADDON_LOADED must forward arg1 to GuildTakeover.OnAddonLoaded(arg1)")

-- Test 8: PLAYER_REGEN_DISABLED → ops combat aborts, existence-guarded.
scripts.OnEvent(frame, "PLAYER_REGEN_DISABLED") -- must not error without ops
local sortCombats, transferCombats, junkCombats = 0, 0, 0
ns.Bags.SortExecutor = { OnCombat = function() sortCombats = sortCombats + 1 end }
ns.Bags.Transfers    = { OnCombat = function() transferCombats = transferCombats + 1 end }
ns.Bags.Junk         = { OnCombat = function() junkCombats = junkCombats + 1 end }
scripts.OnEvent(frame, "PLAYER_REGEN_DISABLED")
assert(sortCombats == 1, "PLAYER_REGEN_DISABLED must route to SortExecutor.OnCombat()")
assert(transferCombats == 1, "PLAYER_REGEN_DISABLED must route to Transfers.OnCombat()")
assert(junkCombats == 1, "PLAYER_REGEN_DISABLED must route to Junk.OnCombat()")
ns.Bags.SortExecutor, ns.Bags.Transfers, ns.Bags.Junk = nil, nil, nil

-- Test 9: refresh while already enabled + active (profile switch between two
-- enabled profiles) must re-anchor all four windows via OnProfileChanged
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

-- Test 10: /quibags slash routing (registered at load; gated on IsActive)
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

-- Test 11: cached bank/guild browsing away from live sessions. The toggles
-- prefer the LIVE presentation when the session is open, cached otherwise;
-- shown windows just hide.
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
local bankShowsBefore, guildShowsBefore = #bankShows, #guildShows
slash("bank")
assert(#bankShows == bankShowsBefore + 1, "/quibags bank must run the bank toggle")
slash("guild")
assert(#guildShows == guildShowsBefore + 1, "/quibags guild must run the guild toggle")
assert(_G.BINDING_NAME_QUI_BAGS_TOGGLE_BANK ~= nil, "bank keybind label must be registered")
assert(_G.BINDING_NAME_QUI_BAGS_TOGGLE_GUILD ~= nil, "guild keybind label must be registered")

-- Test 12: /quibags clearnew → NewItems.ClearAllNew (existence-guarded)
local clearNews = 0
ns.Bags.NewItems = { ClearAllNew = function() clearNews = clearNews + 1 end }
slash("clearnew")
assert(clearNews == 1, "/quibags clearnew must route to NewItems.ClearAllNew")
ns.Bags.NewItems = nil

-- Test 13: disabling via refresh unregisters the UI events, hides the windows,
-- cancels ops, and reverts the takeovers — silently. Collection (the
-- collector) is unaffected; this module owns the UI only.
local hiddenBeforeDisable = bankWindowHides
local guildHiddenBeforeDisable = guildWindowHides
ns.Bags.SortExecutor = { Cancel = logger("sort-cancel") }
ns.Bags.Transfers    = { Cancel = logger("transfer-cancel") }
ns.Bags.Junk = { OnMerchant = function(shown) takeoverLog[#takeoverLog + 1] = "junk-merchant:" .. tostring(shown) end }
ns.Bags.NewItems = { OnDisable = logger("newitems-disable") }
settings.enabled = false
def.refresh()
ns.Bags.SortExecutor, ns.Bags.Transfers, ns.Bags.Junk, ns.Bags.NewItems = nil, nil, nil, nil
assert(ns.Bags.IsActive() == false, "IsActive must drop to false on disable")
assert(not registered["BANKFRAME_OPENED"] and not registered["BANKFRAME_CLOSED"]
       and not registered["PLAYER_INTERACTION_MANAGER_FRAME_SHOW"]
       and not registered["ITEM_LOCK_CHANGED"] and not registered["BAG_UPDATE_COOLDOWN"]
       and not registered["EQUIPMENT_SETS_CHANGED"] and not registered["PLAYER_REGEN_DISABLED"]
       and not registered["GUILDBANKFRAME_OPENED"] and not registered["GUILDBANKFRAME_CLOSED"]
       and not registered["GUILDBANKLOG_UPDATE"] and not registered["ADDON_LOADED"],
       "all UI events must unregister when disabled")
-- StopUI order: ALL windows hide FIRST (their onClose must still see IsLive()
-- to route server-side closes), then ops cancels + merchant reset, then
-- NewItems.OnDisable, then Takeover.Revert, BankTakeover.Revert, GuildTakeover.Revert.
assert(takeoverLog[#takeoverLog - 10] == "bag-window-hide"
       and takeoverLog[#takeoverLog - 9] == "bank-window-hide"
       and takeoverLog[#takeoverLog - 8] == "guild-window-hide"
       and takeoverLog[#takeoverLog - 7] == "search-window-hide"
       and takeoverLog[#takeoverLog - 6] == "sort-cancel"
       and takeoverLog[#takeoverLog - 5] == "transfer-cancel"
       and takeoverLog[#takeoverLog - 4] == "junk-merchant:false"
       and takeoverLog[#takeoverLog - 3] == "newitems-disable"
       and takeoverLog[#takeoverLog - 2] == "revert"
       and takeoverLog[#takeoverLog - 1] == "bank-revert"
       and takeoverLog[#takeoverLog] == "guild-revert",
       "disable must hide windows, cancel ops + reset merchant, disable new-items, then revert the takeovers")
assert(bankWindowHides > hiddenBeforeDisable, "disable must hide the bank window")
assert(guildWindowHides > guildHiddenBeforeDisable, "disable must hide the guild window")
assert(#popupsShown == 0, "disable must be silent — no reload prompt (profile switches must not nag)")

-- Test 14: the slash command goes quiet while the module is disabled
do
    local p = {}
    local rp = _G.print
    _G.print = function(...) p[#p + 1] = table.concat({ ... }, " ") end
    SlashCmdList["QUIBAGS"]("")
    SlashCmdList["QUIBAGS"]("search")
    _G.print = rp
    assert(bagToggles == 1 and searchToggles == 2,
        "/quibags must not toggle windows while the module is disabled")
    assert(#p == 2, "disabled /quibags must explain itself")
end

print("OK: bags_module_gate_test")
