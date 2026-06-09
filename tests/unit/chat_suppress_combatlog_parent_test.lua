-- tests/unit/chat_suppress_combatlog_parent_test.lua
-- Run: lua tests/unit/chat_suppress_combatlog_parent_test.lua
-- Verifies ChatFrame2's enforced parent follows CombatLogTab.GetHostParent:
-- host container while the combat-log tab is active, hidden anchor otherwise.

local function F()
    local f = {}
    function f:Hide() end
    function f:GetParent() end
    function f:SetParent() end
    return f
end
_G.UIParent = F()
_G.CreateFrame = function() return F() end
_G.hooksecurefunc = function() end

local host = {}
local ns
ns = {
    Helpers = { IsSecretValue = function() return false end },
    QUI = { Chat = { _internals = {
        GetSettings = function() return { enabled = true } end,
        IsChatEnabled = function(s) return s and s.enabled ~= false end,
    } } },
}
-- Stub CombatLogTab: hostNow toggles below to simulate active/inactive.
local hostNow = nil
ns.QUI.Chat.CombatLogTab = { GetHostParent = function() return hostNow end }

assert(loadfile("QUI_Chat/chat/blizzard_suppress.lua"))("QUI", ns)
local Suppress = ns.QUI.Chat.BlizzardSuppress

-- Pre-apply, hiddenAnchor is nil (created during SuppressAll); with no host the
-- resolver returns nil.
assert(Suppress._ResolveChatFrame2Parent() == nil, "no host, no anchor yet => nil")

-- Combat-log tab active: host wins.
hostNow = host
assert(Suppress._ResolveChatFrame2Parent() == host, "host present => host wins")

-- Tab inactive again: falls back to the anchor (nil pre-apply).
hostNow = nil
assert(Suppress._ResolveChatFrame2Parent() == nil, "host cleared => back to anchor")

print("OK chat_suppress_combatlog_parent_test")
