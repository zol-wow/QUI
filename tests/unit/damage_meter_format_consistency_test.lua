-- tests/unit/damage_meter_format_consistency_test.lua
-- Run: lua tests/unit/damage_meter_format_consistency_test.lua
--
-- Regression test: before this fix, FormatNumber branched on secret state and
-- routed combat-tainted values through C_StringUtil.TruncateWhenZero, which
-- emits raw integer strings ("1523") rather than abbreviated values ("1.5K").
-- That made damage-meter rows look different the moment combat started —
-- "1.5K (250)" out of combat would jump to "1500 (250)" in combat, silently
-- dropping the user's numberFormat setting.
--
-- The fix routes everything through AbbreviateNumbers / BreakUpLargeNumbers,
-- both flagged SecretArguments=AllowedWhenTainted. This test pins that
-- contract: secret and non-secret inputs MUST go through the same Blizzard
-- formatter with the same options, and the only branch left in FormatNumber
-- is the format-string dispatch.

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
local function extractFormatOpts()
    local chunk = src:match("(local _formatOpts = .-)\nlocal function FormatNumber")
    assert(chunk, "could not locate _formatOpts block")
    return chunk .. "\n"
end

-- Static guard: FormatNumber must NOT mention any taint-branch helper. If
-- someone reintroduces an IsSecretValue / TruncateWhenZero branch, this fires
-- before the runtime assertions even start.
local formatNumberSrc = extract("FormatNumber")
assert(not formatNumberSrc:find("IsSecretValue"),
    "FormatNumber must not branch on IsSecretValue — both paths go through Blizzard")
assert(not formatNumberSrc:find("TruncateWhenZero"),
    "FormatNumber must not route through TruncateWhenZero — that emits raw integers")
assert(not formatNumberSrc:find("== 0"),
    "FormatNumber must not compare amount to 0 — let Blizzard's formatter handle zero")

-- Stub Blizzard globals. Identity tags travel from CreateAbbreviateConfig
-- through to AbbreviateNumbers so the test can prove that secret and
-- non-secret inputs use the SAME options table.
local _calls
local function reset() _calls = {} end
_G.CreateAbbreviateConfig = function(data)
    return { __config_for = data }
end
_G.AbbreviateNumbers = function(n, opts)
    table.insert(_calls, { fn = "abbrev", n = n, opts = opts })
    return "ABBR:" .. tostring(n)
end
_G.BreakUpLargeNumbers = function(n)
    table.insert(_calls, { fn = "buln", n = n })
    return "BULN:" .. tostring(n)
end

local loader = assert(loadstring(extractFormatOpts()
    .. extract("FormatNumber")
    .. "\nreturn FormatNumber"))
local FormatNumber = loader()

-- Sentinel that masquerades as a secret-tagged value. Real ConditionalSecret
-- objects are userdata; for dispatch purposes any non-nil value works because
-- FormatNumber never inspects the input.
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })

-- ---- compact: secret and non-secret share the same opts table ----

reset()
FormatNumber(1500, "compact")
FormatNumber(SECRET, "compact")
assert(#_calls == 2, "two AbbreviateNumbers calls expected")
assert(_calls[1].fn == "abbrev" and _calls[2].fn == "abbrev",
    "both compact calls must dispatch to AbbreviateNumbers (not BreakUpLargeNumbers)")
assert(_calls[1].opts == _calls[2].opts,
    "secret and non-secret 'compact' MUST share the same opts table — same formatter, same output shape")

-- ---- minimal: same property ----

reset()
FormatNumber(2400000, "minimal")
FormatNumber(SECRET, "minimal")
assert(_calls[1].opts == _calls[2].opts,
    "secret and non-secret 'minimal' MUST share the same opts table")

-- ---- compact vs minimal use *different* opts (sanity check on the dispatch) ----

reset()
FormatNumber(1500, "compact")
FormatNumber(1500, "minimal")
assert(_calls[1].opts ~= _calls[2].opts,
    "compact and minimal must use different opts tables (different breakpoint configs)")

-- ---- complete: BreakUpLargeNumbers for both secret and non-secret ----

reset()
FormatNumber(1500, "complete")
FormatNumber(SECRET, "complete")
assert(#_calls == 2, "two calls expected")
assert(_calls[1].fn == "buln" and _calls[2].fn == "buln",
    "both complete calls must dispatch to BreakUpLargeNumbers")

-- ---- nil: short-circuits BEFORE any formatter call ----

reset()
assert(FormatNumber(nil, "compact") == "", "nil → empty string")
assert(FormatNumber(nil, "complete") == "", "nil → empty string (complete)")
assert(#_calls == 0, "nil must not invoke any formatter (only safe non-comparison)")

print("OK: damage_meter_format_consistency_test")
