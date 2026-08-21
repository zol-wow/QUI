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

_G.RAID_CLASS_COLORS = {
    MAGE = { colorStr = "ff3fc7eb" },
    DEMONHUNTER = { colorStr = "ffa330c9" },
}
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
_G.CHAT_PING_GET = "%s: "
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
    -- core/safecall.lua stub: silent pcall swallow matches the pre-SafeCall
    -- behavior these tests were written against (Task 45b ns-mock precedent).
    SafeCall = function(_policy, fn, ...) return pcall(fn, ...) end,
    SafeCallMethod = function(_policy, obj, name, ...) return pcall(function(...) return obj[name](obj, ...) end, ...) end,
    SafeCallMethodIfPresent = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end,
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
do
    local saved = settings.modifiers.classColors
    settings.modifiers.classColors = nil
    eq("decorate class color default-on",
        F.DecorateSender("CHAT_MSG_SAY", "hi", "Default-Realm", nil, nil, nil, nil, nil, nil, nil, nil, nil, "Player-1-MAGE"),
        "|cff3fc7ebDefault|r")
    settings.modifiers.classColors = saved
end
-- Truly-unknown player (never resolved, so absent from the name cache) stays
-- plain. Uses a fresh name -- "Bob-Realm" was seeded MAGE just above, and the
-- name cache now (correctly) recolors any later line from a known name.
eq("decorate guid unknown",
    F.DecorateSender("CHAT_MSG_SAY", "hi", "Ghost-Realm", nil, nil, nil, nil, nil, nil, nil, nil, nil, "Player-9-NONE"),
    "Ghost")
eq("decorate secret sender", F.DecorateSender("CHAT_MSG_SAY", "hi", secret), nil)
-- Secret GUID (combat / chat-messaging lockdown): the class still resolves and
-- colors the name. GetPlayerInfoByGUID is SecretArguments="AllowedWhenTainted",
-- so the secret GUID passes straight through to the class lookup (stock
-- raid-chat parity) -- the old IsSecret(guid) gate dropped class colors mid
-- combat. The class return is a plain string, so the markup builds normally.
do
    local secretGuid = setmetatable({}, { __tostring = explode, __concat = explode, __len = explode })
    secrets[secretGuid] = true
    local prevGPI = _G.GetPlayerInfoByGUID
    _G.GetPlayerInfoByGUID = function(gg)
        if rawequal(gg, secretGuid) then return "Mage", "MAGE" end
        return prevGPI(gg)
    end
    -- guid at a12: "hi"(a1), "Bob-Realm"(a2), a3..a11 = 9 nils, secretGuid(a12)
    eq("decorate class color secret guid",
        F.DecorateSender("CHAT_MSG_SAY", "hi", "Bob-Realm", nil, nil, nil, nil, nil, nil, nil, nil, nil, secretGuid),
        "|cff3fc7ebBob|r")
    _G.GetPlayerInfoByGUID = prevGPI
    secrets[secretGuid] = nil
end

-- Secret CLASS routing (the real in-game combat case the plain-string stubs
-- above cannot reach: a Lua harness cannot mint a real engine secret). Under
-- lockdown GetPlayerInfoByGUID returns a SECRET englishClass for a secret GUID.
-- A secret cannot be a table key, so the colorizer must NOT index
-- RAID_CLASS_COLORS[class] -- it routes the secret class through
-- C_ClassColor.GetClassColor + ColorMixin:WrapTextInColorCode (both
-- AllowedWhenTainted). This proves the name is still colored without ever keying
-- a table on the secret class -- the divergence from stock that dropped raid/
-- party colors when QUI rejected the secret class instead of forwarding it.
do
    local secretGuid = setmetatable({}, { __tostring = explode, __concat = explode, __len = explode })
    local secretClass = setmetatable({}, { __tostring = explode, __concat = explode, __len = explode })
    secrets[secretGuid] = true
    secrets[secretClass] = true
    local prevGPI = _G.GetPlayerInfoByGUID
    local prevCC = _G.C_ClassColor
    _G.GetPlayerInfoByGUID = function(gg)
        if rawequal(gg, secretGuid) then return secretClass, secretClass end
        return prevGPI(gg)
    end
    local sawClass
    _G.C_ClassColor = {
        GetClassColor = function(cls)
            sawClass = cls
            return { WrapTextInColorCode = function(_, t) return "CC:" .. t end }
        end,
    }
    eq("decorate secret class routes via C_ClassColor",
        F.DecorateSender("CHAT_MSG_PARTY", "hi", "Zed-Realm", nil, nil, nil, nil, nil, nil, nil, nil, nil, secretGuid),
        "CC:Zed")
    eq("secret class forwarded to C_ClassColor", rawequal(sawClass, secretClass), true)
    _G.GetPlayerInfoByGUID = prevGPI
    _G.C_ClassColor = prevCC
    secrets[secretGuid] = nil
    secrets[secretClass] = nil
end

do
    local src = assert(io.open("QUI_Chat/chat/message_format.lua", "r")):read("*a")
    assert(not src:find("wrapped%s*~=%s*nil"),
        "secret-safe class color wrapping must use truthiness, not ~= nil")
end

do
    local prevFilter = _G.ChatFrameUtil.ProcessSenderNameFilters
    local seenCount
    local seenArg15
    _G.ChatFrameUtil.ProcessSenderNameFilters = function(_, decorated, ...)
        seenCount = select("#", ...)
        seenArg15 = select(15, ...)
        return decorated
    end
    local p = F.BuildPayloadFromArgs("CHAT_MSG_SAY",
        "hi", "Bob-Realm", nil, nil, nil, nil, nil, nil, nil, nil, 42,
        "Player-1-MAGE", nil, nil, nil, nil, true)
    -- Wave 3 Task 2: BuildPayloadFromArgs now forwards discordInfo (a18) to
    -- DecorateSender as its 15th vararg slot, exactly like Blizzard's own
    -- GetDecoratedSenderName(event, arg1..arg14, discordInfo) call
    -- (ChatFrameOverrides.lua:310) — so ProcessSenderNameFilters always sees
    -- 15 args now (a1..a14 + discordInfo), never 14. suppressRaidIcons (a17)
    -- still never leaks in (it isn't part of DecorateSender's vararg at all).
    eq("sender filter receives Blizzard arg count (+discordInfo slot)", seenCount, 15)
    eq("sender filter's 15th slot is discordInfo (nil: no Discord traffic here)", seenArg15, nil)
    eq("payload keeps arg17 suppressIcons", p.suppressIcons, true)
    _G.ChatFrameUtil.ProcessSenderNameFilters = prevFilter
end

-- Parity: stock ChatFrameUtil.GetDecoratedSenderName resolves the color via
-- C_ClassColor.GetClassColor FIRST for NON-secret classes too (RAID_CLASS_COLORS
-- is only the no-C_ClassColor fallback). Proves QUI matches that order so a class
-- C_ClassColor knows but RAID_CLASS_COLORS lacks (login burst) still colors.
do
    local prevCC = _G.C_ClassColor
    local sawClass
    _G.C_ClassColor = {
        GetClassColor = function(cls)
            sawClass = cls
            return { WrapTextInColorCode = function(_, t) return "CC:" .. t end }
        end,
    }
    eq("non-secret class uses C_ClassColor first",
        F.DecorateSender("CHAT_MSG_SAY", "hi", "Bob-Realm", nil, nil, nil, nil, nil, nil, nil, nil, nil, "Player-1-MAGE"),
        "CC:Bob")
    eq("non-secret class forwarded to C_ClassColor", sawClass, "MAGE")
    _G.C_ClassColor = prevCC
end

-- Combat name-cache recovery (the party/raid/guild fix). In live combat the
-- engine returns NOTHING for a secret GUID (GetPlayerInfoByGUID is
-- MayReturnNothing under chat-messaging lockdown), so the secret-GUID
-- passthrough ALONE goes plain -- which is exactly the reported bug. A sender
-- resolved earlier while non-secret seeds a name->class cache; when the same
-- name speaks during combat, the class is recovered by name even though the
-- GUID won't resolve. The default stub returns nothing for an unknown GUID, so
-- the secret sentinel here naturally resolves to nothing (no GPI override).
do
    local secretGuid = setmetatable({}, { __tostring = explode, __concat = explode, __len = explode })
    secrets[secretGuid] = true
    -- 1) Seed: non-secret GUID resolves MAGE for sender "Cara-Realm".
    eq("namecache seed colors",
        F.DecorateSender("CHAT_MSG_PARTY", "hi", "Cara-Realm", nil, nil, nil, nil, nil, nil, nil, nil, nil, "Player-1-MAGE"),
        "|cff3fc7ebCara|r")
    -- 2) Combat: secret GUID resolves to NOTHING; name cache recovers the class.
    eq("namecache combat recover",
        F.DecorateSender("CHAT_MSG_PARTY", "hi", "Cara-Realm", nil, nil, nil, nil, nil, nil, nil, nil, nil, secretGuid),
        "|cff3fc7ebCara|r")
    -- 3) A never-seen sender stays plain -- no false recovery from the cache.
    eq("namecache unknown stays plain",
        F.DecorateSender("CHAT_MSG_PARTY", "hi", "Newbie-Realm", nil, nil, nil, nil, nil, nil, nil, nil, nil, secretGuid),
        "Newbie")
    secrets[secretGuid] = nil
end

-- Proactive roster seeding (the cold-login-into-combat fix). Lazy seeding above
-- needs a sender to have spoken while non-secret FIRST; a player who logs in
-- straight into a Mythic+ pull and types in /party has NO such prior line, so
-- the GUID is already secret and the name cache is empty -> plain name. Seeding
-- from UnitClass (classFilename is non-secret even in combat) at login/roster
-- change warms the cache so the very first combat line is class-colored, with
-- NO GetPlayerInfoByGUID resolve. Covers the reported case: the player's OWN
-- Demon Hunter name in party chat, plus cross-realm groupmates.
do
    local roster = {
        player = { loc = "Demon Hunter", class = "DEMONHUNTER", full = "Drew",             short = "Drew" },
        party1 = { loc = "Mage",         class = "MAGE",        full = "Zin-OtherRealm",   short = "Zin"  },
        party2 = { loc = "Mage",         class = "MAGE",        full = "Kara-Other Realm", short = "Kara", guid = "Player-2-MAGE" },
    }
    local prev = {
        IsInGroup = _G.IsInGroup, IsInRaid = _G.IsInRaid, UnitExists = _G.UnitExists,
        UnitIsPlayer = _G.UnitIsPlayer, UnitClass = _G.UnitClass, GetUnitName = _G.GetUnitName,
        UnitName = _G.UnitName, UnitGUID = _G.UnitGUID,
    }
    _G.UnitName = nil
    _G.IsInGroup = function() return true end
    _G.IsInRaid = function() return false end
    _G.UnitExists = function(u) return roster[u] ~= nil end
    _G.UnitIsPlayer = function() return true end
    _G.UnitClass = function(u)
        local e = roster[u]; if e then return e.loc, e.class end
    end
    _G.GetUnitName = function(u, server)
        local e = roster[u]; if not e then return nil end
        return server and e.full or e.short
    end
    _G.UnitGUID = function(u)
        local e = roster[u]; return e and e.guid or nil
    end

    F.SeedKnownClasses()

    local secretGuid = setmetatable({}, { __tostring = explode, __concat = explode, __len = explode })
    secrets[secretGuid] = true
    -- Player's OWN party line, in combat (secret GUID), never chatted before:
    -- recovered purely from the login seed of UnitClass("player").
    eq("seed player own combat color",
        F.DecorateSender("CHAT_MSG_PARTY", "hi", "Drew", nil, nil, nil, nil, nil, nil, nil, nil, nil, secretGuid),
        "|cffa330c9Drew|r")
    -- Cross-realm groupmate (arg2 keeps "-Realm"), secret GUID: recovered from
    -- the realm-qualified roster seed, again with no GUID resolve.
    eq("seed roster cross-realm color",
        F.DecorateSender("CHAT_MSG_PARTY", "hi", "Zin-OtherRealm", nil, nil, nil, nil, nil, nil, nil, nil, nil, secretGuid),
        "|cff3fc7ebZin|r")
    -- Some APIs expose spaced realm names while chat args use compact realm
    -- names. Store both aliases so the cold-combat fallback hits either form.
    eq("seed roster compact realm alias color",
        F.DecorateSender("CHAT_MSG_PARTY", "hi", "Kara-OtherRealm", nil, nil, nil, nil, nil, nil, nil, nil, nil, secretGuid),
        "|cff3fc7ebKara|r")
    -- UnitGUID is readable outside identity restriction; cache it too so a cold
    -- player-info lookup still colors a non-secret sender GUID.
    eq("seed roster guid cache color",
        F.DecorateSender("CHAT_MSG_PARTY", "hi", "Cold-Realm", nil, nil, nil, nil, nil, nil, nil, nil, nil, "Player-2-MAGE"),
        "|cff3fc7ebCold|r")
    secrets[secretGuid] = nil

    for k, v in pairs(prev) do _G[k] = v end
    _G.UnitName = prev.UnitName
    _G.UnitGUID = prev.UnitGUID
end

do
    local prev = {
        IsInGroup = _G.IsInGroup, IsInRaid = _G.IsInRaid, UnitExists = _G.UnitExists,
        UnitIsPlayer = _G.UnitIsPlayer, UnitClass = _G.UnitClass, GetUnitName = _G.GetUnitName,
        UnitName = _G.UnitName, UnitGUID = _G.UnitGUID,
    }
    _G.IsInGroup = function() return false end
    _G.IsInRaid = function() return false end
    _G.UnitExists = function(u) return u == "player" end
    _G.UnitIsPlayer = function() return true end
    _G.UnitClass = function() return "Mage", "MAGE" end
    _G.UnitGUID = function() return nil end
    _G.UnitName = nil
    _G.GetUnitName = function() error("secret unit name read", 2) end

    local ok = pcall(F.SeedKnownClasses, false)
    assert(ok, "SeedKnownClasses must survive restricted roster names")

    for k, v in pairs(prev) do _G[k] = v end
    _G.UnitName = prev.UnitName
    _G.UnitGUID = prev.UnitGUID
end

-- Guild member seeding (cold-login-into-combat guild fix). Guild senders are not
-- always group units, so the group roster seed above cannot warm their
-- name->class entries. Blizzard Communities resolves guild roster class display
-- from C_Club member classID -> C_CreatureInfo classFile; QUI uses the same
-- plain class token to warm the sender-name cache before chat lockdown.
do
    local prev = {
        C_ChatInfo = _G.C_ChatInfo, C_Club = _G.C_Club, C_CreatureInfo = _G.C_CreatureInfo,
        IsInGroup = _G.IsInGroup, IsInRaid = _G.IsInRaid, UnitExists = _G.UnitExists,
        UnitIsPlayer = _G.UnitIsPlayer, UnitClass = _G.UnitClass, GetUnitName = _G.GetUnitName,
    }
    _G.C_ChatInfo = { InChatMessagingLockdown = function() return false end }
    _G.C_Club = {
        GetGuildClubId = function() return 55 end,
        GetClubMembers = function(clubId)
            assert(clubId == 55, "guild seed used wrong club id")
            return { 77 }
        end,
        GetMemberInfo = function(clubId, memberId)
            assert(clubId == 55 and memberId == 77, "guild seed used wrong member")
            return { name = "Guildie-OtherRealm", classID = 8 }
        end,
    }
    _G.C_CreatureInfo = {
        GetClassInfo = function(classID)
            assert(classID == 8, "guild seed used wrong class id")
            return { classFile = "MAGE" }
        end,
    }
    _G.UnitExists = function() return false end
    _G.IsInGroup = function() return false end
    _G.IsInRaid = function() return false end

    F.SeedKnownClasses()

    local secretGuid = setmetatable({}, { __tostring = explode, __concat = explode, __len = explode })
    secrets[secretGuid] = true
    eq("seed guild combat color",
        F.DecorateSender("CHAT_MSG_GUILD", "hi", "Guildie-OtherRealm", nil, nil, nil, nil, nil, nil, nil, nil, nil, secretGuid),
        "|cff3fc7ebGuildie|r")
    secrets[secretGuid] = nil

    for k, v in pairs(prev) do _G[k] = v end
end

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

eq("ping includes sender", F.BuildEventLine("CHAT_MSG_PING", { text = "Attack", rawSender = "Ann" }),
    "Ann: Attack")

local formatSourceFile = assert(io.open("QUI_Chat/chat/message_format.lua", "r"))
local formatSource = formatSourceFile:read("*a")
formatSourceFile:close()
assert(formatSource:find("if not IsSecret(sender) and (type(sender) ~= \"string\" or sender == \"\") then", 1, true),
    "PING sender must probe secret values before comparing them")
assert(formatSource:find("if type(prefix) == \"nil\" then return nil end", 1, true),
    "PING prefix must use a nil check before passing secret output onward")

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

-- In-game the BN sender is a |K kstring; kstring escapes are CASE-SENSITIVE,
-- so the chatTarget must pass through un-uppercased (FCFManager_GetChatTarget
-- parity) — |KJ27|K is an invalid escape that breaks the whole link parse.
eq("bn kstring target", F.BuildEventLine("CHAT_MSG_BN_WHISPER_INFORM",
        { text = "yo", sender = "|Kj27|k", bnID = 77, lineID = 4242 }),
    "[W:To] |HBNplayer:|Kj27|k:77:4242:BN_WHISPER:|Kj27|k|h[|Kj27|k]|h: yo")

-- Absent text -> nil (capture guards non-empty strings; nothing to render)
eq("nil text", F.BuildEventLine("CHAT_MSG_SAY", { sender = "Ann" }), nil)

-- Raw event entrypoint: formatter owns raw CHAT_MSG args and returns both the
-- rendered line and a safe payload for capture metadata/storage.
do
    local line, p, secretBody = F.BuildEventLineFromArgs("CHAT_MSG_CHANNEL",
        "wts", "Ann", nil, "2. Trade", nil, nil, nil, 2, "Trade")
    eq("raw args line", line, "|Hchannel:channel:2|h[T]|h |Hplayer:Ann:0:CHANNEL:2|h[Ann]|h: wts")
    eq("raw args sender", p.sender, "Ann")
    eq("raw args raw sender", p.rawSender, "Ann")
    eq("raw args channel name", p.chName, "Trade")
    eq("raw args secret flag", secretBody, false)
end

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

-- Boss and monster out-message prefixes resolve through the CHAT_<TYPE>_GET
-- globals (mirrored by ChatFrameUtil.GetOutMessageFormatKey), matching
-- Blizzard's MessageFormatter branch for MONSTER_* and RAID_BOSS_* events. The
-- resolver delegates to the helper only when the key EXISTS — a key-less type
-- (TEXT_EMOTE / GUILD_ITEM_LOOTED) must never trip Blizzard's missing-key assert
-- (see chat_text_emote_missing_get_no_assert_test).
eq("evt boss helper prefix", F.BuildEventLine("CHAT_MSG_RAID_BOSS_EMOTE",
        { text = "casts Doom.", sender = "Big Boss" }),
    "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|tBig Boss casts Doom.")

_G.CHAT_MONSTER_YELL_GET = "%s yells: "
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

-- Plain body + secret sender + secret GUID in combat: the body itself is a
-- normal string, but the sender identity is restricted. The formatter must still
-- build a class-colored sender prefix from fixed templates and the raw GUID;
-- otherwise the line degrades to plain body and renders in the chat-type color.
do
    local meta = getmetatable(secret)
    local function sentinel()
        local s = setmetatable({}, meta)
        secrets[s] = true
        return s
    end

    local secretSender = sentinel()
    local secretGuid = sentinel()
    local shown = sentinel()
    local coloredShown = sentinel()
    local coloredLink = sentinel()
    local coloredPrefix = sentinel()
    local coloredFinal = sentinel()

    local prevGPI = _G.GetPlayerInfoByGUID
    _G.GetPlayerInfoByGUID = function(gg)
        if rawequal(gg, secretGuid) then return "Mage", "MAGE" end
        return prevGPI(gg)
    end

    local realFormat = string.format
    string.format = function(fmt, ...)
        local a1, a2 = ...
        if fmt == "[%s]" and rawequal(a1, secretSender) then
            return shown
        elseif fmt == "|c%s%s|r" and a1 == "ff3fc7eb" and rawequal(a2, shown) then
            return coloredShown
        elseif fmt == "|Hplayer:%s|h%s|h" and rawequal(a1, secretSender) and rawequal(a2, coloredShown) then
            return coloredLink
        elseif fmt == "%s%s" and a1 == "" and rawequal(a2, coloredLink) then
            return coloredLink
        elseif fmt == "[P] %s: " and rawequal(a1, coloredLink) then
            return coloredPrefix
        elseif fmt == "%s%s" and rawequal(a1, coloredPrefix) and a2 == "plain body" then
            return coloredFinal
        end
        return realFormat(fmt, ...)
    end

    local got = F.BuildEventLine("CHAT_MSG_PARTY", {
        text = "plain body",
        rawSender = secretSender,
        rawGuid = secretGuid,
    })

    string.format = realFormat
    _G.GetPlayerInfoByGUID = prevGPI
    assert(rawequal(got, coloredFinal), "plain body with secret sender+GUID keeps class-colored prefix")
end

-- Instance-chat secret identity in combat: GetPlayerInfoByGUID can return
-- nothing for the secret GUID, but UnitClassFromGUID is secret-arg allowed and
-- returns a non-secret class filename. This keeps M+ instance-chat prefixes
-- class-colored when both sender and GUID are restricted.
do
    local meta = getmetatable(secret)
    local function sentinel()
        local s = setmetatable({}, meta)
        secrets[s] = true
        return s
    end

    local secretSender = sentinel()
    local secretGuid = sentinel()
    local shown = sentinel()
    local coloredShown = sentinel()
    local plainLink = sentinel()
    local coloredLink = sentinel()
    local plainPrefix = sentinel()
    local coloredPrefix = sentinel()
    local plainFinal = sentinel()
    local coloredFinal = sentinel()

    local prevGPI = _G.GetPlayerInfoByGUID
    local prevUCFG = _G.UnitClassFromGUID
    _G.GetPlayerInfoByGUID = function(gg)
        if rawequal(gg, secretGuid) then return nil end
        return prevGPI(gg)
    end
    _G.UnitClassFromGUID = function(gg)
        if rawequal(gg, secretGuid) then return "Demon Hunter", "DEMONHUNTER", 12 end
        return nil
    end

    local realFormat = string.format
    string.format = function(fmt, ...)
        local a1, a2 = ...
        if fmt == "[%s]" and rawequal(a1, secretSender) then
            return shown
        elseif fmt == "|c%s%s|r" and a1 == "ffa330c9" and rawequal(a2, shown) then
            return coloredShown
        elseif fmt == "|Hplayer:%s|h%s|h" and rawequal(a1, secretSender) and rawequal(a2, shown) then
            return plainLink
        elseif fmt == "|Hplayer:%s|h%s|h" and rawequal(a1, secretSender) and rawequal(a2, coloredShown) then
            return coloredLink
        elseif fmt == "%s%s" and a1 == "" and rawequal(a2, plainLink) then
            return plainLink
        elseif fmt == "%s%s" and a1 == "" and rawequal(a2, coloredLink) then
            return coloredLink
        elseif fmt == "[IL] %s: " and rawequal(a1, plainLink) then
            return plainPrefix
        elseif fmt == "[IL] %s: " and rawequal(a1, coloredLink) then
            return coloredPrefix
        elseif fmt == "%s%s" and rawequal(a1, plainPrefix) and a2 == "focus kick" then
            return plainFinal
        elseif fmt == "%s%s" and rawequal(a1, coloredPrefix) and a2 == "focus kick" then
            return coloredFinal
        end
        return realFormat(fmt, ...)
    end

    local got = F.BuildEventLineFromArgs("CHAT_MSG_INSTANCE_CHAT_LEADER",
        "focus kick", secretSender, nil, nil, nil, nil, nil, nil, nil, nil, nil, secretGuid)

    string.format = realFormat
    _G.GetPlayerInfoByGUID = prevGPI
    _G.UnitClassFromGUID = prevUCFG
    assert(rawequal(got, coloredFinal), "instance-chat secret GUID uses UnitClassFromGUID class color")
end

-- Secret sender + secret GUID in combat: player-name color should still be
-- preserved by resolving class from the raw GUID, without storing or comparing
-- the secret identity.
do
    local meta = getmetatable(secret)
    local function sentinel()
        local s = setmetatable({}, meta)
        secrets[s] = true
        return s
    end

    local secretSender = sentinel()
    local secretGuid = sentinel()
    local partyBody = sentinel()
    local shown = sentinel()
    local coloredShown = sentinel()
    local plainLink = sentinel()
    local coloredLink = sentinel()
    local plainPrefix = sentinel()
    local coloredPrefix = sentinel()
    local plainFinal = sentinel()
    local coloredFinal = sentinel()

    local prevGPI = _G.GetPlayerInfoByGUID
    _G.GetPlayerInfoByGUID = function(gg)
        if rawequal(gg, secretGuid) then return "Mage", "MAGE" end
        return prevGPI(gg)
    end

    local realFormat = string.format
    string.format = function(fmt, ...)
        local a1, a2 = ...
        if fmt == "[%s]" and rawequal(a1, secretSender) then
            return shown
        elseif fmt == "|c%s%s|r" and a1 == "ff3fc7eb" and rawequal(a2, shown) then
            return coloredShown
        elseif fmt == "|Hplayer:%s|h%s|h" and rawequal(a1, secretSender) and rawequal(a2, shown) then
            return plainLink
        elseif fmt == "|Hplayer:%s|h%s|h" and rawequal(a1, secretSender) and rawequal(a2, coloredShown) then
            return coloredLink
        elseif fmt == "%s%s" and a1 == "" and rawequal(a2, plainLink) then
            return plainLink
        elseif fmt == "%s%s" and a1 == "" and rawequal(a2, coloredLink) then
            return coloredLink
        elseif fmt == "[P] %s: " and rawequal(a1, plainLink) then
            return plainPrefix
        elseif fmt == "[P] %s: " and rawequal(a1, coloredLink) then
            return coloredPrefix
        elseif fmt == "%s%s" and rawequal(a1, plainPrefix) and rawequal(a2, partyBody) then
            return plainFinal
        elseif fmt == "%s%s" and rawequal(a1, coloredPrefix) and rawequal(a2, partyBody) then
            return coloredFinal
        end
        return realFormat(fmt, ...)
    end

    local got = F.WrapSecretEventLine("CHAT_MSG_PARTY", {
        text = partyBody,
        rawSender = secretSender,
        rawGuid = secretGuid,
    })

    string.format = realFormat
    _G.GetPlayerInfoByGUID = prevGPI
    assert(rawequal(got, coloredFinal), "secret sender+GUID keeps class-colored prefix")
end

-- ============================================================================
-- Wave 3 Task 2: Discord guild chat (CHAT_MSG_GUILD_DISCORD) formatter parity
-- ============================================================================
-- Parity sources: ChatFrameOverrides.lua:284-657 (MessageEventHandler),
-- ChatFrameUtil.lua:994-1111 (GetDecoratedSenderName, DiscordNameColorize,
-- FormatDiscordMessage), ItemRef.lua:122-129 + LinkUtil.lua:1-77
-- (GetDiscordUserLink / LinkTypes.DiscordUser = "discorduser"),
-- DiscordConstantsDocumentation.lua (DiscordChatInfo fields,
-- DiscordDisplayNameType.GlobalName = 2 -- the literal fallback
-- DISCORD_GLOBAL_NAME_TYPE uses when _G.Enum isn't present, so no Enum mock
-- is needed here).

_G.CHAT_GUILD_DISCORD_GET = "%s says: "
_G.DISCORD_MESSAGE_ATTACHMENT = "[Attachment]"
_G.DISCORD_MESSAGE_POLL = "[Poll]"
_G.DISCORD_MESSAGE_FORWARD = "[Forwarded]"
_G.YELLOW_FONT_COLOR = { WrapTextInColorCode = function(_, t) return "Y<" .. t .. ">" end }

-- --- DecorateSender: Discord identity override (ChatFrameUtil.lua:1018-1026) --

-- userID == 0 (not from Discord): discordInfo entirely ignored, ordinary
-- WoW-character decoration proceeds untouched.
eq("decorate discord userID=0 ignored",
    F.DecorateSender("CHAT_MSG_GUILD", "hi", "Bob-Realm", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        { userID = 0, lastOnlineName = "ShouldNotAppear" }),
    "Bob")

-- lastOnlineName path (type ~= GlobalName / no globalName): BOTH the
-- decorated name and the class-color GUID swap to the Discord identity's
-- linked WoW character -- and the swapped name is NOT re-ambiguated
-- (Blizzard overwrites decoratedPlayerName directly with lastOnlineName,
-- ChatFrameUtil.lua:1025, with no further Ambiguate call), so a cross-realm
-- lastOnlineName keeps its "-Realm" suffix unlike an ordinary sender.
eq("decorate discord lastOnlineName class-colored, realm kept (not re-ambiguated)",
    F.DecorateSender("CHAT_MSG_GUILD_DISCORD", "hi", "DiscordHandle#0", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        { userID = 111222333, lastOnlineName = "Zed-Realm", lastOnlineGUID = "Player-1-MAGE" }),
    "|cff3fc7ebZed-Realm|r")

-- No class resolves for the linked GUID (absent here): the swapped name still
-- renders, uncolored -- never falls back to the original WoW-side handle.
eq("decorate discord lastOnlineName, no linked guid, stays plain",
    F.DecorateSender("CHAT_MSG_GUILD_DISCORD", "hi", "DiscordHandle#0", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        { userID = 444555666, lastOnlineName = "Nobody-Realm" }),
    "Nobody-Realm")

-- GlobalName display mode: returns ChatFrameUtil.DiscordNameColorize(globalName)
-- IMMEDIATELY (ChatFrameUtil.lua:1019-1023), bypassing BOTH the
-- timerunning-icon check AND ProcessSenderNameFilters entirely -- a genuine
-- Blizzard quirk, mirrored rather than "fixed".
do
    local prevFilter = _G.ChatFrameUtil.ProcessSenderNameFilters
    local filterCalled = false
    _G.ChatFrameUtil.ProcessSenderNameFilters = function(_, decorated) filterCalled = true; return decorated end
    _G.C_ChatInfo = { GetColorForChatType = function(name)
        assert(name == "DISCORD_PLAYER_NAME", "queries the DISCORD_PLAYER_NAME chat-color slot")
        return { r = 224 / 255, g = 227 / 255, b = 1 }
    end }
    eq("decorate discord globalName colorized via GetColorForChatType",
        F.DecorateSender("CHAT_MSG_GUILD_DISCORD", "hi", "WoWCharName", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
            { userID = 777888999, type = 2, globalName = "coolname" }),
        "|cffe0e3ffcoolname|r")
    eq("globalName path bypasses ProcessSenderNameFilters (Blizzard quirk)", filterCalled, false)
    _G.ChatFrameUtil.ProcessSenderNameFilters = prevFilter
    _G.C_ChatInfo = nil
end

-- GetColorForChatType unavailable: falls back to Blizzard's own hardcoded
-- CreateColor(224, 227, 255, 1) literal (ChatFrameUtil.lua:1056) -- same
-- E0E3FF facsimile, since C_ChatInfo is absent from this harness by default.
eq("decorate discord globalName fallback color (no C_ChatInfo)",
    F.DecorateSender("CHAT_MSG_GUILD_DISCORD", "hi", "WoWCharName", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        { userID = 1, type = 2, globalName = "fallbackname" }),
    "|cffe0e3fffallbackname|r")

-- Secret discordInfo (the CHAT_MSG_GUILD case: SecretInChatMessagingLockdown
-- under combat lockdown, and discordInfo itself has no NeverSecret marker):
-- degrades to the ordinary WoW-character path rather than throwing or
-- guessing (IsFromDiscord's own conservative gate never asserts "from
-- Discord" on an unreadable table).
do
    local secretDiscordInfo = setmetatable({}, { __tostring = explode, __concat = explode, __len = explode })
    secrets[secretDiscordInfo] = true
    eq("decorate secret discordInfo degrades to normal path (no crash)",
        F.DecorateSender("CHAT_MSG_GUILD", "hi", "Fresh-Realm", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
            secretDiscordInfo),
        "Fresh")
    secrets[secretDiscordInfo] = nil
end

-- --- FormatDiscordMessage: content markers (ChatFrameUtil.lua:1079-1111) ---
-- Isolated from the discorduser-link/outMsg-quirk branches below by using a
-- non-GUILD/-GUILD_DISCORD typeKey -- Blizzard's own `if isFromDiscord then
-- message = FormatDiscordMessage(...)` gate has NO typeKey restriction
-- (ChatFrameOverrides.lua:611-613).

eq("discord marker: fromDiscord=false leaves message untouched (own inner gate)",
    F.BuildEventLine("CHAT_MSG_SAY", {
        text = "hello", sender = "Ann", decorated = "Ann",
        isFromDiscord = true, discordInfo = { userID = 5, fromDiscord = false, hasAttachment = true },
    }),
    "|Hplayer:Ann:0:SAY:|h[Ann]|h: hello")

eq("discord marker: attachment",
    F.BuildEventLine("CHAT_MSG_SAY", {
        text = "look at this", sender = "Ann", decorated = "Ann",
        isFromDiscord = true, discordInfo = { userID = 5, fromDiscord = true, hasAttachment = true },
    }),
    "|Hplayer:Ann:0:SAY:|h[Ann]|h: Y<[Attachment]> look at this")

eq("discord marker: multiple flags -- LAST in Blizzard's if-chain order wins (poll after attachment), never stacked",
    F.BuildEventLine("CHAT_MSG_SAY", {
        text = "vote now", sender = "Ann", decorated = "Ann",
        isFromDiscord = true,
        discordInfo = { userID = 5, fromDiscord = true, hasAttachment = true, hasPoll = true },
    }),
    "|Hplayer:Ann:0:SAY:|h[Ann]|h: Y<[Poll]> vote now")

eq("discord marker: forwardedMessage replaces the body entirely (Blizzard quirk)",
    F.BuildEventLine("CHAT_MSG_SAY", {
        text = "original text (discarded)", sender = "Ann", decorated = "Ann",
        isFromDiscord = true,
        discordInfo = { userID = 5, fromDiscord = true, hasForwardedMessage = true, forwardedMessage = "the forwarded text" },
    }),
    "|Hplayer:Ann:0:SAY:|h[Ann]|h: Y<[Forwarded]> the forwarded text")

do
    local secretFlag = setmetatable({}, { __tostring = explode, __concat = explode, __len = explode })
    secrets[secretFlag] = true
    eq("discord marker: secret flag value never asserted true",
        F.BuildEventLine("CHAT_MSG_SAY", {
            text = "hello", sender = "Ann", decorated = "Ann",
            isFromDiscord = true, discordInfo = { userID = 5, fromDiscord = true, hasAttachment = secretFlag },
        }),
        "|Hplayer:Ann:0:SAY:|h[Ann]|h: hello")
    secrets[secretFlag] = nil
end

-- --- BuildPlayerLink: GetDiscordUserLink parity (ChatFrameOverrides.lua:594-595,
-- 637-638; ItemRef.lua:122-124; LinkUtil.lua:62,69-77) -- p-based, combining
-- identity + link + marker end-to-end for CHAT_MSG_GUILD_DISCORD.

do
    local discordInfo = {
        userID = 987654321, fromDiscord = true, hasAttachment = true,
        lastOnlineName = "Zed-Realm", lastOnlineGUID = "Player-1-MAGE",
    }
    local decorated = F.DecorateSender("CHAT_MSG_GUILD_DISCORD", "hey guild", "DiscordHandle#0",
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, discordInfo)
    eq("e2e: decorated identity swapped + class-colored", decorated, "|cff3fc7ebZed-Realm|r")

    local line = F.BuildEventLine("CHAT_MSG_GUILD_DISCORD", {
        text = "hey guild", sender = "DiscordHandle#0", decorated = decorated,
        lineID = 909, bnID = 0,
        isFromDiscord = true, discordInfo = discordInfo,
    })
    -- |Hdiscorduser:bnetIDAccount:discordUserID:lineID:chatGroup:chatTarget|h...|h,
    -- PLUS ChatFrameOverrides.lua:637-638's genuine extra-space quirk (pflag
    -- .." "..playerLink, unconditional -- with pflag empty here that reads as
    -- a stray space after the [GD] shorten tag; mirrored, not "fixed").
    eq("e2e: [GD] tag + discorduser link + attachment marker + GUILD_DISCORD extra-space quirk", line,
        "[GD]  |Hdiscorduser:0:987654321:909:GUILD_DISCORD:|h[|cff3fc7ebZed-Realm|r]|h: Y<[Attachment]> hey guild")
end

-- CHAT_MSG_GUILD carrying a Discord-bridged message (isFromDiscord true for
-- typeKey=="GUILD" too, ChatFrameOverrides.lua:594): gets the SAME
-- discorduser link, but NOT the extra-space quirk -- that quirk's condition
-- is `type == "GUILD_DISCORD"` specifically (ChatFrameOverrides.lua:637),
-- never "GUILD".
do
    local discordInfo = { userID = 42, fromDiscord = true }
    local line = F.BuildEventLine("CHAT_MSG_GUILD", {
        text = "hi from bridge", sender = "Handle#1", decorated = "Handle#1",
        lineID = 5, bnID = 0, isFromDiscord = true, discordInfo = discordInfo,
    })
    eq("e2e: GUILD+isFromDiscord uses discorduser link, no extra-space quirk",
        line, "[G] |Hdiscorduser:0:42:5:GUILD:|h[Handle#1]|h: hi from bridge")
end

-- --- Full raw-args round trip: BuildEventLineFromArgs / BuildPayloadFromArgs
-- unpack through a18 (discordInfo), matching message_capture.lua's forwarded
-- vararg chain end to end. ---

do
    local discordInfo = {
        userID = 555, fromDiscord = true, hasPoll = true,
        lastOnlineName = "Kara-Realm", lastOnlineGUID = "Player-2-MAGE",
    }
    -- a1=text a2=sender a3..a10=8 nils a11=lineID a12=guid(WoW-side; irrelevant
    -- once discordInfo swaps it) a13=bnID a14=isMobile a15=isSubtitle
    -- a16=hideSenderInLetterbox a17=suppressRaidIcons a18=discordInfo
    local line, p, secretBody = F.BuildEventLineFromArgs("CHAT_MSG_GUILD_DISCORD",
        "raid at 8pm?", "DiscordHandle#0", nil, nil, nil, nil, nil, nil, nil, nil,
        314, nil, 0, false, false, false, false, discordInfo)
    eq("e2e raw-args: not secret", secretBody, false)
    eq("e2e raw-args: payload carries discordInfo by identity", rawequal(p.discordInfo, discordInfo), true)
    eq("e2e raw-args: payload isFromDiscord gate", p.isFromDiscord, true)
    eq("e2e raw-args: identity swapped + class-colored", p.decorated, "|cff3fc7ebKara-Realm|r")
    eq("e2e raw-args: full line -- [GD] tag, discorduser link, swapped identity, poll marker, extra-space quirk",
        line,
        "[GD]  |Hdiscorduser:0:555:314:GUILD_DISCORD:|h[|cff3fc7ebKara-Realm|r]|h: Y<[Poll]> raid at 8pm?")
end

-- Non-Discord CHAT_MSG_GUILD_DISCORD traffic (a WoW player's own message
-- routed through the bridge stream, userID==0): behaves exactly like an
-- ordinary GUILD line -- plain GetPlayerLink, no discorduser link, no markers.
do
    local line, p = F.BuildEventLineFromArgs("CHAT_MSG_GUILD_DISCORD",
        "just a normal guild line", "Wowchar-Realm", nil, nil, nil, nil, nil, nil, nil, nil,
        7, nil, 0, false, false, false, false, { userID = 0, fromDiscord = false })
    eq("non-discord GUILD_DISCORD payload isFromDiscord false", p.isFromDiscord, false)
    eq("non-discord GUILD_DISCORD renders as a plain player link ([GD] tag, no quirk space)",
        line, "[GD] |Hplayer:Wowchar-Realm:7:GUILD_DISCORD:|h[Wowchar]|h: just a normal guild line")
end

-- channelShorten short tag: GUILD_DISCORD gets its own [GD] (distinct from
-- GUILD's [G]) instead of the tag-less "name: text" fallback unlisted types
-- get. QUI-only feature (Blizzard has no shorten mode), so the tag has no
-- Blizzard citation -- consistency with the surrounding 1-2 char tag style is
-- the contract.
eq("channelShorten tag for GUILD_DISCORD is [GD], distinct from GUILD's [G]",
    F.BuildEventLine("CHAT_MSG_GUILD_DISCORD", { text = "hi", sender = "Ann" }),
    "[GD] |Hplayer:Ann:0:GUILD_DISCORD:|h[Ann]|h: hi")

-- Review Minor 2: discordInfo with a usable lastOnlineGUID but NO usable
-- lastOnlineName swaps only the GUID -- the displayed name stays the raw
-- Discord handle, colored by the LINKED character's class. That resolve must
-- NOT seed nameClassCache[handle] = linked class: the handle is not a
-- character name, and a poisoned entry would recolor unrelated future lines
-- from the same handle via the cold-GUID name-recovery path.
do
    local handle = "PollutionHandle#9"
    -- 1) Guid-only swap: colors via the linked GUID (MAGE), name un-swapped.
    eq("discord guid-only swap colors handle via linked guid",
        F.DecorateSender("CHAT_MSG_GUILD_DISCORD", "hi", handle, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
            { userID = 31, lastOnlineGUID = "Player-1-MAGE" }),
        "|cff3fc7eb" .. handle .. "|r")
    -- 2) Same handle later, secret GUID (no engine resolve), no discordInfo:
    -- the name-cache recovery path is the only way this could color. A seeded
    -- nameClassCache[handle] from step 1 would return the MAGE color here;
    -- the fix (classLookupName cleared on a guid-only swap) keeps it plain.
    local secretGuid = setmetatable({}, getmetatable(secret))
    secrets[secretGuid] = true
    eq("discord guid-only swap does NOT seed the name cache under the handle",
        F.DecorateSender("CHAT_MSG_GUILD", "hi", handle, nil, nil, nil, nil, nil, nil, nil, nil, nil, secretGuid),
        handle)
    secrets[secretGuid] = nil
end

print("OK: chat_message_format_test")
