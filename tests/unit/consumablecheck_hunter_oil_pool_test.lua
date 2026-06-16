-- tests/unit/consumablecheck_hunter_oil_pool_test.lua
-- Run: lua tests/unit/consumablecheck_hunter_oil_pool_test.lua
-- A Hunter's main-hand pool is ammo-only by default; this verifies it widens
-- to include weapon oils so a configured oil macro can be suggested on the bow.

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
function UnitClass() return "Hunter", "HUNTER" end
function InCombatLockdown() return false end
function IsPlayerSpell() return false end

UIParent = newFrame()
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
NUM_BAG_SLOTS = 0
Enum = {
    ItemClass = { Consumable = 0 },
    ItemConsumableSubclass = { FoodAndDrink = 5, Flask = 3, Phial = 3 },
}

-- Hunter owns one ammo (257746 Hawkeye) and one oil (243734 Phoenix Oil).
local itemCounts = { [257746] = 1, [243734] = 1 }

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

-- Pool widening: a Hunter's main hand now considers both ammo and oils.
local owned = check.GetOwnedItemsForButton("oilMH")
local ids = {}
for _, it in ipairs(owned) do ids[it.itemID] = true end
assert(ids[257746], "owned ammo should remain a candidate on the Hunter main hand")
assert(ids[243734], "weapon oils should now also be candidates on the Hunter main hand")

-- With a Phoenix Oil macro, the popup suggests the oil rather than the ammo.
macroSelection = { itemID = 243734, label = "Thalassian Phoenix Oil (Crit + Haste)" }
local sel = check.ResolveSelectedOwnedItem("oilMH", owned)
assert(sel and sel.itemID == 243734, "configured oil macro should be the Hunter main-hand suggestion")

-- Label follows the configured oil family...
assert(check.GetEnhancementLabel("MH") == "Thalassian Phoenix Oil (Crit + Haste)",
    "MH label should reflect the configured oil family for a Hunter")

-- ...and falls back to the class default ("Ammo") when no weapon macro is set.
macroSelection = nil
assert(check.GetEnhancementLabel("MH") == "Ammo",
    "MH label should fall back to the class default when no weapon macro is configured")

print("OK: consumablecheck_hunter_oil_pool_test")
