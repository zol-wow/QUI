local macroNames = { [121] = "FocusMarker_DUI" }
local edited = {}
local created = {}
local function noop() end

function CreateFrame()
    return setmetatable({}, { __index = function() return noop end })
end
function GetNumMacros() return 120, 30 end
function GetMacroInfo(index) return macroNames[index] end
function EditMacro(index, name, icon, body)
    edited[#edited + 1] = { index = index, name = name, body = body }
    macroNames[index] = name
end
function CreateMacro(name, icon, body, perCharacter)
    created[#created + 1] = { name = name, body = body, perCharacter = perCharacter }
end
function InCombatLockdown() return false end

local settings = {
    focusMarker = { enabled = true, marker = 7, useMouseover = true, writeMacro = true },
}
local ns = {
    Helpers = {
        CreateDBGetter = function() return function() return settings end end,
    },
}
assert(loadfile("modules/qol/focus_marker.lua"))("QUI", ns)
ns.RefreshFocusMarker()

assert(#created == 0, "legacy macro migration must not create a duplicate")
assert(#edited == 1 and edited[1].index == 121 and edited[1].name == "FocusMarker_QUI",
    "FocusMarker_DUI must be renamed in place")
assert(edited[1].body:find("/tm", 1, true), "migrated macro must receive the current body")

print("OK: focus_marker_legacy_migration_test")
