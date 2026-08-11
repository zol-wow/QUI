local function fail(msg)
    print("FAIL: nameplates_starter_styles_test - " .. msg)
    os.exit(1)
end

local function noop() end

_G.UnitIsMinion = function() return false end
_G.UnitIsOtherPlayersPet = function() return false end
_G.UnitIsUnit = function() return false end
_G.UnitCanAttack = function() return true end
_G.UnitClassification = function() return "normal" end
_G.UnitLevel = function() return 80 end
_G.UnitIsPlayer = function() return false end
_G.CreateFrame = function() return { SetScript = noop, RegisterEvent = noop } end
_G.UIParent = {}
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

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
assert(loadfile("QUI_Nameplates/nameplates/presets.lua"))("QUI_Nameplates", ns)

local NP = ns.QUI_Nameplates
local function test(name, fn) print(name); fn(); print("  ok") end

local function LegacyProfile()
    return {
        enabled = true,
        health = { width = 210, height = 24, texture = "Quazii" },
        name = { enabled = true, size = 11 },
        colors = { hostile = { 0.39, 0.11, 0.09 } },
        auras = { enabled = true, elements = {} },
        fading = { nonTargetAlpha = 1.0 },
        layout = { targetScale = 1.0 },
        cvars = { maxDistance = 60 },
        friendly = { mode = "nameonly", showInWorld = true },
    }
end

test("a starter style reaches every type config", function()
    local s = NP.NormalizeTypes(LegacyProfile())
    ns.Helpers.GetModuleSettings = function() return s end
    if NP.Presets.ApplyStyleTable("compact") ~= true then fail("apply reported failure") end
    for _, key in ipairs(NP.PlateType.ORDER) do
        if s.types[key].health.width ~= 160 then
            fail(key .. " did not receive the compact width")
        end
        if s.types[key].name.size ~= 10 then
            fail(key .. " did not receive the compact name size")
        end
    end
end)

test("a starter style writes nothing at the top level", function()
    local s = NP.NormalizeTypes(LegacyProfile())
    ns.Helpers.GetModuleSettings = function() return s end
    NP.Presets.ApplyStyleTable("compact")
    if s.health ~= nil then fail("health must not be written at the top level") end
    if s.castbar ~= nil then fail("castbar must not be written at the top level") end
end)

test("a snapshot round-trips the six type configs", function()
    local s = NP.NormalizeTypes(LegacyProfile())
    s.types.bossElite.health.width = 300
    local snap = NP.Presets.Snapshot(s)
    s.types.bossElite.health.width = 210
    NP.Presets.ApplySnapshot(s, snap)
    if s.types.bossElite.health.width ~= 300 then
        fail("the snapshot did not carry per-type configs")
    end
end)

test("excluded keys stay out of a snapshot", function()
    local s = NP.NormalizeTypes(LegacyProfile())
    s.specAutoSwitch = true
    local snap = NP.Presets.Snapshot(s)
    if snap.specAutoSwitch ~= nil then fail("specAutoSwitch must be excluded") end
    if snap.enabled ~= nil then fail("enabled must be excluded") end
end)

test("a starter style does not alias the same table across two types", function()
    local s = NP.NormalizeTypes(LegacyProfile())
    ns.Helpers.GetModuleSettings = function() return s end
    NP.Presets.ApplyStyleTable("compact")
    if s.types.bossElite.health == s.types.enemyNPC.health then
        fail("two types must not share the same health table instance")
    end
    s.types.bossElite.health.width = 999
    if s.types.enemyNPC.health.width ~= 160 then
        fail("editing one type's fanned-out patch must not affect another")
    end
end)

test("an array-valued patch field replaces wholesale and fans out as independent copies", function()
    local s = NP.NormalizeTypes(LegacyProfile())
    ns.Helpers.GetModuleSettings = function() return s end
    for _, key in ipairs(NP.PlateType.ORDER) do
        s.types[key].health.bgColor = { 0.12, 0.12, 0.12, 1 }
    end
    NP.Presets.STARTER_STYLES.arrayProbe = { health = { bgColor = { 1, 0, 0 } } }

    if NP.Presets.ApplyStyleTable("arrayProbe") ~= true then fail("apply reported failure") end

    for _, key in ipairs(NP.PlateType.ORDER) do
        local bg = s.types[key].health.bgColor
        if bg[1] ~= 1 or bg[2] ~= 0 or bg[3] ~= 0 then
            fail(key .. " did not receive the array patch value")
        end
        if bg[4] ~= nil then
            fail(key .. " kept a stale element from an element-wise array merge instead of a wholesale replace")
        end
    end

    s.types.bossElite.health.bgColor[1] = 0
    if s.types.enemyNPC.health.bgColor[1] ~= 1 then
        fail("mutating one type's array copy must not affect another type's copy")
    end
end)

local RealHarness
do
    local env = dofile("tools/_addon_env.lua")
    RealHarness = env.LoadHarness(nil, { noSeed = true })
    assert(loadfile("QUI_Nameplates/nameplates/shared.lua"))("QUI_Nameplates", RealHarness.ns)
    assert(loadfile("QUI_Nameplates/nameplates/plate_type.lua"))("QUI_Nameplates", RealHarness.ns)
    assert(loadfile("QUI_Nameplates/nameplates/presets.lua"))("QUI_Nameplates", RealHarness.ns)
end
local RealNP = RealHarness.ns.QUI_Nameplates

test("the default style resets all six types to the shipped defaults", function()
    local rawNameplates = RealHarness.db.profile.nameplates
    rawNameplates.types.bossElite.health.width = 999
    rawNameplates.types.enemyNPC.name.size = 1

    if RealNP.Presets.ApplyStyleTable("default") ~= true then
        fail("default style application reported failure")
    end

    for _, key in ipairs(RealNP.PlateType.ORDER) do
        local t = rawNameplates.types[key]
        if t.health.width ~= 210 then
            fail(key .. " was not reset to the shipped default health.width")
        end
        if t.name.size ~= 11 then
            fail(key .. " was not reset to the shipped default name.size")
        end
    end
end)

test("the default style clears legacy flat keys so they cannot fold back over the reset", function()
    local rawNameplates = RealHarness.db.profile.nameplates
    rawNameplates.health = { width = 777 }
    rawNameplates.name = { size = 33 }
    rawNameplates.types.bossElite.health.width = 999

    if RealNP.Presets.ApplyStyleTable("default") ~= true then
        fail("default style application reported failure")
    end

    for _, key in ipairs(RealNP.PlateType.ORDER) do
        local resolved = RealNP.GetTypeSettings({ npType = key })
        if resolved.health.width ~= 210 then
            fail(key .. " reads " .. tostring(resolved.health.width)
                .. " after a default reset -- the legacy top-level health block folded back over it")
        end
        if resolved.name.size ~= 11 then
            fail(key .. " reads name size " .. tostring(resolved.name.size)
                .. " after a default reset -- the legacy top-level name block folded back over it")
        end
    end

    if rawNameplates.health ~= nil or rawNameplates.name ~= nil then
        fail("the default style must leave the profile normalized, with no legacy top-level per-type keys")
    end
end)

print("OK: nameplates_starter_styles_test")
