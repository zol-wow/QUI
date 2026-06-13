-- modules/chat/message_capture.lua
-- Direct-event capture for the custom chat display. Registers every routed
-- CHAT_MSG_* event on an insecure capture frame (independent delivery — no
-- dispatch-order dependence), runs Blizzard's message-event filters for
-- cross-addon compat, applies the secret-first guard, and appends to
-- MessageStore. Also registers the non-CHAT_MSG system events Blizzard's
-- ChatFrameMixin:SystemEventHandler turns into chat lines (/played, level-up,
-- GMOTD, disconnects...) — suppressed Blizzard frames are event-neutered, so
-- without this those lines would be lost entirely. A hooksecurefunc on
-- DEFAULT_CHAT_FRAME.AddMessage is the FALLBACK for non-event traffic only
-- (addon print(), direct AddMessage); event-driven and own-addon lines are
-- skipped via stack inspection.
--
-- SECRET SAFETY: arg1 (and any payload arg) may be secret. issecretvalue
-- BEFORE any operator; classification keys off the EVENT NAME only. Payload
-- args proven non-secret land in the `p` table handed to MessageFormat;
-- p.text/p.rawSender carry raw (possibly secret) values for the entry points
-- that own the secret discipline.
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
    local ok, formatted = pcall(string.format, fmt, ...)
    if not ok then return nil end
    return formatted
end

-- Events routed to chat frames but not in ChatTypeGroupInverted.
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

-- NOTE: capture runs whenever the chat module is enabled; disabling tears it
-- down (goes inert). Capture starts at ADDON_LOADED, so the login burst is
-- caught; only pre-ADDON_LOADED engine lines are missed.
local function CaptureActive()
    local settings = I.GetSettings and I.GetSettings()
    if not (I.IsChatEnabled and I.IsChatEnabled(settings)) then return false end
    return true
end

-- ---------------------------------------------------------------------------
-- System-event replication (ChatFrameMixin:SystemEventHandler parity —
-- vendored FrameXML: Blizzard_ChatFrameBase/Mainline/ChatFrameOverrides.lua
-- :183-266 + ChatFrameUtil.DisplayTimePlayed/DisplayLevelUp/DisplayGMOTD).
-- Suppressed frames never receive these, so the capture frame owns them.
-- ---------------------------------------------------------------------------

-- Append a replicated system line. typeKey colors via the same read-only
-- resolver event lines use; entries are SYSTEM-group so default tabs show them.
-- SECRET-FIRST: probe before any inspection — a secret line (GMOTD under
-- lockdown) flows opaquely with s=true; type() is the only operator applied
-- to non-secret values before the string checks.
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

local seenMotd -- session GMOTD dedupe (Blizzard shows each broadcast once)

-- GMOTD held until the GUILD chat color syncs. ChatTypeInfo carries NO r/g/b
-- at file scope (vendored ChatTypeInfoConstants.lua) — colors arrive per-type
-- via UPDATE_CHAT_COLOR during the login settings download, AFTER the login
-- GMOTD is available. Appending earlier bakes ColorForTypeKey's white fallback
-- into the entry permanently: Blizzard prints early too but recovers by
-- retroactively recoloring lines (UpdateColorByID, ChatFrameOverrides.lua:147),
-- a pass the store has no equivalent of. The held payload may be SECRET:
-- stored opaquely, flagged separately, no operator ever touches it here.
local pendingMotd, hasPendingMotd

-- Per-type colors captured from UPDATE_CHAT_COLOR's OWN args ({r,g,b} keyed
-- by upper-cased type). The event payload is authoritative the moment it
-- fires, while ChatTypeInfo is only authoritative after Blizzard's handler
-- (same dispatch, unspecified cross-frame order) writes it — reading the args
-- removes that ordering dependence entirely.
local syncedTypeColors = {}

local function GuildColorReady()
    -- A user override wins inside ColorForTypeKey regardless of ChatTypeInfo.
    local CC = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.ChannelColors
    if CC and CC.HasOverride and CC.HasOverride("GUILD") then return true end
    if syncedTypeColors.GUILD then return true end
    local info = _G.ChatTypeInfo and _G.ChatTypeInfo.GUILD
    return info ~= nil and info.r ~= nil
end

local SYSTEM_EVENTS = {}

SYSTEM_EVENTS.TIME_PLAYED_MSG = function(event, totalTime, levelTime)
    -- Honor the stock silent-request dance: addons that RequestTimePlayed()
    -- without wanting chat output unregister TIME_PLAYED_MSG from the chat
    -- frames first. The neutered frames can't reflect that, so
    -- blizzard_suppress mirrors the outside intent — when the default frame
    -- wouldn't have printed, neither do we (fixes "/played spam at login").
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
        local ok, active = pcall(_G.C_GameRules.IsGameRuleActive, _G.Enum.GameRule.ChatLinkLevelToastsDisabled)
        noLink = ok and active or false
    end
    if not noLink and _G.C_PlayerInfo and _G.C_PlayerInfo.IsPlayerNPERestricted then
        local ok, restricted = pcall(_G.C_PlayerInfo.IsPlayerNPERestricted)
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
        -- Only a REAL payload may stash. The pull triggers route empty
        -- broadcasts through here (C_Club's broadcast field is nil/"" until
        -- the club syncs, AFTER the GUILD_MOTD event on a cold login), and
        -- letting one overwrite a stashed real MOTD drops the line at flush.
        if IsSecret(motd) or (type(motd) == "string" and motd ~= "") then
            pendingMotd, hasPendingMotd = motd, true
        end
        return
    end
    local fmt = GlobalString("GUILD_MOTD_TEMPLATE")
    if not fmt then return end
    if IsSecret(motd) then
        -- Can't compare for dedupe; show at most one secret MOTD per session.
        if seenMotd == true then return end
        seenMotd = true
        AppendSystemLine(event, FormatString(fmt, motd), "GUILD")
        return
    end
    if type(motd) ~= "string" or motd == "" or motd == seenMotd then return end
    seenMotd = motd
    AppendSystemLine(event, FormatString(fmt, motd), "GUILD")
end

-- Login backfill for the GMOTD. At login the MOTD is delivered with the guild
-- roster sync, often BEFORE this frame catches a GUILD_MOTD event (Blizzard's
-- own chat frame hits the same race — vendored ChatFrameOverrides.lua:131
-- "GMOTD may have arrived before this frame registered for the event"). Blizzard
-- recovers by re-reading the MOTD once guild data lands; without that pull the
-- login MOTD is simply lost. Route the pulled value through the GUILD_MOTD
-- handler so it shares the seenMotd latch — the event path and the pull never
-- double-post, and repeated guild-data events are cheap no-ops once a non-empty
-- MOTD has latched.
--
-- Read the MOTD from the guild club's broadcast field (C_Club), NOT
-- C_GuildInfo.GetMOTD: GetMOTD is HasRestrictions=true and is blocked as a
-- protected function (ADDON_ACTION_BLOCKED) when a guild-data event lands inside
-- an in-combat secret-value dispatch — a pcall cannot suppress that block.
-- C_Club.GetClubInfo carries no such restriction; it only flags a possibly
-- secret return during chat-messaging lockdown, so info.broadcast flows opaquely
-- into the handler, which probes IsSecret before any operator. GetGuildClubId
-- and GetClubInfo are both Nilable (clubs may still be initializing), so guard
-- each return.
local function MaybePullGMOTD()
    -- LOGIN-RECOVERY ONLY: once any MOTD has shown (or stashed pending the
    -- color sync), stop pulling for the rest of the session. The pull events
    -- below keep firing all session (GUILD_ROSTER_UPDATE on every guildie
    -- login/logout, CHANNEL_LEFT/CHANNEL_UI_UPDATE beside channel notices),
    -- and C_Club's broadcast flips between a plain string and a SECRET value
    -- depending on chat-messaging lockdown at pull time — the seenMotd latch
    -- can't dedupe across that domain flip (string latch vs `true` latch), so
    -- an ungated pull re-appends the GMOTD on every flip, "randomly through
    -- the session, next to system messages". A genuinely changed MOTD still
    -- shows via the real GUILD_MOTD event (stock parity); only the pull
    -- fallback is one-shot.
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

-- Primary login-MOTD recovery point. Blizzard's own chat frame backfills the
-- GMOTD on UPDATE_CHAT_WINDOWS (vendored ChatFrameOverrides.lua:114-136,
-- "GMOTD may have arrived before this frame registered for the event"): by the
-- time chat settings download the MOTD has reliably landed, whereas the
-- guild-data events below fire on a cold login BEFORE C_Club's broadcast field is
-- populated (the club broadcast syncs separately from the roster), so the pull
-- there no-ops and the login MOTD is lost until some unrelated later roster
-- update happens to fire. The channel-UI events give repeat retries through the
-- channel-join sequence. Capture.Setup() registers these at ADDON_LOADED, before
-- the login UPDATE_CHAT_WINDOWS, so the login firing is caught. seenMotd dedupes
-- against the GUILD_MOTD event path and the guild-data triggers.
SYSTEM_EVENTS.UPDATE_CHAT_WINDOWS = function() MaybePullGMOTD() end
SYSTEM_EVENTS.CHANNEL_UI_UPDATE = function() MaybePullGMOTD() end
SYSTEM_EVENTS.CHANNEL_LEFT = function() MaybePullGMOTD() end
SYSTEM_EVENTS.GUILD_ROSTER_UPDATE = function() MaybePullGMOTD() end
SYSTEM_EVENTS.PLAYER_GUILD_UPDATE = function() MaybePullGMOTD() end

local function FlushPendingMotd()
    if not (hasPendingMotd and CaptureActive() and GuildColorReady()) then return end
    local motd = pendingMotd
    pendingMotd, hasPendingMotd = nil, false
    SYSTEM_EVENTS.GUILD_MOTD("GUILD_MOTD", motd)
end

-- UPDATE_CHAT_COLOR: the login color burst both un-gates a held GMOTD and
-- retroactively REBAKES already-stored lines of the synced types — Blizzard's
-- UpdateColorByID parity (ChatFrameOverrides.lua:147): their early-printed
-- lines carry a colorID and get recolored when the type's color lands; store
-- entries bake r/g/b at append time, so without this pass any line captured
-- (or replayed from persisted history) before its type synced keeps the white
-- fallback forever.
--
-- Colors come from the event ARGS (cached in syncedTypeColors), never from
-- re-reading ChatTypeInfo: Blizzard's own handler (the neutered frames keep
-- this event registered) writes ChatTypeInfo in the same dispatch with
-- unspecified cross-frame order, and the addon must never write it itself
-- (taints chat dispatch session-wide). The work is DEBOUNCED one frame
-- (C_Timer.After(0)) purely as batching: one walk + one reapply covers the
-- whole same-frame login burst.
--
-- Rebake scope: entries whose k matches a synced type AND whose color was
-- RESOLVED from that type at append time. ADDMESSAGE/BACKFILL carry the
-- producer's own r/g/b (addon prints in custom colors) and HISTORY is the
-- grey session separators — k is just a routing bucket for those, never a
-- color source. CHANNEL/CHANNEL_NOTICE entries bake per-SLOT colors
-- (CHANNEL<n>), so a blanket per-type rebake would be wrong — skipped.
local pendingColorTypes, colorSyncQueued

local REBAKE_SKIP_EVENTS = { ADDMESSAGE = true, BACKFILL = true, HISTORY = true }

-- Override → synced event args → ColorForTypeKey (ChatTypeInfo). Same
-- precedence ColorForTypeKey itself applies, with the args cache between.
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
    -- Debounce: the login burst is dozens of same-frame events; one walk +
    -- one reapply next frame covers them all. The args cache already makes
    -- the colors correct, so the defer is purely a batching concern.
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
        local ok, s = pcall(_G.GetRegionalChatUnavailableString)
        if ok and type(s) == "string" then return s end
    end
    return nil
end

SYSTEM_EVENTS.CHAT_REGIONAL_STATUS_CHANGED = function(event, isServiceAvailable)
    if IsSecret(isServiceAvailable) then return end
    if isServiceAvailable then
        if _G.GetRegionalChatAvailableString then
            local ok, s = pcall(_G.GetRegionalChatAvailableString)
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

-- Language cache for [Orcish]-style headers lives in MessageFormat; the
-- capture frame owns its event wiring (format stays frame-free).
SYSTEM_EVENTS.PLAYER_ENTERING_WORLD = function()
    if Format.RefreshLanguages then Format.RefreshLanguages() end
    -- /reload keeps guild data cached, so the MOTD is readable right here even
    -- if no GUILD_ROSTER_UPDATE re-fires; on a cold login GetMOTD is still empty
    -- this early and the roster-update pull above catches it. seenMotd dedupes.
    MaybePullGMOTD()
end

SYSTEM_EVENTS.ALTERNATIVE_DEFAULT_LANGUAGE_CHANGED = function()
    if Format.RefreshLanguages then Format.RefreshLanguages() end
end

-- Reported sender: drop their lines from the store and rebuild the windows
-- (FCF_RemoveAllMessagesFromChanSender parity). Compares metadata only —
-- entry.m is never touched.
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

-- ---------------------------------------------------------------------------
-- Regional-channel auto-add (ChatFrame_CheckAddChannel parity — vendored
-- ChatFrameOverrides.lua:49-71): joining a regional channel that no window-1
-- tab lists gets added to the first tab, like Blizzard adds it to the
-- default frame. Heals configs whose channel seed predates the channel.
-- ---------------------------------------------------------------------------
local function MaybeAutoAddChannel(event, p)
    if event ~= "CHAT_MSG_CHANNEL_NOTICE" then return end
    if IsSecret(p.text) or p.text ~= "YOU_CHANGED" then return end
    if type(p.zoneID) ~= "number" or p.zoneID <= 0 then return end
    local CI = _G.C_ChatInfo
    if not (CI and CI.IsChannelRegionalForChannelID) then return end
    local ok, regional = pcall(CI.IsChannelRegionalForChannelID, p.zoneID)
    if not ok or not regional then return end
    if Registry and Registry.Refresh then Registry.Refresh() end
    local name = p.chName or p.chBase
    local TM = ns.QUI.Chat.TabManager
    if TM and TM.EnsureDefaultChannelListed and type(name) == "string" and name ~= "" then
        TM.EnsureDefaultChannelListed(name)
    end
end

-- Whisper-family chatTypeKeys (shared via chat.lua's _internals; see
-- I.WHISPER_TYPE_KEYS). Used here for whisper-popout conversation routing.
local WHISPER_POPOUT_KEYS = I.WHISPER_TYPE_KEYS

local function GetWhisperMode()
    if type(_G.GetCVar) ~= "function" then return nil end
    local ok, value = pcall(_G.GetCVar, "whisperMode")
    if ok then return value end
    return nil
end

local function ShouldTranslateBlizzardWhisperPopouts()
    local settings = I.GetSettings and I.GetSettings()
    local wt = settings and settings.customDisplay and settings.customDisplay.whisperTabs
    return wt == nil or wt.translatePopout ~= false
end

local function IsWhisperPopoutOnly(typeKey, convKey)
    -- Do not suppress the regular saved tabs unless the entry has a known
    -- conversation destination. Secret/malformed identities stay inline rather
    -- than disappearing.
    if not convKey or not WHISPER_POPOUT_KEYS[typeKey] then return nil end
    if not ShouldTranslateBlizzardWhisperPopouts() then return nil end
    return GetWhisperMode() == "popout" and true or nil
end

-- ---------------------------------------------------------------------------
-- CHAT_MSG_* capture
-- ---------------------------------------------------------------------------

local function OnCaptureEvent(_, event, ...)
    local active = CaptureActive()
    if not active then return end

    local sysHandler = SYSTEM_EVENTS[event]
    if sysHandler then
        sysHandler(event, ...)
        return
    end

    -- Letterbox/cinematic-hidden lines: Blizzard bails before filters when
    -- arg16 is set; mirror that. Probe before truth-testing (may be secret;
    -- if it is, we can't know — let the line through rather than risk an op).
    local a16 = select(16, ...)
    if not IsSecret(a16) and a16 then return end
    -- arg17 (suppressRaidIcons) is not in the filter contract (filters see
    -- args 1-14) — read it from the original payload.
    local a17 = select(17, ...)

    -- Cross-addon compat: honor ChatFrameUtil.AddMessageEventFilter consumers
    -- (spam blockers etc.). ChatFrame1 is the filter context — filters that
    -- act per-frame behave as they do for the default frame. While suppressed
    -- ChatFrame1 is EVENT-NEUTERED (receives no events), so this is the ONLY
    -- invocation; with the module disabled capture never reaches here. Either
    -- way the filter chain runs exactly once per message in steady state.
    -- (Blizzard's filter registry skips callbacks on secret payloads via
    -- canaccessvalue — we inherit that protection by calling the same API.)
    local filtered, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14
    local isChatMessage = type(event) == "string" and event:sub(1, 9) == "CHAT_MSG_"
    if isChatMessage and _G.ChatFrameUtil and _G.ChatFrameUtil.ProcessMessageEventFilters and _G.ChatFrame1 then
        filtered, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14 =
            _G.ChatFrameUtil.ProcessMessageEventFilters(_G.ChatFrame1, event, ...)
        if filtered then return end
    else
        a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14 = ...
    end

    local typeKey = Format.EventToTypeKey(event)

    -- Probed payload for MessageFormat: every field except text/rawSender is
    -- nil unless proven non-secret AND well-typed. chName is the registry's
    -- canonical display name (community identifiers resolved) so filters and
    -- rendering agree on one spelling.
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
        bnID = (not IsSecret(a13)) and type(a13) == "number" and a13 or nil,
        suppressIcons = (not IsSecret(a17)) and a17 and true or nil,
    }
    if p.chBase then
        p.chName = Registry and Registry.ResolveName
            and Registry.ResolveName(p.chNum, p.chBase) or p.chBase
    end
    if Format.DecorateSender then
        p.decorated = Format.DecorateSender(event, a1, a2, a3, a4, a5, a6, a7,
            a8, a9, a10, a11, a12, a13, a14)
    end

    MaybeAutoAddChannel(event, p)

    -- R-to-reply: Blizzard records the last whisperer via
    -- ChatFrameUtil.SetLastTellTarget inside its per-frame message handler
    -- (ChatFrameOverrides.lua:648-651) — event-neutered under the takeover —
    -- so mirror the bookkeeping here or ChatFrameUtil.ReplyTell (the REPLY
    -- keybind) finds no target and silently no-ops. Incoming only: the
    -- outgoing side (LastTOLD, reply-to-last-told) is recorded by the editbox
    -- send path, which stays live. p.sender is already nil when arg2 is
    -- secret or malformed; BN kstring senders pass through raw, exactly as
    -- Blizzard passes arg2.
    if (event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER") and p.sender then
        local CFU = _G.ChatFrameUtil
        if CFU and CFU.SetLastTellTarget then
            pcall(CFU.SetLastTellTarget, p.sender, typeKey)
        end
    end

    -- Per-channel colors live in ChatTypeInfo.CHANNEL<n>, not .CHANNEL.
    -- chName resolves channel-name-keyed user overrides in ChannelColors.
    local colorKey = typeKey
    if (typeKey == "CHANNEL" or typeKey == "CHANNEL_NOTICE") and p.chNum and p.chNum > 0 then
        colorKey = "CHANNEL" .. p.chNum
    end
    local r, g, b = Format.ColorForTypeKey(colorKey, p.chName)

    -- Whisper conversation tagging: key off the counterparty identity
    -- (arg2 playerName — sender on incoming, target on _INFORM; vendored
    -- ChatInfoDocumentation.lua:2486ff). The event is
    -- SecretInChatMessagingLockdown and playerName is NOT NeverSecret —
    -- probe before any operator. A secret identity leaves the entry
    -- untagged (falls through to type-filter tabs); a secret BODY does not
    -- block tagging (both append paths below carry the fields).
    -- ConversationManager loads after this file (chat.xml) — runtime lookup.
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

    -- SECRET-FIRST: no operator may touch a1 before this check.
    if IsSecret(a1) then
        -- BN friend-status toasts put the toast TYPE token in arg1
        -- (FRIEND_ONLINE/FRIEND_OFFLINE/...), which Blizzard renders by indexing
        -- BN_INLINE_TOAST_<token>. Under ChatMessagingLockdown the token is
        -- secret: it can neither index that globalstring (concat throws) nor be
        -- shown as-is (a secret token paints the raw word "FRIEND_ONLINE"). Drop
        -- it, exactly as the reference client discards secret friend-status
        -- toasts. Classifies by EVENT NAME (typeKey) only -- never compares the
        -- secret value. Broadcasts carry real message text in arg1, so they fall
        -- through to the verbatim secret path below and are NOT dropped.
        if typeKey == "BN_INLINE_TOAST_ALERT" then return end
        local m = a1
        if Format.WrapSecretEventLine then
            m = Format.WrapSecretEventLine(event, p) or a1
        end
        -- Timestamp secret lines too: AddTimestamp's secret path wraps via
        -- C_StringUtil.WrapString (secret-safe) and passes through unchanged
        -- when that API is unavailable. No Lua operator touches the payload.
        if I.AddTimestamp then
            m = (I.AddTimestamp(m))
        end
        Store.Append({ m = m, r = r, g = g, b = b, e = event, k = typeKey, s = true,
            ch = p.chName, gid = p.guid, w = convKey, wn = convName,
            whisperPopoutOnly = whisperPopoutOnly, t = Now() })
        return
    end
    if type(a1) ~= "string" or a1 == "" then return end

    local line = Format.BuildEventLine(event, p)
    if not line then return end
    -- Redundant-text collapse (loot/xp/honor compaction) — pure transform,
    -- gated inside the module on its own setting.
    local RT = ns.QUI.Chat.RedundantText
    if RT and RT.TryCollapseForCapture then
        line = (RT.TryCollapseForCapture(line, event))
    end
    -- Coordinate waypoint links — pure transform, self-gated on the
    -- coordinates toggle (same relative order the old rendered pipeline used).
    local HL = ns.QUI.Chat.Hyperlinks
    if HL and HL.TryLinkifyCoordsForCapture then
        line = (HL.TryLinkifyCoordsForCapture(line))
    end
    -- Keyword highlight + sound (ProcessForCapture owns the keyword sound).
    local KA = ns.QUI.Chat.KeywordAlert
    if KA and KA.ProcessForCapture then
        line = (KA.ProcessForCapture(line, p.sender))
    end
    -- Capture-time decorations: timestamps must reflect ARRIVAL time and
    -- rebuilds must not re-run transforms, so entry.m stores the final line.
    -- Both helpers are pure text functions; AddTimestamp self-gates on
    -- settings.timestamps.enabled. Parens force first-return-only.
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

-- Fallback for traffic that never fires a CHAT_MSG event (addon print(),
-- direct system AddMessage). Skip event-dispatch traffic (captured above)
-- and our own history repump (would duplicate restored lines). Other QUI
-- prints SHOULD flow through — they're user-facing output.
local function OnFallbackAddMessage(_, msg, r, g, b)
    local active = CaptureActive()
    if not active then return end
    -- SECRET-FIRST: secrets only arrive here via event dispatch, which the
    -- stack check below skips anyway — but guard before any operator.
    if IsSecret(msg) then return end
    if type(msg) ~= "string" or msg == "" then return end
    if IsSecret(r) or IsSecret(g) or IsSecret(b) then r, g, b = 1, 1, 1 end

    local trace = _G.debugstack and _G.debugstack(3, 8, 0) or ""
    if trace:find("ChatFrame_OnEvent", 1, true)
        or trace:find("MessageEventHandler", 1, true)
        or trace:find("AddOns/" .. ADDON_NAME .. "/chat/history", 1, true) then
        return
    end

    -- Timestamp fallback lines too (Blizzard timestamps ALL rendered lines;
    -- arrival time is known here). URL linkify is event-path-only — addon
    -- prints carry their own links.
    -- Fallback entries are routed as SYSTEM (un-classifiable rendered lines;
    -- tabs whitelisting the SYSTEM group show them — matching the General
    -- frame addon prints target).
    if I.AddTimestamp then
        msg = (I.AddTimestamp(msg))
    end
    Store.Append({ m = msg, r = r or 1, g = g or 1, b = b or 1, e = "ADDMESSAGE", k = "SYSTEM", t = Now() })
end

-- One-shot backfill from the default frame's existing scrollback — used on a
-- MID-SESSION first enable so the custom display starts with what the user
-- already sees instead of empty. Secret lines are stored opaquely (s=true,
-- zero operators). Entries are typed SYSTEM/BACKFILL: rendered lines can't
-- be re-classified, so SYSTEM-listing tabs show them.
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
        -- Only CHAT_MSG_* events: the inverted map also carries GUILD_MOTD,
        -- which is replicated through SYSTEM_EVENTS below instead.
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
    -- Non-CHAT_MSG system traffic (SystemEventHandler parity).
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
    -- hooksecurefunc cannot be removed; OnFallbackAddMessage self-gates on
    -- CaptureActive(), so it goes inert when the module is disabled.
end
