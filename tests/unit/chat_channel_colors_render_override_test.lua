-- tests/unit/chat_channel_colors_render_override_test.lua
-- Run: lua tests/unit/chat_channel_colors_render_override_test.lua
--
-- Verifies chat.lua's rendered-message transform applies a per-channel color
-- override (from ns.QUI.Chat._lineColorResolver) by substituting the line's
-- r,g,b -- and pulls in lines (e.g. whispers) that have an override even when
-- they have no timestamp/URL/pipeline work. Harness mirrors
-- chat_rendered_transform_taint_test.lua.

local unpack = unpack
local function noop() end

local settings = {
    enabled = true,
    timestamps = { enabled = true, format = "24h" },
    urls = { enabled = true, color = { 0.078, 0.608, 0.992, 1 } },
    modifiers = {},
    hyperlinks = { coordinates = false, friendlyURLs = false },
}

local function createStateTable()
    local state = setmetatable({}, { __mode = "k" })
    return state, function(key)
        local value = state[key]
        if not value then value = {}; state[key] = value end
        return value
    end
end

local secret = { __secret = true }

ChatFrameUtil = { AddMessageEventFilter = noop }
function ChatFrame_AddMessageEventFilter() end

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
end

C_Timer = { After = function(_, callback) callback() end }
C_ChatInfo = { _locked = false, InChatMessagingLockdown = function() return C_ChatInfo._locked end }
function date() return "12:34" end
function geterrorhandler() return function(err) error(err, 2) end end

local function newChatFrame()
    local frame = { messages = {}, transformCalls = 0 }
    function frame:GetNumMessages() return #self.messages end
    function frame:GetMessageInfo(index) return unpack(self.messages[index]) end
    function frame:AddMessage(message, r, g, b, infoID, accessID, typeID, event, eventArgs, formatter, ...)
        self.messages[#self.messages + 1] = { message, r, g, b, infoID, accessID, typeID, event, eventArgs, formatter, ... }
    end
    function frame:TransformMessages(predicate, transform)
        self.transformCalls = self.transformCalls + 1
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
        if script == "OnEvent" then eventFrame = frame; frame.OnEvent = handler end
    end
    return frame
end

local chatFrame = newChatFrame()
NUM_CHAT_WINDOWS = 1
ChatFrame1 = chatFrame
DEFAULT_CHAT_FRAME = chatFrame

local ns = {
    Helpers = {
        CreateDBGetter = function() return function() return settings end end,
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
    QUI = { Chat = {
        Sounds = { Setup = noop },
        Skinning = { SkinAll = noop, StyleAllTabs = noop },
        Cleanup = {},
        EditBoxBasics = {},
        EditBoxHistory = { InitializeForFrame = noop },
        Copy = { SetupURLClick = noop },
    } },
}

assert(loadfile("modules/chat/chat.lua"))("QUI", ns)
assert(loadfile("modules/chat/pipeline.lua"))("QUI", ns)

assert(eventFrame and eventFrame.OnEvent, "chat module should install an ADDON_LOADED handler")
eventFrame.OnEvent(eventFrame, "ADDON_LOADED", "QUI")

-- Install a stub resolver: only WHISPER gets an override color.
ns.QUI.Chat._lineColorResolver = function(event)
    if event == "CHAT_MSG_WHISPER" then return 0.9, 0.1, 0.2 end
    return nil
end

-- WHISPER is NOT a decoration event, so this line is transformed ONLY because
-- the resolver reports an override -- proving the gate + the r,g,b substitution.
chatFrame:AddMessage("hey", 1, 1, 1, 1, 0, 0, "CHAT_MSG_WHISPER", { [2] = "A-Realm", [11] = 201 })
local w = chatFrame.messages[1]
assert(w[1] == "hey", "whisper message text should be unchanged; got: " .. tostring(w[1]))
assert(w[2] == 0.9 and w[3] == 0.1 and w[4] == 0.2,
    "whisper line must be recolored by the resolver; got "
        .. tostring(w[2]) .. "," .. tostring(w[3]) .. "," .. tostring(w[4]))

-- GUILD has no override: it still transforms (timestamp) but keeps its r,g,b.
chatFrame:AddMessage("hi", 1, 1, 1, 1, 0, 0, "CHAT_MSG_GUILD", { [2] = "B-Realm", [11] = 202 })
local guild = chatFrame.messages[2]
assert(guild[2] == 1 and guild[3] == 1 and guild[4] == 1,
    "no-override line must keep Blizzard's color; got "
        .. tostring(guild[2]) .. "," .. tostring(guild[3]) .. "," .. tostring(guild[4]))

print("OK: chat_channel_colors_render_override_test")
