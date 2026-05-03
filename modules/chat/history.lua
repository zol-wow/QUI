---------------------------------------------------------------------------
-- QUI Chat Module — Persistent History
-- Captures all displayed chat messages into per-character SV. Replays
-- them on next login with session separators. Time-based retention with
-- per-channel overrides. Opt-in whisper storage.
--
-- Storage layout:
--   Settings : db.profile.chat.history       (toggles, retention sliders)
--   Entries  : db.char.chat.history.entries  (the captured messages)
--
-- Per-character semantics come from AceDB's `char` namespace, which
-- Blizzard ultimately writes to QUIDB.char.<charKey>.chat.history. This
-- diverges from the original plan's literal "QUIDB.<charKey>.chat.history"
-- because QUIDB's top-level is owned by AceDB-3.0 (profileKeys / profiles
-- / char / factionrealm); writing under db.char delivers the same
-- per-character semantics through the established API.
--
-- Chat-type detection:
--   Blizzard's chat code calls `frame:AddMessage(msg, r, g, b, info.id)`
--   where `info.id` is the integer ChatTypeInfo[<key>].id. We capture that
--   5th positional arg and reverse it back to the chatTypeKey ("WHISPER",
--   "GUILD", etc.) via a one-shot map built from ChatTypeInfo. The key is
--   stamped on each entry as `c` for per-channel retention, and gates the
--   storeWhispers filter — locale-independent, replaces the older heuristic
--   that sniffed rendered text for "whispers:" / "To <name>:".
---------------------------------------------------------------------------

local ADDON_NAME, ns = ...

local I = assert(ns.QUI and ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: history.lua loaded before chat.lua. Check chat.xml — chat.lua must precede history.lua.")

ns.QUI.Chat.History = ns.QUI.Chat.History or {}
local History = ns.QUI.Chat.History

local Helpers = ns.Helpers
-- _G.QUI is the AceAddon (provides .db, set by QUICore:OnInitialize).
-- NOT to be confused with ns.QUI, which is the chat module's namespace
-- bucket — that one has no .db. Capturing the wrong one was the cause of
-- chat history never persisting (every getHistory() call returned nil).
local QUI = _G.QUI

-- Forward declaration. ApplyEnabled is referenced by the _afterRefresh
-- registration below before its body is defined; without the forward decl
-- closures would capture nil. Same pattern other chat modifiers use.
local ApplyEnabled

-- File-local re-pump flag. When true, the AddMessage hook drops captures
-- so we don't recursively store messages we are replaying.
History._repumping = false

-- ---------------------------------------------------------------------------
-- SV access
-- ---------------------------------------------------------------------------

-- Returns the persisted history table, lazy-creating in db.char.
-- Returns nil when AceDB hasn't initialised yet (very early load order).
local function getHistory()
    if not QUI or not QUI.db or not QUI.db.char then return nil end
    QUI.db.char.chat = QUI.db.char.chat or {}
    QUI.db.char.chat.history = QUI.db.char.chat.history or { schemaVersion = 1, entries = {} }
    if not QUI.db.char.chat.history.entries then
        QUI.db.char.chat.history.entries = {}
    end
    return QUI.db.char.chat.history
end

-- ---------------------------------------------------------------------------
-- Capture: hooksecurefunc on each managed ChatFrame's AddMessage
-- ---------------------------------------------------------------------------

-- Weak-keyed: don't pin frames if Blizzard ever recycles them.
local hookedFrames = setmetatable({}, { __mode = "k" })

-- Reverse map: ChatTypeInfo[key].id (integer) → key (string). Built lazily
-- on first lookup because ChatTypeInfo may not be fully populated at file
-- load. The forward direction (key → info table with .id) is what Blizzard
-- exposes; we want the inverse for incoming AddMessage calls that supply
-- the integer id as the 5th positional arg. Only commit the cache once
-- ChatTypeInfo is actually populated — building empty would silently
-- bypass the whisper-storage gate for the rest of the session.
local idToKey
local function resolveChatTypeKey(chatTypeID)
    if not chatTypeID then return nil end
    if not idToKey and type(ChatTypeInfo) == "table" then
        local m = {}
        for k, v in pairs(ChatTypeInfo) do
            if type(v) == "table" and v.id then
                m[v.id] = k
            end
        end
        if next(m) then idToKey = m end
    end
    return idToKey and idToKey[chatTypeID] or nil
end

-- Whisper-family chatTypeKeys. Used by the storeWhispers gate to drop
-- whisper messages without falling back on locale-fragile text sniffing.
local WHISPER_KEYS = {
    WHISPER          = true,
    WHISPER_INFORM   = true,
    BN_WHISPER       = true,
    BN_WHISPER_INFORM = true,
}

local function captureToHistory(frame, msg, r, g, b, chatTypeID, ...)
    if History._repumping then return end

    -- Secret guards must precede type(msg) and the msg == "" compare —
    -- both push msg as an operand and taint execution, which propagates
    -- back through AddMessage into Blizzard's HistoryKeeper. Same
    -- IsSecretValue-first ordering as copy.lua:135.
    if Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(msg) then return end
    if Helpers and Helpers.HasSecretValue and Helpers.HasSecretValue(r, g, b, chatTypeID) then return end

    if type(msg) ~= "string" or msg == "" then return end

    local settings = I.GetSettings and I.GetSettings()
    local s = settings and settings.history
    if not s or not s.enabled then return end

    -- Find frame ID. Managed frames are ChatFrame1..NUM_CHAT_WINDOWS.
    -- Temp whisper windows / unmanaged frames are not in this range and
    -- get dropped at the not-found check below.
    local frameID
    local nWindows = _G.NUM_CHAT_WINDOWS or 50
    for i = 1, nWindows do
        if _G["ChatFrame" .. i] == frame then
            frameID = i
            break
        end
    end
    if not frameID then return end

    -- Resolve chat-type key from the integer id Blizzard's chat code passes
    -- as the 5th positional arg to AddMessage. May be nil for messages that
    -- don't originate from a CHAT_MSG_* event (system text, slash output).
    local chatTypeKey = resolveChatTypeKey(chatTypeID)

    -- Drop whispers when the user has opted out, gated on the resolved key.
    if not s.storeWhispers and chatTypeKey and WHISPER_KEYS[chatTypeKey] then
        return
    end

    local h = getHistory()
    if not h then return end

    local entries = h.entries
    entries[#entries + 1] = {
        t = (GetServerTime and GetServerTime()) or time(),
        f = frameID,
        m = msg,
        r = r, g = g, b = b,
        c = chatTypeKey,  -- per-channel retention reads this; nil when the
                          -- AddMessage call had no chatTypeID (system/slash).
    }

    -- Soft size warning. Once-per-session; user can lower retention.
    if #entries > 10000 and not h._sizeWarned then
        h._sizeWarned = true
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cff34D399[QUI]|r Chat history exceeds 10,000 entries. Consider lowering the retention setting.",
                1, 1, 1)
        end
    end
end

local function hookFrame(frame)
    if not frame or hookedFrames[frame] then return end
    hookedFrames[frame] = true
    hooksecurefunc(frame, "AddMessage", captureToHistory)
end

local function hookAllManagedFrames()
    local nWindows = _G.NUM_CHAT_WINDOWS or 10
    for i = 1, nWindows do
        local f = _G["ChatFrame" .. i]
        -- Skip combat log frame. Belt-and-suspenders: `frame.isCombatLog`
        -- is the modern flag (robust to user-relocated combat log) but it's
        -- set by Blizzard_CombatLog, a load-on-demand addon — at QUI's
        -- ADDON_LOADED the flag may not be set yet. The `_G.ChatFrame2`
        -- identity check is the unconditional fallback for the standard
        -- combat-log slot.
        if f and not f.isCombatLog and f ~= _G.ChatFrame2 then
            hookFrame(f)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Pruning (time-based, with per-channel overrides)
-- ---------------------------------------------------------------------------

local function pruneExpired()
    local settings = I.GetSettings and I.GetSettings()
    local s = settings and settings.history
    if not s then return end

    local now = (GetServerTime and GetServerTime()) or time()
    local globalCutoff = now - (s.retentionDays or 7) * 86400
    local perChannel = s.perChannelRetention or {}

    local h = getHistory()
    if not h or not h.entries then return end

    local kept = {}
    local entries = h.entries
    for i = 1, #entries do
        local entry = entries[i]
        local cutoff = globalCutoff
        if entry.c and perChannel[entry.c] then
            cutoff = now - perChannel[entry.c] * 86400
        end
        if entry.t and entry.t >= cutoff then
            kept[#kept + 1] = entry
        end
    end
    h.entries = kept
end

-- ---------------------------------------------------------------------------
-- Login re-pump
-- ---------------------------------------------------------------------------

-- The body is wrapped in pcall + a guaranteed flag-reset so any error inside
-- (frame:AddMessage on a weird frame, table.sort on a malformed entry, etc.)
-- can't leave History._repumping stuck at true — that would silently kill
-- captureToHistory for the rest of the session.
local function repump()
    History._repumping = true

    local ok, err = pcall(function()
        local settings = I.GetSettings and I.GetSettings()
        local s = settings and settings.history
        if not s or not s.enabled then return end

        pruneExpired()

        local h = getHistory()
        if not h or not h.entries or #h.entries == 0 then return end

        -- Group entries by frame ID.
        local byFrame = {}
        for i = 1, #h.entries do
            local e = h.entries[i]
            if e.f then
                byFrame[e.f] = byFrame[e.f] or {}
                local list = byFrame[e.f]
                list[#list + 1] = e
            end
        end

        -- Sort each frame's entries chronologically.
        for _, list in pairs(byFrame) do
            table.sort(list, function(a, b) return (a.t or 0) < (b.t or 0) end)
        end

        local sepBefore = "──── Previous session ────"
        local sepAfter  = "──── Resumed ────"
        local sepR, sepG, sepB = 0.5, 0.5, 0.5

        for frameID, list in pairs(byFrame) do
            local frame = _G["ChatFrame" .. frameID]
            if frame then
                if s.showSeparators then
                    frame:AddMessage(sepBefore, sepR, sepG, sepB)
                end
                for i = 1, #list do
                    local e = list[i]
                    frame:AddMessage(e.m or "", e.r or 1, e.g or 1, e.b or 1)
                end
                if s.showSeparators then
                    frame:AddMessage(sepAfter, sepR, sepG, sepB)
                end
            end
        end
    end)

    History._repumping = false

    if not ok and geterrorhandler then
        geterrorhandler()(err)
    end
end

-- ---------------------------------------------------------------------------
-- Public API: Clear history
-- ---------------------------------------------------------------------------

function History.Clear()
    local h = getHistory()
    if h then
        h.entries = {}
        h._sizeWarned = nil
    end
end

function History.GetMessagesForFrame(frameID)
    frameID = tonumber(frameID)
    if not frameID then return {} end

    pruneExpired()

    local h = getHistory()
    if not h or not h.entries then return {} end

    local matches = {}
    local entries = h.entries
    for i = 1, #entries do
        local e = entries[i]
        if e and e.f == frameID and type(e.m) == "string" then
            matches[#matches + 1] = e
        end
    end

    table.sort(matches, function(a, b) return (a.t or 0) < (b.t or 0) end)

    local messages = {}
    for i = 1, #matches do
        messages[#messages + 1] = matches[i].m
    end
    return messages
end

-- ---------------------------------------------------------------------------
-- ApplyEnabled — placeholder for the _afterRefresh dispatch.
-- Capture is decided per-message via the live settings read; there is
-- nothing to install or tear down on toggle. The slot is reserved so that
-- future logic (e.g. dynamic hook attach/detach) can plug in here without
-- disturbing the registration.
-- ---------------------------------------------------------------------------

function ApplyEnabled()
    -- Intentionally no-op for Phase B-T2. See header comment.
end

-- ---------------------------------------------------------------------------
-- Event handler: hook frames at ADDON_LOADED, replay at PLAYER_LOGIN
-- ---------------------------------------------------------------------------
-- ADDON_LOADED is too early for the replay — AceDB initializes in
-- QUICore:OnInitialize which may not have run yet, so getHistory()
-- returns nil and repump silently does nothing. PLAYER_LOGIN is the
-- canonical "everything ready" signal: every addon's OnInitialize has
-- completed, AceDB defaults are wired, and Blizzard's HistoryKeeper
-- has finished its own restore pass. The 100ms defer past PLAYER_LOGIN
-- is kept so any third-party chat addons get to settle first; without
-- it our restored lines can interleave with native restoration.

local addonFrame = CreateFrame("Frame")
addonFrame:RegisterEvent("ADDON_LOADED")
addonFrame:RegisterEvent("PLAYER_LOGIN")
addonFrame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == ADDON_NAME then
        hookAllManagedFrames()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        if C_Timer and C_Timer.After then
            C_Timer.After(0.1, repump)
        else
            repump()
        end
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)

-- New permanent windows opened mid-session also need capture hooks.
-- Idempotent via hookedFrames weak table (re-hooking is a no-op).
if hooksecurefunc and _G.FCF_OpenNewWindow then
    hooksecurefunc("FCF_OpenNewWindow", function(...)
        if C_Timer and C_Timer.After then
            C_Timer.After(0.1, hookAllManagedFrames)
        else
            hookAllManagedFrames()
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Cleanup on chat-window close
-- ---------------------------------------------------------------------------
-- Closing a chat tab (right-click "Close Chat Window", /close, X on a
-- popped-out window — all route through FCF_Close) frees the ChatFrameN
-- slot for FCF_OpenNewWindow to recycle. Without cleanup the closed tab's
-- captured entries linger in SV keyed to that frame ID, then on next login
-- replay into whatever new tab inherits the slot — cross-contaminating an
-- unrelated window. Prune entries for the closed slot at close time.
--
-- ChatFrame2 (combat log) can't be closed and was never captured into, so
-- the hook is a no-op for that slot in practice.

local function getFrameID(frame)
    if not frame then return nil end
    local nWindows = _G.NUM_CHAT_WINDOWS or 50
    for i = 1, nWindows do
        if _G["ChatFrame" .. i] == frame then return i end
    end
    return nil
end

local function pruneFrameID(frameID)
    if not frameID then return end
    local h = getHistory()
    if not h or not h.entries then return end
    local entries = h.entries
    local kept = {}
    for i = 1, #entries do
        local e = entries[i]
        if e.f ~= frameID then
            kept[#kept + 1] = e
        end
    end
    h.entries = kept
    h._sizeWarned = nil
end

if hooksecurefunc and _G.FCF_Close then
    hooksecurefunc("FCF_Close", function(frame)
        pruneFrameID(getFrameID(frame))
    end)
end

table.insert(ns.QUI.Chat._afterRefresh, ApplyEnabled)
