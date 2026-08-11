local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: editbox_history.lua loaded before chat.lua. Check chat.xml — chat.lua must precede editbox_history.lua.")

ns.QUI.Chat.EditBoxHistory = ns.QUI.Chat.EditBoxHistory or {}
local EBH = ns.QUI.Chat.EditBoxHistory

local InitializeForFrame

local function isProtectedCommand(text)
    if not text or text == "" then return false end
    local cmd = text:match("^(/[^%s]+)")
    if not cmd then return false end
    return (type(IsSecureCmd) == "function" and IsSecureCmd(cmd)) or false
end

local allowSecureCommands = true

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

local cursors = setmetatable({}, { __mode = "k" })

local originalInput = setmetatable({}, { __mode = "k" })

local function pushEntry(store, entry, s, editBox)
    store.entries[#store.entries + 1] = entry
    local maxEntries = s.maxEntries or 200
    while #store.entries > maxEntries do
        table.remove(store.entries, 1)
    end
    cursors[editBox] = nil
    originalInput[editBox] = nil
end

local preSendCallbackRegistered = false
local PRE_SEND_OWNER = "QUI_ChatEditBoxHistory"

local function captureSent(editBox)
    if not editBox then return end
    local chatFrame = editBox.chatFrame
    if I.IsTemporaryChatFrame and I.IsTemporaryChatFrame(chatFrame) then return end

    local settings = I.GetSettings and I.GetSettings()
    if not (I.IsChatEnabled and I.IsChatEnabled(settings)) then return end
    local s = settings and settings.editboxHistory
    if not s or not s.enabled then return end

    local text = editBox:GetText()
    if Helpers.IsSecretValue and Helpers.IsSecretValue(text) then return end
    if not text or text == "" then return end

    if not allowSecureCommands and isProtectedCommand(text) then
        cursors[editBox] = nil
        originalInput[editBox] = nil
        return
    end

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
    if Helpers.IsSecretValue and Helpers.IsSecretValue(target) then
        target = nil
    end

    local store = getStore()
    if not store then return end

    pushEntry(store, { ct = chatType, tg = target, m = text }, s, editBox)
end

local function captureSlashCommand(editBox, text)
    if not editBox then return end
    local chatFrame = editBox.chatFrame
    if I.IsTemporaryChatFrame and I.IsTemporaryChatFrame(chatFrame) then return end

    local settings = I.GetSettings and I.GetSettings()
    if not (I.IsChatEnabled and I.IsChatEnabled(settings)) then return end
    local s = settings and settings.editboxHistory
    if not s or not s.enabled then return end

    if Helpers.IsSecretValue and Helpers.IsSecretValue(text) then return end
    if not text or text == "" then return end

    local command = text:match("^(/[^%s]+)")
    if not command then return end
    local key = command:upper()

    local slashList = _G.hash_SlashCmdList
    if not (slashList and slashList[key]) then return end

    if not allowSecureCommands and isProtectedCommand(text) then return end

    if s.filterSensitive and isSensitiveCommand(text) then return end

    local store = getStore()
    if not store then return end

    local last = store.entries[#store.entries]
    if last and last.m == text and last.ct == nil and last.tg == nil then
        cursors[editBox] = nil
        originalInput[editBox] = nil
        return
    end

    pushEntry(store, { m = text }, s, editBox)
end

local function RegisterPreSendCallback()
    if preSendCallbackRegistered then return end
    if not (EventRegistry and EventRegistry.RegisterCallback) then return end

    preSendCallbackRegistered = true
    EventRegistry:RegisterCallback("ChatFrame.OnEditBoxPreSendText", function(_, editBox)
        ns.SafeCall("bulkhead", captureSent, editBox)
    end, PRE_SEND_OWNER)
end

local function UnregisterPreSendCallback()
    if not preSendCallbackRegistered then return end
    preSendCallbackRegistered = false
    if EventRegistry and EventRegistry.UnregisterCallback then
        pcall(EventRegistry.UnregisterCallback, EventRegistry,
            "ChatFrame.OnEditBoxPreSendText", PRE_SEND_OWNER)
    end
end

local function ComposeRecallText(entry, settings)
    local msg = entry.m or ""
    if not (settings and settings.restoreChatType) then
        return msg
    end

    local ct = entry.ct
    if not ct or ct == "SAY" then
        return msg
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

    local slash = _G["SLASH_" .. ct .. "1"]
    if slash then
        return slash .. " " .. msg
    end
    return msg
end

local function IsChatMessagingLockedDown()
    return (I.IsChatMessagingLockedDown and I.IsChatMessagingLockedDown()) or false
end

local function applyEntryToEditBox(editBox, entry, settings)
    if not entry then return end
    local text = ComposeRecallText(entry, settings)
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

    if cursors[editBox] == nil then
        local current = editBox:GetText()
        if Helpers.IsSecretValue and Helpers.IsSecretValue(current) then current = nil end
        originalInput[editBox] = { text = current or "" }
    end

    local cursor = cursors[editBox] or 0
    cursor = cursor + 1
    if cursor > #store.entries then cursor = #store.entries end
    cursors[editBox] = cursor

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
    if not cursor then return end

    cursor = cursor - 1
    if cursor < 1 then
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

local hookedEditBoxes = setmetatable({}, { __mode = "k" })

local function IsEditBoxHistoryEnabled()
    local settings = I.GetSettings and I.GetSettings()
    return (I.IsChatEnabled and I.IsChatEnabled(settings))
        and settings.editboxHistory and settings.editboxHistory.enabled
end

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

    ApplyAltArrowModeToEditBox(editBox)

    if not IsEditBoxHistoryEnabled() then return end

    if hookedEditBoxes[editBox] then return end
    hookedEditBoxes[editBox] = true

    editBox:HookScript("OnArrowPressed", function(self, key)
        if key == "UP" then
            navigateUp(self)
        elseif key == "DOWN" then
            navigateDown(self)
        end
    end)

    if hooksecurefunc and editBox.AddHistoryLine then
        hooksecurefunc(editBox, "AddHistoryLine", function(self, text)
            ns.SafeCall("bulkhead", captureSlashCommand, self, text)
        end)
    end
end

local function InitializeForAllFrames()
    local n = _G.NUM_CHAT_WINDOWS or 10
    for i = 1, n do
        local f = _G["ChatFrame" .. i]
        if f and not f.isCombatLog and f ~= _G.ChatFrame2 then
            InitializeForFrame(f)
        end
    end
end

EBH.InitializeForFrame    = InitializeForFrame
EBH.InitializeForAllFrames = InitializeForAllFrames

EBH._IsProtectedCommand   = isProtectedCommand
EBH._captureSent          = captureSent
EBH._captureSlashCommand  = captureSlashCommand
EBH._applyEntryToEditBox  = applyEntryToEditBox
EBH._SetAllowSecureCommands = function(v) allowSecureCommands = v end

local function ApplyEnabled()
    SyncPreSendCallback()
    ApplyAltArrowMode()
    InitializeForAllFrames()
end

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

if hooksecurefunc then
    if _G.FCF_OpenNewWindow then
        hooksecurefunc("FCF_OpenNewWindow", function() InitializeForAllFrames() end)
    end
    if _G.FCF_OpenTemporaryWindow then
        hooksecurefunc("FCF_OpenTemporaryWindow", function() InitializeForAllFrames() end)
    end
end

table.insert(ns.QUI.Chat._afterRefresh, ApplyEnabled)
