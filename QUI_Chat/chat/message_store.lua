-- modules/chat/message_store.lua
-- RAM-only ring buffer of captured chat entries — the source of truth for the
-- custom display. The ScrollingMessageFrame is a re-populatable VIEW of this
-- store (tab switches Clear()+re-append; the SMF's own historyBuffer cannot
-- replay removed lines).
--
-- Entry shape: { m=text|SECRET, r,g,b=color, e=eventName, k=typeKey,
--                ch=channelName|nil, s=true when m is secret, t=epoch,
--                gid=senderGUID|nil (non-secret only),
--                w=conversationKey|nil, wn=counterpartyName|nil (whisper
--                events only; nil when the identity arg is absent/secret) }
--
-- SECRET SAFETY: entries may carry secret values in .m. This file must never
-- apply ANY Lua operator to .m — store the table and hand it back, only.
local ADDON_NAME, ns = ...

local _I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: message_store.lua loaded before chat.lua. Check chat.xml — chat.lua must precede message_store.lua.")

ns.QUI.Chat.MessageStore = ns.QUI.Chat.MessageStore or {}
local Store = ns.QUI.Chat.MessageStore

local entries = {}        -- entries[1] = oldest surviving
local cap = 1000
local subscribers = {}

-- Amortized trim: only compact once we overshoot cap by 50%, then slice back
-- down to cap. Keeps Append O(1) during spam bursts.
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
    -- Floor of 50 prevents degenerate compaction thrash from bad settings.
    if type(n) ~= "number" or n < 50 then return end
    cap = math.floor(n)
    Compact()
end

function Store.Append(entry)
    if type(entry) ~= "table" then return end
    entries[#entries + 1] = entry
    Compact()
    for i = 1, #subscribers do
        -- Isolate subscriber errors; the entry passes through untouched.
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
    -- Snapshot the table reference: if fn() calls Store.Clear() mid-iteration,
    -- we keep iterating the old snapshot instead of feeding fn() nils.
    local t = entries
    for i = 1, #t do
        fn(t[i])
    end
end

function Store.Size()
    return #entries
end

function Store.Clear()
    entries = {}
end
