-- tests/unit/chat_message_capture_test.lua
-- Run: lua tests/unit/chat_message_capture_test.lua
-- Verifies: event registration from ChatTypeGroupInverted gated by
-- IsEventValid; Blizzard filter pass (drop + rewrite); secret-first capture
-- (formatter NEVER sees a secret body); displayMode gating; teardown;
-- AddMessage fallback hook skipping event-driven and own-addon traffic.

local function explode() error("operator applied to secret sentinel", 2) end
local secret = setmetatable({}, { __tostring = explode, __concat = explode, __len = explode })

-- WoW API mocks ------------------------------------------------------------
local registered, unregisteredAll = {}, false
local captureFrame = {
    RegisterEvent = function(_, e) registered[e] = true end,
    UnregisterAllEvents = function() unregisteredAll = true; registered = {} end,
    SetScript = function(self, _, fn) self._onEvent = fn end,
}
function _G.CreateFrame() return captureFrame end
_G.ChatTypeGroupInverted = { CHAT_MSG_SAY = "SAY", CHAT_MSG_GUILD = "GUILD", CHAT_MSG_BOGUS = "BOGUS",
    GUILD_MOTD = "GUILD", CHAT_MSG_CHANNEL_NOTICE = "CHANNEL" }
_G.C_EventUtils = { IsEventValid = function(e) return e ~= "CHAT_MSG_BOGUS" end }
_G.ChatTypeInfo = { SAY = { r = 1, g = 1, b = 1 }, RAID_WARNING = { r = 1, g = 0.28, b = 0 }, CHANNEL2 = { r = 1, g = 0.75, b = 0.75 } }
function _G.Ambiguate(name) return name end
function _G.GetServerTime() return 1234 end
_G.ChatFrame1 = { name = "ChatFrame1" }
_G.DEFAULT_CHAT_FRAME = _G.ChatFrame1

local filterImpl = nil
_G.ChatFrameUtil = { ProcessMessageEventFilters = function(frame, event, ...)
    if filterImpl then return filterImpl(frame, event, ...) end
    return false, ...
end }

local hooked = {}
local hookCount = 0
function _G.hooksecurefunc(tbl, name, fn) hooked[name] = fn; hookCount = hookCount + 1 end
local stack = ""
function _G.debugstack() return stack end

-- ns / settings scaffolding --------------------------------------------------
local settings = { enabled = true, displayMode = "custom", customDisplay = { maxLines = 500 } }
local ns = {
    Helpers = { IsSecretValue = function(v) return v == secret end },
    QUI = { Chat = { _internals = {
        GetSettings = function() return settings end,
        IsChatEnabled = function(s) return s and s.enabled ~= false end,
    } } },
}

-- Real store + real format (already tested) so capture integrates with them.
assert(loadfile("modules/chat/message_store.lua"))("QUI", ns)
assert(loadfile("modules/chat/message_format.lua"))("QUI", ns)
assert(loadfile("modules/chat/message_capture.lua"))("QUI", ns)
local Capture = ns.QUI.Chat.MessageCapture
local Store = ns.QUI.Chat.MessageStore

Capture.Setup()

-- Registration: valid events from the inverted map + explicit extras; bogus skipped
assert(registered.CHAT_MSG_SAY, "registers CHAT_MSG_SAY")
assert(registered.CHAT_MSG_GUILD, "registers CHAT_MSG_GUILD")
assert(registered.CHAT_MSG_CHANNEL, "registers explicit CHAT_MSG_CHANNEL")
assert(not registered.CHAT_MSG_BOGUS, "IsEventValid gate skips bogus event")
assert(not registered.GUILD_MOTD, "non-CHAT_MSG event (GUILD_MOTD) not registered")
assert(not registered.CHAT_MSG_CHANNEL_NOTICE, "token-payload event excluded")
assert(type(captureFrame._onEvent) == "function", "OnEvent handler installed")
assert(type(hooked.AddMessage) == "function", "fallback AddMessage hook installed")
assert(hookCount == 1, "fallback hook installed once")
Capture.Setup()
assert(hookCount == 1, "repeat Setup does not stack hooks")

local fire = function(event, ...) captureFrame._onEvent(captureFrame, event, ...) end

-- Plain capture: formatted line + event color + metadata
fire("CHAT_MSG_SAY", "hello", "Bob")
assert(Store.Size() == 1, "captured 1")
local e1; Store.ForEach(function(e) e1 = e end)
assert(e1.m == "|Hplayer:Bob|h[Bob]|h: hello", "formatted line, got " .. tostring(e1.m))
assert(e1.e == "CHAT_MSG_SAY" and e1.k == "SAY" and e1.t == 1234, "metadata")
assert(e1.r == 1 and e1.g == 1 and e1.b == 1, "event color")

-- Filter drop
filterImpl = function() return true end
fire("CHAT_MSG_SAY", "spam", "Bob")
assert(Store.Size() == 1, "filtered message dropped")

-- Filter rewrite
filterImpl = function(frame, event, a1, ...) return false, "REWRITTEN", ... end
fire("CHAT_MSG_SAY", "original", "Bob")
local e2; Store.ForEach(function(e) e2 = e end)
assert(e2.m:find("REWRITTEN", 1, true), "filter rewrite respected")
filterImpl = nil

-- Secret body: stored opaquely, flagged, formatter untouched (sentinel traps ops)
fire("CHAT_MSG_RAID_WARNING", secret, "Boss")
local e3; Store.ForEach(function(e) e3 = e end)
assert(rawequal(e3.m, secret), "secret stored by identity")
assert(e3.s == true, "secret flagged")
assert(e3.k == "RAID_WARNING", "typeKey from event name only")
assert(e3.r == 1 and e3.g == 0.28 and e3.b == 0, "color from event, not payload")

-- displayMode gate
settings.displayMode = "blizzard"
fire("CHAT_MSG_SAY", "ignored", "Bob")
assert(Store.Size() == 4 - 1, "no capture in blizzard mode")  -- 3 entries
settings.displayMode = "custom"

-- Channel messages pull per-channel color (ChatTypeInfo.CHANNEL<n>)
fire("CHAT_MSG_CHANNEL", "wts gem", "Ann", nil, "2. Trade", nil, nil, nil, 2, "Trade")
local e3b; Store.ForEach(function(e) e3b = e end)
assert(e3b.m == "[2. Trade] |Hplayer:Ann|h[Ann]|h: wts gem", "channel line, got " .. tostring(e3b.m))
assert(e3b.r == 1 and e3b.g == 0.75 and e3b.b == 0.75, "per-channel color from CHANNEL2")
assert(e3b.k == "CHANNEL" and e3b.ch == "Trade", "channel metadata")

-- Secret channel number: the "CHANNEL"..n concat is guarded (sentinel traps __concat)
fire("CHAT_MSG_CHANNEL", "x", "Ann", nil, nil, nil, nil, nil, secret, "Trade")
local e3c; Store.ForEach(function(e) e3c = e end)
assert(e3c.m == "[Trade] |Hplayer:Ann|h[Ann]|h: x", "secret chan num degrades, got " .. tostring(e3c.m))

-- Secret sender degrades to bare text via event path
fire("CHAT_MSG_SAY", "no sender", secret)
local e3d; Store.ForEach(function(e) e3d = e end)
assert(e3d.m == "no sender", "secret sender dropped, got " .. tostring(e3d.m))

-- Fallback hook: plain addon print captured as SYSTEM-ish line
stack = "some/Addon/file.lua:10"
hooked.AddMessage(_G.ChatFrame1, "addon says hi", 1, 1, 1)
local e4; Store.ForEach(function(e) e4 = e end)
assert(e4.m == "addon says hi", "fallback captured plain AddMessage")

-- Fallback hook: event-dispatch traffic skipped (already captured via events)
local before = Store.Size()
stack = "[string \"@Interface/AddOns/Blizzard_ChatFrameBase/Mainline/ChatFrameOverrides.lua\"]: in function 'MessageEventHandler'"
hooked.AddMessage(_G.ChatFrame1, "event-driven", 1, 1, 1)
assert(Store.Size() == before, "event-driven AddMessage skipped (MessageEventHandler marker)")

-- Fallback hook: own HISTORY repump traffic skipped
stack = "Interface/AddOns/QUI/modules/chat/history.lua:120"
hooked.AddMessage(_G.ChatFrame1, "repumped", 1, 1, 1)
assert(Store.Size() == before, "history repump AddMessage skipped")

-- Other own-addon prints DO flow (only the history repump is skipped)
stack = "Interface/AddOns/QUI/modules/chat/hyperlinks.lua:125"
hooked.AddMessage(_G.ChatFrame1, "qui feedback", 1, 1, 1)
assert(Store.Size() == before + 1, "non-history own-addon AddMessage captured")
before = Store.Size()

-- Fallback hook: secret guard first (never crashes, never stores)
stack = "some/Addon/file.lua:10"
hooked.AddMessage(_G.ChatFrame1, secret, 1, 1, 1)
assert(Store.Size() == before, "secret via fallback dropped safely")

-- Fallback hook: secret r/g/b degrade to white, message still captured
hooked.AddMessage(_G.ChatFrame1, "rgb secret", secret, secret, secret)
local e5; Store.ForEach(function(e) e5 = e end)
assert(e5.m == "rgb secret" and e5.r == 1 and e5.g == 1 and e5.b == 1, "secret rgb degraded to white")
before = Store.Size()

-- Teardown unregisters everything
Capture.Teardown()
assert(unregisteredAll, "teardown unregisters events")

print("OK: chat_message_capture_test")
