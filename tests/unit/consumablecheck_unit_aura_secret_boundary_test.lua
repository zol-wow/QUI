-- tests/unit/consumablecheck_unit_aura_secret_boundary_test.lua
-- Run: lua tests/unit/consumablecheck_unit_aura_secret_boundary_test.lua
--
-- Wave 2 Task 7 (H5): ConsumablesFrame registers UNIT_AURA player-only
-- (RegisterUnitEvent("UNIT_AURA", "player"), modules/qol/consumablecheck.lua
-- :1637) — the C-level filter already guarantees this OnEvent handler only
-- ever fires for the player unit. The pre-fix handler additionally compared
-- the payload `unit` against the literal string "player" (:1631).
--
-- PTR 68569 marks the whole UNIT_AURA event SecretWhenAurasRestricted, so in
-- combat/encounter/challenge/PvP the payload `unit` may arrive as an opaque
-- secret value. tests/helpers/secret_sentinel.lua CAVEAT 1 documents that a
-- secret-vs-string `==` compare is a cross-type comparison in Lua 5.1: it
-- does NOT throw, it silently evaluates to `false`. That means the old guard
-- didn't crash under restriction — it did something worse: it silently
-- SKIPPED UpdateConsumables() every single time the event fired while
-- restricted, even though the event genuinely was for the player. This test
-- pins the fix (drop the unit read/guard entirely) via that silent-skip
-- behavior, not a throw.

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

local SecretSentinel = dofile("tests/helpers/secret_sentinel.lua")
local restoreIssecretvalue = SecretSentinel.InstallSecretStub()

-- settings = false forces UpdateConsumables's very first statement
-- (`local settings = GetSettings(); if not settings then return end`) to
-- return immediately after the ONE GetSettings() call — giving a clean,
-- side-effect-free call counter that proves whether UpdateConsumables ran,
-- without needing to drive its full button/texture pipeline.
local settings = false
local getSettingsCalls = 0
local ns = {
    Helpers = {
        CreateDBGetter = function()
            return function()
                getSettingsCalls = getSettingsCalls + 1
                return settings
            end
        end,
    },
    ConsumableMacros = {
        GetVariantOrderForItem = function() return nil end,
        GetSelectedItem = function() return nil end,
    },
    Utils = { IsInInstancedContent = function() return false end },
}

(dofile("tests/helpers/locale.lua"))(ns)
-- Instrumented load (Task 7): truthiness/==/# on sentinels now THROW
-- inside the module, matching in-game 12.1 secret semantics.
assert(SecretSentinel.LoadInstrumented("modules/qol/consumablecheck.lua"))("QUI", ns)

local consumablesFrame = _G.QUI_ConsumablesFrame
assert(consumablesFrame, "ConsumablesFrame should register itself globally as QUI_ConsumablesFrame")
local onEvent = consumablesFrame:GetScript("OnEvent")
assert(type(onEvent) == "function", "ConsumablesFrame should have an OnEvent handler")

-- Secret/opaque unit token (simulates PTR 68569 restriction): the handler
-- must still drive UpdateConsumables — registration is already
-- RegisterUnitEvent("UNIT_AURA", "player"), so no payload unit read is safe
-- OR necessary.
local before = getSettingsCalls
onEvent(consumablesFrame, "UNIT_AURA", SecretSentinel.MakeSecretSentinel())
assert(getSettingsCalls == before + 1,
    "UNIT_AURA handler must call UpdateConsumables regardless of the payload unit's identity (registration is already player-only)")

-- Plain "player" string still works (no regression on the common case).
before = getSettingsCalls
onEvent(consumablesFrame, "UNIT_AURA", "player")
assert(getSettingsCalls == before + 1,
    "UNIT_AURA handler should still fire for the literal 'player' token")

-- Non-UNIT_AURA events must not spuriously call UpdateConsumables (this
-- frame only ever registers UNIT_AURA, but pin the event-name check too).
before = getSettingsCalls
onEvent(consumablesFrame, "SOME_OTHER_EVENT", "player")
assert(getSettingsCalls == before,
    "non-UNIT_AURA events must not trigger UpdateConsumables")

_G.issecretvalue = restoreIssecretvalue

print("OK: consumablecheck_unit_aura_secret_boundary_test")
