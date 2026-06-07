-- tests/unit/damage_meter_value_text_test.lua
-- Run: lua tests/unit/damage_meter_value_text_test.lua
--
-- BuildValueText composes the per-row value cell from (primary, secondary)
-- pairs. Three contracts are protected here:
--   1. The "0" → "" suppression must operate on the formatted *string*, never
--      on the input number, and must skip secret-tagged strings (`== "0"`
--      against a secret-tagged value taints under Patch 12.0+ combat rules).
--   2. Both primary and secondary go through the *same* numberFormat — the
--      pre-fix code hardcoded secondary to "compact", producing mismatched
--      cells like "2,400,000 (450)" in complete mode.
--   3. AbbreviateNumbers returns "0" for zero (never ""), so the suppression
--      must happen at the BuildValueText layer, not inside FormatNumber.

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

local loader = assert(loadstring(extract("BuildValueText")
    .. "\nreturn BuildValueText"))
local BuildValueText = loader()

-- Stubs that model the new FormatNumber contract:
--   * Non-secret 0 returns "0" (mirroring AbbreviateNumbers(0)).
--   * Secret values bypass the equality path; SECRET_ZERO formats to "0" as
--     before — proving that suppression is gated on secret state.
--   * Format string is passed through so we can verify it for both primary
--     and secondary (point 2 above).
local SECRET_NUMBER = {}
local SECRET_ZERO   = {}
local _formatCalls
local function reset() _formatCalls = {} end
local function IsSecret(v) return v == SECRET_NUMBER or v == SECRET_ZERO end
local function FormatNumber(v, fmt)
    table.insert(_formatCalls, fmt)
    if v == SECRET_NUMBER then return "SEC" end
    if v == SECRET_ZERO   then return "0"   end
    if v == nil           then return ""    end
    if v == 0             then return "0"   end -- AbbreviateNumbers contract
    if fmt == "compact" then
        if v >= 1e6 then return string.format("%.1fM", v / 1e6) end
        if v >= 1e3 then return string.format("%.1fK", v / 1e3) end
    elseif fmt == "complete" then
        return string.format("%d", v):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    end
    return tostring(v)
end

-- ---- Standard rendering paths ----

reset()
assert(BuildValueText(1500, 999, "compact", IsSecret, FormatNumber) == "1.5K (999)",
    "standard primary + secondary render")

-- Point 2: secondary must match the user's numberFormat. Same call with
-- "complete" must render both sides as comma-separated, not compact.
reset()
assert(BuildValueText(1500, 999, "complete", IsSecret, FormatNumber) == "1,500 (999)",
    "secondary uses the same numberFormat as primary (was hardcoded 'compact')")
assert(_formatCalls[1] == "complete" and _formatCalls[2] == "complete",
    "FormatNumber is called with the same format for both primary and secondary")

-- ---- "0" → "" suppression — point 1 + 3 ----

-- Non-secret zero secondary: stub now returns "0" (AbbreviateNumbers contract).
-- BuildValueText must suppress that "(0)" rather than relying on FormatNumber
-- to short-circuit.
reset()
assert(BuildValueText(1500, 0, "compact", IsSecret, FormatNumber) == "1.5K",
    "non-secret '0' secondary suppressed at string layer")

-- Non-secret zero primary: same symmetric suppression — falls through to the
-- secondary value rather than rendering "0 (100)".
reset()
assert(BuildValueText(0, 100, "compact", IsSecret, FormatNumber) == "100",
    "non-secret '0' primary suppressed → secondary takes over")

-- Both non-secret zeros → empty cell.
reset()
assert(BuildValueText(0, 0, "compact", IsSecret, FormatNumber) == "",
    "both '0' (non-secret) → empty cell")

-- nil propagation: stub returns "" for nil → both sides empty → empty cell.
reset()
assert(BuildValueText(nil, nil, "compact", IsSecret, FormatNumber) == "",
    "nil values render empty cell")

-- ---- Secret-tag protection — point 1 ----

reset()
assert(BuildValueText(SECRET_NUMBER, SECRET_NUMBER, "compact", IsSecret, FormatNumber) == "SEC (SEC)",
    "both secret: render together (no string equality check)")

-- KEY REGRESSION: secret-tagged value whose formatter returned literal "0".
-- The equality-based suppression must short-circuit on secret state, otherwise
-- `secondaryStr == "0"` against a secret string taints execution.
reset()
assert(BuildValueText(1500, SECRET_ZERO, "compact", IsSecret, FormatNumber) == "1.5K (0)",
    "secret-zero secondary keeps '(0)' — equality suppression bypassed")

-- Same for secret-zero primary: must NOT trip the new symmetric primary
-- suppression. Equality against the secret "0" string would taint.
reset()
assert(BuildValueText(SECRET_ZERO, 100, "compact", IsSecret, FormatNumber) == "0 (100)",
    "secret-zero primary kept as '0' — equality suppression bypassed")

-- Mixed: secret primary, non-secret secondary.
reset()
assert(BuildValueText(SECRET_NUMBER, 500, "compact", IsSecret, FormatNumber) == "SEC (500)",
    "secret primary + plain secondary")

-- Defensive: nil IsSecret (e.g. Helpers not yet loaded) → falls through to
-- non-secret path everywhere.
reset()
assert(BuildValueText(1500, 0, "compact", nil, FormatNumber) == "1.5K",
    "nil IsSecret falls back to non-secret path")

print("OK: damage_meter_value_text_test")
