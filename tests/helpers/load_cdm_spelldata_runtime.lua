return function(ns)
    ns = ns or {}
    local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")

    local existingShared = ns.CDMShared or {}
    if not existingShared.GetBuiltinContainerEntryKind then
        local sharedNS = {
            Helpers = ns.Helpers,
            Addon = ns.Addon,
        }
        loadChunk("QUI_CDM/cdm/cdm_shared.lua", "cdm_shared.lua")("QUI", sharedNS)
        for key, value in pairs(sharedNS.CDMShared or {}) do
            if existingShared[key] == nil then
                existingShared[key] = value
            end
        end
        ns.CDMShared = existingShared
    end

    if not ns.CDMAuraCatalog then
        loadChunk("QUI_CDM/cdm/cdm_spelldata.lua", "cdm_aura_catalog.lua")("QUI", ns)
    end
    if not ns.CDMAuraRuntime then
        loadChunk("QUI_CDM/cdm/cdm_spelldata.lua", "cdm_aura_runtime.lua")("QUI", ns)
    end

    return ns
end
