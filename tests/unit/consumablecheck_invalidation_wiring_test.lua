-- tests/unit/consumablecheck_invalidation_wiring_test.lua
-- Run: lua5.1 tests/unit/consumablecheck_invalidation_wiring_test.lua
--
-- Source pins for the snapshot-invalidation seams. The snapshot must be
-- dropped ONLY on: bag changes (storage bus "BagsChanged", raw
-- BAG_UPDATE_DELAYED fallback), equipment changes ("EquippedChanged" /
-- PLAYER_EQUIPMENT_CHANGED), roster changes (GROUP_ROSTER_UPDATE), and
-- preference writes (both PostClick seams + QUI_RefreshConsumables).
-- UNIT_AURA must NOT invalidate.

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return (d:gsub("\r\n", "\n"))
end

local src = readAll("modules/qol/consumablecheck.lua")
local fails = 0
local function check(name, ok)
    if ok then print("  ok  " .. name)
    else fails = fails + 1; print("FAIL  " .. name) end
end

-- Bus-first wiring with raw-event harness fallback.
check("subscribes to storage bus BagsChanged",
    src:find('ns.Storage.Bus.Subscribe("BagsChanged", OnInventoryPossiblyChanged)', 1, true) ~= nil)
check("subscribes to storage bus EquippedChanged",
    src:find('ns.Storage.Bus.Subscribe("EquippedChanged", OnInventoryPossiblyChanged)', 1, true) ~= nil)
check("raw BAG_UPDATE_DELAYED fallback registered when bus absent",
    src:find('eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")', 1, true) ~= nil)
check("raw PLAYER_EQUIPMENT_CHANGED fallback registered when bus absent",
    src:find('eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")', 1, true) ~= nil)
check("GROUP_ROSTER_UPDATE always registered (warlock/healthstone visibility)",
    src:find('eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")', 1, true) ~= nil)

-- The UNIT_AURA handler must stay a pure repaint trigger: no invalidation.
local onEventStart = assert(src:find('if event == "UNIT_AURA" then', 1, true))
local onEventEnd = assert(src:find("UpdateConsumables()", onEventStart, true))
check("UNIT_AURA handler does not invalidate the snapshot",
    src:sub(onEventStart, onEventEnd + 40):find("InvalidateInventorySnapshot", 1, true) == nil)

-- Preference seams invalidate BEFORE the deferred repaint.
local rowPost = assert(src:find("SetPreferredItemID(self.buttonType, self.itemID)", 1, true))
local rowInval = src:find("InvalidateInventorySnapshot()", rowPost, true)
local rowTimer = assert(src:find("C_Timer.After(0.1, UpdateConsumables)", rowPost, true))
check("picker row PostClick invalidates after SetPreferredItemID, before the deferred update",
    rowInval ~= nil and rowInval < rowTimer)
local usePost = assert(src:find("SetPreferredItemID(button.buttonType, self.selectedItemID)", 1, true))
check("left-click pin-on-use invalidates the snapshot",
    src:find("InvalidateInventorySnapshot()", usePost, true) ~= nil)

-- Settings-apply path invalidates.
local refreshStart = assert(src:find("_G.QUI_RefreshConsumables = function()", 1, true))
local refreshShown = assert(src:find("if ConsumablesFrame:IsShown() then", refreshStart, true))
check("QUI_RefreshConsumables invalidates before refreshing",
    (src:find("InvalidateInventorySnapshot()", refreshStart, true) or math.huge) < refreshShown)

-- Divergent-render seams force a full repaint (lastStates cleared).
local hideStart = assert(src:find("local function HideConsumablesFrameNow()", 1, true))
local hideEnd = assert(src:find("local function EnsureConsumableCombatDeferFrame", hideStart, true))
check("HideConsumablesFrameNow clears lastStates (clicks hidden -> render diverged)",
    src:sub(hideStart, hideEnd):find("snapshotCache.lastStates = nil", 1, true) ~= nil)
local initStart = assert(src:find("local function InitializeButtons()", 1, true))
local initEnd = assert(src:find("ConsumablesFrame.buttonSize = buttonSize", initStart, true))
check("InitializeButtons clears lastStates (buttons recreated)",
    src:sub(initStart, initEnd):find("snapshotCache.lastStates = nil", 1, true) ~= nil)
local regenStart = assert(src:find('if event == "PLAYER_REGEN_DISABLED" then', 1, true))
local regenEnd = assert(src:find('elseif event == "PLAYER_REGEN_ENABLED" then', regenStart, true))
check("PLAYER_REGEN_DISABLED clears lastStates (clicks hidden by handler)",
    src:sub(regenStart, regenEnd):find("snapshotCache.lastStates = nil", 1, true) ~= nil)

if fails > 0 then error(fails .. " failure(s) in consumablecheck_invalidation_wiring_test") end
print("OK: consumablecheck_invalidation_wiring_test")
