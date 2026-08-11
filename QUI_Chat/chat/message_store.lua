local ADDON_NAME, ns = ...

local _I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: message_store.lua loaded before chat.lua. Check chat.xml — chat.lua must precede message_store.lua.")

ns.QUI.Chat.MessageStore = ns.QUI.Chat.MessageStore or {}
local Store = ns.QUI.Chat.MessageStore

local entries = {}
local cap = 1000
local subscribers = {}

local function Compact()
    local n = #entries
    if n <= cap + math.floor(cap / 2) then return end
    local fresh = {}
    for i = n - cap + 1, n do
        fresh[#fresh + 1] = entries[i]
    end
    entries = fresh
end

function Store.SetCap(n)
    if type(n) ~= "number" or n < 50 then return end
    cap = math.floor(n)
    Compact()
end

function Store.Append(entry)
    if type(entry) ~= "table" then return end
    entries[#entries + 1] = entry
    Compact()
    for i = 1, #subscribers do
        local ok, err = pcall(subscribers[i], entry)
        if not ok and _G.geterrorhandler then
            _G.geterrorhandler()(err)
        end
    end
end

function Store.OnAppend(fn)
    if type(fn) == "function" then
        subscribers[#subscribers + 1] = fn
    end
end

function Store.ForEach(fn)
    local t = entries
    for i = 1, #t do
        fn(t[i])
    end
end

function Store.Size()
    return #entries
end

function Store.RemoveWhere(pred)
    if type(pred) ~= "function" then return 0 end
    local kept, removed = {}, 0
    for i = 1, #entries do
        local entry = entries[i]
        local ok, matched = ns.SafeCall("bulkhead", pred, entry)
        if ok and matched then
            removed = removed + 1
        else
            kept[#kept + 1] = entry
        end
    end
    if removed > 0 then
        entries = kept
    end
    return removed
end

function Store.Clear()
    entries = {}
end
