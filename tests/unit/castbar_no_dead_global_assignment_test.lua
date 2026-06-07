-- tests/unit/castbar_no_dead_global_assignment_test.lua
-- Run: lua tests/unit/castbar_no_dead_global_assignment_test.lua
--
-- castbar.lua must NOT assign _G.QUI_Castbars. It is a dead write: unitframes.lua
-- loads after castbar.lua and overwrites the global with QUI_UF.castbars (the
-- table every castbar frame is actually registered into; unitframes.lua re-points
-- QUI_Castbar.castbars at it too). castbar's assignment pointed at an orphaned
-- initial table that nothing reads at runtime. Reads of the global (castbar.lua
-- and cdm/hud_visibility.lua) all happen at runtime and see the unitframes table.

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return (data:gsub("\r\n", "\n"))
end

local castbar = readAll("QUI_UnitFrames/unitframes/castbar.lua")
local unitframes = readAll("QUI_UnitFrames/unitframes/unitframes.lua")

assert(not castbar:find("_G.QUI_Castbars = ", 1, true),
    "castbar.lua must not assign _G.QUI_Castbars (dead write overwritten by unitframes.lua)")
assert(unitframes:find("_G.QUI_Castbars = QUI_UF.castbars", 1, true),
    "unitframes.lua must remain the single owner/assigner of the _G.QUI_Castbars global")
assert(castbar:find("_G.QUI_Castbars and _G.QUI_Castbars", 1, true),
    "castbar.lua should still READ _G.QUI_Castbars (only the dead assignment is removed)")

print("castbar_no_dead_global_assignment_test: OK")
