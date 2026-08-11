-- tests/unit/map_teleports_cooldown_secret_safe_test.lua
-- Run: lua tests/unit/map_teleports_cooldown_secret_safe_test.lua
--
-- C_Spell.GetSpellCooldown is SecretWhenCooldownsRestricted
-- (SpellDocumentation.lua:252) and CooldownFrame_Set compares its fields
-- (start > 0, Cooldown.lua:2) — that path throws when the map is refreshed
-- under cooldown restriction. The teleport panel must use the duration-object
-- carrier instead: GetSpellCooldownDuration → SetCooldownFromDurationObject
-- (repo policy: preferredSecretSafeSetter, cdm_blizzard_reference.lua:63).

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local source = readFile("modules/dungeon/map_teleports.lua")

assert(source:find("GetSpellCooldownDuration", 1, true),
    "map teleports must fetch cooldowns as duration objects")
assert(source:find("SetCooldownFromDurationObject", 1, true),
    "map teleports must sink cooldowns via SetCooldownFromDurationObject")
assert(not source:find("CooldownFrame_Set(", 1, true),
    "CooldownFrame_Set compares secret-capable fields and must not be used here")
assert(not source:find("C_Spell.GetSpellCooldown(", 1, true),
    "raw GetSpellCooldown fields must not be read here")

print("PASS map_teleports_cooldown_secret_safe_test")
