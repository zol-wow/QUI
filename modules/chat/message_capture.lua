-- modules/chat/message_capture.lua
-- Direct-event capture for the custom chat display. Registers every routed
-- CHAT_MSG_* event on an insecure capture frame (independent delivery — no
-- dispatch-order dependence), runs Blizzard's message-event filters for
-- cross-addon compat, applies the secret-first guard, and appends to
-- MessageStore. A hooksecurefunc on DEFAULT_CHAT_FRAME.AddMessage is the
-- FALLBACK for non-event traffic only (addon print(), system AddMessage);
-- event-driven and own-addon lines are skipped via stack inspection.
--
-- SECRET SAFETY: arg1 (and any payload arg) may be secret. issecretvalue
-- BEFORE any operator; classification keys off the EVENT NAME only.
local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: message_capture.lua loaded before chat.lua. Check chat.xml — chat.lua must precede message_capture.lua.")

ns.QUI.Chat.MessageCapture = ns.QUI.Chat.MessageCapture or {}
local Capture = ns.QUI.Chat.MessageCapture

local Store = assert(ns.QUI.Chat.MessageStore, "message_store.lua must load before message_capture.lua")
local Format = assert(ns.QUI.Chat.MessageFormat, "message_format.lua must load before message_capture.lua")

local function IsSecret(v)
    return Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(v) or false
end

local function Now()
    return (_G.GetServerTime and _G.GetServerTime()) or time()
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

local function OnCaptureEvent(_, event, ...)
    local active = CaptureActive()
    if not active then return end

    -- Letterbox/cinematic-hidden lines: Blizzard bails before filters when
    -- arg16 is set; mirror that. Probe before truth-testing (may be secret;
    -- if it is, we can't know — let the line through rather than risk an op).
    local a16 = select(16, ...)
    if not IsSecret(a16) and a16 then return end

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
    -- Per-channel colors live in ChatTypeInfo.CHANNEL<n>, not .CHANNEL.
    -- a8 (channel number) may be secret in restricted contexts — probe first.
    -- a9 is the channel base-name ("Trade"); needed so ColorForTypeKey can
    -- resolve channel-name-keyed user overrides in ChannelColors.
    local colorKey = typeKey
    local colorChName  -- channel base-name for override lookup; nil for non-channel events
    if (typeKey == "CHANNEL" or typeKey == "CHANNEL_NOTICE")
        and not IsSecret(a8) and type(a8) == "number" and a8 > 0 then
        colorKey = "CHANNEL" .. a8
        if not IsSecret(a9) and type(a9) == "string" and a9 ~= "" then
            colorChName = a9
        end
    end
    local r, g, b = Format.ColorForTypeKey(colorKey, colorChName)

    local chName
    if not IsSecret(a9) and type(a9) == "string" and a9 ~= "" then
        chName = a9
    end

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
        if info and not IsSecret(a2) and type(a2) == "string" and a2 ~= "" then
            convKey = Conv.DeriveKey(info.chatType, a2)
            convName = a2
        end
    end

    -- SECRET-FIRST: no operator may touch a1 before this check.
    if IsSecret(a1) then
        local m = a1
        if Format.WrapSecretEventLine then
            m = Format.WrapSecretEventLine(event, a1,
                a2,
                (not IsSecret(a4)) and type(a4) == "string" and a4 or nil,
                (not IsSecret(a8)) and type(a8) == "number" and a8 or nil,
                (not IsSecret(a9)) and type(a9) == "string" and a9 or nil,
                (not IsSecret(a12)) and type(a12) == "string" and a12 or nil,
                (not IsSecret(a13)) and type(a13) == "number" and a13 or nil,
                (not IsSecret(a11)) and type(a11) == "number" and a11 or nil) or a1
        end
        -- Timestamp secret lines too: AddTimestamp's secret path wraps via
        -- C_StringUtil.WrapString (secret-safe) and passes through unchanged
        -- when that API is unavailable. No Lua operator touches the payload.
        if I.AddTimestamp then
            m = (I.AddTimestamp(m))
        end
        Store.Append({ m = m, r = r, g = g, b = b, e = event, k = typeKey, s = true,
            ch = chName, gid = (not IsSecret(a12)) and type(a12) == "string" and a12 or nil,
            w = convKey, wn = convName, t = Now() })
        return
    end
    if type(a1) ~= "string" or a1 == "" then return end

    local line = Format.BuildEventLine(event, a1,
        (not IsSecret(a2)) and a2 or nil,
        (not IsSecret(a4)) and a4 or nil,
        (not IsSecret(a8)) and a8 or nil,
        chName,
        (not IsSecret(a12)) and a12 or nil,
        (not IsSecret(a13)) and a13 or nil,
        (not IsSecret(a11)) and a11 or nil,
        (not IsSecret(a5)) and a5 or nil)
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
        line = (KA.ProcessForCapture(line, (not IsSecret(a2)) and a2 or nil))
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
    Store.Append({ m = line, r = r, g = g, b = b, e = event, k = typeKey, ch = chName,
        gid = (not IsSecret(a12)) and type(a12) == "string" and a12 or nil,
        w = convKey, wn = convName, t = Now() })
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
        or trace:find("AddOns/" .. ADDON_NAME .. "/modules/chat/history", 1, true) then
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
        -- which Blizzard routes via SystemEventHandler -> AddMessage; our
        -- fallback hook captures that formatted line once instead.
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
