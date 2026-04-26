--[[
  decode_profile.lua

  Decode and inspect QUI profile import strings produced by
  core/profile_io.lua. Useful for diagnosing profile import issues without
  loading the addon in WoW.

  Supports all three QUI string formats:
    QUI1: full profile (db.profile only)
    QCB1: single tracker bar export
    QCT1: all tracker bars export

  Usage:
    lua tools/decode_profile.lua <path-to-file-with-import-string>
    lua tools/decode_profile.lua -                         # read from stdin
    lua tools/decode_profile.lua <file> --full             # also write full dump

  The "full" mode writes a sibling <input>.dump.txt containing a depth-
  bounded pretty-print of the entire deserialized payload.

  Path-independent: the script resolves bundled libs relative to its own
  location, so it works whether run from the repo root or from tools/.
]]

local function ScriptDir()
    local p = (arg and arg[0]) or ""
    p = p:gsub("\\", "/")
    local dir = p:match("(.*/)")
    if dir == nil or dir == "" then return "./" end
    return dir
end

local libsRoot = ScriptDir() .. "../libs"

-- Stub the WoW global aliases the bundled libs reach for.
strmatch = string.match
strfind  = string.find
strsub   = string.sub
strlower = string.lower
strupper = string.upper
strrep   = string.rep
strtrim  = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
strjoin  = function(sep, ...)
    local n = select("#", ...)
    local out = {}
    for i = 1, n do out[i] = tostring(select(i, ...)) end
    return table.concat(out, sep)
end
tinsert  = table.insert
tremove  = table.remove
tconcat  = table.concat
wipe     = function(t) for k in pairs(t) do t[k] = nil end return t end
geterrorhandler = function() return print end

dofile(libsRoot .. "/LibStub/LibStub.lua")
dofile(libsRoot .. "/LibDeflate/LibDeflate.lua")
dofile(libsRoot .. "/AceSerializer-3.0.lua")

local LibDeflate    = LibStub("LibDeflate")
local AceSerializer = LibStub("AceSerializer-3.0")

----------------------------------------------------------------------------
-- I/O
----------------------------------------------------------------------------

local function ReadInput(path)
    if path == "-" then
        return io.read("*a")
    end
    local f, err = io.open(path, "rb")
    if not f then error("Could not open input: " .. tostring(err)) end
    local data = f:read("*a")
    f:close()
    return data
end

local function WriteFile(path, content)
    local f = assert(io.open(path, "w"))
    f:write(content)
    f:close()
end

----------------------------------------------------------------------------
-- Decode
----------------------------------------------------------------------------

local KNOWN_PREFIXES = { "QUI1:", "QCT1:", "QCB1:" }

local function StripWhitespace(s)
    return (s:gsub("%s+", ""))
end

local function DetectPrefix(s)
    for _, p in ipairs(KNOWN_PREFIXES) do
        if s:sub(1, #p) == p then
            return p, s:sub(#p + 1)
        end
    end
    return nil, s
end

local function Decode(rawString)
    rawString = StripWhitespace(rawString)
    local prefix, body = DetectPrefix(rawString)
    if not prefix then
        return nil, "Unknown prefix (expected QUI1:, QCT1:, or QCB1:)"
    end

    local compressed = LibDeflate:DecodeForPrint(body)
    if not compressed then return nil, "DecodeForPrint failed" end

    local serialized = LibDeflate:DecompressDeflate(compressed)
    if not serialized then return nil, "DecompressDeflate failed" end

    local ok, payload = AceSerializer:Deserialize(serialized)
    if not ok then return nil, "AceSerializer:Deserialize failed: " .. tostring(payload) end

    return {
        prefix       = prefix,
        encodedSize  = #body,
        compressedSize = #compressed,
        serializedSize = #serialized,
        payload      = payload,
    }
end

----------------------------------------------------------------------------
-- Pretty-print helpers
----------------------------------------------------------------------------

local function ReprScalar(v)
    local t = type(v)
    if t == "string" then return string.format("%q", v) end
    if t == "number" or t == "boolean" or t == "nil" then return tostring(v) end
    return "<" .. t .. ">"
end

local function CountKeys(t)
    if type(t) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function SortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta == tb then return tostring(a) < tostring(b) end
        return ta < tb
    end)
    return keys
end

local function DumpTree(t, indent, depth, maxDepth, out)
    indent = indent or ""
    depth = depth or 0
    maxDepth = maxDepth or 99
    out = out or {}

    if type(t) ~= "table" then
        out[#out + 1] = indent .. ReprScalar(t)
        return out
    end
    if depth >= maxDepth then
        out[#out + 1] = indent .. ("{<table %d keys, depth-truncated>}"):format(CountKeys(t))
        return out
    end

    out[#out + 1] = indent .. "{"
    for _, k in ipairs(SortedKeys(t)) do
        local v = t[k]
        local kr = (type(k) == "number") and ("[" .. k .. "]") or tostring(k)
        if type(v) == "table" then
            out[#out + 1] = indent .. "  " .. kr .. " ="
            DumpTree(v, indent .. "    ", depth + 1, maxDepth, out)
        else
            out[#out + 1] = indent .. "  " .. kr .. " = " .. ReprScalar(v)
        end
    end
    out[#out + 1] = indent .. "}"
    return out
end

----------------------------------------------------------------------------
-- Inspectors
----------------------------------------------------------------------------

local function PrintHeader(decoded)
    print(("Prefix:           %s"):format(decoded.prefix))
    print(("Encoded size:     %d bytes"):format(decoded.encodedSize))
    print(("Compressed size:  %d bytes"):format(decoded.compressedSize))
    print(("Serialized size:  %d bytes"):format(decoded.serializedSize))
end

local function PrintTopLevel(payload)
    print("\n========== TOP-LEVEL KEYS ==========")
    local lines = {}
    for k, v in pairs(payload) do
        lines[#lines + 1] = ("  %-32s  %s"):format(tostring(k), type(v))
    end
    table.sort(lines)
    for _, l in ipairs(lines) do print(l) end
end

local function PrintSchemaInfo(payload)
    print("\n========== SCHEMA / SPEC METADATA ==========")
    print(("  _schemaVersion         = %s"):format(ReprScalar(payload._schemaVersion)))
    print(("  _defaultsVersion       = %s"):format(ReprScalar(payload._defaultsVersion)))
    if payload.ncdm then
        print(("  ncdm._lastSpecID       = %s"):format(ReprScalar(payload.ncdm._lastSpecID)))
        print(("  ncdm._snapshotVersion  = %s"):format(ReprScalar(payload.ncdm._snapshotVersion)))
        print(("  ncdm.customEntriesSpecSpecific = %s")
            :format(ReprScalar(payload.ncdm.customEntriesSpecSpecific)))
    end
end

local function PrintBar(idxLabel, bar)
    print(("\n  --- %s ---"):format(idxLabel))
    for _, k in ipairs({
        "id", "name", "enabled", "specSpecificSpells",
        "_sourceSpecID", "_resolutionState",
        "iconSize", "spacing", "growDirection", "lockedToPlayer",
    }) do
        local v = bar[k]
        if v ~= nil then
            print(("    %-22s = %s"):format(k, ReprScalar(v)))
        end
    end
    if type(bar.entries) == "table" then
        print(("    entries (%d):"):format(#bar.entries))
        for ei, e in ipairs(bar.entries) do
            if type(e) == "table" then
                local kvs = {}
                for _, k in ipairs({ "type", "id", "name", "_sourceID", "_ambiguousResolved" }) do
                    if e[k] ~= nil then
                        kvs[#kvs + 1] = ("%s=%s"):format(k, ReprScalar(e[k]))
                    end
                end
                print(("      [%d] %s"):format(ei, table.concat(kvs, " ")))
            else
                print(("      [%d] %s"):format(ei, ReprScalar(e)))
            end
        end
    end
end

local function PrintCustomTrackers(payload)
    print("\n========== customTrackers.bars[] (legacy) ==========")
    if type(payload.customTrackers) ~= "table" or type(payload.customTrackers.bars) ~= "table" then
        print("  (absent — nothing to inspect)")
        return
    end
    print(("  bar count: %d"):format(#payload.customTrackers.bars))
    for i, bar in ipairs(payload.customTrackers.bars) do
        if type(bar) == "table" then
            PrintBar("bars[" .. i .. "]", bar)
        end
    end
end

local function PrintCustomBarContainers(payload)
    print("\n========== ncdm.containers[customBar_*] (V2 unified) ==========")
    local containers = payload.ncdm and payload.ncdm.containers
    if type(containers) ~= "table" then
        print("  (no ncdm.containers table)")
        return
    end
    local found = {}
    for k in pairs(containers) do
        if type(k) == "string" and k:find("^customBar_") then
            found[#found + 1] = k
        end
    end
    table.sort(found)
    if #found == 0 then
        print("  (no customBar_* containers — v32 migration not yet run)")
        return
    end
    print(("  customBar container count: %d"):format(#found))
    for _, k in ipairs(found) do
        PrintBar(k, containers[k])
    end
end

local function PrintBarPayload(payload)
    -- For QCT1: / QCB1: tracker-bar exports.
    if type(payload.bars) == "table" then
        print("\n========== payload.bars[] (QCT1 export) ==========")
        for i, bar in ipairs(payload.bars) do
            if type(bar) == "table" then
                PrintBar("bars[" .. i .. "]", bar)
            end
        end
    end
    if type(payload.bar) == "table" then
        print("\n========== payload.bar (QCB1 export) ==========")
        PrintBar("bar", payload.bar)
    end
    if type(payload.specEntries) == "table" then
        print("\n========== payload.specEntries (per-spec global tracker entries) ==========")
        for k, v in pairs(payload.specEntries) do
            print(("  [%s] = %s (%d keys)"):format(tostring(k), type(v), CountKeys(v)))
        end
    end
end

----------------------------------------------------------------------------
-- Main
----------------------------------------------------------------------------

local function Main(args)
    local inputArg, fullDump = nil, false
    for _, a in ipairs(args) do
        if a == "--full" then fullDump = true
        elseif not inputArg then inputArg = a end
    end

    if not inputArg then
        print("usage: lua tools/decode_profile.lua <file|-> [--full]")
        os.exit(1)
    end

    local raw = ReadInput(inputArg)
    local decoded, err = Decode(raw)
    if not decoded then
        print("ERROR: " .. tostring(err))
        os.exit(2)
    end

    PrintHeader(decoded)

    local payload = decoded.payload

    if decoded.prefix == "QUI1:" then
        PrintTopLevel(payload)
        PrintSchemaInfo(payload)
        PrintCustomTrackers(payload)
        PrintCustomBarContainers(payload)
    else
        PrintBarPayload(payload)
    end

    if fullDump and inputArg ~= "-" then
        local out = DumpTree(payload, "", 0, 8)
        local outPath = inputArg .. ".dump.txt"
        WriteFile(outPath, table.concat(out, "\n"))
        print(("\nFull depth-8 dump written to: %s"):format(outPath))
    end
end

Main(arg)
