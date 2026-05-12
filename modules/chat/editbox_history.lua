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
-- Secure-command allowlist (const; not user-editable)
-- ---------------------------------------------------------------------------
-- These prefixes match commands that frequently embed passwords, secrets, or
-- raw Lua. Filtering them out of history is a security posture, not a user
-- preference, so the table is intentionally not exposed to settings.
local SECURE_PATTERNS = {
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

local function isSecureCommand(text)
    if not text or text == "" then return false end
    local lowered = text:lower()
    for i = 1, #SECURE_PATTERNS do
        if lowered:find(SECURE_PATTERNS[i]) then
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

-- Original chat-type per edit-box, captured when navigation starts so that
-- walking past newest can restore it.
local originalTypes = setmetatable({}, { __mode = "k" })

local function IsChatAttributeLockedDown()
    return (type(InCombatLockdown) == "function" and InCombatLockdown())
        or (I.IsChatMessagingLockedDown and I.IsChatMessagingLockedDown())
end

-- ---------------------------------------------------------------------------
-- Capture: use Blizzard's explicit pre-send notification
-- ---------------------------------------------------------------------------
-- The edit-box OnEnterPressed script calls SendText, which calls the protected
-- chat send API. Do not HookScript/SetScript that path. FrameXML triggers
-- ChatFrame.OnEditBoxPreSendText after ParseText and before GetText, which is
-- the safe addon extension point for observing the outgoing message.
local preSendCallbackRegistered = false

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

    -- Filter sensitive commands.
    if s.filterSensitive and isSecureCommand(text) then
        cursors[editBox] = nil
        originalTypes[editBox] = nil
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
    originalTypes[editBox] = nil
end

local function RegisterPreSendCallback()
    if preSendCallbackRegistered then return end
    if not (EventRegistry and EventRegistry.RegisterCallback) then return end

    preSendCallbackRegistered = true
    EventRegistry:RegisterCallback("ChatFrame.OnEditBoxPreSendText", function(_, editBox)
        pcall(captureSent, editBox)
    end, "QUI_ChatEditBoxHistory")
end

-- ---------------------------------------------------------------------------
-- Recall: Up/Down arrow navigation
-- ---------------------------------------------------------------------------

local function applyEntryToEditBox(editBox, entry, settings)
    if not entry then return end

    editBox:SetText(entry.m or "")

    if settings and settings.restoreChatType and entry.ct and not IsChatAttributeLockedDown() then
        editBox:SetAttribute("chatType", entry.ct)
        if entry.tg then
            if entry.ct == "WHISPER" or entry.ct == "BN_WHISPER" then
                editBox:SetAttribute("tellTarget", entry.tg)
            elseif entry.ct == "CHANNEL" then
                editBox:SetAttribute("channelTarget", entry.tg)
            end
        end
        -- Re-trigger header update so the chat-type prefix re-renders.
        if ChatEdit_UpdateHeader then
            ChatEdit_UpdateHeader(editBox)
        end
    end

    editBox:SetCursorPosition(#(entry.m or ""))
end

local function navigateUp(editBox)
    local settings = I.GetSettings and I.GetSettings()
    if not (I.IsChatEnabled and I.IsChatEnabled(settings)) then return end
    local s = settings and settings.editboxHistory
    if not s or not s.enabled then return end

    local store = getStore()
    if not store or #store.entries == 0 then return end

    -- Capture original chat type if starting fresh.
    if cursors[editBox] == nil then
        originalTypes[editBox] = {
            ct = editBox:GetAttribute("chatType"),
            tg = editBox:GetAttribute("tellTarget") or editBox:GetAttribute("channelTarget"),
        }
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

    local store = getStore()
    if not store then return end

    local cursor = cursors[editBox]
    if not cursor then return end  -- not navigating

    cursor = cursor - 1
    if cursor < 1 then
        -- Walked past newest. Restore original.
        cursors[editBox] = nil
        local orig = originalTypes[editBox]
        editBox:SetText("")
        if orig and s.restoreChatType and orig.ct and not IsChatAttributeLockedDown() then
            editBox:SetAttribute("chatType", orig.ct)
            if ChatEdit_UpdateHeader then ChatEdit_UpdateHeader(editBox) end
        end
        originalTypes[editBox] = nil
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

-- ---------------------------------------------------------------------------
-- ApplyEnabled: settings change hook
-- ---------------------------------------------------------------------------
-- Sync alt-arrow mode on already-hooked editboxes, then arm arrow navigation on
-- any editboxes that weren't hooked at load (toggle off→on flow). Once
-- installed, disabling later is handled by the IsEditBoxHistoryEnabled() gate
-- inside captureSent / navigate.
local function ApplyEnabled()
    RegisterPreSendCallback()
    ApplyAltArrowMode()
    InitializeForAllFrames()
end

-- Initial hook setup at file-load (defensive — frames may not exist yet).
RegisterPreSendCallback()
InitializeForAllFrames()

local addonFrame = CreateFrame("Frame")
addonFrame:RegisterEvent("ADDON_LOADED")
addonFrame:RegisterEvent("PLAYER_LOGIN")
addonFrame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == ADDON_NAME then
        RegisterPreSendCallback()
        InitializeForAllFrames()
    elseif event == "PLAYER_LOGIN" then
        RegisterPreSendCallback()
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
