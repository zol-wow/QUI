-- tests/unit/chat_history_store_path_test.lua
-- Run: lua tests/unit/chat_history_store_path_test.lua
-- Verifies the store-path capture and repump branches in history.lua:
--   (a) suppressed + SAY entry               → AppendLive {f=1, c="SAY", m=...}
--   (b) not suppressed (pre-PEW window)       → STILL appends (single path)
--   (c) whisper entry, storeWhispers=false    → skipped
--   (d) e="HISTORY"/"BACKFILL" or entry.hist → skipped
--   (e) secret entry (entry.s=true)           → skipped
--   (f) repump + enabled                      → store receives sep+lines+sep;
--                                                separators stay SYSTEM+hist,
--                                                lines preserve their original
--                                                routing fields (k/ch/e) + hist;
--                                                NO AddMessage on any frame
--   (g) repump never AddMessages frames       → regardless of state, frames
--                                                receive zero AddMessage calls;
--                                                store still receives lines
-- luacheck: globals CreateFrame hooksecurefunc GetServerTime time NUM_CHAT_WINDOWS ChatFrame1 ChatFrame2

local unpack = unpack or table.unpack

-------------------------------------------------------------------------------
-- Globals required by history.lua
-------------------------------------------------------------------------------

local eventFrame
function _G.CreateFrame(...)
    local f = {}
    function f:RegisterEvent() end
    function f:UnregisterEvent() end
    function f:UnregisterAllEvents() end
    function f:SetScript(script, handler)
        if script == "OnEvent" then
            eventFrame = f
            f.OnEvent = handler
        end
    end
    return f
end

function _G.hooksecurefunc(target, method, fn)
    if type(target) == "table" then
        local orig = target[method] or function() end
        target[method] = function(self, ...)
            local r = { orig(self, ...) }
            fn(self, ...)
            return unpack(r)
        end
    end
    -- global-name variant: no-op (history.lua uses this for FCF hooks)
end

_G.GetServerTime = function() return 1700000000 end
_G.time = function() return 1700000000 end
_G.NUM_CHAT_WINDOWS = 2

local chatFrame1 = {}
function chatFrame1:AddMessage() end
_G.ChatFrame1 = chatFrame1
_G.ChatFrame2 = {}   -- combat log placeholder (never hooked)

_G.QUI = {}  -- the AceAddon global expected by history.lua

-------------------------------------------------------------------------------
-- Toggleable state
-------------------------------------------------------------------------------

local suppressActive   = false
local appendLiveCalls  = {}  -- records each AppendLive call
local storeAppendCalls = {}  -- records each MessageStore.Append call
local addMsgCalls      = {}  -- per-frame AddMessage call records

local settings = {
    enabled    = true,
    history = {
        enabled         = true,
        storeWhispers   = false,
        excludedChannels = {},
        replayLines     = 10,
        showSeparators  = true,
    },
}

-------------------------------------------------------------------------------
-- Storage stub with GetRecentEntries fixture
-------------------------------------------------------------------------------

local storageFxEntries = {}  -- seeded per repump test

local HistoryStorageStub = {
    Init            = function() end,
    MigrateFromAceDB = function() end,
    PersistNow      = function() end,
    Prune           = function() end,
    AppendLive = function(entry)
        appendLiveCalls[#appendLiveCalls + 1] = entry
    end,
    GetRecentEntries = function(limit)
        local out = {}
        for i = 1, math.min(limit, #storageFxEntries) do
            out[#out + 1] = storageFxEntries[i]
        end
        return out
    end,
}

-------------------------------------------------------------------------------
-- MessageStore stub
-------------------------------------------------------------------------------

local storeSubscribers = {}

local MessageStoreStub = {
    OnAppend = function(fn)
        if type(fn) == "function" then
            storeSubscribers[#storeSubscribers + 1] = fn
        end
    end,
    Append = function(entry)
        storeAppendCalls[#storeAppendCalls + 1] = entry
    end,
}

-------------------------------------------------------------------------------
-- Build ns
-------------------------------------------------------------------------------

local ns = {
    Helpers = {
        IsSecretValue = function(v)
            return type(v) == "table" and v.__secret == true
        end,
        HasSecretValue = function(...)
            for i = 1, select("#", ...) do
                local v = select(i, ...)
                if type(v) == "table" and v.__secret == true then return true end
            end
            return false
        end,
    },
    QUI = {
        Chat = {
            _internals = {
                GetSettings    = function() return settings end,
                IsChatEnabled  = function(s) return s and s.enabled ~= false end,
            },
            HistoryStorage = HistoryStorageStub,
            MessageStore   = MessageStoreStub,
            BlizzardSuppress = {
                IsActive = function() return suppressActive end,
            },
            _afterRefresh = {},
        },
    },
}

-------------------------------------------------------------------------------
-- Load history.lua
-------------------------------------------------------------------------------

assert(loadfile("QUI_Chat/chat/history.lua"))("QUI", ns)

local History = ns.QUI.Chat.History
assert(History, "History table exported")
assert(type(History._CaptureFromStore) == "function", "_CaptureFromStore exported")
assert(type(History._Repump) == "function",           "_Repump exported")

-------------------------------------------------------------------------------
-- Helper: fire a store entry through captureFromStore directly
-------------------------------------------------------------------------------

local function fireCapture(entry)
    History._CaptureFromStore(entry)
end

local function resetCaptureCalls()
    appendLiveCalls = {}
end

local function resetRepumpCalls()
    storeAppendCalls = {}
    addMsgCalls = {}
end

-- Instrument ChatFrame1.AddMessage to record calls
local addMsgOrig = chatFrame1.AddMessage
chatFrame1.AddMessage = function(self, m, r, g, b)
    addMsgCalls[#addMsgCalls + 1] = { m = m, r = r, g = g, b = b }
    return addMsgOrig(self, m, r, g, b)
end

-------------------------------------------------------------------------------
-- Case (a): suppressed + SAY entry → AppendLive {f=1, c="SAY", m=...}
-------------------------------------------------------------------------------

suppressActive = true
resetCaptureCalls()
fireCapture({ e = "CHAT_MSG_SAY", k = "SAY", m = "hello world",
              r = 1, g = 1, b = 1, s = false })
assert(#appendLiveCalls == 1,
    "(a) expected 1 AppendLive, got " .. #appendLiveCalls)
assert(appendLiveCalls[1].f == 1,
    "(a) f should be 1, got " .. tostring(appendLiveCalls[1].f))
assert(appendLiveCalls[1].c == "SAY",
    "(a) c should be SAY, got " .. tostring(appendLiveCalls[1].c))
assert(appendLiveCalls[1].m == "hello world",
    "(a) m mismatch, got " .. tostring(appendLiveCalls[1].m))
assert(appendLiveCalls[1].ev == "CHAT_MSG_SAY",
    "(a) source event must be persisted for replay routing, got "
    .. tostring(appendLiveCalls[1].ev))
print("  ok  (a) suppressed SAY -> AppendLive f=1 c=SAY ev=CHAT_MSG_SAY")

-- Channel capture also persists the channel NAME (named-channel routing).
resetCaptureCalls()
fireCapture({ e = "CHAT_MSG_CHANNEL", k = "CHANNEL2", ch = "Trade",
              m = "WTS something", r = 1, g = 1, b = 1, s = false })
assert(#appendLiveCalls == 1, "(a2) expected 1 AppendLive, got " .. #appendLiveCalls)
assert(appendLiveCalls[1].ch == "Trade",
    "(a2) channel name must be persisted, got " .. tostring(appendLiveCalls[1].ch))
assert(appendLiveCalls[1].c == "CHANNEL2",
    "(a2) type key persisted, got " .. tostring(appendLiveCalls[1].c))
print("  ok  (a2) channel capture persists ch=Trade for replay routing")

-------------------------------------------------------------------------------
-- Case (b): not suppressed (pre-PEW window) → STILL appends (single path)
-------------------------------------------------------------------------------

suppressActive = false
resetCaptureCalls()
fireCapture({ e = "CHAT_MSG_SAY", k = "SAY", m = "pre-pew line",
              r = 1, g = 1, b = 1, s = false })
assert(#appendLiveCalls == 1,
    "(b) not suppressed must STILL append (store path owns all windows), got "
    .. #appendLiveCalls)
print("  ok  (b) not suppressed -> still appends (single path)")

-------------------------------------------------------------------------------
-- Case (c): whisper entry, storeWhispers=false → skipped
-------------------------------------------------------------------------------

suppressActive = true
resetCaptureCalls()
fireCapture({ e = "CHAT_MSG_WHISPER", k = "WHISPER", m = "secret whisper",
              r = 1, g = 1, b = 1, s = false })
assert(#appendLiveCalls == 0,
    "(c) whisper with storeWhispers=false should be skipped, got " .. #appendLiveCalls)
print("  ok  (c) whisper skipped when storeWhispers=false")

-------------------------------------------------------------------------------
-- Case (d): e="HISTORY" and e="BACKFILL" → skipped
-------------------------------------------------------------------------------

suppressActive = true
resetCaptureCalls()
fireCapture({ e = "HISTORY", k = "SYSTEM", m = "old line",
              r = 1, g = 1, b = 1, s = false })
assert(#appendLiveCalls == 0,
    "(d) e=HISTORY should be skipped, got " .. #appendLiveCalls)

fireCapture({ e = "BACKFILL", k = "SAY", m = "backfill line",
              r = 1, g = 1, b = 1, s = false })
assert(#appendLiveCalls == 0,
    "(d) e=BACKFILL should be skipped, got " .. #appendLiveCalls)

-- A replayed history line now carries its ORIGINAL event (so it routes like
-- live), so the hist marker — not e=="HISTORY" — is what stops re-capture.
fireCapture({ hist = true, e = "CHAT_MSG_SAY", k = "SAY", m = "replayed line",
              r = 1, g = 1, b = 1, s = false })
assert(#appendLiveCalls == 0,
    "(d) entry.hist (replayed history) must be skipped, got " .. #appendLiveCalls)
print("  ok  (d) e=HISTORY, e=BACKFILL, and entry.hist skipped")

-------------------------------------------------------------------------------
-- Case (e): secret entry (entry.s=true) → skipped
-------------------------------------------------------------------------------

suppressActive = true
resetCaptureCalls()
fireCapture({ e = "CHAT_MSG_GUILD", k = "GUILD", m = "secret text",
              r = 1, g = 1, b = 1, s = true })
assert(#appendLiveCalls == 0,
    "(e) secret entry should be skipped, got " .. #appendLiveCalls)
print("  ok  (e) secret entry skipped")

-------------------------------------------------------------------------------
-- Case (f): repump + enabled → store gets sep+lines+sep, frames get NO AddMessage
-------------------------------------------------------------------------------

storageFxEntries = {
    { f = 1, m = "line one", r = 1, g = 0.5, b = 0.5,
      c = "GUILD", ev = "CHAT_MSG_GUILD" },
    { f = 1, m = "line two", r = 0.5, g = 1, b = 0.5,
      c = "CHANNEL2", ch = "Trade", ev = "CHAT_MSG_CHANNEL" },
}
resetRepumpCalls()

History._Repump()

-- Separators + 2 lines = 4 store entries
assert(#storeAppendCalls == 4,
    "(f) expected 4 store entries (sep+2+sep), got " .. #storeAppendCalls)

local sepBefore = storeAppendCalls[1]
local line1     = storeAppendCalls[2]
local line2     = storeAppendCalls[3]
local sepAfter  = storeAppendCalls[4]

-- Separators stay synthetic SYSTEM markers; every replayed append is flagged
-- hist so capture and sounds skip it.
assert(sepBefore.e == "HISTORY",  "(f) separator e should be HISTORY")
assert(sepBefore.k == "SYSTEM",   "(f) separator k should be SYSTEM")
assert(sepBefore.hist == true,    "(f) separator must carry the hist marker")
assert(sepAfter.e == "HISTORY",   "(f) trailing sep e should be HISTORY")
assert(sepAfter.k == "SYSTEM",    "(f) trailing sep k should be SYSTEM")
assert(sepAfter.hist == true,     "(f) trailing sep must carry the hist marker")

-- Replayed lines preserve their ORIGINAL routing fields so per-window tab
-- filters route them exactly like live traffic (the bug was flattening every
-- line to k=SYSTEM, which dumped all history into every window).
assert(line1.m == "line one",      "(f) line1 m mismatch")
assert(line1.k == "GUILD",         "(f) line1 k must preserve the type key, got " .. tostring(line1.k))
assert(line1.e == "CHAT_MSG_GUILD","(f) line1 e must preserve the source event, got " .. tostring(line1.e))
assert(line1.hist == true,         "(f) line1 must carry the hist marker")
assert(line1.k ~= "SYSTEM",        "(f) line1 must NOT be flattened to SYSTEM")
assert(line2.m == "line two",      "(f) line2 m mismatch")
assert(line2.k == "CHANNEL2",      "(f) line2 k must preserve the channel type key, got " .. tostring(line2.k))
assert(line2.ch == "Trade",        "(f) line2 ch must preserve the channel name, got " .. tostring(line2.ch))
assert(line2.hist == true,         "(f) line2 must carry the hist marker")

-- No AddMessage calls to any frame
assert(#addMsgCalls == 0,
    "(f) suppressed: NO frame AddMessage expected, got " .. #addMsgCalls)

print("  ok  (f) repump -> store sep+routed-lines+sep, no frame AddMessage")

-------------------------------------------------------------------------------
-- Case (g): repump NEVER sends AddMessage to frames — the Blizzard AddMessage
--           path is deleted; all repump output goes to the store only.
-------------------------------------------------------------------------------

storageFxEntries = {
    { f = 1, m = "line X", r = 1, g = 1, b = 1 },
    { f = 1, m = "line Y", r = 1, g = 1, b = 1 },
}
resetRepumpCalls()

History._Repump()

-- Store still receives sep + lines + sep
assert(#storeAppendCalls == 4,
    "(g) expected 4 store entries (sep+2+sep), got " .. #storeAppendCalls)

-- Frames receive ZERO AddMessage calls (the byFrame/AddMessage else-path is gone)
assert(#addMsgCalls == 0,
    "(g) repump must never call frame AddMessage, got " .. #addMsgCalls)

print("  ok  (g) repump never AddMessages frames; store receives sep+lines+sep")

-------------------------------------------------------------------------------
-- Also verify _repumping is false after repump completes (flag reset)
-------------------------------------------------------------------------------
assert(History._repumping == false, "repumping flag must be false after repump")
print("  ok  _repumping flag cleared after repump")

print("OK: chat_history_store_path_test")
