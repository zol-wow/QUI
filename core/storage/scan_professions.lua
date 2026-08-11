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
    if not rec then return false end
    if type(GetProfessions) ~= "function" then return false end
    hasDirty = false
    local fresh = {}
    local prof1, prof2, archaeology, fishing, cooking = GetProfessions()
    Append(fresh, prof1, true)
    Append(fresh, prof2, true)
    Append(fresh, cooking)
    Append(fresh, fishing)
    Append(fresh, archaeology)
    rec.professions = fresh
    Storage.Bus.Publish("ProfessionsChanged", Storage.Store.GetCurrentCharacterKey())
    return true
end
