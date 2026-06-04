-- tests/unit/migration_backup_prune_test.lua
-- Verifies migration rollback snapshots stay bounded and do not carry the
-- legacy per-profile shipped-default snapshot.
-- Run: lua tests/unit/migration_backup_prune_test.lua

local env = dofile("tools/_addon_env.lua")
local ns = env.LoadCore()
local Migrations = ns.Migrations

local failures = 0
local function check(name, ok, detail)
    if ok then print(("  ok  %s"):format(name))
    else failures = failures + 1; print(("FAIL  %s  %s"):format(name, detail or "")) end
end

do
    local profile = {
        _schemaVersion = 39,
        _shippedDefaults = { general = { oldDefault = true } },
        customSetting = true,
        _migrationBackup = {
            slots = {
                { snapshot = { _schemaVersion = 38, _shippedDefaults = { stale = true } } },
                { snapshot = { _schemaVersion = 37, _shippedDefaults = { older = true } } },
            },
        },
    }

    local changed = Migrations.RunOnProfile(profile)

    local slots = profile._migrationBackup and profile._migrationBackup.slots
    local snapshot = slots and slots[1] and slots[1].snapshot
    check("new migration reports backup cleanup", changed == true)
    check("new migration keeps one backup slot", type(slots) == "table" and #slots == 1)
    check("new migration backup keeps user data", snapshot and snapshot.customSetting == true)
    check("new migration backup strips shipped defaults", snapshot and snapshot._shippedDefaults == nil)
end

do
    local profile = {
        _schemaVersion = 999,
        _migrationBackup = {
            slots = {
                { snapshot = { keep = true, _shippedDefaults = { stale = true } } },
                { snapshot = { older = true, _shippedDefaults = { older = true } } },
            },
        },
    }

    local changed = Migrations.RunOnProfile(profile)

    local slots = profile._migrationBackup and profile._migrationBackup.slots
    local snapshot = slots and slots[1] and slots[1].snapshot
    check("current profile reports backup cleanup", changed == true)
    check("current profile prunes old backup slots", type(slots) == "table" and #slots == 1)
    check("current profile backup strips shipped defaults", snapshot and snapshot._shippedDefaults == nil)
end

if failures > 0 then
    os.exit(1)
end
print("migration_backup_prune_test: OK")
