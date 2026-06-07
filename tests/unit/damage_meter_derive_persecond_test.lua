-- tests/unit/damage_meter_derive_persecond_test.lua
-- Run: lua tests/unit/damage_meter_derive_persecond_test.lua
--
-- Standalone test for DerivePerSecond — the pure helper that recomputes a
-- row's per-second rate from totalAmount / sessionDuration instead of trusting
-- the API's amountPerSecond.
--
-- The regression it guards: C_DamageMeter's per-source amountPerSecond is
-- SecretWhenInCombat and is derived from the live session duration. After
-- combat ends it declassifies to a garbage value (the report: a target-dummy
-- DPS row read "4" and an HPS row read "7.04e-15" instead of ~405K). The
-- session's own GetSessionDurationSeconds is AllowedWhenUntainted and NOT
-- SecretWhenInCombat, so we divide totalAmount by it ourselves. We can only
-- divide once totalAmount is non-secret (post-combat / idle / historical);
-- mid-combat it stays secret, so the helper returns nil and the caller keeps
-- the API value (the C side reads the secret). Comparing/dividing a secret in
-- Lua faults, so the secret guard MUST run before any numeric comparison.

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a"); file:close()
    return data:gsub("\r\n", "\n")
end

local src = readAll("QUI_DamageMeter/damage_meter/damage_meter.lua")

local start_pos = src:find("local function DerivePerSecond")
assert(start_pos, "could not locate DerivePerSecond block in damage_meter.lua")
local end_pos = src:find("QUI_DamageMeter%.DerivePerSecond", start_pos)
assert(end_pos, "could not locate QUI_DamageMeter.DerivePerSecond assignment")

local chunk = src:sub(start_pos, end_pos - 1):match("^(.-)\n%s*$")
assert(chunk, "failed to extract function chunk")

local loader = assert(loadstring(chunk .. "\nreturn DerivePerSecond"))
local DerivePerSecond = loader()

-- Case 1 (the bug): 19.44M total over a 48s fight → ~405K/s, NOT the API's "4".
do
    local rate = DerivePerSecond(19440000, 48, nil)
    assert(rate and math.abs(rate - 405000) < 1, "405000/s expected, got " .. tostring(rate))
end

-- Case 2: a small healing total over a short fight → a sane rate, NOT 7.04e-15.
do
    local rate = DerivePerSecond(300, 12, nil)
    assert(rate == 25, "25/s expected, got " .. tostring(rate))
end

-- Case 3 (mid-combat): secret totalAmount → nil. Defer to the API value;
-- dividing a secret in Lua would fault. Secret check precedes the comparison.
do
    local SECRET = setmetatable({}, { __tostring = function() return "secret" end })
    local function isSecret(x) return x == SECRET end
    assert(DerivePerSecond(SECRET, 48, isSecret) == nil, "secret total must return nil")
end

-- Case 4: secret duration → nil (guarded before any comparison).
do
    local SECRET = setmetatable({}, {})
    local function isSecret(x) return x == SECRET end
    assert(DerivePerSecond(19440000, SECRET, isSecret) == nil, "secret duration must return nil")
end

-- Case 5: zero / negative / nil duration → nil (no divide-by-zero, no fault).
do
    assert(DerivePerSecond(19440000, 0, nil)   == nil, "zero duration → nil")
    assert(DerivePerSecond(19440000, -5, nil)  == nil, "negative duration → nil")
    assert(DerivePerSecond(19440000, nil, nil) == nil, "nil duration → nil")
end

-- Case 6: nil totalAmount → nil (no row data yet).
do
    assert(DerivePerSecond(nil, 48, nil) == nil, "nil total → nil")
end

-- Case 7: missing isSecret (Helpers unavailable) must not crash on plain numbers.
do
    assert(DerivePerSecond(1000, 10, nil) == 100, "nil isSecret + plain numbers → 100")
end

print("OK: damage_meter_derive_persecond_test")
