---------------------------------------------------------------------------
-- QUI Chat Module — Persistent History
-- Captures all displayed chat messages into per-character SV. Replays
-- them on next login with session separators. Time-based retention with
-- per-channel overrides. Opt-in whisper storage. Per-channel exclude list.
--
-- Single-path ownership: the store subscriber (installed at ADDON_LOADED)
-- owns ALL capture. Capture starts at ADDON_LOADED so entries exist before
-- PLAYER_ENTERING_WORLD; no AddMessage hook path exists.
--
-- Storage layout:
--   Settings : db.profile.chat.history       (toggles, retention sliders)
--   Entries  : QUI_ChatHistory (per-character SV file via Storage)
--
-- Per-character semantics come from Blizzard's per-character SavedVariables
-- file (declared in QUI.toc as `SavedVariablesPerCharacter`). The earlier
-- AceDB-backed slot (`db.char.chat.history.entries`) is migrated once on
-- first load via Storage.MigrateFromAceDB.
--
-- Persistence model:
--   Captures append to Storage's plain `current` SV array. Older entries are
--   rotated into small serialized chunks, so normal reloads no longer
--   compress or decompress the entire history. Login replay and copy request
--   bounded recent slices and only decode the newest chunks they need.
---------------------------------------------------------------------------

local ADDON_NAME, ns = ...

local I = assert(ns.QUI and ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: history.lua loaded before chat.lua. Check chat.xml — chat.lua must precede history.lua.")

ns.QUI.Chat.History = ns.QUI.Chat.History or {}
local History = ns.QUI.Chat.History

local LOGIN_REPLAY_LIMIT = 500

-- Forward declaration. ApplyEnabled is referenced by the _afterRefresh
-- registration below before its body is defined; without the forward decl
-- closures would capture nil. Same pattern other chat modifiers use.
local ApplyEnabled

-- File-local re-pump flag. When true, the store subscriber drops captures
-- so we don't recursively store messages we are replaying.
History._repumping = false

-- Latch: store subscriber installed at most once per session.
local storeSubscribed = false

-- ---------------------------------------------------------------------------
-- Capture: store subscriber (single-path)
-- ---------------------------------------------------------------------------

-- Whisper-family chatTypeKeys. Used by the storeWhispers gate to drop
-- whisper messages without falling back on locale-fragile text sniffing.
-- Shared with message_capture via chat.lua's _internals (loads first).
local WHISPER_KEYS = I.WHISPER_TYPE_KEYS

-- excludedChannels is keyed by channel NAME (same GetChannelList spelling the
-- settings UI stores and Registry.ResolveName produces). Live channel captures
-- carry k="CHANNEL" — no slot digits, the slot only feeds the color key — so
-- entry.ch is the primary match; the CHANNEL<slot> path is only a fallback for
-- entries that carry a slot-suffixed key without a channel name.
local function isExcludedChannel(chatTypeKey, channelName, excludedSet)
    if not excludedSet then return false end
    if type(channelName) == "string" and channelName ~= ""
       and excludedSet[channelName] == true then
        return true
    end
    if type(chatTypeKey) ~= "string" then return false end
    local slotStr = chatTypeKey:match("^CHANNEL(%d+)$")
    if not slotStr then return false end
    local slot = tonumber(slotStr)
    if not slot or not GetChannelName then return false end
    local resolvedName = select(2, GetChannelName(slot))
    if not resolvedName or resolvedName == "" then return false end
    return excludedSet[resolvedName] == true
end

-- Store subscriber owns ALL capture (pre-PEW and steady state). Capture
-- starts at ADDON_LOADED so entries exist before PLAYER_ENTERING_WORLD;
-- no AddMessage hook path exists. f=1: frame-agnostic; entries record the
-- default-frame slot.
local function captureFromStore(entry)
    if History._repumping then return end
    if entry.hist then return end -- a replayed history line; never re-capture it
    if entry.s then return end -- secrets are never persisted
    if type(entry.m) ~= "string" or entry.m == "" then return end -- future producers
    local e = entry.e
    if e == "ADDMESSAGE" or e == "BACKFILL" or e == "HISTORY" then return end
    -- /played output is point-in-time: replaying stale totals every login
    -- reads as "/played fired multiple times". Never persist it.
    if e == "TIME_PLAYED_MSG" then return end
    local settings = I.GetSettings and I.GetSettings()
    if not (I.IsChatEnabled and I.IsChatEnabled(settings)) then return end
    local s = settings and settings.history
    if not s or not s.enabled then return end
    local chatTypeKey = entry.k
    if not s.storeWhispers and chatTypeKey and WHISPER_KEYS[chatTypeKey] then return end
    if isExcludedChannel(chatTypeKey, entry.ch, s.excludedChannels) then return end
    local Storage = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.HistoryStorage
    if not Storage then return end
    Storage.AppendLive({
        t = entry.t or ((GetServerTime and GetServerTime()) or time()),
        f = 1,
        m = entry.m,
        r = entry.r, g = entry.g, b = entry.b,
        c = chatTypeKey,
        -- Routing fields, so login replay can flow through the SAME per-window
        -- tab filters as live traffic instead of fanning into every window:
        -- channel name (named-channel routing), source event (group fallback
        -- for keys like PARTY_LEADER), whisper conversation key (conversation
        -- tab routing). All nil for traffic that doesn't carry them.
        ch = entry.ch,
        ev = entry.e,
        w = entry.w,
    }, s.maxEntries)
end

-- Export for the test harness (the real subscriber installs on ADDON_LOADED,
-- not directly reachable from Lua unit tests).
History._CaptureFromStore = captureFromStore

-- ---------------------------------------------------------------------------
-- Pruning
-- ---------------------------------------------------------------------------

-- Single logout pass: prune by retention, cap by count, and normalize chunk
-- metadata. Forced even in combat because /reload mid-combat fires LOGOUT.
local function pruneAndPersist()
    local Storage = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.HistoryStorage
    if not Storage then return end

    local settings = I.GetSettings and I.GetSettings()
    local s = settings and settings.history
    if not s or not s.enabled then
        Storage.PersistNow()
        return
    end

    if Storage.Prune then
        Storage.Prune(s)
    end
    Storage.PersistNow()
end

-- ---------------------------------------------------------------------------
-- Login re-pump
-- ---------------------------------------------------------------------------

-- The body is wrapped in pcall + a guaranteed flag-reset so any error inside
-- (frame:AddMessage on a weird frame, table.sort on a malformed entry, etc.)
-- can't leave History._repumping stuck at true — that would silently kill
-- the store-subscriber capture for the rest of the session.
local function repump()
    History._repumping = true

    local ok, err = pcall(function()
        local settings = I.GetSettings and I.GetSettings()
        if not (I.IsChatEnabled and I.IsChatEnabled(settings)) then return end
        local s = settings and settings.history
        if not s or not s.enabled then return end

        local Storage = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.HistoryStorage
        if not Storage then return end

        if Storage.Prune then
            Storage.Prune(s)
        end

        local replayLimit = tonumber(s.replayLines) or LOGIN_REPLAY_LIMIT
        local entries = Storage.GetRecentEntries and Storage.GetRecentEntries(replayLimit) or {}
        if #entries == 0 then return end

        local sepBefore = "---- Previous session ----"
        local sepAfter  = "---- Resumed ----"
        local sepR, sepG, sepB = 0.5, 0.5, 0.5

        -- Chat enabled = the QUI display owns rendering; repump goes to the
        -- store. (Repump never runs with chat disabled — gated above.)
        -- hist=true marks every replayed line so capture and sounds skip it
        -- (each line now carries its ORIGINAL event for routing, so the old
        -- e=="HISTORY" guard can no longer identify it).
        -- History._repumping is still true here (we are inside the pcall).
        local StoreMod = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.MessageStore
        if StoreMod and StoreMod.Append then
            local now = (GetServerTime and GetServerTime()) or time()
            -- Separators are synthetic session markers: SYSTEM-keyed so they
            -- surface in the main/default tabs.
            local function pumpSeparator(m)
                StoreMod.Append({ m = m, r = sepR, g = sepG, b = sepB,
                    e = "HISTORY", k = "SYSTEM", hist = true, t = now })
            end
            -- Replayed entries carry their original routing fields (type key,
            -- channel name, source event, whisper conversation) so each window's
            -- tab filter routes them exactly like live traffic.
            local function pumpEntry(rec)
                StoreMod.Append({
                    m = rec.m or "", r = rec.r or 1, g = rec.g or 1, b = rec.b or 1,
                    k = rec.c, ch = rec.ch, e = rec.ev, w = rec.w,
                    hist = true, t = rec.t or now,
                })
            end
            if s.showSeparators then pumpSeparator(sepBefore) end
            for i = 1, #entries do
                -- Stale /played totals from earlier sessions read as repeated
                -- /played output; skip them on replay (capture no longer
                -- persists new ones, this purges already-saved data).
                if entries[i].ev ~= "TIME_PLAYED_MSG" then
                    pumpEntry(entries[i])
                end
            end
            if s.showSeparators then pumpSeparator(sepAfter) end
        end
    end)

    History._repumping = false

    if not ok and geterrorhandler then
        geterrorhandler()(err)
    end
end

-- Export for the test harness: repump() is local; the PLAYER_LOGIN C_Timer
-- path is not directly reachable in unit tests without mocking the event
-- loop. Tests call History._Repump() directly.
History._Repump = repump

-- ---------------------------------------------------------------------------
-- Public API: Clear history
-- ---------------------------------------------------------------------------

function History.Clear()
    local Storage = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.HistoryStorage
    if Storage and Storage.Clear then Storage.Clear() end
end

function History.ClearAllCharacters()
    local Storage = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.HistoryStorage
    if not Storage or not Storage.ClearAllCharacters then return 0, 0, nil end
    return Storage.ClearAllCharacters()
end

function History.GetMessagesForFrame(frameID, limit)
    frameID = tonumber(frameID)
    if not frameID then return {} end

    local Storage = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.HistoryStorage
    if not Storage then return {} end

    local cap = tonumber(limit)
    local entries = Storage.GetRecentForFrame and Storage.GetRecentForFrame(frameID, cap) or {}
    local messages = {}
    for i = 1, #entries do
        local e = entries[i]
        if e and type(e.m) == "string" then
            messages[#messages + 1] = e.m
        end
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
-- ADDON_LOADED is too early for the replay — Storage.Init runs there,
-- but Storage.MigrateFromAceDB needs QUI.db.keys.char which AceDB only
-- populates in QUICore:OnInitialize. PLAYER_LOGIN is the canonical
-- "everything ready" signal: every addon's OnInitialize has completed,
-- AceDB defaults are wired, and Blizzard's HistoryKeeper has finished
-- its own restore pass. The 100ms defer past PLAYER_LOGIN is kept so
-- any third-party chat addons get to settle first; without it our
-- restored lines can interleave with native restoration.

local addonFrame = CreateFrame("Frame")
addonFrame:RegisterEvent("ADDON_LOADED")
addonFrame:RegisterEvent("PLAYER_LOGIN")
addonFrame:RegisterEvent("PLAYER_LOGOUT")
addonFrame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == ADDON_NAME then
        local Storage = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.HistoryStorage
        if Storage and Storage.Init then Storage.Init() end
        -- Subscribe once so captureFromStore receives every new store entry.
        if not storeSubscribed then
            local MsgStore = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.MessageStore
            if MsgStore and MsgStore.OnAppend then
                storeSubscribed = true
                MsgStore.OnAppend(captureFromStore)
            end
        end
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        local Storage = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.HistoryStorage
        if Storage and Storage.MigrateFromAceDB then
            Storage.MigrateFromAceDB()
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0.1, repump)
        else
            repump()
        end
        self:UnregisterEvent("PLAYER_LOGIN")
    elseif event == "PLAYER_LOGOUT" then
        pruneAndPersist()
    end
end)

-- ---------------------------------------------------------------------------
-- Cleanup on chat-window close
-- ---------------------------------------------------------------------------
-- Closing a chat tab (right-click "Close Chat Window", /close, X on a
-- popped-out window — all route through FCF_Close) frees the ChatFrameN
-- slot for FCF_OpenNewWindow to recycle. Without cleanup the closed tab's
-- captured entries linger keyed to that frame ID, then on next login
-- replay into whatever new tab inherits the slot — cross-contaminating
-- an unrelated window.
--
-- ChatFrame2 (combat log) can't be closed and was never captured into, so
-- the hook is a no-op for that slot in practice.
--
-- Eager prune delegates to Storage, which rewrites only affected chunks and
-- the plain current buffer.

local function getFrameID(frame)
    if not frame then return nil end
    local nWindows = _G.NUM_CHAT_WINDOWS or 50
    for i = 1, nWindows do
        if _G["ChatFrame" .. i] == frame then return i end
    end
    return nil
end

local function pruneClosedFrame(frameID)
    if not frameID then return end
    local Storage = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.HistoryStorage
    if Storage and Storage.RemoveFrame then
        Storage.RemoveFrame(frameID)
    end
end

if hooksecurefunc and _G.FCF_Close then
    hooksecurefunc("FCF_Close", function(frame)
        pruneClosedFrame(getFrameID(frame))
    end)
end

table.insert(ns.QUI.Chat._afterRefresh, ApplyEnabled)
