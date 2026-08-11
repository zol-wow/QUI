local ADDON_NAME, ns = ... -- luacheck: ignore ADDON_NAME

local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: conversation_manager.lua loaded before chat.lua. Check chat.xml — chat.lua must precede conversation_manager.lua.")

ns.QUI.Chat.ConversationManager = ns.QUI.Chat.ConversationManager or {}
local Conv = ns.QUI.Chat.ConversationManager

local Store = assert(ns.QUI.Chat.MessageStore,
    "message_store.lua must load before conversation_manager.lua")

local function IsSecret(v)
    return ns.Helpers and ns.Helpers.IsSecretValue and ns.Helpers.IsSecretValue(v) or false
end

local conversations = {}
local order = {}

local WHISPER_EVENTS = {
    CHAT_MSG_WHISPER           = { chatType = "WHISPER",    incoming = true  },
    CHAT_MSG_WHISPER_INFORM    = { chatType = "WHISPER",    incoming = false },
    CHAT_MSG_BN_WHISPER        = { chatType = "BN_WHISPER", incoming = true  },
    CHAT_MSG_BN_WHISPER_INFORM = { chatType = "BN_WHISPER", incoming = false },
}
Conv.WHISPER_EVENTS = WHISPER_EVENTS

function Conv.DeriveKey(chatType, counterparty)
    if IsSecret(counterparty) or type(counterparty) ~= "string" or counterparty == "" then
        return nil
    end
    if chatType ~= "BN_WHISPER" and not counterparty:find("-", 1, true)
        and _G.GetNormalizedRealmName then
        local realm = _G.GetNormalizedRealmName()
        if type(realm) == "string" and realm ~= "" then
            counterparty = counterparty .. "-" .. realm
        end
    end
    local prefix = (chatType == "BN_WHISPER") and "BN:" or "W:"
    return prefix .. counterparty:lower()
end

local function WhisperSettings()
    local settings = I.GetSettings and I.GetSettings()
    local cd = settings and settings.customDisplay
    return cd and cd.whisperTabs or nil
end

local function GetWhisperMode()
    if type(_G.GetCVar) ~= "function" then return nil end
    local ok, value = pcall(_G.GetCVar, "whisperMode")
    if ok then return value end
    return nil
end

local function BlizzardWantsConversationTab(wt)
    if wt and wt.translatePopout == false then return false end
    local mode = GetWhisperMode()
    return mode == "popout" or mode == "popout_and_inline"
end

local function ClampWindowID(windowID)
    local Display = ns.QUI.Chat.DisplayLayer
    local n = (Display and Display.GetWindowCount and Display.GetWindowCount()) or 1
    if n < 1 then n = 1 end
    windowID = tonumber(windowID) or 1
    if windowID < 1 or windowID > n then return 1 end
    return windowID
end

function Conv.IsOpen(key)
    return conversations[key] ~= nil
end

function Conv.Get(key)
    return conversations[key]
end

function Conv.EachForWindow(windowID, fn)
    for i = 1, #order do
        local c = conversations[order[i]]
        if c and c.windowID == windowID then fn(c) end
    end
end

local function RefreshAfterChange()
    local TabUI = ns.QUI.Chat.TabUI
    if TabUI and TabUI.Rebuild then TabUI.Rebuild() end
end

function Conv.Open(chatType, target, windowID, activate)
    local key = Conv.DeriveKey(chatType, target)
    if not key then return nil end
    local existing = conversations[key]
    if existing then
        if activate then
            local TabUI = ns.QUI.Chat.TabUI
            if TabUI and TabUI.ActivateConversation then
                TabUI.ActivateConversation(existing.windowID, key)
            end
        end
        return key
    end
    windowID = ClampWindowID(windowID)
    local name = target
    if chatType == "WHISPER" and _G.Ambiguate then
        name = _G.Ambiguate(target, "short")
    end
    conversations[key] = {
        key      = key,
        chatType = chatType,
        target   = target,
        name     = name,
        windowID = windowID,
    }
    order[#order + 1] = key
    RefreshAfterChange()
    local TabUI = ns.QUI.Chat.TabUI
    if activate then
        if TabUI and TabUI.ActivateConversation then
            TabUI.ActivateConversation(windowID, key)
        end
    elseif TabUI and TabUI.FlashConversation then
        TabUI.FlashConversation(windowID, key)
    end
    return key
end

function Conv.Close(key)
    if not conversations[key] then return end
    conversations[key] = nil
    for i = #order, 1, -1 do
        if order[i] == key then table.remove(order, i) end
    end
    if key == Conv.GetPreTargetedKey() then
        Conv.ClearPreTarget()
    end
    RefreshAfterChange()
end

function Conv.OnWindowDeleted(windowID)
    for _, c in pairs(conversations) do
        if c.windowID == windowID then
            c.windowID = 1
        elseif c.windowID > windowID then
            c.windowID = c.windowID - 1
        end
    end
end

local preTargetedKey

function Conv.PreTargetEditBox(key)
    local c = conversations[key]
    local eb = _G.ChatFrame1EditBox
    if not (c and eb) then return end
    if eb.HasFocus and eb:HasFocus() then
        if eb.HasText then
            if eb:HasText() then return end
        elseif type(eb.GetText) == "function" and (eb:GetText() or "") ~= "" then
            return
        end
    end
    if eb.SetChatType then eb:SetChatType(c.chatType)
    elseif eb.SetAttribute then eb:SetAttribute("chatType", c.chatType) end
    if eb.SetTellTarget then eb:SetTellTarget(c.target)
    elseif eb.SetAttribute then eb:SetAttribute("tellTarget", c.target) end
    if eb.UpdateHeader then eb:UpdateHeader() end
    preTargetedKey = key
end

function Conv.GetPreTargetedKey()
    return preTargetedKey
end

function Conv.ClearPreTarget()
    if not preTargetedKey then return end
    preTargetedKey = nil
    local eb = _G.ChatFrame1EditBox
    if not eb then return end
    if eb.HasFocus and eb:HasFocus() then
        if eb.HasText then
            if eb:HasText() then return end
        elseif type(eb.GetText) == "function" and (eb:GetText() or "") ~= "" then
            return
        end
    end
    if eb.SetChatType then eb:SetChatType("SAY")
    elseif eb.SetAttribute then eb:SetAttribute("chatType", "SAY") end
    if eb.UpdateHeader then eb:UpdateHeader() end
end

function Conv.OnBlizzardPopout(chatType, chatTarget)
    local wt = WhisperSettings()
    if not (wt and wt.translatePopout) then return end
    if chatType ~= "WHISPER" and chatType ~= "BN_WHISPER" then return end
    if IsSecret(chatTarget) or type(chatTarget) ~= "string" or chatTarget == "" then return end
    local Display = ns.QUI.Chat.DisplayLayer
    local windowID = (Display and Display.GetActiveWindow and Display.GetActiveWindow()) or 1
    Conv.Open(chatType, chatTarget, windowID, true)
end

Store.OnAppend(function(entry)
    if not entry.w or conversations[entry.w] then return end
    local info = WHISPER_EVENTS[entry.e]
    if not info then return end
    local wt = WhisperSettings()
    local want = BlizzardWantsConversationTab(wt)
    if not want and wt then
        if info.incoming then want = wt.autoIncoming else want = wt.autoOutgoing end
    end
    if not want then return end
    if IsSecret(entry.wn) or type(entry.wn) ~= "string" or entry.wn == "" then return end
    Conv.Open(info.chatType, entry.wn, wt and wt.targetWindow or 1, false)
end)
