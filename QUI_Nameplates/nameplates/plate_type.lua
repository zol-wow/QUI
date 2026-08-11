local ADDON_NAME, ns = ...
local NP = ns.QUI_Nameplates
if not NP then return end

local pcall = pcall
local ipairs = ipairs

local PlateType = {}
NP.PlateType = PlateType

local DEFAULT_KEY = "enemyNPC"
PlateType.DEFAULT_KEY = DEFAULT_KEY

local MINOR = { minus = true, trivial = true }

local function Ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok then return nil end
    return value
end

local function IsMinion(unit)
    if NP.Plain(Ask(UnitIsMinion, unit), "boolean") == true then return true end
    if NP.Plain(Ask(UnitIsOtherPlayersPet, unit), "boolean") == true then return true end
    return NP.Plain(Ask(UnitIsUnit, unit, "pet"), "boolean") == true
end

local function IsFriendly(unit)
    return NP.Plain(Ask(UnitCanAttack, "player", unit), "boolean") == false
end

local function IsBossElite(unit)
    local classification = NP.Plain(Ask(UnitClassification, unit), "string")
    if classification and ns.Classification and ns.Classification.DATA[classification] then
        return true
    end
    return NP.Plain(Ask(UnitLevel, unit), "number") == -1
end

local function IsMinorTrivial(unit)
    local classification = NP.Plain(Ask(UnitClassification, unit), "string")
    return classification ~= nil and MINOR[classification] == true
end

local function IsPlayer(unit)
    if NP.Plain(Ask(UnitIsPlayer, unit), "boolean") == true then return true end
    return NP.Plain(Ask(UnitTreatAsPlayerForDisplay, unit), "boolean") == true
end

local ORDER = { "petMinion", "friendly", "bossElite", "minorTrivial", "enemyPlayer", "enemyNPC" }
PlateType.ORDER = ORDER

local PREDICATES = {
    petMinion = IsMinion,
    friendly = IsFriendly,
    bossElite = IsBossElite,
    minorTrivial = IsMinorTrivial,
    enemyPlayer = IsPlayer,
    enemyNPC = function() return true end,
}

local KEYS = {}
for _, key in ipairs(ORDER) do KEYS[key] = true end
PlateType.KEYS = KEYS

function PlateType.Resolve(unit)
    if type(unit) ~= "string" or unit == "" then return DEFAULT_KEY end
    for _, key in ipairs(ORDER) do
        if PREDICATES[key](unit) then return key end
    end
    return DEFAULT_KEY
end
