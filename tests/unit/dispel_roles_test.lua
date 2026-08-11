-- tests/unit/dispel_roles_test.lua
-- Run: lua5.1 tests/unit/dispel_roles_test.lua
--
-- Test dispel school capability mapping: class->schools by spec

local ns = dofile("tools/_addon_env.lua").LoadCore()
local DR = ns.QUI_DispelRoles
local failures=0; local function check(n,ok,d) if ok then print("  ok  "..n) else failures=failures+1; print("FAIL  "..n.." "..(d or "")) end end
do
    local hpal = DR.SchoolsForClassSpec("PALADIN", 65)
    check("hpal magic", hpal.Magic == true)
    check("hpal disease", hpal.Disease == true and hpal.Poison == true)
    local retpal = DR.SchoolsForClassSpec("PALADIN", 70)
    check("retpal poison disease", retpal.Poison == true and retpal.Disease == true)
    check("retpal no magic", retpal.Magic == nil)
    local mage = DR.SchoolsForClassSpec("MAGE", nil)
    check("mage curse", mage.Curse == true)
    local rogue = DR.SchoolsForClassSpec("ROGUE", nil)
    check("rogue none", next(rogue) == nil)
    local disc = DR.SchoolsForClassSpec("PRIEST", 256)
    check("disc magic disease", disc.Magic == true and disc.Disease == true)
    -- Purify Disease is the ALL-spec priest dispel; Purify (Magic) is
    -- heal-spec only. Shadow must be Disease-only, never Magic.
    local shadow = DR.SchoolsForClassSpec("PRIEST", 258)
    check("shadow disease only", shadow.Disease == true and shadow.Magic == nil)
    local shaman_resto = DR.SchoolsForClassSpec("SHAMAN", 264)
    check("shaman_resto curse magic", shaman_resto.Curse == true and shaman_resto.Magic == true)
    local druid_resto = DR.SchoolsForClassSpec("DRUID", 105)
    check("druid_resto curse poison magic", druid_resto.Curse == true and druid_resto.Poison == true and druid_resto.Magic == true)
    local monk_mw = DR.SchoolsForClassSpec("MONK", 270)
    check("monk_mw poison disease magic", monk_mw.Poison == true and monk_mw.Disease == true and monk_mw.Magic == true)
    -- Expunge (Poison) is the ALL-spec evoker dispel; Naturalize adds Magic
    -- for Preservation. Disease is Cauterizing Flame — a talent, not a spec
    -- capability, so it must NOT appear here.
    local evoker_pres = DR.SchoolsForClassSpec("EVOKER", 1468)
    check("evoker_pres magic poison", evoker_pres.Magic == true and evoker_pres.Poison == true and evoker_pres.Disease == nil)
    local evoker_dev = DR.SchoolsForClassSpec("EVOKER", 1467)
    check("evoker_dev poison only", evoker_dev.Poison == true and evoker_dev.Magic == nil)
end
print("dispel_roles_test "..(failures==0 and "OK" or "FAILED")); os.exit(failures==0 and 0 or 1)
