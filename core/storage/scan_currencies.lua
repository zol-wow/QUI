local ADDON_NAME, ns = ...
local Storage = ns.Storage or {}; ns.Storage = Storage

local ScanCurrencies = {}
Storage.ScanCurrencies = ScanCurrencies

local hasDirty = false
local observed = {}

function ScanCurrencies.OnDisplayUpdate(currencyID)
    if currencyID then observed[currencyID] = true end
    hasDirty = true
end

function ScanCurrencies.MarkAllDirty()
    hasDirty = true
end

function ScanCurrencies.Drain()
    if not hasDirty then return false end
    local rec = Storage.Store.GetCurrentCharacter()
    if not rec then return false end
    hasDirty = false
    local fresh = {}
    for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
        local info = C_CurrencyInfo.GetCurrencyListInfo(i)
        if info and not info.isHeader and info.currencyID and info.currencyID > 0
                and info.quantity and info.quantity > 0 then
            fresh[info.currencyID] = info.quantity
        end
    end
    local function RefreshUnlisted(id)
        if fresh[id] == nil then
            local info = C_CurrencyInfo.GetCurrencyInfo(id)
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
    Storage.Bus.Publish("CurrenciesChanged", Storage.Store.GetCurrentCharacterKey())
    return true
end
