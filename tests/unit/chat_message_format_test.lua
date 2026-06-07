-- tests/unit/chat_message_format_test.lua
-- Run: lua tests/unit/chat_message_format_test.lua
-- Verifies event->typeKey mapping, short prefixes, sender player-links,
-- channel prefixes, READ-ONLY ChatTypeInfo color lookup (write-trapped),
-- and secret-arg degradation.

-- ChatTypeInfo mock that EXPLODES on write — proves HARD CONSTRAINT 2.
_G.C_BattleNet = { GetAccountInfoByID = function(id)
    if id == 77 then return { gameAccountInfo = { characterName = "Thrall" } } end
    return nil
end }

_G.ChatTypeInfo = setmetatable({}, {
    __index = function(_, k)
        if k == "SAY" then return { r = 1, g = 0.5, b = 0.25 } end
        if k == "GUILD" then return { r = 0.25, g = 1, b = 0.25 } end
        if k == "LOOT" then return { r = 0, g = 0.667, b = 0 } end
        if k == "MONSTER_YELL" then return { r = 1, g = 0.25, b = 0.25 } end
        return nil
    end,
    __newindex = function() error("WRITE to ChatTypeInfo is forbidden") end,
})
_G.Ambiguate = function(name) return (name:gsub("%-.*$", "")) end

_G.RAID_CLASS_COLORS = { MAGE = { colorStr = "ff3fc7eb" } }
function _G.GetPlayerInfoByGUID(guid)
    if guid == "Player-1-MAGE" then return "Mage", "MAGE" end
    return nil
end

_G.CHAT_YOU_CHANGED_NOTICE = "Changed Channel: |Hchannel:%d|h[%s]|h"
_G.BN_INLINE_TOAST_FRIEND_ONLINE = "%s has come online."
_G.BN_INLINE_TOAST_FRIEND_OFFLINE = "%s has gone offline."
_G.BN_INLINE_TOAST_FRIEND_REQUEST = "You have a pending friend request."
_G.BN_INLINE_TOAST_BROADCAST = "%s broadcast: %s"
_G.BN_INLINE_TOAST_BROADCAST_INFORM = "Broadcast sent."
_G.ERR_FRIEND_OFFLINE_S = "%s has gone offline."
_G.CHAT_IGNORED = "%s is ignoring you."
_G.CHAT_FILTERED = "Message to %s was filtered."
_G.CHAT_RESTRICTED_TRIAL = "Trial accounts cannot use that."
_G.CHAT_EMOTE_GET = "%s "
_G.CHAT_MONSTER_EMOTE_GET = "%s "
_G.CHAT_RAID_BOSS_EMOTE_GET = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|t%s "
_G.CHAT_MONSTER_SAY_GET = "%s says: "
_G.ChatFrameUtil = {
    GetOutMessageFormatKey = function(typeKey)
        if typeKey == "RAID_BOSS_EMOTE" then
            return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|t%s "
        end
        if typeKey == "MONSTER_YELL" then
            return "%s yells: "
        end
        return _G["CHAT_" .. typeKey .. "_GET"] or ""
    end,
}
function _G.BNGetNumFriendInvites() return 3 end
_G.BN_INLINE_TOAST_FRIEND_PENDING = "You have %d pending friend requests."

local function explode() error("operator applied to secret sentinel", 2) end
local secret = setmetatable({}, { __tostring = explode, __concat = explode, __len = explode })

-- ChannelColors override store (seeded for the rewire tests below).
-- Mirrors the real ChannelColors.GetEffective(key) contract:
--   builtin types keyed by type string ("SAY", "WHISPER", ...),
--   custom channels keyed by channel NAME ("Trade").
local channelColorDB = {}
local ChannelColors = {
    -- Faithful to the REAL contract (channel_colors.lua): GetEffective never
    -- returns nil (white fallback); consumers must gate on HasOverride.
    HasOverride = function(key)
        return channelColorDB[key] ~= nil
    end,
    GetEffective = function(key)
        local c = channelColorDB[key]
        if c then return c[1], c[2], c[3] end
        return 1, 1, 1 -- real API: white, NEVER nil
    end,
}

local ns = {
    Helpers = { IsSecretValue = function(v) return v == secret end },
    QUI = { Chat = {
        _internals = {
            GetSettings = function() return { modifiers = { classColors = { enabled = true } } } end,
        },
        ChannelColors = ChannelColors,
    } },
}

assert(loadfile("QUI_Chat/chat/message_format.lua"))("QUI", ns)
local F = ns.QUI.Chat.MessageFormat

local function eq(label, got, want)
    assert(got == want, label .. ": expected " .. tostring(want) .. " got " .. tostring(got))
end

-- EventToTypeKey
eq("typeKey SAY", F.EventToTypeKey("CHAT_MSG_SAY"), "SAY")
eq("typeKey RW", F.EventToTypeKey("CHAT_MSG_RAID_WARNING"), "RAID_WARNING")
eq("typeKey boss notice", F.EventToTypeKey("RAID_BOSS_EMOTE"), "RAID_BOSS_EMOTE")
eq("typeKey quest boss notice", F.EventToTypeKey("QUEST_BOSS_EMOTE"), "QUEST_BOSS_EMOTE")
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

-- Class-colored sender via GUID (reads RAID_CLASS_COLORS directly)
eq("class color", F.BuildLine("CHAT_MSG_SAY", "hi", "Bob-Realm", nil, nil, "Player-1-MAGE"),
    "|Hplayer:Bob-Realm|h[|cff3fc7ebBob|r]|h: hi")

-- Unknown GUID -> uncolored
eq("guid unknown", F.BuildLine("CHAT_MSG_SAY", "hi", "Bob-Realm", nil, nil, "Player-9-NONE"),
    "|Hplayer:Bob-Realm|h[Bob]|h: hi")

-- BN whisper WITH bnSenderID -> real BNplayer link
eq("bn link", F.BuildLine("CHAT_MSG_BN_WHISPER", "yo", "Aria", nil, nil, nil, 77),
    "[W:From] |HBNplayer:Aria:77:0:BN_WHISPER:0|h[Aria]|h: yo")

-- Secret sender degrades to bare text (no ops on the secret)
eq("secret sender", F.BuildLine("CHAT_MSG_SAY", "hello", secret), "hello")

-- Secret channel name degrades to no channel prefix
eq("secret channel", F.BuildLine("CHAT_MSG_CHANNEL", "x", "Ann", 2, secret),
    "|Hplayer:Ann|h[Ann]|h: x")

-- BuildEventLine: default path delegates to BuildLine
eq("evt default", F.BuildEventLine("CHAT_MSG_SAY", "hello", "Bob-Realm"),
    "|Hplayer:Bob-Realm|h[Bob]|h: hello")

-- Achievement: arg1 template formatted with player link
eq("evt ach", F.BuildEventLine("CHAT_MSG_ACHIEVEMENT", "%s has earned [Big Win]!", "Ann"),
    "|Hplayer:Ann|h[Ann]|h has earned [Big Win]!")

-- Channel notice: token -> globalstring(num, channelFullName)
eq("evt notice", F.BuildEventLine("CHAT_MSG_CHANNEL_NOTICE", "YOU_CHANGED", nil, "2. Trade", 2),
    "Changed Channel: |Hchannel:2|h[2. Trade]|h")

-- Unknown notice token -> nil (drop, never render raw token)
eq("evt notice unknown", F.BuildEventLine("CHAT_MSG_CHANNEL_NOTICE", "NO_SUCH_TOKEN", nil, "2. Trade", 2), nil)

-- BN toast with %s: BN link when bnID known; character name appended when
-- C_BattleNet.GetAccountInfoByID resolves (bnID 77 -> "Thrall" in the mock)
eq("evt toast", F.BuildEventLine("CHAT_MSG_BN_INLINE_TOAST_ALERT", "FRIEND_ONLINE", "Aria", nil, nil, nil, nil, 77),
    "|HBNplayer:Aria:77:0:BN_INLINE_TOAST_ALERT:0|h[Aria]|h (Thrall) has come online.")

-- No account info (bnID 88 unknown) -> no suffix
eq("evt toast nochar", F.BuildEventLine("CHAT_MSG_BN_INLINE_TOAST_ALERT", "FRIEND_ONLINE", "Bea", nil, nil, nil, nil, 88),
    "|HBNplayer:Bea:88:0:BN_INLINE_TOAST_ALERT:0|h[Bea]|h has come online.")

-- FRIEND_OFFLINE must never render as the raw token; it formats the localized
-- BN toast string with the actual friend display name.
eq("evt toast offline friend", F.BuildEventLine("CHAT_MSG_BN_INLINE_TOAST_ALERT", "FRIEND_OFFLINE", "Bea", nil, nil, nil, nil, 88, 31337),
    "|HBNplayer:Bea:88:31337:BN_INLINE_TOAST_ALERT:0|h[Bea]|h has gone offline.")

-- BN toast without %s: bare globalstring
eq("evt toast bare", F.BuildEventLine("CHAT_MSG_BN_INLINE_TOAST_ALERT", "FRIEND_REQUEST", nil),
    "You have a pending friend request.")

-- Player emotes use Blizzard's emote branch: link the sender without adding a
-- normal chat colon.
eq("evt player emote", F.BuildEventLine("CHAT_MSG_EMOTE", "waves.", "Ann"),
    "|Hplayer:Ann|h[Ann]|h waves.")

-- Text emotes are already full sentences; replace the first sender occurrence
-- with a player link instead of prefixing "sender: ".
eq("evt text emote", F.BuildEventLine("CHAT_MSG_TEXT_EMOTE", "Ann waves.", "Ann"),
    "|Hplayer:Ann|h[Ann]|h waves.")

-- Boss emote: format(GET .. text, name, name) — Blizzard substitutes the
-- GET's %s AND any %s inside the emote text with the monster name.
eq("evt boss", F.BuildEventLine("CHAT_MSG_RAID_BOSS_EMOTE", "%s prepares something deadly!", "Big Boss"),
    "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|tBig Boss Big Boss prepares something deadly!")

-- Boss and monster out-message prefixes must come from ChatFrameUtil when it
-- is available, matching Blizzard's MessageFormatter branch for MONSTER_* and
-- RAID_BOSS_* events.
local oldBossGet = _G.CHAT_RAID_BOSS_EMOTE_GET
_G.CHAT_RAID_BOSS_EMOTE_GET = nil
eq("evt boss helper prefix", F.BuildEventLine("CHAT_MSG_RAID_BOSS_EMOTE", "casts Doom.", "Big Boss"),
    "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|tBig Boss casts Doom.")
_G.CHAT_RAID_BOSS_EMOTE_GET = oldBossGet

eq("evt monster yell helper prefix", F.BuildEventLine("CHAT_MSG_MONSTER_YELL", "Run away!", "Dungeon Boss"),
    "Dungeon Boss yells: Run away!")

-- Monster emote
eq("evt emote", F.BuildEventLine("CHAT_MSG_MONSTER_EMOTE", "looks around.", "A Rat"),
    "A Rat looks around.")

-- Secret text on special path -> nil (drop)
eq("evt secret", F.BuildEventLine("CHAT_MSG_ACHIEVEMENT", secret, "Ann"), nil)

-- Monster say: GET verb + name, no player link
eq("evt monster say", F.BuildEventLine("CHAT_MSG_MONSTER_SAY", "Hello adventurer.", "Quest Giver"),
    "Quest Giver says: Hello adventurer.")

-- Non-chat raid-warning boss events feed RaidNotice_AddMessage in Blizzard;
-- when mirrored into QUI chat they use the same format(text, name, name) body.
eq("evt raid boss notice", F.BuildEventLine("RAID_BOSS_EMOTE", "%s casts Doom.", "Big Boss"),
    "Big Boss casts Doom.")
eq("evt raid boss whisper notice", F.BuildEventLine("RAID_BOSS_WHISPER", "%s whispers: Hide!", "Big Boss"),
    "Big Boss whispers: Hide!")
eq("evt quest boss notice", F.BuildEventLine("QUEST_BOSS_EMOTE", "%s calls for help.", "Quest Boss"),
    "Quest Boss calls for help.")

-- FRIEND_PENDING toast: %d invite count, never the raw template
eq("evt toast pending", F.BuildEventLine("CHAT_MSG_BN_INLINE_TOAST_ALERT", "FRIEND_PENDING", nil),
    "You have 3 pending friend requests.")

-- BN link carries lineID + category (INFORM maps to BN_WHISPER)
_G.BN_INLINE_TOAST_FRIEND_REMOVED = "%s has been removed from your friends list."
eq("bn lineid", F.BuildLine("CHAT_MSG_BN_WHISPER_INFORM", "yo", "Aria", nil, nil, nil, 77, 4242),
    "[W:To] |HBNplayer:Aria:77:4242:BN_WHISPER:0|h[Aria]|h: yo")

-- FRIEND_REMOVED: plain name, no link, no brackets (Blizzard parity)
eq("evt toast removed", F.BuildEventLine("CHAT_MSG_BN_INLINE_TOAST_ALERT", "FRIEND_REMOVED", "Aria"),
    "Aria has been removed from your friends list.")

-- BN broadcast/inform events carry templates, not plain message bodies.
eq("evt bn broadcast", F.BuildEventLine("CHAT_MSG_BN_INLINE_TOAST_BROADCAST", "Raid\nnight   now", "Aria", nil, nil, nil, nil, 77, 4242),
    "|HBNplayer:Aria:77:4242:BN_INLINE_TOAST_ALERT:0|h[Aria]|h broadcast: Raid night now")
eq("evt bn broadcast inform", F.BuildEventLine("CHAT_MSG_BN_INLINE_TOAST_BROADCAST_INFORM", "Raid night now", "Aria"),
    "Broadcast sent.")

-- Error/ignore events format global strings instead of displaying the token body.
eq("evt ignored", F.BuildEventLine("CHAT_MSG_IGNORED", "IGNORED", "Noisy"),
    "Noisy is ignoring you.")
eq("evt filtered", F.BuildEventLine("CHAT_MSG_FILTERED", "FILTERED", "Noisy"),
    "Message to Noisy was filtered.")
eq("evt restricted", F.BuildEventLine("CHAT_MSG_RESTRICTED", "RESTRICTED", nil),
    "Trial accounts cannot use that.")

-- CHANNEL_LIST roster rendering
_G.CHAT_CHANNEL_LIST_GET = "[%d. %s] "
-- chanlist with channel context: GET prefix + raw list text
-- format("[%d. %s] " .. "Ann, Bob, Cee", 2, "Trade") = "[2. Trade] Ann, Bob, Cee"
eq("evt chanlist", F.BuildEventLine("CHAT_MSG_CHANNEL_LIST", "Ann, Bob, Cee", nil, "Trade", 2),
    "[2. Trade] Ann, Bob, Cee")
-- No channel context (num/name absent) -> raw text
eq("evt chanlist raw", F.BuildEventLine("CHAT_MSG_CHANNEL_LIST", "Ann, Bob", nil, nil, nil),
    "Ann, Bob")

-- CHANNEL_NOTICE_USER moderation notices
-- Non-positional mocks; arg order matches Blizzard: (num, channelFull, actor [, target])
-- Single-user: format(gs, arg8=num, arg4=name, arg2=actor)
_G.CHAT_OWNER_CHANGED_NOTICE = "%d %s owner is now %s"
-- format("%d %s owner is now %s", 2, "Trade", "Ann") = "2 Trade owner is now Ann"
eq("evt notuser owner", F.BuildEventLine("CHAT_MSG_CHANNEL_NOTICE_USER", "OWNER_CHANGED", "Ann", "Trade", 2),
    "2 Trade owner is now Ann")

-- Two-user: format(gs, arg8=num, arg4=name, arg2=actor, arg5=target)
_G.CHAT_PLAYER_KICKED_NOTICE = "[%d %s] %s kicked by %s."
-- format("[%d %s] %s kicked by %s.", 2, "Trade", "Mod", "Bob") = "[2 Trade] Mod kicked by Bob."
eq("evt notuser kicked", F.BuildEventLine("CHAT_MSG_CHANNEL_NOTICE_USER", "PLAYER_KICKED", "Mod", "Trade", 2, nil, nil, nil, nil, "Bob"),
    "[2 Trade] Mod kicked by Bob.")

-- INVITE: format(gs, arg4=name, playerLink(arg2=actor))
_G.CHAT_INVITE_NOTICE = "%s has invited you to join %s"
-- format("%s has invited you to join %s", "Trade", "|Hplayer:Ann|h[Ann]|h")
--   = "Trade has invited you to join |Hplayer:Ann|h[Ann]|h"
eq("evt notuser invite", F.BuildEventLine("CHAT_MSG_CHANNEL_NOTICE_USER", "INVITE", "Ann", "Trade", nil),
    "Trade has invited you to join |Hplayer:Ann|h[Ann]|h")

-- Unknown token -> dropped (nil)
eq("evt notuser unknown", F.BuildEventLine("CHAT_MSG_CHANNEL_NOTICE_USER", "NO_SUCH", "Ann", "Trade", 2), nil)

-- ChannelColors rewire: override must reach ColorForTypeKey --------------------
-- 1. No override → ChatTypeInfo fallback (existing SAY mock: r=1, g=0.5, b=0.25)
r, g, b = F.ColorForTypeKey("SAY")
eq("rewire: no override SAY still reads ChatTypeInfo r", r, 1)
eq("rewire: no override SAY still reads ChatTypeInfo g", g, 0.5)
eq("rewire: no override SAY still reads ChatTypeInfo b", b, 0.25)

-- 2. Builtin override: seed SAY override, must win over ChatTypeInfo
channelColorDB["SAY"] = { 0.1, 0.2, 0.3 }
r, g, b = F.ColorForTypeKey("SAY")
eq("rewire: builtin override SAY r", r, 0.1)
eq("rewire: builtin override SAY g", g, 0.2)
eq("rewire: builtin override SAY b", b, 0.3)
channelColorDB["SAY"] = nil  -- clear for next assertions

-- 3. Custom-channel override: seed "Trade" by name; caller passes chName="Trade"
--    capture passes colorKey="CHANNEL2" + chName="Trade" — the rewire must
--    consult ChannelColors.GetEffective("Trade") because that's how the override
--    is stored (channel NAME, not slot).
channelColorDB["Trade"] = { 0.9, 0.8, 0.7 }
r, g, b = F.ColorForTypeKey("CHANNEL2", "Trade")
eq("rewire: custom-channel override Trade r", r, 0.9)
eq("rewire: custom-channel override Trade g", g, 0.8)
eq("rewire: custom-channel override Trade b", b, 0.7)
channelColorDB["Trade"] = nil

-- 4. REGRESSION (review Critical): non-builtin types with NO override must
--    read ChatTypeInfo, never the override store's white fallback. The real
--    GetEffective NEVER returns nil — an ungated call turns these white.
r, g, b = F.ColorForTypeKey("LOOT")
eq("rewire: no-override LOOT reads ChatTypeInfo r", r, 0)
eq("rewire: no-override LOOT reads ChatTypeInfo g", g, 0.667)
eq("rewire: no-override LOOT reads ChatTypeInfo b", b, 0)
r, g, b = F.ColorForTypeKey("MONSTER_YELL")
eq("rewire: no-override MONSTER_YELL reads ChatTypeInfo r", r, 1)
eq("rewire: no-override MONSTER_YELL g", g, 0.25)
eq("rewire: no-override MONSTER_YELL b", b, 0.25)
-- CHANNEL<n> with a readable number but SECRET/absent name: no chName →
-- override store skipped for the name; falls back to ChatTypeInfo/white,
-- never the store's white-on-miss masking a real CHANNEL2 color.
channelColorDB["CHANNEL2"] = { 0.5, 0.5, 0.9 } -- slot-keyed builtin-style override
r, g, b = F.ColorForTypeKey("CHANNEL2", nil)
eq("rewire: slot-keyed override reachable without chName r", r, 0.5)
channelColorDB["CHANNEL2"] = nil

-- 4. Custom-channel with NO override → falls back to ChatTypeInfo["CHANNEL2"]
--    (ChatTypeInfo mock: CHANNEL2 = { r=1, g=0.75, b=0.75 })
-- (The capture test already seeds that mock but format_test doesn't — we add it.)
_G.ChatTypeInfo = setmetatable({
    SAY = { r = 1, g = 0.5, b = 0.25 },
    GUILD = { r = 0.25, g = 1, b = 0.25 },
    CHANNEL2 = { r = 1, g = 0.75, b = 0.75 },
}, {
    __newindex = function() error("WRITE to ChatTypeInfo is forbidden") end,
})
r, g, b = F.ColorForTypeKey("CHANNEL2", "Trade")
eq("rewire: no custom override falls back to ChatTypeInfo CHANNEL2 r", r, 1)
eq("rewire: no custom override falls back to ChatTypeInfo CHANNEL2 g", g, 0.75)
eq("rewire: no custom override falls back to ChatTypeInfo CHANNEL2 b", b, 0.75)

-- 5. ColorForTypeKey with no ChannelColors available → falls back to ChatTypeInfo
--    (not a crash; nil-safe). For an unknown key → white.
local F2 = {}
do
    local ns2 = {
        Helpers = { IsSecretValue = function(v) return false end },
        QUI = { Chat = { _internals = {
            GetSettings = function() return {} end,
        } } },
        -- deliberately no ChannelColors on ns2.QUI.Chat
    }
    assert(loadfile("QUI_Chat/chat/message_format.lua"))("QUI", ns2)
    F2 = ns2.QUI.Chat.MessageFormat
end
-- "NOSUCH" has no ChatTypeInfo entry → white
r, g, b = F2.ColorForTypeKey("NOSUCH")
eq("rewire: no ChannelColors module → white fallback r", r, 1)
eq("rewire: no ChannelColors module → white fallback g", g, 1)
eq("rewire: no ChannelColors module → white fallback b", b, 1)

print("OK: chat_message_format_test")
