-- tests/unit/safe_number_or_nil_reaction_guard_test.lua
-- Run: lua tests/unit/safe_number_or_nil_reaction_guard_test.lua
--
-- Two pins from the 2026-07 Safe* unwrap audit:
-- (1) Helpers.SafeNumberOrNil contract: number in -> number out, everything
--     unreadable (secret / nil / non-numeric) -> nil. This is the helper for
--     callers whose nil guards must be LIVE — Helpers.SafeToNumber can never
--     return nil (`fallback or 0`), which made downstream nil guards dead
--     code at nine call sites.
-- (2) Source guards: both unit-reaction color paths must gate on
--     `reaction and reaction > 0` so a secret/unknown reaction (folded to 0
--     by SafeToNumber) falls through instead of painting hostile red.

---------------------------------------------------------------------------
-- (1) Behavioral: load the REAL core/utils.lua with a fake secret probe.
---------------------------------------------------------------------------
local SECRET = setmetatable({}, { __tostring = function() return "SECRET" end })
local function fakeIsSecretValue(v) return v == SECRET end
_G.issecretvalue = fakeIsSecretValue
_G.LibStub = function() return nil end

local ns = {}
ns.SafeCall = function(_policy, fn, ...) return pcall(fn, ...) end
ns.SafeCallMethod = function(_policy, obj, name, ...) return pcall(function(...) return obj[name](obj, ...) end, ...) end
ns.SafeCallMethodIfPresent = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end
assert(loadfile("core/utils.lua"))("QUI", ns)

local H = ns.Helpers
assert(H and H.SafeNumberOrNil, "core/utils.lua must export Helpers.SafeNumberOrNil")

assert(H.SafeNumberOrNil(5) == 5, "number passes through")
assert(H.SafeNumberOrNil("7") == 7, "numeric string coerces")
assert(H.SafeNumberOrNil(nil) == nil, "nil stays nil")
assert(H.SafeNumberOrNil("x") == nil, "non-numeric string -> nil")
assert(H.SafeNumberOrNil(SECRET) == nil, "secret -> nil (reject, never 0)")

-- Contrast pin: SafeToNumber's documented 0-coercion — an explicit nil
-- fallback still yields 0, so its callers' nil guards are dead by contract.
assert(H.SafeToNumber(SECRET, nil) == 0, "SafeToNumber folds secret to 0 even with nil fallback")
assert(H.SafeToNumber(nil, nil) == 0, "SafeToNumber folds nil to 0 even with nil fallback")

---------------------------------------------------------------------------
-- (2) Source guards: reaction > 0 gate on BOTH reaction-color paths.
---------------------------------------------------------------------------
local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local data = f:read("*a"); f:close()
    return (data:gsub("\r\n", "\n"))
end

local utilsSrc = readAll("core/utils.lua")
local classColorBody = utilsSrc:match("function Helpers%.GetUnitClassColor.-\nend")
assert(classColorBody, "GetUnitClassColor not found in core/utils.lua")
assert(classColorBody:find("if reaction and reaction > 0 then", 1, true),
    "utils GetUnitClassColor must gate the hostility cascade on reaction > 0")

local ufSrc = readAll("QUI_UnitFrames/unitframes/unitframes.lua")
-- Scope to the hostility-color block so the pin survives unrelated edits.
local hostilityBlock = ufSrc:match("useHostilityColor.-\n%s+end\n")
assert(hostilityBlock, "useHostilityColor block not found in unitframes.lua")
assert(hostilityBlock:find("if reaction and reaction > 0 then", 1, true),
    "unitframes hostility color must gate on reaction > 0 — a bare `if reaction` " ..
    "sends secret/unknown reactions (folded to 0, truthy) down the hostile-red branch")

print("OK safe_number_or_nil_reaction_guard_test")
