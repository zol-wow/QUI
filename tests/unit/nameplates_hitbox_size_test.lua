local function fail(msg)
    print("FAIL: nameplates_hitbox_size_test - " .. msg)
    os.exit(1)
end

local function test(name, fn)
    print(name)
    fn()
    print("  ok")
end

local function noop() end

CreateFrame = function()
    return {
        RegisterEvent = noop,
        RegisterUnitEvent = noop,
        SetScript = noop,
        Hide = noop,
        Show = noop,
    }
end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
InCombatLockdown = function() return false end
SetCVar = noop
UnitIsMinion = function() return false end
UnitIsOtherPlayersPet = function() return false end
UnitIsUnit = function() return false end
UnitCanAttack = function() return true end
UnitClassification = function() return "normal" end
UnitLevel = function() return 80 end
UnitIsPlayer = function() return false end
UnitTreatAsPlayerForDisplay = function() return false end

local sizeCalls = {}
C_NamePlate = {
    GetNamePlateForUnit = function() return nil end,
    SetNamePlateSize = function(w, h) sizeCalls[#sizeCalls + 1] = { w, h } end,
}
C_CVar = { SetCVarBitfield = noop, GetCVarInfo = function() return nil end }
Enum = {}
C_NamePlateManager = nil

local settingsStore

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        GetModuleSettings = function() return settingsStore end,
    },
    UIKit = { ResolveFontPath = function() return "" end },
    L = setmetatable({}, { __index = function(_, k) return k end }),
}

assert(loadfile("core/classification.lua"))("QUI", ns)
assert(loadfile("QUI_Nameplates/nameplates/shared.lua"))("QUI_Nameplates", ns)
assert(loadfile("QUI_Nameplates/nameplates/plate_type.lua"))("QUI_Nameplates", ns)
assert(loadfile("QUI_Nameplates/nameplates/cvars.lua"))("QUI_Nameplates", ns)

local NP = ns.QUI_Nameplates
local NPCVars = ns.QUI_NameplatesCVars
if not NPCVars then fail("cvars.lua did not export ns.QUI_NameplatesCVars") end

local function TypeConfig(width, height, castH, nameSize, nameOffsetY, powerH)
    return {
        health = { width = width, height = height },
        castbar = { height = castH },
        name = { size = nameSize, offsetY = nameOffsetY },
        powerBar = powerH and { enabled = true, height = powerH } or { enabled = false },
    }
end

local function FreshSettings()
    return {
        enabled = true,
        cvars = { hitboxScaleX = 100, hitboxScaleY = 100 },
        types = {
            petMinion    = TypeConfig(100, 10, 10, 10, 0),
            friendly     = TypeConfig(120, 12, 10, 10, 0),
            bossElite    = TypeConfig(400, 20, 10, 10, 0),
            minorTrivial = TypeConfig(90, 8, 10, 10, 0),
            enemyPlayer  = TypeConfig(150, 15, 30, 20, -6, 9),
            enemyNPC     = TypeConfig(210, 24, 17, 11, 4),
        },
    }
end

local function ApplyAndCapture()
    sizeCalls = {}
    NPCVars.ApplyPlateSize()
    if #sizeCalls ~= 1 then
        fail("expected exactly one SetNamePlateSize call, got " .. #sizeCalls)
    end
    return sizeCalls[1][1], sizeCalls[1][2]
end

test("the one global plate size takes the widest health bar across all six types", function()
    settingsStore = FreshSettings()
    local w = ApplyAndCapture()
    if w ~= 400 then
        fail("expected the bossElite width of 400, got " .. tostring(w)
            .. " -- 210 means the size is being read off the deleted top-level health block")
    end
end)

test("the height is the tallest stack, resolved independently of the widest type", function()
    settingsStore = FreshSettings()
    local _, h = ApplyAndCapture()
    if h ~= 80 then
        fail("expected the enemyPlayer stack height of 80 (15 bar + 30 cast + 9 power + 26 name), got " .. tostring(h))
    end
end)

test("editing one type's health bar moves the global size", function()
    settingsStore = FreshSettings()
    local before = ApplyAndCapture()
    settingsStore.types.minorTrivial.health.width = 900
    local after = ApplyAndCapture()
    if after ~= 900 then
        fail("widening a single type must widen the shared hitbox, got " .. tostring(after)
            .. " (was " .. tostring(before) .. ")")
    end
end)

test("shrinking the widest type falls back to the next widest, never below the rest", function()
    settingsStore = FreshSettings()
    settingsStore.types.bossElite.health.width = 50
    local w = ApplyAndCapture()
    if w ~= 210 then
        fail("expected the next-widest type (enemyNPC, 210), got " .. tostring(w))
    end
end)

test("the hitbox scales multiply the resolved maximum, not a constant", function()
    settingsStore = FreshSettings()
    settingsStore.cvars.hitboxScaleX = 150
    settingsStore.cvars.hitboxScaleY = 200
    local w, h = ApplyAndCapture()
    if w ~= 600 then
        fail("expected 400 * 1.5 = 600, got " .. tostring(w)
            .. " -- 315 means the scale is being applied to a hardcoded 210")
    end
    if h ~= 95 then
        fail("expected the enemyPlayer stack with a doubled bar (30 + 30 + 9 + 26 = 95), got " .. tostring(h))
    end
end)

test("a legacy flat profile is folded before the size is read", function()
    settingsStore = {
        enabled = true,
        cvars = { hitboxScaleX = 100, hitboxScaleY = 100 },
        health = { width = 333, height = 24 },
        castbar = { height = 17 },
        name = { size = 11, offsetY = 4 },
    }
    local w, h = ApplyAndCapture()
    if w ~= 333 then
        fail("a pre-types profile must still size from its own health width, got " .. tostring(w))
    end
    if h ~= 56 then
        fail("expected 24 + 17 + 15 = 56, got " .. tostring(h))
    end
    if settingsStore.health ~= nil then
        fail("reading the size must leave the profile normalized, not re-seed the legacy keys")
    end
end)

test("a profile with no type configs at all still gets a usable hitbox", function()
    settingsStore = { enabled = true, cvars = {} }
    local w, h = ApplyAndCapture()
    if w <= 0 or h <= 0 then
        fail("a degenerate profile must not collapse the hitbox to zero, got "
            .. tostring(w) .. "x" .. tostring(h))
    end
end)

test("the size is not written when the module is disabled", function()
    settingsStore = FreshSettings()
    settingsStore.enabled = false
    sizeCalls = {}
    NPCVars.ApplyPlateSize()
    if #sizeCalls ~= 0 then fail("a disabled module must not resize plates") end
end)

test("NP.PlateType.ORDER drives which configs are considered", function()
    settingsStore = FreshSettings()
    local originalOrder = NP.PlateType.ORDER
    NP.PlateType.ORDER = { "petMinion", "minorTrivial" }
    local w = ApplyAndCapture()
    NP.PlateType.ORDER = originalOrder
    if w ~= 100 then
        fail("with only petMinion and minorTrivial in the order, the widest is 100, got " .. tostring(w))
    end
end)

print("OK: nameplates_hitbox_size_test")
