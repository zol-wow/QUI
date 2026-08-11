local function fail(msg)
    print("FAIL: nameplates_types_normalizer_test - " .. msg)
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

test("a legacy profile folds into six identical type configs", function()
    local s = NP.NormalizeTypes(LegacyProfile())
    if type(s.types) ~= "table" then fail("types table was not created") end
    for _, key in ipairs(NP.PlateType.ORDER) do
        local t = s.types[key]
        if type(t) ~= "table" then fail("missing type config " .. key) end
        if t.health.width ~= 210 then fail(key .. " lost health.width") end
        if t.name.size ~= 11 then fail(key .. " lost name.size") end
        if t.colors.hostile[1] ~= 0.39 then fail(key .. " lost colors.hostile") end
    end
end)

test("the six copies are independent, not shared references", function()
    local s = NP.NormalizeTypes(LegacyProfile())
    s.types.bossElite.health.width = 300
    if s.types.enemyNPC.health.width ~= 210 then
        fail("editing one type must not affect another")
    end
end)

test("global keys stay at the top level and leave the type configs", function()
    local s = NP.NormalizeTypes(LegacyProfile())
    if s.fading == nil then fail("fading must stay global") end
    if s.cvars == nil then fail("cvars must stay global") end
    if s.enabled ~= true then fail("enabled must stay global") end
    if s.types.enemyNPC.fading ~= nil then fail("fading must not be copied per type") end
    if s.types.enemyNPC.cvars ~= nil then fail("cvars must not be copied per type") end
end)

test("legacy visual keys are removed from the top level", function()
    local s = NP.NormalizeTypes(LegacyProfile())
    if s.health ~= nil then fail("legacy health must be removed after folding") end
    if s.colors ~= nil then fail("legacy colors must be removed after folding") end
end)

test("running twice changes nothing", function()
    local s = NP.NormalizeTypes(LegacyProfile())
    s.types.bossElite.health.width = 300
    NP.NormalizeTypes(s)
    if s.types.bossElite.health.width ~= 300 then fail("second run clobbered an edit") end
end)

test("a profile that already has types is left alone", function()
    local s = { enabled = true, types = { enemyNPC = { health = { width = 999 } } } }
    NP.NormalizeTypes(s)
    if s.types.enemyNPC.health.width ~= 999 then fail("existing types must not be rebuilt") end
end)

test("GetTypeSettings falls back to enemyNPC for an unknown type", function()
    local s = NP.NormalizeTypes(LegacyProfile())
    ns.Helpers.GetModuleSettings = function() return s end
    if NP.GetTypeSettings({ npType = "nonsense" }) ~= s.types.enemyNPC then
        fail("unknown type must fall back to enemyNPC")
    end
    if NP.GetTypeSettings({}) ~= s.types.enemyNPC then
        fail("missing npType must fall back to enemyNPC")
    end
    if NP.GetTypeSettings({ npType = "bossElite" }) ~= s.types.bossElite then
        fail("a known type must return its own config")
    end
end)

local RealHarness
do
    local env = dofile("tools/_addon_env.lua")
    local seed = {
        QUI_DB = {
            profileKeys = { ["TestChar - TestRealm"] = "Default" },
            profiles = {
                Default = {
                    nameplates = {
                        enabled = true,
                        health = { width = 777, height = 30, texture = "LegacyTex" },
                        name = { enabled = true, size = 33 },
                        colors = { hostile = { 0.11, 0.22, 0.33 } },
                    },
                },
            },
        },
        QUIDB = {},
    }
    RealHarness = env.LoadHarness(seed, { noSeed = true })
    assert(loadfile("QUI_Nameplates/nameplates/shared.lua"))("QUI_Nameplates", RealHarness.ns)
    assert(loadfile("QUI_Nameplates/nameplates/plate_type.lua"))("QUI_Nameplates", RealHarness.ns)
end
local RealNP = RealHarness.ns.QUI_Nameplates

test("a real AceDB profile: legacy flat data plus AceDB-fabricated types folds, and the user's values win", function()
    local rawNameplates = RealHarness.db.profile.nameplates

    if rawget(rawNameplates, "types") == nil then
        fail("expected AceDB to have already fabricated types before NormalizeTypes ever runs")
    end
    if rawget(rawNameplates, "health") == nil then
        fail("expected the legacy flat health key to still be sitting on the raw profile")
    end
    if rawNameplates.types.enemyNPC.health.width ~= 210 then
        fail("expected AceDB to have filled types.enemyNPC.health with the shipped default pre-fold")
    end

    RealNP.NormalizeTypes(rawNameplates)

    for _, key in ipairs(RealNP.PlateType.ORDER) do
        local t = rawNameplates.types[key]
        if t.health.width ~= 777 then
            fail(key .. " kept the AceDB default instead of the user's legacy health.width")
        end
        if t.name.size ~= 33 then
            fail(key .. " lost the user's legacy name.size")
        end
        if t.colors.hostile[1] ~= 0.11 then
            fail(key .. " lost the user's legacy colors.hostile")
        end
        if t.health.borderSize ~= 1 then
            fail(key .. " lost the AceDB default health.borderSize, a sibling the legacy health patch never touched")
        end
        if t.health.bgAlpha ~= 1.0 then
            fail(key .. " lost the AceDB default health.bgAlpha, a sibling the legacy health patch never touched")
        end
        if t.colors.neutral[1] ~= 0.81 or t.colors.neutral[2] ~= 0.72 or t.colors.neutral[3] ~= 0.19 then
            fail(key .. " lost the AceDB default colors.neutral, a sibling the legacy colors patch never touched")
        end
        if t.colors.threatEnabled ~= true then
            fail(key .. " lost the AceDB default colors.threatEnabled, a sibling the legacy colors patch never touched")
        end
        if t.raidMarker.enabled ~= true or t.raidMarker.size ~= 24 then
            fail(key .. " should have kept the AceDB shipped raidMarker default since no legacy raidMarker existed")
        end
    end
    if rawget(rawNameplates, "health") ~= nil then
        fail("legacy health must be removed from the raw profile after folding")
    end

    RealNP.NormalizeTypes(rawNameplates)
    if rawNameplates.types.bossElite.health.width ~= 777 then
        fail("a second run against the real AceDB profile must not clobber the folded value")
    end
end)

test("a genuinely fresh AceDB profile with only AceDB-fabricated types is left alone", function()
    RealHarness.db:SetProfile("FreshProfile")
    local rawNameplates = RealHarness.db.profile.nameplates

    if rawget(rawNameplates, "health") ~= nil then
        fail("a fresh profile must never carry a legacy health key")
    end
    if rawNameplates.types.enemyNPC.health.width ~= 210 then
        fail("expected AceDB to ship the default types.enemyNPC.health.width on a fresh profile")
    end
    local typesRefBefore = rawNameplates.types

    RealNP.NormalizeTypes(rawNameplates)

    if rawNameplates.types ~= typesRefBefore then
        fail("a fresh profile's types table must not be rebuilt")
    end
    if rawNameplates.types.enemyNPC.health.width ~= 210 then
        fail("a fresh profile's shipped default must be left untouched")
    end
end)

test("the boolean showInInstances folds to the never/nameonly/always enum", function()
    local s1 = NP.NormalizeTypes({ friendly = { showInInstances = true } })
    if s1.friendly.showInInstances ~= "always" then
        fail("true meant show them, so it must fold to always, got "
            .. tostring(s1.friendly.showInInstances))
    end

    local s2 = NP.NormalizeTypes({ friendly = { showInInstances = false } })
    if s2.friendly.showInInstances ~= "never" then
        fail("false meant hide them, so it must fold to never, got "
            .. tostring(s2.friendly.showInInstances))
    end

    local s3 = NP.NormalizeTypes({ friendly = { showInInstances = "nonsense" } })
    if s3.friendly.showInInstances ~= "never" then
        fail("an unknown value must fall back to never, got "
            .. tostring(s3.friendly.showInInstances))
    end

    local s4 = NP.NormalizeTypes({ friendly = { showInInstances = "nameonly" } })
    if s4.friendly.showInInstances ~= "nameonly" then
        fail("a valid enum value must survive the fold")
    end

    local s5 = NP.NormalizeTypes({ friendly = { showInInstances = "always" } })
    NP.NormalizeTypes(s5)
    if s5.friendly.showInInstances ~= "always" then
        fail("the fold must be idempotent -- it runs on every GetTypeSettings call")
    end
end)

print("OK: nameplates_types_normalizer_test")
