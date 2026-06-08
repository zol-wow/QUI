-- tests/unit/chat_message_format_test.lua
-- Run: lua tests/unit/chat_message_format_test.lua
-- Verifies event->typeKey mapping, Blizzard-parity line building (GET formats,
-- full player links with lineID:chatType:chatTarget, hyperlinked channel
-- prefixes), the channelShorten presets, sender decoration, READ-ONLY
-- ChatTypeInfo color lookup (write-trapped), and secret-arg degradation.

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

-- FrameXML constant consumed for link chatType data (PARTY_LEADER -> PARTY).
_G.CHAT_INVERTED_CATEGORY_LIST = {
    PARTY_LEADER = "PARTY", RAID_LEADER = "RAID", RAID_WARNING = "RAID",
    GUILD_ACHIEVEMENT = "GUILD", GUILD_ITEM_LOOTED = "GUILD",
    WHISPER_INFORM = "WHISPER", AFK = "WHISPER", DND = "WHISPER",
    BN_WHISPER_INFORM = "BN_WHISPER", INSTANCE_CHAT_LEADER = "INSTANCE_CHAT",
}

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
_G.CHAT_EMOTE_GET = "%s "
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
-- Identity set of secret sentinels: the WrapSecretEventLine section below
-- registers string.format RESULTS here too (in-game, format propagates
-- secrecy onto everything it builds from a secret input).
local secrets = { [secret] = true }

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

-- channelShorten defaults ON (matches core/defaults.lua); flipped per-section.
local settings = { modifiers = {
    classColors = { enabled = true },
    channelShorten = { enabled = true, preset = "letter" },
} }

local ns = {
    Helpers = { IsSecretValue = function(v) return secrets[v] == true end },
    QUI = { Chat = {
        _internals = {
            GetSettings = function() return settings end,
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

-- DecorateSender: realm ambiguated; class color from GUID (QUI setting gate)
eq("decorate ambiguate", F.DecorateSender("CHAT_MSG_SAY", "hi", "Bob-Realm"), "Bob")
-- guid is a12: event, text(1), sender(2), then a3..a11 nils, guid at 12
eq("decorate class color",
    F.DecorateSender("CHAT_MSG_SAY", "hi", "Bob-Realm", nil, nil, nil, nil, nil, nil, nil, nil, nil, "Player-1-MAGE"),
    "|cff3fc7ebBob|r")
eq("decorate guid unknown",
    F.DecorateSender("CHAT_MSG_SAY", "hi", "Bob-Realm", nil, nil, nil, nil, nil, nil, nil, nil, nil, "Player-9-NONE"),
    "Bob")
eq("decorate secret sender", F.DecorateSender("CHAT_MSG_SAY", "hi", secret), nil)

-- ============ short mode (channelShorten enabled, letter preset) ============

-- SAY: no type prefix in short mode; full player link carries lineID:chatType:chatTarget
eq("say line", F.BuildEventLine("CHAT_MSG_SAY", { text = "hello", sender = "Bob-Realm", decorated = "Bob" }),
    "|Hplayer:Bob-Realm:0:SAY:|h[Bob]|h: hello")

-- Guild gets the short prefix
eq("guild line", F.BuildEventLine("CHAT_MSG_GUILD", { text = "hi", sender = "Ann" }),
    "[G] |Hplayer:Ann:0:GUILD:|h[Ann]|h: hi")

-- Numbered channel: letter preset abbreviates the label; the channel link and
-- the link's channel chatTarget survive
eq("channel line", F.BuildEventLine("CHAT_MSG_CHANNEL",
        { text = "wts", sender = "Ann", chNum = 2, chBase = "Trade", chName = "Trade", channelFull = "2. Trade" }),
    "|Hchannel:channel:2|h[T]|h |Hplayer:Ann:0:CHANNEL:2|h[Ann]|h: wts")

-- Channel without number (secret/absent arg8+arg4, base name survived)
eq("channel noname", F.BuildEventLine("CHAT_MSG_CHANNEL",
        { text = "wts", sender = "Ann", chName = "Trade" }),
    "[Trade] |Hplayer:Ann:0:CHANNEL:|h[Ann]|h: wts")

-- Number preset keeps just the slot number
settings.modifiers.channelShorten.preset = "number"
eq("channel number preset", F.BuildEventLine("CHAT_MSG_CHANNEL",
        { text = "wts", sender = "Ann", chNum = 2, chBase = "Trade", chName = "Trade", channelFull = "2. Trade" }),
    "|Hchannel:channel:2|h[2]|h |Hplayer:Ann:0:CHANNEL:2|h[Ann]|h: wts")
settings.modifiers.channelShorten.preset = "letter"

-- RAW types render bodies verbatim — CHAT_MSG_SYSTEM often carries a sender
-- name in arg2 that must NOT become a prefix (Blizzard parity).
eq("system raw", F.BuildEventLine("CHAT_MSG_SYSTEM", { text = "Realm restart", sender = "Ann" }),
    "Realm restart")

-- BN whisper sender renders plain (a |Hplayer:| link would be a broken target)
eq("bn whisper", F.BuildEventLine("CHAT_MSG_BN_WHISPER", { text = "yo", sender = "Aria" }),
    "[W:From] [Aria]: yo")

-- BN whisper WITH bnSenderID -> real BNplayer link (chatTarget = upper name)
eq("bn link", F.BuildEventLine("CHAT_MSG_BN_WHISPER", { text = "yo", sender = "Aria", bnID = 77 }),
    "[W:From] |HBNplayer:Aria:77:0:BN_WHISPER:ARIA|h[Aria]|h: yo")

-- BN link carries lineID + category (INFORM maps to BN_WHISPER)
eq("bn lineid", F.BuildEventLine("CHAT_MSG_BN_WHISPER_INFORM",
        { text = "yo", sender = "Aria", bnID = 77, lineID = 4242 }),
    "[W:To] |HBNplayer:Aria:77:4242:BN_WHISPER:ARIA|h[Aria]|h: yo")

-- Absent text -> nil (capture guards non-empty strings; nothing to render)
eq("nil text", F.BuildEventLine("CHAT_MSG_SAY", { sender = "Ann" }), nil)

-- Secret sender (capture passes sender=nil) degrades to the bare body
eq("secret sender", F.BuildEventLine("CHAT_MSG_SAY", { text = "hello", rawSender = secret }), "hello")

-- Secret channel name degrades to no channel prefix (chatTarget keeps slot)
eq("secret channel", F.BuildEventLine("CHAT_MSG_CHANNEL", { text = "x", sender = "Ann", chNum = 2 }),
    "|Hplayer:Ann:0:CHANNEL:2|h[Ann]|h: x")

-- Achievement: arg1 template formatted with player link (decorated name)
eq("evt ach", F.BuildEventLine("CHAT_MSG_ACHIEVEMENT", { text = "%s has earned [Big Win]!", sender = "Ann" }),
    "|Hplayer:Ann|h[Ann]|h has earned [Big Win]!")

-- Channel notice: token -> globalstring(num, channelFullName)
eq("evt notice", F.BuildEventLine("CHAT_MSG_CHANNEL_NOTICE",
        { text = "YOU_CHANGED", channelFull = "2. Trade", chNum = 2 }),
    "Changed Channel: |Hchannel:2|h[2. Trade]|h")

-- Unknown notice token -> nil (drop, never render raw token)
eq("evt notice unknown", F.BuildEventLine("CHAT_MSG_CHANNEL_NOTICE",
    { text = "NO_SUCH_TOKEN", channelFull = "2. Trade", chNum = 2 }), nil)

-- BN toast with %s: BN link when bnID known; character name appended when
-- C_BattleNet.GetAccountInfoByID resolves (bnID 77 -> "Thrall" in the mock)
eq("evt toast", F.BuildEventLine("CHAT_MSG_BN_INLINE_TOAST_ALERT",
        { text = "FRIEND_ONLINE", sender = "Aria", bnID = 77 }),
    "|HBNplayer:Aria:77:0:BN_INLINE_TOAST_ALERT:0|h[Aria]|h (Thrall) has come online.")

-- No account info (bnID 88 unknown) -> no suffix
eq("evt toast nochar", F.BuildEventLine("CHAT_MSG_BN_INLINE_TOAST_ALERT",
        { text = "FRIEND_ONLINE", sender = "Bea", bnID = 88 }),
    "|HBNplayer:Bea:88:0:BN_INLINE_TOAST_ALERT:0|h[Bea]|h has come online.")

-- FRIEND_OFFLINE must never render as the raw token; it formats the localized
-- BN toast string with the actual friend display name.
eq("evt toast offline friend", F.BuildEventLine("CHAT_MSG_BN_INLINE_TOAST_ALERT",
        { text = "FRIEND_OFFLINE", sender = "Bea", bnID = 88, lineID = 31337 }),
    "|HBNplayer:Bea:88:31337:BN_INLINE_TOAST_ALERT:0|h[Bea]|h has gone offline.")

-- BN toast without %s: bare globalstring
eq("evt toast bare", F.BuildEventLine("CHAT_MSG_BN_INLINE_TOAST_ALERT", { text = "FRIEND_REQUEST" }),
    "You have a pending friend request.")

-- Player emotes: Blizzard's emote grammar — sender link WITHOUT brackets
-- (usingEmote keeps the bare decorated name), no colon.
eq("evt player emote", F.BuildEventLine("CHAT_MSG_EMOTE", { text = "waves.", sender = "Ann" }),
    "|Hplayer:Ann:0:EMOTE:|hAnn|h waves.")

-- Text emotes are already full sentences; replace the first sender occurrence
-- with a player link instead of prefixing "sender: ".
eq("evt text emote", F.BuildEventLine("CHAT_MSG_TEXT_EMOTE", { text = "Ann waves.", sender = "Ann" }),
    "|Hplayer:Ann:0:TEXT_EMOTE:|hAnn|h waves.")

-- Boss emote: format(GET .. text, name, name) — Blizzard substitutes the
-- GET's %s AND any %s inside the emote text with the monster name.
eq("evt boss", F.BuildEventLine("CHAT_MSG_RAID_BOSS_EMOTE",
        { text = "%s prepares something deadly!", sender = "Big Boss" }),
    "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|tBig Boss Big Boss prepares something deadly!")

-- Boss and monster out-message prefixes must come from ChatFrameUtil when it
-- is available, matching Blizzard's MessageFormatter branch for MONSTER_* and
-- RAID_BOSS_* events.
local oldBossGet = _G.CHAT_RAID_BOSS_EMOTE_GET
_G.CHAT_RAID_BOSS_EMOTE_GET = nil
eq("evt boss helper prefix", F.BuildEventLine("CHAT_MSG_RAID_BOSS_EMOTE",
        { text = "casts Doom.", sender = "Big Boss" }),
    "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|tBig Boss casts Doom.")
_G.CHAT_RAID_BOSS_EMOTE_GET = oldBossGet

eq("evt monster yell helper prefix", F.BuildEventLine("CHAT_MSG_MONSTER_YELL",
        { text = "Run away!", sender = "Dungeon Boss" }),
    "Dungeon Boss yells: Run away!")

-- Monster emote
eq("evt emote", F.BuildEventLine("CHAT_MSG_MONSTER_EMOTE", { text = "looks around.", sender = "A Rat" }),
    "A Rat looks around.")

-- Secret text on special path -> nil (drop)
eq("evt secret", F.BuildEventLine("CHAT_MSG_ACHIEVEMENT", { text = secret, sender = "Ann" }), nil)

-- Monster say: GET verb + name, no player link
eq("evt monster say", F.BuildEventLine("CHAT_MSG_MONSTER_SAY",
        { text = "Hello adventurer.", sender = "Quest Giver" }),
    "Quest Giver says: Hello adventurer.")

-- Non-chat raid-warning boss events feed RaidNotice_AddMessage in Blizzard;
-- when mirrored into QUI chat they use the same format(text, name, name) body.
eq("evt raid boss notice", F.BuildEventLine("RAID_BOSS_EMOTE",
        { text = "%s casts Doom.", sender = "Big Boss" }),
    "Big Boss casts Doom.")
eq("evt raid boss whisper notice", F.BuildEventLine("RAID_BOSS_WHISPER",
        { text = "%s whispers: Hide!", sender = "Big Boss" }),
    "Big Boss whispers: Hide!")
eq("evt quest boss notice", F.BuildEventLine("QUEST_BOSS_EMOTE",
        { text = "%s calls for help.", sender = "Quest Boss" }),
    "Quest Boss calls for help.")

-- FRIEND_PENDING toast: %d invite count, never the raw template
eq("evt toast pending", F.BuildEventLine("CHAT_MSG_BN_INLINE_TOAST_ALERT", { text = "FRIEND_PENDING" }),
    "You have 3 pending friend requests.")

-- FRIEND_REMOVED: plain name, no link, no brackets (Blizzard parity)
_G.BN_INLINE_TOAST_FRIEND_REMOVED = "%s has been removed from your friends list."
eq("evt toast removed", F.BuildEventLine("CHAT_MSG_BN_INLINE_TOAST_ALERT",
        { text = "FRIEND_REMOVED", sender = "Aria" }),
    "Aria has been removed from your friends list.")

-- BN broadcast/inform events carry templates, not plain message bodies.
eq("evt bn broadcast", F.BuildEventLine("CHAT_MSG_BN_INLINE_TOAST_BROADCAST",
        { text = "Raid\nnight   now", sender = "Aria", bnID = 77, lineID = 4242 }),
    "|HBNplayer:Aria:77:4242:BN_INLINE_TOAST_ALERT:0|h[Aria]|h broadcast: Raid night now")
eq("evt bn broadcast inform", F.BuildEventLine("CHAT_MSG_BN_INLINE_TOAST_BROADCAST_INFORM",
        { text = "Raid night now", sender = "Aria" }),
    "Broadcast sent.")

-- Error/ignore events format global strings instead of displaying the token body.
eq("evt ignored", F.BuildEventLine("CHAT_MSG_IGNORED", { text = "IGNORED", sender = "Noisy" }),
    "Noisy is ignoring you.")
eq("evt filtered", F.BuildEventLine("CHAT_MSG_FILTERED", { text = "FILTERED", sender = "Noisy" }),
    "Message to Noisy was filtered.")
eq("evt restricted", F.BuildEventLine("CHAT_MSG_RESTRICTED", { text = "RESTRICTED" }),
    "Trial accounts cannot use that.")

-- CHANNEL_LIST roster rendering
_G.CHAT_CHANNEL_LIST_GET = "[%d. %s] "
-- chanlist with channel context: GET prefix + raw list text
-- format("[%d. %s] " .. "Ann, Bob, Cee", 2, "Trade") = "[2. Trade] Ann, Bob, Cee"
eq("evt chanlist", F.BuildEventLine("CHAT_MSG_CHANNEL_LIST",
        { text = "Ann, Bob, Cee", channelFull = "Trade", chNum = 2 }),
    "[2. Trade] Ann, Bob, Cee")
-- No channel context (num/name absent) -> raw text
eq("evt chanlist raw", F.BuildEventLine("CHAT_MSG_CHANNEL_LIST", { text = "Ann, Bob" }),
    "Ann, Bob")

-- CHANNEL_NOTICE_USER moderation notices
-- Non-positional mocks; arg order matches Blizzard: (num, channelFull, actor [, target])
-- Single-user: format(gs, arg8=num, arg4=name, arg2=actor)
_G.CHAT_OWNER_CHANGED_NOTICE = "%d %s owner is now %s"
-- format("%d %s owner is now %s", 2, "Trade", "Ann") = "2 Trade owner is now Ann"
eq("evt notuser owner", F.BuildEventLine("CHAT_MSG_CHANNEL_NOTICE_USER",
        { text = "OWNER_CHANGED", sender = "Ann", channelFull = "Trade", chNum = 2 }),
    "2 Trade owner is now Ann")

-- Two-user: format(gs, arg8=num, arg4=name, arg2=actor, arg5=target)
_G.CHAT_PLAYER_KICKED_NOTICE = "[%d %s] %s kicked by %s."
-- format("[%d %s] %s kicked by %s.", 2, "Trade", "Mod", "Bob") = "[2 Trade] Mod kicked by Bob."
eq("evt notuser kicked", F.BuildEventLine("CHAT_MSG_CHANNEL_NOTICE_USER",
        { text = "PLAYER_KICKED", sender = "Mod", channelFull = "Trade", chNum = 2, target = "Bob" }),
    "[2 Trade] Mod kicked by Bob.")

-- INVITE: format(gs, arg4=name, playerLink(arg2=actor))
_G.CHAT_INVITE_NOTICE = "%s has invited you to join %s"
-- format("%s has invited you to join %s", "Trade", "|Hplayer:Ann|h[Ann]|h")
--   = "Trade has invited you to join |Hplayer:Ann|h[Ann]|h"
eq("evt notuser invite", F.BuildEventLine("CHAT_MSG_CHANNEL_NOTICE_USER",
        { text = "INVITE", sender = "Ann", channelFull = "Trade" }),
    "Trade has invited you to join |Hplayer:Ann|h[Ann]|h")

-- Unknown token -> dropped (nil)
eq("evt notuser unknown", F.BuildEventLine("CHAT_MSG_CHANNEL_NOTICE_USER",
    { text = "NO_SUCH", sender = "Ann", channelFull = "Trade", chNum = 2 }), nil)

-- GUILD_ITEM_LOOTED: "$s" placeholder substituted with a bare player link
eq("evt guild item looted", F.BuildEventLine("CHAT_MSG_GUILD_ITEM_LOOTED",
        { text = "$s loots [Sword]", sender = "Ann" }),
    "|Hplayer:Ann|h[Ann]|h loots [Sword]")

-- ============ full mode (channelShorten disabled: Blizzard GET formats) =====

settings.modifiers.channelShorten.enabled = false
_G.CHAT_SAY_GET = "%s says: "
_G.CHAT_CHANNEL_GET = "%s: "

eq("say full", F.BuildEventLine("CHAT_MSG_SAY", { text = "hello", sender = "Bob-Realm", decorated = "Bob" }),
    "|Hplayer:Bob-Realm:0:SAY:|h[Bob]|h says: hello")

-- Full channel label via ResolvePrefixedChannelName (identity without util)
eq("channel full", F.BuildEventLine("CHAT_MSG_CHANNEL",
        { text = "wts", sender = "Ann", chNum = 2, chBase = "Trade", chName = "Trade", channelFull = "2. Trade" }),
    "|Hchannel:channel:2|h[2. Trade]|h |Hplayer:Ann:0:CHANNEL:2|h[Ann]|h: wts")

-- Language header when the message language differs from the default
_G.GetDefaultLanguage = function() return "Common" end
_G.GetAlternativeDefaultLanguage = function() return "Common" end
eq("say language header", F.BuildEventLine("CHAT_MSG_SAY",
        { text = "throm-ka", sender = "Bob-Realm", decorated = "Bob", language = "Orcish" }),
    "|Hplayer:Bob-Realm:0:SAY:|h[Bob]|h says: [Orcish] throm-ka")

-- AFK flag prefix from CHAT_FLAG_* globalstrings
_G.CHAT_FLAG_AFK = "<AFK> "
eq("afk pflag", F.BuildEventLine("CHAT_MSG_SAY",
        { text = "hello", sender = "Bob-Realm", decorated = "Bob", flags = "AFK" }),
    "<AFK> |Hplayer:Bob-Realm:0:SAY:|h[Bob]|h says: hello")

-- Raid-icon expression expansion routed through C_ChatInfo
_G.C_ChatInfo = { ReplaceIconAndGroupExpressions = function(msg) return (msg:gsub("{rt1}", "{ICON}")) end }
eq("raid icon expansion", F.BuildEventLine("CHAT_MSG_SAY",
        { text = "go {rt1}", sender = "Bob-Realm", decorated = "Bob" }),
    "|Hplayer:Bob-Realm:0:SAY:|h[Bob]|h says: go {ICON}")
_G.C_ChatInfo = nil

settings.modifiers.channelShorten.enabled = true

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

-- ======== WrapSecretEventLine: secret bodies across message types ========
-- In-game, string.format accepts secret VALUES and PROPAGATES secrecy; only
-- Lua operators (==, .., #, tostring) throw ("attempt to compare local
-- 'prefix' (a secret string value...)" — the original 46x crash). A secret
-- body is never used AS a format string. Per type: monster/emote build a GET
-- prefix from a fixed template and join the raw body; special + boss-notice
-- bodies (which ARE the template) pass through verbatim; raw types pass
-- through. Assertions pin the contract BY IDENTITY — no comparisons, no drop
-- to a different value than each type's grammar demands.
do
    local meta = getmetatable(secret)
    local function sentinel()
        local s = setmetatable({}, meta)
        secrets[s] = true
        return s
    end

    local secretSender = sentinel()
    local monsterBody = sentinel()     -- MONSTER_*: GET prefix + raw body joined
    local bossBody = sentinel()        -- RAID_BOSS_EMOTE notice: passes through
    local achBody = sentinel()         -- ACHIEVEMENT (special): passes through
    local playerEmoteBody = sentinel() -- EMOTE: GET join, linked non-secret sender
    local prefixes = {}                -- propagated GET prefixes by fmt string
    local joins = {}                   -- final "%s%s" joins keyed by body sentinel

    local realFormat = string.format
    string.format = function(fmt, ...)
        local a1 = ...
        if type(fmt) == "string" and fmt ~= "%s%s" and fmt:find("%%s")
            and rawequal(a1, secretSender) then
            prefixes[fmt] = prefixes[fmt] or sentinel() -- GET prefix: secret in, secret out
            return prefixes[fmt]
        elseif fmt == "%s%s" and (secrets[a1] or type(a1) == "string") then
            local body = select(2, ...)
            joins[body] = joins[body] or { prefix = a1, j = sentinel() }
            return joins[body].j
        end
        return realFormat(fmt, ...)
    end

    -- 1. MONSTER_EMOTE, secret sender + body: GET prefix propagates secret,
    --    the RAW body is joined to it. Never the bare body, never nil. (The
    --    name lives in the GET prefix — the body is never used as a format.)
    local got = F.WrapSecretEventLine("CHAT_MSG_MONSTER_EMOTE",
        { text = monsterBody, rawSender = secretSender, lineID = 2538 })
    assert(joins[monsterBody] and rawequal(got, joins[monsterBody].j)
        and rawequal(joins[monsterBody].prefix, prefixes["%s "]),
        "monster emote: GET prefix + raw body joined")

    -- 2. Boss notice: body IS the template — can't format a secret body, so
    --    pass the body through verbatim.
    got = F.WrapSecretEventLine("RAID_BOSS_EMOTE",
        { text = bossBody, rawSender = "Big Boss", sender = "Big Boss" })
    assert(rawequal(got, bossBody), "boss notice: secret body passes through")

    -- 3. Achievement (a SPECIAL_KIND): body is the template — passes through.
    got = F.WrapSecretEventLine("CHAT_MSG_ACHIEVEMENT",
        { text = achBody, rawSender = "Ann", sender = "Ann" })
    assert(rawequal(got, achBody), "achievement: secret body passes through")

    -- 4. Player EMOTE, non-secret sender: GET ("%s ") joined like Blizzard,
    --    sender rendered as a player link inside the prefix.
    got = F.WrapSecretEventLine("CHAT_MSG_EMOTE",
        { text = playerEmoteBody, rawSender = "Bob-Realm", sender = "Bob-Realm",
          decorated = "Bob" })
    local j = joins[playerEmoteBody]
    assert(j and rawequal(got, j.j), "player emote: GET prefix joined")
    assert(type(j.prefix) == "string" and j.prefix:find("|Hplayer:", 1, true)
        and j.prefix:find("Bob", 1, true), "player emote: linked sender in prefix")

    string.format = realFormat
end

print("OK: chat_message_format_test")
