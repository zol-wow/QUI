-- tests/unit/chat_combat_log_tab_manager_test.lua
-- Run: lua tests/unit/chat_combat_log_tab_manager_test.lua
-- Verifies the combat-log tab is reconciled into window 1 from the
-- customDisplay.combatLogTab setting (add when on, remove when off, never
-- duplicate), and that BuildTabFilter shows nothing for it.
_G.NUM_CHAT_WINDOWS = 1
_G.ChatFrame1 = {}
function _G.GetChatWindowInfo(i)
    if i == 1 then return "General", 14, 1, 1, 1, 1, true, false, true end
    return ""
end
function _G.GetChatWindowMessages() end
function _G.GetChatWindowChannels() end

local settings = { enabled = true, customDisplay = { combatLogTab = true, windows = {} } }
local ns = {
    Helpers = { IsSecretValue = function() return false end },
    QUI = { Chat = { _internals = {
        GetSettings = function() return settings end,
        IsChatEnabled = function(s) return s and s.enabled ~= false end,
    } } },
}
ns.QUI.Chat.DisplayLayer = { Rebuild = function() end }

assert(loadfile("QUI_Chat/chat/tab_manager.lua"))("QUI", ns)
local TM = ns.QUI.Chat.TabManager

local function countCombatLog(t)
    local n = 0
    for i = 1, #t do if t[i].combatLog then n = n + 1 end end
    return n
end

-- 1. Enabled: exactly one combat-log tab seeded into window 1.
local tabs = TM.GetWindowTabs(1)
assert(countCombatLog(tabs) == 1, "expected 1 combat-log tab, got " .. countCombatLog(tabs))
assert(TM.IsCombatLogTab(tabs[#tabs]) == true, "last tab should be the combat-log tab")

-- 2. Idempotent: re-reading config never duplicates it.
TM.GetWindowsConfig(); TM.GetWindowsConfig()
assert(countCombatLog(TM.GetWindowTabs(1)) == 1, "reconcile must not duplicate")

-- 3. Disabled: the combat-log tab is removed.
settings.customDisplay.combatLogTab = false
TM.GetWindowsConfig()
assert(countCombatLog(TM.GetWindowTabs(1)) == 0, "disabled => no combat-log tab")

-- 4. Re-enable: it comes back, still single.
settings.customDisplay.combatLogTab = true
TM.GetWindowsConfig()
assert(countCombatLog(TM.GetWindowTabs(1)) == 1, "re-enable => one combat-log tab")

-- 5. Show-nothing filter.
local cl
for _, t in ipairs(TM.GetWindowTabs(1)) do if t.combatLog then cl = t end end
local f = TM.BuildTabFilter(cl)
assert(f({ k = "SAY", e = "CHAT_MSG_SAY" }) == false, "combat-log filter shows nothing")

-- 6. Non-combat-log tab predicate is false.
assert(TM.IsCombatLogTab({ name = "General" }) == false)
assert(TM.IsCombatLogTab(nil) == false)

print("OK chat_combat_log_tab_manager_test")
