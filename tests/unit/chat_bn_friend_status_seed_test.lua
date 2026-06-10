-- tests/unit/chat_bn_friend_status_seed_test.lua
-- Run: lua tests/unit/chat_bn_friend_status_seed_test.lua
--
-- Battle.net friend online/offline lines arrive as the BN_INLINE_TOAST_ALERT
-- message group (captured on QUI's own frame regardless of stock registration).
-- The custom-display tab filter is opt-in, and that group does NOT round-trip
-- through GetChatWindowMessages, so a tab seeded from the stock General window
-- (or migrated from a pre-takeover profile) omits it and silently drops
-- "[Friend] has come online".  The tab manager must ensure any non-inverted
-- SYSTEM tab also lists BN_INLINE_TOAST_ALERT -- the same pairing
-- tab_filters.lua's SYSTEM_GROUP_UPGRADE applies to the legacy per-frame store.
-- One-time + versioned so a later deliberate removal sticks; inverted (opt-out)
-- tabs already show it and must be left untouched.

_G.ChatTypeGroupInverted = {}
_G.NUM_CHAT_WINDOWS = 3
_G.ChatFrame1 = {}
_G.ChatFrame2 = {} -- bare: modern FrameXML sets no isCombatLog property; seed must skip by identity
_G.ChatFrame3 = {}

local windowInfo = {
    [1] = { "General", 14, 1, 1, 1, 1, true, false, true },
    [2] = { "Combat Log", 14, 1, 1, 1, 1, true, false, true },
    [3] = { "Trade", 14, 1, 1, 1, 1, true, false, true },
}
function _G.GetChatWindowInfo(i)
    local t = windowInfo[i]
    if t then return unpack(t) end
    return ""
end

-- General carries SYSTEM (stock default) but NOT BN_INLINE_TOAST_ALERT: exactly
-- the gap that drops Battle.net friend status under the takeover.
local windowMessages = {
    [1] = { "SAY", "GUILD", "SYSTEM" },
    [3] = { "CHANNEL" },
}
function _G.GetChatWindowMessages(i)
    local t = windowMessages[i]
    if t then return unpack(t) end
end
local windowChannels = { [3] = { "Trade", 0 } }
function _G.GetChatWindowChannels(i)
    local t = windowChannels[i]
    if t then return unpack(t) end
end

local ns = {
    Helpers = { IsSecretValue = function() return false end },
    QUI = { Chat = { _internals = {} } },
}
ns.QUI.Chat.DisplayLayer = { Rebuild = function() end }

local activeSettings
ns.QUI.Chat._internals.GetSettings = function() return activeSettings end
ns.QUI.Chat._internals.IsChatEnabled = function(s) return s and s.enabled ~= false end

assert(loadfile("QUI_Chat/chat/tab_manager.lua"))("QUI", ns)
local TM = ns.QUI.Chat.TabManager

-- 1) SEED PATH: a freshly seeded General tab (SYSTEM present) must gain the
--    Battle.net friend-status group so friend online/offline lines display.
activeSettings = { enabled = true, customDisplay = { windows = {} } }
local seeded = TM.GetWindowTabs(1)
local general
for _, t in ipairs(seeded) do
    if t.name == "General" then general = t end
end
assert(general, "General tab seeded")
assert(general.groups.SYSTEM, "General tab keeps SYSTEM from the stock seed")
assert(general.groups.BN_INLINE_TOAST_ALERT == true,
    "seeded General tab must list BN_INLINE_TOAST_ALERT (Battle.net friend status)")

-- The seeded filter must now pass a friend online/offline entry.
local f = TM.BuildFilter(general)
assert(f({ k = "BN_INLINE_TOAST_ALERT", e = "CHAT_MSG_BN_INLINE_TOAST_ALERT" }) == true,
    "seeded General filter passes Battle.net friend status")

-- 2) HEAL PATH: a pre-existing profile (already-seeded windows) whose General
--    tab has SYSTEM but lacks the group is upgraded in place; sibling tabs that
--    never showed SYSTEM are left alone.
activeSettings = { enabled = true, customDisplay = { windows = {
    { width = 430, height = 190, tabs = {
        { name = "General", groups = { SYSTEM = true, SAY = true }, channels = {}, invert = false },
        { name = "Trade", groups = {}, channels = { Trade = true }, invert = false },
    } },
} } }
local healed = TM.GetWindowTabs(1)
assert(healed[1].name == "General", "existing General tab preserved")
assert(healed[1].groups.BN_INLINE_TOAST_ALERT == true,
    "existing SYSTEM tab healed to include BN_INLINE_TOAST_ALERT")
assert(healed[2].groups.BN_INLINE_TOAST_ALERT == nil,
    "non-SYSTEM tab must not gain the group")

-- 3) OPT-OUT TABS: an inverted (denylist) tab already shows everything not
--    denied, so the group must NOT be force-added there.
activeSettings = { enabled = true, customDisplay = { windows = {
    { width = 430, height = 190, tabs = {
        { name = "All", groups = { COMBAT_XP_GAIN = false }, channels = {}, invert = true },
    } },
} } }
local invTabs = TM.GetWindowTabs(1)
assert(invTabs[1].groups.BN_INLINE_TOAST_ALERT == nil,
    "inverted tab left untouched (already shows friend status)")

-- 4) ONE-TIME: after the heal has run for a profile, a user removing the group
--    must stick (the upgrade is versioned, not re-applied every read).
activeSettings = { enabled = true, customDisplay = { windows = {
    { width = 430, height = 190, tabs = {
        { name = "General", groups = { SYSTEM = true }, channels = {}, invert = false },
    } },
} } }
TM.GetWindowTabs(1) -- first read heals + stamps the version
assert(activeSettings.customDisplay.windows[1].tabs[1].groups.BN_INLINE_TOAST_ALERT == true,
    "first read heals the General tab")
activeSettings.customDisplay.windows[1].tabs[1].groups.BN_INLINE_TOAST_ALERT = nil
local again = TM.GetWindowTabs(1)
assert(again[1].groups.BN_INLINE_TOAST_ALERT == nil,
    "heal is one-time; a later deliberate removal is respected")

print("OK: chat_bn_friend_status_seed_test")
