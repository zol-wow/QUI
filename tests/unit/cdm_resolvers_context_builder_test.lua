-- tests/unit/cdm_resolvers_context_builder_test.lua
-- Run: lua tests/unit/cdm_resolvers_context_builder_test.lua

function InCombatLockdown() return false end
function geterrorhandler() return function(err) error(err) end end
function CreateFrame()
    return {
        RegisterEvent = function() end,
        RegisterUnitEvent = function() end,
        SetScript = function() end,
    }
end

local ns = {
    Helpers = {},
    CDMSources = {
        QueryOverrideSpell = function() return nil end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_runtime_queries.lua", "cdm_runtime_queries.lua")("QUI", ns)
loadChunk("QUI_CDM/cdm/cdm_resolvers.lua", "cdm_resolvers.lua")("QUI", ns)

local resolvers = assert(ns.CDMResolvers, "CDMResolvers table was not exported")
local buildContext = assert(resolvers.BuildCooldownStateContext,
    "cooldown state context builder was not exported")

local icon = {
    _totemSlot = 3,
}

local context = buildContext(icon, {
    type = "spell",
    id = 202,
    spellID = 202,
    kind = "cooldown",
    viewerType = "essential",
}, 202, {
    contextKey = "_activityCooldownStateContext",
    containerKey = "utility",
    useBuffSwipe = false,
    skipAuraPhase = true,
})

assert(context == icon._activityCooldownStateContext,
    "builder should store context on the requested owner key")
assert(context.runtimeSpellID == 202,
    "builder should carry runtime spell identity")
assert(context.containerKey == "utility",
    "explicit container key should win")
assert(context.totemSlot == 3,
    "owner totem slot should be copied by default")
assert(context.useBuffSwipe == false,
    "renderer buff-swipe policy should be copied")
assert(context.skipAuraPhase == true,
    "renderer skip-aura policy should be normalized")

context = buildContext({}, {
    type = "spell",
    id = 101,
    kind = "aura",
    viewerType = "customBar",
}, 101, {
    useBuffSwipe = true,
})

assert(context.containerKey == "customBar",
    "entry viewerType should be the default container key")
assert(context.useBuffSwipe == true,
    "truthy renderer buff-swipe policy should be copied")
assert(context.skipAuraPhase == false,
    "missing skip-aura policy should normalize to false")

local bar = {}
context = buildContext(bar, {
    type = "spell",
    id = 999,
    kind = "aura",
    viewerType = "customBar",
}, 999, {
    fallbackContainerKey = "trackedBar",
})

assert(context == bar._cooldownStateContext,
    "default context key should be used for renderer frames")
assert(context.containerKey == "customBar",
    "entry viewerType should win over fallback container key")

context = buildContext(bar, nil, nil, {
    fallbackContainerKey = "trackedBar",
})

assert(context.entry == nil,
    "builder should clear stale entry")
assert(context.runtimeSpellID == nil,
    "builder should clear stale runtime spell identity")
assert(context.containerKey == "trackedBar",
    "fallback container key should apply when entry is absent")
assert(context.useBuffSwipe == nil,
    "builder should clear stale buff-swipe policy")
assert(context.skipAuraPhase == false,
    "builder should clear stale skip-aura policy")

print("OK: cdm_resolvers_context_builder_test")
