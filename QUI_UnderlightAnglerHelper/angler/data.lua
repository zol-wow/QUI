-- QUI_UnderlightAnglerHelper/angler/data.lua -- what the Underlight Angler is
-- made of and how far along the player is.
--
-- Blizzard's artifact window no longer draws the fishing artifact's trait tree,
-- so the layout lives here: the twelve powers, where each sits on the art, and
-- which links form the two routes worth buying first. The checklist half reads
-- the client (achievement, profession, quests, bags) and reduces it to four
-- steps plus the one to do next. Nothing in this file touches a frame.
--
-- Ported from the standalone Underlight Angler UI addon by CoreMeeko2.
local _, ns = ...

local Angler = ns.UnderlightAngler or {}
ns.UnderlightAngler = Angler

Angler.ACHIEVEMENT_ID = 10596        -- Bigger Fish to Fry
Angler.ROD_ITEM_ID = 133755          -- Underlight Angler
Angler.LEGION_FISHING_SKILL_LINE = 2586
Angler.REQUIRED_SKILL = 100
Angler.ROOT_POWER_ID = 1021          -- Undercurrent, present only in this artifact
-- Any step of the Luminous Pearl chain being done or in the log means the pearl
-- was fished up.
Angler.PEARL_QUEST_IDS = { 40960, 40961, 41010 }

-- powerID -> spell, English fallback name, max rank, position on the art (0..1).
Angler.Traits = {
    [1021] = { spellID = 201891, name = "Undercurrent",               maxRank = 1, x = 0.45, y = 0.48 },
    [1022] = { spellID = 201927, name = "Cursed Queenfish Angling",   maxRank = 3, x = 0.39, y = 0.22 },
    [1023] = { spellID = 201881, name = "Mossgill Perch Angling",     maxRank = 3, x = 0.36, y = 0.36 },
    [1024] = { spellID = 201929, name = "Highmountain Salmon Angling", maxRank = 3, x = 0.50, y = 0.62 },
    [1025] = { spellID = 201883, name = "Stormray Angling",           maxRank = 3, x = 0.58, y = 0.76 },
    [1026] = { spellID = 201884, name = "Runescale Koi Angling",      maxRank = 3, x = 0.84, y = 0.68 },
    [1027] = { spellID = 201887, name = "Black Barracuda Angling",    maxRank = 3, x = 0.85, y = 0.18 },
    [1028] = { spellID = 201943, name = "Better Luck Next Time",      maxRank = 1, x = 0.30, y = 0.86 },
    [1029] = { spellID = 201944, name = "Surface Tension",            maxRank = 1, x = 0.25, y = 0.22 },
    [1030] = { spellID = 201945, name = "Bloodfishing",               maxRank = 1, x = 0.68, y = 0.43 },
    [1032] = { spellID = 201948, name = "Underlight Blessing",        maxRank = 1, x = 0.13, y = 0.43 },
    [1033] = { spellID = 201952, name = "Way of the Flounder",        maxRank = 1, x = 0.10, y = 0.86 },
}

-- Route 1 ends at water walking and swim speed, route 2 at the threat
-- reduction; route 0 links are valid purchases that sit on neither.
Angler.Links = {
    { from = 1021, to = 1030, route = 1 },
    { from = 1030, to = 1022, route = 1 },
    { from = 1022, to = 1029, route = 1 },
    { from = 1029, to = 1032, route = 1 },
    { from = 1030, to = 1024, route = 2 },
    { from = 1024, to = 1028, route = 2 },
    { from = 1028, to = 1033, route = 2 },
    { from = 1030, to = 1023, route = 0 },
    { from = 1030, to = 1025, route = 0 },
    { from = 1030, to = 1026, route = 0 },
    { from = 1030, to = 1027, route = 0 },
    { from = 1023, to = 1029, route = 0 },
    { from = 1025, to = 1028, route = 0 },
}

function Angler.TraitName(powerID)
    local trait = Angler.Traits[powerID]
    if not trait then return nil end
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(trait.spellID)
    if type(name) == "string" and name ~= "" then return name end
    return trait.name
end

-- True while the artifact the client has open is the Underlight Angler. Every
-- C_ArtifactUI power query answers for whichever artifact is open, so rank
-- reads and purchases are only meaningful behind this.
function Angler.IsArtifactOpen()
    local powers = C_ArtifactUI and C_ArtifactUI.GetPowers and C_ArtifactUI.GetPowers()
    if type(powers) ~= "table" then return false end
    for _, powerID in ipairs(powers) do
        if powerID == Angler.ROOT_POWER_ID then return true end
    end
    return false
end

-- Legion Fishing skill, or nil when the client will not say. The skill-line
-- query works with the profession window closed. The child-profession query is
-- the standalone addon's method, kept as the fallback: it answers for whichever
-- page is open, so it only counts while that page is Legion Fishing.
function Angler.GetLegionFishingSkill()
    local api = C_TradeSkillUI
    if not api then return nil, nil end
    if api.GetProfessionInfoBySkillLineID then
        local info = api.GetProfessionInfoBySkillLineID(Angler.LEGION_FISHING_SKILL_LINE)
        if type(info) == "table" and type(info.skillLevel) == "number"
            and type(info.maxSkillLevel) == "number" and info.maxSkillLevel > 0 then
            return info.skillLevel, info.maxSkillLevel
        end
    end
    if api.GetChildProfessionInfo then
        local info = api.GetChildProfessionInfo()
        if type(info) == "table" and info.professionID == Angler.LEGION_FISHING_SKILL_LINE
            and type(info.skillLevel) == "number" and type(info.maxSkillLevel) == "number"
            and info.maxSkillLevel > 0 then
            return info.skillLevel, info.maxSkillLevel
        end
    end
    return nil, nil
end

local function HasRod()
    if not (C_Item and C_Item.GetItemCount) then return false end
    return (C_Item.GetItemCount(Angler.ROD_ITEM_ID, true, false, true) or 0) > 0
end

local function HasPearlProgress()
    if not (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) then return false end
    local isOnQuest = C_QuestLog.IsOnQuest
    for _, questID in ipairs(Angler.PEARL_QUEST_IDS) do
        if C_QuestLog.IsQuestFlaggedCompleted(questID) then return true end
        if isOnQuest and isOnQuest(questID) then return true end
    end
    return false
end

function Angler.ReadProgress()
    local achievementName, completed
    local getAchievementInfo = _G.GetAchievementInfo
    if getAchievementInfo then
        local _, name, _, done = getAchievementInfo(Angler.ACHIEVEMENT_ID)
        achievementName, completed = name, done == true
    end
    local skill, maxSkill = Angler.GetLegionFishingSkill()
    local rod = HasRod()
    return {
        achievementName = achievementName,
        achievement = completed or false,
        skill = skill,
        maxSkill = maxSkill,
        pearl = rod or HasPearlProgress(),
        rod = rod,
    }
end

-- The first unfinished step, in the order the game enforces them:
-- "achievement" -> "skill" (or "skillUnknown") -> "pearl" -> "khadgar" -> "ready".
function Angler.NextStep(progress)
    if not progress.achievement then return "achievement" end
    if not progress.skill then return "skillUnknown" end
    if progress.skill < Angler.REQUIRED_SKILL then return "skill" end
    if not progress.pearl then return "pearl" end
    if not progress.rod then return "khadgar" end
    return "ready"
end
