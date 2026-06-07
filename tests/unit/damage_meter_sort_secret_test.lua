-- tests/unit/damage_meter_sort_secret_test.lua
-- Run: lua tests/unit/damage_meter_sort_secret_test.lua
--
-- Regression: the damage meter re-sorts sources by amount / amount-per-second
-- (PrepareSourcesForRender, GetCombinedHealingView/Breakdown). The old code
-- handed table.sort a comparator that returned false for EVERY pair whenever a
-- value was secret-tagged — which is the whole list during combat. Under such
-- a degenerate comparator Lua 5.1's quicksort does NOT leave the array as-is;
-- it reorders it, scrambling the API's already-correct descending order so the
-- highest DPS/HPS rows ended up mid-list or at the bottom. Demonstration:
--
--   table.sort({100,90,80,70,60,50,40,30,20,10}, function() return false end)
--   --> 100,50,40,30,20,60,80,70,90,10   (scrambled!)
--
-- SortByDescSafe fixes this by skipping the sort when any key is secret (the
-- API order, sorted on the C side, is already correct) and only sorting when
-- every key is comparable.

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

local loader = assert(loadstring(extract("SortByDescSafe") .. "\nreturn SortByDescSafe"))
local SortByDescSafe = loader()

local function vals(list)
    local out = {}
    for i, e in ipairs(list) do out[i] = e.amt end
    return table.concat(out, ",")
end
local function makeDescList(n)
    local l = {}
    for i = 1, n do l[i] = { amt = (n - i + 1) * 10 } end -- 100,90,...,10
    return l
end
local keyFn = function(e) return e.amt end

-- A secret marker + matching isSecret predicate (mirrors Helpers.IsSecretValue).
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
local function isSecret(v) return v == SECRET end

-- 1. THE BUG: every key secret (combat) must PRESERVE the incoming API order,
--    not scramble it. This is the exact case the old comparator broke.
local secretList = {}
for i = 1, 10 do secretList[i] = { amt = SECRET, orig = (10 - i + 1) * 10 } end
SortByDescSafe(secretList, keyFn, isSecret)
local order = {}
for i, e in ipairs(secretList) do order[i] = e.orig end
assert(table.concat(order, ",") == "100,90,80,70,60,50,40,30,20,10",
    "all-secret keys must preserve API order, got " .. table.concat(order, ","))

-- 2. No secret values: sorts strictly descending.
local asc = { { amt = 10 }, { amt = 50 }, { amt = 30 }, { amt = 90 }, { amt = 20 } }
SortByDescSafe(asc, keyFn, isSecret)
assert(vals(asc) == "90,50,30,20,10", "non-secret keys sort descending, got " .. vals(asc))

-- 3. A SINGLE secret key anywhere means we can't safely compare → preserve order.
local mixed = { { amt = 10 }, { amt = SECRET }, { amt = 90 } }
SortByDescSafe(mixed, keyFn, isSecret)
assert(mixed[1].amt == 10 and mixed[3].amt == 90 and isSecret(mixed[2].amt),
    "a single secret key preserves order (no partial sort)")

-- 4. nil keys are treated as 0 by the comparator (not secret), still sortable.
local withNil = { { amt = nil }, { amt = 5 }, { amt = nil }, { amt = 99 } }
SortByDescSafe(withNil, function(e) return e.amt end, isSecret)
assert(withNil[1].amt == 99 and withNil[2].amt == 5, "nil keys sort as 0 (descending)")

-- 5. No isSecret predicate supplied → always sorts (nothing is "secret").
local noPred = makeDescList(4) -- {40,30,20,10}
noPred[1].amt, noPred[4].amt = 10, 100 -- jumble first/last -> {10,30,20,100}
SortByDescSafe(noPred, keyFn, nil)
assert(vals(noPred) == "100,30,20,10", "without isSecret, always sorts descending, got " .. vals(noPred))

-- 6. Degenerate inputs don't error.
SortByDescSafe({}, keyFn, isSecret)
SortByDescSafe({ { amt = 1 } }, keyFn, isSecret)

print("OK: damage_meter_sort_secret_test")
