local function readAll(path)
    local f = assert(io.open(path, "r"))
    local text = f:read("*a")
    f:close()
    return text
end

local source = readAll("QUI_CDM/cdm/cdm_sources.lua")
assert(not source:find("C_UnitAuras", 1, true))
for _, name in ipairs({
    "QueryAuraDuration",
    "QueryAuraDataByAuraInstanceID",
    "QueryAuraHasExpirationTime",
    "QueryAuraFilteredOutByInstanceID",
    "QueryAuraApplicationDisplayCount",
    "QueryUnitAuraBySpellID",
    "QueryPlayerAuraBySpellID",
    "QueryAuraDataBySpellID",
    "QueryCooldownAuraBySpellID",
    "QueryAuraDataBySpellName",
    "QueryUnitAuras",
}) do
    assert(not source:find(name, 1, true), "removed aura bridge export: " .. name)
end

print("OK cdm_sources_secret_aura_gate_test")
