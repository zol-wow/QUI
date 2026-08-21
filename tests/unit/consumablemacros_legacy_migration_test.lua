local macroNames = {
    [121] = "Flask_DUI",
    [122] = "Pot_DUI",
}
local macroBodies = {
    [121] = "old flask body",
}
local edits = {}
local deletes = {}
local creates = {}
local function noop() end

function CreateFrame()
    return setmetatable({}, { __index = function() return noop end })
end

function InCombatLockdown() return false end
function wipe(t)
    for key in pairs(t) do t[key] = nil end
end
function GetNumMacros() return 120, 30 end
function GetMacroInfo(index)
    return macroNames[index], nil, macroBodies[index]
end
function GetMacroIndexByName(name)
    for index, macroName in pairs(macroNames) do
        if macroName == name then return index end
    end
    return 0
end
function EditMacro(index, name, icon, body)
    edits[#edits + 1] = { index = index, name = name, body = body }
    macroNames[index] = name
    macroBodies[index] = body
end
function DeleteMacro(index)
    deletes[#deletes + 1] = index
    macroNames[index] = nil
end
function CreateMacro(name, icon, body, perCharacter)
    creates[#creates + 1] = { name = name, body = body, perCharacter = perCharacter }
end

Constants = { MacroConsts = { MAX_CHARACTER_MACROS = 30 } }
C_Item = { GetItemCount = function() return 1 end }
DEFAULT_CHAT_FRAME = { AddMessage = function() end }

local db = {
    enabled = true,
    chatNotifications = false,
    selectedFlask = "blood_knights",
}
local ns = {
    Helpers = { GetConsumableMacrosDB = function() return db end },
}
(dofile("tests/helpers/locale.lua"))(ns)
assert(loadfile("modules/utility/consumablemacros.lua"))("QUI", ns)

assert(ns.ConsumableMacros:ForceRefresh() == nil)
assert(#creates == 0, "legacy macro migration must not create a duplicate")
assert(#edits == 1 and edits[1].index == 121 and edits[1].name == "Flask_QUI",
    "Flask_DUI must be renamed in place")
assert(macroNames[121] == "Flask_QUI" and macroBodies[121]:find("/use item:", 1, true),
    "migrated macro must receive the current body")

ns.ConsumableMacros:DeleteMacros()
local deleted = {}
for _, index in ipairs(deletes) do deleted[index] = true end
assert(deleted[121] and deleted[122], "cleanup must include new and legacy macro names")

print("OK: consumablemacros_legacy_migration_test")
