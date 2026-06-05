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
}

-- Token-payload events the Phase 1 formatter can't render (raw "YOU_CHANGED"
-- at login, "%s has earned..." achievements, "%s" boss emotes); excluded
-- until Phase 2 formatting parity. Dual display: these still show in the
-- Blizzard frames, so nothing is lost for opt-in users.
local EXCLUDED_EVENTS = {
    CHAT_MSG_CHANNEL_NOTICE = true,
    CHAT_MSG_CHANNEL_NOTICE_USER = true,
    CHAT_MSG_CHANNEL_LIST = true,
    CHAT_MSG_MONSTER_EMOTE = true,
    CHAT_MSG_ACHIEVEMENT = true,           -- arg1 has %s, needs format(GetPlayerLink)
    CHAT_MSG_GUILD_ACHIEVEMENT = true,     -- same
    CHAT_MSG_BN_INLINE_TOAST_ALERT = true, -- arg1 is a token (FRIEND_ONLINE etc.)
    CHAT_MSG_RAID_BOSS_EMOTE = true,       -- arg1 may carry %s for boss name
    CHAT_MSG_RAID_BOSS_WHISPER = true,     -- same
}

local captureFrame
local fallbackHooked = false

-- NOTE (accepted Phase 1 limitation): capture only runs while displayMode is
-- "custom", so the first enable starts with an empty backlog and blizzard-
-- mode interludes leave gaps; capture also starts at PLAYER_LOGIN, so the
-- pre-login burst (MOTD, system welcome) lands only in the Blizzard frames.
-- Deliberate: default-mode users must pay zero per-message cost. Phase 2 may
-- add opt-in always-capture or backfill.
local function CaptureActive()
    local settings = I.GetSettings and I.GetSettings()
    if not (I.IsChatEnabled and I.IsChatEnabled(settings)) then return false end
    return settings and settings.displayMode == "custom"
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
    -- act per-frame behave as they do for the default frame. Phase 1 tradeoff:
    -- ChatFrame1 also runs this chain itself, so per-frame stateful filters
    -- see the frame twice; revisit when the Blizzard display is suppressed.
    -- (Blizzard's filter registry skips callbacks on secret payloads via
    -- canaccessvalue — we inherit that protection by calling the same API.)
    local filtered, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14
    if _G.ChatFrameUtil and _G.ChatFrameUtil.ProcessMessageEventFilters and _G.ChatFrame1 then
        filtered, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14 =
            _G.ChatFrameUtil.ProcessMessageEventFilters(_G.ChatFrame1, event, ...)
        if filtered then return end
    else
        a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14 = ...
    end

    local typeKey = Format.EventToTypeKey(event)
    -- Per-channel colors live in ChatTypeInfo.CHANNEL<n>, not .CHANNEL.
    -- a8 (channel number) may be secret in restricted contexts — probe first.
    local colorKey = typeKey
    if typeKey == "CHANNEL" and not IsSecret(a8) and type(a8) == "number" and a8 > 0 then
        colorKey = "CHANNEL" .. a8
    end
    local r, g, b = Format.ColorForTypeKey(colorKey)

    -- SECRET-FIRST: no operator may touch a1 before this check.
    if IsSecret(a1) then
        Store.Append({ m = a1, r = r, g = g, b = b, e = event, k = typeKey, s = true, t = Now() })
        return
    end
    if type(a1) ~= "string" or a1 == "" then return end

    local chName
    if not IsSecret(a9) and type(a9) == "string" and a9 ~= "" then
        chName = a9
    end
    local line = Format.BuildLine(event, a1,
        (not IsSecret(a2)) and a2 or nil,
        (not IsSecret(a8)) and a8 or nil,
        chName)
    Store.Append({ m = line, r = r, g = g, b = b, e = event, k = typeKey, ch = chName, t = Now() })
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

    Store.Append({ m = msg, r = r or 1, g = g or 1, b = b or 1, e = "ADDMESSAGE", t = Now() })
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
        if event:sub(1, 9) == "CHAT_MSG_" and not EXCLUDED_EVENTS[event]
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
    -- CaptureActive(), so it goes inert when displayMode flips back.
end
