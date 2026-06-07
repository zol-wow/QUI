-- tests/unit/chat_tab_manager_test.lua
-- Run: lua tests/unit/chat_tab_manager_test.lua
-- Verifies filter closures (whitelist/blacklist over typeKey + channel),
-- secret entries filtering through safe metadata, SetActiveTab driving Display.Rebuild,
-- group normalization via ChatTypeGroupInverted, and one-time stock-tab seeding.

_G.ChatTypeGroupInverted = {
    CHAT_MSG_PARTY_LEADER = "PARTY",
    CHAT_MSG_PARTY = "PARTY",
    CHAT_MSG_RAID_BOSS_EMOTE = "MONSTER_BOSS_EMOTE",
}
_G.NUM_CHAT_WINDOWS = 5
_G.ChatFrame1 = {}
_G.ChatFrame2 = { isCombatLog = true }
_G.ChatFrame3 = {}
_G.ChatFrame4 = { privateMessageList = true }
_G.ChatFrame5 = {}
local windowInfo = {
    [1] = { "General", 14, 1, 1, 1, 1, true, false, true },
    [2] = { "Combat Log", 14, 1, 1, 1, 1, true, false, true },
    [3] = { "Trade", 14, 1, 1, 1, 1, true, false, true },
    [4] = { "Whisper", 14, 1, 1, 1, 1, true, false, true },
    [5] = { "Hidden", 14, 1, 1, 1, 1, false, false, false },
}
function _G.GetChatWindowInfo(i)
    local t = windowInfo[i]
    if t then return unpack(t) end
    return ""
end
local windowMessages = {
    [1] = { "SAY", "GUILD" },
    [3] = { "CHANNEL" },
}
local windowChannels = {
    [1] = { "General", 0 },
    [3] = { "Trade", 0 },
}
function _G.GetChatWindowMessages(i)
    local t = windowMessages[i]
    if t then return unpack(t) end
end
function _G.GetChatWindowChannels(i)
    local t = windowChannels[i]
    if t then return unpack(t) end
end

local settings = { enabled = true, customDisplay = { windows = {} } }
local ns = {
    Helpers = { IsSecretValue = function() return false end },
    QUI = { Chat = { _internals = {
        GetSettings = function() return settings end,
        IsChatEnabled = function(s) return s and s.enabled ~= false end,
    } } },
}

-- Display stub records Rebuild calls (two-arg: windowID, filter)
local rebuiltWindow, rebuiltWith = "UNSET", "UNSET"
ns.QUI.Chat.DisplayLayer = { Rebuild = function(id, fn) rebuiltWindow, rebuiltWith = id, fn end }

assert(loadfile("QUI_Chat/chat/tab_manager.lua"))("QUI", ns)
local TM = ns.QUI.Chat.TabManager

-- Whitelist filter
local f = TM.BuildFilter({ groups = { GUILD = true }, channels = { Trade = true }, invert = false })
assert(f({ k = "GUILD" }) == true, "whitelisted group passes")
assert(f({ k = "SAY" }) == false, "non-listed group blocked")
assert(f({ k = "CHANNEL", ch = "Trade" }) == true, "whitelisted channel passes")
assert(f({ k = "CHANNEL", ch = "General" }) == false, "non-listed channel blocked")
assert(f({ s = true, k = "GUILD" }) == true, "secret listed metadata passes filter")
assert(f({ s = true, k = "SAY" }) == false, "secret non-listed metadata is blocked")
assert(f({ s = true, k = "CHANNEL", ch = "Trade" }) == true, "secret listed channel metadata passes")

-- Named channels are controlled by the channel-name set. The broad CHANNEL
-- group is not an all-channel wildcard for messages that carry channelBaseName.
local generalOnly = TM.BuildFilter({ groups = { CHANNEL = true }, channels = { General = true } })
assert(generalOnly({ k = "CHANNEL", ch = "General" }) == true, "listed channel passes despite CHANNEL group")
assert(generalOnly({ k = "CHANNEL", ch = "Trade" }) == false, "CHANNEL group does not leak Trade")
assert(generalOnly({ k = "CHANNEL" }) == true, "nameless channel events can still match CHANNEL group")

-- Normalize saved filter tables: current UI writes set-shaped tables, but
-- older/imported data can be array-shaped and checkbox paths can leave false
-- keys. False keys must not count as constraints; array values must.
local channelsOnly = TM.BuildFilter({
    groups = { SAY = false, GUILD = false },
    channels = { "Trade", General = false },
})
assert(channelsOnly({ k = "SAY" }) == false, "false group keys do not pass")
assert(channelsOnly({ k = "CHANNEL", ch = "Trade" }) == true, "array channel value passes")
assert(channelsOnly({ k = "CHANNEL", ch = "General" }) == false, "false channel key blocked")
assert(TM.BuildFilter({ groups = { SAY = false }, channels = { Trade = false } }) == nil,
    "all-false sets are treated as unconstrained")

-- Blacklist filter
local g = TM.BuildFilter({ groups = { SAY = true }, channels = {}, invert = true })
assert(g({ k = "SAY" }) == false, "blacklisted group blocked")
assert(g({ k = "GUILD" }) == true, "non-blacklisted passes")
assert(g({ s = true, k = "SAY" }) == false, "secret listed metadata is blocked by blacklist")
assert(g({ s = true, k = "GUILD" }) == true, "secret non-listed metadata passes blacklist")

-- Blacklist by channel name
local h = TM.BuildFilter({ groups = {}, channels = { Trade = true }, invert = true })
assert(h({ k = "CHANNEL", ch = "Trade" }) == false, "blacklisted channel blocked")
assert(h({ k = "CHANNEL", ch = "General" }) == true, "non-blacklisted channel passes")

-- Nil/empty tabData -> nil filter (show all)
assert(TM.BuildFilter(nil) == nil, "nil tabData -> nil filter")
assert(TM.BuildFilter({}) == nil, "empty tabData -> nil filter")

-- SetActiveTab is window-scoped and drives Display.Rebuild for that window.
-- Even a nil tab produces a closure now (conversation exclusion), but with no
-- ConversationManager loaded it behaves as show-all.
TM.SetActiveTab(1, { groups = { GUILD = true }, invert = false })
assert(rebuiltWindow == 1, "rebuild targeted window 1")
assert(type(rebuiltWith) == "function", "rebuild called with filter fn")
assert(TM.GetActiveFilter(1) == rebuiltWith, "active filter retained per window")
assert(rebuiltWith({ k = "GUILD" }) == true and rebuiltWith({ k = "SAY" }) == false,
    "wrapped filter preserves base semantics")
TM.SetActiveTab(2, { groups = { SAY = true } })
assert(rebuiltWindow == 2, "second window rebuild targeted window 2")
assert(TM.GetActiveFilter(1) ~= TM.GetActiveFilter(2), "filters independent per window")
TM.SetActiveTab(1, nil)
assert(type(TM.GetActiveFilter(1)) == "function", "nil tab still yields exclusion closure")
assert(TM.GetActiveFilter(1)({ k = "SAY" }) == true, "nil-tab closure shows everything")

-- Conversation filter + exclusion
local cf = TM.BuildConversationFilter("W:somebody-realm")
assert(cf({ w = "W:somebody-realm", k = "WHISPER" }) == true, "conversation filter matches key")
assert(cf({ w = "W:other-realm", k = "WHISPER" }) == false, "other conversation blocked")
assert(cf({ k = "WHISPER" }) == false, "untagged whisper blocked from conversation tab")

-- Exclusion: with a stub manager claiming the conversation is open, regular
-- tab filters drop its entries; closed conversations flow normally.
local openKeys = { ["W:somebody-realm"] = true }
ns.QUI.Chat.ConversationManager = { IsOpen = function(k) return openKeys[k] == true end }
local wf = TM.BuildTabFilter({ groups = { WHISPER = true }, channels = {}, invert = false })
assert(wf({ k = "WHISPER", w = "W:somebody-realm" }) == false, "open conversation excluded from regular tab")
assert(wf({ k = "WHISPER", w = "W:other-realm" }) == true, "closed conversation passes")
assert(wf({ k = "WHISPER" }) == true, "untagged whisper passes")
local allf = TM.BuildTabFilter(nil)
assert(allf({ k = "SAY" }) == true, "unconstrained tab filter shows non-whisper")
assert(allf({ k = "WHISPER", w = "W:somebody-realm" }) == false,
    "unconstrained tab filter still excludes open conversations")
ns.QUI.Chat.ConversationManager = nil

-- Group normalization: typeKey PARTY_LEADER matches a groups set listing PARTY
local pf = TM.BuildFilter({ groups = { PARTY = true } })
assert(pf({ k = "PARTY_LEADER", e = "CHAT_MSG_PARTY_LEADER" }) == true, "leader maps to group via inverted map")
assert(pf({ k = "SAY", e = "CHAT_MSG_SAY" }) == false, "unrelated still blocked")

-- Non-chat raid warning events route into the existing monster-boss tab groups.
local bfilt = TM.BuildFilter({ groups = { MONSTER_BOSS_EMOTE = true, MONSTER_BOSS_WHISPER = true } })
assert(bfilt({ k = "RAID_BOSS_EMOTE", e = "RAID_BOSS_EMOTE" }) == true,
    "non-chat raid boss emote maps to monster-boss emote group")
assert(bfilt({ k = "QUEST_BOSS_EMOTE", e = "QUEST_BOSS_EMOTE" }) == true,
    "quest boss emote maps to monster-boss emote group")
assert(bfilt({ k = "RAID_BOSS_WHISPER", e = "RAID_BOSS_WHISPER" }) == true,
    "non-chat raid boss whisper maps to monster-boss whisper group")

-- Empty QUI windows[] seeds window 1 once from active, non-combat,
-- non-temporary stock windows.
local seeded = TM.GetWindowTabs(1)
assert(#seeded == 2, "seed should import General and Trade only, got " .. tostring(#seeded))
assert(seeded[1].name == "General" and seeded[2].name == "Trade",
    "seeded tab names should preserve active stock tab names")
assert(seeded[1].groups.SAY and seeded[1].groups.GUILD and seeded[1].channels.General,
    "General seed should carry groups/channels as sets")
assert(seeded[2].groups.CHANNEL and seeded[2].channels.Trade,
    "Trade seed should carry channel group and Trade channel")
local seededGeneralFilter = TM.BuildFilter(seeded[1])
local seededTradeFilter = TM.BuildFilter(seeded[2])
assert(seededGeneralFilter({ k = "CHANNEL", ch = "General" }) == true,
    "seeded General tab should pass its saved channel")
assert(seededGeneralFilter({ k = "CHANNEL", ch = "Trade" }) == false,
    "seeded General tab must not receive saved Trade channel")
assert(seededTradeFilter({ k = "CHANNEL", ch = "Trade" }) == true,
    "seeded Trade tab should pass its saved channel")
assert(seededTradeFilter({ k = "CHANNEL", ch = "General" }) == false,
    "seeded Trade tab must not receive saved General channel")
assert(type(TM.BuildTabDataFromWindow) == "nil",
    "runtime tab data must no longer be derived from stock chat windows")

-- Once seeded, changing stock windows must not resync or append tabs.
windowInfo[1][1] = "Renamed Stock General"
windowInfo[5][7] = true
_G.ChatFrame5 = {}
windowMessages[5] = { "RAID" }
local afterStockChange = TM.GetWindowTabs(1)
assert(#afterStockChange == 2, "seeded QUI tabs must not keep syncing stock windows")
assert(afterStockChange[1].name == "General",
    "seeded QUI tab name must not follow later stock-window renames")

-- Per-window tab accessors: array of SET-shaped entries, index-addressed
local win1tabs = TM.GetWindowsConfig()[1].tabs
win1tabs[1] = { name = "Loot Watch", groups = { LOOT = true }, channels = {}, invert = false }
win1tabs[2] = { name = "Trade Only", groups = {}, channels = { Trade = true } }
-- Overwrite so #win1tabs == 2 (remove any extra seeded entries first)
for i = 3, #win1tabs do win1tabs[i] = nil end
local list = TM.GetWindowTabs(1)
assert(#list == 2 and list[1].name == "Loot Watch", "GetWindowTabs returns the array")
local t1 = TM.GetWindowTab(1, 1)
assert(t1 and t1.groups.LOOT, "GetWindowTab returns entry by index")
assert(TM.GetWindowTab(1, 9) == nil, "missing index -> nil")
assert(TM.GetWindowTab(1, "x") == nil, "non-numeric index -> nil")

-- Custom entries feed BuildFilter directly (sets, no adapter)
local tabfilt = TM.BuildFilter(t1)
assert(tabfilt({ k = "LOOT" }) == true and tabfilt({ k = "SAY" }) == false, "custom tabData filters directly")

print("OK: chat_tab_manager_test")
