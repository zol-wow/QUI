-- tests/unit/aura_element_border_color_test.lua
-- Run: lua5.1 tests/unit/aura_element_border_color_test.lua
--
-- borderColor is an OPTIONAL per-element field (absent = theme border), so it
-- must NOT be seeded on new elements (raw-SV absent-key rule, same contract as
-- the boolean gates). AuraSkin is never loaded headless, so the skin-side read
-- is asserted by source scan (established pattern, see
-- buffborders_no_secureauraheader_test.lua). dedupeDefensives absence is
-- already pinned by aura_elements_model_test.lua (Wave 4) — not re-checked.

local ns = dofile("tools/_addon_env.lua").LoadCore()
local E = ns.AuraElements

local failures = 0
local function check(name, ok, detail)
    if ok then print(("  ok  %s"):format(name))
    else failures = failures + 1; print(("FAIL  %s  %s"):format(name, detail or "")) end
end

local strip = E.NewFilterStripElement("HELPFUL")
check("new strip has NO borderColor (absent = theme)", strip.borderColor == nil,
    tostring(strip.borderColor))

-- NormalizeElement must leave a stored borderColor alone (no heal/strip).
local stored = E.NewFilterStripElement("HELPFUL")
stored.borderColor = { 0, 0.8, 0, 1 }
E.NormalizeElement(stored)
check("NormalizeElement preserves borderColor", stored.borderColor
    and stored.borderColor[2] == 0.8, "stripped or mutated")

-- Skin-side read (source scan; AuraSkin needs live frame APIs).
local f = io.open("core/aura_skin.lua", "r")
local src = f:read("*a"); f:close()
check("styleButton reads profile.borderColor", src:find("profile.borderColor", 1, true) ~= nil)

-- Element → layout-profile passthrough: styleButton receives G.ElementProfile's
-- output, NOT the element — an explicit field list that silently drops any key
-- it doesn't map. borderColor must survive the mapping or the skin read above
-- is dead code (final-review C1: the green defensives border shipped no-op).
local G = ns.AuraGlue
check("AuraGlue.ElementProfile passes borderColor through", (function()
    if not (G and G.ElementProfile) then return false end
    local p = G.ElementProfile(stored)
    return type(p.borderColor) == "table" and p.borderColor[2] == 0.8
end)(), "dropped by the profile mapper")
check("ElementProfile leaves borderColor ABSENT when element has none", (function()
    if not (G and G.ElementProfile) then return false end
    return G.ElementProfile(strip).borderColor == nil
end)(), "invented a value")

if failures > 0 then os.exit(1) end
print("aura_element_border_color_test: all checks passed")
