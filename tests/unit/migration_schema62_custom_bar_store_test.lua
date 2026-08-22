local ns = dofile("tools/_addon_env.lua").LoadCore()
local M = ns.Migrations

local liveKey = "custom_1778883503_8224"
local legacyKey = "customBar_old_tracker"
local orphanKey = "custom_1776292480_7595"
local live = { containerType = "customBar", entries = { { type = "consumable", id = 1711 } } }
local profile = {
    _schemaVersion = M.CURRENT_SCHEMA_VERSION - 1,
    ncdm = {
        essential = { enabled = true },
        containers = {
            essential = { enabled = true },
            utility = { enabled = true },
            buff = { enabled = true },
            trackedBar = { enabled = true },
            [liveKey] = live,
            [legacyKey] = { containerType = "customBar", entries = {} },
        },
        [liveKey] = { containerType = "customBar", entries = { { type = "spell", id = 6201 } } },
        [legacyKey] = { containerType = "customBar", entries = { { type = "spell", id = 6201 } } },
        [orphanKey] = { containerType = "customBar", entries = { { type = "spell", id = 6201 } } },
    },
}

M.RunOnProfile(profile)

assert(profile._schemaVersion == M.CURRENT_SCHEMA_VERSION)
assert(profile.ncdm[liveKey] == nil)
assert(profile.ncdm[legacyKey] == nil)
assert(profile.ncdm.containers[liveKey] == live)
assert(profile.ncdm.containers[liveKey].entries[1].id == 1711)
assert(profile.ncdm[orphanKey] ~= nil)
assert(profile.ncdm.essential ~= nil)

M.RunOnProfile(profile)
assert(profile.ncdm[liveKey] == nil)
assert(profile.ncdm[legacyKey] == nil)
assert(profile.ncdm[orphanKey] ~= nil)

print("migration_schema62_custom_bar_store_test: all checks passed")
