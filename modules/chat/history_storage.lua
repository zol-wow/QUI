---------------------------------------------------------------------------
-- QUI Chat Module — Persistent History Storage
-- Owns the per-character SV file (QUI_ChatHistory), encode/decode,
-- live-session buffer, and one-time migration from the old AceDB slot
-- (QUIDB.char[*].chat.history.entries). history.lua composes these
-- primitives — it does not touch SV directly.
---------------------------------------------------------------------------

local ADDON_NAME, ns = ...

ns.QUI = ns.QUI or {}
ns.QUI.Chat = ns.QUI.Chat or {}
ns.QUI.Chat.HistoryStorage = ns.QUI.Chat.HistoryStorage or {}
local Storage = ns.QUI.Chat.HistoryStorage

local QUI = _G.QUI

local AceSerializer = LibStub and LibStub("AceSerializer-3.0", true)
local LibDeflate    = LibStub and LibStub("LibDeflate", true)

-- Live session buffer. Capture appends here; flush merges into persisted.
-- Cleared after every successful Flush.
local liveBuffer = {}

local SCHEMA_VERSION = 1

-- Encode an array of entries to a printable string. Returns "" for empty
-- input so the SV slot stores a deterministic empty value (avoids nil vs
-- "" round-trip ambiguity).
local function encode(entries)
    if not AceSerializer or not LibDeflate then return "" end
    if type(entries) ~= "table" or #entries == 0 then return "" end
    local serialized = AceSerializer:Serialize(entries)
    local compressed = LibDeflate:CompressDeflate(serialized, { level = 5 })
    return LibDeflate:EncodeForPrint(compressed)
end

-- Decode a printable string to an array of entries. Returns {} for any
-- failure (nil input, malformed string, deserialize error). Never errors.
local function decode(encoded)
    if not AceSerializer or not LibDeflate then return {} end
    if type(encoded) ~= "string" or encoded == "" then return {} end
    local compressed = LibDeflate:DecodeForPrint(encoded)
    if not compressed then return {} end
    local serialized = LibDeflate:DecompressDeflate(compressed)
    if not serialized then return {} end
    local ok, payload = AceSerializer:Deserialize(serialized)
    if not ok or type(payload) ~= "table" then return {} end
    return payload
end

Storage._Encode = encode
Storage._Decode = decode

-- Lazy-create the per-character SV slot. Returns the table or nil if
-- WoW hasn't loaded the SV yet (very early load order — caller no-ops).
local function getSV()
    if _G.QUI_ChatHistory == nil then
        _G.QUI_ChatHistory = { schemaVersion = SCHEMA_VERSION, encoded = "", count = 0 }
    end
    local sv = _G.QUI_ChatHistory
    if type(sv) ~= "table" then
        -- Corrupted slot — reset rather than error. User loses history;
        -- they were going to lose it anyway when SV refused to load.
        _G.QUI_ChatHistory = { schemaVersion = SCHEMA_VERSION, encoded = "", count = 0 }
        sv = _G.QUI_ChatHistory
    end
    sv.schemaVersion = sv.schemaVersion or SCHEMA_VERSION
    sv.encoded       = sv.encoded or ""
    sv.count         = sv.count or 0
    return sv
end

-- Resolve the current character's AceDB key. Returns nil before AceDB is
-- initialized; caller no-ops in that case and a later Init reattempts.
local function selfKey()
    local q = _G.QUI
    if not q or not q.db or not q.db.keys then return nil end
    return q.db.keys.char
end

function Storage.Init()
    getSV()  -- ensures SV slot is well-formed before first capture.
    Storage.MigrateFromAceDB()
end

function Storage.AppendLive(entry)
    if type(entry) ~= "table" then return end
    liveBuffer[#liveBuffer + 1] = entry
end

-- Decodes the persisted blob and concatenates the live buffer. Cost is
-- O(persisted-bytes + live-len). Returned array MUST NOT be mutated by
-- callers — Flush is the only mutation path.
function Storage.Snapshot()
    local sv = getSV()
    local persisted = decode(sv.encoded)
    if #liveBuffer == 0 then
        return persisted
    end
    local out = persisted
    local base = #out
    for i = 1, #liveBuffer do
        out[base + i] = liveBuffer[i]
    end
    return out
end

-- Replaces the persisted blob with `pruned` (caller-pruned + caller-capped),
-- and clears the live buffer. After flush, Snapshot() returns exactly
-- `pruned`.
function Storage.Flush(pruned)
    if type(pruned) ~= "table" then pruned = {} end
    local sv = getSV()
    sv.encoded = encode(pruned)
    sv.count   = #pruned
    -- Wipe live buffer in-place (preserves table identity for any future
    -- weak refs or upvalues).
    for i = #liveBuffer, 1, -1 do liveBuffer[i] = nil end
end

function Storage.Clear()
    local sv = getSV()
    sv.encoded = ""
    sv.count   = 0
    for i = #liveBuffer, 1, -1 do liveBuffer[i] = nil end
end

-- One-time migration. Idempotent via the _migrated sentinel on the new SV.
-- Reads QUIDB.char[selfKey].chat.history.entries, encodes into the new
-- per-character SV, and nils the old slot to free Lua heap. Other characters'
-- entries are left untouched — they migrate themselves on next login.
function Storage.MigrateFromAceDB()
    local sv = getSV()
    if sv._migrated then return end

    local key = selfKey()
    if not key then return end  -- AceDB not ready yet; retry later.

    local quiDB = _G.QUIDB
    if type(quiDB) ~= "table" then
        sv._migrated = true  -- Nothing to migrate; mark done so we skip future attempts.
        return
    end
    local charDB = type(quiDB.char) == "table" and quiDB.char[key] or nil
    local oldHist = type(charDB) == "table" and type(charDB.chat) == "table"
                    and charDB.chat.history or nil
    local oldEntries = type(oldHist) == "table" and oldHist.entries or nil

    if type(oldEntries) == "table" and #oldEntries > 0 then
        sv.encoded = encode(oldEntries)
        sv.count   = #oldEntries
        oldHist.entries = nil  -- free the Lua heap held by the old array.
        oldHist._sizeWarned = nil
    end

    sv._migrated = true
end

-- Wipe the new SV (this character's blob + live buffer) AND walk QUIDB.char[*]
-- to wipe any leftover legacy entries from characters that haven't logged in
-- under the new system yet. Returns (charactersTouched, entriesCleared).
function Storage.ClearAllCharacters()
    local clearedCharacters = 0
    local clearedEntries = 0

    -- New SV (this character only — other chars own their own files).
    local sv = getSV()
    clearedEntries = clearedEntries + (sv.count or 0)
    sv.encoded = ""
    sv.count   = 0
    for i = #liveBuffer, 1, -1 do liveBuffer[i] = nil end
    clearedCharacters = clearedCharacters + 1

    -- Legacy AceDB slot — walk every character's leftover history.entries.
    local quiDB = _G.QUIDB
    if type(quiDB) == "table" and type(quiDB.char) == "table" then
        for charKey, charData in pairs(quiDB.char) do
            if type(charData) == "table" and type(charData.chat) == "table" then
                local hist = charData.chat.history
                if type(hist) == "table" and type(hist.entries) == "table" then
                    clearedEntries = clearedEntries + #hist.entries
                    hist.entries = nil
                    hist._sizeWarned = nil
                    clearedCharacters = clearedCharacters + 1
                end
            end
        end
    end

    return clearedCharacters, clearedEntries
end

function Storage.GetCount()
    local sv = getSV()
    return (sv.count or 0) + #liveBuffer
end

function Storage.GetEncodedSize()
    local sv = getSV()
    return type(sv.encoded) == "string" and #sv.encoded or 0
end
