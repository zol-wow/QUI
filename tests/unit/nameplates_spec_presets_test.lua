-- tests/unit/nameplates_spec_presets_test.lua
-- Run: lua tests/unit/nameplates_spec_presets_test.lua
--
-- Spec-linked plate presets (v1.1): snapshot/apply round-trip with excluded
-- keys, per-spec storage, ghost-key removal on apply, deep-copy isolation,
-- and auto-switch on PLAYER_SPECIALIZATION_CHANGED.

local function fail(msg)
    print("FAIL: nameplates_spec_presets_test - " .. msg)
    os.exit(1)
end

local function noop() end

wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
local eventFrames = {}
CreateFrame = function()
    local f = { _events = {}, _scripts = {} }
    f.RegisterEvent = function(self, e) self._events[e] = true end
    f.RegisterUnitEvent = function(self, e, u) self._events[e] = u end
    f.SetScript = function(self, k, h) self._scripts[k] = h end
    eventFrames[#eventFrames + 1] = f
    return f
end
local currentSpec = 1
GetSpecialization = function() return currentSpec end
local specRoles = { [1] = "TANK", [2] = "HEALER", [3] = "DAMAGER" }
GetSpecializationRole = function(spec) return specRoles[spec] end

-- Account-wide storage (role presets live in db.global)
QUI = { db = { global = {} } }

local settings = {
    enabled = true,
    health = { width = 156, height = 17, bgColor = { 0.12, 0.12, 0.12 } },
    colors = { hostile = { 0.39, 0.11, 0.09 } },
    specPresets = {},
    specAutoSwitch = false,
}
local refreshCount = 0
local ns = {
    Helpers = {
        GetModuleSettings = function() return settings end,
        IsSecretValue = function() return false end,
    },
    QUI_RefreshNameplates = function() refreshCount = refreshCount + 1 end,
}

assert(loadfile("QUI_Nameplates/nameplates/shared.lua"))("QUI_Nameplates", ns)
-- shared.lua overwrote our refresh stub? No — shared doesn't define it; but
-- keep ours registered after load in case.
ns.QUI_RefreshNameplates = function() refreshCount = refreshCount + 1 end
assert(loadfile("QUI_Nameplates/nameplates/presets.lua"))("QUI_Nameplates", ns)

local Presets = ns.QUI_Nameplates.Presets
if not Presets then fail("NP.Presets not exported") end

local function test(n, f) print(n); f(); print("  ok") end

test("snapshot excludes enabled + preset storage, deep-copies the rest", function()
    local snap = Presets.Snapshot(settings)
    if snap.enabled ~= nil then fail("enabled must not enter a snapshot") end
    if snap.specPresets ~= nil then fail("preset storage must not enter a snapshot") end
    if snap.specAutoSwitch ~= nil then fail("auto-switch flag must not enter a snapshot") end
    if snap.health.width ~= 156 then fail("values must copy") end
    if snap.health == settings.health then fail("snapshot must deep-copy, not alias") end
    snap.health.width = 999
    if settings.health.width ~= 156 then fail("mutating a snapshot must not touch live settings") end
end)

test("save/apply round-trip restores values; live edits don't leak into saved presets", function()
    if not Presets.SaveForSpec(1) then fail("save must succeed") end
    if not Presets.HasPreset(1) then fail("preset must exist after save") end

    settings.health.width = 200
    settings.colors.hostile[1] = 0.9
    settings.health.ghostKey = true   -- added after the snapshot

    if not Presets.ApplyForSpec(1) then fail("apply must succeed") end
    if settings.health.width ~= 156 then fail("apply must restore width") end
    if math.abs(settings.colors.hostile[1] - 0.39) > 1e-9 then fail("apply must restore colors") end
    if settings.health.ghostKey ~= nil then fail("apply must wipe ghost keys from snapshotted tables") end
    if settings.enabled ~= true then fail("apply must not touch enabled") end
    if refreshCount < 1 then fail("apply must trigger the nameplate refresh") end
end)

test("apply for a spec without a preset is a no-op", function()
    local before = refreshCount
    if Presets.ApplyForSpec(3) then fail("apply must fail for an empty slot") end
    if refreshCount ~= before then fail("failed apply must not refresh") end
    if Presets.HasPreset(nil) then fail("nil spec has no preset") end
end)

test("clear removes the stored preset", function()
    Presets.ClearForSpec(1)
    if Presets.HasPreset(1) then fail("clear must remove the preset") end
end)

test("auto-switch applies the new spec's preset on PLAYER_SPECIALIZATION_CHANGED", function()
    settings.health.width = 156
    Presets.SaveForSpec(2)
    settings.health.width = 500

    -- find the presets event frame
    local presetFrame
    for _, f in ipairs(eventFrames) do
        if f._events.PLAYER_SPECIALIZATION_CHANGED then presetFrame = f end
    end
    if not presetFrame then fail("presets event frame missing") end

    -- auto-switch off: nothing happens
    currentSpec = 2
    presetFrame._scripts.OnEvent(presetFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
    if settings.health.width ~= 500 then fail("auto-switch off must not apply") end

    -- auto-switch on: preset applies
    settings.specAutoSwitch = true
    presetFrame._scripts.OnEvent(presetFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
    if settings.health.width ~= 156 then fail("auto-switch must apply the spec's preset") end

    -- other units are ignored
    settings.health.width = 500
    presetFrame._scripts.OnEvent(presetFrame, "PLAYER_SPECIALIZATION_CHANGED", "party1")
    if settings.health.width ~= 500 then fail("non-player spec changes must be ignored") end

    -- disabled module: no auto-switch
    settings.enabled = false
    presetFrame._scripts.OnEvent(presetFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
    if settings.health.width ~= 500 then fail("disabled module must not auto-switch") end
    settings.enabled = true
end)

---------------------------------------------------------------------------
-- Role presets (account-wide tier)
---------------------------------------------------------------------------
local function FindPresetFrame()
    for _, f in ipairs(eventFrames) do
        if f._events.PLAYER_SPECIALIZATION_CHANGED then return f end
    end
end

test("role store lives in db.global and is lazily created", function()
    if QUI.db.global.nameplateRolePresets ~= nil then
        fail("role store must not exist before first use")
    end
    local store = Presets.GetRoleStore()
    if store ~= QUI.db.global.nameplateRolePresets then fail("role store must live in db.global") end
    if store.autoSwitch ~= false then fail("role auto-switch defaults off") end
end)

test("role save/apply round-trip; invalid roles rejected", function()
    settings.health.width = 333
    if not Presets.SaveForRole("TANK") then fail("save for TANK must succeed") end
    if not Presets.HasRolePreset("TANK") then fail("TANK preset must exist") end
    if Presets.SaveForRole("bogus") then fail("invalid role must be rejected") end
    if Presets.HasRolePreset("HEALER") then fail("HEALER slot must be empty") end

    settings.health.width = 111
    if not Presets.ApplyForRole("TANK") then fail("apply for TANK must succeed") end
    if settings.health.width ~= 333 then fail("role apply must restore values") end
    if Presets.ApplyForRole("HEALER") then fail("empty role slot must not apply") end
end)

test("role auto-switch on spec change, gated by the global toggle", function()
    local presetFrame = FindPresetFrame()
    settings.specAutoSwitch = false
    currentSpec = 1 -- TANK

    settings.health.width = 777
    presetFrame._scripts.OnEvent(presetFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
    if settings.health.width ~= 777 then fail("role auto-switch off must not apply") end

    Presets.GetRoleStore().autoSwitch = true
    presetFrame._scripts.OnEvent(presetFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
    if settings.health.width ~= 333 then fail("role auto-switch must apply the TANK preset") end

    -- no preset for the new role → nothing happens
    currentSpec = 2 -- HEALER, empty slot
    settings.health.width = 888
    presetFrame._scripts.OnEvent(presetFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
    if settings.health.width ~= 888 then fail("empty role slot must leave settings alone") end
end)

test("precedence: spec preset beats role preset", function()
    local presetFrame = FindPresetFrame()
    currentSpec = 1 -- TANK role, and spec 1
    settings.health.width = 424
    Presets.SaveForSpec(1)          -- spec preset: width 424
    settings.specAutoSwitch = true  -- both tiers armed; TANK role preset = 333

    settings.health.width = 999
    presetFrame._scripts.OnEvent(presetFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
    if settings.health.width ~= 424 then
        fail("spec preset (more specific) must win over the role preset, got " .. settings.health.width)
    end
end)

test("initial login applies presets; /reload does not", function()
    local presetFrame = FindPresetFrame()
    settings.specAutoSwitch = false
    currentSpec = 1

    settings.health.width = 555
    presetFrame._scripts.OnEvent(presetFrame, "PLAYER_ENTERING_WORLD", false) -- reload
    if settings.health.width ~= 555 then fail("/reload must not re-apply presets") end

    presetFrame._scripts.OnEvent(presetFrame, "PLAYER_ENTERING_WORLD", true) -- fresh login
    if settings.health.width ~= 333 then fail("initial login must apply the role preset") end
end)

test("role clear empties the account-wide slot", function()
    Presets.ClearForRole("TANK")
    if Presets.HasRolePreset("TANK") then fail("clear must remove the role preset") end
end)

print("OK: nameplates_spec_presets_test")
