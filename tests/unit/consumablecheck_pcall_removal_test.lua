-- tests/unit/consumablecheck_pcall_removal_test.lua
-- Source-text contract pins for modules/qol/consumablecheck.lua (Task 1b).
-- Run: lua5.1 tests/unit/consumablecheck_pcall_removal_test.lua
--
-- 13 error-swallowing pcalls wrapped pure addon-local table lookups and
-- widget calls on values ALREADY sanitized upstream (Helpers.SafeValue /
-- Helpers.SafeToNumber before every site). They could only ever catch our
-- own bugs, and they silenced them on a hot per-aura scan path while paying
-- a closure allocation per call. Every site's sanitize-trace was verified
-- before deletion (task-1b-report.md); this test pins the outcome: the
-- pcall wrappers are gone, the lookups they guarded are still there, and the
-- upstream sanitize calls that make the deletion safe are still there too
-- (they are now load-bearing).

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return (d:gsub("\r\n", "\n"))
end

local src = readAll("modules/qol/consumablecheck.lua")
local fails = 0
local function check(name, ok)
    if ok then print("  ok  " .. name)
    else fails = fails + 1; print("FAIL  " .. name) end
end

-- No error-swallowing pcall left anywhere in the file. Audit found exactly
-- 13 pcalls wrapping addon-local logic and all 13 were removed. Round-22
-- reintroduced exactly ONE deliberate C-API boundary guard: the unbounded
-- aura index walk pcalls C_UnitAuras.GetAuraDataByIndex per index (iterator
-- termination contract — pcall-fail terminates), which is a secret-guard,
-- not an error-swallow of our own logic. Census: exactly 1, exactly that
-- literal.
local pcallCount = select(2, src:gsub("pcall%(", ""))
check("exactly one pcall( remains in consumablecheck.lua (the aura index-walk guard)",
    pcallCount == 1)
check("the surviving pcall is the GetAuraDataByIndex index-walk guard",
    src:find("pcall(C_UnitAuras.GetAuraDataByIndex, \"player\", i, \"HELPFUL\")", 1, true) ~= nil)

-- Logic kept: the lookups the pcalls used to guard are still present and
-- still gate on the exact same tables/keys (match semantics preserved).
check("FOOD_BUFFS[spellId] lookup kept (wrapper gone)",
    src:find("FOOD_BUFFS[spellId]", 1, true) ~= nil)
check("food match still ORs the fallback icon literal (exact semantics preserved)",
    src:find("FOOD_BUFFS[spellId] or icon == 136000", 1, true) ~= nil)
check("FLASK_BUFFS[spellId] lookup kept (wrapper gone)",
    src:find("FLASK_BUFFS[spellId]", 1, true) ~= nil)
check("RUNE_BUFFS[spellId] lookup kept (wrapper gone)",
    src:find("RUNE_BUFFS[spellId]", 1, true) ~= nil)
check("mhConfig.anyBuffIDs[spellId] lookup kept (ScanPlayerBuffs)",
    src:find("mhConfig.anyBuffIDs[spellId]", 1, true) ~= nil)
check("ohConfig.anyBuffIDs[spellId] lookup kept (ScanPlayerBuffs)",
    src:find("ohConfig.anyBuffIDs[spellId]", 1, true) ~= nil)
check("CheckEnhancementActive removed (weapon-aura detection now sources ScanPlayerBuffs)",
    src:find("CheckEnhancementActive", 1, true) == nil)
check("ComputeEnhancementState present (compute-only replacement)",
    src:find("local function ComputeEnhancementState(", 1, true) ~= nil)

-- Sanitize-trace: the upstream Helpers.SafeValue / Helpers.SafeToNumber
-- calls that make every deletion safe are still present and still run
-- before the lookups/arithmetic that depend on them. These are now
-- load-bearing (no pcall left to paper over a regression here).
check("spellId sanitized via Helpers.SafeValue before ScanPlayerBuffs' lookups",
    src:find("local spellId = Helpers.SafeValue(auraData.spellId)", 1, true) ~= nil)
check("icon sanitized via Helpers.SafeValue before the food fallback compare",
    src:find("local icon = Helpers.SafeValue(auraData.icon)", 1, true) ~= nil)
check("weapon-aura match still rides ScanPlayerBuffs' sanitized spellId (mh/oh pins above)",
    src:find("local spellId = Helpers.SafeValue(auraData.spellId)", 1, true) ~= nil)
check("expires coerced via Helpers.SafeToNumber before the timeText arithmetic",
    src:find("local expires = Helpers.SafeToNumber(auraData.expirationTime)", 1, true) ~= nil)

-- Healthstone arithmetic: both operands are `or 0`-coerced counts, so the
-- addition can never throw. The `or 0` coercions are the sanitize-trace.
check("hsCount coerced via `or 0`",
    src:find("local hsCount = C_Item.GetItemCount(5512, false, true) or 0", 1, true) ~= nil)
check("hsLockCount coerced via `or 0`",
    src:find("local hsLockCount = C_Item.GetItemCount(224464, false, true) or 0", 1, true) ~= nil)
check("totalHS is now a plain inline sum, no pcall/ok-guard left around it",
    src:find("local totalHS = hsCount + hsLockCount", 1, true) ~= nil)

-- No stray closure-wrapper artifacts left behind from the deleted pcalls
-- (e.g. `local success, isFood =` / `local ok, match =` result pairs that
-- pcall used to populate).
check("no leftover pcall result-pair locals (success, isFood)",
    src:find("success, isFood", 1, true) == nil)
check("no leftover pcall result-pair locals (success, isFlask)",
    src:find("success, isFlask", 1, true) == nil)
check("no leftover pcall result-pair locals (success, isRune)",
    src:find("success, isRune", 1, true) == nil)
check("no leftover pcall result-pair locals (ok, match)",
    src:find("ok, match", 1, true) == nil)
check("no leftover pcall result-pair locals (ok, totalHS)",
    src:find("ok, totalHS", 1, true) == nil)

if fails > 0 then error(fails .. " failure(s) in consumablecheck_pcall_removal_test") end
print("OK: consumablecheck_pcall_removal_test (all checks passed)")
