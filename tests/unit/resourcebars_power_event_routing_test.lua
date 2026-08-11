-- tests/unit/resourcebars_power_event_routing_test.lua
-- Run: lua tests/unit/resourcebars_power_event_routing_test.lua
--
-- OnUnitPower refreshed BOTH large renderers on every UNIT_POWER_* event
-- even though the payload names exactly which power type changed
-- (tests/api-docs/blizzard/UnitDocumentation.lua: UNIT_POWER_UPDATE payload
-- is { unitTarget, powerType cstring }). RoutePowerEvent is the pure
-- routing seam: given the event token and each bar's displayed token, it
-- decides which renderer(s) the event touches. Derived resources with no
-- UnitPower token (STAGGER, SOUL, tracker stacks) must keep their old
-- refresh-on-every-event superset behavior.

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a"); file:close()
    return data:gsub("\r\n", "\n")
end

local src = readAll("QUI_ResourceBars/resourcebars/resourcebars.lua")

local start_pos = src:find("local POWER_EVENT_TOKENS = {", 1, true)
assert(start_pos, "could not locate POWER_EVENT_TOKENS block")
local end_pos = src:find("ns.RoutePowerEvent = RoutePowerEvent", start_pos, true)
assert(end_pos, "could not locate ns.RoutePowerEvent export")

-- The chunk indexes the global Enum at load time: stub it with distinct ids.
Enum = { PowerType = {
    Mana = 0, Rage = 1, Focus = 2, Energy = 3, ComboPoints = 4, Runes = 5,
    RunicPower = 6, SoulShards = 7, LunarPower = 8, HolyPower = 9,
    Maelstrom = 11, Chi = 12, Insanity = 13, ArcaneCharges = 16, Fury = 17,
    Essence = 19,
} }
-- DEVIATION (recorded in task report): in the real file `ns` is the file's
-- vararg parameter, not a global, but the extracted chunk still runs the
-- trailing `ns.POWER_EVENT_TOKENS = POWER_EVENT_TOKENS` export assignment.
-- Stub it so the chunk executes standalone.
ns = {}

local chunk = src:sub(start_pos, end_pos - 1)
local loader = assert(loadstring(chunk .. "\nreturn RoutePowerEvent, POWER_EVENT_TOKENS"))
local RoutePowerEvent, TOKENS = loader()

-- Every UnitPower-driven displayable resource has a token (spellings per
-- tests/framexml .../PowerBarColorUtil.lua).
assert(TOKENS[Enum.PowerType.Mana] == "MANA", "Mana token")
assert(TOKENS[Enum.PowerType.ComboPoints] == "COMBO_POINTS", "ComboPoints token")
assert(TOKENS[Enum.PowerType.Runes] == "RUNES", "Runes token")
assert(TOKENS[Enum.PowerType.RunicPower] == "RUNIC_POWER", "RunicPower token")
assert(TOKENS[Enum.PowerType.HolyPower] == "HOLY_POWER", "HolyPower token")
assert(TOKENS[Enum.PowerType.ArcaneCharges] == "ARCANE_CHARGES", "ArcaneCharges token")
assert(TOKENS[Enum.PowerType.Essence] == "ESSENCE", "Essence token")

-- Token-less caller (PLAYER_REGEN_*, PLAYER_TARGET_CHANGED, direct calls,
-- secret-degraded payload): both bars, always.
do
    local p, s = RoutePowerEvent(nil, "MANA", "COMBO_POINTS")
    assert(p == true and s == true, "token-less event must refresh both")
end

-- Rogue: ENERGY tick skips the combo renderer; combo event skips primary.
do
    local p, s = RoutePowerEvent("ENERGY", "ENERGY", "COMBO_POINTS")
    assert(p == true and s == false, "ENERGY must not refresh the combo bar")
    p, s = RoutePowerEvent("COMBO_POINTS", "ENERGY", "COMBO_POINTS")
    assert(p == false and s == true, "COMBO_POINTS must not refresh primary")
end

-- DK: RUNIC_POWER spam no longer re-renders the rune bar (rune special
-- case: RUNE_POWER_UPDATE + the smooth OnUpdate timer drive it instead).
do
    local p, s = RoutePowerEvent("RUNIC_POWER", "RUNIC_POWER", "RUNES")
    assert(p == true and s == false, "RUNIC_POWER must skip the rune bar")
end

-- Brewmaster: STAGGER has no UnitPower token (nil) — the secondary keeps
-- refreshing on every power event, exactly as before routing.
do
    local p, s = RoutePowerEvent("ENERGY", "ENERGY", nil)
    assert(p == true and s == true, "unmapped secondary must always refresh")
end

-- A power type neither bar displays skips both renderers.
do
    local p, s = RoutePowerEvent("ALTERNATE", "MANA", "COMBO_POINTS")
    assert(p == false and s == false, "unrelated power must skip both")
end

print("PASS resourcebars_power_event_routing_test")
