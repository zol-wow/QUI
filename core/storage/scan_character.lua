-- luacheck: globals GetXPExhaustion GetAverageItemLevel C_SpecializationInfo C_Map
local ADDON_NAME, ns = ...
local Storage = ns.Storage or {}; ns.Storage = Storage

local ScanCharacter = {}
Storage.ScanCharacter = ScanCharacter

local hasDirty = false

function ScanCharacter.MarkAllDirty()
    hasDirty = true
end

function ScanCharacter.OnTimePlayed(total, thisLevel)
    local rec = Storage.Store.GetCurrentCharacter()
    if not rec then return end
    rec.details.playedTotal = total
    rec.details.playedLevel = thisLevel
    Storage.Bus.Publish("CharacterChanged", Storage.Store.GetCurrentCharacterKey())
end

function ScanCharacter.Drain()
    if not hasDirty then return false end
    local rec = Storage.Store.GetCurrentCharacter()
    if not rec then return false end
    hasDirty = false
    local d = rec.details
    d.level = UnitLevel("player")
    d.xp = UnitXP("player")
    d.xpMax = UnitXPMax("player")
    d.restedXP = GetXPExhaustion()
    d.money = GetMoney()
    if type(GetAverageItemLevel) == "function" then
        local _, equipped = GetAverageItemLevel()
        d.ilvl = equipped
    end
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
        local specIndex = C_SpecializationInfo.GetSpecialization()
        if specIndex and specIndex > 0 then
            local specID, _, _, icon = C_SpecializationInfo.GetSpecializationInfo(specIndex)
            if specID and specID > 0 then
                d.specID = specID
                d.specIcon = icon
            end
        end
    end
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if mapID then
        local info = C_Map.GetMapInfo(mapID)
        if info and info.name then d.zone = info.name end
    end
    d.lastSeen = time()
    Storage.Bus.Publish("CharacterChanged", Storage.Store.GetCurrentCharacterKey())
    return true
end
