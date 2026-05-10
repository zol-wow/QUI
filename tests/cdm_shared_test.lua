-- tests/cdm_shared_test.lua
-- Headless verification of shared CDM helper semantics. Run: lua tests/cdm_shared_test.lua

local core = {
    db = {
        profile = {
            ncdm = {
                enabled = true,
                essential = { enabled = true },
                containers = {
                    custom = { enabled = true },
                },
            },
        },
    },
}

local ns = {
    Helpers = {
        IsSecretValue = function(value)
            return value == "__secret__"
        end,
        GetCore = function()
            return core
        end,
    },
}

local chunk = assert(loadfile("modules/cdm/cdm_shared.lua"))
chunk("QUI", ns)

local Shared = assert(ns.CDMShared, "CDMShared table was not exported")

assert(Shared.IsRuntimeEnabled() == true, "runtime should be enabled by default")
core.db.profile.ncdm.enabled = false
assert(Shared.IsRuntimeEnabled() == false, "runtime should follow ncdm.enabled=false")
core.db.profile.ncdm.enabled = true

assert(Shared.GetNcdmDB() == core.db.profile.ncdm, "GetNcdmDB returned wrong table")
assert(Shared.GetContainerDB("essential") == core.db.profile.ncdm.essential, "builtin container lookup failed")
assert(Shared.GetContainerDB("custom") == core.db.profile.ncdm.containers.custom, "custom container lookup failed")
assert(Shared.GetContainerDB("missing") == nil, "missing container should return nil")

assert(Shared.IsSafeNumeric(12.5) == true, "number should be safe numeric")
assert(Shared.IsSafeNumeric("__secret__") == false, "secret should not be safe numeric")
assert(Shared.IsSafeNumeric("12") == false, "string should not be safe numeric")

assert(Shared.SafeBoolean(true) == true, "true should stay true")
assert(Shared.SafeBoolean(false) == false, "false should stay false")
assert(Shared.SafeBoolean("__secret__") == nil, "secret boolean should become nil")

assert(Shared.SettingEnabled(nil, true) == true, "nil should use fallback")
assert(Shared.SettingEnabled(nil, false) == false, "nil should use false fallback")
assert(Shared.SettingEnabled(false, true) == false, "explicit false should stay false")
assert(Shared.SettingEnabled(0, false) == false, "non-true value should be disabled")

print("OK: cdm_shared_test")
