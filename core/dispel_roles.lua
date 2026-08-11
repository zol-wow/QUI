local ADDON_NAME, ns = ...
local DR = {}
ns.QUI_DispelRoles = DR

local BASE = {
    PALADIN = { Poison = true, Disease = true, Magic_healSpecs = { [65] = true } },
    PRIEST  = { Disease = true, Magic_healSpecs = { [256]=true, [257]=true } },
    SHAMAN  = { Curse = true, Magic_healSpecs = { [264] = true } },
    DRUID   = { Curse = true, Poison = true, Magic_healSpecs = { [105] = true } },
    MONK    = { Poison = true, Disease = true, Magic_healSpecs = { [270] = true } },
    EVOKER  = { Poison = true, Magic_healSpecs = { [1468] = true } },
    MAGE    = { Curse = true },
    HUNTER  = { }, WARRIOR = {}, ROGUE = {}, WARLOCK = {}, DEMONHUNTER = {}, DEATHKNIGHT = {},
}

function DR.SchoolsForClassSpec(classFile, specID)
    local out = {}
    local def = BASE[classFile]
    if not def then return out end
    for k, v in pairs(def) do
        if v == true then
            out[k] = true
        elseif type(v) == "table" then
            local school = k:match("^(%a+)_healSpecs$")
            if school and specID and v[specID] then out[school] = true end
        end
    end
    return out
end

function DR.PlayerDispelSchools()
    local _, classFile = UnitClass("player")
    local specID = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization
        and (function() local i = C_SpecializationInfo.GetSpecialization(); return i and select(1, GetSpecializationInfo(i)) end)() or nil
    return DR.SchoolsForClassSpec(classFile, specID)
end

return DR
