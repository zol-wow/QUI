-- tests/unit/chat_tab_manager_windows_test.lua
-- GetWindowsConfig seeds windows[1] (geometry defaults + Blizzard-derived
-- tab seed) exactly once; GetWindowTabs/GetWindowTab address per-window
-- arrays; ReapplyAll rebuilds every window with its active filter;
-- OnWindowDeleted compacts per-window filter state.
-- Run: lua tests/unit/chat_tab_manager_windows_test.lua

_G.ChatTypeGroupInverted = {}
_G.NUM_CHAT_WINDOWS = 2
_G.ChatFrame1 = {}
_G.ChatFrame2 = { isCombatLog = true }
function _G.GetChatWindowInfo(i)
    if i == 1 then return "General", 14, 1, 1, 1, 1, true, false, true end
    if i == 2 then return "Combat Log", 14, 1, 1, 1, 1, true, false, true end
    return ""
end
function _G.GetChatWindowMessages(i)
    if i == 1 then return "SAY", "GUILD" end
end
function _G.GetChatWindowChannels(i)
    if i == 1 then return "General", 0 end
end

local settings = { enabled = true, customDisplay = { windows = {} } }
local ns = {
    Helpers = { IsSecretValue = function() return false end },
    QUI = { Chat = { _internals = {
        GetSettings = function() return settings end,
        IsChatEnabled = function(s) return s and s.enabled ~= false end,
    } } },
}
local rebuilds = {}
ns.QUI.Chat.DisplayLayer = { Rebuild = function(id, fn) rebuilds[#rebuilds + 1] = { id = id, fn = fn } end }

assert(loadfile("QUI_Chat/chat/tab_manager.lua"))("QUI", ns)
local TM = ns.QUI.Chat.TabManager

-- Seeding: empty windows[] -> windows[1] with default geometry + seeded tabs
local wins = TM.GetWindowsConfig()
assert(#wins == 1, "windows[1] seeded")
assert(wins[1].width == 430 and wins[1].height == 190, "default geometry seeded")
assert(wins[1].position and wins[1].position.point == "BOTTOMLEFT", "default position seeded")
assert(type(wins[1].tabs) == "table" and #wins[1].tabs >= 1, "tabs seeded")
assert(wins[1].tabs[1].name == "General", "Blizzard-derived seed (combat log skipped)")
assert(wins[1].tabs[1].groups.SAY == true and wins[1].tabs[1].groups.GUILD == true, "groups seeded")
assert(wins[1].tabs[1].channels.General == true, "channels seeded")

-- Seeding is one-shot: a second call returns the same array untouched
wins[1].tabs[1].name = "Renamed"
assert(TM.GetWindowsConfig()[1].tabs[1].name == "Renamed", "seed does not re-run")

-- Per-window tab access
settings.customDisplay.windows[2] = { width = 300, height = 150,
    position = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 },
    tabs = { { name = "W2Tab", groups = { RAID = true }, channels = {}, invert = false } } }
assert(TM.GetWindowTabs(2)[1].name == "W2Tab", "GetWindowTabs addresses window 2")
assert(TM.GetWindowTab(2, 1).name == "W2Tab", "GetWindowTab addresses entry")
assert(TM.GetWindowTab(2, 9) == nil, "missing index -> nil")

-- ReapplyAll rebuilds each configured window
TM.SetActiveTab(1, { groups = { SAY = true } })
TM.SetActiveTab(2, { groups = { RAID = true } })
rebuilds = {}
TM.ReapplyAll()
assert(#rebuilds == 2 and rebuilds[1].id == 1 and rebuilds[2].id == 2, "ReapplyAll hit both windows")

-- OnWindowDeleted compacts filter slots (window 2's filter becomes slot 1's neighbor)
local f2 = TM.GetActiveFilter(2)
TM.OnWindowDeleted(1)
assert(TM.GetActiveFilter(1) == f2, "filter slots compacted on delete")

print("chat_tab_manager_windows_test: all passed")
