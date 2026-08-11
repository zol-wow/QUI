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
    local ok, formatted = ns.SafeCall("report", string.format, fmt, ...)
    if not ok then return nil end
    return formatted
end

local function IsFromDiscord(discordInfo)
    if IsSecret(discordInfo) or type(discordInfo) ~= "table" then return false end
    local userID = discordInfo.userID
    if IsSecret(userID) or not userID or userID == 0 then return false end
    return true
end

local function ShortenPreset()
    local settings = I.GetSettings and I.GetSettings()
    local cs = settings and settings.modifiers and settings.modifiers.channelShorten
    if not (cs and cs.enabled) then return nil end
    return cs.preset == "number" and "number" or "letter"
end

local function ShowRealmNames()
    local settings = I.GetSettings and I.GetSettings()
    return (settings and settings.modifiers and settings.modifiers.showRealmNames) == true
end

local CLASS_CACHE_CAP = 2000

local guidClassCache, guidClassCount = {}, 0

local nameClassCache, nameClassCount = {}, 0

local function CacheableName(name)
    if type(name) ~= "string" or name == "" or IsSecret(name) then return nil end
    return name
end

local function StoreNameClass(name, englishClass)
    if IsSecret(englishClass) or type(englishClass) ~= "string" or englishClass == "" then return end
    local key = CacheableName(name)
    if not key then return end
    if nameClassCache[key] == nil then
        if nameClassCount >= CLASS_CACHE_CAP then
            nameClassCache, nameClassCount = {}, 0
        end
        nameClassCount = nameClassCount + 1
    end
    nameClassCache[key] = englishClass
end

local function StoreNameClassAliases(name, englishClass)
    StoreNameClass(name, englishClass)
    if type(name) ~= "string" or IsSecret(name) then return end
    if _G.Ambiguate then
        local ok, short = ns.SafeCall("best-effort-style", _G.Ambiguate, name, "short")
        if ok then StoreNameClass(short, englishClass) end
    end
end

local function StoreNameClassVariants(name, englishClass)
    StoreNameClassAliases(name, englishClass)
    if type(name) ~= "string" or IsSecret(name) then return end
    local player, realm = name:match("^([^-]+)%-(.+)$")
    if player and realm then
        local compactRealm = realm:gsub("%s+", "")
        if compactRealm ~= realm then
            StoreNameClassAliases(player .. "-" .. compactRealm, englishClass)
        end
    end
end

local function LookupNameClass(name)
    local key = CacheableName(name)
    if not key then return nil end
    local direct = nameClassCache[key]
    if direct then return direct end
    local player, realm = key:match("^([^-]+)%-(.+)$")
    if player and realm then
        local compactRealm = realm:gsub("%s+", "")
        if compactRealm ~= realm then
            local compact = nameClassCache[player .. "-" .. compactRealm]
            if compact then return compact end
        end
    end
    if _G.Ambiguate then
        local ok, short = ns.SafeCall("best-effort-style", _G.Ambiguate, key, "short")
        if ok then return nameClassCache[short] end
    end
    return nil
end

local function StoreGuidClass(guid, englishClass)
    if IsSecret(guid) or type(guid) ~= "string" or guid == "" then return end
    if IsSecret(englishClass) or type(englishClass) ~= "string" or englishClass == "" then return end
    if guidClassCache[guid] == nil then
        if guidClassCount >= CLASS_CACHE_CAP then
            guidClassCache, guidClassCount = {}, 0
        end
        guidClassCount = guidClassCount + 1
    end
    guidClassCache[guid] = englishClass
end

local function SeedUnitClass(unit)
    if not _G.UnitExists then return end
    local okExists, exists = ns.SafeCall("best-effort-style", _G.UnitExists, unit)
    if not okExists or not exists then return end
    if _G.UnitIsPlayer then
        local okPlayer, isPlayer = ns.SafeCall("best-effort-style", _G.UnitIsPlayer, unit)
        if not okPlayer or not isPlayer then return end
    end
    if not _G.UnitClass then return end
    local ok, _, englishClass = pcall(_G.UnitClass, unit)
    if not ok or IsSecret(englishClass)
        or type(englishClass) ~= "string" or englishClass == "" then return end
    if _G.UnitGUID then
        local okGuid, guid = ns.SafeCall("best-effort-style", _G.UnitGUID, unit)
        if okGuid then StoreGuidClass(guid, englishClass) end
    end
    if _G.UnitName then
        local okName, name, server = pcall(_G.UnitName, unit)
        if okName and not IsSecret(name) and type(name) == "string" and name ~= "" then
            if not IsSecret(server) and type(server) == "string" and server ~= "" then
                StoreNameClassVariants(name .. "-" .. server, englishClass)
            end
            StoreNameClassVariants(name, englishClass)
            return
        end
    end
    local getName = _G.GetUnitName
    if getName then
        local okFull, full = ns.SafeCall("best-effort-style", getName, unit, true)
        if okFull then StoreNameClassVariants(full, englishClass) end
        local okShort, short = ns.SafeCall("best-effort-style", getName, unit, false)
        if okShort then StoreNameClassVariants(short, englishClass) end
    end
end

local function InChatMessagingLockdown()
    local CI = _G.C_ChatInfo
    if not (CI and CI.InChatMessagingLockdown) then return false end
    local ok, restricted = ns.SafeCall("best-effort-style", CI.InChatMessagingLockdown)
    return ok and restricted == true or false
end

local function SeedGuildMemberClasses()
    if InChatMessagingLockdown() then return end
    local Club, CreatureInfo = _G.C_Club, _G.C_CreatureInfo
    if not (Club and Club.GetGuildClubId and Club.GetClubMembers and Club.GetMemberInfo) then return end
    if not (CreatureInfo and CreatureInfo.GetClassInfo) then return end

    local okClub, clubId = pcall(Club.GetGuildClubId)
    if not okClub or IsSecret(clubId) or clubId == nil then return end
    local okMembers, members = pcall(Club.GetClubMembers, clubId)
    if not okMembers or IsSecret(members) or type(members) ~= "table" then return end

    for i = 1, #members do
        local memberId = members[i]
        if not IsSecret(memberId) and type(memberId) == "number" then
            local okInfo, info = pcall(Club.GetMemberInfo, clubId, memberId)
            if okInfo and not IsSecret(info) and type(info) == "table" then
                local name, classID = info.name, info.classID
                if not IsSecret(name) and type(name) == "string" and name ~= ""
                    and not IsSecret(classID) and type(classID) == "number" then
                    local okClass, classInfo = pcall(CreatureInfo.GetClassInfo, classID)
                    if okClass and not IsSecret(classInfo) and type(classInfo) == "table" then
                        StoreNameClassAliases(name, classInfo.classFile)
                    end
                end
            end
        end
    end
end

function Format.SeedKnownClasses(includeGuild)
    SeedUnitClass("player")
    if _G.IsInRaid and _G.IsInRaid() then
        for i = 1, 40 do SeedUnitClass("raid" .. i) end
    elseif _G.IsInGroup and _G.IsInGroup() then
        for i = 1, 4 do SeedUnitClass("party" .. i) end
    end
    if includeGuild ~= false then
        SeedGuildMemberClasses()
    end
end

local function ResolveSenderClass(guid, name)
    local cname = CacheableName(name)
    local secret = IsSecret(guid)
    if not secret then
        local cached = guidClassCache[guid]
        if cached then
            if cname then StoreNameClassVariants(cname, cached) end
            return cached
        end
    end
    if _G.GetPlayerInfoByGUID then
        local ok, _, englishClass = pcall(_G.GetPlayerInfoByGUID, guid)
        if ok
            and (IsSecret(englishClass) or (type(englishClass) == "string" and englishClass ~= "")) then
            if not IsSecret(englishClass) then
                if not secret then StoreGuidClass(guid, englishClass) end
                if cname then StoreNameClassVariants(cname, englishClass) end
            end
            return englishClass
        end
    end
    if _G.UnitClassFromGUID then
        local ok, _, englishClass = pcall(_G.UnitClassFromGUID, guid)
        if ok
            and (IsSecret(englishClass) or (type(englishClass) == "string" and englishClass ~= "")) then
            if not IsSecret(englishClass) then
                if not secret then StoreGuidClass(guid, englishClass) end
                if cname then StoreNameClassVariants(cname, englishClass) end
            end
            return englishClass
        end
    end
    local byName = LookupNameClass(cname)
    if byName then return byName end
    return nil
end

local function ColorizeSenderName(guid, name, text)
    local guidSecret = IsSecret(guid)
    if not guidSecret and not guid then return text end
    local settings = I.GetSettings and I.GetSettings()
    local mods = settings and settings.modifiers
    local classColors = mods and mods.classColors
    if classColors and classColors.enabled == false then return text end
    local englishClass = ResolveSenderClass(guid, name)
    local clsSecret = IsSecret(englishClass)
    if not clsSecret and not englishClass then return text end
    if _G.C_ClassColor and _G.C_ClassColor.GetClassColor then
        local ok, color = ns.SafeCall("best-effort-style", _G.C_ClassColor.GetClassColor, englishClass)
        if ok and type(color) == "table" and color.WrapTextInColorCode then
            local ok2, wrapped = pcall(color.WrapTextInColorCode, color, text)
            if ok2 and (IsSecret(wrapped) or wrapped) then return wrapped end
        end
    end
    if not IsSecret(englishClass) then
        local cc = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[englishClass]
        local colorStr = cc and cc.colorStr
        if type(colorStr) == "string" then
            return ("|c%s%s|r"):format(colorStr, text)
        end
    end
    return text
end

local DISCORD_GLOBAL_NAME_TYPE =
    (_G.Enum and _G.Enum.DiscordDisplayNameType and _G.Enum.DiscordDisplayNameType.GlobalName) or 2

local function DiscordNameColorize(name)
    local r255, g255, b255 = 224, 227, 255
    local CI = _G.C_ChatInfo
    if CI and CI.GetColorForChatType then
        local ok, colorInfo = pcall(CI.GetColorForChatType, "DISCORD_PLAYER_NAME")
        if ok and not IsSecret(colorInfo) and type(colorInfo) == "table"
            and type(colorInfo.r) == "number" and type(colorInfo.g) == "number"
            and type(colorInfo.b) == "number" then
            r255, g255, b255 = colorInfo.r * 255, colorInfo.g * 255, colorInfo.b * 255
        end
    end
    local hex = ("ff%02x%02x%02x"):format(
        math.floor(r255 + 0.5) % 256, math.floor(g255 + 0.5) % 256, math.floor(b255 + 0.5) % 256)
    return ("|c%s%s|r"):format(hex, name)
end

function Format.DecorateSender(event, ...)
    local _, sender = ...
    if IsSecret(sender) or type(sender) ~= "string" or sender == "" then return nil end
    local typeKey = Format.EventToTypeKey(event)
    local decorated = sender
    if _G.Ambiguate then
        local mode = ShowRealmNames()
            and (typeKey == "GUILD" and "guild" or "none")
            or "short"
        local ok, short = ns.SafeCall("best-effort-style", _G.Ambiguate, sender, mode)
        if ok and type(short) == "string" and short ~= "" then decorated = short end
    end
    local guid = select(12, ...)
    local classLookupName = sender

    local discordInfo = select(15, ...)
    if IsFromDiscord(discordInfo) then
        local shouldShowGlobalName = not IsSecret(discordInfo.type) and discordInfo.type == DISCORD_GLOBAL_NAME_TYPE
        local globalName = discordInfo.globalName
        if shouldShowGlobalName and not IsSecret(globalName)
            and type(globalName) == "string" and globalName ~= "" then
            return DiscordNameColorize(globalName)
        end
        local lastOnlineGUID = discordInfo.lastOnlineGUID
        if not IsSecret(lastOnlineGUID) and type(lastOnlineGUID) == "string" and lastOnlineGUID ~= "" then
            guid = lastOnlineGUID
            classLookupName = nil
        end
        local lastOnlineName = discordInfo.lastOnlineName
        if not IsSecret(lastOnlineName) and type(lastOnlineName) == "string" and lastOnlineName ~= "" then
            decorated = lastOnlineName
            classLookupName = lastOnlineName
        end
    end

    if not IsSecret(guid) and type(guid) == "string" and guid ~= ""
        and _G.C_ChatInfo and _G.C_ChatInfo.IsTimerunningPlayer
        and _G.TimerunningUtil and _G.TimerunningUtil.AddSmallIcon then
        local ok, isTR = ns.SafeCall("best-effort-style", _G.C_ChatInfo.IsTimerunningPlayer, guid)
        if ok and isTR then
            local ok2, marked = ns.SafeCall("best-effort-style", _G.TimerunningUtil.AddSmallIcon, decorated)
            if ok2 and type(marked) == "string" and marked ~= "" then decorated = marked end
        end
    end
    -- @secret-policy: drop-color-when-secret (readable name preserved; combat
    local colored = ColorizeSenderName(guid, classLookupName, decorated)
    if not IsSecret(colored) then decorated = colored end
    local util = _G.ChatFrameUtil
    if util and util.ProcessSenderNameFilters then
        local ok, filtered = ns.SafeCall("best-effort-style", util.ProcessSenderNameFilters, event, decorated, ...)
        if ok and type(filtered) == "string" and filtered ~= "" then decorated = filtered end
    end
    return decorated
end

function Format.BuildPayloadFromArgs(event, ...)
    local a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18 = ...
    local p = {
        text = a1,
        rawSender = a2,
        sender = (not IsSecret(a2)) and type(a2) == "string" and a2 ~= "" and a2 or nil,
        language = (not IsSecret(a3)) and type(a3) == "string" and a3 or nil,
        channelFull = (not IsSecret(a4)) and type(a4) == "string" and a4 or nil,
        target = (not IsSecret(a5)) and type(a5) == "string" and a5 or nil,
        flags = (not IsSecret(a6)) and type(a6) == "string" and a6 or nil,
        zoneID = (not IsSecret(a7)) and type(a7) == "number" and a7 or nil,
        chNum = (not IsSecret(a8)) and type(a8) == "number" and a8 or nil,
        chBase = (not IsSecret(a9)) and type(a9) == "string" and a9 ~= "" and a9 or nil,
        lineID = (not IsSecret(a11)) and type(a11) == "number" and a11 or nil,
        guid = (not IsSecret(a12)) and type(a12) == "string" and a12 ~= "" and a12 or nil,
        rawGuid = a12,
        bnID = (not IsSecret(a13)) and type(a13) == "number" and a13 or nil,
        suppressIcons = (not IsSecret(a17)) and a17 and true or nil,
        isSubtitle = a15 and true or nil,
        hideSenderInLetterbox = a16 and true or nil,
        discordInfo = a18,
        isFromDiscord = IsFromDiscord(a18),
    }
    if p.chBase then
        local Registry = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.ChannelRegistry
        p.chName = Registry and Registry.ResolveName
            and Registry.ResolveName(p.chNum, p.chBase) or p.chBase
    end
    p.decorated = Format.DecorateSender(event, a1, a2, a3, a4, a5, a6, a7,
        a8, a9, a10, a11, a12, a13, a14, a18)
    return p
end

local BOSS_NOTICE_EVENTS = {
    RAID_BOSS_EMOTE = true,
    RAID_BOSS_WHISPER = true,
    QUEST_BOSS_EMOTE = true,
}

local TYPE_PREFIX = {
    GUILD = "[G] ",
    GUILD_DISCORD = "[GD] ",
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

function Format.ColorForTypeKey(typeKey, chName)
    local CC = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.ChannelColors
    if CC and CC.HasOverride and CC.GetEffective then
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
    local info = typeKey and _G.ChatTypeInfo and _G.ChatTypeInfo[typeKey]
    if info then
        return info.r or 1, info.g or 1, info.b or 1
    end
    return 1, 1, 1
end

ns.QUI.Chat._typeColorResolver = function(typeKey, chName)
    return Format.ColorForTypeKey(typeKey, chName)
end

local defaultLanguage, alternativeDefaultLanguage

function Format.RefreshLanguages()
    if _G.GetDefaultLanguage then
        local ok, lang = ns.SafeCall("best-effort-style", _G.GetDefaultLanguage)
        if ok and type(lang) == "string" then defaultLanguage = lang end
    end
    if _G.GetAlternativeDefaultLanguage then
        local ok, lang = ns.SafeCall("best-effort-style", _G.GetAlternativeDefaultLanguage)
        if ok and type(lang) == "string" then alternativeDefaultLanguage = lang end
    end
end

local function RelevantDefaultLanguage(typeKey)
    if defaultLanguage == nil and alternativeDefaultLanguage == nil then
        Format.RefreshLanguages()
    end
    if typeKey == "SAY" or typeKey == "YELL" then
        return alternativeDefaultLanguage
    end
    return defaultLanguage
end

local function PFlag(flags, zoneID, chNum)
    if type(flags) ~= "string" or flags == "" then return "" end
    local util = _G.ChatFrameUtil
    if util and util.GetPFlag then
        local ok, pflag = ns.SafeCall("chain-next", util.GetPFlag, flags, zoneID or 0, chNum or 0)
        if ok and type(pflag) == "string" then return pflag end
    end
    local gs = _G["CHAT_FLAG_" .. flags]
    return type(gs) == "string" and gs or ""
end

local function EscapeFormatTokens(msg)
    if _G.C_StringUtil and _G.C_StringUtil.EscapeLuaFormatString then
        local ok, escaped = ns.SafeCall("chain-next", _G.C_StringUtil.EscapeLuaFormatString, msg)
        if ok and type(escaped) == "string" then return escaped end
    end
    return (msg:gsub("%%", "%%%%"))
end

local function CanExpandExpressions(chatGroup)
    local util = _G.ChatFrameUtil
    if util and util.CanChatGroupPerformExpressionExpansion then
        local ok, can = ns.SafeCall("chain-next", util.CanChatGroupPerformExpressionExpansion, chatGroup)
        if ok then return can and true or false end
    end
    return chatGroup == "RAID"
end

local function ExpandIconExpressions(msg, suppressIcons, chatGroup)
    if _G.C_ChatInfo and _G.C_ChatInfo.ReplaceIconAndGroupExpressions then
        local ok, replaced = ns.SafeCall("chain-next", _G.C_ChatInfo.ReplaceIconAndGroupExpressions,
            msg, suppressIcons and true or false, not CanExpandExpressions(chatGroup))
        if ok and type(replaced) == "string" then return replaced end
    end
    return msg
end

local function CollapseSpaces(msg)
    if _G.C_StringUtil and _G.C_StringUtil.RemoveContiguousSpaces then
        local ok, trimmed = ns.SafeCall("chain-next", _G.C_StringUtil.RemoveContiguousSpaces, msg, 4)
        if ok and type(trimmed) == "string" then return trimmed end
    end
    return (msg:gsub("     +", "    "))
end

local DISCORD_MARKER_ORDER = {
    { flag = "hasAttachment", gs = "DISCORD_MESSAGE_ATTACHMENT" },
    { flag = "hasPoll", gs = "DISCORD_MESSAGE_POLL" },
    { flag = "hasEmbed", gs = "DISCORD_MESSAGE_EMBED" },
    { flag = "hasSticker", gs = "DISCORD_MESSAGE_STICKER" },
    { flag = "hasEmoji", gs = "DISCORD_MESSAGE_EMOJI" },
    { flag = "hasForwardedMessage", gs = "DISCORD_MESSAGE_FORWARD" },
}

local function DiscordMarkerText(globalStringName, body)
    local gs = _G[globalStringName]
    if type(gs) ~= "string" or gs == "" then return body end
    local label = gs
    local color = _G.YELLOW_FONT_COLOR
    if type(color) == "table" and color.WrapTextInColorCode then
        local ok, wrapped = ns.SafeCallMethod("best-effort-style", color, "WrapTextInColorCode", gs)
        if ok and type(wrapped) == "string" and wrapped ~= "" then label = wrapped end
    end
    return ("%s %s"):format(label, body)
end

local function FormatDiscordMessage(discordInfo, message)
    if IsSecret(discordInfo) or type(discordInfo) ~= "table" then return message end
    local fromDiscord = discordInfo.fromDiscord
    if IsSecret(fromDiscord) or not fromDiscord then return message end
    local modified = message
    for i = 1, #DISCORD_MARKER_ORDER do
        local entry = DISCORD_MARKER_ORDER[i]
        local flagValue = discordInfo[entry.flag]
        if not IsSecret(flagValue) and flagValue then
            if entry.flag == "hasForwardedMessage" then
                local forwarded = discordInfo.forwardedMessage
                local body = (not IsSecret(forwarded) and type(forwarded) == "string" and forwarded ~= "")
                    and forwarded or message
                modified = DiscordMarkerText(entry.gs, body)
            else
                modified = DiscordMarkerText(entry.gs, message)
            end
        end
    end
    return modified
end

local function ResolvePrefixedChannelName(channelFull)
    local util = _G.ChatFrameUtil
    if util and util.ResolvePrefixedChannelName then
        local ok, resolved = ns.SafeCall("chain-next", util.ResolvePrefixedChannelName, channelFull)
        if ok and type(resolved) == "string" and resolved ~= "" then return resolved end
    end
    return channelFull
end

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

local function LetterChannelLabel(name)
    if name:find("Services", 1, true) then return "S" end
    if name:sub(1, 5) == "Trade" then return "T" end
    if name:sub(1, 7) == "General" then return "Gen" end
    if name:sub(1, 12) == "LocalDefense" then return "LD" end
    if name:sub(1, 12) == "WorldDefense" then return "WD" end
    if name:sub(1, 15) == "LookingForGroup" then return "LFG" end
    return UTF8Prefix(name, 3)
end

local function HasChannelContext(p, typeKey)
    if type(p.channelFull) == "string" and p.channelFull ~= "" then return true end
    return (typeKey == "CHANNEL" or typeKey == "COMMUNITIES_CHANNEL")
        and type(p.chName) == "string" and p.chName ~= ""
end

local function ChannelDecoration(p)
    local num = p.chNum
    if type(num) ~= "number" or num <= 0 then
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

local function GetOutMessageFormatKey(typeKey)
    local direct = _G["CHAT_" .. typeKey .. "_GET"]
    if type(direct) ~= "string" or direct == "" then
        return "%s "
    end
    local util = _G.ChatFrameUtil and _G.ChatFrameUtil.GetOutMessageFormatKey
    if type(util) == "function" then
        local ok, fmt = ns.SafeCall("chain-next", util, typeKey)
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
    if fmt == "%s " then fmt = "%s: " end
    return fmt
end

local function BracketedPlayerLink(name, shown)
    return ("|Hplayer:%s|h[%s]|h"):format(name, shown)
end

local function ChatTargetFor(chatGroup, sender, chNum)
    if chatGroup == "CHANNEL" then
        return type(chNum) == "number" and tostring(chNum) or ""
    end
    if (chatGroup == "WHISPER" or chatGroup == "BN_WHISPER")
        and not IsSecret(sender) and type(sender) == "string" then
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
        return linkDisplayText
    end
    if (typeKey == "GUILD_DISCORD" or typeKey == "GUILD") and p.isFromDiscord then
        local lid = type(p.lineID) == "number" and p.lineID or 0
        local target = ChatTargetFor(chatGroup, sender, p.chNum)
        local bnID = type(p.bnID) == "number" and p.bnID or 0
        return ("|Hdiscorduser:%s:%s:%d:%s:%s|h%s|h"):format(
            bnID, p.discordInfo.userID, lid, chatGroup, target, linkDisplayText)
    end
    if typeKey == "COMMUNITIES_CHANNEL" then
        if _G.C_Club and _G.C_Club.GetInfoFromLastCommunityChatLine then
            local ok, messageInfo, clubId, streamId = ns.SafeCall("chain-next", _G.C_Club.GetInfoFromLastCommunityChatLine)
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

local function BuildSecretSenderLink(p)
    if not IsSecret(p.rawSender) then return nil end
    local guid = p.rawGuid
    local guidSecret = IsSecret(guid)
    if not guidSecret and not guid then guid = p.guid end
    if not IsSecret(p.text) and not guidSecret and not guid then return nil end
    local shown = string.format("[%s]", p.rawSender)
    shown = ColorizeSenderName(guid, p.sender, shown)
    return string.format("|Hplayer:%s|h%s|h", p.rawSender, shown)
end

local function FormatNormalLine(event, typeKey, p)
    local text = p.text
    local chatGroup = ChatCategory(typeKey)
    local isMonster = IsMonsterOrRaidBossType(typeKey)
    local showLink = not isMonster

    if typeKey == "VOICE_TEXT" and _G.GetCVarBool then
        local ok, enabled = ns.SafeCall("chain-next", _G.GetCVarBool, "speechToText")
        if ok and not enabled then return nil end
    end

    if type(p.lineID) == "number" and _G.C_ChatInfo and _G.C_ChatInfo.IsChatLineCensored then
        local ok, censored = ns.SafeCall("chain-next", _G.C_ChatInfo.IsChatLineCensored, p.lineID)
        if ok and censored then return text end
    end

    local msg = text
    if showLink then
        msg = EscapeFormatTokens(msg)
    end
    msg = ExpandIconExpressions(msg, p.suppressIcons, chatGroup)
    msg = CollapseSpaces(msg)
    if p.isFromDiscord then
        msg = FormatDiscordMessage(p.discordInfo, msg)
    end

    local pflag = PFlag(p.flags, p.zoneID, p.chNum)
    local sender = type(p.sender) == "string" and p.sender or ""
    local usingDifferentLanguage = type(p.language) == "string" and p.language ~= ""
        and p.language ~= RelevantDefaultLanguage(typeKey)

    if showLink and sender == "" and typeKey ~= "TEXT_EMOTE" then
        local secretLink = BuildSecretSenderLink(p)
        if IsSecret(secretLink) or secretLink then
            local linkWithFlag = string.format("%s%s", pflag, secretLink)
            local fmt = OutFormat(typeKey)
            if usingDifferentLanguage then
                fmt = fmt .. ("[%s] "):format(p.language)
            end
            local prefix = string.format(fmt, linkWithFlag)
            if HasChannelContext(p, typeKey) then
                local deco = ChannelDecoration(p)
                if deco ~= "" then
                    prefix = string.format("%s%s", deco, prefix)
                end
            end
            return string.format("%s%s", prefix, msg)
        end
        if HasChannelContext(p, typeKey) then
            return ChannelDecoration(p) .. msg
        end
        return msg
    end

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
                outMsg = (msg:gsub("%$s", ("|Hplayer:%s|h%s|h"):format(sender, linkDisplayText)))
            elseif typeKey == "GUILD_DISCORD" and p.isFromDiscord then
                outMsg = FormatString(fmt .. msg, pflag .. " " .. playerLink)
            else
                outMsg = FormatString(fmt .. msg, pflag .. playerLink)
            end
        end
    end
    if not outMsg then return nil end

    if HasChannelContext(p, typeKey) then
        outMsg = ChannelDecoration(p) .. outMsg
    end
    return outMsg
end

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
        if text == "FRIEND_PENDING" then
            local n = (_G.BNGetNumFriendInvites and _G.BNGetNumFriendInvites()) or 0
            return FormatString(gs, n)
        end
        if text == "FRIEND_REMOVED" or text == "BATTLETAG_FRIEND_REMOVED" then
            if type(sender) ~= "string" or sender == "" then return nil end
            return FormatString(gs, sender)
        end
        if not gs:find("%%s") then return gs end
        if type(sender) ~= "string" or sender == "" then return nil end
        local part = BNToastPlayerLink(sender, p.bnID, p.lineID, typeKey)
        if not part then return nil end
        if (text == "FRIEND_ONLINE" or text == "FRIEND_OFFLINE")
            and type(p.bnID) == "number"
            and _G.C_BattleNet and _G.C_BattleNet.GetAccountInfoByID then
            local okA, info = ns.SafeCall("chain-next", _G.C_BattleNet.GetAccountInfoByID, p.bnID)
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

function Format.WrapSecretEventLine(event, p)
    if type(p) ~= "table" then return nil end
    local text = p.text
    if not IsSecret(text) then return text end
    local typeKey = Format.EventToTypeKey(event)
    if not typeKey then return text end

    if BOSS_NOTICE_EVENTS[event] or SPECIAL_KIND[typeKey] then
        return text
    end

    local prefix
    if IsMonsterOrRaidBossType(typeKey) then
        prefix = string.format(GetOutMessageFormatKey(typeKey), p.rawSender)
    elseif typeKey == "EMOTE" then
        local who = p.rawSender
        if p.sender then
            who = PFlag(p.flags, p.zoneID, p.chNum)
                .. (BuildPlayerLink(typeKey, ChatCategory(typeKey), p, p.decorated or p.sender) or p.sender)
        end
        prefix = string.format(GetOutMessageFormatKey(typeKey), who)
    elseif IsRawType(typeKey) or typeKey == "TEXT_EMOTE" then
        return text
    else
        local chatGroup = ChatCategory(typeKey)
        local pflag = PFlag(p.flags, p.zoneID, p.chNum)
        local link
        if type(p.sender) == "string" and p.sender ~= "" then
            link = BuildPlayerLink(typeKey, chatGroup, p, ("[%s]"):format(p.decorated or p.sender))
        elseif IsSecret(p.rawSender) then
            link = BuildSecretSenderLink(p)
        end
        local linkSecret = IsSecret(link)
        if linkSecret or link then
            prefix = string.format(OutFormat(typeKey), string.format("%s%s", pflag, link))
        elseif TYPE_PREFIX[typeKey] then
            prefix = TYPE_PREFIX[typeKey]
        end
        if HasChannelContext(p, typeKey) then
            local deco = ChannelDecoration(p)
            if deco ~= "" then
                if IsSecret(prefix) or prefix then
                    prefix = string.format("%s%s", deco, prefix)
                else
                    prefix = deco
                end
            end
        end
    end

    if not IsSecret(prefix) and not prefix then return text end
    return string.format("%s%s", prefix, text)
end

function Format.BuildEventLineFromArgs(event, ...)
    local p = Format.BuildPayloadFromArgs(event, ...)
    local typeKey = Format.EventToTypeKey(event)
    local text = p.text
    if IsSecret(text) then
        if typeKey == "BN_INLINE_TOAST_ALERT" then return nil, p, true end
        return Format.WrapSecretEventLine(event, p), p, true
    end
    if type(text) ~= "string" or text == "" then return nil, p, false end
    -- @secret-policy: line-secrecy-follows-any-secret-part
    local line = Format.BuildEventLine(event, p)
    if IsSecret(line) then return line, p, true end
    return line, p, false
end
