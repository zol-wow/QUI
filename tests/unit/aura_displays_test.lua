local function fail(msg)
    print("FAIL: aura_displays_test - " .. msg)
    os.exit(1)
end

local profile = {}
local ns = {}
ns.Helpers = {
    GetProfile = function() return profile end,
    GetModuleSettings = function(name, defaults)
        if not profile[name] then
            profile[name] = {}
            for k, v in pairs(defaults or {}) do profile[name][k] = v end
        end
        return profile[name]
    end,
}

assert(loadfile("core/aura_elements.lua"))("QUI", ns)
local AuraElements = ns.AuraElements
assert(loadfile("core/aura_glue.lua"))("QUI", ns)

assert(loadfile("modules/trackers/aura_displays.lua"))("QUI", ns)
local AD = ns.QUI_AuraDisplays
if not AD or type(AD.NewDisplay) ~= "function" then
    fail("ns.QUI_AuraDisplays.NewDisplay must be exported")
end

local store = AD.Store()
if type(store) ~= "table" then fail("Store must return a table") end
if type(store.displays) ~= "table" or type(store.order) ~= "table"
    or type(store.groups) ~= "table" then
    fail("Store must guarantee displays, order and groups tables")
end

local a = AD.NewDisplay("First")
if a.id ~= "d1" then fail("first display id must be d1, got " .. tostring(a.id)) end
if a.unitMode ~= "token" or a.unit ~= "player" then
    fail("new display must default to the player token")
end
if a.layout.direction ~= "RIGHT" or a.layout.alignment ~= "CENTER"
    or a.layout.spacing ~= 2 then
    fail("new display must default to a centered rightward row layout")
end
if type(a.auras) ~= "table" or a.auras.elements ~= nil then
    fail("new display must leave auras.elements unset so EnsureSeeded can seed it")
end
if type(a.load) ~= "table" or type(a.load.classes) ~= "table" then
    fail("new display must carry an empty load condition table")
end

AuraElements.EnsureSeeded(a.auras, AD.DefaultBucket)
if type(a.auras.elements) ~= "table" or type(a.auras.elements["*"]) ~= "table"
    or #a.auras.elements["*"] == 0 then
    fail("EnsureSeeded must seed a non-empty default bucket into auras.elements['*']")
end

local firstTracked = AuraElements.NewTrackedElement({ 101 }, "icon")
local secondTracked = AuraElements.NewTrackedElement({ 202 }, "icon")
local layout = AD.ResolveDisplayLayout({ firstTracked, secondTracked })
if layout.placements[secondTracked].offsetX ~= 18 or layout.width ~= 34 then
    fail("default tracked rows must auto-flow with one icon gap")
end

local containerLayout = { layout = { direction = "DOWN", alignment = "END", spacing = 4 } }
local vertical = AD.ResolveDisplayLayout(containerLayout, { firstTracked, secondTracked })
if vertical.width ~= 16 or vertical.height ~= 36
    or vertical.placements[secondTracked].offsetY ~= -20
    or vertical.placements[secondTracked].offsetX ~= 0 then
    fail("display row layout must stack rows using the container direction and alignment")
end

local centeredSingle = AuraElements.NewTrackedElement({ 303 }, "icon")
centeredSingle.growDirection = "CENTER"
centeredSingle.spacing = 8
local singleProfile = AD.ResolveDisplayLayout({}, { centeredSingle }).profiles[centeredSingle]
if singleProfile.grow ~= "RIGHT" or singleProfile.spacing ~= 0 then
    fail("single-spell tracked rows must use a stable one-icon layout profile")
end
local multiTracked = AuraElements.NewTrackedElement({ 404, 505 }, "icon")
multiTracked.growDirection = "CENTER"
multiTracked.spacing = 8
local multiProfile = AD.ResolveDisplayLayout({}, { multiTracked }).profiles[multiTracked]
if multiProfile.grow ~= "CENTER" or multiProfile.spacing ~= 8 then
    fail("multi-spell tracked rows must retain their internal grow layout")
end

local unlimitedStrip = AuraElements.NewFilterStripElement("HELPFUL")
unlimitedStrip.maxIcons = 0
local previewLayout = AD.ResolveDisplayLayout({ unlimitedStrip }, true)
if previewLayout.profiles[unlimitedStrip].maxIcons ~= 3 then
    fail("Aura Displays preview must not reserve 40 icons for an unlimited strip")
end

local b = AD.NewDisplay("Second")
if b.id ~= "d2" then fail("second display id must be d2, got " .. tostring(b.id)) end
if #store.order ~= 2 or store.order[1] ~= "d1" or store.order[2] ~= "d2" then
    fail("order must append new displays")
end

if AD.MoveDisplay ~= nil then
    fail("AD.MoveDisplay was replaced by MoveDisplayWithinGroup and must not come back")
end

local dup = AD.DuplicateDisplay("d1", "First Copy")
if dup.id ~= "d3" then fail("duplicate must take a fresh id, got " .. tostring(dup.id)) end
if dup.name ~= "First Copy" then fail("duplicate must take the supplied name") end
if dup.auras.elements == a.auras.elements then
    fail("duplicate must deep copy the aura store, not alias it")
end
if dup.auras._elementIDsBackfilled ~= nil then
    fail("duplicate must clear the backfill flag so the copy re-uniquifies its element ids")
end
for _, bucket in pairs(dup.auras.elements) do
    for i = 1, #bucket do
        if bucket[i].id ~= nil then
            fail("duplicate must clear copied element ids, got " .. tostring(bucket[i].id))
        end
    end
end
AuraElements.EnsureSeeded(dup.auras, AD.DefaultBucket)
local sourceElementID = a.auras.elements["*"][1].id
local copyElementID = dup.auras.elements["*"][1].id
if copyElementID == nil or copyElementID == sourceElementID then
    fail("a re-seeded copy must mint an element id distinct from its source, got "
        .. tostring(copyElementID) .. " against " .. tostring(sourceElementID))
end

profile.frameAnchoring = { auraDisplay_d1 = { offsetX = 10 } }
if not AD.DeleteDisplay("d1") then fail("DeleteDisplay must succeed for a live id") end
if store.displays["d1"] ~= nil then fail("DeleteDisplay must remove the display") end
for i = 1, #store.order do
    if store.order[i] == "d1" then fail("DeleteDisplay must remove the order entry") end
end
if profile.frameAnchoring.auraDisplay_d1 ~= nil then
    fail("DeleteDisplay must drop the frameAnchoring entry")
end

local reused = AD.NewDisplay("After Delete")
if reused.id ~= "d4" then
    fail("ids must not be reused after a delete, got " .. tostring(reused.id))
end

local x = AD.NewDisplay("X")
local y = AD.NewDisplay("Y")
if not AD.DeleteDisplay(y.id) then
    fail("DeleteDisplay must succeed for the highest-id display")
end
local afterHighDelete = AD.NewDisplay("After High Delete")
local xNum = tonumber(x.id:match("%d+"))
local yNum = tonumber(y.id:match("%d+"))
local newNum = tonumber(afterHighDelete.id:match("%d+"))
if not (newNum > xNum and newNum > yNum) then
    fail("ids must not be reused after deleting the highest id, got " .. tostring(afterHighDelete.id))
end

if not AD.GroupEnabled("Raid") then fail("an unknown group must count as enabled") end
AD.SetGroupEnabled("Raid", false)
if AD.GroupEnabled("Raid") then fail("SetGroupEnabled(false) must disable the group") end
if not AD.GroupEnabled(nil) then fail("a nil group must count as enabled") end

local raidGroup = AD.GetGroup("Raid", false)
if type(raidGroup) ~= "table" or not tostring(raidGroup.id):match("^g%d+$") then
    fail("creating group state must mint a stable group id")
end
if raidGroup.growDirection ~= "RIGHT" or raidGroup.alignment ~= "CENTER"
    or raidGroup.spacing ~= 4 or raidGroup.scale ~= 1
    or raidGroup.itemWidth ~= 0 or raidGroup.itemHeight ~= 0 then
    fail("new groups must carry complete layout defaults")
end
local raidAnchorKey = AD.GroupAnchorKey("Raid", false)
if raidAnchorKey ~= AD.GROUP_ANCHOR_PREFIX .. raidGroup.id then
    fail("GroupAnchorKey must use the group's stable id")
end

AD.SetGroupEnabled("", false)
if not AD.GroupEnabled("") then
    fail("an empty group name must never gate visibility - no header renders controls for it")
end
if store.groups[""] ~= nil then
    fail("SetGroupEnabled must not mint a store entry for an empty group name")
end

if AD.RenameGroup("Raid", "Mythic") ~= true then
    fail("RenameGroup must succeed when the new name is free")
end
if store.groups["Raid"] ~= nil then fail("RenameGroup must drop the old group entry") end
if AD.GroupEnabled("Mythic") then
    fail("RenameGroup must carry the group's disabled state across to the new name")
end
if AD.GroupAnchorKey("Mythic", false) ~= raidAnchorKey then
    fail("RenameGroup must preserve the group's layout anchor key")
end

local renameMember = AD.NewDisplay("Member")
renameMember.group = "Mythic"
if AD.RenameGroup("Mythic", "Renamed") ~= true then
    fail("RenameGroup must succeed when the group has members")
end
if renameMember.group ~= "Renamed" then
    fail("RenameGroup must move every member to the new name, got "
        .. tostring(renameMember.group))
end

if AD.RenameGroup("Renamed", "Renamed") ~= true then
    fail("renaming a group to its current name must be a successful no-op")
end

AD.SetGroupEnabled("Heroic", true)
local collideOK, collideReason = AD.RenameGroup("Renamed", "Heroic")
if collideOK ~= false or collideReason ~= "collision" then
    fail("RenameGroup must report a name collision as false, 'collision', got "
        .. tostring(collideOK) .. ", " .. tostring(collideReason))
end

local implicitMember = AD.NewDisplay("Implicit")
implicitMember.group = "Legacy"
local implicitOK, implicitReason = AD.RenameGroup("Renamed", "Legacy")
if implicitOK ~= false or implicitReason ~= "collision" then
    fail("RenameGroup must detect a group that exists only on a display, got "
        .. tostring(implicitOK) .. ", " .. tostring(implicitReason))
end

local emptyOK, emptyReason = AD.RenameGroup("Renamed", "")
if emptyOK ~= false or emptyReason ~= "invalid" then
    fail("RenameGroup must reject an empty new name as false, 'invalid', got "
        .. tostring(emptyOK) .. ", " .. tostring(emptyReason))
end
if AD.RenameGroup(nil, "Anything") ~= false then
    fail("RenameGroup must reject a nil old name")
end
if AD.RenameGroup("Renamed", 7) ~= false then
    fail("RenameGroup must reject a non-string new name")
end

local deleteGroupMember = AD.NewDisplay("Delete Group Member")
deleteGroupMember.group = "Disposable"
local disposable = AD.GetGroup("Disposable", true)
local disposableAnchor = AD.GroupAnchorKey("Disposable", false)
profile.frameAnchoring = profile.frameAnchoring or {}
profile.frameAnchoring[disposableAnchor] = { offsetX = 25 }
if not AD.DeleteGroup("Disposable") then fail("DeleteGroup must remove a real group") end
if deleteGroupMember.group ~= nil then
    fail("DeleteGroup must make its former members ungrouped")
end
if profile.frameAnchoring[disposableAnchor] ~= nil then
    fail("DeleteGroup must remove the stable group layout anchor")
end
if AD.GetGroup("Disposable", false) ~= nil or disposable == nil then
    fail("DeleteGroup must remove group settings without invalidating the captured test value")
end

local layoutMembers = {
    { id = "a", width = 10, height = 8 },
    { id = "b", width = 20, height = 12 },
    { id = "c", width = 6, height = 10 },
}
local layoutW, layoutH, placed = AD.ComputeGroupLayout({
    growDirection = "RIGHT", alignment = "CENTER", spacing = 2,
}, layoutMembers)
if layoutW ~= 40 or layoutH ~= 12 then
    fail("RIGHT group extent must include member sizes and spacing")
end
if placed[1].x ~= 5 or placed[2].x ~= 22 or placed[3].x ~= 37 then
    fail("RIGHT group growth must preserve member order from left to right")
end
if placed[1].y ~= -6 or placed[2].y ~= -6 then
    fail("CENTER group alignment must share the cross-axis center")
end

layoutW, layoutH, placed = AD.ComputeGroupLayout({
    growDirection = "LEFT", alignment = "START", spacing = 2,
}, layoutMembers)
if placed[1].x ~= 35 or placed[2].x ~= 18 or placed[3].x ~= 3 then
    fail("LEFT group growth must place the first member at the right edge")
end
if placed[1].y ~= -4 or placed[2].y ~= -6 then
    fail("START group alignment must align horizontal members to the top edge")
end

layoutW, layoutH, placed = AD.ComputeGroupLayout({
    growDirection = "CENTER_H", alignment = "END", spacing = 2,
}, {
    { id = "a", width = 10, height = 8 },
    { id = "b", width = 10, height = 8 },
    { id = "c", width = 10, height = 8 },
})
if layoutW ~= 34 or placed[1].x ~= 17 or placed[2].x ~= 29 or placed[3].x ~= 5 then
    fail("CENTER_H group growth must alternate members around the anchor")
end

layoutW, layoutH, placed = AD.ComputeGroupLayout({
    growDirection = "UP", alignment = "END", spacing = 3,
    itemWidth = 30, itemHeight = 14,
}, layoutMembers)
if layoutW ~= 30 or layoutH ~= 48 then
    fail("forced member size must define the group extent")
end
if placed[1].y ~= -41 or placed[3].y ~= -7 then
    fail("UP group growth must place the first member at the bottom edge")
end

local emptyW, emptyH, emptyLayout = AD.ComputeGroupLayout({}, {})
if emptyW ~= 1 or emptyH ~= 1 or #emptyLayout ~= 0 then
    fail("an empty group must retain a safe 1x1 layout")
end

local ordered = AD.OrderedDisplays()
if #ordered ~= #store.order then
    fail("OrderedDisplays must return one entry per order id, got " .. #ordered)
end
if ordered[1].id ~= store.order[1] then fail("OrderedDisplays must follow order") end

local function OrderIndex(id)
    for i = 1, #store.order do
        if store.order[i] == id then return i end
    end
    return nil
end

local moveA = AD.NewDisplay("MoveA")
local moveB = AD.NewDisplay("MoveB")
local moveC = AD.NewDisplay("MoveC")
moveA.group = "g1"
moveB.group = "g2"
moveC.group = "g1"

local moveAIndex, moveBIndex, moveCIndex =
    OrderIndex(moveA.id), OrderIndex(moveB.id), OrderIndex(moveC.id)
if not (moveAIndex < moveBIndex and moveBIndex < moveCIndex) then
    fail("test setup must interleave MoveA, MoveB, MoveC in that order")
end

if not AD.MoveDisplayWithinGroup(moveA.id, 1) then
    fail("MoveDisplayWithinGroup must move past an interleaved other-group member")
end
if OrderIndex(moveA.id) ~= moveCIndex then
    fail("MoveDisplayWithinGroup must land in its same-group neighbour's old slot")
end
if OrderIndex(moveC.id) ~= moveAIndex then
    fail("MoveDisplayWithinGroup must swap the neighbour into the moved display's old slot")
end
if OrderIndex(moveB.id) ~= moveBIndex then
    fail("MoveDisplayWithinGroup must not disturb an interleaved other-group member")
end

if AD.MoveDisplayWithinGroup(moveB.id, -1) or AD.MoveDisplayWithinGroup(moveB.id, 1) then
    fail("MoveDisplayWithinGroup must refuse to move a display with no same-group neighbour")
end

local roster = {}
local playerRealm = "Ravencrest"
local SECRET = setmetatable({}, { __tostring = function() return "SECRET" end })
local SECRET_NAME = "<secret-string>"

GetNumGroupMembers = function() return #roster end
IsInRaid = function() return #roster > 5 end
UnitFullName = function(unit)
    local entry = roster[unit]
    if not entry then return nil end
    return entry.name, entry.realm
end
UnitGroupRolesAssigned = function(unit)
    local entry = roster[unit]
    return entry and entry.role or "NONE"
end
UnitIsUnit = function(a, b) return a == b end
GetNormalizedRealmName = function() return playerRealm end
issecretvalue = function(v) return v == SECRET or v == SECRET_NAME end

ns.Helpers.FoldUTF8 = function(text)
    if text == SECRET_NAME then error("string operation on a secret value", 0) end
    if type(text) ~= "string" then return text end
    return (text:gsub("\195[\128-\158]", function(pair)
        return "\195" .. string.char(pair:byte(2) + 0x20)
    end)):lower()
end
ns.Helpers.GetCurrentSpecID = function() return 105 end
ns.Helpers.UnitTokenMatches = function(a, b) return UnitIsUnit(a, b) end
ns.QUI_AuraWizard = { PlayerRole = function() return "HEALER" end }
UnitClass = function() return "Druid", "DRUID" end

local function SetRoster(entries)
    roster = {}
    for i, entry in ipairs(entries) do
        local token = entry.token or ("party" .. i)
        roster[token] = entry
        roster[i] = entry
    end
end

local tokenDisplay = { unitMode = "token", unit = "boss1", enabled = true,
    load = { classes = {}, specs = {}, roles = {}, encounters = {} } }
if AD.ResolveUnit(tokenDisplay) ~= "boss1" then
    fail("a static token must pass through unchanged")
end

local badToken = { unitMode = "token", unit = "notaunit" }
if AD.ResolveUnit(badToken) ~= nil then fail("an unknown token must resolve to nil") end

SetRoster({
    { token = "player", name = "Zaebos", realm = "", role = "HEALER" },
    { token = "party1", name = "Ürsa", realm = "", role = "TANK" },
    { token = "party2", name = "Kaltar", realm = "Draenor", role = "TANK" },
    { token = "party3", name = "Fenrir", realm = "AzjolNerub", role = "DAMAGER" },
})

local byName = { unitMode = "name", unit = "Kaltar" }
if AD.ResolveUnit(byName) ~= "party2" then
    fail("a bare name must match regardless of realm, got " .. tostring(AD.ResolveUnit(byName)))
end

local byFullName = { unitMode = "name", unit = "Kaltar-Draenor" }
if AD.ResolveUnit(byFullName) ~= "party2" then fail("a name-realm pair must match") end

local wrongRealm = { unitMode = "name", unit = "Kaltar-Ravencrest" }
if AD.ResolveUnit(wrongRealm) ~= nil then
    fail("a name with the wrong realm must not match")
end

local sameRealm = { unitMode = "name", unit = "Ürsa-" .. playerRealm }
if AD.ResolveUnit(sameRealm) ~= "party1" then
    fail("a name qualified with the player's own realm must match a same-realm unit "
        .. "(UnitFullName returns an empty realm string for same-realm units), got "
        .. tostring(AD.ResolveUnit(sameRealm)))
end

local sameUnitWrongRealm = { unitMode = "name", unit = "Ürsa-Draenor" }
if AD.ResolveUnit(sameUnitWrongRealm) ~= nil then
    fail("a same-realm unit typed with a genuinely different realm must not match, got "
        .. tostring(AD.ResolveUnit(sameUnitWrongRealm)))
end

local hyphenRealm = { unitMode = "name", unit = "Fenrir-Azjol-Nerub" }
if AD.ResolveUnit(hyphenRealm) ~= "party3" then
    fail("a realm containing punctuation must normalize before comparing, got "
        .. tostring(AD.ResolveUnit(hyphenRealm)))
end

local accented = { unitMode = "name", unit = "ürsa" }
if AD.ResolveUnit(accented) ~= "party1" then
    fail("name matching must case-fold, got " .. tostring(AD.ResolveUnit(accented)))
end

local absent = { unitMode = "name", unit = "Nobody" }
if AD.ResolveUnit(absent) ~= nil then fail("an absent name must resolve to nil") end

local cotank = { unitMode = "cotank" }
if AD.ResolveUnit(cotank) ~= "party1" then
    fail("cotank must pick the first non-player tank, got " .. tostring(AD.ResolveUnit(cotank)))
end

local realUnitTokenMatches = ns.Helpers.UnitTokenMatches
ns.Helpers.UnitTokenMatches = nil
if AD.ResolveUnit(cotank) ~= nil then
    fail("cotank must fail closed when player identity is unprovable, got "
        .. tostring(AD.ResolveUnit(cotank)))
end
ns.Helpers.UnitTokenMatches = realUnitTokenMatches

SetRoster({ { token = "player", name = "Zaebos", realm = playerRealm, role = "TANK" } })
if AD.ResolveUnit(cotank) ~= nil then
    fail("cotank must exclude the player and return nil when alone")
end

SetRoster({
    { token = "player", name = "Zaebos", realm = SECRET, role = "HEALER" },
    { token = "party1", name = "Ürsa", realm = "", role = "TANK" },
})
local secretPlayerRealm = { unitMode = "name", unit = "Ürsa-" .. playerRealm }
if AD.ResolveUnit(secretPlayerRealm) ~= "party1" then
    fail("a secret player realm must fall through to the next realm source, got "
        .. tostring(AD.ResolveUnit(secretPlayerRealm)))
end

SetRoster({
    { token = "player", name = "Zaebos", realm = "", role = "HEALER" },
    { token = "party1", name = "Ürsa", realm = SECRET, role = "TANK" },
})
local secretCandidateRealm = { unitMode = "name", unit = "Ürsa-" .. playerRealm }
if AD.ResolveUnit(secretCandidateRealm) ~= nil then
    fail("a candidate whose realm reads secret must be skipped, not matched, got "
        .. tostring(AD.ResolveUnit(secretCandidateRealm)))
end

SetRoster({
    { token = "player", name = "Zaebos", realm = "", role = "HEALER" },
    { token = "party1", name = SECRET_NAME, realm = "", role = "TANK" },
})
local okSecretName, secretNameResult = pcall(AD.ResolveUnit, { unitMode = "name", unit = "Ürsa" })
if not okSecretName then
    fail("a secret name must be probed before any string operation reaches it: "
        .. tostring(secretNameResult))
end
if secretNameResult ~= nil then
    fail("a candidate whose name reads secret must be skipped, not matched, got "
        .. tostring(secretNameResult))
end

SetRoster({
    { token = "player", name = "Zaebos", realm = playerRealm, role = "HEALER" },
    { token = "party1", name = "Ürsa", realm = playerRealm, role = SECRET },
})
local secretRoleProbes = 0
local realIsSecretValue = issecretvalue
issecretvalue = function(v)
    if v == SECRET then secretRoleProbes = secretRoleProbes + 1 end
    return realIsSecretValue(v)
end
local secretRoleCotank = { unitMode = "cotank" }
if AD.ResolveUnit(secretRoleCotank) ~= nil then
    fail("a co-tank candidate with a secret role must not be treated as a co-tank, got "
        .. tostring(AD.ResolveUnit(secretRoleCotank)))
end
if secretRoleProbes < 1 then
    fail("ResolveCoTank must probe a secret role through issecretvalue before comparing it")
end
issecretvalue = realIsSecretValue

local raidRoster = {}
for i = 1, 8 do
    raidRoster[i] = { token = "raid" .. i, name = "Raider" .. i, realm = playerRealm, role = "DAMAGER" }
end
raidRoster[3].name = "Kolgar"
raidRoster[4].role = "TANK"
SetRoster(raidRoster)

local raidByName = { unitMode = "name", unit = "Kolgar" }
if AD.ResolveUnit(raidByName) ~= "raid3" then
    fail("name resolution must reach the raid branch of GroupTokens, got "
        .. tostring(AD.ResolveUnit(raidByName)))
end

local raidCotank = { unitMode = "cotank" }
if AD.ResolveUnit(raidCotank) ~= "raid4" then
    fail("cotank resolution must reach the raid branch of GroupTokens, got "
        .. tostring(AD.ResolveUnit(raidCotank)))
end

local open = { load = { classes = {}, specs = {}, roles = {}, encounters = {} } }
if not AD.PassesLoad(open) then fail("empty load conditions must pass") end

if not AD.PassesLoad({ load = { classes = { DRUID = true } } }) then
    fail("a matching class must pass")
end
if AD.PassesLoad({ load = { classes = { MAGE = true } } }) then
    fail("a non-matching class must fail")
end
if not AD.PassesLoad({ load = { classes = { WARRIOR = false } } }) then
    fail("a class set with no true entries must not arm the gate (unchecking a box must not lock out every character)")
end
if not AD.PassesLoad({ load = { specs = { [105] = true } } }) then
    fail("a matching spec must pass")
end
if AD.PassesLoad({ load = { specs = { [104] = true } } }) then
    fail("a non-matching spec must fail")
end
if not AD.PassesLoad({ load = { roles = { HEALER = true } } }) then
    fail("a matching role must pass")
end
if AD.PassesLoad({ load = { roles = { TANK = true } } }) then
    fail("a non-matching role must fail")
end
if not AD.PassesLoad({ load = { roles = { TANK = false } } }) then
    fail("a role set with no true entries must not arm the gate")
end
if AD.PassesLoad({ load = { classes = { DRUID = true }, roles = { TANK = true } } }) then
    fail("load conditions must combine as AND")
end

if AD.PassesLoad({ load = { encounters = { [2820] = true } } }) then
    fail("an encounter condition must fail outside its encounter")
end
AD.SetEncounter(2820)
if not AD.PassesLoad({ load = { encounters = { [2820] = true } } }) then
    fail("an encounter condition must pass inside its encounter")
end
AD.SetEncounter(nil)

if AD.UnitPolarityFor({ unitMode = "token", unit = "player" }) ~= "friendly" then
    fail("player must read as friendly polarity")
end
if AD.UnitPolarityFor({ unitMode = "token", unit = "boss1" }) ~= "hostile" then
    fail("boss units must read as hostile polarity")
end
if AD.UnitPolarityFor({ unitMode = "token", unit = "target" }) ~= nil then
    fail("target polarity is unknown until runtime and must be nil")
end
if AD.UnitPolarityFor({ unitMode = "cotank" }) ~= "friendly" then
    fail("cotank must read as friendly polarity")
end

SetRoster({ { token = "player", name = "Zaebos", realm = playerRealm, role = "HEALER" } })
local live = { id = "dx", enabled = true, unitMode = "token", unit = "player",
    load = { classes = {}, specs = {}, roles = {}, encounters = {} } }
if not AD.DisplayActive(live) then fail("an enabled, resolvable, unloaded display must be active") end
live.enabled = false
if AD.DisplayActive(live) then fail("a disabled display must be inactive") end
live.enabled = true
live.group = "Raid"
AD.SetGroupEnabled("Raid", false)
if AD.DisplayActive(live) then fail("a display in a disabled group must be inactive") end
AD.SetGroupEnabled("Raid", true)
live.unit = "notaunit"
if AD.DisplayActive(live) then fail("a display with an unresolvable unit must be inactive") end

local realGetProfile = ns.Helpers.GetProfile
ns.Helpers.GetProfile = function() return nil end
if AD.Store() ~= nil then
    fail("Store must return nil before a live profile exists, or lazy sub-table init writes "
        .. "into the defaults table and leaks into every fresh profile")
end
if AD.NewDisplay("Cold") ~= nil then fail("NewDisplay must fail closed with no profile") end
if AD.DuplicateDisplay("d2", "Cold Copy") ~= nil then
    fail("DuplicateDisplay must fail closed with no profile")
end
if AD.DeleteDisplay("d2") ~= false then fail("DeleteDisplay must fail closed with no profile") end
if AD.RenameGroup("Renamed", "Cold") ~= false then
    fail("RenameGroup must fail closed with no profile")
end
if not AD.GroupEnabled("Renamed") then
    fail("GroupEnabled must default to enabled with no profile, never hide a display")
end
ns.Helpers.GetProfile = realGetProfile
if AD.Store() == nil then fail("Store must recover once the profile is back") end

-- Runtime group integration: grouped displays share one host/mover, then an
-- ungrouped display returns to UIParent and regains its own mover.
local function NewFrame(parent)
    local frame = { parent = parent, width = 1, height = 1, scale = 1, shown = false }
    function frame:SetSize(w, h) self.width, self.height = w, h end
    function frame:GetSize() return self.width, self.height end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:SetScale(scale) self.scale = scale end
    function frame:GetParent() return self.parent end
    function frame:SetParent(nextParent) self.parent = nextParent end
    function frame:SetClampedToScreen() end
    function frame:ClearAllPoints() self.point = nil end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:SetAlpha(alpha) self.alpha = alpha end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    return frame
end

UIParent = NewFrame(nil)
InCombatLockdown = function() return false end
CreateFrame = function(_, _, parent) return NewFrame(parent) end
local layoutElements = {}
ns.L = setmetatable({}, { __index = function(_, key) return key end })
ns.AuraElements = {
    NewFilterStripElement = function() return {} end,
    EnsureSeeded = function() end,
    -- One renderable element per display: since beta4, hosts are sized by
    -- BuildDisplayLayout from renderable elements (an empty display is 1x1),
    -- so the 10px stub profile below only applies if something renders.
    ActiveElementsForSpec = function() return { { mode = "filterStrip" } } end,
}
ns.AuraGlue = {
    ElementProfile = function()
        return { maxPerRow = 1, maxIcons = 1, iconSize = 10, spacing = 0 }
    end,
    AurasAreSecret = function() return false end,
    QueueRegenWork = function() end,
}
ns.AuraSurface = { ApplyElementPass = function() return true end }
ns.Addon = { AuraSkin = { LayoutAnchor = function() return "TOPLEFT" end } }
ns.QUI_LayoutMode = {
    RegisterElement = function(_, def) layoutElements[def.key] = def end,
    UnregisterElement = function(_, key) layoutElements[key] = nil end,
}
ns.Helpers.IsLayoutModeActive = function() return false end
ns.SafeCall = function(_, fn, ...)
    local ok, result = pcall(fn, ...)
    if not ok then fail("runtime SafeCall failed: " .. tostring(result)) end
    return ok, result
end
ns.SafeCallMethod = function(_, target, method, ...)
    return target[method](target, ...)
end

-- Reload the runtime so its cached dependency upvalues (E/AuraGlue/AuraSurface/
-- AuraSkin) bind to the stubs above — the sections before this one resolved
-- them against the real modules loaded at the top of this file.
assert(loadfile("modules/trackers/aura_displays.lua"))("QUI", ns)
AD = ns.QUI_AuraDisplays

local runtimeFirst = AD.NewDisplay("Runtime First", "Runtime Group")
local runtimeSecond = AD.NewDisplay("Runtime Second", "Runtime Group")
local runtimeGroup = AD.GetGroup("Runtime Group", true)
runtimeGroup.spacing = 4
runtimeGroup.scale = 1.5
AD.Refresh()

local runtimeGroupHost = AD.GroupHostFor("Runtime Group")
local runtimeFirstHost = AD.HostFor(runtimeFirst.id)
local runtimeSecondHost = AD.HostFor(runtimeSecond.id)
if not runtimeGroupHost or runtimeGroupHost.width ~= 24 or runtimeGroupHost.height ~= 10 then
    fail("Refresh must create and size a populated group host")
end
if runtimeGroupHost.scale ~= 1.5
    or runtimeFirstHost.parent ~= runtimeGroupHost
    or runtimeSecondHost.parent ~= runtimeGroupHost then
    fail("group runtime must apply scale and parent members to the group host")
end
if runtimeFirstHost.point[4] ~= 5 or runtimeSecondHost.point[4] ~= 19 then
    fail("group runtime must place members using the configured spacing")
end
local runtimeGroupKey = AD.GroupAnchorKey("Runtime Group", false)
if not layoutElements[runtimeGroupKey]
    or layoutElements[AD.ANCHOR_PREFIX .. runtimeFirst.id]
    or layoutElements[AD.ANCHOR_PREFIX .. runtimeSecond.id] then
    fail("grouped displays must expose one group Layout Mode mover")
end

runtimeFirst.group = nil
AD.Refresh()
if runtimeFirstHost.parent ~= UIParent or runtimeFirstHost.scale ~= 1 then
    fail("an ungrouped display must return to UIParent at its natural scale")
end
if not layoutElements[AD.ANCHOR_PREFIX .. runtimeFirst.id] then
    fail("an ungrouped display must regain its individual Layout Mode mover")
end
if runtimeGroupHost.width ~= 10 then
    fail("the remaining one-member group must reflow")
end

print("PASS: aura_displays_test")
