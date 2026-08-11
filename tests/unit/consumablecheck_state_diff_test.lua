-- tests/unit/consumablecheck_state_diff_test.lua
-- Run: lua5.1 tests/unit/consumablecheck_state_diff_test.lua
--
-- Pure helpers for the state/inventory split: ButtonStatesEqual compares
-- only plain (pre-probed) fields; DiffButtonStates returns the changed
-- button set plus whether the shown set changed (layout trigger). prev=nil
-- must diff as "everything changed" (forced full repaint).

local function noop() end

local function newFrame(name)
    local frame = { scripts = {} }
    local methods = {}
    function methods:CreateTexture() return newFrame() end
    function methods:CreateFontString() return newFrame() end
    function methods:SetScript(script, handler) self.scripts[script] = handler end
    function methods:GetScript(script) return self.scripts[script] end
    local f = setmetatable(frame, { __index = function(_, k) return methods[k] or noop end })
    if name then _G[name] = f end
    return f
end
function CreateFrame(_, name) return newFrame(name) end
function LibStub() return nil end
function UnitClass() return "Mage", "MAGE" end
function InCombatLockdown() return false end
function IsPlayerSpell() return false end
function IsLoggedIn() return true end
function GetTime() return 0 end
function GetInventoryItemID() return nil end
function GetWeaponEnchantInfo() return false, nil, nil, nil, false, nil, nil, nil end
function GetNumGroupMembers() return 0 end
function IsInRaid() return false end
function UnitExists() return false end

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
local ns = {
    __test = true,
    Helpers = {
        CreateDBGetter = function() return function() return settings end end,
        IsSecretValue = function() return false end,
        SafeValue = function(v) return v end,
        SafeToNumber = function(v) return tonumber(v) or 0 end,
    },
    ConsumableMacros = {
        GetVariantOrderForItem = function() return nil end,
        GetSelectedItem = function() return nil end,
    },
    Utils = { IsInInstancedContent = function() return false end },
    WhenLoggedIn = function(fn) if fn then fn() end end,
}

(dofile("tests/helpers/locale.lua"))(ns)
assert(loadfile("modules/qol/consumablecheck.lua"))("QUI", ns)
local check = assert(ns.ConsumableCheckTest, "consumable check test seam should be exported")

local eq = assert(check.ButtonStatesEqual, "ButtonStatesEqual must be exported")
local diff = assert(check.DiffButtonStates, "DiffButtonStates must be exported")

-- Equality basics
assert(eq(nil, nil) == true, "nil == nil")
assert(eq(nil, { shown = true }) == false, "nil vs state must differ")
local a = { shown = true, active = false, icon = nil, timeText = "", clickable = true, itemID = 111, count = 2 }
local b = { shown = true, active = false, icon = nil, timeText = "", clickable = true, itemID = 111, count = 2 }
assert(eq(a, b) == true, "identical fields must compare equal")
for _, field in ipairs({ "shown", "active", "clickable" }) do
    local saved = b[field]
    b[field] = not saved
    assert(eq(a, b) == false, field .. " flip must be detected")
    b[field] = saved
end
b.timeText = "5m"
assert(eq(a, b) == false, "timeText change must be detected")
b.timeText = ""
b.itemID = 222
assert(eq(a, b) == false, "itemID change must be detected")
b.itemID = 111
b.count = 3
assert(eq(a, b) == false, "count change must be detected")
b.count = 2
b.icon = 12345
assert(eq(a, b) == false, "icon change must be detected")

-- Diff: nil prev = everything changed, visibility changed for shown buttons
local types = { "food", "flask" }
local next1 = {
    food = { shown = true, active = false, icon = nil, timeText = "", clickable = false },
    flask = { shown = false, active = false, icon = nil, timeText = "", clickable = false },
}
local changed, visChanged = diff(nil, next1, types)
assert(#changed == 2, "nil prev must mark every button changed")
assert(visChanged == true, "nil->shown must flag visibility change")

-- Diff: steady state = no changes
local changed2, visChanged2 = diff(next1, next1, types)
assert(#changed2 == 0, "identical maps must produce no changes")
assert(visChanged2 == false, "identical maps must not flag visibility")

-- Diff: single-button state flip without visibility change
local next2 = {
    food = { shown = true, active = true, icon = nil, timeText = "", clickable = false },
    flask = next1.flask,
}
local changed3, visChanged3 = diff(next1, next2, types)
assert(#changed3 == 1 and changed3[1] == "food", "only food changed")
assert(visChanged3 == false, "active flip is not a visibility change")

-- Diff: visibility flip
local next3 = {
    food = next2.food,
    flask = { shown = true, active = false, icon = nil, timeText = "", clickable = false },
}
local changed4, visChanged4 = diff(next2, next3, types)
assert(#changed4 == 1 and changed4[1] == "flask", "only flask changed")
assert(visChanged4 == true, "shown flip must flag visibility change")

print("OK: consumablecheck_state_diff_test")
