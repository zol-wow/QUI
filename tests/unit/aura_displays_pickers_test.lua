local function fail(msg)
    print("FAIL: aura_displays_pickers_test - " .. msg)
    os.exit(1)
end

local ns = {}
_G.GetNumClasses = function() return 2 end
_G.C_CreatureInfo = {
    GetClassInfo = function(classID)
        if classID == 1 then return { classFile = "WARRIOR", className = "Warrior" } end
        if classID == 2 then return { classFile = "PALADIN", className = "Paladin" } end
    end,
}
_G.C_SpecializationInfo = {
    GetNumSpecializationsForClassID = function(classID) return classID == 1 and 2 or 1 end,
}
_G.GetSpecializationInfoForClassID = function(classID, i)
    return classID * 100 + i, "Spec" .. i, nil, 12345
end

_G.EJ_GetNumTiers = function() return 3 end
_G.EJ_SelectTier = function(tier)
    if tier ~= 3 then fail("must select the LAST tier, got " .. tostring(tier)) end
end
_G.EJ_GetInstanceByIndex = function(index, isRaid)
    if isRaid ~= true then fail("must walk raids only") end
    if index == 1 then return 1300, "Raid One" end
end
_G.EJ_SelectInstance = function(instanceID)
    if instanceID ~= 1300 then fail("must select the walked instance") end
end
_G.EJ_GetEncounterInfoByIndex = function(index)
    if index == 1 then return "Boss A", "", 9001, 0, "", 0, 3001 end
    if index == 2 then return "Boss B", "", 9002, 0, "", 0, 3002 end
end

assert(loadfile("modules/trackers/settings/aura_displays_pickers.lua"))("QUI", ns)
local P = ns.QUI_AuraDisplayPickers
if type(P) ~= "table" then fail("ns.QUI_AuraDisplayPickers must be exported") end

local classes = P.ClassSpecData()
if #classes ~= 2 then fail("expected 2 classes, got " .. tostring(#classes)) end
if classes[1].classFile ~= "WARRIOR" or classes[1].className ~= "Warrior" then
    fail("class 1 must carry classFile and className")
end
if #classes[1].specs ~= 2 or classes[1].specs[1].specID ~= 101 then
    fail("warrior must carry 2 specs with real specIDs")
end
if classes[1].specs[1].icon ~= 12345 or classes[1].specs[1].name ~= "Spec1" then
    fail("spec entries must carry name and icon")
end

local tiers = P.ListCurrentTierRaidEncounters()
if #tiers ~= 1 or tiers[1].instanceID ~= 1300 then
    fail("expected exactly the one raid instance")
end
if #tiers[1].encounters ~= 2 then fail("expected 2 encounters") end
if tiers[1].encounters[1].id ~= 3001 or tiers[1].encounters[2].id ~= 3002 then
    fail("encounter ids must be the DUNGEON encounter id (7th return), got "
        .. tostring(tiers[1].encounters[1].id))
end
if tiers[1].encounters[1].name ~= "Boss A" then fail("encounter name missing") end

_G.EJ_GetNumTiers = nil
local ns2 = {}
assert(loadfile("modules/trackers/settings/aura_displays_pickers.lua"))("QUI", ns2)
local empty = ns2.QUI_AuraDisplayPickers.ListCurrentTierRaidEncounters()
if type(empty) ~= "table" or #empty ~= 0 then
    fail("missing EJ API must yield an empty array, not an error")
end

print("OK: aura_displays_pickers_test")
