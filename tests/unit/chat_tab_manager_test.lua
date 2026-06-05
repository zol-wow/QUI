-- tests/unit/chat_tab_manager_test.lua
-- Run: lua tests/unit/chat_tab_manager_test.lua
-- Verifies filter closures (whitelist/blacklist over typeKey + channel),
-- secret entries always passing, and SetActiveTab driving Display.Rebuild.

local ns = {
    Helpers = { IsSecretValue = function() return false end },
    QUI = { Chat = { _internals = {
        GetSettings = function() return { enabled = true, tabs = {} } end,
        IsChatEnabled = function(s) return s and s.enabled ~= false end,
    } } },
}

-- Display stub records Rebuild calls
local rebuiltWith = "UNSET"
ns.QUI.Chat.DisplayLayer = { Rebuild = function(fn) rebuiltWith = fn end }

assert(loadfile("modules/chat/tab_manager.lua"))("QUI", ns)
local TM = ns.QUI.Chat.TabManager

-- Whitelist filter
local f = TM.BuildFilter({ groups = { GUILD = true }, channels = { Trade = true }, invert = false })
assert(f({ k = "GUILD" }) == true, "whitelisted group passes")
assert(f({ k = "SAY" }) == false, "non-listed group blocked")
assert(f({ k = "CHANNEL", ch = "Trade" }) == true, "whitelisted channel passes")
assert(f({ k = "CHANNEL", ch = "General" }) == false, "non-listed channel blocked")
assert(f({ s = true }) == true, "secret always passes filter")

-- Blacklist filter
local g = TM.BuildFilter({ groups = { SAY = true }, channels = {}, invert = true })
assert(g({ k = "SAY" }) == false, "blacklisted group blocked")
assert(g({ k = "GUILD" }) == true, "non-blacklisted passes")
assert(g({ s = true }) == true, "secret always passes blacklist too")

-- Blacklist by channel name
local h = TM.BuildFilter({ groups = {}, channels = { Trade = true }, invert = true })
assert(h({ k = "CHANNEL", ch = "Trade" }) == false, "blacklisted channel blocked")
assert(h({ k = "CHANNEL", ch = "General" }) == true, "non-blacklisted channel passes")

-- Nil/empty tabData -> nil filter (show all)
assert(TM.BuildFilter(nil) == nil, "nil tabData -> nil filter")
assert(TM.BuildFilter({}) == nil, "empty tabData -> nil filter")

-- SetActiveTab drives Display.Rebuild; tab 0/nil clears the filter
TM.SetActiveTab({ groups = { GUILD = true }, invert = false })
assert(type(rebuiltWith) == "function", "rebuild called with filter fn")
assert(TM.GetActiveFilter() == rebuiltWith, "active filter retained")
TM.SetActiveTab(nil)
assert(rebuiltWith == nil, "nil tab clears filter (show-all rebuild)")
assert(TM.GetActiveFilter() == nil, "active filter cleared")

print("OK: chat_tab_manager_test")
