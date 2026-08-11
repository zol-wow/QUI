-- tests/unit/actionbars_pet_overlay_namespace_test.lua
-- Run: lua tests/unit/actionbars_pet_overlay_namespace_test.lua
--
-- IsSpellOverlayed lives in C_SpellActivationOverlay
-- (SpellActivationOverlayDocumentation.lua:5,11); C_Spell.IsSpellOverlayed
-- does not exist, so the guarded call was permanently false and pet proc
-- glows never showed.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local source = readFile("QUI_ActionBars/actionbars/actionbars_petstance.lua")

assert(source:find("C_SpellActivationOverlay.IsSpellOverlayed", 1, true),
    "pet glow must query C_SpellActivationOverlay.IsSpellOverlayed")
assert(not source:find("C_Spell.IsSpellOverlayed", 1, true),
    "C_Spell.IsSpellOverlayed does not exist")

print("PASS actionbars_pet_overlay_namespace_test")
