local function fail(msg)
    print("FAIL: nameplates_visibility_unpin_test - " .. msg)
    os.exit(1)
end

local function noop() end

local written = {}
SetCVar = function(name, value) written[name] = value end
InCombatLockdown = function() return false end
C_CVar = { SetCVar = noop, SetCVarBitfield = noop }
C_Timer = { After = function(_, fn) fn() end }
CreateFrame = function()
    return { RegisterEvent = noop, UnregisterEvent = noop, SetScript = noop, Hide = noop, Show = noop }
end

local env = dofile("tools/_addon_env.lua")
local harness = env.LoadHarness({
    QUI_DB = {
        profileKeys = { ["TestChar - TestRealm"] = "Default" },
        profiles = {
            Default = {
                _defaultsVersion = 3,
                nameplates = { enabled = true },
            },
        },
    },
    QUIDB = {},
}, { noSeed = true })

local ns = harness.ns
local db = harness.db

local rawNameplates = db.profile.nameplates
if rawget(rawNameplates, "cvars") == nil then
    fail("expected AceDB copyDefaults to have fabricated nameplates.cvars before anything ran")
end
if rawNameplates.cvars.showFriendlyPets ~= true then
    fail("setup: the shipped default must be true, got "
        .. tostring(rawNameplates.cvars.showFriendlyPets))
end

if not (ns.Compatibility and ns.Compatibility.RunShippedDefaultsMaintenance) then
    fail("ns.Compatibility.RunShippedDefaultsMaintenance not exported")
end

db.global = db.global or {}
db.global._shippedProfileDefaults = { nameplates = { cvars = { showFriendlyPets = false } } }
rawNameplates.cvars.showFriendlyPets = nil

ns.Compatibility.RunShippedDefaultsMaintenance(db)

if rawget(rawNameplates.cvars, "showFriendlyPets") ~= false then
    fail("setup: PinDefaultsRecursive was expected to pin the OLD default false into the profile, got "
        .. tostring(rawget(rawNameplates.cvars, "showFriendlyPets")))
end

assert(loadfile("QUI_Nameplates/nameplates/shared.lua"))("QUI_Nameplates", ns)
assert(loadfile("QUI_Nameplates/nameplates/cvars.lua"))("QUI_Nameplates", ns)

local NPCVars = ns.QUI_NameplatesCVars
NPCVars.ApplyUnitVisibility()

if written.nameplateShowFriendlyPlayerPets ~= 1 then
    fail("a profile carrying the pinned old default must be unpinned to 1, got "
        .. tostring(written.nameplateShowFriendlyPlayerPets))
end

written = {}
db.profile.nameplates.cvars.showFriendlyPets = false
NPCVars.ApplyUnitVisibility()
if written.nameplateShowFriendlyPlayerPets ~= 0 then
    fail("after the one-shot, a deliberate untick must survive, got "
        .. tostring(written.nameplateShowFriendlyPlayerPets))
end

print("OK: nameplates_visibility_unpin_test")
