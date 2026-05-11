-- tests/cdm_runtime_store_test.lua
-- Run: lua tests/cdm_runtime_store_test.lua

function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local ns = {}

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
})

local afterIconWrite = store.Version()

store.SetIconState(icon, {
    mode = "gcd-only",
    sourceID = 12345,
    active = false,
})

assert(store.Version() == afterIconWrite, "identical SetIconState should not churn version")

print("OK: cdm_runtime_store_test")
