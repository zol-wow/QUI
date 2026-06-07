-- tests/unit/chat_tab_filters_system_group_upgrade_test.lua
-- Run: lua tests/unit/chat_tab_filters_system_group_upgrade_test.lua
-- Storage-shape upgrade: a stored pre-version tab entry that whitelists
-- SYSTEM gets the split-out groups (incl. PING) appended in place at
-- ADDON_LOADED, and the entry is version-stamped. tab_filters no longer
-- touches Blizzard windows or feeds runtime QUI tabs.
-- luacheck: globals CreateFrame

local eventFrame
function _G.CreateFrame()
    local frame = {}
    function frame:RegisterEvent() end
    function frame:UnregisterEvent() end
    function frame:SetScript(script, handler)
        if script == "OnEvent" then
            eventFrame = frame
            frame.OnEvent = handler
        end
    end
    return frame
end

local settings = {
    enabled = true,
    tabs = {
        [1] = {
            customized = true,
            groups = { "SYSTEM" },
            channels = {},
            -- no _groupsVersion: legacy entry
        },
        [3] = {
            customized = true,
            groups = { "PARTY" },
            channels = {},
        },
    },
}

local ns = {
    QUI = { Chat = {
        _internals = {
            GetSettings = function() return settings end,
            IsChatEnabled = function(s) return s and s.enabled ~= false end,
        },
    } },
}

assert(loadfile("QUI_Chat/chat/tab_filters.lua"))("QUI", ns)
local TF = ns.QUI.Chat.TabFilters

local function has(list, v)
    for i = 1, #list do if list[i] == v then return true end end
    return false
end

assert(eventFrame and eventFrame.OnEvent, "event frame wired")
eventFrame.OnEvent(eventFrame, "ADDON_LOADED", "QUI")

local e1 = settings.tabs[1]
for _, g in ipairs({ "ERRORS", "TARGETICONS", "BN_INLINE_TOAST_ALERT",
                     "PET_BATTLE_COMBAT_LOG", "PET_BATTLE_INFO", "PING" }) do
    assert(has(e1.groups, g),
        "legacy SYSTEM tab filters should be upgraded to include " .. g)
end
assert(e1._groupsVersion == TF.GROUPS_VERSION, "entry version-stamped")

-- Non-SYSTEM entry: stamped but no groups injected
local e3 = settings.tabs[3]
assert(#e3.groups == 1 and e3.groups[1] == "PARTY", "non-SYSTEM entry untouched")
assert(e3._groupsVersion == TF.GROUPS_VERSION, "non-SYSTEM entry stamped")

-- Idempotent: second fire changes nothing
local before = #e1.groups
eventFrame.OnEvent(eventFrame, "PLAYER_LOGIN")
assert(#e1.groups == before, "upgrade idempotent")

-- Storage API: SaveTabConfig stamps; ResetTab clears
TF.SaveTabConfig(2, { "GUILD" }, { "Trade" })
assert(settings.tabs[2].customized == true, "SaveTabConfig stores")
assert(settings.tabs[2]._groupsVersion == TF.GROUPS_VERSION, "SaveTabConfig stamps version")
TF.ResetTab(2)
assert(settings.tabs[2] == nil, "ResetTab clears the stored entry")

print("OK: chat_tab_filters_system_group_upgrade_test")
