---------------------------------------------------------------------------
-- Core storage: character-basics scanner. Writes roster fields onto the
-- current character's details record: level, xp/rested, ilvl, spec, zone,
-- money, played time, lastSeen. Dirty-mark + drain like its siblings;
-- played time is the exception (event payload, no API to poll — written
-- directly by OnTimePlayed whenever TIME_PLAYED_MSG fires, i.e. on any
-- /played; this module never ISSUES RequestTimePlayed → no chat spam).
--
-- GetAverageItemLevel return order verified against vendored FrameXML:
--   PaperDollFrame.lua:1298:
--     local avgItemLevel, avgItemLevelEquipped, avgItemLevelPvP = GetAverageItemLevel();
--   Equipped ilvl is the SECOND return value.
---------------------------------------------------------------------------
-- luacheck: globals GetXPExhaustion GetAverageItemLevel C_SpecializationInfo C_Map
local ADDON_NAME, ns = ...
local Storage = ns.Storage or {}; ns.Storage = Storage

local ScanCharacter = {}
Storage.ScanCharacter = ScanCharacter

local hasDirty = false

function ScanCharacter.MarkAllDirty()
    hasDirty = true
end

--- TIME_PLAYED_MSG payload (totalTimePlayed, timePlayedThisLevel — both
--- seconds; SystemDocumentation.lua).
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
    if not rec then return false end -- transient: dirty mark preserved
    hasDirty = false
    local d = rec.details
    d.level = UnitLevel("player")
    d.xp = UnitXP("player")
    d.xpMax = UnitXPMax("player")
    -- Nilable: nil = no rested pool AND nil at max level — consumers must
    -- treat nil as "hide", never as zero (the two states are not
    -- distinguishable from this field alone).
    d.restedXP = GetXPExhaustion()
    d.money = GetMoney()
    if type(GetAverageItemLevel) == "function" then
        local _, equipped = GetAverageItemLevel()
        d.ilvl = equipped
    end
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
        local specIndex = C_SpecializationInfo.GetSpecialization()
        -- 0 = no spec chosen (and 0 is truthy) — never index spec 0
        if specIndex and specIndex > 0 then
            local specID, _, _, icon = C_SpecializationInfo.GetSpecializationInfo(specIndex)
            if specID and specID > 0 then
                d.specID = specID
                d.specIcon = icon
            end
        end
    end
    -- nil mapID (instances/loading screens) retains the last-known zone
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if mapID then
        local info = C_Map.GetMapInfo(mapID)
        if info and info.name then d.zone = info.name end
    end
    d.lastSeen = time()
    Storage.Bus.Publish("CharacterChanged", Storage.Store.GetCurrentCharacterKey())
    return true
end
