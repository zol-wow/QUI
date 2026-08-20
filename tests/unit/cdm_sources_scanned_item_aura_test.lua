local function readAll(path)
    local f = assert(io.open(path, "r"))
    local text = f:read("*a")
    f:close()
    return text
end

local source = readAll("QUI_CDM/cdm/cdm_sources.lua")
assert(source:find("QueryScannedItemAuraInfo", 1, true))
assert(not source:find("C_UnitAuras", 1, true))
assert(not source:find("QueryAuraDuration", 1, true))

print("OK cdm_sources_scanned_item_aura_test")
