---------------------------------------------------------------------------
-- Core storage: professions scanner. Writes rec.professions as a dense
-- list, primaries first: { skillLineID, name, icon, rank, maxRank,
-- isPrimary }. API shape verified against vendored FrameXML:
--   Blizzard_TrainerUI/Blizzard_TrainerUI.lua:26:
--     local prof1, prof2 = GetProfessions();
--   Interface/AddOns/Blizzard_UIPanels_Game/Mainline/WorldMapFrame.lua:73:
--     local prof1, prof2, arch, fish, cook, firstAid = GetProfessions();
--   Blizzard_ProfessionsBook/Blizzard_ProfessionsBook.lua:387:
--     local name, texture, rank, maxRank, numSpells, spellOffset, skillLine,
--           rankModifier, ... = GetProfessionInfo(index);
-- Events verified against vendored docs:
--   SkillInfoDocumentation.lua:17: SKILL_LINES_CHANGED
--   TradeSkillUIDocumentation.lua:1360: TRADE_SKILL_LIST_UPDATE
---------------------------------------------------------------------------
-- luacheck: globals GetProfessions GetProfessionInfo
local ADDON_NAME, ns = ...
local Storage = ns.Storage or {}; ns.Storage = Storage

local ScanProfessions = {}
Storage.ScanProfessions = ScanProfessions

local hasDirty = false

function ScanProfessions.MarkAllDirty()
    hasDirty = true
end

local function Append(list, index, isPrimary)
    if not index then return end
    local name, icon, rank, maxRank, _, _, skillLineID = GetProfessionInfo(index)
    if not skillLineID then return end
    list[#list + 1] = {
        skillLineID = skillLineID,
        name = name,
        icon = icon,
        rank = rank,
        maxRank = maxRank,
        isPrimary = isPrimary or nil,
    }
end

function ScanProfessions.Drain()
    if not hasDirty then return false end
    local rec = Storage.Store.GetCurrentCharacter()
    if not rec then return false end -- transient: dirty mark preserved
    if type(GetProfessions) ~= "function" then return false end
    hasDirty = false
    local fresh = {}
    -- firstAid (6th return) omitted — removed from the game; always nil now
    local prof1, prof2, archaeology, fishing, cooking = GetProfessions()
    Append(fresh, prof1, true)
    Append(fresh, prof2, true)
    -- secondaries: cook, fish, arch (professions-book display order)
    Append(fresh, cooking)
    Append(fresh, fishing)
    Append(fresh, archaeology)
    rec.professions = fresh
    Storage.Bus.Publish("ProfessionsChanged", Storage.Store.GetCurrentCharacterKey())
    return true
end
