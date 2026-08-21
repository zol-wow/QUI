local function readAll(path)
    local f = assert(io.open(path, "r"))
    local text = f:read("*a")
    f:close()
    return text
end

local source = readAll("QUI_CDM/cdm/cdm_spelldata.lua")
assert(not source:find("C_UnitAuras", 1, true))
assert(not source:find("GetAuraDataByIndex", 1, true))
assert(not source:find("EvictDeadCacheEntriesForUnit", 1, true))
assert(not source:find("ForEachReadableAura", 1, true))
assert(not source:find("QueryAuraDataByAuraInstanceID", 1, true))

print("OK cdm_spelldata_secret_eviction_gate_test")
