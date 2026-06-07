-- tests/unit/cdm_resolvers_mirror_identity_test.lua
-- Run: lua tests/unit/cdm_resolvers_mirror_identity_test.lua

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
    ["essential:70759"] = {
        cooldownID = 70759,
        viewerCategory = "essential",
        spellID = 77575,
        overrideSpellID = 77575,
    },
    ["utility:28527"] = {
        cooldownID = 28527,
        viewerCategory = "utility",
        spellID = 48707,
        overrideSpellID = 48707,
    },
    ["buff:9103"] = {
        cooldownID = 9103,
        viewerCategory = "buff",
        spellID = 395152,
        overrideTooltipSpellID = 395296,
        linkedSpellIDs = { 395296 },
    },
}

local bySpell = {
    buff = {
        [101] = 9001,
        [301] = 9001,
        [777] = 9103,
        [395152] = 9103,
        [395296] = 9103,
    },
    trackedBar = {
        [102] = 9002,
    },
    utility = {
        [202] = 8002,
        [48707] = 28527,
    },
    essential = {
        [77575] = 70759,
    },
}

local directBySpell = {
    buff = {
        [101] = 9001,
        [301] = 9001,
        [395296] = 9103,
    },
    trackedBar = {
        [102] = 9002,
    },
    utility = {
        [202] = 8002,
        [48707] = 28527,
    },
    essential = {
        [77575] = 70759,
    },
}

local ns = {
    Helpers = {},
    CDMSources = {
        QueryOverrideSpell = function() return nil end,
    },
    CDMBlizzMirror = {
        GetDirectCooldownIDForViewer = function(spellID, viewerCategory)
            local cat = directBySpell[viewerCategory]
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
local resolveIdentityState = assert(resolvers.ResolveBlizzardMirrorIdentityState,
    "shared mirror identity state resolver was not exported")

local identity = resolveIdentityState({
    type = "spell",
    id = 101,
    kind = "aura",
    viewerType = "customBar",
})

assert(identity and identity.cooldownID == 9001,
    "custom aura identity should expose a named cooldownID")
assert(identity and identity.category == "buff",
    "custom aura identity should expose its accepted category")
assert(identity and identity.state == states["buff:9001"],
    "custom aura identity should expose the accepted mirror state")
assert(identity and identity.strictAuraBinding == true,
    "custom aura identity should expose strict aura binding")
assert(identity and identity.source == "entry",
    "custom aura identity should report entry-derived binding")
assert(identity and identity.entryType == "spell",
    "custom aura identity should expose the normalized entry type")

identity = resolveIdentityState({
    type = "spell",
    id = 102,
    kind = "aura",
    viewerType = "customBar",
})

assert(identity and identity.cooldownID == 9002,
    "fallback aura identity should expose a named cooldownID")
assert(identity and identity.category == "trackedBar",
    "fallback aura identity should expose the accepted fallback category")
assert(identity and identity.viewerCategory == nil,
    "custom-bar aura identity should not invent a native viewer category")

identity = resolveIdentityState({
    type = "spell",
    id = 395152,
    kind = "aura",
    viewerType = "buff",
})

assert(identity and identity.cooldownID == 9103,
    "existing source-ability aura entries should resolve through mirror-backed aliases")
assert(identity and identity.category == "buff",
    "source-ability aura aliases should keep the accepted aura mirror category")

identity = resolveIdentityState({
    type = "spell",
    id = 777,
    kind = "aura",
    viewerType = "buff",
})

assert(identity == nil,
    "broad aura aliases should not bind unless the mirror state carries the entry identity")

identity = resolveIdentityState({
    type = "spell",
    id = 202,
    kind = "cooldown",
    viewerType = "customBar",
})

assert(identity and identity.cooldownID == 8002,
    "custom cooldown identity should expose a named cooldownID")
assert(identity and identity.category == "utility",
    "custom cooldown identity should expose its accepted category")
assert(identity and identity.strictAuraBinding == false,
    "custom cooldown identity should not use strict aura binding")

identity = resolveIdentityState({
    type = "aura",
    id = 101,
    viewerType = "customIcon",
})

assert(identity and identity.cooldownID == 9001,
    "entry type aura should resolve through aura categories")
assert(identity and identity.category == "buff",
    "entry type aura should keep the aura mirror category")

identity = resolveIdentityState({
    type = "cooldown",
    id = 202,
    viewerType = "customIcon",
})

assert(identity and identity.cooldownID == 8002,
    "entry type cooldown should resolve through cooldown categories")
assert(identity and identity.category == "utility",
    "entry type cooldown should keep the cooldown mirror category")

identity = resolveIdentityState({
    type = "spell",
    id = 999,
    kind = "aura",
    viewerType = "customBar",
    cooldownID = 9002,
})

assert(identity and identity.cooldownID == 9002,
    "explicit custom aura identity should expose a named cooldownID")
assert(identity and identity.category == "trackedBar",
    "explicit custom aura identity should expose the accepted category")
assert(identity and identity.source == "entry-cooldownID",
    "explicit custom aura identity should report cooldownID-derived binding")

identity = resolveIdentityState({
    type = "spell",
    id = 202,
    kind = "aura",
    viewerType = "customBar",
})

assert(identity == nil,
    "rejected aura entry should not expose a mirror identity state")

identity = resolveIdentityState({
    type = "spell",
    id = 77575,
    spellID = 77575,
    kind = "cooldown",
    viewerType = "essential",
    cooldownID = 28527,
    linkedSpellIDs = { 48707 },
})

assert(identity and identity.cooldownID == 70759,
    "mismatched explicit cooldownID should not bind Outbreak to AMS")
assert(identity and identity.category == "essential",
    "mismatched explicit cooldownID should fall back to the entry's own category")

identity = resolveIdentityState({
    type = "item",
    id = 101,
})

assert(identity == nil,
    "unsupported entry types should not expose a mirror identity state")

local state = resolvers.ResolveCooldownState({
    entry = {
        type = "spell",
        id = 77575,
        spellID = 77575,
        kind = "cooldown",
        viewerType = "essential",
        linkedSpellIDs = { 48707 },
    },
    runtimeSpellID = 77575,
    mirrorCooldownID = 28527,
    mirrorCategory = "utility",
    containerKey = "essential",
    useBuffSwipe = true,
})

assert(state and state.mirrorCooldownID == 70759,
    "stale icon mirror binding should be rejected during resolved state resolution")
assert(state and state.mirrorCategory == "essential",
    "stale icon mirror binding should fall back to the entry's own render category")

print("OK: cdm_resolvers_mirror_identity_test")
