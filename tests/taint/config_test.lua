-- tests/taint/config_test.lua
local Config = dofile("tests/taint/config.lua")

local function assert_eq(a, e, msg)
    if a ~= e then error((msg or "") .. ": expected " .. tostring(e) ..
        ", got " .. tostring(a), 2) end
end
local function assert_true(v, msg) if not v then error(msg or "", 2) end end

-- Default config when file missing
local cfg = Config.loadFromString(nil)
assert_eq(#cfg.strict_paths, 0, "no strict paths by default")
assert_eq(#cfg.ignore_paths, 3, "default ignore paths count")
assert_true(cfg.coverage.secretWhenCooldownsRestricted, "coverage default")

-- Load from string (synthetic config)
local synthetic = [[
return {
    strict_paths = { "modules/cdm/" },
    strict_unwrap_paths = { "modules/cdm/" },
    ignore_paths = { "libs/", "tests/" },
    coverage = { secretWhenCooldownsRestricted = true },
    extra_safe_sinks = { "MyMod.Helper" },
    extra_unwraps = { "MyMod.SafeRead" },
}
]]
local cfg2 = Config.loadFromString(synthetic)
assert_eq(cfg2.strict_paths[1], "modules/cdm/", "strict path loaded")
assert_eq(cfg2.strict_unwrap_paths[1], "modules/cdm/", "strict unwrap path loaded")
assert_eq(#cfg2.extra_safe_sinks, 1, "extra safe sinks")
assert_eq(cfg2.extra_unwraps[1], "MyMod.SafeRead", "extra unwrap")

-- isStrictPath helper
assert_true(Config.isStrictPath(cfg2, "modules/cdm/cdm_icon_renderer.lua"),
    "file under strict path")
assert_eq(Config.isStrictPath(cfg2, "modules/foo/bar.lua"), false,
    "file outside strict path")

assert_true(Config.isStrictUnwrapPath(cfg2, "modules/cdm/cdm_icon_renderer.lua"),
    "file under strict unwrap path")
assert_eq(Config.isStrictUnwrapPath(cfg2, "modules/foo/bar.lua"), false,
    "file outside strict unwrap path")

-- isIgnoredPath helper
assert_true(Config.isIgnoredPath(cfg2, "libs/AceAddon-3.0.lua"), "ignored libs")
assert_eq(Config.isIgnoredPath(cfg2, "modules/cdm/cdm_icon_renderer.lua"),
    false, "not ignored")

-- Malformed config: returns defaults + error
local bad = Config.loadFromString("return { invalid lua }")
assert_eq(bad, nil, "malformed returns nil")

-- Test: partial coverage override preserves defaults for unspecified keys
local partialCoverage = [[
return { coverage = { secretWhenCooldownsRestricted = false } }
]]
local cfg3 = Config.loadFromString(partialCoverage)
assert_eq(cfg3.coverage.secretWhenCooldownsRestricted, false,
    "user override applied")
assert_eq(cfg3.coverage.isSecretReturn, true,
    "isSecretReturn default preserved through partial coverage override")
assert_eq(cfg3.coverage.secretArguments_restricted, true,
    "secretArguments_restricted default preserved through partial coverage override")

print("config test passed")

-- Round-23 element keys
do
    local cfg = Config.loadFromString(nil)
    assert(cfg.coverage.conditionalSecretContents == true,
        "conditionalSecretContents coverage defaults ON")
    assert(type(cfg.element_secret_functions) == "table",
        "element_secret_functions default present")
    assert(type(cfg.element_container_params) == "table",
        "element_container_params default present")
    local merged = Config.loadFromString([[return {
        element_secret_functions = { "Sources.QueryUnitAuras" },
        element_container_params = { CopyReadableAuras = { 1 } },
    }]])
    assert(merged.element_secret_functions[1] == "Sources.QueryUnitAuras",
        "element_secret_functions merges")
    assert(merged.element_container_params.CopyReadableAuras[1] == 1,
        "element_container_params merges")
    assert(merged.coverage.conditionalSecretContents == true,
        "partial config keeps coverage default")
end
print("config element keys test passed")
