-- tests/unit/damage_meter_shorten_name_test.lua
-- Run: lua tests/unit/damage_meter_shorten_name_test.lua
--
-- ShortenName drops the "-Realm" suffix from a unit name when the shortenNames
-- setting is on, by delegating to Blizzard's Ambiguate(name, "short"). The
-- contract protected here:
--   1. nil input passes through as nil so callers keep their own fallback
--      (the row renderer does `ShortenName(name) or "?"`).
--   2. With the setting OFF, the name is returned verbatim — no Ambiguate call.
--   3. With the setting ON but Ambiguate unavailable (minimal client), the name
--      is returned verbatim rather than erroring.
--   4. With the setting ON and Ambiguate present, the Ambiguate result is used,
--      falling back to the original if Ambiguate returns nil.
-- ShortenName never compares or concatenates the (ConditionalSecret) name — its
-- only touch is the C call — so this stays secret-safe under combat rules.

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end

local src = readAll("QUI_DamageMeter/damage_meter/damage_meter.lua")

local function extract(funcName)
    local pat = "(local function " .. funcName .. ".-\nend\n)"
    local chunk = src:match(pat)
    assert(chunk, "could not locate " .. funcName .. " in damage_meter.lua")
    return chunk
end

-- ShortenName closes over GetSettings and Ambiguate. Declare them as locals
-- ahead of the extracted chunk so the function binds them as upvalues, then
-- hand back a setter so each case can inject its own stubs.
local loader = assert(loadstring(
    "local GetSettings, Ambiguate\n"
    .. extract("ShortenName")
    .. "\nreturn ShortenName, function(gs, amb) GetSettings = gs; Ambiguate = amb end"))
local ShortenName, setDeps = loader()

local function settings(on) return function() return { shortenNames = on } end end
local function ambiguateShort(name, mode)
    assert(mode == "short", "ShortenName must request the 'short' form")
    return (name:gsub("%-.*$", ""))
end

-- 1. nil passes through (caller supplies the fallback).
setDeps(settings(true), ambiguateShort)
assert(ShortenName(nil) == nil, "nil input returns nil")

-- 2. setting OFF → verbatim, Ambiguate never consulted.
setDeps(settings(false), function() error("Ambiguate must not be called when shortenNames is off") end)
assert(ShortenName("Anya-Stormrage") == "Anya-Stormrage", "setting off returns name verbatim")

-- 3. setting ON but no Ambiguate (minimal client) → verbatim, no error.
setDeps(settings(true), nil)
assert(ShortenName("Anya-Stormrage") == "Anya-Stormrage", "missing Ambiguate returns name verbatim")

-- 4. setting ON + Ambiguate present → realm stripped; realm-less names untouched.
setDeps(settings(true), ambiguateShort)
assert(ShortenName("Anya-Stormrage") == "Anya", "cross-realm name shortened")
assert(ShortenName("Anya") == "Anya", "same-realm name unchanged")

-- 4b. Ambiguate returning nil falls back to the original name.
setDeps(settings(true), function() return nil end)
assert(ShortenName("Anya-Stormrage") == "Anya-Stormrage", "nil Ambiguate result falls back to original")

-- Defensive: no settings table (db not ready) → verbatim.
setDeps(function() return nil end, ambiguateShort)
assert(ShortenName("Anya-Stormrage") == "Anya-Stormrage", "nil settings returns name verbatim")

print("OK: damage_meter_shorten_name_test")
