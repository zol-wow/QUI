-- tests/chat_hyperlink_tooltip_test.lua
-- Run: lua tests/chat_hyperlink_tooltip_test.lua

local function noop() end

local settings = {
    enabled = true,
    hyperlinks = {
        coordinates = false,
        friendlyURLs = false,
        interactiveNames = true,
    },
}

local callbacks = {}
EventRegistry = {
    RegisterCallback = function(_, event, callback)
        callbacks[event] = callbacks[event] or {}
        table.insert(callbacks[event], callback)
    end,
}

GameTooltip = {
    SetOwner = function(self, owner, anchor)
        self.owner = owner
        self.anchor = anchor
    end,
    SetHyperlink = function(self, link)
        self.link = link
    end,
    Show = function(self)
        self.shown = true
    end,
    Hide = function(self)
        self.shown = false
        self.hidden = true
    end,
}

function hooksecurefunc() end

function CreateFrame()
    return {
        RegisterEvent = noop,
        SetScript = noop,
    }
end

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
    },
    QUI = {
        Chat = {
            _afterRefresh = {},
            _internals = {
                GetSettings = function() return settings end,
                IsChatEnabled = function(s) return s and s.enabled ~= false end,
                IsChatMessagingLockedDown = function() return false end,
            },
            Pipeline = {
                Register = noop,
                Unregister = noop,
            },
        },
    },
}

assert(loadfile("modules/chat/hyperlinks.lua"))("QUI", ns)

local enterCallbacks = callbacks["ChatFrame.OnHyperlinkEnter"]
local leaveCallbacks = callbacks["ChatFrame.OnHyperlinkLeave"]
assert(enterCallbacks and #enterCallbacks == 1, "hyperlinks module should register chat hyperlink enter callback")
assert(leaveCallbacks and #leaveCallbacks == 1, "hyperlinks module should register chat hyperlink leave callback")

local chatFrame = { name = "ChatFrame1" }
enterCallbacks[1](nil, chatFrame, "item:19019::::::::")
assert(GameTooltip.owner == chatFrame, "item tooltip should anchor to the chat frame")
assert(GameTooltip.anchor == "ANCHOR_CURSOR", "item tooltip should anchor at the cursor")
assert(GameTooltip.link == "item:19019::::::::", "item tooltip should use the hovered hyperlink")
assert(GameTooltip.shown == true, "item tooltip should be shown")

leaveCallbacks[1](nil, chatFrame)
assert(GameTooltip.shown == false, "tooltip should hide when leaving the hyperlink")

GameTooltip.owner = nil
GameTooltip.anchor = nil
GameTooltip.link = nil
GameTooltip.shown = nil
GameTooltip.hidden = nil

enterCallbacks[1](nil, chatFrame, "addon:quaziiuichat:url:https://discord.gg/FFUjA4JXnH")
assert(GameTooltip.link == nil, "QUI URL addon links should not be passed to GameTooltip:SetHyperlink")
assert(GameTooltip.shown == nil, "QUI URL addon links should not show an item tooltip")

print("OK: chat_hyperlink_tooltip_test")
