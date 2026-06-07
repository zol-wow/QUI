-- Headless tests for QUI_Chat/chat/history_storage.lua.
-- Run from repo root: lua tests/unit/test_chat_history_storage.lua

local env = dofile("tools/_addon_env.lua")
env.LoadLibs()

local ns = { QUI = { Chat = {} } }
local function loadStorage()
    local chunk = assert(loadfile("QUI_Chat/chat/history_storage.lua"))
    local function runner(...) return chunk(...) end
    runner("QUI", ns)
    return ns.QUI.Chat.HistoryStorage
end

local Storage = loadStorage()

local failures = 0
local function check(name, ok, detail)
    if ok then
        print(("  ok  %s"):format(name))
    else
        failures = failures + 1
        print(("FAIL  %s  %s"):format(name, detail or ""))
    end
end

local function reset()
    _G.QUI_ChatHistory = nil
    _G.QUIDB = nil
    _G.QUI = nil
    Storage.Init()
end

local function entry(t, frame, text, channel)
    return { t = t, f = frame or 1, m = text, r = 1, g = 1, b = 1, c = channel or "SAY" }
end

-- Codec round-trip.
do
    local entries = {
        entry(1700000000, 1, "hello world", "SAY"),
        entry(1700000001, 1, "[TestPlayer]: yo", "WHISPER"),
        entry(1700000002, 3, "guild chatter here", "GUILD"),
    }
    local encoded, codec = Storage._Encode(entries)
    check("encode returns string", type(encoded) == "string" and #encoded > 0, tostring(encoded))
    check("encode returns codec", type(codec) == "string" and codec ~= "")

    local decoded = Storage._Decode(encoded, codec)
    check("decode returns table", type(decoded) == "table")
    check("decode length matches", #decoded == 3, tostring(#decoded))

    for i = 1, 3 do
        local a, b = entries[i], decoded[i]
        check(("decode entry %d preserves m"):format(i), a.m == b.m, b.m)
        check(("decode entry %d preserves t"):format(i), a.t == b.t, tostring(b.t))
        check(("decode entry %d preserves f"):format(i), a.f == b.f, tostring(b.f))
        check(("decode entry %d preserves c"):format(i), a.c == b.c, tostring(b.c))
    end
end

-- Empty and garbage decode safely.
do
    local encoded, codec = Storage._Encode({})
    check("empty round-trip", #Storage._Decode(encoded, codec) == 0)
    check("decode nil empty", #Storage._Decode(nil) == 0)
    check("decode garbage empty", #Storage._Decode("not-a-real-encoded-string", "ace") == 0)
end

-- Appends stay in the plain current buffer until rotation.
do
    reset()
    Storage.AppendLive(entry(100, 1, "live A"))
    Storage.AppendLive(entry(101, 1, "live B"))

    local snap = Storage.Snapshot()
    check("snapshot returns current entries",
          #snap == 2 and snap[1].m == "live A" and snap[2].m == "live B")
    check("current buffer used before rotation",
          #_G.QUI_ChatHistory.current == 2 and #_G.QUI_ChatHistory.chunks == 0)
end

-- Snapshot merges serialized chunks before current.
do
    local chunk = assert(Storage._MakeChunk({
        entry(50, 1, "old A"),
        entry(51, 2, "old B"),
    }))
    _G.QUI_ChatHistory = {
        schemaVersion = 2,
        chunks = { chunk },
        current = { entry(100, 1, "live A") },
        count = 3,
        totalCount = 3,
    }
    _G.QUIDB = nil
    _G.QUI = nil

    Storage.Init()

    local snap = Storage.Snapshot()
    check("snapshot merges chunks then current",
          #snap == 3 and snap[1].m == "old A" and snap[3].m == "live A",
          ("got %d entries"):format(#snap))
end

-- Legacy v1 compressed blob migrates to schema v2.
do
    local oldEntries = {
        entry(1, 1, "encoded"),
        entry(2, 1, "fallback A"),
    }
    _G.QUI_ChatHistory = {
        schemaVersion = 1,
        encoded = Storage._EncodeLegacy(oldEntries),
        count = #oldEntries,
        entries = oldEntries, -- same full-array fallback should not duplicate
    }
    _G.QUIDB = nil
    _G.QUI = nil

    Storage.Init()

    local snap = Storage.Snapshot()
    check("legacy migrated to v2", _G.QUI_ChatHistory.schemaVersion == 2)
    check("legacy fallback deduped",
          #snap == 2 and snap[1].m == "encoded" and snap[2].m == "fallback A",
          ("got %d entries"):format(#snap))
    check("legacy encoded cleared", _G.QUI_ChatHistory.encoded == nil)
end

-- Rotation creates chunks and recent frame reads do not need a full snapshot.
do
    reset()
    for i = 1, 1005 do
        Storage.AppendLive(entry(i, i % 2 == 0 and 1 or 3, "line " .. i))
    end

    check("rotation created chunks", Storage.GetChunkCount() > 0)
    check("count after rotation", Storage.GetCount() == 1005, tostring(Storage.GetCount()))

    local recent = Storage.GetRecentForFrame(1, 5)
    check("recent frame limit",
          #recent == 5 and recent[1].m == "line 996" and recent[5].m == "line 1004",
          recent[1] and recent[1].m or "nil")
end

-- PersistNow normalizes chunks without writing the old monolithic blob.
do
    reset()
    for i = 1, 650 do
        Storage.AppendLive(entry(i, 1, "persist " .. i))
    end
    Storage.PersistNow()

    check("PersistNow set count", _G.QUI_ChatHistory.count == 650)
    check("PersistNow does not write encoded", _G.QUI_ChatHistory.encoded == nil)
    check("PersistNow keeps bounded current", #_G.QUI_ChatHistory.current == 500)
    check("PersistNow created one chunk", #_G.QUI_ChatHistory.chunks == 1)
end

-- Flush replaces stored state.
do
    reset()
    Storage.AppendLive(entry(1, 1, "x"))
    Storage.AppendLive(entry(2, 1, "y"))

    Storage.Flush({ entry(1, 1, "x") })

    check("flush sets count", _G.QUI_ChatHistory.count == 1)
    local snap = Storage.Snapshot()
    check("flush replaces state", #snap == 1 and snap[1].m == "x",
          ("got %d entries"):format(#snap))
end

-- Clear wipes everything.
do
    reset()
    Storage.AppendLive(entry(1, 1, "x"))
    Storage.Clear()
    check("Clear empties stored state", #Storage.Snapshot() == 0)
    check("Clear zeros count", Storage.GetCount() == 0)
end

-- GetCount reads metadata.
do
    reset()
    Storage.Flush({
        entry(1, 1, "a"),
        entry(2, 1, "b"),
        entry(3, 1, "c"),
    })
    check("GetCount = 3 after flush", Storage.GetCount() == 3)
end

-- Migration from old AceDB slot imports this character only.
do
    _G.QUI_ChatHistory = nil
    _G.QUIDB = {
        char = {
            ["TestChar - TestRealm"] = {
                chat = {
                    history = {
                        schemaVersion = 1,
                        entries = {
                            entry(1, 1, "old1"),
                            entry(2, 1, "old2"),
                        },
                    },
                },
            },
            ["OtherChar - TestRealm"] = {
                chat = {
                    history = {
                        schemaVersion = 1,
                        entries = {
                            entry(9, 1, "other-char"),
                        },
                    },
                },
            },
        },
    }
    _G.QUI = { db = { keys = { char = "TestChar - TestRealm" } } }

    Storage.Init()

    check("migration set v2 schema", _G.QUI_ChatHistory.schemaVersion == 2)
    check("migration set flag", _G.QUI_ChatHistory._migrated == true)
    check("migration set count", _G.QUI_ChatHistory.count == 2)

    local snap = Storage.Snapshot()
    check("migrated entries recoverable",
          #snap == 2 and snap[1].m == "old1" and snap[2].m == "old2")

    local self = _G.QUIDB.char["TestChar - TestRealm"].chat.history
    check("self entries nil after migration",
          self.entries == nil or #self.entries == 0,
          tostring(self.entries))

    local other = _G.QUIDB.char["OtherChar - TestRealm"].chat.history
    check("other char untouched",
          other.entries and #other.entries == 1)
end

-- ClearAllCharacters wipes new current character SV and legacy slots.
do
    Storage.ClearAllCharacters()

    check("ClearAll wiped new SV", #Storage.Snapshot() == 0)
    check("ClearAll wiped this char count", _G.QUI_ChatHistory.count == 0)

    local other = _G.QUIDB.char["OtherChar - TestRealm"].chat.history
    check("ClearAll wiped legacy other-char entries",
          other.entries == nil or #other.entries == 0)
end

-- ClearAllCharacters stamps a global token so sibling SVPC files clear on
-- their next login. Simulate a second character logging in afterwards.
do
    reset()
    Storage.AppendLive(entry(1, 1, "char-A msg"))

    local _, _, token = Storage.ClearAllCharacters()
    check("ClearAll returns token", type(token) == "number" and token > 0,
          tostring(token))
    check("ClearAll stamped global token",
          _G.QUIDB and _G.QUIDB.global
              and _G.QUIDB.global.chatHistoryClearAllToken == token,
          tostring(_G.QUIDB and _G.QUIDB.global
              and _G.QUIDB.global.chatHistoryClearAllToken))
    check("ClearAll stamped self token",
          _G.QUI_ChatHistory._clearAllToken == token,
          tostring(_G.QUI_ChatHistory._clearAllToken))

    -- Switch to a different character: keep account-wide QUIDB, but swap the
    -- SVPC table for a fresh one with unrelated history and no token.
    local globalToken = _G.QUIDB.global.chatHistoryClearAllToken
    _G.QUI_ChatHistory = {
        schemaVersion = 2,
        chunks = {},
        current = { entry(50, 1, "char-B msg") },
        count = 1,
        totalCount = 1,
    }
    _G.QUI = nil

    Storage.Init()

    check("sibling char wiped on next login",
          #Storage.Snapshot() == 0 and _G.QUI_ChatHistory.count == 0,
          tostring(_G.QUI_ChatHistory.count))
    check("sibling char now stamped with token",
          _G.QUI_ChatHistory._clearAllToken == globalToken,
          tostring(_G.QUI_ChatHistory._clearAllToken))

    -- A second Init on the same character must be a no-op for live data.
    Storage.AppendLive(entry(60, 1, "char-B post-wipe"))
    Storage.Init()
    check("post-wipe appends survive subsequent Init",
          #Storage.Snapshot() == 1 and Storage.Snapshot()[1].m == "char-B post-wipe",
          tostring(#Storage.Snapshot()))
end

-- A new ClearAllCharacters call after the previous token was honored must
-- produce a strictly larger token (so siblings wipe again on next login).
do
    local prev = _G.QUIDB.global.chatHistoryClearAllToken
    local _, _, next = Storage.ClearAllCharacters()
    check("repeated ClearAll produces monotonic token",
          type(next) == "number" and next > prev,
          ("prev=%s next=%s"):format(tostring(prev), tostring(next)))
end

print(("\n%d failure(s)"):format(failures))
os.exit(failures == 0 and 0 or 1)
