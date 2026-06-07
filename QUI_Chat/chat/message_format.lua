-- modules/chat/message_format.lua
-- Minimal formatter for custom-display lines captured from CHAT_MSG_* events.
-- Phase 1 uses deliberately short prefixes ([G], [2. Trade]); full Blizzard
-- formatting parity is the Phase 2 expansion of this file (design Risk 2 —
-- ALL replicated Blizzard formatting must stay isolated here).
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

local function PlayerLink(sender, guid)
    if IsSecret(sender) or type(sender) ~= "string" or sender == "" then return nil end
    local shown = (_G.Ambiguate and _G.Ambiguate(sender, "short")) or sender
    local colorStr = SenderClassColorStr(guid)
    if colorStr then
        shown = ("|c%s%s|r"):format(colorStr, shown)
    end
    return ("|Hplayer:%s|h[%s]|h"):format(sender, shown), shown
end

local BOSS_NOTICE_EVENTS = {
    RAID_BOSS_EMOTE = true,
    RAID_BOSS_WHISPER = true,
    QUEST_BOSS_EMOTE = true,
}

-- Short prefixes for the common routed types. Types not listed render bare.
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

-- Build the display line for a NON-secret body. Secret/absent sender or
-- channel args degrade gracefully (drop that fragment; never touch secrets).
-- Args mirror the CHAT_MSG_* payload positions used: text=arg1, sender=arg2,
-- channelNumber=arg8, channelBaseName=arg9, guid=arg12, bnID=arg13, lineID=arg11.
function Format.BuildLine(event, text, sender, channelNumber, channelName, guid, bnID, lineID)
    -- Contract: non-secret string body (capture guards this). Degrade to an
    -- empty body rather than erroring/tainting if a future caller slips.
    if IsSecret(text) or type(text) ~= "string" then text = "" end
    local typeKey = Format.EventToTypeKey(event)
    local prefix = ""
    if typeKey == "CHANNEL" then
        if not IsSecret(channelName) and type(channelName) == "string" and channelName ~= "" then
            if not IsSecret(channelNumber) and type(channelNumber) == "number" and channelNumber > 0 then
                prefix = ("[%d. %s] "):format(channelNumber, channelName)
            else
                prefix = ("[%s] "):format(channelName)
            end
        end
    elseif typeKey and TYPE_PREFIX[typeKey] then
        prefix = TYPE_PREFIX[typeKey]
    end

    local senderPart = ""
    if not IsSecret(sender) and type(sender) == "string" and sender ~= "" then
        local _, shown = PlayerLink(sender, guid)
        if typeKey == "BN_WHISPER" or typeKey == "BN_WHISPER_INFORM" then
            if not IsSecret(bnID) and type(bnID) == "number" then
                local lid = (not IsSecret(lineID) and type(lineID) == "number") and lineID or 0
                -- Category per Blizzard: INFORM links carry BN_WHISPER.
                local category = (typeKey == "BN_WHISPER_INFORM") and "BN_WHISPER" or typeKey
                -- Real BN link: |HBNplayer:name:bnetIDAccount:lineID:chatType:chatTarget|h
                senderPart = ("|HBNplayer:%s:%d:%d:%s:0|h[%s]|h: "):format(sender, bnID, lid, category, shown)
            else
                -- No bnSenderID -> plain (a |Hplayer:| link would be a broken
                -- click target for BN display names).
                senderPart = ("[%s]: "):format(shown)
            end
        else
            senderPart = ("|Hplayer:%s|h[%s]|h: "):format(sender, shown)
        end
    end

    return prefix .. senderPart .. text
end

-- Special-event dispatch table: these events carry tokens/templates instead
-- of plain bodies and replicate Blizzard's exact format calls (vendored
-- FrameXML: Blizzard_ChatFrameBase/Mainline/ChatFrameOverrides.lua).
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
    EMOTE = "playeremote",
    TEXT_EMOTE = "textemote",
    MONSTER_SAY = "emote",
    MONSTER_YELL = "emote",
    MONSTER_WHISPER = "emote",
    MONSTER_PARTY = "emote",
    MONSTER_EMOTE = "emote",
    RAID_BOSS_EMOTE = "emote",
    RAID_BOSS_WHISPER = "emote",
}

local function BNToastGlobalString(token)
    local gs = _G["BN_INLINE_TOAST_" .. token]
    if type(gs) == "string" then return gs end
    if token == "FRIEND_OFFLINE" and type(_G.ERR_FRIEND_OFFLINE_S) == "string" then
        return _G.ERR_FRIEND_OFFLINE_S
    end
    return nil
end

local function ChatCategoryForTypeKey(typeKey)
    local categories = _G.CHAT_INVERTED_CATEGORY_LIST
    local category = type(categories) == "table" and categories[typeKey] or nil
    if type(category) == "string" then return category end
    if typeKey == "BN_INLINE_TOAST_BROADCAST"
        or typeKey == "BN_INLINE_TOAST_BROADCAST_INFORM" then
        return "BN_INLINE_TOAST_ALERT"
    end
    return typeKey
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

local function GetOutMessageFormatKey(typeKey)
    local util = _G.ChatFrameUtil and _G.ChatFrameUtil.GetOutMessageFormatKey
    if type(util) == "function" then
        local ok, fmt = pcall(util, typeKey)
        if ok and type(fmt) == "string" and fmt ~= "" then
            return fmt
        end
    end
    local fmt = _G["CHAT_" .. typeKey .. "_GET"]
    if type(fmt) == "string" and fmt ~= "" then
        return fmt
    end
    return "%s "
end

local function IsMonsterOrRaidBossType(typeKey)
    return type(typeKey) == "string"
        and (typeKey:sub(1, 7) == "MONSTER" or typeKey:sub(1, 9) == "RAID_BOSS")
end

local function FormatString(fmt, ...)
    local ok, formatted = pcall(string.format, fmt, ...)
    if not ok then return nil end
    return formatted
end

local function IsNormalPlayerType(typeKey)
    return typeKey == "SAY"
        or typeKey == "CHANNEL"
        or typeKey == "COMMUNITIES_CHANNEL"
        or TYPE_PREFIX[typeKey] ~= nil
end

local function FormattedPlayerLink(sender, guid)
    if not IsSecret(sender) then
        return PlayerLink(sender, guid)
    end
    local shown = FormatString("[%s]", sender)
    if not shown then return nil end
    return FormatString("|Hplayer:%s|h%s|h", sender, shown)
end

local function FormattedBNPlayerLink(typeKey, sender, guid, bnID, lineID)
    local shown
    if IsSecret(sender) then
        shown = FormatString("[%s]", sender)
    else
        local _, display = PlayerLink(sender, guid)
        shown = display and FormatString("[%s]", display) or nil
    end
    if not shown then return nil end

    if not IsSecret(bnID) and type(bnID) == "number" then
        local lid = (not IsSecret(lineID) and type(lineID) == "number") and lineID or 0
        local category = (typeKey == "BN_WHISPER_INFORM") and "BN_WHISPER" or typeKey
        return FormatString("|HBNplayer:%s:%d:%d:%s:0|h%s|h", sender, bnID, lid, category, shown)
    end

    return shown
end

local function FormattedSenderPart(typeKey, sender, guid, bnID, lineID)
    local link
    if typeKey == "BN_WHISPER" or typeKey == "BN_WHISPER_INFORM" then
        link = FormattedBNPlayerLink(typeKey, sender, guid, bnID, lineID)
    else
        link = FormattedPlayerLink(sender, guid)
    end
    if not link then return nil end
    return FormatString("%s: ", link)
end

local function FormattedChannelPrefix(channelNumber, channelName)
    if IsSecret(channelName) or type(channelName) ~= "string" or channelName == "" then
        return ""
    end
    if not IsSecret(channelNumber) and type(channelNumber) == "number" and channelNumber > 0 then
        return FormatString("[%d. %s] ", channelNumber, channelName) or ""
    end
    return FormatString("[%s] ", channelName) or ""
end

local function SecretNormalPrefix(typeKey, sender, channelNumber, channelName, guid, bnID, lineID)
    local prefix = ""
    if typeKey == "CHANNEL" then
        prefix = FormattedChannelPrefix(channelNumber, channelName)
    elseif TYPE_PREFIX[typeKey] then
        prefix = TYPE_PREFIX[typeKey]
    end

    local senderPart = FormattedSenderPart(typeKey, sender, guid, bnID, lineID)
    if not senderPart then return prefix ~= "" and prefix or nil end
    return FormatString("%s%s", prefix, senderPart)
end

local function SecretMonsterPrefix(typeKey, sender)
    local fmt = GetOutMessageFormatKey(typeKey)
    if IsSecret(sender) then
        return FormatString(fmt, sender)
    end
    if type(sender) ~= "string" or sender == "" then return nil end
    return FormatString(fmt, sender)
end

function Format.WrapSecretEventLine(event, text, sender, _channelFull, channelNumber, channelName, guid, bnID, lineID)
    if not IsSecret(text) then return text end
    local typeKey = Format.EventToTypeKey(event)

    local prefix
    if IsNormalPlayerType(typeKey) then
        prefix = SecretNormalPrefix(typeKey, sender, channelNumber, channelName, guid, bnID, lineID)
    elseif IsMonsterOrRaidBossType(typeKey) then
        prefix = SecretMonsterPrefix(typeKey, sender)
    else
        return text
    end
    if IsSecret(prefix) then
        return FormatString("%s%s", prefix, text) or text
    end
    if type(prefix) ~= "string" or prefix == "" then return text end

    return FormatString("%s%s", prefix, text) or text
end

-- One entry point for capture: returns the display line, or nil to DROP the
-- message (unrenderable token, secret template, missing globalstring).
-- Args mirror payload positions: text=arg1, sender=arg2, channelFull=arg4,
-- channelNumber=arg8, channelBase=arg9, guid=arg12, bnID=arg13, lineID=arg11,
-- targetUser=arg5 (CHANNEL_NOTICE_USER two-user target, e.g. kicked player).
function Format.BuildEventLine(event, text, sender, channelFull, channelNumber, channelBase, guid, bnID, lineID, targetUser)
    local typeKey = Format.EventToTypeKey(event)
    local kind = BOSS_NOTICE_EVENTS[event] and "bossnotice" or typeKey and SPECIAL_KIND[typeKey]
    if not kind then
        return Format.BuildLine(event, text, sender, channelNumber, channelBase, guid, bnID, lineID)
    end

    -- Every special kind formats with the payload — secret or non-string
    -- templates are unrenderable: drop rather than risk an operator.
    if IsSecret(text) or type(text) ~= "string" or text == "" then return nil end

    if kind == "ach" then
        if IsSecret(sender) or type(sender) ~= "string" or sender == "" then return nil end
        local shown = (_G.Ambiguate and _G.Ambiguate(sender, "short")) or sender
        local colorStr = SenderClassColorStr(guid)
        if colorStr then shown = ("|c%s%s|r"):format(colorStr, shown) end
        local link = ("|Hplayer:%s|h[%s]|h"):format(sender, shown)
        local ok, line = pcall(string.format, text, link)
        return ok and line or nil
    elseif kind == "playeremote" then
        local link = PlayerLink(sender, guid)
        if not link then return nil end
        local fmt = GetOutMessageFormatKey(typeKey)
        local ok, line = pcall(string.format, fmt .. text, link)
        return ok and line or nil
    elseif kind == "textemote" then
        local link = PlayerLink(sender, guid)
        if not link or IsSecret(sender) or type(sender) ~= "string" or sender == "" then return nil end
        return (text:gsub(sender, link, 1))
    elseif kind == "bossnotice" then
        if IsSecret(sender) or type(sender) ~= "string" or sender == "" then return nil end
        local ok, line = pcall(string.format, text, sender, sender)
        return ok and line or nil
    elseif kind == "chanlist" then
        local num = (not IsSecret(channelNumber) and type(channelNumber) == "number") and channelNumber or nil
        local name = (not IsSecret(channelFull) and type(channelFull) == "string") and channelFull or nil
        local fmt = _G.CHAT_CHANNEL_LIST_GET
        if num and name and type(fmt) == "string" then
            local ok, line = pcall(string.format, fmt .. text, num, name)
            return ok and line or text
        end
        return text
    elseif kind == "channotuser" then
        local gs = _G["CHAT_" .. text .. "_NOTICE_BN"]
        if type(gs) ~= "string" then gs = _G["CHAT_" .. text .. "_NOTICE"] end
        if type(gs) ~= "string" then return nil end
        local num = (not IsSecret(channelNumber) and type(channelNumber) == "number") and channelNumber or 0
        local name = (not IsSecret(channelFull) and type(channelFull) == "string") and channelFull or ""
        local actor = (not IsSecret(sender) and type(sender) == "string") and sender or ""
        local target = (not IsSecret(targetUser) and type(targetUser) == "string") and targetUser or ""
        local ok, line
        if text == "INVITE" then
            local link = actor ~= "" and ("|Hplayer:%s|h[%s]|h"):format(actor, actor) or ""
            ok, line = pcall(string.format, gs, name, link)
        elseif target ~= "" then
            ok, line = pcall(string.format, gs, num, name, actor, target)
        else
            ok, line = pcall(string.format, gs, num, name, actor)
        end
        return ok and line or nil
    elseif kind == "notice" then
        local gs = _G["CHAT_" .. text .. "_NOTICE_BN"]
        if type(gs) ~= "string" then gs = _G["CHAT_" .. text .. "_NOTICE"] end
        if type(gs) ~= "string" then return nil end
        local num = (not IsSecret(channelNumber) and type(channelNumber) == "number") and channelNumber or 0
        -- arg4 is the PREFIXED full name ("2. Trade") — Blizzard passes it
        -- through (ResolvePrefixedChannelName keeps the prefix); real notice
        -- globalstrings place %s inside [..] with the %d in the link data.
        local name = (not IsSecret(channelFull) and type(channelFull) == "string") and channelFull or ""
        local ok, line = pcall(string.format, gs, num, name)
        return ok and line or nil
    elseif kind == "ignored" then
        local gs = _G.CHAT_IGNORED
        if type(gs) ~= "string" or IsSecret(sender) or type(sender) ~= "string" or sender == "" then return nil end
        local ok, line = pcall(string.format, gs, sender)
        return ok and line or nil
    elseif kind == "filtered" then
        local gs = _G.CHAT_FILTERED
        if type(gs) ~= "string" or IsSecret(sender) or type(sender) ~= "string" or sender == "" then return nil end
        local ok, line = pcall(string.format, gs, sender)
        return ok and line or nil
    elseif kind == "restricted" then
        return type(_G.CHAT_RESTRICTED_TRIAL) == "string" and _G.CHAT_RESTRICTED_TRIAL or nil
    elseif kind == "bnbroadcast" then
        local gs = _G.BN_INLINE_TOAST_BROADCAST
        if type(gs) ~= "string" then return nil end
        local link = BNToastPlayerLink(sender, bnID, lineID, typeKey)
        if not link then return nil end
        local body = NormalizeInlineToastText(text)
        if body == "" then return nil end
        local ok, line = pcall(string.format, gs, link, body)
        return ok and line or nil
    elseif kind == "bnbroadcastinform" then
        return type(_G.BN_INLINE_TOAST_BROADCAST_INFORM) == "string"
            and _G.BN_INLINE_TOAST_BROADCAST_INFORM or nil
    elseif kind == "bntoast" then
        local gs = BNToastGlobalString(text)
        if type(gs) ~= "string" then return nil end
        -- FRIEND_PENDING is %d-based (invite count), not %s-based.
        if text == "FRIEND_PENDING" then
            local n = (_G.BNGetNumFriendInvites and _G.BNGetNumFriendInvites()) or 0
            local okP, lineP = pcall(string.format, gs, n)
            return okP and lineP or nil
        end
        -- FRIEND_REMOVED/BATTLETAG_FRIEND_REMOVED: plain name, no link, no brackets.
        if text == "FRIEND_REMOVED" or text == "BATTLETAG_FRIEND_REMOVED" then
            if IsSecret(sender) or type(sender) ~= "string" or sender == "" then return nil end
            local okR, lineR = pcall(string.format, gs, sender)
            return okR and lineR or nil
        end
        if not gs:find("%%s") then return gs end
        if IsSecret(sender) or type(sender) ~= "string" or sender == "" then return nil end
        local part = BNToastPlayerLink(sender, bnID, lineID, typeKey)
        if not part then return nil end
        -- FRIEND_ONLINE/OFFLINE parity: append the character name when the
        -- BN account info resolves (sync read; nil-safe — the API may return
        -- nothing at login or when the friend is in a non-WoW game).
        -- gameAccountInfo.characterName is Nilable per BNetGameAccountInfo docs.
        if (text == "FRIEND_ONLINE" or text == "FRIEND_OFFLINE")
            and not IsSecret(bnID) and type(bnID) == "number"
            and _G.C_BattleNet and _G.C_BattleNet.GetAccountInfoByID then
            local okA, info = pcall(_G.C_BattleNet.GetAccountInfoByID, bnID)
            local game = okA and type(info) == "table"
                and type(info.gameAccountInfo) == "table" and info.gameAccountInfo or nil
            local charName = game and game.characterName
            if type(charName) == "string" and charName ~= "" then
                part = part .. (" (%s)"):format(charName)
            end
        end
        local ok, line = pcall(string.format, gs, part)
        return ok and line or nil
    else -- "emote": format(GET .. text, name, name) — Blizzard's literal call
        if IsSecret(sender) or type(sender) ~= "string" or sender == "" then return nil end
        local fmt = GetOutMessageFormatKey(typeKey)
        local ok, line = pcall(string.format, fmt .. text, sender, sender)
        return ok and line or nil
    end
end
