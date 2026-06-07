---------------------------------------------------------------------------
-- QUI Chat Module - Persistent History Storage
-- Owns the per-character SV file (QUI_ChatHistory), one-time migration from
-- older layouts, and bounded access to recent persisted messages.
--
-- SV schema (QUI_ChatHistory), v2:
--   schemaVersion : 2
--   current       : plain array of newest entries. This is the write path.
--   chunks        : older fixed-size serialized arrays with metadata.
--   count         : total entries across chunks + current.
--
-- Normal reloads no longer compress or decompress the whole history. Appends
-- touch only `current`; old entries are rotated into serialized chunks in
-- small batches. Consumers ask for recent entries, so login replay and copy
-- decode only the newest chunks needed for the requested limit.
---------------------------------------------------------------------------

local ADDON_NAME, ns = ...

ns.QUI = ns.QUI or {}
ns.QUI.Chat = ns.QUI.Chat or {}
ns.QUI.Chat.HistoryStorage = ns.QUI.Chat.HistoryStorage or {}
local Storage = ns.QUI.Chat.HistoryStorage

local AceSerializer = LibStub and LibStub("AceSerializer-3.0", true)
local LibDeflate    = LibStub and LibStub("LibDeflate", true)

local SCHEMA_VERSION = 2
local CHUNK_SIZE = 500
local HOT_KEEP = 500
local HOT_ROTATE_AT = 1000
local DEFAULT_MAX_ENTRIES = 5000

local chunkCache = setmetatable({}, { __mode = "k" })

-- ---------------------------------------------------------------------------
-- Codec
-- ---------------------------------------------------------------------------

local function encodeChunk(entries)
    if type(entries) ~= "table" or #entries == 0 then return "", "none" end

    if C_EncodingUtil and C_EncodingUtil.SerializeJSON then
        local ok, data = pcall(C_EncodingUtil.SerializeJSON, entries)
        if ok and type(data) == "string" then
            return data, "json"
        end
    end

    if AceSerializer then
        return AceSerializer:Serialize(entries), "ace"
    end

    return nil, nil
end

local function decodeChunkData(data, codec)
    if type(data) == "table" then return data end
    if type(data) ~= "string" or data == "" then return {} end

    if codec == "json" and C_EncodingUtil and C_EncodingUtil.DeserializeJSON then
        local ok, payload = pcall(C_EncodingUtil.DeserializeJSON, data)
        if ok and type(payload) == "table" then return payload end
    end

    if (codec == "ace" or codec == nil) and AceSerializer then
        local ok, payload = AceSerializer:Deserialize(data)
        if ok and type(payload) == "table" then return payload end
    end

    return {}
end

local function encodeLegacyCompressed(entries)
    if not AceSerializer or not LibDeflate then return "" end
    if type(entries) ~= "table" or #entries == 0 then return "" end
    local serialized = AceSerializer:Serialize(entries)
    local compressed = LibDeflate:CompressDeflate(serialized, { level = 5 })
    return LibDeflate:EncodeForPrint(compressed)
end

local function decodeLegacyCompressed(encoded)
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

Storage._Encode = encodeChunk
Storage._Decode = decodeChunkData
Storage._EncodeLegacy = encodeLegacyCompressed
Storage._DecodeLegacy = decodeLegacyCompressed

-- ---------------------------------------------------------------------------
-- SV helpers
-- ---------------------------------------------------------------------------

local function resetV2(sv)
    for key in pairs(sv) do
        sv[key] = nil
    end
    sv.schemaVersion = SCHEMA_VERSION
    sv.current = {}
    sv.chunks = {}
    sv.count = 0
    sv.totalCount = 0
end

local function refreshCount(sv)
    local total = type(sv.current) == "table" and #sv.current or 0
    if type(sv.chunks) == "table" then
        for _, chunk in ipairs(sv.chunks) do
            total = total + (tonumber(chunk.count) or 0)
        end
    end
    sv.count = total
    sv.totalCount = total
    return total
end

local function makeChunk(entries)
    if type(entries) ~= "table" or #entries == 0 then return nil end
    local data, codec = encodeChunk(entries)
    if not data then return nil end
    return {
        first = entries[1] and entries[1].t or 0,
        last = entries[#entries] and entries[#entries].t or 0,
        count = #entries,
        data = data,
        codec = codec,
    }
end

Storage._MakeChunk = makeChunk

local function appendChunkOrCurrent(sv, entries)
    local chunk = makeChunk(entries)
    if chunk then
        sv.chunks[#sv.chunks + 1] = chunk
    else
        local current = sv.current
        for i = 1, #entries do
            current[#current + 1] = entries[i]
        end
    end
end

local function rebuildFromEntries(sv, entries, maxEntries)
    resetV2(sv)
    if type(entries) ~= "table" or #entries == 0 then return end

    local cap = tonumber(maxEntries) or DEFAULT_MAX_ENTRIES
    local firstIndex = math.max(1, #entries - cap + 1)
    local trimmedCount = #entries - firstIndex + 1
    local splitCount = math.max(0, trimmedCount - HOT_KEEP)
    local cursor = firstIndex

    while splitCount > 0 do
        local batch = {}
        local take = math.min(CHUNK_SIZE, splitCount)
        for i = 1, take do
            batch[i] = entries[cursor]
            cursor = cursor + 1
        end
        appendChunkOrCurrent(sv, batch)
        splitCount = splitCount - take
    end

    while cursor <= #entries do
        sv.current[#sv.current + 1] = entries[cursor]
        cursor = cursor + 1
    end

    refreshCount(sv)
end

local function sameEntry(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    return a.t == b.t and a.f == b.f and a.m == b.m
        and a.r == b.r and a.g == b.g and a.b == b.b and a.c == b.c
end

local function sameEntries(a, b)
    if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then return false end
    for i = 1, #a do
        if not sameEntry(a[i], b[i]) then return false end
    end
    return true
end

local function migrateSV(sv)
    if sv.schemaVersion == SCHEMA_VERSION then
        if type(sv.current) ~= "table" then sv.current = {} end
        if type(sv.chunks) ~= "table" then sv.chunks = {} end
        sv.encoded = nil
        sv.entries = nil
        refreshCount(sv)
        return
    end

    local migratedFlag = sv._migrated
    local entries = decodeLegacyCompressed(sv.encoded)
    local fallback = type(sv.entries) == "table" and sv.entries or nil

    if fallback and #fallback > 0 then
        if #entries == 0 then
            entries = fallback
        elseif not sameEntries(entries, fallback) then
            local base = #entries
            for i = 1, #fallback do
                entries[base + i] = fallback[i]
            end
        end
    end

    rebuildFromEntries(sv, entries)
    sv._migrated = migratedFlag
end

local function getSV()
    if type(_G.QUI_ChatHistory) ~= "table" then
        _G.QUI_ChatHistory = {
            schemaVersion = SCHEMA_VERSION,
            current = {},
            chunks = {},
            count = 0,
            totalCount = 0,
        }
    end

    local sv = _G.QUI_ChatHistory
    migrateSV(sv)
    return sv
end

local function decodeChunk(chunk)
    if type(chunk) ~= "table" then return {} end
    local cached = chunkCache[chunk]
    if cached then return cached end
    local entries = decodeChunkData(chunk.data, chunk.codec)
    chunkCache[chunk] = entries
    return entries
end

local function rotateCurrent(sv, force)
    local current = sv.current
    if type(current) ~= "table" or #current == 0 then return end
    if not force and #current < HOT_ROTATE_AT then return end

    local moveCount = #current - HOT_KEEP
    if moveCount <= 0 then return end

    local cursor = 1
    while cursor <= moveCount do
        local batch = {}
        local last = math.min(moveCount, cursor + CHUNK_SIZE - 1)
        for i = cursor, last do
            batch[#batch + 1] = current[i]
        end
        appendChunkOrCurrent(sv, batch)
        cursor = last + 1
    end

    local keep = #current - moveCount
    for i = 1, keep do
        current[i] = current[i + moveCount]
    end
    for i = keep + 1, #current do
        current[i] = nil
    end
end

local function selfKey()
    local q = _G.QUI
    if not q or not q.db or not q.db.keys then return nil end
    return q.db.keys.char
end

-- Deferred-clear token. SVPC files for other characters cannot be touched from
-- the running addon; instead, ClearAllCharacters stamps a token in account-wide
-- QUIDB.global, and each character honors it once on its next login by wiping
-- its own SVPC and recording the token it honored.
local CLEAR_TOKEN_KEY = "chatHistoryClearAllToken"

local function getGlobalClearToken()
    local quiDB = _G.QUIDB
    if type(quiDB) ~= "table" then return nil end
    if type(quiDB.global) ~= "table" then return nil end
    return tonumber(quiDB.global[CLEAR_TOKEN_KEY])
end

local function setGlobalClearToken(token)
    _G.QUIDB = _G.QUIDB or {}
    if type(_G.QUIDB.global) ~= "table" then _G.QUIDB.global = {} end
    _G.QUIDB.global[CLEAR_TOKEN_KEY] = token
end

local function newClearToken()
    local prev = tonumber(getGlobalClearToken()) or 0
    local seconds = 0
    if type(time) == "function" then
        seconds = tonumber(time()) or 0
    elseif type(os) == "table" and type(os.time) == "function" then
        seconds = tonumber(os.time()) or 0
    end
    if seconds > prev then return seconds end
    return prev + 1
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function Storage.Init()
    getSV()
    Storage.MigrateFromAceDB()
    Storage.HonorPendingClearAll()
end

-- Honors any pending ClearAllCharacters token stamped by a sibling character.
-- Returns true if this character's history was wiped as a result.
function Storage.HonorPendingClearAll()
    local token = getGlobalClearToken()
    if not token then return false end
    local sv = getSV()
    if tonumber(sv._clearAllToken) == token then return false end
    resetV2(sv)
    sv._clearAllToken = token
    return true
end

function Storage.AppendLive(entry)
    if type(entry) ~= "table" then return end
    local sv = getSV()
    sv.current[#sv.current + 1] = entry
    sv.count = (tonumber(sv.count) or refreshCount(sv)) + 1
    sv.totalCount = sv.count
    rotateCurrent(sv, false)
    refreshCount(sv)
    if sv.count > DEFAULT_MAX_ENTRIES + HOT_ROTATE_AT then
        Storage.Cap(DEFAULT_MAX_ENTRIES)
    end
end

function Storage.Snapshot()
    local sv = getSV()
    local out = {}
    for _, chunk in ipairs(sv.chunks) do
        local decoded = decodeChunk(chunk)
        for i = 1, #decoded do
            out[#out + 1] = decoded[i]
        end
    end
    for i = 1, #sv.current do
        out[#out + 1] = sv.current[i]
    end
    return out
end

-- Compatibility for old callers. Mutating this return value does not change
-- storage; use Flush, RemoveFrame, or Prune for write operations.
function Storage.GetArray()
    return Storage.Snapshot()
end

function Storage.GetRecentEntries(limit, filterFunc)
    local sv = getSV()
    local cap = tonumber(limit)
    local collected = {}

    local function take(entry)
        if type(entry) ~= "table" then return false end
        if filterFunc and not filterFunc(entry) then return false end
        collected[#collected + 1] = entry
        return cap and #collected >= cap
    end

    for i = #sv.current, 1, -1 do
        if take(sv.current[i]) then break end
    end

    if not cap or #collected < cap then
        for chunkIndex = #sv.chunks, 1, -1 do
            local decoded = decodeChunk(sv.chunks[chunkIndex])
            for i = #decoded, 1, -1 do
                if take(decoded[i]) then break end
            end
            if cap and #collected >= cap then break end
        end
    end

    local out = {}
    for i = #collected, 1, -1 do
        out[#out + 1] = collected[i]
    end
    return out
end

function Storage.GetRecentForFrame(frameID, limit)
    frameID = tonumber(frameID)
    if not frameID then return {} end
    return Storage.GetRecentEntries(limit, function(entry)
        return entry.f == frameID
    end)
end

function Storage.Flush(pruned)
    rebuildFromEntries(getSV(), pruned)
end

function Storage.PersistNow()
    local sv = getSV()
    rotateCurrent(sv, true)
    sv.entries = nil
    sv.encoded = nil
    refreshCount(sv)
end

function Storage.Clear()
    resetV2(getSV())
end

function Storage.MigrateFromAceDB()
    local sv = getSV()
    if sv._migrated then return end

    local key = selfKey()
    if not key then return end

    local quiDB = _G.QUIDB
    if type(quiDB) ~= "table" then
        sv._migrated = true
        return
    end

    local charDB = type(quiDB.char) == "table" and quiDB.char[key] or nil
    local oldHist = type(charDB) == "table" and type(charDB.chat) == "table"
                    and charDB.chat.history or nil
    local oldEntries = type(oldHist) == "table" and oldHist.entries or nil

    if type(oldEntries) == "table" and #oldEntries > 0 then
        if refreshCount(sv) == 0 then
            rebuildFromEntries(sv, oldEntries)
        else
            local entries = Storage.Snapshot()
            local base = #entries
            for i = 1, #oldEntries do
                entries[base + i] = oldEntries[i]
            end
            rebuildFromEntries(sv, entries)
        end
        oldHist.entries = nil
        oldHist._sizeWarned = nil
    end

    sv._migrated = true
end

local function maxRetentionDays(settings)
    local days = tonumber(settings and settings.retentionDays) or 7
    local perChannel = settings and settings.perChannelRetention
    if type(perChannel) == "table" then
        for _, value in pairs(perChannel) do
            local channelDays = tonumber(value)
            if channelDays and channelDays > days then
                days = channelDays
            end
        end
    end
    return days
end

local function keepByRetention(entry, settings, now)
    if type(entry) ~= "table" or not entry.t then return false end
    local days = tonumber(settings and settings.retentionDays) or 7
    local perChannel = settings and settings.perChannelRetention
    if entry.c and type(perChannel) == "table" and tonumber(perChannel[entry.c]) then
        days = tonumber(perChannel[entry.c])
    end
    return entry.t >= now - days * 86400
end

function Storage.Cap(maxEntries)
    local sv = getSV()
    local cap = math.max(0, tonumber(maxEntries) or DEFAULT_MAX_ENTRIES)
    local total = refreshCount(sv)

    while total > cap and #sv.chunks > 0 do
        local chunk = sv.chunks[1]
        local chunkCount = tonumber(chunk.count) or 0
        local extra = total - cap

        if chunkCount <= extra then
            table.remove(sv.chunks, 1)
            chunkCache[chunk] = nil
            total = total - chunkCount
        else
            local decoded = decodeChunk(chunk)
            local kept = {}
            for i = extra + 1, #decoded do
                kept[#kept + 1] = decoded[i]
            end
            local replacement = makeChunk(kept)
            if replacement then
                sv.chunks[1] = replacement
            else
                table.remove(sv.chunks, 1)
                for i = #kept, 1, -1 do
                    table.insert(sv.current, 1, kept[i])
                end
            end
            total = cap
        end
    end

    if total > cap and #sv.current > cap then
        local extra = #sv.current - cap
        local keep = #sv.current - extra
        for i = 1, keep do
            sv.current[i] = sv.current[i + extra]
        end
        for i = keep + 1, #sv.current do
            sv.current[i] = nil
        end
    end

    refreshCount(sv)
end

function Storage.Prune(settings)
    local sv = getSV()
    local now = (GetServerTime and GetServerTime()) or time()
    local oldestAllowed = now - maxRetentionDays(settings) * 86400

    local write = 0
    for i = 1, #sv.current do
        local entry = sv.current[i]
        if keepByRetention(entry, settings, now) then
            write = write + 1
            sv.current[write] = entry
        end
    end
    for i = #sv.current, write + 1, -1 do
        sv.current[i] = nil
    end

    write = 0
    for i = 1, #sv.chunks do
        local chunk = sv.chunks[i]
        if (tonumber(chunk.last) or 0) >= oldestAllowed then
            write = write + 1
            sv.chunks[write] = chunk
        else
            chunkCache[chunk] = nil
        end
    end
    for i = #sv.chunks, write + 1, -1 do
        sv.chunks[i] = nil
    end

    Storage.Cap(settings and settings.maxEntries or DEFAULT_MAX_ENTRIES)
    rotateCurrent(sv, true)
    refreshCount(sv)
end

function Storage.RemoveFrame(frameID)
    frameID = tonumber(frameID)
    if not frameID then return end

    local sv = getSV()

    local write = 0
    for i = 1, #sv.current do
        local entry = sv.current[i]
        if entry.f ~= frameID then
            write = write + 1
            sv.current[write] = entry
        end
    end
    for i = #sv.current, write + 1, -1 do
        sv.current[i] = nil
    end

    write = 0
    for i = 1, #sv.chunks do
        local chunk = sv.chunks[i]
        local decoded = decodeChunk(chunk)
        local kept = {}
        for j = 1, #decoded do
            if decoded[j].f ~= frameID then
                kept[#kept + 1] = decoded[j]
            end
        end
        if #kept > 0 then
            local replacement = #kept == #decoded and chunk or makeChunk(kept)
            if replacement then
                write = write + 1
                sv.chunks[write] = replacement
            end
        end
        if #kept ~= #decoded then
            chunkCache[chunk] = nil
        end
    end
    for i = #sv.chunks, write + 1, -1 do
        sv.chunks[i] = nil
    end

    refreshCount(sv)
end

-- Clears the current character's SVPC history now and stamps an account-wide
-- token so other characters wipe their own SVPC the next time they log in.
-- Also wipes any leftover legacy AceDB-per-character history in QUIDB.char.
-- Returns (clearedCharactersNow, clearedEntriesNow, deferredToken).
function Storage.ClearAllCharacters()
    local clearedCharacters = 0
    local clearedEntries = 0

    local sv = getSV()
    clearedEntries = clearedEntries + refreshCount(sv)
    resetV2(sv)
    clearedCharacters = clearedCharacters + 1

    local token = newClearToken()
    setGlobalClearToken(token)
    sv._clearAllToken = token

    local quiDB = _G.QUIDB
    if type(quiDB) == "table" and type(quiDB.char) == "table" then
        for _, charData in pairs(quiDB.char) do
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

    return clearedCharacters, clearedEntries, token
end

function Storage.GetCount()
    return refreshCount(getSV())
end

function Storage.GetEncodedSize()
    local sv = getSV()
    local size = 0
    for _, chunk in ipairs(sv.chunks) do
        if type(chunk.data) == "string" then
            size = size + #chunk.data
        end
    end
    return size
end

function Storage.GetChunkCount()
    local sv = getSV()
    return #sv.chunks
end
