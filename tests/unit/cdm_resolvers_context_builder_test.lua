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

local states = {
    ["buff:9001"] = { cooldownID = 9001, viewerCategory = "buff" },
    ["trackedBar:9002"] = { cooldownID = 9002, viewerCategory = "trackedBar" },
    ["utility:8002"] = { cooldownID = 8002, viewerCategory = "utility" },
}

local bySpell = {
    buff = {
        [101] = 9001,
    },
    trackedBar = {
        [102] = 9002,
    },
    utility = {
        [202] = 8002,
    },
}

local ns = {
    Helpers = {},
    CDMSources = {
        QueryOverrideSpell = function() return nil end,
    },
    CDMBlizzMirror = {
        GetDirectCooldownIDForViewer = function(spellID, viewerCategory)
            local cat = bySpell[viewerCategory]
            return cat and cat[spellID] or nil
        end,
        GetCooldownIDForViewer = function(spellID, viewerCategory)
            local cat = bySpell[viewerCategory]
            return cat and cat[spellID] or nil
        end,
        GetStateByCooldownID = function(cooldownID, viewerCategory)
            return states[tostring(viewerCategory) .. ":" .. tostring(cooldownID)]
        end,
        HasChildForCooldownID = function(cooldownID, viewerCategory)
            return states[tostring(viewerCategory) .. ":" .. tostring(cooldownID)] ~= nil
        end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_runtime_queries.lua", "cdm_runtime_queries.lua")("QUI", ns)
loadChunk("QUI_CDM/cdm/cdm_resolvers.lua", "cdm_resolvers.lua")("QUI", ns)

local resolvers = assert(ns.CDMResolvers, "CDMResolvers table was not exported")
local buildContext = assert(resolvers.BuildCooldownStateContext,
    "cooldown state context builder was not exported")

local icon = {
    _blizzMirrorCooldownID = 8002,
    _blizzMirrorCategory = "utility",
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
    cachedMirrorState = states["utility:8002"],
    cachedMirrorSourceID = "mirror:8002:1",
    useBuffSwipe = false,
    skipAuraPhase = true,
})

assert(context == icon._activityCooldownStateContext,
    "builder should store context on the requested owner key")
assert(context.runtimeSpellID == 202,
    "builder should carry runtime spell identity")
assert(context.mirrorCooldownID == 8002,
    "frame mirror identity should be preserved when present")
assert(context.mirrorCategory == "utility",
    "frame mirror category should be preserved when present")
assert(context.cachedMirrorState == states["utility:8002"],
    "cached icon mirror state should be carried into resolver context")
assert(context.cachedMirrorSourceID == "mirror:8002:1",
    "cached icon mirror source key should be carried into resolver context")
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
    mirrorIdentityPolicy = "frame-or-entry",
    useBuffSwipe = true,
})

assert(context.mirrorCooldownID == 9001,
    "missing frame mirror identity should resolve through shared entry identity")
assert(context.mirrorCategory == "buff",
    "missing frame mirror category should resolve through shared entry identity")
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
    cooldownID = 7777,
    blizzardMirrorCategory = "trackedBar",
}, 999, {
    mirrorIdentityPolicy = "entry-or-fallback",
    fallbackContainerKey = "trackedBar",
})

assert(context == bar._cooldownStateContext,
    "default context key should be used for renderer frames")
assert(context.mirrorCooldownID == 7777,
    "bar policy should fall back to explicit entry cooldownID when no mirror identity exists")
assert(context.mirrorCategory == "trackedBar",
    "bar policy should normalize fallback entry mirror category")
assert(context.containerKey == "customBar",
    "entry viewerType should win over fallback container key")

context = buildContext(bar, nil, nil, {
    mirrorIdentityPolicy = "entry-or-fallback",
    fallbackContainerKey = "trackedBar",
})

assert(context.entry == nil,
    "builder should clear stale entry")
assert(context.runtimeSpellID == nil,
    "builder should clear stale runtime spell identity")
assert(context.mirrorCooldownID == nil,
    "builder should clear stale mirror cooldownID")
assert(context.mirrorCategory == nil,
    "builder should clear stale mirror category")
assert(context.cachedMirrorState == nil,
    "builder should clear stale cached mirror state")
assert(context.cachedMirrorSourceID == nil,
    "builder should clear stale cached mirror source key")
assert(context.containerKey == "trackedBar",
    "fallback container key should apply when entry is absent")
assert(context.useBuffSwipe == nil,
    "builder should clear stale buff-swipe policy")
assert(context.skipAuraPhase == false,
    "builder should clear stale skip-aura policy")

print("OK: cdm_resolvers_context_builder_test")
