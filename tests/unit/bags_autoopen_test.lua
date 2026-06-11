-- tests/unit/bags_autoopen_test.lua
-- Run: lua tests/unit/bags_autoopen_test.lua
local loader = dofile("tests/helpers/load_bags_data.lua")
loader.InstallBaseStubs()
_G.Enum.PlayerInteractionType = {
    Merchant = 5, MailInfo = 17, Auctioneer = 21, TradePartner = 28,
    ScrappingMachine = 40, ItemUpgrade = 53,
}

local ns = loader.LoadAll()
local settings = { behavior = { autoOpen = {
    merchant = true, mail = false, auctionHouse = true, trade = true,
    scrappingMachine = true, itemUpgrade = true, socket = true,
} } }
ns.Helpers = { CreateDBGetter = function() return function() return settings end end }
local windowLog = {}
ns.Bags.BagWindow = {
    Show = function() windowLog[#windowLog + 1] = "show" end,
    Hide = function() windowLog[#windowLog + 1] = "hide" end,
    IsShown = function() return false end,
}

local chunk = assert(loadfile("QUI_Bags/bags/autoopen.lua"))
chunk("QUI", ns)
local AutoOpen = ns.Bags.AutoOpen

-- Test 1: interaction SHOW honors per-type settings
AutoOpen.OnInteraction(Enum.PlayerInteractionType.Merchant, true)
assert(windowLog[#windowLog] == "show", "merchant must auto-open")
AutoOpen.OnInteraction(Enum.PlayerInteractionType.MailInfo, true)
assert(#windowLog == 1, "mail disabled must not open")
AutoOpen.OnInteraction(Enum.PlayerInteractionType.Auctioneer, true)
assert(windowLog[#windowLog] == "show", "auctioneer must auto-open")

-- Test 2: HIDE closes only if the SAME interaction opened it
AutoOpen.OnInteraction(Enum.PlayerInteractionType.Merchant, true)
AutoOpen.OnInteraction(Enum.PlayerInteractionType.Merchant, false)
assert(windowLog[#windowLog] == "hide", "merchant leave must auto-close")
local n = #windowLog
AutoOpen.OnInteraction(Enum.PlayerInteractionType.MailInfo, false)
assert(#windowLog == n, "hide for non-opening interaction must be a no-op")

-- Test 3: unknown interaction types are ignored
AutoOpen.OnInteraction(9999, true)
assert(#windowLog == n, "unknown interaction must be ignored")

-- Test 4: ShouldOpenFor maps programmatic opener frames to settings
assert(AutoOpen.ShouldOpenFor({ GetName = function() return "MerchantFrame" end }) == true)
assert(AutoOpen.ShouldOpenFor({ GetName = function() return "MailFrame" end }) == false)
assert(AutoOpen.ShouldOpenFor({ GetName = function() return "SomeRandomFrame" end }) == true,
       "unknown frames default to open")
assert(AutoOpen.ShouldOpenFor(nil) == true, "nil frame defaults to open")
assert(AutoOpen.ShouldOpenFor({ GetName = function() return "QUI_BankWindow" end }) == true,
       "bank window enabled must open")
settings.behavior.autoOpen.bank = false
assert(AutoOpen.ShouldOpenFor({ GetName = function() return "QUI_BankWindow" end }) == false,
       "bank window disabled must not open")
settings.behavior.autoOpen.bank = true

assert(AutoOpen.ShouldOpenFor({ GetName = function() return "QUI_GuildBankWindow" end }) == true,
       "guild bank window enabled must open")
settings.behavior.autoOpen.guildBank = false
assert(AutoOpen.ShouldOpenFor({ GetName = function() return "QUI_GuildBankWindow" end }) == false,
       "guild bank window disabled must not open")
settings.behavior.autoOpen.guildBank = true

print("OK: bags_autoopen_test")
