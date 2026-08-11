-- tests/unit/nameplates_color_resolver_test.lua
-- Run: lua tests/unit/nameplates_color_resolver_test.lua
--
-- Color resolver purity (plans/009-nameplates.md): the resolver returns
-- plain r,g,b from profile tables only, for every ladder branch, and reads
-- NO Unit* API (static assert). That purity is what makes the
-- skip-if-unchanged latch in front of SetStatusBarColor safe.

local function fail(msg)
    print("FAIL: nameplates_color_resolver_test - " .. msg)
    os.exit(1)
end

---------------------------------------------------------------------------
-- Static purity assert: no Unit* call anywhere in the resolver file.
---------------------------------------------------------------------------
local f = io.open("QUI_Nameplates/nameplates/plate_colors.lua", "rb")
if not f then fail("plate_colors.lua not found") end
local src = f:read("*a")
f:close()
-- Match Unit-API call sites (identifier boundary + open paren), not the
-- word "unit" in comments/fields.
for apiName in src:gmatch("[^%w_](Unit%u[%w_]*)%s*%(") do
    fail("plate_colors.lua calls " .. apiName .. " — the resolver must be pure over precomputed plate state")
end

---------------------------------------------------------------------------
-- Behavioral: exercise every ladder branch.
---------------------------------------------------------------------------
RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }

local ns = { Helpers = {} }
assert(loadfile("QUI_Nameplates/nameplates/shared.lua"))("QUI_Nameplates", ns)
assert(loadfile("QUI_Nameplates/nameplates/plate_colors.lua"))("QUI_Nameplates", ns)
local Colors = ns.QUI_Nameplates.Colors
if not Colors then fail("NP.Colors not exported") end

local settings = {
    colors = {
        hostile  = { 0.39, 0.11, 0.09 },
        neutral  = { 0.81, 0.72, 0.19 },
        friendly = { 0.314, 0.800, 0.408 },
        tapped   = { 0.5, 0.5, 0.5 },
        questEnabled = true,
        quest = { 1, 0.82, 0 },
        classColorEnemyPlayers = true,
        targetEnabled = true,
        target = { 1, 1, 1 },
        focusEnabled = true,
        focus = { 0.051, 0.82, 0.62 },
        threatEnabled = true,
        tankHasAggro = { 0.05, 0.82, 0.62 },
        tankNoAggro  = { 1, 0.22, 0.17 },
        offTankAggro = { 0.188, 0.761, 0.812 },
        dpsHasAggro  = { 1, 0.5, 0 },
        dpsNearAggro = { 0.81, 0.72, 0.19 },
        oocDarken = true,
        oocDarkenFactor = 0.5,
    },
}
local instanceTank = { role = "TANK", inInstance = true }
local instanceDps = { role = "DAMAGER", inInstance = true }
local world = { role = "DAMAGER", inInstance = false }

local function check(label, plate, context, er, eg, eb)
    local r, g, b = Colors.Resolve(plate, settings, context)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        fail(label .. ": non-plain return")
    end
    local function close(a, bV) return math.abs(a - bV) < 1e-9 end
    if not (close(r, er) and close(g, eg) and close(b, eb)) then
        fail(("%s: expected %.3f,%.3f,%.3f got %.3f,%.3f,%.3f"):format(label, er, eg, eb, r, g, b))
    end
end

-- 1. tap-denied beats everything
check("tapped", { npTapDenied = true, npIsQuest = true, npReaction = "hostile", npInCombat = true }, world, 0.5, 0.5, 0.5)

-- 2. quest beats threat/reaction
check("quest", { npIsQuest = true, npReaction = "hostile", npThreat = "high", npInCombat = true }, instanceTank, 1, 0.82, 0)

-- 3. threat: tank with aggro / tank without / offtank
check("tank has aggro", { npReaction = "hostile", npThreat = "high", npInCombat = true }, instanceTank, 0.05, 0.82, 0.62)
check("tank lost aggro", { npReaction = "hostile", npThreat = "low", npInCombat = true }, instanceTank, 1, 0.22, 0.17)
check("offtank", { npReaction = "hostile", npThreat = "offtank", npInCombat = true }, instanceTank, 0.188, 0.761, 0.812)

-- 4. threat: dps pulling / near
check("dps has aggro", { npReaction = "hostile", npThreat = "high", npInCombat = true }, instanceDps, 1, 0.5, 0)
check("dps near aggro", { npReaction = "hostile", npThreat = "near", npInCombat = true }, instanceDps, 0.81, 0.72, 0.19)

-- 5. threat is instance-gated: same plate in the world falls to reaction
check("threat world-gated", { npReaction = "hostile", npThreat = "high", npInCombat = true }, world, 0.39, 0.11, 0.09)

-- 6. dps low threat in instance falls through to reaction (not a threat color)
check("dps low threat", { npReaction = "hostile", npThreat = "low", npInCombat = true }, instanceDps, 0.39, 0.11, 0.09)

-- 7. target/focus override (below threat, above class)
check("target override", { npReaction = "hostile", npIsTarget = true, npIsPlayer = true, npClassToken = "MAGE", npInCombat = true }, world, 1, 1, 1)
check("focus override", { npReaction = "hostile", npIsFocus = true, npInCombat = true }, world, 0.051, 0.82, 0.62)

-- 8. enemy player class color
check("class color", { npReaction = "hostile", npIsPlayer = true, npClassToken = "MAGE", npInCombat = true }, world, 0.25, 0.78, 0.92)

-- 9. reaction colors
check("hostile", { npReaction = "hostile", npInCombat = true }, world, 0.39, 0.11, 0.09)
check("neutral", { npReaction = "neutral", npInCombat = true }, world, 0.81, 0.72, 0.19)
check("friendly", { npReaction = "friendly", npInCombat = false }, world, 0.314, 0.8, 0.408)

-- 10. ooc darkening (factor 0.5); nil combat state (secret) must NOT darken
check("ooc darkened", { npReaction = "hostile", npInCombat = false }, world, 0.195, 0.055, 0.045)
check("secret combat no darken", { npReaction = "hostile", npInCombat = nil }, world, 0.39, 0.11, 0.09)

-- 11. missing settings degrade to fallback, still plain numbers
local r, g, b = Colors.Resolve({}, nil, nil)
if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
    fail("empty inputs must still return plain numbers")
end

print("OK: nameplates_color_resolver_test")
