---------------------------------------------------------------------------
-- QUI Chat Module — Persistent History
-- Captures all displayed chat messages into per-character SV. Replays
-- them on next login with session separators. Time-based retention with
-- per-channel overrides. Opt-in whisper storage. Per-channel exclude list.
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
-- Chat-type detection:
--   Blizzard's chat code calls `frame:AddMessage(msg, r, g, b, info.id)`
--   where `info.id` is the integer ChatTypeInfo[<key>].id. We capture that
--   5th positional arg and reverse it back to the chatTypeKey ("WHISPER",
--   "GUILD", "CHANNEL5", etc.) via a one-shot map built from ChatTypeInfo.
--   The key is stamped on each entry as `c` for per-channel retention,
--   gates the storeWhispers filter, and feeds the channel-exclusion gate
--   (CHANNEL%d+ keys are resolved to channel names via GetChannelName).
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

local Helpers = ns.Helpers
-- _G.QUI is the AceAddon (provides .db, set by QUICore:OnInitialize).
-- NOT to be confused with ns.QUI, which is the chat module's namespace
-- bucket — that one has no .db. Capturing the wrong one breaks any
-- code path that needs db.profile / db.char access.
local QUI = _G.QUI

local LOGIN_REPLAY_LIMIT = 500

-- Forward declaration. ApplyEnabled is referenced by the _afterRefresh
-- registration below before its body is defined; without the forward decl
-- closures would capture nil. Same pattern other chat modifiers use.
local ApplyEnabled

-- File-local re-pump flag. When true, the AddMessage hook drops captures
-- so we don't recursively store messages we are replaying.
History._repumping = false

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

local EVENT_TYPE_TO_BASE_KEY = {
    PARTY_LEADER = "PARTY",
    RAID_LEADER = "RAID",
    RAID_WARNING = "RAID",
    INSTANCE_CHAT_LEADER = "INSTANCE_CHAT",
    GUILD_ACHIEVEMENT = "GUILD",
    GUILD_ITEM_LOOTED = "GUILD",
    WHISPER_INFORM = "WHISPER",
    BN_WHISPER_INFORM = "BN_WHISPER",
}

local function readPackedNeverSecret(eventArgs, index)
    if Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(eventArgs) then return nil end
    if type(eventArgs) ~= "table" then return nil end
    local value = eventArgs[index]
    if Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(value) then return nil end
    return value
end

local function resolveChatTypeKeyFromEvent(event, eventArgs)
    if Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(event) then return nil end
    if type(event) ~= "string" then return nil end

    local eventType = event:match("^CHAT_MSG_(.+)$")
    if not eventType then return nil end

    if eventType == "CHANNEL" or eventType == "COMMUNITIES_CHANNEL" then
        -- ChatInfoDocumentation marks channelIndex (payload arg 8) NeverSecret.
        local slot = tonumber(readPackedNeverSecret(eventArgs, 8))
        if slot and slot > 0 then
            return "CHANNEL" .. slot
        end
        return "CHANNEL"
    end

    local categoryList = _G.CHAT_INVERTED_CATEGORY_LIST
    if type(categoryList) == "table" and categoryList[eventType] then
        return categoryList[eventType]
    end
    return EVENT_TYPE_TO_BASE_KEY[eventType] or eventType
end

-- Whisper-family chatTypeKeys. Used by the storeWhispers gate to drop
-- whisper messages without falling back on locale-fragile text sniffing.
local WHISPER_KEYS = {
    WHISPER          = true,
    WHISPER_INFORM   = true,
    BN_WHISPER       = true,
    BN_WHISPER_INFORM = true,
}

local function isExcludedChannel(chatTypeKey, excludedSet)
    if not excludedSet or not chatTypeKey then return false end
    local slotStr = chatTypeKey:match("^CHANNEL(%d+)$")
    if not slotStr then return false end
    local slot = tonumber(slotStr)
    if not slot or not GetChannelName then return false end
    local _, channelName = GetChannelName(slot)
    if not channelName or channelName == "" then return false end
    return excludedSet[channelName] == true
end

local function captureToHistory(frame, msg, r, g, b, chatTypeID, accessID, typeID, event, eventArgs, ...)
    if History._repumping then return end

    -- Secret guards must precede type(msg) and the msg == "" compare —
    -- both push msg as an operand and taint execution, which propagates
    -- back through AddMessage into Blizzard's HistoryKeeper. Same
    -- IsSecretValue-first ordering as copy.lua:135.
    if Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(msg) then return end
    if Helpers and Helpers.HasSecretValue and Helpers.HasSecretValue(r, g, b) then return end

    if type(msg) ~= "string" or msg == "" then return end

    local settings = I.GetSettings and I.GetSettings()
    if not (I.IsChatEnabled and I.IsChatEnabled(settings)) then return end
    local s = settings and settings.history
    if not s or not s.enabled then return end

    local frameID
    local nWindows = _G.NUM_CHAT_WINDOWS or 50
    for i = 1, nWindows do
        if _G["ChatFrame" .. i] == frame then
            frameID = i
            break
        end
    end
    if not frameID then return end

    local chatTypeKey
    if not (Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(chatTypeID)) then
        chatTypeKey = resolveChatTypeKey(chatTypeID)
    end
    if not chatTypeKey then
        chatTypeKey = resolveChatTypeKeyFromEvent(event, eventArgs)
    end

    if not s.storeWhispers and chatTypeKey and WHISPER_KEYS[chatTypeKey] then
        return
    end

    if isExcludedChannel(chatTypeKey, s.excludedChannels) then
        return
    end

    local Storage = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.HistoryStorage
    if not Storage then return end

    Storage.AppendLive({
        t = (GetServerTime and GetServerTime()) or time(),
        f = frameID,
        m = msg,
        r = r, g = g, b = b,
        c = chatTypeKey,
    })
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
-- captureToHistory for the rest of the session.
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

        -- Group by frame, replay.
        local byFrame = {}
        for i = 1, #entries do
            local e = entries[i]
            if e.f then
                byFrame[e.f] = byFrame[e.f] or {}
                local list = byFrame[e.f]
                list[#list + 1] = e
            end
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
        hookAllManagedFrames()
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
