-- tests/cdm_resolvers_mirror_identity_hotpath_test.lua
-- Run: lua tests/cdm_resolvers_mirror_identity_hotpath_test.lua

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

assert(loadfile("modules/cdm/cdm_resolvers.lua"))("QUI", ns)

local resolveIdentity = assert(ns.CDMResolvers.ResolveBlizzardMirrorIdentity,
    "shared mirror identity resolver was not exported")

local entries = {
    {
        type = "spell",
        id = 101,
        kind = "aura",
        viewerType = "customBar",
    },
    {
        type = "spell",
        id = 202,
        kind = "cooldown",
        viewerType = "customBar",
    },
    {
        type = "spell",
        id = 999,
        kind = "aura",
        viewerType = "customBar",
        cooldownID = 9002,
    },
}

for i = 1, 100 do
    local entry = entries[(i - 1) % #entries + 1]
    assert(resolveIdentity(entry))
end

collectgarbage("collect")
local before = collectgarbage("count")
collectgarbage("stop")

for i = 1, 10000 do
    local entry = entries[(i - 1) % #entries + 1]
    assert(resolveIdentity(entry))
end

local after = collectgarbage("count")
collectgarbage("restart")
collectgarbage("collect")

local deltaKB = after - before
assert(deltaKB < 64, string.format(
    "mirror identity resolver allocated %.1f KB over 10000 hot-path calls", deltaKB))

print("OK: cdm_resolvers_mirror_identity_hotpath_test")
