--[[
  gen_new_profile_seed.lua

  One-shot generator: decode a full QUI profile export string (QUI1:) and emit
  core/new_profile_defaults.lua, the seed applied to every newly-created profile
  via AceDB OnNewProfile (core/init.lua). Existing profiles are never touched.

  Meta/latch/runtime keys are stripped (any top-level "_"-prefixed key + the
  fpsBackup runtime CVar buffer) so the seed carries ONLY genuine settings; the
  migration/compat layers still stamp _schemaVersion/_defaultsVersion on the
  seeded profile afterwards exactly as they do for a fresh profile.

  Usage:
    lua tools/gen_new_profile_seed.lua <path-to-string-file> [out.lua]
    lua tools/gen_new_profile_seed.lua -                       # string on stdin
]]

local function ScriptDir()
    local p = (arg and arg[0]) or ""
    p = p:gsub("\\", "/")
    local dir = p:match("(.*/)")
    if dir == nil or dir == "" then return "./" end
    return dir
end

local env = dofile(ScriptDir() .. "_addon_env.lua")
env.LoadLibs()

local LibDeflate    = LibStub("LibDeflate")
local AceSerializer = LibStub("AceSerializer-3.0")

----------------------------------------------------------------------------
-- Strip set: anything that is migration/runtime state, not a setting.
----------------------------------------------------------------------------
local function ShouldStripTopKey(k)
    if type(k) ~= "string" then return false end
    if k:sub(1, 1) == "_" then return true end   -- every meta/latch key is "_"-prefixed
    if k == "fpsBackup" then return true end       -- runtime CVar backup buffer (defaults.lua = nil)
    if k == "powerBarAltPosition" then return true end -- dead legacy position store, no runtime consumer
    return false
end

----------------------------------------------------------------------------
-- Decode
----------------------------------------------------------------------------
local function ReadInput(path)
    if path == "-" then return io.read("*a") end
    local f, err = io.open(path, "rb")
    if not f then error("Could not open input: " .. tostring(err)) end
    local data = f:read("*a")
    f:close()
    return data
end

local function Decode(raw)
    raw = (raw:gsub("%s+", ""))
    assert(raw:sub(1, 5) == "QUI1:", "expected a QUI1: full-profile string")
    local compressed = assert(LibDeflate:DecodeForPrint(raw:sub(6)), "DecodeForPrint failed")
    local serialized = assert(LibDeflate:DecompressDeflate(compressed), "DecompressDeflate failed")
    local ok, payload = AceSerializer:Deserialize(serialized)
    assert(ok, "Deserialize failed: " .. tostring(payload))
    assert(type(payload) == "table", "payload is not a table")
    return payload
end

----------------------------------------------------------------------------
-- Deterministic Lua-source serializer (sorted keys, round-trip numbers)
----------------------------------------------------------------------------
local IDENT = "^[%a_][%w_]*$"
local RESERVED = {
    ["and"]=true,["break"]=true,["do"]=true,["else"]=true,["elseif"]=true,["end"]=true,
    ["false"]=true,["for"]=true,["function"]=true,["if"]=true,["in"]=true,["local"]=true,
    ["nil"]=true,["not"]=true,["or"]=true,["repeat"]=true,["return"]=true,["then"]=true,
    ["true"]=true,["until"]=true,["while"]=true,
}

local function ReprNumber(v)
    if v ~= v then return "0/0" end
    if v == math.huge then return "math.huge" end
    if v == -math.huge then return "-math.huge" end
    if v == math.floor(v) and math.abs(v) < 1e15 then
        return string.format("%d", v)
    end
    return string.format("%.17g", v)
end

local function ReprScalar(v)
    local t = type(v)
    if t == "string" then return string.format("%q", v) end
    if t == "number" then return ReprNumber(v) end
    if t == "boolean" then return tostring(v) end
    error("unsupported scalar type: " .. t)
end

local function SortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        return tostring(a) < tostring(b)
    end)
    return keys
end

local Serialize
function Serialize(t, indent, out)
    local pad = string.rep("    ", indent)
    out[#out + 1] = "{\n"
    for _, k in ipairs(SortedKeys(t)) do
        local v = t[k]
        local keyStr
        if type(k) == "string" and k:match(IDENT) and not RESERVED[k] then
            keyStr = k
        elseif type(k) == "string" then
            keyStr = "[" .. string.format("%q", k) .. "]"
        elseif type(k) == "number" then
            keyStr = "[" .. ReprNumber(k) .. "]"
        else
            error("unsupported key type: " .. type(k))
        end
        out[#out + 1] = pad .. "    " .. keyStr .. " = "
        if type(v) == "table" then
            Serialize(v, indent + 1, out)
        else
            out[#out + 1] = ReprScalar(v)
        end
        out[#out + 1] = ",\n"
    end
    out[#out + 1] = pad .. "}"
end

----------------------------------------------------------------------------
-- Main
----------------------------------------------------------------------------
local inPath  = arg[1] or error("usage: gen_new_profile_seed.lua <string-file> [out.lua]")
local outPath = arg[2] or (ScriptDir() .. "../core/new_profile_defaults.lua")

local profile = Decode(ReadInput(inPath))

local stripped = {}
for k in pairs(profile) do
    if ShouldStripTopKey(k) then stripped[#stripped + 1] = k end
end
table.sort(stripped)
for _, k in ipairs(stripped) do profile[k] = nil end

-- Force the shipped new-user theme to QUI's Classic Mint, regardless of the
-- source profile's theme. general.themePreset is the live read (main.lua and
-- the options theme picker, QUI_Options/framework.lua); the top-level copy is
-- the legacy store. Set both + the derived accent color so every consumer
-- resolves mint. Mint = "Classic Mint" -> {0.204, 0.827, 0.600} (#34D399).
local function ApplyThemeOverride(p)
    local function mint() return { 0.204, 0.827, 0.6, 1 } end
    p.themePreset = "Classic Mint"
    p.addonAccentColor = mint()
    if type(p.general) ~= "table" then p.general = {} end
    p.general.themePreset = "Classic Mint"
    p.general.addonAccentColor = mint()
    p.general.skinUseClassColor = false   -- picker keeps this in sync with the preset
end
ApplyThemeOverride(profile)

local body = {}
Serialize(profile, 0, body)
local seedSrc = table.concat(body)

local header = [[
-- AUTO-GENERATED by tools/gen_new_profile_seed.lua -- DO NOT EDIT BY HAND.
-- The shipped new-profile defaults. Applied to EVERY newly-created profile
-- (and every fresh install's Default profile) via the AceDB OnNewProfile hook
-- in core/init.lua. Existing profiles are never touched; copies keep their
-- source. defaults.lua stays the legacy fallback so the shadow-defaults pin
-- (core/compatibility.lua) sees no diff for existing users.
--
-- Stripped on generation: every "_"-prefixed meta/latch key + fpsBackup, so a
-- seeded profile still reads as unmigrated (stored schema 0) and the migration
-- layer stamps _schemaVersion/_defaultsVersion on it normally afterwards.
--
-- Regenerate after curating: lua tools/gen_new_profile_seed.lua <string-file>
local ADDON_NAME, ns = ...

ns.NewProfileSeed = ]]

local footer = [[

-- Deep-overwrite the seed onto a freshly-created profile table. AceDB has
-- already filled it with legacy defaults via copyDefaults; we overwrite the
-- curated keys on top. Called from the OnNewProfile hook BEFORE the new
-- profile is first read, so the first reader sees seeded values (no reload).
local function DeepApply(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            local d = dst[k]
            if type(d) ~= "table" then d = {}; dst[k] = d end
            DeepApply(d, v)
        else
            dst[k] = v
        end
    end
end

function ns.ApplyNewProfileSeed(profile)
    if type(profile) ~= "table" then return end
    DeepApply(profile, ns.NewProfileSeed)
end
]]

local f = assert(io.open(outPath, "w"))
f:write(header)
f:write(seedSrc)
f:write("\n")
f:write(footer)
f:close()

local kept = 0
for _ in pairs(profile) do kept = kept + 1 end
io.write(string.format("Wrote %s\n  kept %d top-level setting keys, stripped %d meta/runtime keys: %s\n",
    outPath, kept, #stripped, table.concat(stripped, ", ")))

-- Keep the Profiles-tab "Starter Profile" preset in lock-step with the seed:
-- when we wrote the canonical seed (no custom out path), regenerate
-- importstrings/starter_profile.lua from it so the two never drift. Runs as a
-- separate process so the freshly-written seed file is re-read cleanly.
-- Guard: tests/unit/starter_preset_matches_seed_test.lua.
if not arg[2] then
    local interp = arg[-1] or "lua"
    local presetGen = ScriptDir() .. "gen_starter_preset_from_seed.lua"
    io.write("Regenerating Starter Profile preset from seed...\n")
    local ok = os.execute(string.format('%q %q', interp, presetGen))
    if ok ~= true and ok ~= 0 then
        error("preset regen failed -- run manually: lua tools/gen_starter_preset_from_seed.lua")
    end
end
