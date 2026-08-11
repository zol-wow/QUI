-- tests/unit/cdm_provider_displaydata_gate_test.lua
-- Cold-boot taint gate: QUI must never be the FIRST caller into Blizzard's
-- CooldownViewerSettings data provider getters. Those getters lazily build
-- the shared displayData cache (CheckBuildDisplayData); building it on QUI's
-- stack taints the cooldownInfo/order tables that the viewer's own secure
-- RefreshData/GetCooldownIDs read at item mint -- every buff item is then
-- born isActive=false for the session (aura reads secret, the
-- DisallowTaintedAccess aura map rejects registration). /reload healed
-- because a SHOWN viewer rebuilds the cache securely before QUI touches it.
--
-- Pins:
--   * cdm_index BuildOrderedMaps and cdm_catalog GetTrackedCategorySet read
--     the provider memo fields RAW (displayDataDirty / displayData) and do
--     NOT call provider getters while the cache is unbuilt or dirty.
--   * the index bail does not latch: once the cache is built (by a secure
--     consumer), the very next call rebuilds without needing a new broker
--     invalidation.
-- Run: lua tests/unit/cdm_provider_displaydata_gate_test.lua

_G.wipe = function(tbl)
    for k in pairs(tbl) do
        tbl[k] = nil
    end
end

_G.issecretvalue = function()
    return false
end

_G.Enum = {
    CooldownViewerCategory = {
        TrackedBuff = 2,
        TrackedBar = 3,
        Essential = 0,
        Utility = 1,
        HiddenSpell = 4,
        HiddenAura = 5,
    },
}

_G.CreateFrame = function()
    return {
        RegisterEvent = function() end,
        SetScript = function() end,
    }
end
_G.EventRegistry = {
    RegisterCallback = function() end,
}

_G.C_CooldownViewer = {
    IsCooldownViewerAvailable = function()
        return true
    end,
    GetCooldownViewerCategorySet = function()
        return { 88 }
    end,
    GetCooldownViewerCooldownInfo = function(cooldownID)
        if cooldownID == 88 then
            return {
                spellID = 12345,
                overrideSpellID = nil,
                overrideTooltipSpellID = nil,
            }
        end
        return nil
    end,
}

local ns = {}
-- Task 45f: cdm_catalog.lua routes discarded-result pcall guards through
-- ns.SafeCall. Additive stub (T1d/T1e precedent) — bare pcall passthrough.
ns.SafeCall = function(_policy, fn, ...) return pcall(fn, ...) end
ns.SafeCallMethod = function(_policy, obj, name, ...) return pcall(function(...) return obj[name](obj, ...) end, ...) end
ns.SafeCallMethodIfPresent = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")

local indexChunk = loadChunk("QUI_CDM/cdm/cdm_index.lua", "cdm_index.lua")
indexChunk("QUI", ns)
local catalogChunk = loadChunk("QUI_CDM/cdm/cdm_catalog.lua", "cdm_catalog.lua")
catalogChunk("QUI", ns)

ns.CDMSources = {
    QueryBaseSpell = function(spellID)
        return spellID
    end,
    QuerySpellInfo = function()
        return nil
    end,
    QueryOverrideSpell = function(spellID)
        return spellID
    end,
}

local index = assert(ns.CDMIndex, "CDMIndex table was not exported")
local catalog = assert(ns.CDMCatalog, "CDMCatalog table was not exported")

---------------------------------------------------------------------------
-- Provider stub with switchable built-ness. getterCalls counts every touch
-- of a lazily-building getter -- the gate's job is to keep this at zero
-- until the cache reads as built.
---------------------------------------------------------------------------
local getterCalls = 0
local providerStub = {
    displayDataDirty = true,
    displayData = nil,
    GetLayoutManager = function()
        return {}
    end,
    GetOrderedCooldownIDsForCategory = function(_, category)
        getterCalls = getterCalls + 1
        if category == 0 then
            return { 88 }
        end
        return {}
    end,
}
_G.CooldownViewerSettings = {
    GetDataProvider = function()
        return providerStub
    end,
}

-- 1) dirty cache: index ordered maps must stay empty, getters untouched.
local gated = index.GetOrderedSpellMap()
assert(type(gated) == "table", "gated ordered map should still be a table")
assert(next(gated) == nil, "ordered map must stay empty while provider cache is dirty")
assert(getterCalls == 0, "index must not call provider getters while cache is dirty")

-- 2) fresh provider (both memo fields nil) is unbuilt too.
providerStub.displayDataDirty = nil
assert(next(index.GetOrderedSpellMap()) == nil,
    "ordered map must stay empty while provider displayData is nil")
assert(getterCalls == 0, "index must not call provider getters while displayData is nil")

-- 3) catalog tracked-set read is gated the same way.
local ids, ready = catalog.GetTrackedCategorySet(0, true)
assert(ids == nil and ready == false,
    "catalog must report not-ready while provider cache is unbuilt")
assert(getterCalls == 0, "catalog must not call provider getters while cache is unbuilt")

-- 4) built cache: the next index call rebuilds WITHOUT a new invalidation
--    (the gate bail must not latch the ordered-map version).
providerStub.displayDataDirty = false
providerStub.displayData = {}
local built = index.GetOrderedSpellMap()
assert(built[12345] and built[12345].cooldownID == 88,
    "ordered map should populate on the first call after the cache is built")
assert(getterCalls > 0, "provider getter should be consumed once the cache is built")

local callsAfterBuild = getterCalls
assert(index.GetOrderedSpellMap() == built, "built ordered map should be cached again")
assert(getterCalls == callsAfterBuild, "cached ordered map should not re-walk the provider")

-- 5) catalog serves the tracked set once built.
local builtIds, builtReady = catalog.GetTrackedCategorySet(0, true)
assert(builtReady == true and type(builtIds) == "table" and builtIds[1] == 88,
    "catalog should serve the provider tracked set once the cache is built")

-- 6) re-dirtied cache (SPELLS_CHANGED etc. MarkDirty): index keeps serving
--    the STALE maps rather than rebuilding through a dirty provider.
local callsBeforeRedirty = getterCalls
providerStub.displayDataDirty = true
index.Notify("manual")
local stale = index.GetOrderedSpellMap()
assert(stale[12345] and stale[12345].cooldownID == 88,
    "index should keep serving stale ordered maps while the provider re-dirties")
assert(getterCalls == callsBeforeRedirty,
    "index must not rebuild through a dirty provider after invalidation")

print("OK: cdm_provider_displaydata_gate_test")
