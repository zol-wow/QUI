-- tests/cdm_runtime_store_test.lua
-- Run: lua tests/cdm_runtime_store_test.lua

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

local ns = {
    Helpers = {
        IsSecretValue = function(value)
            return getmetatable(value) == secretValueMT
        end,
    },
}

assert(loadfile("modules/cdm/cdm_runtime_store.lua"))("QUI", ns)

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
assert(store.Version() == 1, "identical SetState should not churn version")
assert(same.epoch == 1, "identical SetState should not churn epoch")

local changed = store.SetState("cooldown:test", {
    mode = "cooldown",
    active = false,
    durObj = durObj,
})

assert(changed == first, "changed SetState should update the existing table")
assert(store.Version() == 2, "changed SetState should increment version")
assert(changed.epoch == 2, "changed SetState should increment epoch")

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
local cachedIconKey = icon._cdmRuntimeKey

assert(cachedIconKey == "essential:spell:12345:slot-1", "SetIconState should cache the resolved runtime key on the icon")
assert(icon._cdmRuntimeKeyEntry == icon._spellEntry, "SetIconState should remember which entry produced the cached key")

store.SetIconState(icon, {
    mode = "gcd-only",
    sourceID = 12345,
    active = false,
    key = "gcd-only:12345",
})

assert(store.Version() == afterIconWrite, "identical SetIconState should not churn version")
assert(icon._cdmRuntimeKey == cachedIconKey, "identical SetIconState should reuse the cached runtime key")

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

assert(icon._cdmRuntimeKey == "utility:spell:67890:slot-2", "changing the icon entry should refresh the cached runtime key")
assert(icon._cdmRuntimeKeyEntry == icon._spellEntry, "entry refresh should update the key owner")

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
assert(rawequal(updatedSecretState.opaqueValue, nextSecretOpaqueValue),
    "secret value refresh should store the latest value")

print("OK: cdm_runtime_store_test")
