local function readAll(path)
    local f = assert(io.open(path, "r"))
    local text = f:read("*a")
    f:close()
    return text
end

local source = readAll("QUI_CDM/cdm/cdm_spelldata.lua")
assert(not source:find("QueryAuraApplicationDisplayCount", 1, true))
assert(not source:find("QueryAuraDataByAuraInstanceID", 1, true))
assert(not source:find("QueryAuraDataBySpellName", 1, true))
assert(not source:find("QueryUnitAuras", 1, true))
assert(source:find("GetDisplayableAuraApplications", 1, true))

print("OK cdm_spelldata_stack_resolution_test")
