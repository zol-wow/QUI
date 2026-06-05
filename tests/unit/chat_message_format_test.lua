-- tests/unit/chat_message_format_test.lua
-- Run: lua tests/unit/chat_message_format_test.lua
-- Verifies event->typeKey mapping, short prefixes, sender player-links,
-- channel prefixes, READ-ONLY ChatTypeInfo color lookup (write-trapped),
-- and secret-arg degradation.

-- ChatTypeInfo mock that EXPLODES on write — proves HARD CONSTRAINT 2.
_G.ChatTypeInfo = setmetatable({}, {
    __index = function(_, k)
        if k == "SAY" then return { r = 1, g = 0.5, b = 0.25 } end
        if k == "GUILD" then return { r = 0.25, g = 1, b = 0.25 } end
        return nil
    end,
    __newindex = function() error("WRITE to ChatTypeInfo is forbidden") end,
})
_G.Ambiguate = function(name) return (name:gsub("%-.*$", "")) end

local function explode() error("operator applied to secret sentinel", 2) end
local secret = setmetatable({}, { __tostring = explode, __concat = explode, __len = explode })

local ns = {
    Helpers = { IsSecretValue = function(v) return v == secret end },
    QUI = { Chat = { _internals = {} } },
}

assert(loadfile("modules/chat/message_format.lua"))("QUI", ns)
local F = ns.QUI.Chat.MessageFormat

local function eq(label, got, want)
    assert(got == want, label .. ": expected " .. tostring(want) .. " got " .. tostring(got))
end

-- EventToTypeKey
eq("typeKey SAY", F.EventToTypeKey("CHAT_MSG_SAY"), "SAY")
eq("typeKey RW", F.EventToTypeKey("CHAT_MSG_RAID_WARNING"), "RAID_WARNING")
eq("typeKey non-chat", F.EventToTypeKey("PLAYER_LOGIN"), nil)
eq("typeKey non-string", F.EventToTypeKey(42), nil)

-- ColorForTypeKey reads ChatTypeInfo, defaults to white when unknown
local r, g, b = F.ColorForTypeKey("SAY")
eq("SAY r", r, 1); eq("SAY g", g, 0.5); eq("SAY b", b, 0.25)
r, g, b = F.ColorForTypeKey("NOSUCH")
eq("unknown r", r, 1); eq("unknown g", g, 1); eq("unknown b", b, 1)
r = F.ColorForTypeKey(nil)
eq("nil key r", r, 1)

-- BuildLine: say (no prefix), sender becomes player link, realm ambiguated
eq("say line", F.BuildLine("CHAT_MSG_SAY", "hello", "Bob-Realm"),
    "|Hplayer:Bob-Realm|h[Bob]|h: hello")

-- Guild gets the short prefix
eq("guild line", F.BuildLine("CHAT_MSG_GUILD", "hi", "Ann"),
    "[G] |Hplayer:Ann|h[Ann]|h: hi")

-- Numbered channel prefix
eq("channel line", F.BuildLine("CHAT_MSG_CHANNEL", "wts", "Ann", 2, "Trade"),
    "[2. Trade] |Hplayer:Ann|h[Ann]|h: wts")

-- Channel without number
eq("channel noname", F.BuildLine("CHAT_MSG_CHANNEL", "wts", "Ann", nil, "Trade"),
    "[Trade] |Hplayer:Ann|h[Ann]|h: wts")

-- No sender -> bare text with prefix
eq("system-ish", F.BuildLine("CHAT_MSG_SYSTEM", "Realm restart", nil), "Realm restart")

-- BN whisper sender renders plain (a |Hplayer:| link would be a broken target)
eq("bn whisper", F.BuildLine("CHAT_MSG_BN_WHISPER", "yo", "Aria"), "[W:From] [Aria]: yo")

-- Non-string text degrades to empty body (defensive contract guard)
eq("nil text", F.BuildLine("CHAT_MSG_SAY", nil, "Ann"), "|Hplayer:Ann|h[Ann]|h: ")

-- Secret sender degrades to bare text (no ops on the secret)
eq("secret sender", F.BuildLine("CHAT_MSG_SAY", "hello", secret), "hello")

-- Secret channel name degrades to no channel prefix
eq("secret channel", F.BuildLine("CHAT_MSG_CHANNEL", "x", "Ann", 2, secret),
    "|Hplayer:Ann|h[Ann]|h: x")

print("OK: chat_message_format_test")
