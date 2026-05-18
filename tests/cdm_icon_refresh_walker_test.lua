-- tests/cdm_icon_refresh_walker_test.lua
-- Run: lua tests/cdm_icon_refresh_walker_test.lua

local ns = {}
assert(loadfile("modules/cdm/cdm_icon_refresh_walker.lua"))("QUI", ns)
local module = assert(ns.CDMIconRefreshWalker, "icon refresh walker module should be exported")

local fullA = { name = "full-a", _spellEntry = { viewerType = "essential" } }
local fullB = { name = "full-b", _spellEntry = { viewerType = "utility" } }
local auraIcon = { name = "aura", _spellEntry = { viewerType = "buff" } }
local cooldownIcon = { name = "cooldown", _spellEntry = { viewerType = "essential" } }
local barIcon = { name = "bar", _spellEntry = { viewerType = "trackedBar" } }

local pools = {
    essential = { fullA, cooldownIcon },
    utility = { fullB },
    buff = { auraIcon },
    trackedBar = { barIcon },
}

local calls = {}
local function record(...)
    calls[#calls + 1] = table.concat({ ... }, ":")
end

local function hasCall(value)
    for _, call in ipairs(calls) do
        if call == value then return true end
    end
    return false
end

local controller = module.Create({
    getIconPools = function() return pools end,
    refreshAllIcon = function(icon, context)
        record("all", icon.name, context.reason)
    end,
    resolveContainerDBAndType = function(entry, ncdm, ncdmContainers)
        record("resolve", entry.viewerType, ncdm.marker)
        if entry.viewerType == "buff" then
            return {}, "aura"
        end
        if entry.viewerType == "trackedBar" then
            return {}, "auraBar"
        end
        return {}, "cooldown"
    end,
    refreshCooldownOnlyIcon = function(icon)
        record("cooldown", icon.name)
    end,
    updateIconVisibility = function(icon, entry, containerDB, editMode, inCombat)
        record("visibility", icon.name, tostring(editMode), tostring(inCombat))
    end,
    refreshTypeIcon = function(icon, context)
        record("type", icon.name, context.reason)
    end,
})

local refreshed = controller:RefreshAll({ reason = "full" })
assert(refreshed == 5, "full refresh should walk every icon in every pool")
assert(hasCall("all:full-a:full"), "full refresh should call renderer callback")
assert(hasCall("all:bar:full"), "full refresh should include later pools")

calls = {}
refreshed = controller:RefreshCooldownOnly({
    ncdm = { marker = "db" },
    ncdmContainers = {},
    editMode = true,
    inCombat = false,
})
assert(refreshed == 3, "cooldown-only refresh should skip aura and auraBar containers")
assert(hasCall("resolve:essential:db"), "cooldown-only refresh should resolve container facts")
assert(hasCall("cooldown:full-a"), "cooldown-only refresh should update matching cooldown icons")
assert(hasCall("visibility:full-a:true:false"),
    "cooldown-only refresh should update visibility after icon refresh")

calls = {}
refreshed = controller:RefreshType("utility", { reason = "type" })
assert(refreshed == 1, "type refresh should walk only the requested pool")
assert(calls[1] == "type:full-b:type", "type refresh should call renderer callback")
assert(controller:RefreshType("missing", {}) == 0,
    "missing type refresh should be a no-op")

print("OK: cdm_icon_refresh_walker_test")
