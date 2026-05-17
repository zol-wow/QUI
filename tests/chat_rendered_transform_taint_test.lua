-- tests/chat_rendered_transform_taint_test.lua
-- Run: lua tests/chat_rendered_transform_taint_test.lua

local unpack = unpack

local function noop() end

local settings = {
    enabled = true,
    timestamps = {
        enabled = true,
        format = "24h",
    },
    urls = {
        enabled = true,
        color = { 0.078, 0.608, 0.992, 1 },
    },
    modifiers = {},
    hyperlinks = {
        coordinates = false,
        friendlyURLs = false,
    },
}

local function createStateTable()
    local state = setmetatable({}, { __mode = "k" })
    return state, function(key)
        local value = state[key]
        if not value then
            value = {}
            state[key] = value
        end
        return value
    end
end

local secret = { __secret = true }

local filterCalls = 0
ChatFrameUtil = {
    AddMessageEventFilter = function()
        filterCalls = filterCalls + 1
    end,
}
function ChatFrame_AddMessageEventFilter()
    filterCalls = filterCalls + 1
end

local globalHooks = {}
function hooksecurefunc(target, method, func)
    if type(target) == "table" then
        local original = target[method] or noop
        target[method] = function(self, ...)
            local results = { original(self, ...) }
            func(self, ...)
            return unpack(results)
        end
        return
    end

    assert(type(target) == "string", "unexpected hook target")
    assert(type(method) == "function", "global hook requires callback")
    globalHooks[target] = globalHooks[target] or {}
    table.insert(globalHooks[target], method)
end

C_Timer = {
    After = function(_, callback) callback() end,
}

C_ChatInfo = {
    _locked = false,
    InChatMessagingLockdown = function()
        return C_ChatInfo._locked
    end,
}

function date()
    return "12:34"
end

function geterrorhandler()
    return function(err) error(err, 2) end
end

local function newChatFrame()
    local frame = { messages = {} }

    function frame:GetNumMessages()
        return #self.messages
    end

    function frame:GetMessageInfo(index)
        return unpack(self.messages[index])
    end

    function frame:AddMessage(message, r, g, b, infoID, accessID, typeID, event, eventArgs, formatter, ...)
        self.messages[#self.messages + 1] = {
            message, r, g, b, infoID, accessID, typeID, event, eventArgs, formatter, ...
        }
    end

    function frame:TransformMessages(predicate, transform)
        for i = 1, #self.messages do
            local message = self.messages[i]
            if predicate(unpack(message)) then
                self.messages[i] = { transform(unpack(message)) }
            end
        end
    end

    return frame
end

local eventFrame
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

local chatFrame = newChatFrame()
NUM_CHAT_WINDOWS = 1
ChatFrame1 = chatFrame
DEFAULT_CHAT_FRAME = chatFrame

local ns = {
    Helpers = {
        CreateDBGetter = function()
            return function() return settings end
        end,
        CreateStateTable = createStateTable,
        IsSecretValue = function(value) return value == secret end,
        HasSecretValue = function(...)
            for i = 1, select("#", ...) do
                if select(i, ...) == secret then return true end
            end
            return false
        end,
    },
    UIKit = {},
    QUI = {
        Chat = {
            Sounds = { Setup = noop },
            Skinning = {
                SkinAll = noop,
                StyleAllTabs = noop,
            },
            Cleanup = {},
            EditBoxBasics = {},
            EditBoxHistory = {
                InitializeForFrame = noop,
            },
            Copy = {
                SetupURLClick = noop,
            },
        },
    },
}

assert(loadfile("modules/chat/chat.lua"))("QUI", ns)
assert(loadfile("modules/chat/pipeline.lua"))("QUI", ns)

assert(filterCalls == 0, "chat pipeline must not register pre-dispatch message filters")

local pipelineHit = false
ns.QUI.Chat.Pipeline.Register("test_rendered_modifier", 100, function(message, info, event)
    assert(event == "CHAT_MSG_RAID_WARNING", "pipeline should receive clean rendered event")
    assert(info.rendered == true, "pipeline should know this came from the rendered path")
    assert(info.author == "RaidLead-Realm", "pipeline should receive safe author")
    assert(info.lineID == 101, "pipeline should receive safe line ID")
    pipelineHit = true
    return message .. " [pipeline]", info
end)
assert(#ns.QUI.Chat.Pipeline._modifiers == 1, "test modifier should be registered")
assert(ns.QUI.Chat.Pipeline.ShouldRunForEvent("CHAT_MSG_RAID_WARNING"), "raid warnings should be pipeline events")

assert(eventFrame and eventFrame.OnEvent, "chat module should install an ADDON_LOADED handler")
eventFrame.OnEvent(eventFrame, "ADDON_LOADED", "QUI")

assert(filterCalls == 0, "ADDON_LOADED must not install ChatFrame message filters")

chatFrame:AddMessage(
    "pull at https://example.com",
    1, 1, 1,
    1, 0, 0,
    "CHAT_MSG_RAID_WARNING",
    { [2] = "RaidLead-Realm", [11] = 101 }
)

local transformed = chatFrame.messages[1][1]
assert(pipelineHit, "rendered pipeline modifier should run; actual: " .. tostring(transformed))
assert(transformed:find("^%[12:34%] "), "rendered transform should add QUI timestamp")
assert(
    transformed:find("|Haddon:quaziiuichat:url:https://example.com|h[https://example.com]|h", 1, true),
    "rendered transform should linkify URL"
)
assert(transformed:find(" %[pipeline%]$"), "rendered transform should run the pipeline")

C_ChatInfo._locked = true
chatFrame:AddMessage(
    "locked https://example.com",
    1, 1, 1,
    1, 0, 0,
    "CHAT_MSG_RAID_WARNING",
    { [2] = "RaidLead-Realm", [11] = 102 }
)
assert(chatFrame.messages[2][1] == "locked https://example.com", "chat lockdown should skip rendered transforms")
C_ChatInfo._locked = false

chatFrame:AddMessage(
    "secret event https://example.com",
    1, 1, 1,
    1, 0, 0,
    secret,
    { [2] = "RaidLead-Realm", [11] = 103 }
)
assert(chatFrame.messages[3][1] == "secret event https://example.com", "secret event token should skip transform safely")

LOOT_ITEM_SELF = "You receive item: %s."
LOOT_ITEM = "%s receives item: %s."
LOOT_CURRENCY_SELF = "You receive currency: %s."
LOOT_CURRENCY = "%s receives currency: %s."
COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience."
COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED = "You gain %d experience."
COMBATLOG_HONORGAIN_NO_RANK = "You have been awarded %d honor."
COMBATLOG_HONORGAIN = "%s dies, honorable kill Rank: %s (Estimated Honor Points: %d)"
FACTION_STANDING_INCREASED = "Your reputation with %s has increased by %d."
FACTION_STANDING_DECREASED = "Your reputation with %s has decreased by %d."

settings.modifiers.redundantText = {
    enabled = true,
    patterns = {
        loot = true,
        currency = true,
        xp = true,
        honor = true,
        reputation = true,
    },
}

assert(loadfile("modules/chat/modifiers/redundant_text.lua"))("QUI", ns)
assert(filterCalls == 0, "redundant text cleanup must not install ChatFrame message filters")

chatFrame:AddMessage(
    "You receive item: [Epic Sword].",
    1, 1, 1,
    1, 0, 0,
    "CHAT_MSG_LOOT",
    { [11] = 104 }
)

local check = string.char(226, 156, 147)
local loot = chatFrame.messages[4][1]
assert(loot:find("^%[12:34%] "), "loot cleanup should preserve rendered timestamp")
assert(loot:find(check .. " [Epic Sword]", 1, true), "loot cleanup should collapse after render; actual: " .. tostring(loot))

print("OK: chat_rendered_transform_taint_test")
