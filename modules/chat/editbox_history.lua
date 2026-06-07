---------------------------------------------------------------------------
-- QUI Chat Module — Edit Box Command History (Persistent)
-- Successor to history_arrows.lua's session-only Up/Down arrow recall.
-- Persists per-character via db.char.chat.editboxHistory.entries.
-- Filters sensitive commands (passwords, /script, etc.) from history.
-- Restores chat type and target on recall.
---------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

-- Defensive: assert _internals exists before reading state through it.
-- Set up by chat.lua, which loads first per chat.xml.
local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: editbox_history.lua loaded before chat.lua. Check chat.xml — chat.lua must precede editbox_history.lua.")

ns.QUI.Chat.EditBoxHistory = ns.QUI.Chat.EditBoxHistory or {}
local EBH = ns.QUI.Chat.EditBoxHistory

-- Forward declaration so event/hook closures below can reference InitializeForFrame
-- before its body is defined.
local InitializeForFrame

-- ---------------------------------------------------------------------------
-- Protected ("secure") slash commands — TAINT SAFETY, unconditional
-- ---------------------------------------------------------------------------
-- Commands such as /tm, /rt, /cast, /target invoke protected functions
-- (SetRaidTarget, CastSpellByName, ...). They must never round-trip through
-- history: recall writes the saved line back to the edit box via an insecure
-- SetText, and the game then reads that tainted text in ParseText and runs the
-- secure-command handler — faulting with ADDON_ACTION_FORBIDDEN on the send.
-- Blizzard's IsSecureCmd identifies the full set, so this gate is mandatory and
-- intentionally independent of any user preference.
local function isProtectedCommand(text)
    if not text or text == "" then return false end
    local cmd = text:match("^(/[^%s]+)")
    if not cmd then return false end
    return (type(IsSecureCmd) == "function" and IsSecureCmd(cmd)) or false
end

-- Policy switch (pending in-game confirmation): allow secure (IsSecureCmd)
-- commands like /tm into recall history. The reference addon excludes them, but
-- that exclusion predates fixing the real taint root cause (the SlashCmdList
-- global reassignment) and QUI recalls via SetText only — never SetAttribute,
-- the actual taint vector. If recalling a secure command via SetText and
-- re-sending is ever found to fault (ADDON_ACTION_FORBIDDEN), set this to false
-- to restore the reference exclude-secure behavior in one place. See
-- [[project_slashcmdlist_global_taint]].
local allowSecureCommands = true

-- ---------------------------------------------------------------------------
-- Sensitive-command list (privacy; gated by the filterSensitive setting)
-- ---------------------------------------------------------------------------
-- These prefixes match commands that frequently embed passwords, secrets, or
-- raw Lua. Keeping them out of saved history is a privacy posture surfaced to
-- users via the filterSensitive toggle (distinct from the taint gate above).
local SENSITIVE_PATTERNS = {
    "^/password",
    "^/logout",
    "^/quit",
    "^/exit",
    "^/dnd",
    "^/afk",
    "^/camp",
    "^/script",
    "^/run",
    "^/console",
}

local function isSensitiveCommand(text)
    if not text or text == "" then return false end
    local lowered = text:lower()
    for i = 1, #SENSITIVE_PATTERNS do
        if lowered:find(SENSITIVE_PATTERNS[i]) then
            return true
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Storage accessor
-- ---------------------------------------------------------------------------
-- Per-character entries live at QUI.db.char.chat.editboxHistory (AceDB
-- per-character namespace). NOT raw QUIDB.<char>.chat — that path collides
-- with AceDB's account-wide root. Mirrors Phase B's db.char.chat.history.
local function getStore()
    if not QUI or not QUI.db or not QUI.db.char then return nil end
    QUI.db.char.chat = QUI.db.char.chat or {}
    QUI.db.char.chat.editboxHistory = QUI.db.char.chat.editboxHistory or
        { schemaVersion = 1, entries = {} }
    if not QUI.db.char.chat.editboxHistory.entries then
        QUI.db.char.chat.editboxHistory.entries = {}
    end
    return QUI.db.char.chat.editboxHistory
end

-- ---------------------------------------------------------------------------
-- Per-edit-box state (cursor position in history, original chat type)
-- ---------------------------------------------------------------------------

-- Cursor: per-edit-box, current 1-based index when navigating history.
-- 1 = most recent. nil = not navigating (fresh input).
local cursors = setmetatable({}, { __mode = "k" })

-- Original input text per edit-box, captured when navigation starts so that
-- walking back past the newest entry restores exactly what the user was typing.
local originalInput = setmetatable({}, { __mode = "k" })

-- ---------------------------------------------------------------------------
-- Capture: use Blizzard's explicit pre-send notification
-- ---------------------------------------------------------------------------
-- The edit-box OnEnterPressed script calls SendText, which calls the protected
-- chat send API. Do not HookScript/SetScript that path. FrameXML triggers
-- ChatFrame.OnEditBoxPreSendText after ParseText and before GetText, which is
-- the safe addon extension point for observing the outgoing message.
local preSendCallbackRegistered = false
-- Stable owner key so the pre-send callback can be both registered and later
-- unregistered (EventRegistry keys callbacks by owner). Shared by
-- RegisterPreSendCallback / UnregisterPreSendCallback so they always agree.
local PRE_SEND_OWNER = "QUI_ChatEditBoxHistory"

local function captureSent(editBox)
    if not editBox then return end
    local chatFrame = editBox.chatFrame
    if I.IsTemporaryChatFrame and I.IsTemporaryChatFrame(chatFrame) then return end

    local settings = I.GetSettings and I.GetSettings()
    if not (I.IsChatEnabled and I.IsChatEnabled(settings)) then return end
    local s = settings and settings.editboxHistory
    if not s or not s.enabled then return end

    local text = editBox:GetText() or ""
    if Helpers.IsSecretValue and Helpers.IsSecretValue(text) then return end
    if not text or text == "" then return end

    -- Reference-mode safety: when secure commands are excluded, never store one
    -- (recalling it could taint the send path). captureSent only ever sees chat
    -- messages in practice (slash commands are captured via AddHistoryLine), but
    -- this keeps the policy consistent across both capture paths.
    if not allowSecureCommands and isProtectedCommand(text) then
        cursors[editBox] = nil
        originalInput[editBox] = nil
        return
    end

    -- Privacy filter (user preference): keep passwords/secrets out of history.
    if s.filterSensitive and isSensitiveCommand(text) then
        cursors[editBox] = nil
        originalInput[editBox] = nil
        return
    end

    local chatType = editBox:GetAttribute("chatType")
    if Helpers.IsSecretValue and Helpers.IsSecretValue(chatType) then return end
    local target = nil
    if chatType == "WHISPER" or chatType == "BN_WHISPER" then
        target = editBox:GetAttribute("tellTarget")
    elseif chatType == "CHANNEL" then
        target = editBox:GetAttribute("channelTarget")
    end
    if target and Helpers.IsSecretValue and Helpers.IsSecretValue(target) then
        target = nil
    end

    local store = getStore()
    if not store then return end

    -- Append.
    store.entries[#store.entries + 1] = {
        ct = chatType,
        tg = target,
        m = text,
    }

    -- FIFO trim at maxEntries.
    local maxEntries = s.maxEntries or 200
    while #store.entries > maxEntries do
        table.remove(store.entries, 1)
    end

    -- Reset cursor on this edit box (a fresh send invalidates the
    -- in-progress navigation, if any).
    cursors[editBox] = nil
    originalInput[editBox] = nil
end

-- ---------------------------------------------------------------------------
-- Capture: slash commands (/qui, /tm, ...) via AddHistoryLine
-- ---------------------------------------------------------------------------
-- captureSent (above) only ever sees actual chat messages. For a slash command,
-- ParseText dispatches it, calls editBox:AddHistoryLine(fullText), then
-- ClearChat() — all BEFORE ChatFrame.OnEditBoxPreSendText fires, so the edit box
-- is already empty by capture time and the command is dropped. Hooking
-- AddHistoryLine is the one place the full command text is still visible.
--
-- Chat messages also reach AddHistoryLine (via AddHistory, prefixed with their
-- channel slash, e.g. "/g hi"). We skip those here so they are not double-stored
-- — captureSent already records them with proper chat-type/target restore. The
-- discriminator: real slash commands live in hash_SlashCmdList; chat-type
-- prefixes live in hash_ChatTypeInfoList.
local function captureSlashCommand(editBox, text)
    if not editBox then return end
    local chatFrame = editBox.chatFrame
    if I.IsTemporaryChatFrame and I.IsTemporaryChatFrame(chatFrame) then return end

    local settings = I.GetSettings and I.GetSettings()
    if not (I.IsChatEnabled and I.IsChatEnabled(settings)) then return end
    local s = settings and settings.editboxHistory
    if not s or not s.enabled then return end

    if not text or text == "" then return end
    if Helpers.IsSecretValue and Helpers.IsSecretValue(text) then return end

    local command = text:match("^(/[^%s]+)")
    if not command then return end
    local key = command:upper()

    -- Only real slash commands belong here. hash_SlashCmdList holds command
    -- handlers (/qui, /tm, /reload, ...); chat-type prefixes (/g, /s, /w, ...)
    -- are NOT in it (they live only in hash_ChatTypeInfoList), so they fall
    -- through to captureSent with proper channel/target restore and are not
    -- double-stored. (hash_ChatTypeInfoList is unusable as a discriminator: per
    -- ChatFrameUtil ImportListToHash it also receives every slash command.)
    local slashList = _G.hash_SlashCmdList
    if not (slashList and slashList[key]) then return end

    -- Reference-mode safety: optionally exclude secure commands (see the
    -- allowSecureCommands policy switch).
    if not allowSecureCommands and isProtectedCommand(text) then return end

    -- Privacy filter (user preference): keep /run, /script, passwords, etc. out.
    if s.filterSensitive and isSensitiveCommand(text) then return end

    local store = getStore()
    if not store then return end

    -- Skip a consecutive duplicate of the same command (matches the reference's
    -- history behavior; avoids spamming the store when a command is repeated).
    local last = store.entries[#store.entries]
    if last and last.m == text and last.ct == nil and last.tg == nil then
        cursors[editBox] = nil
        originalInput[editBox] = nil
        return
    end

    -- Slash commands carry no chat type/target; store the literal line so recall
    -- re-sends it verbatim (ComposeRecallText returns it unchanged).
    store.entries[#store.entries + 1] = { m = text }

    local maxEntries = s.maxEntries or 200
    while #store.entries > maxEntries do
        table.remove(store.entries, 1)
    end

    cursors[editBox] = nil
    originalInput[editBox] = nil
end

local function RegisterPreSendCallback()
    if preSendCallbackRegistered then return end
    if not (EventRegistry and EventRegistry.RegisterCallback) then return end

    preSendCallbackRegistered = true
    EventRegistry:RegisterCallback("ChatFrame.OnEditBoxPreSendText", function(_, editBox)
        pcall(captureSent, editBox)
    end, PRE_SEND_OWNER)
end

-- Tear the pre-send capture callback back down so it is physically gone (not
-- merely short-circuiting) while the chat module / edit-box history is off.
-- EventRegistry keys callbacks by owner, so this removes exactly the one we
-- registered. pcall-guarded as defensive cover; safe to call when nothing is
-- currently registered (the early return handles that).
local function UnregisterPreSendCallback()
    if not preSendCallbackRegistered then return end
    preSendCallbackRegistered = false
    if EventRegistry and EventRegistry.UnregisterCallback then
        pcall(EventRegistry.UnregisterCallback, EventRegistry,
            "ChatFrame.OnEditBoxPreSendText", PRE_SEND_OWNER)
    end
end

-- ---------------------------------------------------------------------------
-- Recall: Up/Down arrow navigation
-- ---------------------------------------------------------------------------

-- Compose the recalled edit-box text, encoding the saved chat type as a leading
-- slash command (e.g. "/w Target msg", "/g msg") so the game's own ParseText
-- re-derives the channel when the line is sent.
--
-- This deliberately avoids editBox:SetAttribute(...) to restore chat type.
-- SetAttribute from addon (insecure) code taints the edit box; a tainted edit
-- box then makes protected slash commands (raid/target markers, etc.) fail with
-- ADDON_ACTION_FORBIDDEN on EVERY subsequent send, even freshly typed ones.
-- Encoding the channel as ordinary text keeps the send path untainted.
local function ComposeRecallText(entry, settings)
    local msg = entry.m or ""
    if not (settings and settings.restoreChatType) then
        return msg
    end

    local ct = entry.ct
    if not ct or ct == "SAY" then
        return msg  -- SAY is the default channel; no prefix needed.
    end

    if ct == "WHISPER" or ct == "BN_WHISPER" then
        if entry.tg then
            return (_G["SLASH_WHISPER1"] or "/w") .. " " .. entry.tg .. " " .. msg
        end
        return msg
    elseif ct == "CHANNEL" then
        if entry.tg then
            return "/" .. entry.tg .. " " .. msg
        end
        return msg
    end

    -- SAY/PARTY/GUILD/RAID/YELL/OFFICER/INSTANCE_CHAT/etc.: canonical slash.
    local slash = _G["SLASH_" .. ct .. "1"]
    if slash then
        return slash .. " " .. msg
    end
    return msg
end

-- Mutating the edit box while chat messaging is in secure lockdown taints the
-- send path; every other chat module guards mutations the same way.
local function IsChatMessagingLockedDown()
    return (I.IsChatMessagingLockedDown and I.IsChatMessagingLockedDown()) or false
end

local function applyEntryToEditBox(editBox, entry, settings)
    if not entry then return end
    local text = ComposeRecallText(entry, settings)
    -- Reference-mode safety: when secure commands are excluded, never write one
    -- back to the edit box (also defends any entries saved while allowed).
    if not allowSecureCommands and isProtectedCommand(text) then return end
    editBox:SetText(text)
    editBox:SetCursorPosition(#text)
end

local function navigateUp(editBox)
    local settings = I.GetSettings and I.GetSettings()
    if not (I.IsChatEnabled and I.IsChatEnabled(settings)) then return end
    local s = settings and settings.editboxHistory
    if not s or not s.enabled then return end
    if IsChatMessagingLockedDown() then return end

    local store = getStore()
    if not store or #store.entries == 0 then return end

    -- Capture the user's current input if starting fresh, so walking back past
    -- the newest entry can restore exactly what they were typing.
    if cursors[editBox] == nil then
        local current = editBox:GetText() or ""
        if Helpers.IsSecretValue and Helpers.IsSecretValue(current) then current = "" end
        originalInput[editBox] = { text = current }
    end

    local cursor = cursors[editBox] or 0
    cursor = cursor + 1
    if cursor > #store.entries then cursor = #store.entries end
    cursors[editBox] = cursor

    -- Index from the END (most-recent first).
    local entry = store.entries[#store.entries - cursor + 1]
    applyEntryToEditBox(editBox, entry, s)
end

local function navigateDown(editBox)
    local settings = I.GetSettings and I.GetSettings()
    if not (I.IsChatEnabled and I.IsChatEnabled(settings)) then return end
    local s = settings and settings.editboxHistory
    if not s or not s.enabled then return end
    if IsChatMessagingLockedDown() then return end

    local store = getStore()
    if not store then return end

    local cursor = cursors[editBox]
    if not cursor then return end  -- not navigating

    cursor = cursor - 1
    if cursor < 1 then
        -- Walked back past the newest entry: restore the user's original input.
        -- No SetAttribute here — navigation never changed the edit box's chat
        -- type, so only the typed text needs restoring.
        cursors[editBox] = nil
        local orig = originalInput[editBox]
        local text = (orig and orig.text) or ""
        editBox:SetText(text)
        editBox:SetCursorPosition(#text)
        originalInput[editBox] = nil
        return
    end

    cursors[editBox] = cursor
    local entry = store.entries[#store.entries - cursor + 1]
    applyEntryToEditBox(editBox, entry, s)
end

-- ---------------------------------------------------------------------------
-- Hook setup per chat-frame edit box
-- ---------------------------------------------------------------------------

local hookedEditBoxes = setmetatable({}, { __mode = "k" })

local function IsEditBoxHistoryEnabled()
    local settings = I.GetSettings and I.GetSettings()
    return (I.IsChatEnabled and I.IsChatEnabled(settings))
        and settings.editboxHistory and settings.editboxHistory.enabled
end

-- Add the pre-send capture callback only while the feature is active; remove it
-- otherwise. Called from load, login, and every settings refresh so toggling
-- the chat module (or the edit-box history sub-toggle) installs/removes the hook
-- live instead of leaving it registered-but-inert.
local function SyncPreSendCallback()
    if IsEditBoxHistoryEnabled() then
        RegisterPreSendCallback()
    else
        UnregisterPreSendCallback()
    end
end

local function ApplyAltArrowModeToEditBox(editBox)
    if editBox and editBox.SetAltArrowKeyMode then
        editBox:SetAltArrowKeyMode(not IsEditBoxHistoryEnabled())
    end
end

local function ApplyAltArrowMode()
    for editBox in pairs(hookedEditBoxes) do
        ApplyAltArrowModeToEditBox(editBox)
    end
end

function InitializeForFrame(chatFrame)
    if not chatFrame then return end
    if I.IsTemporaryChatFrame and I.IsTemporaryChatFrame(chatFrame) then return end
    local frameName = chatFrame.GetName and chatFrame:GetName() or nil
    local editBox = chatFrame.editBox or (frameName and _G[frameName .. "EditBox"]) or nil
    if not editBox then return end

    -- Always sync alt-arrow mode (cheap, idempotent) so disable→enable→disable
    -- toggles always end at native behavior, even if no arrow hook is ever
    -- installed for this editBox.
    ApplyAltArrowModeToEditBox(editBox)

    -- Skip arrow-recall hook installation when chat or editboxHistory is off.
    -- Send capture is handled by RegisterPreSendCallback above; the only
    -- per-editbox script hook left here is arrow navigation.
    if not IsEditBoxHistoryEnabled() then return end

    if hookedEditBoxes[editBox] then return end
    hookedEditBoxes[editBox] = true

    -- Hook OnArrowPressed for recall.
    editBox:HookScript("OnArrowPressed", function(self, key)
        if key == "UP" then
            navigateUp(self)
        elseif key == "DOWN" then
            navigateDown(self)
        end
    end)

    -- Capture slash commands, which ParseText clears before OnEditBoxPreSendText
    -- fires. AddHistoryLine receives the full command text just before the clear.
    -- hooksecurefunc is taint-safe (post-hook, never replaces the secure method).
    if hooksecurefunc and editBox.AddHistoryLine then
        hooksecurefunc(editBox, "AddHistoryLine", function(self, text)
            pcall(captureSlashCommand, self, text)
        end)
    end
end

local function InitializeForAllFrames()
    local n = _G.NUM_CHAT_WINDOWS or 10
    for i = 1, n do
        local f = _G["ChatFrame" .. i]
        -- Skip combat log. Belt-and-suspenders: `frame.isCombatLog` is set
        -- by Blizzard_CombatLog (load-on-demand) so may be nil at
        -- ADDON_LOADED; the `_G.ChatFrame2` identity check is the
        -- unconditional fallback for the standard combat-log slot.
        if f and not f.isCombatLog and f ~= _G.ChatFrame2 then
            InitializeForFrame(f)
        end
    end
end

EBH.InitializeForFrame    = InitializeForFrame
EBH.InitializeForAllFrames = InitializeForAllFrames

-- Test seams (headless unit coverage; not part of the runtime contract).
EBH._IsProtectedCommand   = isProtectedCommand
EBH._captureSent          = captureSent
EBH._captureSlashCommand  = captureSlashCommand
EBH._applyEntryToEditBox  = applyEntryToEditBox
EBH._SetAllowSecureCommands = function(v) allowSecureCommands = v end

-- ---------------------------------------------------------------------------
-- ApplyEnabled: settings change hook
-- ---------------------------------------------------------------------------
-- Add or remove the pre-send capture callback to match the current enabled
-- state, sync alt-arrow mode on already-hooked editboxes, then arm arrow
-- navigation on any editboxes that weren't hooked at load (toggle off→on flow).
-- The per-editbox OnArrowPressed / AddHistoryLine hooks cannot be unhooked
-- (HookScript and hooksecurefunc are permanent in the WoW API, and the latter
-- is the taint-safe way to observe AddHistoryLine), so they are installed only
-- while enabled (see InitializeForFrame's IsEditBoxHistoryEnabled gate) and
-- otherwise short-circuit via the same gate inside captureSlashCommand /
-- navigate; toggling the chat module is live, so the inert hooks simply
-- remain installed and short-circuit until re-enabled.
local function ApplyEnabled()
    SyncPreSendCallback()
    ApplyAltArrowMode()
    InitializeForAllFrames()
end

-- Initial hook setup at file-load (defensive — frames may not exist yet).
SyncPreSendCallback()
InitializeForAllFrames()

local addonFrame = CreateFrame("Frame")
addonFrame:RegisterEvent("ADDON_LOADED")
addonFrame:RegisterEvent("PLAYER_LOGIN")
addonFrame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == ADDON_NAME then
        SyncPreSendCallback()
        InitializeForAllFrames()
    elseif event == "PLAYER_LOGIN" then
        SyncPreSendCallback()
        InitializeForAllFrames()
    end
end)

-- Hook FCF_OpenNewWindow / FCF_OpenTemporaryWindow so newly created edit
-- boxes pick up the recall behavior without a /reload.
if hooksecurefunc then
    if _G.FCF_OpenNewWindow then
        hooksecurefunc("FCF_OpenNewWindow", function() InitializeForAllFrames() end)
    end
    if _G.FCF_OpenTemporaryWindow then
        hooksecurefunc("FCF_OpenTemporaryWindow", function() InitializeForAllFrames() end)
    end
end

table.insert(ns.QUI.Chat._afterRefresh, ApplyEnabled)
