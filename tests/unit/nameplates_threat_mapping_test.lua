local function fail(msg)
    print("FAIL: nameplates_threat_mapping_test - " .. msg)
    os.exit(1)
end

local function noop() end

local function NewFrame()
    local f = {
        _events = {},
        _scripts = {},
        RegisterEvent = function(self, e) self._events[e] = true end,
        UnregisterEvent = function(self, e) self._events[e] = nil end,
        SetScript = function(self, k, h) self._scripts[k] = h end,
        GetScript = function(self, k) return self._scripts[k] end,
        Hide = noop, Show = noop, SetAlpha = noop,
    }
    return f
end

local createdFrames = {}
CreateFrame = function(_, _, parent)
    local f = NewFrame(parent)
    createdFrames[#createdFrames + 1] = f
    return f
end

wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
C_Timer = { After = function(_, fn) fn() end }
C_TooltipInfo = nil
UnitName = function(_) return "Selfie" end
GetRaidTargetIndex = function(_) return nil end
UnitHealthPercent = function(_, _, _) return nil end
IsInInstance = function() return true, "party" end

local roster = {}
local roles = {}
local threat = {}

UnitGroupRolesAssigned = function(token)
    if token == "player" then return roles.player or "NONE" end
    return roles[token] or "NONE"
end

IsInRaid = function() return roster._raid == true end
IsInGroup = function() return roster._raid == true or roster._party == true end
UnitExists = function(token) return roster[token] == true end
UnitIsUnit = function(a, b)
    if b ~= "player" then return false end
    return a == roster._playerToken
end
local otherWatcherCalls = 0
UnitThreatSituation = function(watcher, unit)
    if watcher ~= "player" then otherWatcherCalls = otherWatcherCalls + 1 end
    local byUnit = threat[unit]
    return byUnit and byUnit[watcher] or nil
end

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        GetModuleSettings = function() return { enabled = true } end,
    },
    UIKit = {},
    Addon = { Pixels = function(_, v) return v end },
}

assert(loadfile("QUI_Nameplates/nameplates/shared.lua"))("QUI_Nameplates", ns)
assert(loadfile("QUI_Nameplates/nameplates/plate_colors.lua"))("QUI_Nameplates", ns)
assert(loadfile("QUI_Nameplates/nameplates/plate_extras.lua"))("QUI_Nameplates", ns)

local NP = ns.QUI_Nameplates
local Extras = NP and NP.Extras
local Colors = NP and NP.Colors
if not Extras then fail("NP.Extras not exported") end
if not Extras.MapThreatSituation then fail("NPExtras.MapThreatSituation not exported") end
if not Extras.RefreshGroupTanks then fail("NPExtras.RefreshGroupTanks not exported") end
if not Extras.GetGroupTanks then fail("NPExtras.GetGroupTanks not exported") end

local function eq(label, got, want)
    if got ~= want then
        fail(("%s: expected %s got %s"):format(label, tostring(want), tostring(got)))
    end
end

eq("situation 2 always high", Extras.MapThreatSituation(2, false), "high")
eq("situation 3 beats offtank", Extras.MapThreatSituation(3, true), "high")
eq("situation 0 + offtank", Extras.MapThreatSituation(0, true), "offtank")
eq("situation 1 + offtank", Extras.MapThreatSituation(1, true), "offtank")
eq("situation 1 no offtank", Extras.MapThreatSituation(1, false), "near")
eq("situation 0 no offtank", Extras.MapThreatSituation(0, false), "low")
eq("nil situation stays nil", Extras.MapThreatSituation(nil, true), nil)
eq("nil situation no offtank", Extras.MapThreatSituation(nil, false), nil)

local function ResetRoster()
    for k in pairs(roster) do roster[k] = nil end
    for k in pairs(roles) do roles[k] = nil end
    for k in pairs(threat) do threat[k] = nil end
end

local function TankTokens()
    local list = Extras.GetGroupTanks()
    local out = {}
    for i = 1, #list do out[i] = list[i] end
    table.sort(out)
    return table.concat(out, ",")
end

ResetRoster()
Extras.RefreshGroupTanks()
eq("solo roster is empty", TankTokens(), "")

ResetRoster()
roster._party = true
roster._playerToken = "party2"
roster.party1, roster.party2, roster.party3 = true, true, true
roles.party1, roles.party2, roles.party3 = "TANK", "TANK", "HEALER"
Extras.RefreshGroupTanks()
eq("party scan excludes player and non-tanks", TankTokens(), "party1")

ResetRoster()
roster._raid = true
roster._playerToken = "raid3"
roster.raid1, roster.raid2, roster.raid3 = true, true, true
roles.raid1, roles.raid2, roles.raid3 = "DAMAGER", "TANK", "TANK"
Extras.RefreshGroupTanks()
eq("raid scan uses raid prefix", TankTokens(), "raid2")

ResetRoster()
roster._party = true
roster._playerToken = "party3"
roster.party1, roster.party2 = true, true
roles.party1, roles.party2 = "TANK", "TANK"
Extras.RefreshGroupTanks()
eq("two off-tanks both tracked", TankTokens(), "party1,party2")

roles.player = "TANK"
Extras.RefreshContext()
eq("context role is TANK for the integration cases", Extras.GetContext().role, "TANK")

local plate = { unit = "nameplate1" }

threat["nameplate1"] = { player = 3 }
Extras.UpdateThreat(plate)
eq("player tanking wins over off-tank scan", plate.npThreat, "high")

threat["nameplate1"] = { player = 0, party1 = 3 }
Extras.UpdateThreat(plate)
eq("off-tank holds aggro", plate.npThreat, "offtank")

threat["nameplate1"] = { player = 0, party1 = 1 }
Extras.UpdateThreat(plate)
eq("off-tank only near aggro is not offtank", plate.npThreat, "low")

threat["nameplate1"] = { player = 1 }
Extras.UpdateThreat(plate)
eq("no off-tank aggro falls back to near", plate.npThreat, "near")

threat["nameplate1"] = {}
Extras.UpdateThreat(plate)
eq("no threat data clears", plate.npThreat, nil)

local scanBaseline = otherWatcherCalls
threat["nameplate1"] = { player = 2, party1 = 3 }
Extras.UpdateThreat(plate)
eq("tanking short-circuits the off-tank scan", otherWatcherCalls - scanBaseline, 0)

local scopeSettings = {
    colors = {
        hostile = { 0.39, 0.11, 0.09 },
        threatEnabled = true,
        tankHasAggro = { 0.05, 0.82, 0.62 },
        tankNoAggro = { 1, 0.22, 0.17 },
        offTankAggro = { 0.188, 0.761, 0.812 },
        oocDarken = false,
    },
}
local worldPlate = { npReaction = "hostile", npThreat = "high", npInCombat = true }
local world = { role = "TANK", inInstance = false }

local r = Colors.Resolve(worldPlate, scopeSettings, world)
eq("threat is instance-gated by default", r, 0.39)

scopeSettings.colors.threatInstancesOnly = false
r = Colors.Resolve(worldPlate, scopeSettings, world)
eq("threatInstancesOnly=false colors in the open world", r, 0.05)

scopeSettings.colors.threatInstancesOnly = true
r = Colors.Resolve(worldPlate, scopeSettings, world)
eq("threatInstancesOnly=true restores the gate", r, 0.39)

r = Colors.Resolve(worldPlate, scopeSettings, { role = "TANK", inInstance = true })
eq("instances still color with the gate on", r, 0.05)

local rosterEventFrame
for i = 1, #createdFrames do
    local f = createdFrames[i]
    if f._events["GROUP_ROSTER_UPDATE"] then rosterEventFrame = f end
end
if not rosterEventFrame then
    fail("plate_extras must register GROUP_ROSTER_UPDATE to keep the tank roster fresh")
end
if not rosterEventFrame._events["PLAYER_ROLES_ASSIGNED"] then
    fail("roster frame must also refresh on PLAYER_ROLES_ASSIGNED")
end

ResetRoster()
roster._party = true
roster._playerToken = "party3"
roster.party1 = true
roles.party1 = "TANK"
rosterEventFrame._scripts.OnEvent(rosterEventFrame, "GROUP_ROSTER_UPDATE")
eq("GROUP_ROSTER_UPDATE rescans", TankTokens(), "party1")

print("OK: nameplates_threat_mapping_test")
