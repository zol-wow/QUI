local env = dofile("tools/_addon_env.lua")
local ns = env.LoadCore()

local testProfile = { nameplates = { types = {} } }
ns.Helpers = {
    GetProfile = function() return testProfile end,
}

ns.Settings = {
    Renderer = { RenderFeature = function() end },
    Schema = {
        Feature = function(definition) return definition end,
        Section = function(definition) return definition end,
    },
}

env.LoadAddonFile("QUI_Nameplates/nameplates/shared.lua", "QUI_Nameplates", ns)
env.LoadAddonFile("QUI_Nameplates/nameplates/plate_type.lua", "QUI_Nameplates", ns)
env.LoadAddonFile("QUI_Nameplates/nameplates/settings/nameplates_schema.lua", "QUI_Nameplates", ns)

local NP = ns.QUI_Nameplates
local Schema = ns.QUI_NameplatesSettingsSchema

local function fail(msg)
    print("FAIL: nameplates_copy_from_test - " .. msg)
    os.exit(1)
end

local function test(name, fn)
    print(name)
    fn()
    print("  ok")
end

local db = testProfile.nameplates
for _, key in ipairs(NP.PlateType.ORDER) do
    db.types[key] = { health = { width = 200 }, name = { size = 12 } }
end

test("copying overwrites every key of the target", function()
    db.types.bossElite.health.width = 300
    db.types.bossElite.name.size = 20
    db.types.enemyNPC.health.width = 210
    db.types.enemyNPC.name.size = 11
    if Schema.CopyTypeConfig("bossElite", "enemyNPC") ~= true then fail("copy reported failure") end
    if db.types.enemyNPC.health.width ~= 300 then fail("health.width was not copied") end
    if db.types.enemyNPC.name.size ~= 20 then fail("name.size was not copied") end
end)

test("copying leaves the source and the other types untouched", function()
    db.types.bossElite.health.width = 300
    db.types.petMinion.health.width = 150
    Schema.CopyTypeConfig("bossElite", "enemyNPC")
    if db.types.bossElite.health.width ~= 300 then fail("source was mutated") end
    if db.types.petMinion.health.width ~= 150 then fail("an unrelated type was mutated") end
end)

test("the copy is deep, not a shared reference", function()
    Schema.CopyTypeConfig("bossElite", "enemyNPC")
    db.types.enemyNPC.health.width = 999
    if db.types.bossElite.health.width == 999 then fail("copy shared a table reference") end
end)

test("copying fills the target's existing tables in place, it never swaps them out", function()
    local targetRoot = db.types.enemyNPC
    local targetHealth = db.types.enemyNPC.health
    db.types.bossElite.health.width = 321
    Schema.CopyTypeConfig("bossElite", "enemyNPC")
    if db.types.enemyNPC ~= targetRoot then
        fail("CopyTypeConfig replaced the target's root table instead of filling it -- any cached widget bound to the old table object is now stale")
    end
    if db.types.enemyNPC.health ~= targetHealth then
        fail("CopyTypeConfig replaced the target's health table instead of filling it -- any cached widget bound to the old table object is now stale")
    end
    if targetHealth.width ~= 321 then
        fail("the reused health table was not actually updated with the copied value")
    end
end)

test("copying drops a target-only key the source does not have", function()
    db.types.enemyNPC.health.onlyOnTarget = "stale"
    Schema.CopyTypeConfig("bossElite", "enemyNPC")
    if db.types.enemyNPC.health.onlyOnTarget ~= nil then
        fail("a key absent from the source must not survive the copy")
    end
end)

test("copying to or from an unknown type is refused", function()
    if Schema.CopyTypeConfig("bossElite", "nonsense") ~= false then fail("unknown target must refuse") end
    if Schema.CopyTypeConfig("nonsense", "enemyNPC") ~= false then fail("unknown source must refuse") end
    if Schema.CopyTypeConfig("bossElite", "bossElite") ~= false then fail("self-copy must refuse") end
end)

test("ResolveTypeDB returns the requested type's subtree", function()
    local resolved = Schema.ResolveTypeDB("petMinion")
    if resolved ~= db.types.petMinion then
        fail("ResolveTypeDB did not return the petMinion subtree")
    end
end)

test("ResolveTypeDB falls back to enemyNPC for an unknown type", function()
    local resolved = Schema.ResolveTypeDB("nonsense")
    if resolved ~= db.types.enemyNPC then
        fail("ResolveTypeDB must fall back to enemyNPC for an unresolvable key")
    end
end)

print("OK: nameplates_copy_from_test")
