-- tests/unit/nameplates_profiles_test.lua
-- Named, account-wide nameplate profiles: snapshot round-trip with excluded
-- keys, store CRUD, specID-keyed assignments (NOT spec index — index keying
-- collided across classes), role fallback, and auto-switch events.

local function fail(msg)
    print("FAIL: nameplates_profiles_test - " .. msg)
    os.exit(1)
end

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

-- Simulated character: spec INDEX -> global specID + role. Swapping specInfo
-- mid-test simulates logging onto another class where the same index resolves
-- to a different specID.
local currentSpec = 1
local specInfo = {
    [1] = { id = 577, name = "Havoc", role = "DAMAGER" },
    [2] = { id = 581, name = "Vengeance", role = "TANK" },
}
GetSpecialization = function() return currentSpec end
GetSpecializationInfo = function(index)
    local info = specInfo[index]
    if not info then return nil end
    return info.id, info.name
end
GetSpecializationRole = function(index)
    local info = specInfo[index]
    return info and info.role or nil
end

QUI = { db = { global = {}, char = {} } }

local settings = {
    enabled = true,
    health = { width = 156, height = 17, bgColor = { 0.12, 0.12, 0.12 } },
    colors = { hostile = { 0.39, 0.11, 0.09 } },
}
local refreshCount = 0
local ns = {
    Helpers = {
        GetModuleSettings = function() return settings end,
        IsSecretValue = function() return false end,
    },
}

assert(loadfile("QUI_Nameplates/nameplates/shared.lua"))("QUI_Nameplates", ns)
ns.QUI_RefreshNameplates = function() refreshCount = refreshCount + 1 end
assert(loadfile("QUI_Nameplates/nameplates/presets.lua"))("QUI_Nameplates", ns)

local Presets = ns.QUI_Nameplates.Presets
if not Presets then fail("NP.Presets not exported") end

local function test(n, f) print(n); f(); print("  ok") end

local function FindPresetFrame()
    for _, f in ipairs(eventFrames) do
        if f._events.PLAYER_SPECIALIZATION_CHANGED then return f end
    end
end

test("store and assignments live in db.global and are lazily created", function()
    if QUI.db.global.nameplateProfiles ~= nil then fail("store must not exist before first use") end
    local store = Presets.GetProfileStore()
    if store ~= QUI.db.global.nameplateProfiles then fail("store must live in db.global") end
    local assignments = Presets.GetAssignments()
    if assignments ~= QUI.db.global.nameplateProfileAssignments then fail("assignments must live in db.global") end
    if assignments.autoSwitch ~= false then fail("auto-switch defaults off") end
    if type(assignments.specs) ~= "table" or type(assignments.roles) ~= "table" then
        fail("assignments must seed specs/roles maps")
    end
end)

test("save/apply round-trip; ghost keys wiped; name trimmed; empty rejected", function()
    local ok, savedName = Presets.SaveProfile("  Tank Plates  ")
    if not ok or savedName ~= "Tank Plates" then fail("save must trim and succeed") end
    if not Presets.HasProfile("Tank Plates") then fail("profile must exist after save") end
    if Presets.SaveProfile("   ") then fail("blank names must be rejected") end
    if Presets.SaveProfile("__none") then fail("the UI's no-profile sentinel must be rejected as a name") end
    if Presets.SaveProfile("  __none  ") then fail("the reserved name must be rejected after trimming too") end

    local snap = Presets.GetProfileStore()["Tank Plates"]
    if snap.enabled ~= nil then fail("enabled must not enter a snapshot") end
    if snap.health == settings.health then fail("snapshot must deep-copy, not alias") end

    settings.health.width = 200
    settings.colors.hostile[1] = 0.9
    settings.health.ghostKey = true

    if not Presets.ApplyProfile("Tank Plates") then fail("apply must succeed") end
    if settings.health.width ~= 156 then fail("apply must restore width") end
    if math.abs(settings.colors.hostile[1] - 0.39) > 1e-9 then fail("apply must restore colors") end
    if settings.health.ghostKey ~= nil then fail("apply must wipe ghost keys") end
    if settings.enabled ~= true then fail("apply must not touch enabled") end
    if refreshCount < 1 then fail("apply must trigger the nameplate refresh") end
    if Presets.ApplyProfile("Nope") then fail("unknown profile must not apply") end
end)

test("list is sorted case-insensitively", function()
    settings.health.width = 111
    Presets.SaveProfile("aoe farm")
    Presets.SaveProfile("Boss Focus")
    local names = Presets.ListProfileNames()
    if #names ~= 3 then fail("expected 3 profiles, got " .. #names) end
    if names[1] ~= "aoe farm" or names[2] ~= "Boss Focus" or names[3] ~= "Tank Plates" then
        fail("list must sort case-insensitively: " .. table.concat(names, ", "))
    end
end)

test("assignments are keyed by global specID, not spec index", function()
    if Presets.GetCurrentSpecID() ~= 577 then fail("current specID must resolve via GetSpecializationInfo") end
    if not Presets.AssignSpec(581, "Tank Plates") then fail("assign by specID must succeed") end
    if Presets.AssignSpec(581, "Missing") then fail("assigning an unknown profile must fail") end
    if Presets.AssignSpec(0, "Tank Plates") then fail("invalid specID must fail") end
    if Presets.GetSpecAssignment(581) ~= "Tank Plates" then fail("assignment must read back") end
    if Presets.GetSpecAssignment(258) ~= nil then fail("other specIDs must be unassigned") end
    if not Presets.AssignRole("DAMAGER", "aoe farm") then fail("role assign must succeed") end
    if Presets.AssignRole("bogus", "aoe farm") then fail("invalid role must fail") end
end)

test("rename moves the snapshot and rewrites assignments", function()
    if Presets.RenameProfile("Tank Plates", "aoe farm") then fail("rename onto an existing name must fail") end
    if Presets.RenameProfile("Tank Plates", "__none") then fail("rename to the reserved sentinel name must fail") end
    if not Presets.RenameProfile("Tank Plates", "VDH Plates") then fail("rename must succeed") end
    if Presets.HasProfile("Tank Plates") then fail("old name must be gone") end
    if Presets.GetSpecAssignment(581) ~= "VDH Plates" then fail("spec assignment must follow the rename") end
end)

test("delete clears every assignment pointing at the profile", function()
    Presets.AssignRole("TANK", "VDH Plates")
    if not Presets.DeleteProfile("VDH Plates") then fail("delete must succeed") end
    if Presets.HasProfile("VDH Plates") then fail("profile must be gone") end
    if Presets.GetSpecAssignment(581) ~= nil then fail("spec assignment must be cleared") end
    if Presets.GetRoleAssignment("TANK") ~= nil then fail("role assignment must be cleared") end
end)

test("auto-switch: spec assignment wins, role is the fallback, toggle gates all", function()
    local presetFrame = FindPresetFrame()
    if not presetFrame then fail("presets event frame missing") end

    settings.health.width = 156
    Presets.SaveProfile("VDH Plates")
    Presets.AssignSpec(581, "VDH Plates")
    settings.health.width = 42
    Presets.SaveProfile("Role Tank")
    Presets.AssignRole("TANK", "Role Tank")

    -- toggle off: nothing happens
    currentSpec = 2 -- Vengeance (581, TANK)
    settings.health.width = 500
    presetFrame._scripts.OnEvent(presetFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
    if settings.health.width ~= 500 then fail("auto-switch off must not apply") end

    -- toggle on: spec assignment beats role assignment
    Presets.SetAutoSwitch(true)
    presetFrame._scripts.OnEvent(presetFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
    if settings.health.width ~= 156 then fail("spec assignment must win over role, got " .. settings.health.width) end

    -- spec unassigned: role fallback applies
    Presets.AssignSpec(581, nil)
    settings.health.width = 500
    presetFrame._scripts.OnEvent(presetFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
    if settings.health.width ~= 42 then fail("role fallback must apply, got " .. settings.health.width) end

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

test("same spec index on another class resolves to a different specID — no crossover", function()
    Presets.AssignSpec(581, "VDH Plates")
    -- "log onto a priest": index 2 now resolves to Holy (257), HEALER
    specInfo[1] = { id = 256, name = "Discipline", role = "HEALER" }
    specInfo[2] = { id = 257, name = "Holy", role = "HEALER" }
    currentSpec = 2

    local presetFrame = FindPresetFrame()
    settings.health.width = 500
    presetFrame._scripts.OnEvent(presetFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
    if settings.health.width ~= 500 then
        fail("a Vengeance assignment must NOT fire for Holy just because both are spec #2")
    end

    -- restore the DH mapping for later tests
    specInfo[1] = { id = 577, name = "Havoc", role = "DAMAGER" }
    specInfo[2] = { id = 581, name = "Vengeance", role = "TANK" }
    currentSpec = 2
end)

test("active-profile tracking: apply/save set it, edits mark it modified, rename/delete follow", function()
    settings.health.width = 156
    Presets.SaveProfile("Tracked")
    if Presets.GetLastAppliedProfile() ~= "Tracked" then
        fail("saving current settings into a profile must mark it active")
    end
    if Presets.IsActiveProfileModified() then fail("freshly saved profile must not read as modified") end

    settings.health.width = 999
    if not Presets.IsActiveProfileModified() then fail("live edits must mark the active profile modified") end

    Presets.ApplyProfile("Tracked")
    if Presets.IsActiveProfileModified() then fail("re-applying must clear the modified state") end
    if settings.health.width ~= 156 then fail("apply sanity") end

    Presets.RenameProfile("Tracked", "Tracked2")
    if Presets.GetLastAppliedProfile() ~= "Tracked2" then fail("rename must carry the active marker") end

    Presets.DeleteProfile("Tracked2")
    if Presets.GetLastAppliedProfile() ~= nil then fail("deleting the active profile must clear the marker") end
    if Presets.IsActiveProfileModified() then fail("no active profile means nothing is modified") end

    -- applying an assignment via auto-switch also updates the marker
    Presets.SaveProfile("VDH Plates")
    Presets.AssignSpec(581, "VDH Plates")
    Presets.SetAutoSwitch(true)
    currentSpec = 2
    local presetFrame = FindPresetFrame()
    QUI.db.char.nameplateActiveProfile = nil
    presetFrame._scripts.OnEvent(presetFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
    if Presets.GetLastAppliedProfile() ~= "VDH Plates" then
        fail("auto-switch must record the applied profile")
    end
end)

test("initial login applies the assignment; /reload does not", function()
    local presetFrame = FindPresetFrame()
    settings.health.width = 555
    presetFrame._scripts.OnEvent(presetFrame, "PLAYER_ENTERING_WORLD", false) -- reload
    if settings.health.width ~= 555 then fail("/reload must not re-apply") end

    presetFrame._scripts.OnEvent(presetFrame, "PLAYER_ENTERING_WORLD", true) -- fresh login
    if settings.health.width ~= 156 then fail("initial login must apply the spec assignment") end
end)

print("OK: nameplates_profiles_test")
