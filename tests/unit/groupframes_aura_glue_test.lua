-- tests/unit/groupframes_aura_glue_test.lua
-- Run: lua tests/unit/groupframes_aura_glue_test.lua
local function read(p) local h = assert(io.open(p, "rb")); local s = h:read("*a"); h:close(); return s end
local src = read("QUI_GroupFrames/groupframes/groupframes_auras.lua")
local fails = 0
local function check(n, ok) if ok then print("  ok  " .. n) else fails = fails + 1; print("FAIL  " .. n) end end

check("references the model module", src:find("QUI_GroupFramesAuraModel", 1, true) ~= nil)
check("calls ActiveElementsForSpec", src:find("ActiveElementsForSpec", 1, true) ~= nil)
check("calls PopulateElementMatches", src:find("PopulateElementMatches", 1, true) ~= nil)
check("defines BuildElementRenderList", src:find("BuildElementRenderList", 1, true) ~= nil)
if fails > 0 then error(fails .. " failures") end
print("ALL PASS")
