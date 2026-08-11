local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: message_capture.lua loaded before chat.lua. Check chat.xml — chat.lua must precede message_capture.lua.")

ns.QUI.Chat.MessageCapture = ns.QUI.Chat.MessageCapture or {}
local Capture = ns.QUI.Chat.MessageCapture

local Store = assert(ns.QUI.Chat.MessageStore, "message_store.lua must load before message_capture.lua")
local Format = assert(ns.QUI.Chat.MessageFormat, "message_format.lua must load before message_capture.lua")
local Registry = ns.QUI.Chat.ChannelRegistry

local function IsSecret(v)
    return Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(v) or false
end

local function Now()
    return (_G.GetServerTime and _G.GetServerTime()) or time()
end

local function FormatString(fmt, ...)
    local ok, formatted = ns.SafeCall("report", string.format, fmt, ...)
    if not ok then return nil end
    return formatted
end

local EXTRA_EVENTS = {
    "CHAT_MSG_CHANNEL",
    "CHAT_MSG_COMMUNITIES_CHANNEL",
    "CHAT_MSG_SYSTEM",
    "CHAT_MSG_BN_INLINE_TOAST_ALERT",
    "CHAT_MSG_BN_INLINE_TOAST_BROADCAST",
    "CHAT_MSG_BN_INLINE_TOAST_BROADCAST_INFORM",
    "CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE",
    "RAID_BOSS_EMOTE",
    "RAID_BOSS_WHISPER",
    "QUEST_BOSS_EMOTE",
}

local captureFrame
local fallbackHooked = false

local function CaptureActive()
    local settings = I.GetSettings and I.GetSettings()
    if not (I.IsChatEnabled and I.IsChatEnabled(settings)) then return false end
    return true
end

local function AppendSystemLine(event, line, typeKey)
    local secretBody = IsSecret(line)
    if not secretBody and (type(line) ~= "string" or line == "") then return end
    typeKey = typeKey or "SYSTEM"
    local r, g, b = Format.ColorForTypeKey(typeKey)
    if I.AddTimestamp then
        line = (I.AddTimestamp(line))
    end
    Store.Append({ m = line, r = r, g = g, b = b, e = event, k = typeKey,
        s = secretBody or nil, t = Now() })
end

local function GlobalString(name)
    local gs = _G[name]
    return type(gs) == "string" and gs or nil
end

local function TimeBreakDown(t)
    local days = math.floor(t / 86400)
    local hours = math.floor((t % 86400) / 3600)
    local minutes = math.floor((t % 3600) / 60)
    local seconds = math.floor(t % 60)
    return days, hours, minutes, seconds
end

local seenMotd

local pendingMotd, hasPendingMotd

local syncedTypeColors = {}

local function GuildColorReady()
    local CC = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.ChannelColors
    if CC and CC.HasOverride and CC.HasOverride("GUILD") then return true end
    if syncedTypeColors.GUILD then return true end
    local info = _G.ChatTypeInfo and _G.ChatTypeInfo.GUILD
    return info ~= nil and info.r ~= nil
end

local SYSTEM_EVENTS = {}

SYSTEM_EVENTS.TIME_PLAYED_MSG = function(event, totalTime, levelTime)
    local Suppress = ns.QUI.Chat.BlizzardSuppress
    if Suppress and Suppress.TimePlayedWanted and not Suppress.TimePlayedWanted() then
        return
    end
    local dayFmt = GlobalString("TIME_DAYHOURMINUTESECOND")
    local totalFmt, levelFmt = GlobalString("TIME_PLAYED_TOTAL"), GlobalString("TIME_PLAYED_LEVEL")
    if not dayFmt then return end
    if not IsSecret(totalTime) and type(totalTime) == "number" and totalFmt then
        local d, h, m, s = TimeBreakDown(totalTime)
        AppendSystemLine(event, FormatString(totalFmt, FormatString(dayFmt, d, h, m, s) or ""))
    end
    if not IsSecret(levelTime) and type(levelTime) == "number" and levelFmt then
        local d, h, m, s = TimeBreakDown(levelTime)
        AppendSystemLine(event, FormatString(levelFmt, FormatString(dayFmt, d, h, m, s) or ""))
    end
end

SYSTEM_EVENTS.PLAYER_LEVEL_CHANGED = function(event, oldLevel, newLevel, real)
    if IsSecret(oldLevel) or IsSecret(newLevel) or IsSecret(real) then return end
    if not (real and type(oldLevel) == "number" and type(newLevel) == "number") then return end
    if oldLevel == 0 or newLevel == 0 or newLevel <= oldLevel then return end
    local noLink = false
    if _G.C_GameRules and _G.C_GameRules.IsGameRuleActive and _G.Enum
        and _G.Enum.GameRule and _G.Enum.GameRule.ChatLinkLevelToastsDisabled then
        local ok, active = ns.SafeCall("best-effort-style", _G.C_GameRules.IsGameRuleActive, _G.Enum.GameRule.ChatLinkLevelToastsDisabled)
        noLink = ok and active or false
    end
    if not noLink and _G.C_PlayerInfo and _G.C_PlayerInfo.IsPlayerNPERestricted then
        local ok, restricted = ns.SafeCall("best-effort-style", _G.C_PlayerInfo.IsPlayerNPERestricted)
        noLink = ok and restricted or false
    end
    local line
    if noLink then
        line = FormatString(GlobalString("LEVEL_UP_NO_LINK") or "", newLevel)
    else
        line = FormatString(GlobalString("LEVEL_UP") or "", newLevel, newLevel)
    end
    AppendSystemLine(event, line)
end

SYSTEM_EVENTS.GUILD_MOTD = function(event, motd)
    if not GuildColorReady() then
        if IsSecret(motd) or (type(motd) == "string" and motd ~= "") then
            pendingMotd, hasPendingMotd = motd, true
        end
        return
    end
    local fmt = GlobalString("GUILD_MOTD_TEMPLATE")
    if not fmt then return end
    if IsSecret(motd) then
        if seenMotd == true then return end
        seenMotd = true
        AppendSystemLine(event, FormatString(fmt, motd), "GUILD")
        return
    end
    if type(motd) ~= "string" or motd == "" or motd == seenMotd then return end
    seenMotd = motd
    AppendSystemLine(event, FormatString(fmt, motd), "GUILD")
end

local function MaybePullGMOTD()
    if seenMotd ~= nil or hasPendingMotd then return end
    if _G.IsInGuild and not _G.IsInGuild() then return end
    local CC = _G.C_Club
    if not (CC and CC.GetGuildClubId and CC.GetClubInfo) then return end
    local guildClubId = CC.GetGuildClubId()
    if not guildClubId then return end
    local info = CC.GetClubInfo(guildClubId)
    if not info then return end
    SYSTEM_EVENTS.GUILD_MOTD("GUILD_MOTD", info.broadcast)
end

SYSTEM_EVENTS.UPDATE_CHAT_WINDOWS = function() MaybePullGMOTD() end
SYSTEM_EVENTS.CHANNEL_UI_UPDATE = function() MaybePullGMOTD() end
SYSTEM_EVENTS.CHANNEL_LEFT = function() MaybePullGMOTD() end
SYSTEM_EVENTS.GUILD_ROSTER_UPDATE = function()
    if Format.SeedKnownClasses then Format.SeedKnownClasses(true) end
    MaybePullGMOTD()
end
SYSTEM_EVENTS.PLAYER_GUILD_UPDATE = function() MaybePullGMOTD() end

local function FlushPendingMotd()
    if not (hasPendingMotd and CaptureActive() and GuildColorReady()) then return end
    local motd = pendingMotd
    pendingMotd, hasPendingMotd = nil, false
    SYSTEM_EVENTS.GUILD_MOTD("GUILD_MOTD", motd)
end

local pendingColorTypes, colorSyncQueued

local REBAKE_SKIP_EVENTS = { ADDMESSAGE = true, BACKFILL = true, HISTORY = true }

local function ResolveSyncedColor(typeKey)
    local CC = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.ChannelColors
    if CC and CC.HasOverride and CC.GetEffective and CC.HasOverride(typeKey) then
        return CC.GetEffective(typeKey)
    end
    local c = syncedTypeColors[typeKey]
    if c then return c[1], c[2], c[3] end
    return Format.ColorForTypeKey(typeKey)
end

local function DrainColorSync()
    colorSyncQueued = nil
    local types = pendingColorTypes
    pendingColorTypes = nil
    if not (types and CaptureActive()) then return end
    FlushPendingMotd()
    local resolved = {}
    for typeKey in pairs(types) do
        local r, g, b = ResolveSyncedColor(typeKey)
        resolved[typeKey] = { r, g, b }
    end
    local changed = 0
    Store.ForEach(function(entry)
        local c = entry.k and resolved[entry.k]
        if c and not REBAKE_SKIP_EVENTS[entry.e] then
            if entry.r ~= c[1] or entry.g ~= c[2] or entry.b ~= c[3] then
                entry.r, entry.g, entry.b = c[1], c[2], c[3]
                changed = changed + 1
            end
        end
    end)
    if changed > 0 then
        local TM = ns.QUI.Chat.TabManager
        if TM and TM.ReapplyAll then TM.ReapplyAll() end
    end
end

SYSTEM_EVENTS.UPDATE_CHAT_COLOR = function(_, chatType, r, g, b)
    if IsSecret(chatType) or type(chatType) ~= "string" then return end
    local typeKey = chatType:upper()
    if typeKey == "CHANNEL" or typeKey == "CHANNEL_NOTICE" then return end
    if not (IsSecret(r) or IsSecret(g) or IsSecret(b))
        and type(r) == "number" and type(g) == "number" and type(b) == "number" then
        syncedTypeColors[typeKey] = { r, g, b }
    end
    pendingColorTypes = pendingColorTypes or {}
    pendingColorTypes[typeKey] = true
    if colorSyncQueued then return end
    colorSyncQueued = true
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0, DrainColorSync)
    else
        DrainColorSync()
    end
end

SYSTEM_EVENTS.CHAT_SERVER_DISCONNECTED = function(event)
    AppendSystemLine(event, GlobalString("CHAT_SERVER_DISCONNECTED_MESSAGE"))
end

SYSTEM_EVENTS.CHAT_SERVER_RECONNECTED = function(event)
    AppendSystemLine(event, GlobalString("CHAT_SERVER_RECONNECTED_MESSAGE"))
end

SYSTEM_EVENTS.BN_CONNECTED = function(event, suppressNotification)
    if not IsSecret(suppressNotification) and suppressNotification then return end
    AppendSystemLine(event, GlobalString("BN_CHAT_CONNECTED"))
end

SYSTEM_EVENTS.BN_DISCONNECTED = function(event, _, suppressNotification)
    if not IsSecret(suppressNotification) and suppressNotification then return end
    AppendSystemLine(event, GlobalString("BN_CHAT_DISCONNECTED"))
end

local function RegionalUnavailableLine()
    if _G.GetRegionalChatUnavailableString then
        local ok, s = ns.SafeCall("chain-next", _G.GetRegionalChatUnavailableString)
        if ok and type(s) == "string" then return s end
    end
    return nil
end

SYSTEM_EVENTS.CHAT_REGIONAL_STATUS_CHANGED = function(event, isServiceAvailable)
    if IsSecret(isServiceAvailable) then return end
    if isServiceAvailable then
        if _G.GetRegionalChatAvailableString then
            local ok, s = ns.SafeCall("best-effort-style", _G.GetRegionalChatAvailableString)
            if ok and type(s) == "string" then AppendSystemLine(event, s) end
        end
    else
        AppendSystemLine(event, RegionalUnavailableLine())
    end
end

SYSTEM_EVENTS.CHAT_REGIONAL_SEND_FAILED = function(event)
    AppendSystemLine(event, RegionalUnavailableLine())
end

SYSTEM_EVENTS.NOTIFY_CHAT_SUPPRESSED = function(event)
    local linkLabel = GlobalString("RESTRICT_CHAT_CONFIG_HYPERLINK")
    local fmt = GlobalString("RESTRICT_CHAT_CHATFRAME_FORMAT")
    local body = GlobalString("RESTRICT_CHAT_MESSAGE_SUPPRESSED")
    if not (linkLabel and fmt and body) then return end
    local hyperlink = ("|Haadcopenconfig|h[%s]"):format(linkLabel)
    local color = _G.LIGHTBLUE_FONT_COLOR
    if color and color.WrapTextInColorCode then
        hyperlink = color:WrapTextInColorCode(hyperlink)
    end
    AppendSystemLine(event, FormatString(fmt, body, hyperlink))
end

SYSTEM_EVENTS.PLAYER_ENTERING_WORLD = function()
    if Format.RefreshLanguages then Format.RefreshLanguages() end
    if Format.SeedKnownClasses then Format.SeedKnownClasses() end
    MaybePullGMOTD()
end

SYSTEM_EVENTS.GROUP_ROSTER_UPDATE = function()
    if Format.SeedKnownClasses then Format.SeedKnownClasses(false) end
end

SYSTEM_EVENTS.ALTERNATIVE_DEFAULT_LANGUAGE_CHANGED = function()
    if Format.RefreshLanguages then Format.RefreshLanguages() end
end

SYSTEM_EVENTS.PLAYER_REPORT_SUBMITTED = function(_, reportedGUID)
    if IsSecret(reportedGUID) or type(reportedGUID) ~= "string" or reportedGUID == "" then return end
    local removed = Store.RemoveWhere and Store.RemoveWhere(function(entry)
        return entry.gid == reportedGUID
    end) or 0
    if removed > 0 then
        local TM = ns.QUI.Chat.TabManager
        if TM and TM.ReapplyAll then TM.ReapplyAll() end
    end
end

local function MaybeAutoAddChannel(event, p)
    if event ~= "CHAT_MSG_CHANNEL_NOTICE" then return end
    if IsSecret(p.text) or p.text ~= "YOU_CHANGED" then return end
    if type(p.zoneID) ~= "number" or p.zoneID <= 0 then return end
    local CI = _G.C_ChatInfo
    if not (CI and CI.IsChannelRegionalForChannelID) then return end
    local ok, regional = ns.SafeCall("best-effort-style", CI.IsChannelRegionalForChannelID, p.zoneID)
    if not ok or not regional then return end
    if Registry and Registry.Refresh then Registry.Refresh() end
    local name = p.chName or p.chBase
    local TM = ns.QUI.Chat.TabManager
    if TM and TM.EnsureDefaultChannelListed and type(name) == "string" and name ~= "" then
        TM.EnsureDefaultChannelListed(name)
    end
end

local WHISPER_POPOUT_KEYS = I.WHISPER_TYPE_KEYS

local function GetWhisperMode()
    if type(_G.GetCVar) ~= "function" then return nil end
    local ok, value = ns.SafeCall("chain-next", _G.GetCVar, "whisperMode")
    if ok then return value end
    return nil
end

local function ShouldTranslateBlizzardWhisperPopouts()
    local settings = I.GetSettings and I.GetSettings()
    local wt = settings and settings.customDisplay and settings.customDisplay.whisperTabs
    return wt == nil or wt.translatePopout ~= false
end

local function IsWhisperPopoutOnly(typeKey, convKey)
    if not convKey or not WHISPER_POPOUT_KEYS[typeKey] then return nil end
    if not ShouldTranslateBlizzardWhisperPopouts() then return nil end
    return GetWhisperMode() == "popout" and true or nil
end

local function OnCaptureEvent(_, event, ...)
    local active = CaptureActive()
    if not active then return end

    local sysHandler = SYSTEM_EVENTS[event]
    if sysHandler then
        sysHandler(event, ...)
        return
    end

    local a16Raw = select(16, ...)
    if not IsSecret(a16Raw) and a16Raw then return end
    local filtered, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18
    local isChatMessage = type(event) == "string" and event:sub(1, 9) == "CHAT_MSG_"
    if isChatMessage and _G.ChatFrameUtil and _G.ChatFrameUtil.ProcessMessageEventFilters and _G.ChatFrame1 then
        filtered, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18 =
            _G.ChatFrameUtil.ProcessMessageEventFilters(_G.ChatFrame1, event, ...)
        if filtered then return end
    else
        a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18 = ...
    end

    local typeKey = Format.EventToTypeKey(event)

    local line, p, secretBody = Format.BuildEventLineFromArgs(event, a1, a2, a3, a4, a5, a6, a7,
        a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18)

    MaybeAutoAddChannel(event, p)

    if (event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER") and p.sender then
        local CFU = _G.ChatFrameUtil
        if CFU and CFU.SetLastTellTarget then
            ns.SafeCall("sink-forward", CFU.SetLastTellTarget, p.sender, typeKey)
        end
    end

    local colorKey = typeKey
    if (typeKey == "CHANNEL" or typeKey == "CHANNEL_NOTICE") and p.chNum and p.chNum > 0 then
        colorKey = "CHANNEL" .. p.chNum
    end
    local r, g, b = Format.ColorForTypeKey(colorKey, p.chName)

    local convKey, convName
    do
        local Conv = ns.QUI.Chat.ConversationManager
        local info = Conv and Conv.WHISPER_EVENTS and Conv.WHISPER_EVENTS[event]
        if info and p.sender then
            convKey = Conv.DeriveKey(info.chatType, p.sender)
            convName = p.sender
        end
    end
    local whisperPopoutOnly = IsWhisperPopoutOnly(typeKey, convKey)

    if secretBody then
        if not IsSecret(line) and not line then return end
        local m = line
        if I.AddTimestamp then
            m = (I.AddTimestamp(m))
        end
        Store.Append({ m = m, r = r, g = g, b = b, e = event, k = typeKey, s = true,
            ch = p.chName, gid = p.guid, w = convKey, wn = convName,
            whisperPopoutOnly = whisperPopoutOnly, t = Now() })
        return
    end
    if not line then return end
    local RT = ns.QUI.Chat.RedundantText
    if RT and RT.TryCollapseForCapture then
        line = (RT.TryCollapseForCapture(line, event))
    end
    local HL = ns.QUI.Chat.Hyperlinks
    if HL and HL.TryLinkifyCoordsForCapture then
        line = (HL.TryLinkifyCoordsForCapture(line))
    end
    local KA = ns.QUI.Chat.KeywordAlert
    if KA and KA.ProcessForCapture then
        line = (KA.ProcessForCapture(line, p.sender))
    end
    if I.AddTimestamp then
        line = (I.AddTimestamp(line))
    end
    local cfg = I.GetSettings and I.GetSettings()
    if I.MakeURLsClickable and cfg and cfg.urls and cfg.urls.enabled then
        line = (I.MakeURLsClickable(line))
    end
    Store.Append({ m = line, r = r, g = g, b = b, e = event, k = typeKey, ch = p.chName,
        gid = p.guid, w = convKey, wn = convName,
        whisperPopoutOnly = whisperPopoutOnly, t = Now() })
end

local function OnFallbackAddMessage(_, msg, r, g, b)
    local active = CaptureActive()
    if not active then return end
    if IsSecret(msg) then return end
    if type(msg) ~= "string" or msg == "" then return end
    if IsSecret(r) or IsSecret(g) or IsSecret(b) then r, g, b = 1, 1, 1 end

    local trace = _G.debugstack and _G.debugstack(3, 8, 0) or ""
    if trace:find("ChatFrame_OnEvent", 1, true)
        or trace:find("MessageEventHandler", 1, true)
        or trace:find("AddOns/" .. ADDON_NAME .. "/chat/history", 1, true) then
        return
    end

    if I.AddTimestamp then
        msg = (I.AddTimestamp(msg))
    end
    Store.Append({ m = msg, r = r or 1, g = g or 1, b = b or 1, e = "ADDMESSAGE", k = "SYSTEM", t = Now() })
end

function Capture.BackfillFromDefaultFrame()
    local frame = _G.DEFAULT_CHAT_FRAME or _G.ChatFrame1
    if not (frame and frame.GetNumMessages and frame.GetMessageInfo) then return 0 end
    local n = frame:GetNumMessages()
    if IsSecret(n) or type(n) ~= "number" or n <= 0 then return 0 end
    local settings = I.GetSettings and I.GetSettings()
    local cd = settings and settings.customDisplay
    local cap = (cd and cd.maxLines) or 1000
    local added = 0
    for i = math.max(1, n - cap + 1), n do
        local msg, r, g, b = frame:GetMessageInfo(i)
        if IsSecret(r) or IsSecret(g) or IsSecret(b) then r, g, b = 1, 1, 1 end
        if IsSecret(msg) then
            Store.Append({ m = msg, r = r or 1, g = g or 1, b = b or 1, e = "BACKFILL", k = "SYSTEM", s = true, t = Now() })
            added = added + 1
        elseif type(msg) == "string" and msg ~= "" then
            Store.Append({ m = msg, r = r or 1, g = g or 1, b = b or 1, e = "BACKFILL", k = "SYSTEM", t = Now() })
            added = added + 1
        end
    end
    return added
end

function Capture.Setup()
    if not captureFrame then
        captureFrame = CreateFrame("Frame")
        captureFrame:SetScript("OnEvent", OnCaptureEvent)
    end
    local valid = _G.C_EventUtils and _G.C_EventUtils.IsEventValid
    for event in pairs(_G.ChatTypeGroupInverted or {}) do
        if event:sub(1, 9) == "CHAT_MSG_"
            and (not valid or valid(event)) then
            captureFrame:RegisterEvent(event)
        end
    end
    for i = 1, #EXTRA_EVENTS do
        local event = EXTRA_EVENTS[i]
        if not valid or valid(event) then
            captureFrame:RegisterEvent(event)
        end
    end
    for event in pairs(SYSTEM_EVENTS) do
        if not valid or valid(event) then
            captureFrame:RegisterEvent(event)
        end
    end
    if not fallbackHooked and _G.hooksecurefunc and _G.DEFAULT_CHAT_FRAME then
        fallbackHooked = true
        _G.hooksecurefunc(_G.DEFAULT_CHAT_FRAME, "AddMessage", OnFallbackAddMessage)
    end
end

function Capture.Teardown()
    if captureFrame then
        captureFrame:UnregisterAllEvents()
    end
end
