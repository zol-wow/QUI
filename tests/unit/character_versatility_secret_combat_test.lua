-- tests/unit/character_versatility_secret_combat_test.lua
-- Run: lua tests/unit/character_versatility_secret_combat_test.lua
--
-- Regression: Versatility is the only secondary stat whose displayed percent is
-- a Lua sum of two APIs:
--     GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE)
--   + GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE)
-- Crit/Haste/Mastery each use a single call. Those single secret returns pass
-- straight through to the C-side SetFormattedText / StatusBar:SetValue, but a
-- Lua "+" on two secret values throws once the addon is tainted in restricted
-- content (M+/raid/encounter/PvP). The old code ran that "+" unconditionally in
-- the value/bar render path, so in combat pcall failed -> the versatility row's
-- value text froze and its bar sat empty while the other three rendered live.
--
-- Fix: in restricted (secret) content fill the value/bar from the single
-- rating-bonus call only (a lone secret the C side can still consume); only do
-- the full Lua sum out of combat. The rich tooltip must also bail to the plain
-- STAT_VERSATILITY_TOOLTIP when a versatility component is secret, rather than
-- formatting a misleading 0.00% row from the SafeGetStat zero-fallback.

local function readAll(path)
    local f = assert(io.open(path, "rb"), "failed to open " .. path)
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end

local src = readAll("QUI_Skinning/skinning/character_pane/character.lua")

local function has(needle, msg)
    assert(src:find(needle, 1, true), msg)
end
local function hasnot(needle, msg)
    assert(not src:find(needle, 1, true), msg)
end

-- 1. Versatility declares a combat-safe single-call fallback (rating-bonus only,
--    no Lua "+"), distinct from its out-of-combat full sum.
has("combatPercentFunc = function() return GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE) end",
    "versatility must expose a single-call combatPercentFunc (rating-bonus only, no '+')")

-- 2. The render loop selects the combat fallback when secrets are restricted,
--    and pcalls the SELECTED function (not stat.percentFunc directly).
has("if secretsOff and stat.combatPercentFunc then",
    "render loop must swap to combatPercentFunc when secretsOff")
has("local pctOk, pct = pcall(percentFunc)",
    "render loop must pcall the selected percentFunc")
hasnot("local pctOk, pct = pcall(stat.percentFunc)",
    "render loop must not call stat.percentFunc directly (bypasses the combat fallback)")

-- 3. The rich tooltip guards readability before formatting numbers, so a
--    detector/source mismatch can't render a 0.00% versatility tooltip.
has("GetStatOrNil(GetCombatRatingBonus, CR_VERSATILITY_DAMAGE_DONE) == nil",
    "versatility tooltip must check rating-bonus readability before formatting")
has("GetStatOrNil(GetVersatilityBonus, CR_VERSATILITY_DAMAGE_DONE) == nil",
    "versatility tooltip must check non-rating-bonus readability before formatting")

print("OK: character_versatility_secret_combat_test")
