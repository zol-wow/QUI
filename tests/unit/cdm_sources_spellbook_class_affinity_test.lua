-- tests/unit/cdm_sources_spellbook_class_affinity_test.lua
-- Run: lua tests/unit/cdm_sources_spellbook_class_affinity_test.lua
--
-- Class applicability includes hidden, future, flyout, and off-spec player
-- spellbook lanes. It is deliberately broader than current knownness.

_G.issecretvalue = function() return false end

local queryArgs
_G.C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 4 end,
    FindSpellBookSlotForSpell = function(...)
        queryArgs = { ... }
        if queryArgs[1] == 101 then return 7, 0 end
        return nil
    end,
}

local ns = {}
assert(loadfile("QUI_CDM/cdm/cdm_sources.lua"))("QUI", ns)
local sources = assert(ns.CDMSources, "CDMSources table should be exported")

assert(sources.QuerySpellBookClassAffinity(101) == true,
    "a spell in any player spellbook lane should apply to the current class")
assert(queryArgs[2] == true, "hidden spellbook rows must be included")
assert(queryArgs[3] == true, "flyout spellbook rows must be included")
assert(queryArgs[4] == true, "future/unlearned spellbook rows must be included")
assert(queryArgs[5] == true, "off-spec spellbook rows must be included")

assert(sources.QuerySpellBookClassAffinity(201) == false,
    "a definitive player-spellbook miss should classify a foreign-class spell")

_G.C_SpellBook = nil
print("OK: cdm_sources_spellbook_class_affinity_test")
