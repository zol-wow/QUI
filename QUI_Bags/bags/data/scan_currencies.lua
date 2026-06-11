---------------------------------------------------------------------------
-- Bags data layer: currency scanner.
-- Enumeration choice (verified against CurrencyInfoDocumentation):
-- GetCurrencyListInfo(i) returns the full CurrencyInfo struct — including
-- its own `currencyID` and `isHeader` fields — so the visible list walk
-- needs no link parsing. The wrinkle is COLLAPSED HEADERS: collapsed
-- children disappear from the list entirely, and the token UI's remedy
-- (C_CurrencyInfo.ExpandCurrencyList) mutates user-owned UI state, so the
-- scanner must never call it. Instead:
--   1. walk the visible list (skip isHeader rows; key by currencyID),
--   2. refresh IDs known from earlier drains that fell out of the visible
--      walk via direct C_CurrencyInfo.GetCurrencyInfo(id) lookups,
--   3. accumulate IDs observed in CURRENCY_DISPLAY_UPDATE payloads
--      (currencyType is nilable — payload-free fires mean "list changed"),
--      so collapsed-header currencies are captured as soon as they change.
-- Zero quantities are pruned (the map stays small; a zeroed currency that
-- rises again re-announces itself through the event payload).
-- Store shape: rec.currencies = { [currencyID] = quantity } — a flat map,
-- NOT { slots = ... }: currencies never join item summaries (different ID
-- space). Tooltip counts for currencies read store records directly
-- (currency tooltip hook deliberately out of v1 scope).
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags

local ScanCurrencies = {}
Bags.ScanCurrencies = ScanCurrencies

local hasDirty = false
local observed = {} -- [currencyID] = true; event-payload IDs seen this session

--- CURRENCY_DISPLAY_UPDATE: payload (currencyType, quantity, ...) is fully
--- nilable — a carried ID is remembered for by-ID refresh; either way the
--- whole list is the rescan unit (cheap synchronous struct reads).
function ScanCurrencies.OnDisplayUpdate(currencyID)
    if currencyID then observed[currencyID] = true end
    hasDirty = true
end

--- Login catch-up alias (deferred-block symmetry with the other scanners).
function ScanCurrencies.MarkAllDirty()
    hasDirty = true
end

--- Rebuild the currency map; publishes CurrenciesChanged(charKey)
--- (whole-record event — no changed array; see bus.lua). Returns true when
--- written.
function ScanCurrencies.Drain()
    if not hasDirty then return false end
    local rec = Bags.Store.GetCurrentCharacter()
    if not rec then return false end -- transient: dirty mark preserved
    hasDirty = false
    local fresh = {}
    -- 1) visible list walk (collapsed headers hide their children here)
    for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
        local info = C_CurrencyInfo.GetCurrencyListInfo(i) -- MayReturnNothing
        if info and not info.isHeader and info.currencyID and info.currencyID > 0
                and info.quantity and info.quantity > 0 then
            fresh[info.currencyID] = info.quantity
        end
    end
    -- 2)+3) refresh known-but-unlisted IDs by direct lookup
    local function RefreshUnlisted(id)
        if fresh[id] == nil then
            local info = C_CurrencyInfo.GetCurrencyInfo(id) -- MayReturnNothing
            if info and info.quantity and info.quantity > 0 then
                fresh[id] = info.quantity
            end
        end
    end
    local old = rec.currencies
    if type(old) == "table" then
        for id in pairs(old) do RefreshUnlisted(id) end
    end
    for id in pairs(observed) do RefreshUnlisted(id) end
    rec.currencies = fresh
    Bags.Bus.Publish("CurrenciesChanged", Bags.Store.GetCurrentCharacterKey())
    return true
end
