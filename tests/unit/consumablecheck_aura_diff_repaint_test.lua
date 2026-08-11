-- tests/unit/consumablecheck_aura_diff_repaint_test.lua
-- Run: lua5.1 tests/unit/consumablecheck_aura_diff_repaint_test.lua
--
-- UNIT_AURA path contract after the state/inventory split:
--   * update #2 with identical auras repaints NOTHING and never re-walks bags
--   * a single new consumable buff repaints ONLY that button
--   * layout (reposition/resize) reruns only when the shown set changes

local function noop() end

local function newFrame(name)
    -- click defaults to explicit false (not absent) so the non-clickable
    -- healthstone button's `if button.click then` reset-guard reads falsy
    -- via a real rawget instead of falling through __index to `noop`
    -- (truthy). This mirrors real Frame objects, where an unset custom key
    -- is plain nil, not a callable stand-in.
    local frame = { scripts = {}, click = false }
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
NUM_BAG_SLOTS = 1
Enum = {
    ItemClass = { Consumable = 0 },
    ItemConsumableSubclass = { FoodAndDrink = 5, Flask = 3, Phial = 3 },
}
local numSlotsCalls = 0
C_Container = {
    GetContainerNumSlots = function(bag)
        numSlotsCalls = numSlotsCalls + 1
        return bag == 0 and 1 or 0
    end,
    GetContainerItemID = function(bag, slot)
        if bag == 0 and slot == 1 then return 245926 end -- Midnight flask variant
        return nil
    end,
    GetContainerItemInfo = function() return { stackCount = 2 } end,
}
C_Item = {
    GetItemSpell = function() return nil, nil end,
    GetItemInfoInstant = function(itemID) return nil, nil, nil, nil, 100000 + itemID end,
    GetItemInfo = function(itemID) return "item:" .. tostring(itemID) end,
    GetItemCount = function() return 0 end,
    GetItemIconByID = function(itemID) return 100000 + itemID end,
}
C_Spell = { GetSpellTexture = function() return nil end }

local auras = {}
C_UnitAuras = { GetAuraDataByIndex = function(_, i) return auras[i] end }

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
assert(check.RunUpdate and check.GetRepaintLog and check.GetLayoutRunCount,
    "diff-repaint seams must be exported")

-- First update: full paint (prev states nil) + one layout pass + one bag walk
numSlotsCalls = 0
check.RunUpdate()
local firstWalks = numSlotsCalls
assert(firstWalks > 0, "first update must build the snapshot (bag walk)")
assert(#check.GetRepaintLog() == 6, "first update paints all 6 buttons, got " .. #check.GetRepaintLog())
local layoutAfterFirst = check.GetLayoutRunCount()
assert(layoutAfterFirst >= 1, "first update must run layout")

-- Second update, nothing changed: no repaints, no layout, NO bag walk
check.ResetRepaintLog()
check.RunUpdate()
assert(#check.GetRepaintLog() == 0, "unchanged update must repaint nothing")
assert(check.GetLayoutRunCount() == layoutAfterFirst, "unchanged update must not rerun layout")
assert(numSlotsCalls == firstWalks, "aura-driven updates must never re-walk bags")

-- Flask buff appears: exactly the flask button repaints, layout untouched
auras[1] = { spellId = 1235057, icon = 5555, expirationTime = 0 } -- Midnight flask aura
check.ResetRepaintLog()
check.RunUpdate()
local log = check.GetRepaintLog()
assert(#log == 1 and log[1] == "flask",
    "only the flask button may repaint, got " .. #log .. " (" .. tostring(log[1]) .. ")")
assert(check.GetLayoutRunCount() == layoutAfterFirst, "active flip is not a layout change")
assert(numSlotsCalls == firstWalks, "still no bag re-walk")

-- Category toggled off (settings-apply seam): full repaint + layout rerun
settings.consumableFood = false
check.InvalidateInventorySnapshot()
check.ResetRepaintLog()
check.RunUpdate()
assert(#check.GetRepaintLog() == 6, "forced invalidation must repaint everything")
assert(check.GetLayoutRunCount() == layoutAfterFirst + 1, "shown-set change must rerun layout")
assert(numSlotsCalls > firstWalks, "invalidation must rebuild the snapshot")

print("OK: consumablecheck_aura_diff_repaint_test")
