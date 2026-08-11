-- tests/unit/migration_schema60_restore_buffdebuff_test.lua
-- Run: lua5.1 tests/unit/migration_schema60_restore_buffdebuff_test.lua
-- Verifies the schema-60 migration restores the separate debuff grid keys +
-- debuffFrame anchor after unified model.
local ns = dofile("tools/_addon_env.lua").LoadCore()
local M = ns.Migrations

local profile = {
    _schemaVersion = 47,
    buffBorders = { buffIconSize = 35 },
    frameAnchoring = {
        buffFrame   = { parent = "minimap" },
        someChild   = { parent = "buffFrame" },
    },
}

-- Test RestoreBuffDebuffSplit IN ISOLATION. Running the full pipeline
-- (M.RunOnProfile) also calls SeedAuraElements, which
-- CONSUMES these flat buff*/debuff* grid keys into element stores and prunes
-- them — so this step is asserted against the function directly. The full
-- schema-47→60 path (flat keys reshaped into element stores) is covered
-- by migration_floor_collapse_test.lua's at-floor(47) case.
M.RestoreBuffDebuffSplit(profile)

assert(profile.buffBorders.buffIconSize == 35, "buffIconSize must survive")
assert(profile.buffBorders.debuffIconSize == 35, "missing debuffIconSize must be restored from buffIconSize")
assert(profile.buffBorders.debuffIconsPerRow == 10, "missing debuffIconsPerRow must be restored")
assert(profile.buffBorders.debuffIconSpacing == 0, "missing debuffIconSpacing must be restored")
assert(profile.buffBorders.debuffGrowLeft == true, "missing debuffGrowLeft must default to stock QUI orientation")
assert(profile.buffBorders.debuffGrowUp == false, "missing debuffGrowUp must default to stock QUI orientation")
assert(profile.frameAnchoring.debuffFrame ~= nil, "debuffFrame anchor must be restored")
assert(profile.frameAnchoring.debuffFrame.parent == "buffFrame", "debuffFrame should default below/relative to buffFrame")
assert(profile.frameAnchoring.someChild.parent == "buffFrame", "existing dependents must be preserved")
print("migration_schema60_restore_buffdebuff_test: OK")
