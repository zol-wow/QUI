local function fail(msg)
    print("FAIL: nameplates_type_resolver_test - " .. msg)
    os.exit(1)
end

local function noop() end

local unitState = {}

_G.UnitIsMinion = function(u) return unitState.isMinion end
_G.UnitIsOtherPlayersPet = function(u) return unitState.isOtherPet end
_G.UnitIsUnit = function(a, b) return unitState.isSelfPet and b == "pet" end
_G.UnitCanAttack = function(a, b) return unitState.canAttack end
_G.UnitClassification = function(u) return unitState.classification end
_G.UnitLevel = function(u) return unitState.level end
_G.UnitIsPlayer = function(u) return unitState.isPlayer end
_G.UnitReaction = function(a, b) return unitState.reaction end
_G.CreateFrame = function() return { SetScript = noop, RegisterEvent = noop } end
_G.UIParent = {}

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        GetModuleSettings = function() return {} end,
        GetProfile = function() return { nameplates = {} } end,
    },
    UIKit = { ResolveFontPath = function() return "" end },
    L = setmetatable({}, { __index = function(_, k) return k end }),
}

assert(loadfile("core/classification.lua"))("QUI", ns)
assert(loadfile("QUI_Nameplates/nameplates/shared.lua"))("QUI_Nameplates", ns)
assert(loadfile("QUI_Nameplates/nameplates/plate_type.lua"))("QUI_Nameplates", ns)

local PlateType = ns.QUI_Nameplates.PlateType

local function test(name, fn) print(name); fn(); print("  ok") end

local function reset()
    unitState = {
        isMinion = false, isOtherPet = false, isSelfPet = false,
        canAttack = true, classification = "normal", level = 80,
        isPlayer = false, reaction = 2,
    }
end

test("the order has exactly the six keys, most specific first", function()
    local expected = { "petMinion", "friendly", "bossElite", "minorTrivial", "enemyPlayer", "enemyNPC" }
    if #PlateType.ORDER ~= 6 then fail("expected 6 keys, got " .. #PlateType.ORDER) end
    for i, key in ipairs(expected) do
        if PlateType.ORDER[i] ~= key then
            fail("slot " .. i .. " must be " .. key .. ", got " .. tostring(PlateType.ORDER[i]))
        end
    end
end)

test("a hostile normal npc resolves enemyNPC", function()
    reset()
    if PlateType.Resolve("nameplate1") ~= "enemyNPC" then fail("expected enemyNPC") end
end)

test("a hostile player resolves enemyPlayer", function()
    reset()
    unitState.isPlayer = true
    if PlateType.Resolve("nameplate1") ~= "enemyPlayer" then fail("expected enemyPlayer") end
end)

test("a worldboss resolves bossElite", function()
    reset()
    unitState.classification = "worldboss"
    if PlateType.Resolve("nameplate1") ~= "bossElite" then fail("expected bossElite") end
end)

test("a level -1 unit resolves bossElite", function()
    reset()
    unitState.level = -1
    if PlateType.Resolve("nameplate1") ~= "bossElite" then fail("expected bossElite from level -1") end
end)

test("a minus unit resolves minorTrivial", function()
    reset()
    unitState.classification = "minus"
    if PlateType.Resolve("nameplate1") ~= "minorTrivial" then fail("expected minorTrivial") end
end)

test("an unattackable unit resolves friendly", function()
    reset()
    unitState.canAttack = false
    if PlateType.Resolve("nameplate1") ~= "friendly" then fail("expected friendly") end
end)

test("a friendly pet resolves petMinion, not friendly", function()
    reset()
    unitState.canAttack = false
    unitState.isMinion = true
    if PlateType.Resolve("nameplate1") ~= "petMinion" then
        fail("unit kind must beat reaction for pets")
    end
end)

test("UnitIsOtherPlayersPet alone resolves petMinion", function()
    reset()
    unitState.isOtherPet = true
    if PlateType.Resolve("nameplate1") ~= "petMinion" then
        fail("UnitIsOtherPlayersPet must resolve petMinion on its own")
    end
end)

test("UnitIsUnit(unit, \"pet\") alone resolves petMinion", function()
    reset()
    unitState.isSelfPet = true
    if PlateType.Resolve("nameplate1") ~= "petMinion" then
        fail("the player's own pet must resolve petMinion on its own")
    end
end)

test("a hostile pet still resolves petMinion", function()
    reset()
    unitState.isOtherPet = true
    unitState.classification = "elite"
    if PlateType.Resolve("nameplate1") ~= "petMinion" then
        fail("unit kind must beat classification for pets")
    end
end)

test("non-boolean pet returns fall through instead of matching", function()
    reset()
    unitState.isMinion = nil
    unitState.isOtherPet = 1
    unitState.isSelfPet = nil
    if PlateType.Resolve("nameplate1") ~= "enemyNPC" then
        fail("only a plain boolean true may match a pet predicate")
    end
end)

test("a neutral npc resolves enemyNPC", function()
    reset()
    unitState.reaction = 4
    if PlateType.Resolve("nameplate1") ~= "enemyNPC" then
        fail("neutral has no type of its own and must fall through to enemyNPC")
    end
end)

test("a boss that is also a player resolves bossElite first", function()
    reset()
    unitState.isPlayer = true
    unitState.classification = "elite"
    if PlateType.Resolve("nameplate1") ~= "bossElite" then fail("bossElite outranks enemyPlayer") end
end)

test("a nil unit resolves the default key", function()
    reset()
    if PlateType.Resolve(nil) ~= PlateType.DEFAULT_KEY then fail("nil unit must yield the default") end
end)

print("OK: nameplates_type_resolver_test")
