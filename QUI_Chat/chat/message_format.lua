-- modules/chat/message_format.lua
-- Blizzard-parity formatter for custom-display lines captured from CHAT_MSG_*
-- events. Replicates ChatFrameMixin:MessageEventHandler's formatting (vendored
-- FrameXML: Blizzard_ChatFrameBase/Mainline/ChatFrameOverrides.lua:268-674):
-- CHAT_<TYPE>_GET format strings, AFK/DND/GM flags, raid-icon/group expression
-- expansion, language headers, hyperlinked channel prefixes, full player links
-- (lineID:chatType:chatTarget). The channelShorten modifier setting swaps the
-- GET prefixes for compact labels ([G], [T]) without losing the rest.
--
-- Payload tables: both entry points take `p`, a table of probed CHAT_MSG_*
-- args built by message_capture — every possibly-secret field is nil unless
-- proven non-secret, EXCEPT p.text (BuildEventLine: non-secret string;
-- WrapSecretEventLine: secret) and p.rawSender (may be secret; only ever
-- touched through pcall'd string.format, never a Lua operator).
--   p = { text, rawSender, sender, language, channelFull, target, flags,
--         zoneID, chNum, chBase, chName (registry-resolved display name),
--         lineID, guid, bnID, decorated (DecorateSender output) }
--
-- HARD CONSTRAINT: ChatTypeInfo is READ-ONLY here. Never assign into it and
-- never call ChangeChatColor.
local _, ns = ...
local Helpers = ns.Helpers

local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: message_format.lua loaded before chat.lua. Check chat.xml — chat.lua must precede message_format.lua.")

ns.QUI.Chat.MessageFormat = ns.QUI.Chat.MessageFormat or {}
local Format = ns.QUI.Chat.MessageFormat

local function IsSecret(v)
    return Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(v) or false
end

local function FormatString(fmt, ...)
    local ok, formatted = pcall(string.format, fmt, ...)
    if not ok then return nil end
    return formatted
end

-- ---------------------------------------------------------------------------
-- Settings gates
-- ---------------------------------------------------------------------------

-- channelShorten modifier: nil when disabled (full Blizzard formats), else
-- the preset string ("letter" | "number"). Channel labels follow the preset;
-- chat-type prefixes shorten under both presets.
local function ShortenPreset()
    local settings = I.GetSettings and I.GetSettings()
    local cs = settings and settings.modifiers and settings.modifiers.channelShorten
    if not (cs and cs.enabled) then return nil end
    return cs.preset == "number" and "number" or "letter"
end

-- showRealmNames modifier: when true, cross-realm players keep their "-Realm"
-- suffix in chat sender names. Independent of channelShorten (which only
-- shapes channel/type labels). Default false ⇒ realm stripped.
local function ShowRealmNames()
    local settings = I.GetSettings and I.GetSettings()
    return (settings and settings.modifiers and settings.modifiers.showRealmNames) == true
end

-- Class color for a sender GUID, gated on the existing classColors setting.
-- Reads RAID_CLASS_COLORS directly (NOT any custom-color-aware helper — the
-- chat sender recolor must track Blizzard's class palette).
local function SenderClassColorStr(guid)
    if IsSecret(guid) or type(guid) ~= "string" or guid == "" then return nil end
    local settings = I.GetSettings and I.GetSettings()
    local mods = settings and settings.modifiers
    if not (mods and mods.classColors and mods.classColors.enabled) then return nil end
    if not _G.GetPlayerInfoByGUID then return nil end
    -- GetPlayerInfoByGUID: returns localizedClass, englishClass, ... (7 values)
    -- MayReturnNothing=true when GUID is unknown; pcall ok=true, englishClass=nil.
    local ok, _, englishClass = pcall(_G.GetPlayerInfoByGUID, guid)
    if not ok or type(englishClass) ~= "string" then return nil end
    local cc = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[englishClass]
    local colorStr = cc and cc.colorStr
    return type(colorStr) == "string" and colorStr or nil
end

-- ---------------------------------------------------------------------------
-- Sender decoration (ChatFrameUtil.GetDecoratedSenderName parity, vendored
-- ChatFrameUtil.lua:977 — replicated so the class-color gate is QUI's setting,
-- not Blizzard's per-type color toggle)
-- ---------------------------------------------------------------------------

-- Called from capture with the RAW event vararg (filters applied) so
-- ProcessSenderNameFilters sees the same payload Blizzard hands it.
-- Returns nil when the sender is secret/absent — callers fall back to the
-- raw value through pcall'd formats.
function Format.DecorateSender(event, ...)
    local _, sender = ...
    if IsSecret(sender) or type(sender) ~= "string" or sender == "" then return nil end
    local typeKey = Format.EventToTypeKey(event)
    local decorated = sender
    if _G.Ambiguate then
        -- Sender realm display is its OWN setting (showRealmNames), decoupled
        -- from channelShorten (which only shapes channel/type labels). ON mirrors
        -- Blizzard's realm-showing pair ("guild" in guild chat, else "none" —
        -- ChatFrameUtil.lua:993-998); OFF ("short") strips the realm.
        local mode = ShowRealmNames()
            and (typeKey == "GUILD" and "guild" or "none")
            or "short"
        local ok, short = pcall(_G.Ambiguate, sender, mode)
        if ok and type(short) == "string" and short ~= "" then decorated = short end
    end
    local guid = select(12, ...)
    if not IsSecret(guid) and type(guid) == "string" and guid ~= ""
        and _G.C_ChatInfo and _G.C_ChatInfo.IsTimerunningPlayer
        and _G.TimerunningUtil and _G.TimerunningUtil.AddSmallIcon then
        local ok, isTR = pcall(_G.C_ChatInfo.IsTimerunningPlayer, guid)
        if ok and isTR then
            local ok2, marked = pcall(_G.TimerunningUtil.AddSmallIcon, decorated)
            if ok2 and type(marked) == "string" and marked ~= "" then decorated = marked end
        end
    end
    local colorStr = SenderClassColorStr(not IsSecret(guid) and guid or nil)
    if colorStr then
        decorated = ("|c%s%s|r"):format(colorStr, decorated)
    end
    -- Cross-addon sender-name filters (same registry Blizzard consults).
    local util = _G.ChatFrameUtil
    if util and util.ProcessSenderNameFilters then
        local ok, filtered = pcall(util.ProcessSenderNameFilters, event, decorated, ...)
        if ok and type(filtered) == "string" and filtered ~= "" then decorated = filtered end
    end
    return decorated
end

-- ---------------------------------------------------------------------------
-- Type classification
-- ---------------------------------------------------------------------------

local BOSS_NOTICE_EVENTS = {
    RAID_BOSS_EMOTE = true,
    RAID_BOSS_WHISPER = true,
    QUEST_BOSS_EMOTE = true,
}

-- Compact prefixes used when channelShorten is enabled. Types not listed
-- render as "name: text" (SAY/CHANNEL) in short mode.
local TYPE_PREFIX = {
    GUILD = "[G] ",
    OFFICER = "[O] ",
    PARTY = "[P] ",
    PARTY_LEADER = "[PL] ",
    RAID = "[R] ",
    RAID_LEADER = "[RL] ",
    RAID_WARNING = "[RW] ",
    INSTANCE_CHAT = "[I] ",
    INSTANCE_CHAT_LEADER = "[IL] ",
    WHISPER = "[W:From] ",
    WHISPER_INFORM = "[W:To] ",
    BN_WHISPER = "[W:From] ",
    BN_WHISPER_INFORM = "[W:To] ",
    YELL = "[Y] ",
}

-- "CHAT_MSG_SAY" -> "SAY". Event names come from our own RegisterEvent list —
-- plain Lua strings, never secret.
function Format.EventToTypeKey(event)
    if type(event) ~= "string" then return nil end
    local typeKey = event:match("^CHAT_MSG_(.+)$")
    if typeKey then return typeKey end
    if BOSS_NOTICE_EVENTS[event] then return event end
    return nil
end

local function IsMonsterOrRaidBossType(typeKey)
    return type(typeKey) == "string"
        and (typeKey:sub(1, 7) == "MONSTER" or typeKey:sub(1, 9) == "RAID_BOSS")
end

-- Blizzard renders these bodies verbatim (ChatFrameOverrides.lua:382-392) —
-- no sender prefix even when arg2 carries a name (CHAT_MSG_SYSTEM often does).
local RAW_TYPES = {
    SYSTEM = true, SKILL = true, CURRENCY = true, MONEY = true,
    OPENING = true, TRADESKILLS = true, PET_INFO = true, TARGETICONS = true,
    BN_WHISPER_PLAYER_OFFLINE = true, LOOT = true, PING = true,
}

local function IsRawType(typeKey)
    if RAW_TYPES[typeKey] then return true end
    return typeKey:sub(1, 7) == "COMBAT_"
        or typeKey:sub(1, 6) == "SPELL_"
        or typeKey:sub(1, 10) == "BG_SYSTEM_"
end

-- Message group for link data / expression expansion (CHAT_INVERTED_CATEGORY_LIST
-- maps PARTY_LEADER -> PARTY etc.; identity for unlisted types).
local function ChatCategory(typeKey)
    local categories = _G.CHAT_INVERTED_CATEGORY_LIST
    local category = type(categories) == "table" and categories[typeKey] or nil
    if type(category) == "string" then return category end
    return typeKey
end

local function ChatCategoryForTypeKey(typeKey)
    local category = ChatCategory(typeKey)
    if category ~= typeKey then return category end
    if typeKey == "BN_INLINE_TOAST_BROADCAST"
        or typeKey == "BN_INLINE_TOAST_BROADCAST_INFORM" then
        return "BN_INLINE_TOAST_ALERT"
    end
    return typeKey
end

-- ---------------------------------------------------------------------------
-- Color resolution
-- ---------------------------------------------------------------------------

-- READ-ONLY color resolver; white fallback.
-- Consults user channel-color overrides (ns.QUI.Chat.ChannelColors) FIRST so
-- the custom display honours the same overrides the rendered-frame path used to
-- apply at the Blizzard level.  Falls back to ChatTypeInfo (read-only; never
-- written to — see HARD CONSTRAINT above).
--
-- typeKey: "SAY", "WHISPER", "CHANNEL2", etc.
-- chName:  optional channel base-name ("Trade") — used for CHANNEL<n> keys
--          because the override store keys custom channels by NAME not slot.
--
-- NOTE: for CHANNEL events pass "CHANNEL"..channelNumber (e.g. "CHANNEL2") and
-- the channel base name so overrides are found; ChatTypeInfo.CHANNEL itself
-- carries no r/g/b.
function Format.ColorForTypeKey(typeKey, chName)
    -- Override lookup — lazy ns reference so load order is safe.
    -- GetEffective NEVER returns nil (it falls back to white), so the call
    -- must be gated on HasOverride or every non-builtin type goes white and
    -- the ChatTypeInfo fallback below becomes unreachable.
    local CC = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.ChannelColors
    if CC and CC.HasOverride and CC.GetEffective then
        -- Determine the override-store key:
        --   custom channels → channel NAME (the store keys by name, not slot)
        --   built-in types  → typeKey itself ("SAY", "WHISPER", ...)
        local lookupKey
        if type(typeKey) == "string" and typeKey:sub(1, 7) == "CHANNEL" and type(chName) == "string" and chName ~= "" then
            lookupKey = chName
        end
        if lookupKey and CC.HasOverride(lookupKey) then
            return CC.GetEffective(lookupKey)
        end
        if typeKey and CC.HasOverride(typeKey) then
            return CC.GetEffective(typeKey)
        end
    end
    -- ChatTypeInfo fallback (read-only; safe).
    local info = typeKey and _G.ChatTypeInfo and _G.ChatTypeInfo[typeKey]
    if info then
        return info.r or 1, info.g or 1, info.b or 1
    end
    return 1, 1, 1
end

-- ---------------------------------------------------------------------------
-- Language cache (MessageFormatter's defaultLanguage handling; PEW-refreshed
-- like Blizzard's PLAYER_ENTERING_WORLD handler)
-- ---------------------------------------------------------------------------

local defaultLanguage, alternativeDefaultLanguage

-- Re-read on PLAYER_ENTERING_WORLD / ALTERNATIVE_DEFAULT_LANGUAGE_CHANGED —
-- the capture frame owns the event registration (this file stays frame-free;
-- it is a pure formatter).
function Format.RefreshLanguages()
    if _G.GetDefaultLanguage then
        local ok, lang = pcall(_G.GetDefaultLanguage)
        if ok and type(lang) == "string" then defaultLanguage = lang end
    end
    if _G.GetAlternativeDefaultLanguage then
        local ok, lang = pcall(_G.GetAlternativeDefaultLanguage)
        if ok and type(lang) == "string" then alternativeDefaultLanguage = lang end
    end
end

local function RelevantDefaultLanguage(typeKey)
    if defaultLanguage == nil and alternativeDefaultLanguage == nil then
        Format.RefreshLanguages() -- lazy first read (login burst before PEW)
    end
    if typeKey == "SAY" or typeKey == "YELL" then
        return alternativeDefaultLanguage
    end
    return defaultLanguage
end

-- ---------------------------------------------------------------------------
-- Formatting building blocks
-- ---------------------------------------------------------------------------

-- AFK/DND/GM/GUIDE/NEWCOMER flag prefix. ChatFrameUtil.GetPFlag is Blizzard's
-- implementation (vendored ChatFrameUtil.lua:254); flags/zoneID/chNum are
-- NeverSecret per ChatInfoDocumentation event payloads.
local function PFlag(flags, zoneID, chNum)
    if type(flags) ~= "string" or flags == "" then return "" end
    local util = _G.ChatFrameUtil
    if util and util.GetPFlag then
        local ok, pflag = pcall(util.GetPFlag, flags, zoneID or 0, chNum or 0)
        if ok and type(pflag) == "string" then return pflag end
    end
    local gs = _G["CHAT_FLAG_" .. flags]
    return type(gs) == "string" and gs or ""
end

-- Escape '%' so user text can pass through string.format (Blizzard escapes
-- before formatting; skipped for monster types whose GET strings expect raw).
local function EscapeFormatTokens(msg)
    if _G.C_StringUtil and _G.C_StringUtil.EscapeLuaFormatString then
        local ok, escaped = pcall(_G.C_StringUtil.EscapeLuaFormatString, msg)
        if ok and type(escaped) == "string" then return escaped end
    end
    return (msg:gsub("%%", "%%%%"))
end

-- {rt1}/{skull} -> texture markup; group expressions expand only where
-- Blizzard allows (RAID, or INSTANCE_CHAT while in an instance raid).
local function CanExpandExpressions(chatGroup)
    local util = _G.ChatFrameUtil
    if util and util.CanChatGroupPerformExpressionExpansion then
        local ok, can = pcall(util.CanChatGroupPerformExpressionExpansion, chatGroup)
        if ok then return can and true or false end
    end
    return chatGroup == "RAID"
end

local function ExpandIconExpressions(msg, suppressIcons, chatGroup)
    if _G.C_ChatInfo and _G.C_ChatInfo.ReplaceIconAndGroupExpressions then
        local ok, replaced = pcall(_G.C_ChatInfo.ReplaceIconAndGroupExpressions,
            msg, suppressIcons and true or false, not CanExpandExpressions(chatGroup))
        if ok and type(replaced) == "string" then return replaced end
    end
    return msg
end

local function CollapseSpaces(msg)
    if _G.C_StringUtil and _G.C_StringUtil.RemoveContiguousSpaces then
        local ok, trimmed = pcall(_G.C_StringUtil.RemoveContiguousSpaces, msg, 4)
        if ok and type(trimmed) == "string" then return trimmed end
    end
    return (msg:gsub("     +", "    "))
end

-- "2. Community:1234:1" -> "2. Club - Stream"; plain channels pass through.
local function ResolvePrefixedChannelName(channelFull)
    local util = _G.ChatFrameUtil
    if util and util.ResolvePrefixedChannelName then
        local ok, resolved = pcall(util.ResolvePrefixedChannelName, channelFull)
        if ok and type(resolved) == "string" and resolved ~= "" then return resolved end
    end
    return channelFull
end

-- First n UTF-8 characters (channel letter-abbreviations on localized names).
local function UTF8Prefix(text, n)
    local out, i, count = "", 1, 0
    while i <= #text and count < n do
        local b = text:byte(i)
        local len = (b >= 240 and 4) or (b >= 224 and 3) or (b >= 194 and 2) or 1
        out = out .. text:sub(i, i + len - 1)
        i = i + len
        count = count + 1
    end
    return out
end

-- Compact channel label for the letter preset: [1. General] → Gen,
-- [2. Trade - City] → T, [Services] → S; unknown/custom → first 3 letters.
local function LetterChannelLabel(name)
    if name:find("Services", 1, true) then return "S" end
    if name:sub(1, 5) == "Trade" then return "T" end
    if name:sub(1, 7) == "General" then return "Gen" end
    if name:sub(1, 12) == "LocalDefense" then return "LD" end
    if name:sub(1, 12) == "WorldDefense" then return "WD" end
    if name:sub(1, 15) == "LookingForGroup" then return "LFG" end
    return UTF8Prefix(name, 3)
end

-- A line gets the channel prefix when the event carried a prefixed channel
-- name (Blizzard's channelLength>0 rule) — plus the degenerate case where
-- arg4 was secret/absent but the base name survived (channel-family only).
local function HasChannelContext(p, typeKey)
    if type(p.channelFull) == "string" and p.channelFull ~= "" then return true end
    return (typeKey == "CHANNEL" or typeKey == "COMMUNITIES_CHANNEL")
        and type(p.chName) == "string" and p.chName ~= ""
end

-- Hyperlinked channel prefix (Blizzard: "|Hchannel:channel:N|h[2. Trade]|h ")
-- with the shorten presets swapping the label text only — the link survives.
local function ChannelDecoration(p)
    local num = p.chNum
    if type(num) ~= "number" or num <= 0 then
        -- No numbered slot (some communities traffic): plain bracket label.
        local name = p.chName or (type(p.channelFull) == "string" and ResolvePrefixedChannelName(p.channelFull))
        if type(name) ~= "string" or name == "" then return "" end
        return ("[%s] "):format(name)
    end
    local preset = ShortenPreset()
    local label
    if preset == "number" then
        label = tostring(num)
    elseif preset == "letter" then
        local base = p.chName or p.chBase or ""
        label = base ~= "" and LetterChannelLabel(base) or tostring(num)
    else
        local full = type(p.channelFull) == "string" and p.channelFull ~= ""
            and ResolvePrefixedChannelName(p.channelFull) or nil
        label = full or (("%d. %s"):format(num, p.chName or p.chBase or ""))
    end
    return ("|Hchannel:channel:%d|h[%s]|h "):format(num, label)
end

-- GET-format resolution: full mode uses Blizzard's CHAT_<TYPE>_GET ("%s says: ");
-- short mode swaps in the compact prefix ("[G] %s: "). Monster/boss/emote
-- grammar always keeps the GET string.
--
-- Blizzard's ChatFrameUtil.GetOutMessageFormatKey reports a NON-FATAL assert
-- (assertsafe -> geterrorhandler, which is NOT catchable by the pcall below)
-- whenever CHAT_<TYPE>_GET is absent. Some chat types legitimately have none —
-- TEXT_EMOTE and GUILD_ITEM_LOOTED bodies arrive pre-formatted and Blizzard's
-- own MessageFormatter never queries a format key for them. Resolve the raw
-- global FIRST and only delegate to the Blizzard helper when the key exists;
-- otherwise fall back without tripping the assert. In live clients the helper
-- just returns this same global, so gating on it is behaviour-neutral for any
-- key that is present.
local function GetOutMessageFormatKey(typeKey)
    local direct = _G["CHAT_" .. typeKey .. "_GET"]
    if type(direct) ~= "string" or direct == "" then
        return "%s "
    end
    local util = _G.ChatFrameUtil and _G.ChatFrameUtil.GetOutMessageFormatKey
    if type(util) == "function" then
        local ok, fmt = pcall(util, typeKey)
        if ok and type(fmt) == "string" and fmt ~= "" then
            return fmt
        end
    end
    return direct
end

local function OutFormat(typeKey)
    if IsMonsterOrRaidBossType(typeKey) or typeKey == "EMOTE" or typeKey == "TEXT_EMOTE" then
        return GetOutMessageFormatKey(typeKey)
    end
    if ShortenPreset() then
        return (TYPE_PREFIX[typeKey] or "") .. "%s: "
    end
    local fmt = GetOutMessageFormatKey(typeKey)
    if fmt == "%s " then fmt = "%s: " end -- missing GET: sane "[name]: text"
    return fmt
end

-- ---------------------------------------------------------------------------
-- Player links (LinkUtil parity: |Hplayer:name:lineID:chatType:chatTarget|h)
-- ---------------------------------------------------------------------------

-- Bare bracketed player hyperlink "|Hplayer:<name>|h[<shown>]|h" used by the
-- achievement and channel-INVITE notice lines. Keep the link template in one
-- place so a format change can't drift between callers.
local function BracketedPlayerLink(name, shown)
    return ("|Hplayer:%s|h[%s]|h"):format(name, shown)
end

local function ChatTargetFor(chatGroup, sender, chNum)
    if chatGroup == "CHANNEL" then
        return type(chNum) == "number" and tostring(chNum) or ""
    end
    if (chatGroup == "WHISPER" or chatGroup == "BN_WHISPER")
        and not IsSecret(sender) and type(sender) == "string" then
        -- BN senders arrive as |K kstrings; the escape is case-sensitive, so
        -- uppercasing corrupts it and the whole |HBNplayer link renders raw
        -- (FCFManager_GetChatTarget parity).
        if sender:sub(1, 2) == "|K" then return sender end
        return sender:upper()
    end
    return ""
end

local function BuildPlayerLink(typeKey, chatGroup, p, linkDisplayText)
    local sender = p.sender
    if type(sender) ~= "string" or sender == "" then return nil end
    if typeKey == "BN_WHISPER" or typeKey == "BN_WHISPER_INFORM" then
        if type(p.bnID) == "number" then
            local lid = type(p.lineID) == "number" and p.lineID or 0
            local target = ChatTargetFor(chatGroup, sender, p.chNum)
            return ("|HBNplayer:%s:%d:%d:%s:%s|h%s|h"):format(
                sender, p.bnID, lid, chatGroup, target, linkDisplayText)
        end
        -- No bnSenderID -> plain text (a |Hplayer:| link would be a broken
        -- click target for BN display names).
        return linkDisplayText
    end
    if typeKey == "COMMUNITIES_CHANNEL" then
        -- Community message links carry club/stream/message coordinates
        -- (ChatFrameOverrides.lua:564-576). GetInfoFromLastCommunityChatLine
        -- is only valid during the dispatch of this event — pcall + fallback.
        if _G.C_Club and _G.C_Club.GetInfoFromLastCommunityChatLine then
            local ok, messageInfo, clubId, streamId = pcall(_G.C_Club.GetInfoFromLastCommunityChatLine)
            if ok and type(messageInfo) == "table" and messageInfo.messageId then
                local epoch = ("%.f"):format(messageInfo.messageId.epoch or 0)
                local position = ("%.f"):format(messageInfo.messageId.position or 0)
                local isBN = type(p.bnID) == "number" and p.bnID ~= 0
                if isBN then
                    return ("|HBNplayerCommunity:%s:%d:%s:%s:%s:%s|h%s|h"):format(
                        sender, p.bnID, tostring(clubId), tostring(streamId), epoch, position, linkDisplayText)
                end
                return ("|HplayerCommunity:%s:%s:%s:%s:%s|h%s|h"):format(
                    sender, tostring(clubId), tostring(streamId), epoch, position, linkDisplayText)
            end
        end
        return linkDisplayText
    end
    local lid = type(p.lineID) == "number" and p.lineID or 0
    local target = ChatTargetFor(chatGroup, sender, p.chNum)
    return ("|Hplayer:%s:%d:%s:%s|h%s|h"):format(sender, lid, chatGroup, target, linkDisplayText)
end

-- ---------------------------------------------------------------------------
-- Normal (non-secret body) line — MessageFormatter parity
-- ---------------------------------------------------------------------------

local function FormatNormalLine(event, typeKey, p)
    local text = p.text
    local chatGroup = ChatCategory(typeKey)
    local isMonster = IsMonsterOrRaidBossType(typeKey)
    local showLink = not isMonster

    -- VOICE_TEXT honors the speech-to-text CVar like Blizzard.
    if typeKey == "VOICE_TEXT" and _G.GetCVarBool then
        local ok, enabled = pcall(_G.GetCVarBool, "speechToText")
        if ok and not enabled then return nil end
    end

    -- Censored lines render the censored-link body verbatim (lineID is
    -- NeverSecret; the placeholder text arrives pre-built in arg1).
    if type(p.lineID) == "number" and _G.C_ChatInfo and _G.C_ChatInfo.IsChatLineCensored then
        local ok, censored = pcall(_G.C_ChatInfo.IsChatLineCensored, p.lineID)
        if ok and censored then return text end
    end

    local msg = text
    if showLink then
        msg = EscapeFormatTokens(msg)
    end
    msg = ExpandIconExpressions(msg, p.suppressIcons, chatGroup)
    msg = CollapseSpaces(msg)

    local pflag = PFlag(p.flags, p.zoneID, p.chNum)
    local sender = type(p.sender) == "string" and p.sender or ""

    -- Secret/absent sender on a player-typed line: degrade to the bare body
    -- (a "%s says:" with an empty name reads worse than no prefix). Monster
    -- types keep Blizzard's empty-name format below.
    if showLink and sender == "" and typeKey ~= "TEXT_EMOTE" then
        if HasChannelContext(p, typeKey) then
            return ChannelDecoration(p) .. msg
        end
        return msg
    end

    local usingDifferentLanguage = type(p.language) == "string" and p.language ~= ""
        and p.language ~= RelevantDefaultLanguage(typeKey)
    local usingEmote = typeKey == "EMOTE" or typeKey == "TEXT_EMOTE"

    local display = p.decorated or sender
    local linkDisplayText = display
    if usingDifferentLanguage or not usingEmote then
        linkDisplayText = ("[%s]"):format(display)
    end
    local playerLink = BuildPlayerLink(typeKey, chatGroup, p, linkDisplayText)

    local outMsg
    local fmt = OutFormat(typeKey)
    if usingDifferentLanguage then
        local languageHeader = ("[%s] "):format(p.language)
        if showLink and sender ~= "" and playerLink then
            outMsg = FormatString(fmt .. languageHeader .. msg, pflag .. playerLink)
        else
            outMsg = FormatString(fmt .. languageHeader .. msg, pflag .. sender)
        end
    else
        if not showLink or sender == "" or not playerLink then
            if typeKey == "TEXT_EMOTE" then
                outMsg = msg
            else
                outMsg = FormatString(fmt .. msg, pflag .. sender, sender)
            end
        else
            if typeKey == "TEXT_EMOTE" then
                outMsg = (msg:gsub(sender, pflag .. playerLink, 1))
            elseif typeKey == "GUILD_ITEM_LOOTED" then
                -- "$s has looted ..." — Blizzard substitutes a bare player link.
                outMsg = (msg:gsub("%$s", ("|Hplayer:%s|h%s|h"):format(sender, linkDisplayText)))
            else
                outMsg = FormatString(fmt .. msg, pflag .. playerLink)
            end
        end
    end
    if not outMsg then return nil end

    -- Channel prefix whenever the event carries a prefixed channel name
    -- (CHANNEL and COMMUNITIES_CHANNEL traffic).
    if HasChannelContext(p, typeKey) then
        outMsg = ChannelDecoration(p) .. outMsg
    end
    return outMsg
end

-- ---------------------------------------------------------------------------
-- Special-event dispatch: tokens/templates instead of plain bodies, matching
-- Blizzard's exact format calls (vendored ChatFrameOverrides.lua).
-- ---------------------------------------------------------------------------

local SPECIAL_KIND = {
    ACHIEVEMENT = "ach",
    GUILD_ACHIEVEMENT = "ach",
    CHANNEL_NOTICE = "notice",
    CHANNEL_LIST = "chanlist",
    CHANNEL_NOTICE_USER = "channotuser",
    BN_INLINE_TOAST_ALERT = "bntoast",
    BN_INLINE_TOAST_BROADCAST = "bnbroadcast",
    BN_INLINE_TOAST_BROADCAST_INFORM = "bnbroadcastinform",
    IGNORED = "ignored",
    FILTERED = "filtered",
    RESTRICTED = "restricted",
}

local function BNToastGlobalString(token)
    local gs = _G["BN_INLINE_TOAST_" .. token]
    if type(gs) == "string" then return gs end
    if token == "FRIEND_OFFLINE" and type(_G.ERR_FRIEND_OFFLINE_S) == "string" then
        return _G.ERR_FRIEND_OFFLINE_S
    end
    return nil
end

local function BNToastPlayerLink(sender, bnID, lineID, typeKey)
    if IsSecret(sender) or type(sender) ~= "string" or sender == "" then return nil end
    local display = ("[%s]"):format(sender)
    if not IsSecret(bnID) and type(bnID) == "number" then
        local lid = (not IsSecret(lineID) and type(lineID) == "number") and lineID or 0
        return ("|HBNplayer:%s:%d:%d:%s:0|h%s|h"):format(
            sender, bnID, lid, ChatCategoryForTypeKey(typeKey), display)
    end
    return display
end

local function NormalizeInlineToastText(text)
    text = text:gsub("[\r\n]+", " ")
    text = text:gsub("%s%s+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

local function FormatSpecialLine(event, typeKey, kind, p)
    local text, sender = p.text, p.sender
    local channelFull, channelNumber, targetUser = p.channelFull, p.chNum, p.target

    if kind == "ach" then
        if type(sender) ~= "string" or sender == "" then return nil end
        local shown = p.decorated or sender
        local link = BracketedPlayerLink(sender, shown)
        return FormatString(text, link)
    elseif kind == "bossnotice" then
        if type(sender) ~= "string" or sender == "" then return nil end
        return FormatString(text, sender, sender)
    elseif kind == "chanlist" then
        local num = type(channelNumber) == "number" and channelNumber or nil
        local name = type(channelFull) == "string" and channelFull or nil
        local fmt = _G.CHAT_CHANNEL_LIST_GET
        if num and name and type(fmt) == "string" then
            return FormatString(fmt .. text, num, name) or text
        end
        return text
    elseif kind == "channotuser" then
        local gs = _G["CHAT_" .. text .. "_NOTICE_BN"]
        if type(gs) ~= "string" then gs = _G["CHAT_" .. text .. "_NOTICE"] end
        if type(gs) ~= "string" then return nil end
        local num = type(channelNumber) == "number" and channelNumber or 0
        local name = type(channelFull) == "string" and ResolvePrefixedChannelName(channelFull) or ""
        local actor = type(sender) == "string" and sender or ""
        local target = type(targetUser) == "string" and targetUser or ""
        if text == "INVITE" then
            local link = actor ~= "" and BracketedPlayerLink(actor, actor) or ""
            return FormatString(gs, name, link)
        elseif target ~= "" then
            return FormatString(gs, num, name, actor, target)
        end
        return FormatString(gs, num, name, actor)
    elseif kind == "notice" then
        local gs
        if text == "TRIAL_RESTRICTED" then
            gs = _G.CHAT_TRIAL_RESTRICTED_NOTICE_TRIAL
        end
        if type(gs) ~= "string" then gs = _G["CHAT_" .. text .. "_NOTICE_BN"] end
        if type(gs) ~= "string" then gs = _G["CHAT_" .. text .. "_NOTICE"] end
        if type(gs) ~= "string" then return nil end
        local num = type(channelNumber) == "number" and channelNumber or 0
        -- arg4 is the PREFIXED full name ("2. Trade") — resolved so community
        -- identifiers display as "N. Club - Stream" like Blizzard.
        local name = type(channelFull) == "string" and ResolvePrefixedChannelName(channelFull) or ""
        return FormatString(gs, num, name)
    elseif kind == "ignored" then
        local gs = _G.CHAT_IGNORED
        if type(gs) ~= "string" or type(sender) ~= "string" or sender == "" then return nil end
        return FormatString(gs, sender)
    elseif kind == "filtered" then
        local gs = _G.CHAT_FILTERED
        if type(gs) ~= "string" or type(sender) ~= "string" or sender == "" then return nil end
        return FormatString(gs, sender)
    elseif kind == "restricted" then
        return type(_G.CHAT_RESTRICTED_TRIAL) == "string" and _G.CHAT_RESTRICTED_TRIAL or nil
    elseif kind == "bnbroadcast" then
        local gs = _G.BN_INLINE_TOAST_BROADCAST
        if type(gs) ~= "string" then return nil end
        local link = BNToastPlayerLink(sender, p.bnID, p.lineID, typeKey)
        if not link then return nil end
        local body = NormalizeInlineToastText(text)
        if body == "" then return nil end
        return FormatString(gs, link, body)
    elseif kind == "bnbroadcastinform" then
        return type(_G.BN_INLINE_TOAST_BROADCAST_INFORM) == "string"
            and _G.BN_INLINE_TOAST_BROADCAST_INFORM or nil
    elseif kind == "bntoast" then
        local gs = BNToastGlobalString(text)
        if type(gs) ~= "string" then return nil end
        -- FRIEND_PENDING is %d-based (invite count), not %s-based.
        if text == "FRIEND_PENDING" then
            local n = (_G.BNGetNumFriendInvites and _G.BNGetNumFriendInvites()) or 0
            return FormatString(gs, n)
        end
        -- FRIEND_REMOVED/BATTLETAG_FRIEND_REMOVED: plain name, no link, no brackets.
        if text == "FRIEND_REMOVED" or text == "BATTLETAG_FRIEND_REMOVED" then
            if type(sender) ~= "string" or sender == "" then return nil end
            return FormatString(gs, sender)
        end
        if not gs:find("%%s") then return gs end
        if type(sender) ~= "string" or sender == "" then return nil end
        local part = BNToastPlayerLink(sender, p.bnID, p.lineID, typeKey)
        if not part then return nil end
        -- FRIEND_ONLINE/OFFLINE parity: append the character name when the
        -- BN account info resolves (sync read; nil-safe — the API may return
        -- nothing at login or when the friend is in a non-WoW game).
        -- gameAccountInfo.characterName is Nilable per BNetGameAccountInfo docs.
        if (text == "FRIEND_ONLINE" or text == "FRIEND_OFFLINE")
            and type(p.bnID) == "number"
            and _G.C_BattleNet and _G.C_BattleNet.GetAccountInfoByID then
            local okA, info = pcall(_G.C_BattleNet.GetAccountInfoByID, p.bnID)
            local game = okA and type(info) == "table"
                and type(info.gameAccountInfo) == "table" and info.gameAccountInfo or nil
            local charName = game and game.characterName
            if type(charName) == "string" and charName ~= "" then
                part = part .. (" (%s)"):format(charName)
            end
        end
        return FormatString(gs, part)
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Entry points
-- ---------------------------------------------------------------------------

-- One entry point for capture: returns the display line, or nil to DROP the
-- message (unrenderable token, secret template, missing globalstring).
-- p.text is a non-secret string here (capture guards this).
function Format.BuildEventLine(event, p)
    if type(p) ~= "table" then return nil end
    local text = p.text
    if IsSecret(text) or type(text) ~= "string" or text == "" then return nil end
    local typeKey = Format.EventToTypeKey(event)
    if not typeKey then return nil end

    if IsRawType(typeKey) then
        return text
    end
    local kind = BOSS_NOTICE_EVENTS[event] and "bossnotice" or SPECIAL_KIND[typeKey]
    if kind then
        return FormatSpecialLine(event, typeKey, kind, p)
    end
    return FormatNormalLine(event, typeKey, p)
end

-- Secret-body line: build the largest prefix we can (flags, links, channel
-- decoration, GET format) from FIXED templates and join it to the secret body
-- with string.format — which accepts secret values and propagates secrecy, so
-- no Lua operator ever touches the payload (event doc: playerName is
-- Nilable=false without NeverSecret, so the sender may be secret too).
function Format.WrapSecretEventLine(event, p)
    if type(p) ~= "table" then return nil end
    local text = p.text
    if not IsSecret(text) then return text end
    local typeKey = Format.EventToTypeKey(event)
    if not typeKey then return text end

    -- Special + boss-notice lines build their output FROM the body — the body
    -- is itself the format template (boss notices, achievements) or indexes a
    -- globalstring by it. string.format takes secret VALUES, never a secret
    -- format string, so a secret body here is unrenderable: pass it through
    -- verbatim, exactly as the reference client does with secret payloads.
    if BOSS_NOTICE_EVENTS[event] or SPECIAL_KIND[typeKey] then
        return text
    end

    -- string.format accepts secret values and PROPAGATES secrecy; every format
    -- string below is a fixed/Blizzard template (never the secret body), so no
    -- Lua operator touches the payload and no pcall is needed. The prefix may
    -- itself be secret (built from a secret sender) — truthiness only on it,
    -- never a comparison.
    local prefix
    if IsMonsterOrRaidBossType(typeKey) then
        -- Monster chat: "<name> says/yells: " + body. The name lives in the
        -- GET prefix, not the body, so the body never needs filling.
        prefix = string.format(GetOutMessageFormatKey(typeKey), p.rawSender)
    elseif typeKey == "EMOTE" then
        -- Player emote joins the GET ("%s ") like Blizzard: linked sender when
        -- renderable, raw (possibly secret) name otherwise.
        local who = p.rawSender
        if p.sender then
            who = PFlag(p.flags, p.zoneID, p.chNum)
                .. (BuildPlayerLink(typeKey, ChatCategory(typeKey), p, p.decorated or p.sender) or p.sender)
        end
        prefix = string.format(GetOutMessageFormatKey(typeKey), who)
    elseif IsRawType(typeKey) or typeKey == "TEXT_EMOTE" then
        -- Raw types render bodies verbatim; TEXT_EMOTE grammar embeds the name
        -- in the body itself (the sender gsub can't run on a secret).
        return text
    else
        local chatGroup = ChatCategory(typeKey)
        local pflag = PFlag(p.flags, p.zoneID, p.chNum)
        local link
        if type(p.sender) == "string" and p.sender ~= "" then
            link = BuildPlayerLink(typeKey, chatGroup, p, ("[%s]"):format(p.decorated or p.sender))
        elseif IsSecret(p.rawSender) then
            local shown = string.format("[%s]", p.rawSender)
            link = string.format("|Hplayer:%s|h%s|h", p.rawSender, shown)
        end
        if link then
            prefix = string.format(OutFormat(typeKey), string.format("%s%s", pflag, link))
        elseif TYPE_PREFIX[typeKey] then
            prefix = TYPE_PREFIX[typeKey]
        end
        if HasChannelContext(p, typeKey) then
            local deco = ChannelDecoration(p)
            if deco ~= "" then
                prefix = prefix and string.format("%s%s", deco, prefix) or deco
            end
        end
    end

    if not prefix then return text end
    return string.format("%s%s", prefix, text)
end
