-- tests/unit/shipped_defaults_maintenance_test.lua
-- Verifies legacy per-profile shipped-default snapshots are consumed before
-- being replaced by the account-level snapshot.
-- Run: lua tests/unit/shipped_defaults_maintenance_test.lua

local env = dofile("tools/_addon_env.lua")
local ns = env.LoadCore()
local Compatibility = ns.Compatibility

local failures = 0
local function check(name, ok, detail)
    if ok then print(("  ok  %s"):format(name))
    else failures = failures + 1; print(("FAIL  %s  %s"):format(name, detail or "")) end
end

ns.defaults.profile.__unitTestDefaults = {
    enabled = true,
    scale = 2,
}

local firstShadow = {
    __unitTestDefaults = {
        enabled = false,
        scale = 1,
    },
}

local secondShadow = {
    __unitTestDefaults = {
        enabled = "old-alt",
        scale = 3,
    },
}

local db = {
    global = {},
    sv = {
        profiles = {
            First = {
                _defaultsVersion = 3,
                _shippedDefaults = firstShadow,
                __unitTestDefaults = {},
            },
            Second = {
                _defaultsVersion = 3,
                _shippedDefaults = secondShadow,
                __unitTestDefaults = {},
            },
        },
    },
}

Compatibility.RunShippedDefaultsMaintenance(db)

local first = db.sv.profiles.First
local second = db.sv.profiles.Second
local globalSnapshot = db.global._shippedProfileDefaults

check("first profile old enabled default pinned", first.__unitTestDefaults.enabled == false)
check("first profile old scale default pinned", first.__unitTestDefaults.scale == 1)
check("second profile old enabled default pinned", second.__unitTestDefaults.enabled == "old-alt")
check("second profile old scale default pinned", second.__unitTestDefaults.scale == 3)
check("first profile legacy snapshot pruned", first._shippedDefaults == nil)
check("second profile legacy snapshot pruned", second._shippedDefaults == nil)
check("global shipped snapshot written", type(globalSnapshot) == "table")
check("global shipped snapshot refreshed to current default", globalSnapshot
    and globalSnapshot.__unitTestDefaults
    and globalSnapshot.__unitTestDefaults.enabled == true
    and globalSnapshot.__unitTestDefaults.scale == 2)

if failures > 0 then
    os.exit(1)
end
print("shipped_defaults_maintenance_test: OK")
