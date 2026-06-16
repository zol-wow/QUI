-- tests/unit/consumablecheck_pin_on_use_test.lua
-- Run: lua tests/unit/consumablecheck_pin_on_use_test.lua
-- Left-click-to-use must NOT pin the suggestion when it's coming from the macro
-- default (so the popup keeps following the macro). It MUST still pin when there
-- is no macro for the category, or when an explicit right-click pref exists.

local function noop() end

local function newFrame()
    local frame = {}
    local methods = {}
    function methods:CreateTexture() return newFrame() end
    function methods:CreateFontString() return newFrame() end
    return setmetatable(frame, { __index = function(_, k) return methods[k] or noop end })
end
function CreateFrame() return newFrame() end
function LibStub() return nil end
function UnitClass() return "Mage", "MAGE" end
function InCombatLockdown() return false end

UIParent = newFrame()
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
NUM_BAG_SLOTS = 0
Enum = {
    ItemClass = { Consumable = 0 },
    ItemConsumableSubclass = { FoodAndDrink = 5, Flask = 3, Phial = 3 },
}

C_Container = {
    GetContainerNumSlots = function() return 0 end,
    GetContainerItemID = function() return nil end,
    GetContainerItemInfo = function() return nil end,
}
C_Item = {
    GetItemSpell = function() return nil, nil end,
    GetItemInfoInstant = function(itemID) return nil, nil, nil, nil, 100000 + itemID end,
    GetItemInfo = function(itemID) return "item:" .. tostring(itemID) end,
    GetItemCount = function() return 0 end,
    GetItemIconByID = function(itemID) return 100000 + itemID end,
}
C_Spell = { GetSpellTexture = function() return nil end }
C_UnitAuras = { GetAuraDataByIndex = function() return nil end }
C_Timer = { After = function(_, cb) if cb then cb() end end, NewTicker = function() return { Cancel = noop } end }

local settings = {}
local macroSelection = nil

local ns = {
    __test = true,
    Helpers = { CreateDBGetter = function() return function() return settings end end },
    ConsumableMacros = {
        GetVariantOrderForItem = function() return nil end,
        GetSelectedItem = function(dbKey)
            if dbKey == "selectedWeapon" then return macroSelection end
            return nil
        end,
    },
    Utils = { IsInInstancedContent = function() return true end },
}

(dofile("tests/helpers/locale.lua"))(ns)
assert(loadfile("QUI_QoL/qol/consumablecheck.lua"))("QUI", ns)
local check = assert(ns.ConsumableCheckTest, "consumable check test seam should be exported")
assert(type(check.ShouldPersistPreferenceOnUse) == "function",
    "ShouldPersistPreferenceOnUse should be exported on the test seam")

-- Case A: no macro configured, no explicit pref -> legacy pin-on-use (true).
macroSelection = nil
settings.consumablePreferredOilMH = nil
assert(check.ShouldPersistPreferenceOnUse("oilMH") == true,
    "with no macro and no pref, using an item should pin it (legacy behavior)")

-- Case B: macro configured, no explicit pref -> following the macro, do NOT pin (false).
macroSelection = { itemID = 243734, label = "Thalassian Phoenix Oil (Crit + Haste)" }
settings.consumablePreferredOilMH = nil
assert(check.ShouldPersistPreferenceOnUse("oilMH") == false,
    "while following the macro default, using the item must NOT pin it")

-- Case C: macro configured AND an explicit pref already exists -> pin (true).
settings.consumablePreferredOilMH = 243736
assert(check.ShouldPersistPreferenceOnUse("oilMH") == true,
    "an existing explicit preference should still be (re-)pinned on use")

-- Case D: no macro, explicit pref exists -> pin (true).
macroSelection = nil
settings.consumablePreferredOilMH = 243736
assert(check.ShouldPersistPreferenceOnUse("oilMH") == true,
    "with an explicit pref and no macro, using the item should pin it")

print("OK: consumablecheck_pin_on_use_test")
