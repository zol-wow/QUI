local function readAll(path)
    local f = assert(io.open(path, "r"))
    local text = f:read("*a")
    f:close()
    return text
end

local source = readAll("QUI_CDM/cdm/cdm_sources.lua")
for _, name in ipairs({
    "AuraMemo",
    "InvalidateAuraMemo",
    "SetupAuraMemo",
    "C_UnitAuras",
}) do
    assert(not source:find(name, 1, true), "removed aura memo bridge: " .. name)
end

print("OK cdm_sources_aura_memo_test")
