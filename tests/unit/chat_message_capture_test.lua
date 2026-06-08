-- tests/unit/chat_message_capture_test.lua
-- Run: lua tests/unit/chat_message_capture_test.lua
-- Verifies: event registration from ChatTypeGroupInverted gated by
-- IsEventValid; Blizzard filter pass (drop + rewrite); secret-first capture
-- (secret bodies only flow through formatting/rendering sinks); disabled-chat gating; teardown;
-- AddMessage fallback hook skipping event-driven and own-addon traffic.

local function explode() error("operator applied to secret sentinel", 2) end
local secretMeta = { __tostring = explode, __concat = explode, __len = explode, __eq = explode }
local secret = setmetatable({}, secretMeta)
local secretSender = setmetatable({}, secretMeta)
local formattedSecretBarePlayer = {}
local formattedSecretGuild = {}
local formattedSecretMonster = {}
local formattedSecretParty = {}
local formattedSecretRaidWarning = {}
local formattedSecretWhisper = {}
local formattedSecretBNWhisper = {}
local formattedSecretChannel = {}
local formattedSecretYell = {}
local formattedSecretCommunity = {}
local formattedSecretSenderName = {}
local formattedSecretSenderLink = {}
local formattedSecretSenderPrefix = {}
local formattedSecretPartyAndSender = {}
-- Generic propagation result: any format() touching a secret yields a secret.
local formattedSecretPropagated = {}
-- Prefixes match the parity formatter: full player links with
-- lineID:chatType:chatTarget data, short type labels (channelShorten enabled
-- in the settings mock below), letter-preset channel decoration.
local formattedLinesByPrefix = {
    ["|Hplayer:Ann:0:SAY:|h[Ann]|h: "] = formattedSecretBarePlayer,
    ["[G] |Hplayer:Ann:0:GUILD:|h[Ann]|h: "] = formattedSecretGuild,
    ["Dungeon Boss yells: "] = formattedSecretMonster,
    ["[P] |Hplayer:Ann:0:PARTY:|h[Ann]|h: "] = formattedSecretParty,
    ["[RW] |Hplayer:Boss:0:RAID:|h[Boss]|h: "] = formattedSecretRaidWarning,
    ["[W:From] |Hplayer:Ann:0:WHISPER:ANN|h[Ann]|h: "] = formattedSecretWhisper,
    ["[W:From] |HBNplayer:Aria:77:31337:BN_WHISPER:ARIA|h[Aria]|h: "] = formattedSecretBNWhisper,
    ["|Hchannel:channel:2|h[T]|h |Hplayer:Ann:0:CHANNEL:2|h[Ann]|h: "] = formattedSecretChannel,
    ["[Y] |Hplayer:Ann:0:YELL:|h[Ann]|h: "] = formattedSecretYell,
    ["[Ann]: "] = formattedSecretCommunity,
}

local realStringFormat = string.format
string.format = function(fmt, ...)
    local a1, a2 = ...
    if fmt == "%s%s" and type(a1) == "string" and rawequal(a2, secret)
        and formattedLinesByPrefix[a1] then
        return formattedLinesByPrefix[a1]
    elseif fmt == "[%s]" and rawequal(a1, secretSender) then
        return formattedSecretSenderName
    elseif fmt == "|Hplayer:%s|h%s|h" and rawequal(a1, secretSender) and rawequal(a2, formattedSecretSenderName) then
        return formattedSecretSenderLink
    elseif fmt == "%s%s" and a1 == "" and rawequal(a2, formattedSecretSenderLink) then
        -- pflag .. link join (empty pflag): identity on the secret link
        return formattedSecretSenderLink
    elseif fmt == "[P] %s: " and rawequal(a1, formattedSecretSenderLink) then
        return formattedSecretSenderPrefix
    elseif fmt == "%s%s" and rawequal(a1, formattedSecretSenderPrefix) and rawequal(a2, secret) then
        return formattedSecretPartyAndSender
    end
    -- Propagation model: string.format with ANY secret (sentinel table) arg
    -- returns a secret. In-game string.format accepts secret values and
    -- propagates; here the sentinels are plain tables, so realStringFormat
    -- would error — the wrapper no longer pcall-guards these (by design), so
    -- the mock must model the propagation the C side performs.
    for i = 1, select("#", ...) do
        if type((select(i, ...))) == "table" then return formattedSecretPropagated end
    end
    return realStringFormat(fmt, ...)
end

-- WoW API mocks ------------------------------------------------------------
local registered, unregisteredAll = {}, false
local captureFrame = {
    RegisterEvent = function(_, e) registered[e] = true end,
    UnregisterAllEvents = function() unregisteredAll = true; registered = {} end,
    SetScript = function(self, _, fn) self._onEvent = fn end,
}
function _G.CreateFrame() return captureFrame end
_G.ChatTypeGroupInverted = { CHAT_MSG_SAY = "SAY", CHAT_MSG_GUILD = "GUILD", CHAT_MSG_BOGUS = "BOGUS",
    GUILD_MOTD = "GUILD", CHAT_MSG_CHANNEL_NOTICE = "CHANNEL",
    CHAT_MSG_ACHIEVEMENT = "ACHIEVEMENT", CHAT_MSG_CHANNEL_LIST = "CHANNEL",
    CHAT_MSG_EMOTE = "EMOTE", CHAT_MSG_TEXT_EMOTE = "EMOTE",
    CHAT_MSG_MONSTER_YELL = "MONSTER_YELL", CHAT_MSG_RAID_BOSS_EMOTE = "MONSTER_BOSS_EMOTE",
    CHAT_MSG_IGNORED = "IGNORED", CHAT_MSG_FILTERED = "ERRORS", CHAT_MSG_RESTRICTED = "ERRORS" }
-- FrameXML constant consumed for link chatType data (RAID_WARNING -> RAID).
_G.CHAT_INVERTED_CATEGORY_LIST = {
    RAID_WARNING = "RAID", PARTY_LEADER = "PARTY",
    WHISPER_INFORM = "WHISPER", BN_WHISPER_INFORM = "BN_WHISPER",
}
_G.CHAT_YOU_CHANGED_NOTICE = "Changed Channel: |Hchannel:%d|h[%s]|h"
_G.BN_INLINE_TOAST_FRIEND_OFFLINE = "%s has gone offline."
_G.BN_INLINE_TOAST_BROADCAST = "%s broadcast: %s"
_G.BN_INLINE_TOAST_BROADCAST_INFORM = "Broadcast sent."
_G.ERR_FRIEND_OFFLINE_S = "%s has gone offline."
_G.CHAT_IGNORED = "%s is ignoring you."
_G.CHAT_FILTERED = "Message to %s was filtered."
_G.CHAT_RESTRICTED_TRIAL = "Trial accounts cannot use that."
_G.CHAT_EMOTE_GET = "%s "
-- GET globals for the monster/boss prefixes. They exist in the live client; the
-- format-key resolver only consults ChatFrameUtil.GetOutMessageFormatKey when
-- the key is present (key-less types like TEXT_EMOTE must not trip the helper's
-- missing-key assert — see chat_text_emote_missing_get_no_assert_test).
_G.CHAT_MONSTER_YELL_GET = "%s yells: "
_G.CHAT_RAID_BOSS_EMOTE_GET = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|t%s "
_G.GetPlayerInfoByGUID = function() return nil end
_G.RAID_CLASS_COLORS = {}
_G.C_EventUtils = { IsEventValid = function(e) return e ~= "CHAT_MSG_BOGUS" end }
_G.C_StringUtil = {
    WrapString = function()
        error("secret chat formatter should not require C_StringUtil.WrapString", 2)
    end,
}
_G.ChatTypeInfo = { SAY = { r = 1, g = 1, b = 1 }, RAID_WARNING = { r = 1, g = 0.28, b = 0 }, CHANNEL2 = { r = 1, g = 0.75, b = 0.75 },
    EMOTE = { r = 1, g = 0.5, b = 0.25 }, TEXT_EMOTE = { r = 1, g = 0.5, b = 0.25 },
    MONSTER_YELL = { r = 1, g = 0.25, b = 0.25 }, RAID_BOSS_EMOTE = { r = 1, g = 0.82, b = 0 } }
function _G.Ambiguate(name) return name end
function _G.GetServerTime() return 1234 end
local backfillLines = {
    { "old line one", 1, 1, 1 },
    { "old line two", 0.5, 0.5, 0.5 },
}
_G.ChatFrame1 = {
    name = "ChatFrame1",
    GetNumMessages = function() return #backfillLines + 1 end, -- +1 secret below
    GetMessageInfo = function(_, i)
        if i > #backfillLines then return secret, 1, 1, 1 end
        local l = backfillLines[i]
        return l[1], l[2], l[3], l[4]
    end,
}
_G.DEFAULT_CHAT_FRAME = _G.ChatFrame1

local filterImpl = nil
_G.ChatFrameUtil = { ProcessMessageEventFilters = function(frame, event, ...)
    if filterImpl then return filterImpl(frame, event, ...) end
    return false, ...
end,
GetOutMessageFormatKey = function(typeKey)
    if typeKey == "RAID_BOSS_EMOTE" then
        return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|t%s "
    end
    if typeKey == "MONSTER_YELL" then
        return "%s yells: "
    end
    return _G["CHAT_" .. typeKey .. "_GET"] or ""
end }

local hooked = {}
local hookCount = 0
function _G.hooksecurefunc(tbl, name, fn) hooked[name] = fn; hookCount = hookCount + 1 end
local stack = ""
function _G.debugstack() return stack end

-- ns / settings scaffolding --------------------------------------------------
local tsSecretCalls = 0
local settings = { enabled = true, customDisplay = { maxLines = 500 }, urls = { enabled = true },
    -- channelShorten ON matches core/defaults.lua: short type labels + letter
    -- channel abbreviations (the secret prefix map above assumes this mode).
    modifiers = { channelShorten = { enabled = true, preset = "letter" } } }
-- Channel-color override store (ChannelColors rewire).
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
    Helpers = { IsSecretValue = function(v) return rawequal(v, secret) or rawequal(v, secretSender)
        or rawequal(v, formattedSecretSenderName) or rawequal(v, formattedSecretSenderLink)
        or rawequal(v, formattedSecretSenderPrefix) end },
    QUI = { Chat = {
        _internals = {
            GetSettings = function() return settings end,
            IsChatEnabled = function(s) return s and s.enabled ~= false end,
            AddTimestamp = function(t)
                if type(t) ~= "string" then tsSecretCalls = tsSecretCalls + 1; return t end
                return "[12:00] " .. t
            end,
            MakeURLsClickable = function(t) return (t:gsub("URLX", "|Hurl:x|hURLX|h")) end,
        },
        ChannelColors = ChannelColors,
        -- Conversation tagging consumes WHISPER_EVENTS + DeriveKey (the real module
        -- loads after capture in chat.xml; capture must therefore do RUNTIME lookups).
        ConversationManager = {
            WHISPER_EVENTS = {
                CHAT_MSG_WHISPER           = { chatType = "WHISPER", incoming = true },
                CHAT_MSG_WHISPER_INFORM    = { chatType = "WHISPER", incoming = false },
                CHAT_MSG_BN_WHISPER        = { chatType = "BN_WHISPER", incoming = true },
                CHAT_MSG_BN_WHISPER_INFORM = { chatType = "BN_WHISPER", incoming = false },
            },
            DeriveKey = function(chatType, name)
                if type(name) ~= "string" or name == "" then return nil end
                return ((chatType == "BN_WHISPER") and "BN:" or "W:") .. name:lower()
            end,
        },
    } },
}

-- Real store + real format (already tested) so capture integrates with them.
assert(loadfile("QUI_Chat/chat/message_store.lua"))("QUI", ns)
assert(loadfile("QUI_Chat/chat/message_format.lua"))("QUI", ns)
assert(loadfile("QUI_Chat/chat/message_capture.lua"))("QUI", ns)
local Capture = ns.QUI.Chat.MessageCapture
local Store = ns.QUI.Chat.MessageStore

-- Keyword-alert recording stub: capture consults it at event time (not load).
local kaCalls = 0
ns.QUI.Chat.KeywordAlert = { ProcessForCapture = function(m, author) kaCalls = kaCalls + 1; return m end }

Capture.Setup()

-- Registration: valid events from the inverted map + explicit extras; bogus skipped
assert(registered.CHAT_MSG_SAY, "registers CHAT_MSG_SAY")
assert(registered.CHAT_MSG_GUILD, "registers CHAT_MSG_GUILD")
assert(registered.CHAT_MSG_CHANNEL, "registers explicit CHAT_MSG_CHANNEL")
assert(registered.CHAT_MSG_SYSTEM, "registers explicit CHAT_MSG_SYSTEM")
assert(registered.CHAT_MSG_BN_INLINE_TOAST_ALERT, "registers explicit BN toast alerts")
assert(registered.CHAT_MSG_BN_INLINE_TOAST_BROADCAST, "registers explicit BN broadcast toasts")
assert(registered.CHAT_MSG_BN_INLINE_TOAST_BROADCAST_INFORM, "registers explicit BN broadcast inform toasts")
assert(registered.CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE, "registers explicit BN offline whispers")
assert(not registered.CHAT_MSG_BOGUS, "IsEventValid gate skips bogus event")
-- System events Blizzard's SystemEventHandler turns into chat lines are now
-- replicated by capture (suppressed frames are event-neutered and would lose
-- them entirely).
assert(registered.GUILD_MOTD, "GUILD_MOTD replicated (SystemEventHandler parity)")
assert(registered.GUILD_ROSTER_UPDATE, "GUILD_ROSTER_UPDATE registered (login MOTD pull)")
assert(registered.PLAYER_GUILD_UPDATE, "PLAYER_GUILD_UPDATE registered (login MOTD pull)")
assert(registered.TIME_PLAYED_MSG, "TIME_PLAYED_MSG replicated (/played output)")
assert(registered.PLAYER_LEVEL_CHANGED, "PLAYER_LEVEL_CHANGED replicated (level-up line)")
assert(registered.CHAT_SERVER_DISCONNECTED, "disconnect notice replicated")
assert(registered.PLAYER_REPORT_SUBMITTED, "report purge event registered")
assert(registered.CHAT_MSG_CHANNEL_NOTICE, "channel notices now captured")
assert(registered.CHAT_MSG_ACHIEVEMENT, "achievements now captured")
assert(registered.CHAT_MSG_CHANNEL_LIST, "channel list now captured")
assert(registered.CHAT_MSG_EMOTE, "player emotes now captured")
assert(registered.CHAT_MSG_TEXT_EMOTE, "text emotes now captured")
assert(registered.CHAT_MSG_MONSTER_YELL, "monster yells now captured")
assert(registered.CHAT_MSG_RAID_BOSS_EMOTE, "raid boss emotes now captured")
assert(registered.RAID_BOSS_EMOTE, "non-chat raid boss emotes now captured")
assert(registered.RAID_BOSS_WHISPER, "non-chat raid boss whispers now captured")
assert(registered.QUEST_BOSS_EMOTE, "quest boss emotes now captured")
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
assert(e1.m == "[12:00] |Hplayer:Bob:0:SAY:|h[Bob]|h: hello", "timestamped formatted line, got " .. tostring(e1.m))
assert(e1.e == "CHAT_MSG_SAY" and e1.k == "SAY" and e1.t == 1234, "metadata")
assert(e1.r == 1 and e1.g == 1 and e1.b == 1, "event color")
assert(kaCalls >= 1, "capture consults keyword highlighter")
assert(e1.gid == nil or e1.gid == false, "no guid arg -> no gid")

-- URL decoration runs at capture (settings.urls.enabled)
fire("CHAT_MSG_SAY", "see URLX now", "Bob")
local eUrl; Store.ForEach(function(e) eUrl = e end)
assert(eUrl.m:find("|Hurl:x|hURLX|h", 1, true), "URLs linkified at capture, got " .. tostring(eUrl.m))

-- Filter drop
filterImpl = function() return true end
local beforeFilter = Store.Size()
fire("CHAT_MSG_SAY", "spam", "Bob")
assert(Store.Size() == beforeFilter, "filtered message dropped")

-- Filter rewrite
filterImpl = function(frame, event, a1, ...) return false, "REWRITTEN", ... end
fire("CHAT_MSG_SAY", "original", "Bob")
local e2; Store.ForEach(function(e) e2 = e end)
assert(e2.m:find("REWRITTEN", 1, true), "filter rewrite respected")
filterImpl = nil

-- Secret body on a known formatter path: formatted, flagged
fire("CHAT_MSG_RAID_WARNING", secret, "Boss")
local e3; Store.ForEach(function(e) e3 = e end)
assert(rawequal(e3.m, formattedSecretRaidWarning), "secret formatted by identity")
assert(e3.s == true, "secret flagged")
assert(e3.k == "RAID_WARNING", "typeKey from event name only")
assert(e3.r == 1 and e3.g == 0.28 and e3.b == 0, "color from event, not payload")
assert(tsSecretCalls >= 1, "secret lines offered to AddTimestamp")
-- secret path: a12 is nil here so no gid stored
assert(e3.gid == nil, "secret path stores no gid unless probed clean")

-- Sender GUID captured for the sounds self-check
-- a12 = guid per WoW CHAT_MSG arg layout: msg(1), sender(2), lang(3), chan(4),
-- sender2(5), flags(6), zone(7), chanIdx(8), chanBase(9), unused(10), lineID(11), guid(12)
fire("CHAT_MSG_SAY", "with guid", "Bob", nil, nil, nil, nil, nil, nil, nil, nil, nil, "Player-1-ABCD")
local eGid; Store.ForEach(function(e) eGid = e end)
assert(eGid.gid == "Player-1-ABCD", "gid stored, got " .. tostring(eGid.gid))

-- disabled-chat gate
settings.enabled = false
fire("CHAT_MSG_SAY", "ignored", "Bob")
assert(Store.Size() == 5, "no capture when chat disabled")
settings.enabled = true

-- Channel messages pull per-channel color (ChatTypeInfo.CHANNEL<n>)
fire("CHAT_MSG_CHANNEL", "wts gem", "Ann", nil, "2. Trade", nil, nil, nil, 2, "Trade")
local e3b; Store.ForEach(function(e) e3b = e end)
assert(e3b.m == "[12:00] |Hchannel:channel:2|h[T]|h |Hplayer:Ann:0:CHANNEL:2|h[Ann]|h: wts gem",
    "channel line, got " .. tostring(e3b.m))
assert(e3b.r == 1 and e3b.g == 0.75 and e3b.b == 0.75, "per-channel color from CHANNEL2")
assert(e3b.k == "CHANNEL" and e3b.ch == "Trade", "channel metadata")

-- Secret channel number: the "CHANNEL"..n concat is guarded (sentinel traps __concat)
fire("CHAT_MSG_CHANNEL", "x", "Ann", nil, nil, nil, nil, nil, secret, "Trade")
local e3c; Store.ForEach(function(e) e3c = e end)
assert(e3c.m == "[12:00] [Trade] |Hplayer:Ann:0:CHANNEL:|h[Ann]|h: x", "secret chan num degrades, got " .. tostring(e3c.m))

-- Secret channel body: formatted, channelBaseName is retained for tab routing.
fire("CHAT_MSG_CHANNEL", secret, "Ann", nil, "2. Trade", nil, nil, nil, 2, "Trade")
local e3cs; Store.ForEach(function(e) e3cs = e end)
assert(rawequal(e3cs.m, formattedSecretChannel), "secret channel body formatted by identity")
assert(e3cs.s == true and e3cs.k == "CHANNEL" and e3cs.ch == "Trade",
    "secret channel metadata retained for filters")

-- Secret sender degrades to bare text via event path
fire("CHAT_MSG_SAY", "no sender", secret)
local e3d; Store.ForEach(function(e) e3d = e end)
assert(e3d.m == "[12:00] no sender", "secret sender dropped, got " .. tostring(e3d.m))

-- Achievement renders via the special path
fire("CHAT_MSG_ACHIEVEMENT", "%s did it!", "Ann")
local eAch; Store.ForEach(function(e) eAch = e end)
assert(eAch.m:find("|Hplayer:Ann|h[Ann]|h did it!", 1, true), "achievement formatted, got " .. tostring(eAch.m))

-- Channel notice renders via globalstring; arg4=full name, arg8=number
fire("CHAT_MSG_CHANNEL_NOTICE", "YOU_CHANGED", nil, nil, "2. Trade", nil, nil, nil, 2, "Trade")
local eNote; Store.ForEach(function(e) eNote = e end)
assert(eNote.m == "[12:00] Changed Channel: |Hchannel:2|h[2. Trade]|h", "notice formatted+timestamped, got " .. tostring(eNote.m))

-- Unknown notice token: DROPPED (no raw token lines)
local beforeDrop = Store.Size()
fire("CHAT_MSG_CHANNEL_NOTICE", "NO_SUCH_TOKEN", nil, nil, "2. Trade", nil, nil, nil, 2, "Trade")
assert(Store.Size() == beforeDrop, "unrenderable token dropped")

-- BN friend offline toasts carry a token payload; capture must render a
-- localized line, never store the raw "FRIEND_OFFLINE" token.
fire("CHAT_MSG_BN_INLINE_TOAST_ALERT", "FRIEND_OFFLINE", "Bea", nil, nil, nil, nil, nil, nil, nil, nil, 31337, nil, 88)
local eToast; Store.ForEach(function(e) eToast = e end)
assert(eToast.m == "[12:00] |HBNplayer:Bea:88:31337:BN_INLINE_TOAST_ALERT:0|h[Bea]|h has gone offline.",
    "offline toast formatted, got " .. tostring(eToast.m))

-- BN broadcast toasts use a global template with a BN player link and
-- normalized body text.
fire("CHAT_MSG_BN_INLINE_TOAST_BROADCAST", "Raid\nnight   now", "Aria", nil, nil, nil, nil, nil, nil, nil, nil, 4242, nil, 77)
local eBroadcast; Store.ForEach(function(e) eBroadcast = e end)
assert(eBroadcast.m == "[12:00] |HBNplayer:Aria:77:4242:BN_INLINE_TOAST_ALERT:0|h[Aria]|h broadcast: Raid night now",
    "broadcast toast formatted, got " .. tostring(eBroadcast.m))

fire("CHAT_MSG_BN_INLINE_TOAST_BROADCAST_INFORM", "Raid night now", "Aria")
local eBroadcastInform; Store.ForEach(function(e) eBroadcastInform = e end)
assert(eBroadcastInform.m == "[12:00] Broadcast sent.",
    "broadcast inform formatted, got " .. tostring(eBroadcastInform.m))

fire("CHAT_MSG_IGNORED", "IGNORED", "Noisy")
local eIgnored; Store.ForEach(function(e) eIgnored = e end)
assert(eIgnored.m == "[12:00] Noisy is ignoring you.",
    "ignored formatted, got " .. tostring(eIgnored.m))

fire("CHAT_MSG_FILTERED", "FILTERED", "Noisy")
local eFiltered; Store.ForEach(function(e) eFiltered = e end)
assert(eFiltered.m == "[12:00] Message to Noisy was filtered.",
    "filtered formatted, got " .. tostring(eFiltered.m))

fire("CHAT_MSG_RESTRICTED", "RESTRICTED", nil)
local eRestricted; Store.ForEach(function(e) eRestricted = e end)
assert(eRestricted.m == "[12:00] Trial accounts cannot use that.",
    "restricted formatted, got " .. tostring(eRestricted.m))

fire("CHAT_MSG_EMOTE", "waves.", "Ann")
local eEmote; Store.ForEach(function(e) eEmote = e end)
assert(eEmote.m == "[12:00] |Hplayer:Ann:0:EMOTE:|hAnn|h waves.",
    "player emote formatted, got " .. tostring(eEmote.m))

fire("CHAT_MSG_TEXT_EMOTE", "Ann waves.", "Ann")
local eTextEmote; Store.ForEach(function(e) eTextEmote = e end)
assert(eTextEmote.m == "[12:00] |Hplayer:Ann:0:TEXT_EMOTE:|hAnn|h waves.",
    "text emote formatted, got " .. tostring(eTextEmote.m))

fire("CHAT_MSG_MONSTER_YELL", "Run away!", "Dungeon Boss")
local eMonsterYell; Store.ForEach(function(e) eMonsterYell = e end)
assert(eMonsterYell.m == "[12:00] Dungeon Boss yells: Run away!",
    "monster yell keeps sender prefix, got " .. tostring(eMonsterYell.m))
assert(eMonsterYell.k == "MONSTER_YELL" and eMonsterYell.r == 1 and eMonsterYell.g == 0.25 and eMonsterYell.b == 0.25,
    "monster yell metadata/color")

fire("CHAT_MSG_RAID_BOSS_EMOTE", "casts Doom.", "Big Boss")
local eBossEmote; Store.ForEach(function(e) eBossEmote = e end)
assert(eBossEmote.m == "[12:00] |TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|tBig Boss casts Doom.",
    "boss emote keeps sender prefix, got " .. tostring(eBossEmote.m))
assert(eBossEmote.k == "RAID_BOSS_EMOTE" and eBossEmote.r == 1 and eBossEmote.g == 0.82 and eBossEmote.b == 0,
    "boss emote metadata/color")

fire("CHAT_MSG_MONSTER_YELL", secret, "Dungeon Boss")
local eSecretMonster; Store.ForEach(function(e) eSecretMonster = e end)
assert(rawequal(eSecretMonster.m, formattedSecretMonster),
    "secret monster body formatted with readable sender prefix")
assert(eSecretMonster.s == true and eSecretMonster.k == "MONSTER_YELL",
    "secret monster metadata")

fire("CHAT_MSG_SAY", secret, "Ann")
local eSecretSay; Store.ForEach(function(e) eSecretSay = e end)
assert(rawequal(eSecretSay.m, formattedSecretBarePlayer),
    "secret say body formatted with readable sender prefix")

fire("CHAT_MSG_YELL", secret, "Ann")
local eSecretYell; Store.ForEach(function(e) eSecretYell = e end)
assert(rawequal(eSecretYell.m, formattedSecretYell),
    "secret yell body formatted with readable sender prefix")

fire("CHAT_MSG_GUILD", secret, "Ann")
local eSecretGuild; Store.ForEach(function(e) eSecretGuild = e end)
assert(rawequal(eSecretGuild.m, formattedSecretGuild),
    "secret guild body formatted with readable sender prefix")

fire("CHAT_MSG_PARTY", secret, "Ann")
local eSecretParty; Store.ForEach(function(e) eSecretParty = e end)
assert(rawequal(eSecretParty.m, formattedSecretParty),
    "secret party body formatted with readable sender prefix")
assert(eSecretParty.s == true and eSecretParty.k == "PARTY",
    "secret party metadata")

fire("CHAT_MSG_PARTY", secret, secretSender)
local eSecretPartyAndSender; Store.ForEach(function(e) eSecretPartyAndSender = e end)
assert(rawequal(eSecretPartyAndSender.m, formattedSecretPartyAndSender),
    "secret party body formatted with secret sender prefix")
assert(eSecretPartyAndSender.s == true and eSecretPartyAndSender.k == "PARTY",
    "secret party+sender metadata")

fire("CHAT_MSG_WHISPER", secret, "Ann")
local eSecretWhisper; Store.ForEach(function(e) eSecretWhisper = e end)
assert(rawequal(eSecretWhisper.m, formattedSecretWhisper),
    "secret whisper body formatted with readable sender prefix")

fire("CHAT_MSG_BN_WHISPER", secret, "Aria", nil, nil, nil, nil, nil, nil, nil, nil, 31337, nil, 77)
local eSecretBNWhisper; Store.ForEach(function(e) eSecretBNWhisper = e end)
assert(rawequal(eSecretBNWhisper.m, formattedSecretBNWhisper),
    "secret BN whisper body formatted with readable sender prefix")

-- Conversation tagging: whisper-family entries carry w (conversation key)
-- + wn (raw counterparty); both directions key to the counterparty.
Store.Clear()
fire("CHAT_MSG_WHISPER", "hi there", "Sender-Realm")
local eTagIn; Store.ForEach(function(e) eTagIn = e end)
assert(eTagIn.w == "W:sender-realm", "incoming whisper tagged with conversation key, got " .. tostring(eTagIn.w))
assert(eTagIn.wn == "Sender-Realm", "raw counterparty name preserved, got " .. tostring(eTagIn.wn))

fire("CHAT_MSG_WHISPER_INFORM", "re: hi", "Target-Realm")
local eTagOut; Store.ForEach(function(e) eTagOut = e end)
assert(eTagOut.w == "W:target-realm", "outgoing whisper keys to the TARGET, got " .. tostring(eTagOut.w))

fire("CHAT_MSG_BN_WHISPER", "bn hi", "Aria", nil, nil, nil, nil, nil, nil, nil, nil, 31337, nil, 77)
local eTagBN; Store.ForEach(function(e) eTagBN = e end)
assert(eTagBN.w == "BN:aria", "bn whisper tagged, got " .. tostring(eTagBN.w))

fire("CHAT_MSG_SAY", "hello", "Talker-Realm")
local eTagSay; Store.ForEach(function(e) eTagSay = e end)
assert(eTagSay.w == nil and eTagSay.wn == nil, "non-whisper events never tagged")

-- Secret BODY does not block tagging (key derives from non-secret a2);
-- the existing secret whisper assert above already renders via the
-- formatter — re-fire and check tagging fields on the stored entry.
fire("CHAT_MSG_WHISPER", secret, "Ann")
local eTagSecretBody; Store.ForEach(function(e) eTagSecretBody = e end)
assert(eTagSecretBody.s == true and eTagSecretBody.w == "W:ann",
    "secret body still tagged via non-secret sender, got w=" .. tostring(eTagSecretBody.w))
assert(eTagSecretBody.wn == "Ann", "secret body keeps counterparty name, got " .. tostring(eTagSecretBody.wn))

-- Secret IDENTITY blocks tagging (entry untagged, falls to type filters)
fire("CHAT_MSG_WHISPER", secret, secretSender)
local eTagSecretId; Store.ForEach(function(e) eTagSecretId = e end)
assert(eTagSecretId.s == true and eTagSecretId.w == nil and eTagSecretId.wn == nil,
    "secret identity -> untagged")
Store.Clear()

fire("CHAT_MSG_CHANNEL", secret, "Ann", nil, "2. Trade", nil, nil, nil, 2, "Trade")
local eSecretChannel; Store.ForEach(function(e) eSecretChannel = e end)
assert(rawequal(eSecretChannel.m, formattedSecretChannel),
    "secret channel body formatted with readable sender prefix")

fire("CHAT_MSG_COMMUNITIES_CHANNEL", secret, "Ann")
local eSecretCommunity; Store.ForEach(function(e) eSecretCommunity = e end)
assert(rawequal(eSecretCommunity.m, formattedSecretCommunity),
    "secret community body formatted with readable sender prefix")

fire("RAID_BOSS_EMOTE", "%s casts Doom.", "Big Boss")
local eRaidNotice; Store.ForEach(function(e) eRaidNotice = e end)
assert(eRaidNotice.m == "[12:00] Big Boss casts Doom.",
    "raid boss notice formatted, got " .. tostring(eRaidNotice.m))
assert(eRaidNotice.e == "RAID_BOSS_EMOTE" and eRaidNotice.k == "RAID_BOSS_EMOTE",
    "raid boss notice metadata")

-- Fallback hook: plain addon print captured as SYSTEM-ish line
stack = "some/Addon/file.lua:10"
hooked.AddMessage(_G.ChatFrame1, "addon says hi", 1, 1, 1)
local e4; Store.ForEach(function(e) e4 = e end)
assert(e4.m == "[12:00] addon says hi", "fallback captured + timestamped AddMessage")
assert(e4.k == "SYSTEM", "fallback entry routed as SYSTEM")

-- Fallback hook: event-dispatch traffic skipped (already captured via events)
local before = Store.Size()
stack = "[string \"@Interface/AddOns/Blizzard_ChatFrameBase/Mainline/ChatFrameOverrides.lua\"]: in function 'MessageEventHandler'"
hooked.AddMessage(_G.ChatFrame1, "event-driven", 1, 1, 1)
assert(Store.Size() == before, "event-driven AddMessage skipped (MessageEventHandler marker)")

-- Fallback hook: own HISTORY repump traffic skipped
stack = "Interface/AddOns/QUI/chat/history.lua:120"
hooked.AddMessage(_G.ChatFrame1, "repumped", 1, 1, 1)
assert(Store.Size() == before, "history repump AddMessage skipped")

-- Other own-addon prints DO flow (only the history repump is skipped)
stack = "Interface/AddOns/QUI/chat/hyperlinks.lua:125"
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
assert(e5.m == "[12:00] rgb secret" and e5.r == 1 and e5.g == 1 and e5.b == 1, "secret rgb degraded to white")
before = Store.Size()

-- ChannelColors rewire: user override for "Trade" must reach the store entry -----
-- Seed an override for the "Trade" channel name.
channelColorDB["Trade"] = { 0.9, 0.8, 0.7 }
Store.Clear()
fire("CHAT_MSG_CHANNEL", "wts gem override", "Ann", nil, "2. Trade", nil, nil, nil, 2, "Trade")
local eCC; Store.ForEach(function(e) eCC = e end)
assert(eCC, "channel override: entry captured")
assert(eCC.r == 0.9 and eCC.g == 0.8 and eCC.b == 0.7,
    "channel override reaches store r/g/b, got " .. tostring(eCC.r) .. "/" .. tostring(eCC.g) .. "/" .. tostring(eCC.b))
channelColorDB["Trade"] = nil  -- clear

-- Builtin override: SAY override must reach the store entry
channelColorDB["SAY"] = { 0.1, 0.2, 0.3 }
Store.Clear()
fire("CHAT_MSG_SAY", "hello override", "Bob")
local eSAY; Store.ForEach(function(e) eSAY = e end)
assert(eSAY and eSAY.r == 0.1 and eSAY.g == 0.2 and eSAY.b == 0.3,
    "SAY override reaches store r/g/b, got " .. tostring(eSAY and eSAY.r))
channelColorDB["SAY"] = nil

-- SystemEventHandler replication: /played output (two SYSTEM lines)
_G.TIME_PLAYED_TOTAL = "Total time played: %s"
_G.TIME_PLAYED_LEVEL = "Time played this level: %s"
_G.TIME_DAYHOURMINUTESECOND = "%d days, %d hours, %d minutes, %d seconds"
Store.Clear()
fire("TIME_PLAYED_MSG", 90061, 61) -- 1d 1h 1m 1s / 1m 1s
local played = {}
Store.ForEach(function(e) played[#played + 1] = e end)
assert(#played == 2, "played emits two lines, got " .. #played)
assert(played[1].m == "[12:00] Total time played: 1 days, 1 hours, 1 minutes, 1 seconds",
    "played total, got " .. tostring(played[1].m))
assert(played[2].m == "[12:00] Time played this level: 0 days, 0 hours, 1 minutes, 1 seconds",
    "played level, got " .. tostring(played[2].m))
assert(played[1].k == "SYSTEM" and played[1].e == "TIME_PLAYED_MSG", "played metadata")

-- GMOTD: GUILD-typed, deduped per session
_G.GUILD_MOTD_TEMPLATE = "Guild MOTD: %s"
Store.Clear()
fire("GUILD_MOTD", "Raid tonight")
fire("GUILD_MOTD", "Raid tonight")
assert(Store.Size() == 1, "GMOTD deduped, got " .. Store.Size())
local motd; Store.ForEach(function(e) motd = e end)
assert(motd.m == "[12:00] Guild MOTD: Raid tonight", "gmotd line, got " .. tostring(motd.m))
assert(motd.k == "GUILD" and motd.e == "GUILD_MOTD", "gmotd metadata")

-- GMOTD login pull: at login the MOTD often lands before the capture frame
-- catches the GUILD_MOTD event (Blizzard's own chat frame hits the same race),
-- so capture also pulls C_GuildInfo.GetMOTD() on guild-data events. seenMotd is
-- shared with the event path, so the pull and the event never double-post.
_G.IsInGuild = function() return true end
_G.C_GuildInfo = { GetMOTD = function() return "Welcome home" end }
Store.Clear()
fire("GUILD_ROSTER_UPDATE")
assert(Store.Size() == 1, "GMOTD pulled on roster update, got " .. Store.Size())
local pulled; Store.ForEach(function(e) pulled = e end)
assert(pulled.m == "[12:00] Guild MOTD: Welcome home", "pulled gmotd line, got " .. tostring(pulled.m))
assert(pulled.k == "GUILD" and pulled.e == "GUILD_MOTD", "pulled gmotd metadata (event-named, not trigger)")
-- Repeat guild-data events + the real event are deduped against the pull.
fire("GUILD_ROSTER_UPDATE")
fire("PLAYER_GUILD_UPDATE")
fire("GUILD_MOTD", "Welcome home")
assert(Store.Size() == 1, "pull/event share seenMotd dedupe, got " .. Store.Size())
-- Not in a guild: no pull, no crash.
_G.IsInGuild = function() return false end
Store.Clear()
fire("GUILD_ROSTER_UPDATE")
assert(Store.Size() == 0, "no MOTD pull when not in a guild, got " .. Store.Size())
-- PLAYER_ENTERING_WORLD also pulls (the /reload path, guild data already cached).
_G.IsInGuild = function() return true end
_G.C_GuildInfo = { GetMOTD = function() return "Reloaded greeting" end }
Store.Clear()
fire("PLAYER_ENTERING_WORLD")
assert(Store.Size() == 1, "GMOTD pulled on PLAYER_ENTERING_WORLD, got " .. Store.Size())
local reloaded; Store.ForEach(function(e) reloaded = e end)
assert(reloaded.m == "[12:00] Guild MOTD: Reloaded greeting", "PEW gmotd line, got " .. tostring(reloaded.m))

-- PLAYER_REPORT_SUBMITTED purges the reported sender's stored lines
Store.Clear()
fire("CHAT_MSG_SAY", "spammy", "Bob", nil, nil, nil, nil, nil, nil, nil, nil, nil, "Player-1-SPAM")
fire("CHAT_MSG_SAY", "fine", "Ann", nil, nil, nil, nil, nil, nil, nil, nil, nil, "Player-2-OK")
assert(Store.Size() == 2, "two lines pre-report")
fire("PLAYER_REPORT_SUBMITTED", "Player-1-SPAM")
assert(Store.Size() == 1, "reported sender's lines purged, got " .. Store.Size())
local survivor; Store.ForEach(function(e) survivor = e end)
assert(survivor.gid == "Player-2-OK", "unreported sender survives")

-- Teardown unregisters everything
Capture.Teardown()
assert(unregisteredAll, "teardown unregisters events")

-- Backfill: replays the default frame's scrollback, secret lines opaque
Store.Clear()
local added = Capture.BackfillFromDefaultFrame()
assert(added == 3, "backfilled 3 lines, got " .. tostring(added))
local bf = {}
Store.ForEach(function(e) bf[#bf + 1] = e end)
assert(bf[1].m == "old line one" and bf[1].k == "SYSTEM" and bf[1].e == "BACKFILL", "backfill entry shape")
assert(bf[2].r == 0.5, "backfill color preserved")
assert(rawequal(bf[3].m, secret) and bf[3].s == true, "secret backfill line stored opaquely")

print("OK: chat_message_capture_test")
