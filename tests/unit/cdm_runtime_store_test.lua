-- tests/unit/cdm_runtime_store_test.lua
-- Run: lua tests/unit/cdm_runtime_store_test.lua

function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local secretValueMT = {
    __eq = function()
        error("secret value compared")
    end,
}

local function NewSecretValue(label)
    return setmetatable({ label = label }, secretValueMT)
end

local originalRawequal = rawequal
function rawequal(left, right)
    if getmetatable(left) == secretValueMT or getmetatable(right) == secretValueMT then
        error("secret value compared by rawequal")
    end
    return originalRawequal(left, right)
end

local ns = {
    Helpers = {
        IsSecretValue = function(value)
            return getmetatable(value) == secretValueMT
        end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_runtime_store.lua", "cdm_runtime_store.lua")("QUI", ns)

local store = assert(ns.CDMRuntimeStore, "CDMRuntimeStore table was not exported")
local durObj = { token = "duration" }

local first = store.SetState("cooldown:test", {
    mode = "cooldown",
    active = true,
    durObj = durObj,
})

assert(first, "SetState should return stored state")
assert(store.Version() == 1, "first write should increment version")
assert(first.epoch == 1, "first write should stamp epoch")

local same = store.SetState("cooldown:test", {
    mode = "cooldown",
    active = true,
    durObj = durObj,
})

assert(same == first, "identical SetState should reuse the same table")
assert(store.Version() == 2, "SetState should refresh in place without equality checks")
assert(same.epoch == 2, "SetState should stamp each refresh")

local changed = store.SetState("cooldown:test", {
    mode = "cooldown",
    active = false,
    durObj = durObj,
})

assert(changed == first, "changed SetState should update the existing table")
assert(store.Version() == 3, "changed SetState should increment version")
assert(changed.epoch == 3, "changed SetState should increment epoch")
assert(store.GetState("cooldown:test") == nil, "compat SetState should not publish a central runtime cache")

local icon = {
    _spellEntry = {
        viewerType = "essential",
        type = "spell",
        id = 12345,
        _instanceKey = "slot-1",
    },
}

store.SetIconState(icon, {
    mode = "gcd-only",
    sourceID = 12345,
    active = false,
    key = "gcd-only:12345",
})

local afterIconWrite = store.Version()
local iconRuntimeState = icon._cdmRuntimeState

assert(iconRuntimeState, "SetIconState should attach runtime facts to the icon")
assert(iconRuntimeState.key == "essential:spell:12345:slot-1", "SetIconState should stamp the resolved runtime key into the icon-owned state")
assert(store.GetFrameState(icon) == iconRuntimeState, "GetFrameState should return the icon-owned runtime state")
assert(store.GetState(iconRuntimeState.key) == nil, "icon runtime facts should not be centrally indexed by entry key")

store.SetIconState(icon, {
    mode = "gcd-only",
    sourceID = 12345,
    active = false,
    key = "gcd-only:12345",
})

assert(store.Version() == afterIconWrite + 1, "SetIconState should refresh in place without equality checks")
assert(icon._cdmRuntimeState == iconRuntimeState, "identical SetIconState should reuse the icon-owned runtime table")

icon._spellEntry = {
    viewerType = "utility",
    type = "spell",
    id = 67890,
    _instanceKey = "slot-2",
}

store.SetIconState(icon, {
    mode = "cooldown",
    sourceID = 67890,
    active = true,
})

assert(iconRuntimeState.key == "utility:spell:67890:slot-2", "changing the icon entry should refresh the frame-owned runtime key")
assert(icon._cdmRuntimeState == iconRuntimeState, "entry refresh should keep the same icon-owned runtime table")
assert(store.GetState("essential:spell:12345:slot-1") == nil, "entry refresh should keep icon facts out of the central index")
assert(store.GetState("utility:spell:67890:slot-2") == nil,
    "entry refresh should not centrally re-index icon-owned state")

store.ClearAll()
assert(icon._cdmRuntimeState == iconRuntimeState, "ClearAll should not need a weak frame index to reach icon-owned state")
store.ClearFrame(icon)
assert(icon._cdmRuntimeState == nil, "ClearFrame should clear icon-owned runtime state")

local secretOpaqueValue = NewSecretValue("one")
local nextSecretOpaqueValue = NewSecretValue("two")
local secretState = store.SetState("secret:test", {
    mode = "aura",
    active = true,
    opaqueValue = secretOpaqueValue,
    opaqueSource = "display-count",
})
local secretVersion = store.Version()

local ok, updatedSecretState = pcall(function()
    return store.SetState("secret:test", {
        mode = "aura",
        active = true,
        opaqueValue = nextSecretOpaqueValue,
        opaqueSource = "display-count",
    })
end)

assert(ok, "SetState should not compare secret values")
assert(updatedSecretState == secretState, "secret value refresh should reuse the state table")
assert(store.Version() == secretVersion + 1, "unknown secret equality should refresh the stored state")
assert(originalRawequal(updatedSecretState.opaqueValue, nextSecretOpaqueValue),
    "secret value refresh should store the latest value")

print("OK: cdm_runtime_store_test")
