-- tests/unit/chat_history_capture_event_fallback_test.lua
-- Run: lua tests/unit/chat_history_capture_event_fallback_test.lua
-- luacheck: globals CreateFrame hooksecurefunc GetServerTime time NUM_CHAT_WINDOWS ChatFrame1 ChatFrame2

local unpack = unpack

local secretInfoID = { token = "secret-info-id" }
local eventFrame
local stored = {}

local settings = {
    enabled = true,
    history = {
        enabled = true,
        storeWhispers = false,
        excludedChannels = {},
    },
}

local function check(name, ok, detail)
    if not ok then
        error(("FAIL %s %s"):format(name, detail or ""), 2)
    end
    print(("  ok  %s"):format(name))
end

local function noop() end

function CreateFrame()
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

function hooksecurefunc(target, method, callback)
    if type(target) == "table" then
        local original = target[method] or noop
        target[method] = function(self, ...)
            local results = { original(self, ...) }
            callback(self, ...)
            return unpack(results)
        end
        return
    end
end

function GetServerTime()
    return 1700000000
end

function time()
    return 1700000000
end

NUM_CHAT_WINDOWS = 2

local chatFrame = {}
function chatFrame:AddMessage() end
ChatFrame1 = chatFrame
ChatFrame2 = { isCombatLog = true }

local ns = {
    Helpers = {
        IsSecretValue = function(value)
            return value == secretInfoID
        end,
        HasSecretValue = function(...)
            for i = 1, select("#", ...) do
                if select(i, ...) == secretInfoID then
                    return true
                end
            end
            return false
        end,
    },
    QUI = {
        Chat = {
            _internals = {
                GetSettings = function() return settings end,
                IsChatEnabled = function(s) return s and s.enabled ~= false end,
            },
            HistoryStorage = {
                Init = noop,
                MigrateFromAceDB = noop,
                AppendLive = function(entry)
                    stored[#stored + 1] = entry
                end,
                Prune = noop,
                PersistNow = noop,
            },
            _afterRefresh = {},
        },
    },
}

_G.QUI = {}

assert(loadfile("modules/chat/history.lua"))("QUI", ns)
check("history event frame installed", eventFrame and eventFrame.OnEvent)

eventFrame.OnEvent(eventFrame, "ADDON_LOADED", "QUI")

chatFrame:AddMessage(
    "[Guildie]: guild line",
    0.25, 1, 0.25,
    secretInfoID,
    nil, nil,
    "CHAT_MSG_GUILD",
    { [8] = 0, [11] = 101 }
)

chatFrame:AddMessage(
    "[Raidlead]: raid line",
    1, 0.5, 0.5,
    secretInfoID,
    nil, nil,
    "CHAT_MSG_RAID",
    { [8] = 0, [11] = 102 }
)

chatFrame:AddMessage(
    "|Hchannel:channel:5|h[Community]|h [Member]: community line",
    0.7, 0.7, 1,
    secretInfoID,
    nil, nil,
    "CHAT_MSG_COMMUNITIES_CHANNEL",
    { [8] = 5, [11] = 103 }
)

check("secret info id does not drop guild capture", stored[1] and stored[1].c == "GUILD", stored[1] and stored[1].c or "nil")
check("secret info id does not drop raid capture", stored[2] and stored[2].c == "RAID", stored[2] and stored[2].c or "nil")
check("secret info id does not drop community capture", stored[3] and stored[3].c == "CHANNEL5", stored[3] and stored[3].c or "nil")
check("captured all expected lines", #stored == 3, tostring(#stored))

print("OK: chat_history_capture_event_fallback_test")
