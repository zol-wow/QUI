-- tests/unit/bags_scan_currencies_test.lua
-- Run: lua tests/unit/bags_scan_currencies_test.lua
-- Currency scanner: C_CurrencyInfo list walk keyed by the CurrencyInfo
-- struct's own currencyID field (verified: CurrencyInfoDocumentation —
-- GetCurrencyListInfo returns CurrencyInfo {currencyID, isHeader, quantity,
-- ...}, MayReturnNothing). Collapsed headers HIDE their children from the
-- list (token UI re-lists via ExpandCurrencyList, which the scanner must
-- never call — user-owned UI state), so known-but-unlisted IDs are
-- refreshed by direct C_CurrencyInfo.GetCurrencyInfo(id) lookups, and
-- CURRENCY_DISPLAY_UPDATE payloads feed newly observed IDs in.
-- Store shape: rec.currencies = { [currencyID] = quantity } (flat map —
-- currencies never join item summaries; different ID space).
-- luacheck: globals QUI_StorageDB
local loader = dofile("tests/helpers/load_bags_data.lua")
loader.InstallBaseStubs()

-- C_CurrencyInfo stubs --------------------------------------------------
-- visible list rows mirror the CurrencyInfo struct (only fields the scanner
-- may touch + isHeaderExpanded for realism)
local listRows = {}
_G.C_CurrencyInfo.GetCurrencyListSize = function() return #listRows end
_G.C_CurrencyInfo.GetCurrencyListInfo = function(i) return listRows[i] end
local byID = {} -- direct-lookup space: includes collapsed-header currencies
_G.C_CurrencyInfo.GetCurrencyInfo = function(id) return byID[id] end

local function header(name, expanded)
    return { name = name, currencyID = 0, isHeader = true, isHeaderExpanded = expanded,
             quantity = 0, iconFileID = 0 }
end
local function currency(id, qty, icon)
    local info = { name = "Currency" .. id, currencyID = id, isHeader = false,
                   isHeaderExpanded = false, quantity = qty, iconFileID = icon or 1 }
    byID[id] = info
    return info
end

local ns = loader.LoadAll(nil, "scan_currencies.lua")
ns.Bags.RequestDrain = function() end
local Store, ScanCurrencies, Bus = ns.Bags.Store, ns.Bags.ScanCurrencies, ns.Bags.Bus

_G.QUI_StorageDB = nil
Store.Initialize()
Store.EnsureCurrentCharacter()
local KEY = "Testchar-TestRealm"

local events = {}
Bus.Subscribe("CurrenciesChanged", function(_, charKey) events[#events + 1] = charKey end)

-- Test 1: clean drain no-ops
assert(ScanCurrencies.Drain() == false, "undirtied drain must no-op")

-- Test 2: list walk skips headers, keys by currencyID, prunes zeros
listRows = {
    header("Season", true),
    currency(3008, 1500),
    currency(2245, 0),     -- zero quantity → pruned
    header("Legacy", true),
    currency(1166, 42),
}
ScanCurrencies.MarkAllDirty()
assert(ScanCurrencies.Drain() == true, "dirty drain must write")
local rec = Store.GetCurrentCharacter()
assert(rec.currencies[3008] == 1500 and rec.currencies[1166] == 42, "list quantities wrong")
assert(rec.currencies[2245] == nil, "zero-quantity currencies must be pruned")
assert(rec.currencies[0] == nil, "headers must never be stored")
local n = 0; for _ in pairs(rec.currencies) do n = n + 1 end
assert(n == 2, "exactly the two non-zero currencies expected, got " .. n)
assert(#events == 1 and events[1] == KEY, "exactly one CurrenciesChanged(charKey) per drain")
assert(ScanCurrencies.Drain() == false, "clean drain must no-op")

-- Test 3: a previously known ID that fell out of the visible list (its
-- header collapsed) is refreshed via direct GetCurrencyInfo
byID[1166].quantity = 50
listRows = { header("Season", true), currency(3008, 1500), header("Legacy", false) }
ScanCurrencies.MarkAllDirty()
assert(ScanCurrencies.Drain() == true)
rec = Store.GetCurrentCharacter()
assert(rec.currencies[1166] == 50,
       "collapsed-header currency must refresh by ID, got " .. tostring(rec.currencies[1166]))

-- Test 4: CURRENCY_DISPLAY_UPDATE payload feeds an unlisted (collapsed) ID in
local hidden = currency(2812, 7) -- exists in the byID space only
hidden.quantity = 7
ScanCurrencies.OnDisplayUpdate(2812)
assert(ScanCurrencies.Drain() == true)
rec = Store.GetCurrentCharacter()
assert(rec.currencies[2812] == 7, "event-observed currency must be captured by ID")

-- Test 5: payload-free CURRENCY_DISPLAY_UPDATE (all-nilable payload) just
-- marks dirty — full re-walk
byID[3008].quantity = 1600
listRows[2] = byID[3008]
ScanCurrencies.OnDisplayUpdate(nil)
assert(ScanCurrencies.Drain() == true)
rec = Store.GetCurrentCharacter()
assert(rec.currencies[3008] == 1600, "payload-free update must re-walk the list")

-- Test 6: a known currency dropping to zero is pruned on the next drain
byID[3008].quantity = 0
ScanCurrencies.OnDisplayUpdate(3008)
assert(ScanCurrencies.Drain() == true)
rec = Store.GetCurrentCharacter()
assert(rec.currencies[3008] == nil, "zeroed currency must drop out of the map")

-- Test 7: MayReturnNothing tolerance — nil list rows and nil by-ID lookups
listRows = { nil }
byID = {}
ScanCurrencies.MarkAllDirty()
assert(ScanCurrencies.Drain() == true, "drain over nothing-returning APIs must not error")
rec = Store.GetCurrentCharacter()
assert(next(rec.currencies) == nil, "no readable currencies → empty map")

-- Test 8: drain with no character record preserves the dirty mark
ScanCurrencies.MarkAllDirty()
Store.DeleteCharacter(KEY)
assert(ScanCurrencies.Drain() == false, "drain without a record must not write")
Store.EnsureCurrentCharacter()
assert(ScanCurrencies.Drain() == true, "mark must survive a record-less drain")

print("OK: bags_scan_currencies_test")
