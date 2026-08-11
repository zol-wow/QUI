local function fail(msg)
    print("FAIL: nameplates_visibility_cvars_test - " .. msg)
    os.exit(1)
end

local function noop() end

CreateFrame = function(_, _, _)
    local f = {
        _events = {},
        RegisterEvent = noop,
        UnregisterEvent = noop,
        SetScript = noop,
        Hide = noop, Show = noop,
    }
    return f
end
InCombatLockdown = function() return false end
local written = {}
SetCVar = function(name, value) written[name] = value end
C_CVar = { SetCVar = noop, SetCVarBitfield = noop }
C_Timer = { After = function(_, fn) fn() end }
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

local liveSettings = { enabled = true, cvars = {} }
local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        GetModuleSettings = function() return liveSettings end,
    },
}

assert(loadfile("QUI_Nameplates/nameplates/shared.lua"))("QUI_Nameplates", ns)
assert(loadfile("QUI_Nameplates/nameplates/cvars.lua"))("QUI_Nameplates", ns)

local NPCVars = ns.QUI_NameplatesCVars
if not NPCVars then fail("ns.QUI_NameplatesCVars not exported") end
if not NPCVars.ResolveUnitVisibility then fail("NPCVars.ResolveUnitVisibility not exported") end

local function eq(label, got, want)
    if got ~= want then
        fail(("%s: expected %s got %s"):format(label, tostring(want), tostring(got)))
    end
end

local map = NPCVars.ResolveUnitVisibility({ showEnemyPets = false, showEnemyMinus = true })
eq("explicit false becomes 0", map.nameplateShowEnemyPets, 0)
eq("explicit true becomes 1", map.nameplateShowEnemyMinus, 1)
eq("unset enemy master defaults on", map.nameplateShowEnemies, 1)
eq("unset enemy key defaults on", map.nameplateShowEnemyTotems, 1)
eq("unset enemy guardians defaults on", map.nameplateShowEnemyGuardians, 1)
eq("unset enemy minions defaults on", map.nameplateShowEnemyMinions, 1)
eq("unset friendly key defaults on", map.nameplateShowFriendlyPlayerPets, 1)
eq("unset friendly totems defaults on", map.nameplateShowFriendlyPlayerTotems, 1)
eq("unset friendly guardians defaults on", map.nameplateShowFriendlyPlayerGuardians, 1)
eq("unset friendly minions defaults on", map.nameplateShowFriendlyPlayerMinions, 1)

local masterOff = NPCVars.ResolveUnitVisibility({ showEnemies = false, showEnemyPets = true, showEnemyMinus = true })
eq("the enemy master forces its children off", masterOff.nameplateShowEnemyPets, 0)
eq("the enemy master forces minor enemies off", masterOff.nameplateShowEnemyMinus, 0)
eq("the enemy master itself reports off", masterOff.nameplateShowEnemies, 0)
eq("the enemy master never touches friendly kinds", masterOff.nameplateShowFriendlyPlayerPets, 1)

local enemyMinionsOff = NPCVars.ResolveUnitVisibility({
    showEnemyMinions = false, showEnemyPets = true, showEnemyTotems = true,
    showEnemyGuardians = true, showEnemyMinus = true,
})
eq("Minions parents enemy pets", enemyMinionsOff.nameplateShowEnemyPets, 0)
eq("Minions parents enemy totems", enemyMinionsOff.nameplateShowEnemyTotems, 0)
eq("Minions parents enemy guardians", enemyMinionsOff.nameplateShowEnemyGuardians, 0)
eq("Minor enemies are a sibling of Minions, not a child",
    enemyMinionsOff.nameplateShowEnemyMinus, 1)
eq("enemy Minions never reaches the friendly side",
    enemyMinionsOff.nameplateShowFriendlyPlayerPets, 1)

local friendlyMinionsOff = NPCVars.ResolveUnitVisibility({
    showFriendlyMinions = false, showFriendlyPets = true,
    showFriendlyTotems = true, showFriendlyGuardians = true,
})
eq("Minions parents friendly pets", friendlyMinionsOff.nameplateShowFriendlyPlayerPets, 0)
eq("Minions parents friendly totems", friendlyMinionsOff.nameplateShowFriendlyPlayerTotems, 0)
eq("Minions parents friendly guardians", friendlyMinionsOff.nameplateShowFriendlyPlayerGuardians, 0)
eq("friendly Minions never reaches the enemy side",
    friendlyMinionsOff.nameplateShowEnemyPets, 1)

local friendlyOff = NPCVars.ResolveUnitVisibility({
    showFriendlyMinions = true, showFriendlyPets = true,
    showFriendlyTotems = true, showFriendlyGuardians = true,
}, true)
eq("friendly mode off zeroes friendly minions", friendlyOff.nameplateShowFriendlyPlayerMinions, 0)
eq("friendly mode off zeroes friendly pets", friendlyOff.nameplateShowFriendlyPlayerPets, 0)
eq("friendly mode off zeroes friendly totems", friendlyOff.nameplateShowFriendlyPlayerTotems, 0)
eq("friendly mode off zeroes friendly guardians", friendlyOff.nameplateShowFriendlyPlayerGuardians, 0)
eq("friendly mode off never reaches the enemy side", friendlyOff.nameplateShowEnemyPets, 1)

local none = NPCVars.ResolveUnitVisibility(nil)
eq("nil settings still resolves enemy default", none.nameplateShowEnemyPets, 1)
eq("nil settings still resolves friendly default", none.nameplateShowFriendlyPlayerPets, 1)

local onAll = NPCVars.ResolveUnitVisibility({
    showEnemies = true,
    showEnemyPets = true, showEnemyTotems = true, showEnemyGuardians = true,
    showEnemyMinions = true, showEnemyMinus = true,
    showFriendlyPets = true, showFriendlyTotems = true,
    showFriendlyGuardians = true, showFriendlyMinions = true,
})
local count = 0
for cvar, value in pairs(onAll) do
    count = count + 1
    if value ~= 1 then fail(cvar .. " should be 1 when its key is true") end
end
eq("resolver covers ten CVars", count, 10)

local offAll = NPCVars.ResolveUnitVisibility({
    showEnemies = false,
    showEnemyPets = false, showEnemyTotems = false, showEnemyGuardians = false,
    showEnemyMinions = false, showEnemyMinus = false,
    showFriendlyPets = false, showFriendlyTotems = false,
    showFriendlyGuardians = false, showFriendlyMinions = false,
})
for cvar, value in pairs(offAll) do
    if value ~= 0 then fail(cvar .. " should be 0 when its key is false") end
end

local src = io.open("QUI_Nameplates/nameplates/cvars.lua", "rb")
if not src then fail("cvars.lua not found") end
local text = src:read("*a")
src:close()
for _, bogus in ipairs({
    "nameplateShowFriendlyPets", "nameplateShowFriendlyTotems", "nameplateShowFriendlyGuardians",
}) do
    if text:find('"' .. bogus .. '"', 1, true) then
        fail(bogus .. " is not a real CVar — the engine name is nameplateShowFriendlyPlayer*")
    end
end
liveSettings.cvars.showFriendlyPets = true
NPCVars.ApplyUnitVisibility()
eq("a ticked QUI toggle writes the CVar", written.nameplateShowFriendlyPlayerPets, 1)

written = {}
liveSettings.cvars.showFriendlyPets = false
NPCVars.ApplyUnitVisibility()
eq("an unticked QUI toggle writes the CVar", written.nameplateShowFriendlyPlayerPets, 0)

written = {}
liveSettings.cvars = { showFriendlyPets = false, showFriendlyMinions = false }
NPCVars.ApplyUnitVisibility()
eq("a value pinned by the old shipped default is unpinned once",
    written.nameplateShowFriendlyPlayerPets, 1)
eq("every friendly kind is unpinned together",
    written.nameplateShowFriendlyPlayerMinions, 1)

written = {}
liveSettings.cvars.showFriendlyPets = false
NPCVars.ApplyUnitVisibility()
eq("after the one-shot runs, an explicit false is honoured again",
    written.nameplateShowFriendlyPlayerPets, 0)

written = {}
liveSettings.cvars = { showEnemyPets = false }
NPCVars.ApplyUnitVisibility()
eq("the unpin never touches the enemy keys", written.nameplateShowEnemyPets, 0)

local NP = ns.QUI_Nameplates
NP.Friendly = { EffectiveMode = function() return "show" end }
NP.Extras = { GetContext = function() return { inInstance = false } end }

written = {}
liveSettings.cvars = {}
NPCVars.ApplyAll()
eq("ApplyAll reaches the visibility CVars", written.nameplateShowFriendlyPlayerPets, 1)
eq("ApplyAll reaches every friendly kind", written.nameplateShowFriendlyPlayerMinions, 1)

written = {}
liveSettings.friendly = { showNPCs = false }
NPCVars.ApplyFriendlyVisibility()
eq("unticking Friendly NPCs drops the NPC CVar", written.nameplateShowFriendlyNpcs, 0)
eq("unticking Friendly NPCs leaves friendly players alone", written.nameplateShowFriendlyPlayers, 1)

written = {}
liveSettings.friendly = { showNPCs = true }
NPCVars.ApplyFriendlyVisibility()
eq("ticking Friendly NPCs raises the NPC CVar", written.nameplateShowFriendlyNpcs, 1)

written = {}
liveSettings.friendly = {}
NPCVars.ApplyFriendlyVisibility()
eq("an absent showNPCs key keeps the shipped open-world behaviour",
    written.nameplateShowFriendlyNpcs, 1)

print("OK: nameplates_visibility_cvars_test")
