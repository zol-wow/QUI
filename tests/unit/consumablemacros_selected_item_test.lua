-- tests/unit/consumablemacros_selected_item_test.lua
-- Run: lua tests/unit/consumablemacros_selected_item_test.lua

local function noop() end

-- Minimal frame stub: consumablemacros.lua creates an event frame at load.
local function newFrame()
    return setmetatable({}, { __index = function() return noop end })
end
function CreateFrame() return newFrame() end

local macroDB = { selectedFlask = "blood_knights" }

local ns = {
    Helpers = {
        GetConsumableMacrosDB = function() return macroDB end,
    },
}

assert(loadfile("QUI_QoL/utility/consumablemacros.lua"))("QUI", ns)

local CM = assert(ns.ConsumableMacros, "ConsumableMacros should be exported on ns")
assert(type(CM.GetSelectedItem) == "function", "GetSelectedItem should be a function")

-- Configured flask family -> first variant itemID + family label.
local flask = CM.GetSelectedItem("selectedFlask")
assert(flask and flask.itemID == 245930,
    "selectedFlask=blood_knights should resolve to the first variant itemID (245930)")
assert(flask.label == "Flask of the Blood Knights (Haste)",
    "GetSelectedItem should return the family label")

-- Configured weapon family (the user's Phoenix Oil case).
macroDB.selectedWeapon = "phoenix_oil"
local weapon = CM.GetSelectedItem("selectedWeapon")
assert(weapon and weapon.itemID == 243734,
    "selectedWeapon=phoenix_oil should resolve to 243734")
assert(weapon.label == "Thalassian Phoenix Oil (Crit + Haste)",
    "weapon label should match WEAPON_DEFS.phoenix_oil.label")

-- "none" / unset / unknown all return nil.
macroDB.selectedFlask = "none"
assert(CM.GetSelectedItem("selectedFlask") == nil, "\"none\" should resolve to nil")
assert(CM.GetSelectedItem("selectedPotion") == nil, "unset slot should resolve to nil")
assert(CM.GetSelectedItem("notARealSlot") == nil, "unknown dbKey should resolve to nil")

print("OK: consumablemacros_selected_item_test")
