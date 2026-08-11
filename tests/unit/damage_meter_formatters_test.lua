-- tests/unit/damage_meter_formatters_test.lua
-- Run: lua tests/unit/damage_meter_formatters_test.lua
--
-- FormatNumber dispatches to Blizzard's secret-safe number formatters
-- (AbbreviateNumbers / BreakUpLargeNumbers). The unit test stubs those globals
-- to verify dispatch shape — which formatter, which breakpoint config — since
-- the actual abbreviation output is determined by Blizzard at runtime.

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

-- _formatOpts is built at module load via two CreateAbbreviateConfig calls.
-- Anchor on the local declaration; terminate at the line preceding the
-- FormatNumber definition that follows it.
local function extractFormatOpts()
    local chunk = src:match("(local _formatOpts = .-)\nlocal function FormatNumber")
    assert(chunk, "could not locate _formatOpts block")
    return chunk .. "\n"
end

-- Stub Blizzard globals so the extracted code can run under plain Lua.
-- Calls land on _calls so assertions can verify dispatch.
local _calls = {}
local function reset() _calls = {} end

_G.CreateAbbreviateConfig = function(data)
    -- Tag each config with the fractionDivisor of its smallest non-unit
    -- breakpoint (10 for "compact", 1 for "minimal") so AbbreviateNumbers can
    -- report which mode was selected.
    return { __tag = data[3].fractionDivisor }
end
_G.AbbreviateNumbers = function(n, opts)
    table.insert(_calls, { fn = "abbrev", n = n, mode = opts.config.__tag })
    return "ABBR"
end
_G.BreakUpLargeNumbers = function(n)
    table.insert(_calls, { fn = "buln", n = n })
    return "BULN"
end

-- FormatNumber probes before its nil-compare (`secret == nil` throws
-- in-game); the extracted chunk resolves the file-local IsSecretValue as a
-- global here. Model a secret with a sentinel table.
local SECRET = {}
_G.IsSecretValue = function(v) return v == SECRET end

-- FormatDuration delegates its m:ss math to ns.Helpers.FormatMMSS (core/utils.lua).
-- Load the real one into a stub Helpers table so the extracted chunk runs as shipped.
local utilsSrc = readAll("core/utils.lua")
local mmssSrc = utilsSrc:match("(function Helpers%.FormatMMSS.-\nend\n)")
assert(mmssSrc, "could not locate Helpers.FormatMMSS in core/utils.lua")
_G.Helpers = { IsSecretValue = _G.IsSecretValue }
assert(loadstring(mmssSrc))()

local loader = assert(loadstring(extractFormatOpts()
    .. extract("FormatDuration")
    .. extract("FormatNumber")
    .. "\nreturn FormatDuration, FormatNumber"))
local FormatDuration, FormatNumber = loader()

-- FormatDuration (unchanged — pure Lua, no Blizzard dispatch).
assert(FormatDuration(0)   == "",       "0s renders empty")
assert(FormatDuration(nil) == "",       "nil renders empty")
assert(FormatDuration(5)   == "0:05",   "5s -> 0:05")
assert(FormatDuration(65)  == "1:05",   "65s -> 1:05")
assert(FormatDuration(3725) == "62:05", "3725s -> 62:05")

-- FormatNumber — nil short-circuits before any Blizzard call.
reset()
assert(FormatNumber(nil, "compact") == "", "nil -> empty")
assert(#_calls == 0, "nil must not call any formatter")

-- FormatNumber — compact dispatches to AbbreviateNumbers with the compact config.
reset()
assert(FormatNumber(1500, "compact") == "ABBR", "compact returns AbbreviateNumbers result")
assert(#_calls == 1 and _calls[1].fn == "abbrev" and _calls[1].n == 1500 and _calls[1].mode == 10,
    "compact must call AbbreviateNumbers with the fractionDivisor=10 (compact) config")

-- FormatNumber — minimal dispatches to AbbreviateNumbers with the minimal config.
reset()
assert(FormatNumber(2400000, "minimal") == "ABBR", "minimal returns AbbreviateNumbers result")
assert(#_calls == 1 and _calls[1].fn == "abbrev" and _calls[1].n == 2400000 and _calls[1].mode == 1,
    "minimal must call AbbreviateNumbers with the fractionDivisor=1 (minimal) config")

-- FormatNumber — complete dispatches to BreakUpLargeNumbers.
reset()
assert(FormatNumber(1500, "complete") == "BULN", "complete returns BreakUpLargeNumbers result")
assert(#_calls == 1 and _calls[1].fn == "buln" and _calls[1].n == 1500,
    "complete must call BreakUpLargeNumbers")

-- FormatNumber — unknown format falls back to compact (defensive).
reset()
assert(FormatNumber(1500, "garbage") == "ABBR", "unknown -> compact dispatch")
assert(_calls[1].fn == "abbrev" and _calls[1].mode == 10, "unknown format must fall back to compact config")

-- FormatNumber — zero is NOT compared inside FormatNumber. It flows through to
-- the Blizzard formatter unchanged (suppression happens in BuildValueText).
reset()
FormatNumber(0, "compact")
assert(#_calls == 1 and _calls[1].n == 0, "zero must pass through to AbbreviateNumbers, not be short-circuited")

-- FormatNumber — SECRET amounts bypass the nil-compare (probe-first) and ride
-- untouched to the AllowedWhenTainted formatters (sink-passthrough policy).
reset()
assert(FormatNumber(SECRET, "compact") == "ABBR", "secret -> AbbreviateNumbers passthrough")
assert(#_calls == 1 and _calls[1].fn == "abbrev" and _calls[1].n == SECRET,
    "secret amount must reach AbbreviateNumbers raw")
reset()
assert(FormatNumber(SECRET, "complete") == "BULN", "secret -> BreakUpLargeNumbers passthrough")
assert(#_calls == 1 and _calls[1].fn == "buln" and _calls[1].n == SECRET,
    "secret amount must reach BreakUpLargeNumbers raw")

print("OK: damage_meter_formatters_test")
