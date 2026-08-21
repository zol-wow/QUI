local function readAll(path)
    local f = assert(io.open(path, "r"))
    local text = f:read("*a")
    f:close()
    return text
end

local source = readAll("QUI_CDM/cdm/cdm_spelldata.lua")
assert(not source:find("QueryAuraHasExpirationTime", 1, true))
assert(not source:find("QueryAuraDuration", 1, true))
assert(not source:find("QueryAuraDataByAuraInstanceID", 1, true))
assert(source:find("GetReadableAuraDurationState", 1, true))

print("OK cdm_spelldata_secret_expiration_test")
