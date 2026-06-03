-- tests/unit/consumablecheck_macro_default_test.lua
-- Run: lua tests/unit/consumablecheck_macro_default_test.lua
-- Verifies the popup's selection precedence: explicit right-click pref >
-- configured macro default > built-in sort, plus graceful fallback when the
-- configured family isn't owned.

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

-- Two oil families owned: Thalassian Phoenix Oil (243734) and Oil of Dawn (243736).
local itemCounts = { [243734] = 1, [243736] = 1 }

C_Container = {
    GetContainerNumSlots = function() return 0 end,
    GetContainerItemID = function() return nil end,
    GetContainerItemInfo = function() return nil end,
}
C_Item = {
    GetItemSpell = function() return nil, nil end,
    GetItemInfoInstant = function(itemID) return nil, nil, nil, nil, 100000 + itemID end,
    GetItemInfo = function(itemID) return "item:" .. tostring(itemID) end,
    GetItemCount = function(itemID) return itemCounts[itemID] or 0 end,
    GetItemIconByID = function(itemID) return 100000 + itemID end,
}
C_Spell = { GetSpellTexture = function() return nil end }
C_UnitAuras = { GetAuraDataByIndex = function() return nil end }
C_Timer = { After = function(_, cb) if cb then cb() end end, NewTicker = function() return { Cancel = noop } end }

local settings = {}

-- Mutable macro selection for the weapon slot.
local macroSelection = nil  -- set per-assertion below

local ns = {
    __test = true,
    Helpers = { CreateDBGetter = function() return function() return settings end end },
    ConsumableMacros = {
        GetVariantOrderForItem = function() return nil end,  -- distinct families, no within-family variants
        GetSelectedItem = function(dbKey)
            if dbKey == "selectedWeapon" then return macroSelection end
            return nil
        end,
    },
    Utils = { IsInInstancedContent = function() return true end },
}

assert(loadfile("modules/qol/consumablecheck.lua"))("QUI", ns)
local check = assert(ns.ConsumableCheckTest, "consumable check test seam should be exported")

local owned = check.GetOwnedItemsForButton("oilMH")
assert(#owned == 2, "both owned oils should be candidates for a non-Hunter main hand")
assert(owned[1].itemID == 243734, "default sort should put Phoenix Oil (earlier in OIL_ITEMS) first")

-- 1) No explicit pref, no macro -> default sort top (243734).
macroSelection = nil
settings.consumablePreferredOilMH = nil
local sel = check.ResolveSelectedOwnedItem("oilMH", owned)
assert(sel and sel.itemID == 243734, "with no pref and no macro, selection is the default-sort top")

-- 2) No explicit pref, macro = Oil of Dawn -> macro wins over default sort.
macroSelection = { itemID = 243736, label = "Oil of Dawn (Absorb Shield)" }
sel = check.ResolveSelectedOwnedItem("oilMH", owned)
assert(sel and sel.itemID == 243736, "configured macro family should override the default sort")

-- 3) Explicit right-click pref = Phoenix while macro = Dawn -> explicit wins.
settings.consumablePreferredOilMH = 243734
sel = check.ResolveSelectedOwnedItem("oilMH", owned)
assert(sel and sel.itemID == 243734, "an explicit right-click preference still beats the macro default")

-- 4) No explicit pref, macro points at an UNOWNED family -> graceful fallback to sort top.
settings.consumablePreferredOilMH = nil
macroSelection = { itemID = 243738, label = "Smuggler's Enchanted Edge (Arcane Damage)" }  -- not owned
sel = check.ResolveSelectedOwnedItem("oilMH", owned)
assert(sel and sel.itemID == 243734, "an unowned macro family falls back to the best owned item")

-- 5) The macro default must NOT be written into settings (only explicit prefs are).
assert(settings.consumablePreferredOilMH == nil, "macro fallback must never persist into settings")

print("OK: consumablecheck_macro_default_test")
