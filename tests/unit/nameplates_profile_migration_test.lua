-- tests/unit/nameplates_profile_migration_test.lua
-- Legacy nameplates.specPresets were keyed by spec INDEX and collided across
-- classes, so migration converts them into UNASSIGNED named profiles in
-- db.global.nameplateProfiles (labelled with the source QUI profile). Role
-- presets were unambiguous and keep their assignment. Sources are deleted;
-- the migration is idempotent.

local env = dofile("tools/_addon_env.lua")

local seed = { QUI_DB = {
    profileKeys = { ["Char - Realm"] = "TankDPS" },
    profiles = {
        TankDPS = {
            _schemaVersion = 60,
            nameplates = {
                enabled = true,
                specPresets = {
                    [2] = { health = { width = 111 }, friendly = { enabled = false } },
                    [3] = {}, -- empty snapshot: dropped, not converted
                },
                specAutoSwitch = true,
            },
        },
        Healing = {
            _schemaVersion = 60,
            nameplates = {
                specPresets = { [2] = { health = { width = 222 } } },
                specAutoSwitch = false,
            },
        },
    },
    global = {
        nameplateRolePresets = {
            autoSwitch = false,
            TANK = { health = { width = 333 } },
        },
    },
} }

local h = env.LoadHarness(seed)
local Migrations = h.ns.Migrations
assert(Migrations and Migrations.Run, "Migrations.Run missing")

Migrations.Run(h.db)

local g = h.db.global
local store = g.nameplateProfiles
assert(type(store) == "table", "global nameplateProfiles store must exist after migration")

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

assert(store["Migrated spec preset 2 (TankDPS)"], "TankDPS spec preset 2 must become a named profile")
assert(store["Migrated spec preset 2 (TankDPS)"].health.width == 111, "TankDPS snapshot values must survive")
assert(store["Migrated spec preset 2 (Healing)"], "Healing spec preset 2 must become its own profile")
assert(store["Migrated spec preset 2 (Healing)"].health.width == 222, "Healing snapshot values must survive")
assert(store["Tank"], "TANK role preset must become the 'Tank' profile")
assert(store["Tank"].health.width == 333, "role snapshot values must survive")
assert(count(store) == 3, "empty spec presets must not create profiles, got " .. count(store))

local assignments = g.nameplateProfileAssignments
assert(type(assignments) == "table", "assignments must exist")
assert(count(assignments.specs) == 0,
    "index-keyed spec presets are ambiguous across classes and must stay UNASSIGNED")
assert(assignments.roles.TANK == "Tank", "role assignment must be preserved")
assert(assignments.autoSwitch == true, "any legacy auto-switch toggle must carry over")

for name, profile in pairs(h.db.sv.profiles) do
    local np = profile.nameplates
    if type(np) == "table" then
        assert(np.specPresets == nil, name .. ": legacy specPresets must be deleted")
        assert(np.specAutoSwitch == nil, name .. ": legacy specAutoSwitch must be deleted")
    end
end
assert(g.nameplateRolePresets == nil, "legacy role store must be deleted")

-- Idempotency: a second run must not duplicate anything.
Migrations.Run(h.db)
assert(count(g.nameplateProfiles) == 3, "second run must not create duplicate profiles")
assert(g.nameplateProfileAssignments.roles.TANK == "Tank", "second run must not disturb assignments")

print("ok nameplates profile migration")
