-- tests/unit/consumablecheck_snapshot_cache_test.lua
-- Run: lua5.1 tests/unit/consumablecheck_snapshot_cache_test.lua
--
-- The inventory snapshot must be built by walking the bags ONCE, then
-- reused (zero container reads) until explicitly invalidated.

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
assert(check.GetSnapshotEntry, "GetSnapshotEntry must be exported")
assert(check.InvalidateInventorySnapshot, "InvalidateInventorySnapshot must be exported")

-- First access builds the snapshot (bag walk happens)
numSlotsCalls = 0
local entry = check.GetSnapshotEntry("flask")
assert(type(entry) == "table" and type(entry.owned) == "table", "entry shape")
assert(entry.owned[1] and entry.owned[1].itemID == 245926, "flask 245926 found in bags")
assert(entry.owned[1].count == 2, "stack count collected")
assert(entry.selected and entry.selected.itemID == 245926, "selection resolved")
assert(numSlotsCalls > 0, "first access must walk the bags")

-- Second access is a pure cache hit
local before = numSlotsCalls
local entry2 = check.GetSnapshotEntry("flask")
assert(entry2 == entry, "cache hit must return the same entry table")
assert(numSlotsCalls == before, "cache hit must not touch C_Container")

-- Invalidation forces a rebuild
check.InvalidateInventorySnapshot()
local entry3 = check.GetSnapshotEntry("flask")
assert(entry3 ~= entry, "invalidation must drop the cached entry")
assert(numSlotsCalls > before, "rebuild must walk the bags again")

print("OK: consumablecheck_snapshot_cache_test")
