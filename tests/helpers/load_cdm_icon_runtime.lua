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

    if not ns.CDMAuraRuntime then
        loadChunk("QUI_CDM/cdm/cdm_spelldata.lua", "cdm_aura_runtime.lua")("QUI", ns)
    end

    if not ns.CDMRuntimeQueries then
        ns.CDMSources = ns.CDMSources or {}
        ns.CDMSources.QuerySpellCooldown = ns.CDMSources.QuerySpellCooldown or function() return nil end
        ns.CDMSources.QuerySpellCharges = ns.CDMSources.QuerySpellCharges or function() return nil end
        ns.CDMSources.QuerySpellCooldownDuration = ns.CDMSources.QuerySpellCooldownDuration or function() return nil end
        ns.CDMSources.QuerySpellChargeDuration = ns.CDMSources.QuerySpellChargeDuration or function() return nil end
        ns.CDMSources.QueryOverrideSpell = ns.CDMSources.QueryOverrideSpell or function() return nil end
        ns.CDMSources.QuerySpellDisplayCount = ns.CDMSources.QuerySpellDisplayCount or function() return nil end
        ns.CDMSources.QuerySpellCount = ns.CDMSources.QuerySpellCount or function() return nil end
        loadChunk("QUI_CDM/cdm/cdm_runtime_queries.lua", "cdm_runtime_queries.lua")("QUI", ns)
    end

    if not ns.CDMIconStackText then
        loadChunk("QUI_CDM/cdm/cdm_icon_renderer.lua", "cdm_icon_stack_text.lua")("QUI", ns)
    end
    if not ns.CDMIconStackPolicy then
        loadChunk("QUI_CDM/cdm/cdm_icon_renderer.lua", "cdm_icon_stack_policy.lua")("QUI", ns)
    end
    if not ns.CDMIconMirrorIndex then
        loadChunk("QUI_CDM/cdm/cdm_icon_renderer.lua", "cdm_icon_mirror_index.lua")("QUI", ns)
    end
    if not ns.CDMIconRuntimeRefresh then
        loadChunk("QUI_CDM/cdm/cdm_icon_renderer.lua", "cdm_icon_runtime_refresh.lua")("QUI", ns)
    end
    if not ns.CDMIconUpdateScheduler then
        loadChunk("QUI_CDM/cdm/cdm_icon_renderer.lua", "cdm_icon_update_scheduler.lua")("QUI", ns)
    end
    if not ns.CDMIconRefreshBatch then
        loadChunk("QUI_CDM/cdm/cdm_icon_renderer.lua", "cdm_icon_refresh_batch.lua")("QUI", ns)
    end
    if not ns.CDMIconRefreshWalker then
        loadChunk("QUI_CDM/cdm/cdm_icon_renderer.lua", "cdm_icon_refresh_walker.lua")("QUI", ns)
    end
    if not ns.CDMIconItemVisualPolicy then
        loadChunk("QUI_CDM/cdm/cdm_icon_renderer.lua", "cdm_icon_item_visual_policy.lua")("QUI", ns)
    end
    if not ns.CDMIconVisibilityPolicy then
        loadChunk("QUI_CDM/cdm/cdm_icon_renderer.lua", "cdm_icon_visibility_policy.lua")("QUI", ns)
    end
    if not ns.CDMIconRangePolicy then
        loadChunk("QUI_CDM/cdm/cdm_icon_renderer.lua", "cdm_icon_range_policy.lua")("QUI", ns)
    end
    if not ns.CDMIconCooldownPolicy then
        loadChunk("QUI_CDM/cdm/cdm_icon_renderer.lua", "cdm_icon_cooldown_policy.lua")("QUI", ns)
    end
    if not ns.CDMIconCustomBarPolicy then
        loadChunk("QUI_CDM/cdm/cdm_icon_renderer.lua", "cdm_icon_custom_bar_policy.lua")("QUI", ns)
    end

    return ns
end
