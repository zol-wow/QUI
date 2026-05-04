-- Headless tests for modules/chat/history_storage.lua codec and storage.
-- Run from repo root:  lua tests/test_chat_history_storage.lua

local env = dofile("tools/_addon_env.lua")
env.LoadLibs()

-- Load the storage module standalone. It needs ns + LibStub globals.
local ns = { QUI = { Chat = {} } }
local function loadStorage()
    -- Simulate the (ADDON_NAME, ns) varargs the file expects via dofile env.
    local chunk = assert(loadfile("modules/chat/history_storage.lua"))
    -- Lua 5.1: setfenv to inject our ns; vararg chunk receives our table.
    -- Use a helper that re-calls with explicit varargs.
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

-- ---- Codec round-trip ----
do
    local entries = {
        { t = 1700000000, f = 1, m = "hello world",         r = 1.0, g = 1.0, b = 1.0, c = "SAY" },
        { t = 1700000001, f = 1, m = "[TestPlayer]: yo",    r = 0.4, g = 0.8, b = 1.0, c = "WHISPER" },
        { t = 1700000002, f = 3, m = "guild chatter here",  r = 0.4, g = 1.0, b = 0.4, c = "GUILD" },
    }
    local encoded = Storage._Encode(entries)
    check("encode returns string", type(encoded) == "string" and #encoded > 0, tostring(encoded))

    local decoded = Storage._Decode(encoded)
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

-- ---- Empty array round-trip ----
do
    local encoded = Storage._Encode({})
    local decoded = Storage._Decode(encoded)
    check("empty round-trip", type(decoded) == "table" and #decoded == 0)
end

-- ---- Decode of nil/garbage returns empty array ----
do
    check("decode nil → empty", #Storage._Decode(nil) == 0)
    check("decode garbage → empty", #Storage._Decode("not-a-real-encoded-string") == 0)
end

-- ---- Snapshot merges persisted + live ----
do
    -- Reset the SV slot. Storage uses _G.QUI_ChatHistory.
    _G.QUI_ChatHistory = nil

    Storage.Init()

    Storage.AppendLive({ t = 100, f = 1, m = "live A", r = 1, g = 1, b = 1, c = "SAY" })
    Storage.AppendLive({ t = 101, f = 1, m = "live B", r = 1, g = 1, b = 1, c = "SAY" })

    local snap = Storage.Snapshot()
    check("snapshot returns live-only when no persisted",
          #snap == 2 and snap[1].m == "live A" and snap[2].m == "live B")

    -- Pretend a flush happened by encoding directly into the SV slot.
    _G.QUI_ChatHistory.encoded = Storage._Encode({
        { t = 50, f = 1, m = "old A", r = 1, g = 1, b = 1, c = "SAY" },
    })
    _G.QUI_ChatHistory.count = 1

    -- live buffer still has 2 entries from above
    local snap2 = Storage.Snapshot()
    check("snapshot merges persisted then live",
          #snap2 == 3 and snap2[1].m == "old A" and snap2[3].m == "live B",
          ("got %d entries: %s"):format(#snap2, snap2[1] and snap2[1].m or "nil"))
end

-- ---- Flush replaces persisted and clears live ----
do
    _G.QUI_ChatHistory = nil
    Storage.Init()

    Storage.AppendLive({ t = 1, f = 1, m = "x", r = 1, g = 1, b = 1, c = "SAY" })
    Storage.AppendLive({ t = 2, f = 1, m = "y", r = 1, g = 1, b = 1, c = "SAY" })

    Storage.Flush({
        { t = 1, f = 1, m = "x", r = 1, g = 1, b = 1, c = "SAY" },
        -- (y was pruned by the caller before passing in)
    })

    check("flush sets count", _G.QUI_ChatHistory.count == 1)
    check("flush wrote encoded", type(_G.QUI_ChatHistory.encoded) == "string"
                              and #_G.QUI_ChatHistory.encoded > 0)
    -- After flush, live should be empty. Snapshot should equal the pruned
    -- array we passed to Flush.
    local snap = Storage.Snapshot()
    check("flush clears live buffer", #snap == 1 and snap[1].m == "x",
          ("got %d entries"):format(#snap))
end

-- ---- Clear wipes everything ----
do
    _G.QUI_ChatHistory = nil
    Storage.Init()
    Storage.AppendLive({ t = 1, f = 1, m = "x", r = 1, g = 1, b = 1, c = "SAY" })
    Storage.Flush({ { t = 1, f = 1, m = "x", r = 1, g = 1, b = 1, c = "SAY" } })

    Storage.Clear()
    check("Clear empties live + persisted", #Storage.Snapshot() == 0)
    check("Clear zeros count", Storage.GetCount() == 0)
end

-- ---- GetCount reads metadata without decoding ----
do
    _G.QUI_ChatHistory = nil
    Storage.Init()
    Storage.Flush({
        { t = 1, f = 1, m = "a", r = 1, g = 1, b = 1, c = "SAY" },
        { t = 2, f = 1, m = "b", r = 1, g = 1, b = 1, c = "SAY" },
        { t = 3, f = 1, m = "c", r = 1, g = 1, b = 1, c = "SAY" },
    })
    check("GetCount = 3 after flush", Storage.GetCount() == 3)
end

-- ---- Migration from AceDB slot ----
do
    _G.QUI_ChatHistory = nil

    -- Simulate old AceDB-side state. The storage module reads
    -- _G.QUIDB.char[charKey].chat.history.entries.
    _G.QUIDB = {
        char = {
            ["TestChar - TestRealm"] = {
                chat = {
                    history = {
                        schemaVersion = 1,
                        entries = {
                            { t = 1, f = 1, m = "old1", r = 1, g = 1, b = 1, c = "SAY" },
                            { t = 2, f = 1, m = "old2", r = 1, g = 1, b = 1, c = "SAY" },
                        },
                    },
                },
            },
            ["OtherChar - TestRealm"] = {
                chat = {
                    history = {
                        schemaVersion = 1,
                        entries = {
                            { t = 9, f = 1, m = "other-char", r = 1, g = 1, b = 1, c = "SAY" },
                        },
                    },
                },
            },
        },
    }

    -- Stub a minimal QUI.db.keys.char so MigrateFromAceDB can resolve "self".
    _G.QUI = _G.QUI or {}
    _G.QUI.db = { keys = { char = "TestChar - TestRealm" } }

    Storage.MigrateFromAceDB()

    check("migration encoded old entries",
          type(_G.QUI_ChatHistory.encoded) == "string" and #_G.QUI_ChatHistory.encoded > 0)
    check("migration set _migrated flag", _G.QUI_ChatHistory._migrated == true)
    check("migration set count", _G.QUI_ChatHistory.count == 2)

    local snap = Storage.Snapshot()
    check("migrated entries are recoverable",
          #snap == 2 and snap[1].m == "old1" and snap[2].m == "old2")

    -- Self slot wiped to free memory:
    local self = _G.QUIDB.char["TestChar - TestRealm"].chat.history
    check("self entries nil-ed after migration",
          self.entries == nil or #self.entries == 0,
          tostring(self.entries))

    -- Other char untouched:
    local other = _G.QUIDB.char["OtherChar - TestRealm"].chat.history
    check("other char entries preserved",
          other.entries and #other.entries == 1)
end

-- ---- Migration is idempotent ----
do
    -- Don't reset SV. Run again. Should be a no-op.
    local before = _G.QUI_ChatHistory.encoded
    Storage.MigrateFromAceDB()
    check("idempotent: encoded unchanged",
          _G.QUI_ChatHistory.encoded == before)
end

-- ---- ClearAllCharacters wipes legacy + new ----
do
    -- new SV has migrated entries, plus a fresh other-char legacy slot
    Storage.ClearAllCharacters()

    check("ClearAll wiped new SV", #Storage.Snapshot() == 0)
    check("ClearAll wiped this char's encoded blob", _G.QUI_ChatHistory.count == 0)

    local other = _G.QUIDB.char["OtherChar - TestRealm"].chat.history
    check("ClearAll wiped legacy other-char entries",
          other.entries == nil or #other.entries == 0)
end

print(("\n%d failure(s)"):format(failures))
os.exit(failures == 0 and 0 or 1)
