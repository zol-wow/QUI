-- tests/unit/consumablecheck_login_init_test.lua
-- Run: lua tests/unit/consumablecheck_login_init_test.lua
--
-- Regression guard for the "Eager-LOD self-ADDON_LOADED init is DEAD" class.
-- QUI_QoL is eager-LoadAddOn'd by the core from OnEnable, so this module's own
-- ADDON_LOADED self-event is never delivered to its just-registered handler and
-- InitializeButtons() never runs that way. Init must therefore run via
-- ns.WhenLoggedIn (fires immediately for a post-login LOD load). Without it the
-- buttons table stays empty {} and the first ready check / end-of-combat update
-- crashes indexing buttons.oilMH / buttons.healthstone (in-game report).

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
function UnitClass() return "Shaman", "SHAMAN" end
function InCombatLockdown() return false end
function IsPlayerSpell() return false end
function IsLoggedIn() return true end
function GetTime() return 0 end
function GetInventoryItemID() return nil end

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

-- ns.WhenLoggedIn fires the callback immediately when already logged in, which
-- mirrors how the real init.lua helper behaves for a sub-addon loaded after
-- PLAYER_LOGIN. This is the ONLY init path that runs for an eager-LOD module.
local ns = {
    __test = true,
    Helpers = { CreateDBGetter = function() return function() return settings end end },
    ConsumableMacros = {
        GetVariantOrderForItem = function() return nil end,
        GetSelectedItem = function() return nil end,
    },
    Utils = { IsInInstancedContent = function() return false end },
    WhenLoggedIn = function(fn) if fn then fn() end end,
}

(dofile("tests/helpers/locale.lua"))(ns)
assert(loadfile("QUI_QoL/qol/consumablecheck.lua"))("QUI_QoL", ns)
local check = assert(ns.ConsumableCheckTest, "consumable check test seam should be exported")

-- After login, every category button must exist. If init only hangs off the
-- (undelivered) ADDON_LOADED self-event, this table is empty and indexing any
-- key during UpdateConsumables throws "attempt to index field ... (a nil value)".
local buttons = check.GetButtons()
for _, key in ipairs({ "food", "flask", "oilMH", "rune", "healthstone", "oilOH" }) do
    assert(type(buttons[key]) == "table",
        "button '" .. key .. "' should be initialized at login via ns.WhenLoggedIn")
end

print("OK: consumablecheck_login_init_test")
