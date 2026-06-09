-- modules/chat/conversation_manager.lua
-- Runtime-only whisper conversation registry — the takeover-native
-- replacement for Blizzard's temporary whisper windows. A conversation is a
-- session-scoped TAB (rendered by tab_ui after the saved tabs); nothing here
-- is ever written to saved variables, so /reload always resets to a clean
-- slate (by design: session-only lifetime).
--
-- Keying: counterparty identity, case-folded — "W:" .. name for WHISPER,
-- "BN:" .. name for BN_WHISPER. arg2/chatTarget are name-shaped in every
-- creation path (vendored ChatInfoDocumentation.lua:2486ff: playerName is
-- the sender on incoming and the target on _INFORM). Identity args may be
-- SECRET in chat messaging lockdown (playerName is not NeverSecret) — every
-- entry point probes IsSecret before any operator.
--
-- Editbox pre-target mirrors ChatFrameUtil.SendBNetTell/ReplyTell (vendored
-- ChatFrameUtil.lua:313-340): SetChatType + SetTellTarget + UpdateHeader on
-- the insecure ChatFrame1EditBox. SetChatType and SetTellTarget are both thin
-- SetAttribute wrappers (ChatFrameEditBox.lua:18-49). No ChatTypeInfo writes
-- anywhere.
--
-- IMPORTANT: GetAttribute returns SecretReturnsForAspect=Attributes — never
-- compare its return value with == in any path. ClearPreTarget restores to
-- SAY unconditionally based on preTargetedKey tracking alone; it never reads
-- the current attribute back.
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

local conversations = {} -- key -> { key, name, chatType, target, windowID }
local order = {}         -- keys in creation order (stable tab-bar order)

-- Shared with message_capture.lua (entry tagging) — single source of truth
-- for which events are whisper-family and their direction.
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
    -- Canonicalize: WHISPER names may arrive realm-less from unit-popup
    -- popouts while CHAT_MSG arg2 is realm-qualified — qualify with the
    -- player's own realm so both paths key identically.
    -- (GetNormalizedRealmName verified in PlayerScriptDocumentation.lua.)
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

-- whisperTabs.targetWindow (and any caller-supplied id) may be stale after
-- window deletion — clamp to a live window, falling back to the primary.
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
    -- Additive model (see TabManager.BuildTabFilter): opening/closing a
    -- conversation only adds/removes its own tab button — it never changes what
    -- the OTHER tabs show, so only the tab BAR needs rebuilding here.
    --
    -- Do NOT run a content ReapplyAll: this store subscriber runs BEFORE
    -- display_layer's, so a Clear+rebuild here would render the just-appended
    -- whisper that auto-created the tab, and display_layer's live append would
    -- then render it a second time (double line). Closing an ACTIVE conversation
    -- tab is handled inside TabUI.Rebuild, whose fallback re-activates a saved
    -- tab and rebuilds that one window's content.
    local TabUI = ns.QUI.Chat.TabUI
    if TabUI and TabUI.Rebuild then TabUI.Rebuild() end
end

-- Idempotent. activate=true also selects the conversation tab (and thereby
-- pre-targets the editbox via tab_ui's activation path).
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
        -- Background creation (auto paths): draw the eye without stealing focus.
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
    -- Only reset the editbox when closing the conversation we pre-targeted;
    -- closing an unrelated conversation must not clobber the active editbox.
    if key == Conv.GetPreTargetedKey() then
        Conv.ClearPreTarget()
    end
    RefreshAfterChange()
end

-- Display.DeleteWindow shifted ids down; re-home this window's conversations
-- to the primary and follow the shift for higher windows.
function Conv.OnWindowDeleted(windowID)
    for _, c in pairs(conversations) do
        if c.windowID == windowID then
            c.windowID = 1
        elseif c.windowID > windowID then
            c.windowID = c.windowID - 1
        end
    end
end

---------------------------------------------------------------------------
-- Editbox reply pre-target
---------------------------------------------------------------------------
-- Tracks whether WE last set the editbox to a whisper target. Never read
-- back from GetAttribute (SecretReturnsForAspect=Attributes — comparisons
-- with == on that return would throw in restricted context). Tracking our
-- own state is sufficient: if preTargetedKey is set, we restore to SAY
-- unconditionally on ClearPreTarget.
local preTargetedKey

function Conv.PreTargetEditBox(key)
    local c = conversations[key]
    local eb = _G.ChatFrame1EditBox
    if not (c and eb) then return end
    -- Never clobber a message mid-compose. HasText is the doc-clean probe:
    -- GetText is SecretReturnsForAspect=Text (a secret insert would make the
    -- ~= "" comparison throw); HasText carries no secret annotation.
    if eb.HasFocus and eb:HasFocus() then
        if eb.HasText then
            if eb:HasText() then return end
        elseif type(eb.GetText) == "function" and (eb:GetText() or "") ~= "" then
            return
        end
    end
    -- SetChatType/SetTellTarget are both plain SetAttribute wrappers
    -- (ChatFrameEditBox.lua:18-49). Writing is always safe; only reads of
    -- GetAttribute are secret-sensitive (SecretReturnsForAspect=Attributes).
    if eb.SetChatType then eb:SetChatType(c.chatType)
    elseif eb.SetAttribute then eb:SetAttribute("chatType", c.chatType) end
    if eb.SetTellTarget then eb:SetTellTarget(c.target)
    elseif eb.SetAttribute then eb:SetAttribute("tellTarget", c.target) end
    if eb.UpdateHeader then eb:UpdateHeader() end
    preTargetedKey = key
end

-- Returns the key of the conversation currently pre-targeted in the editbox,
-- or nil if none. Used by Close to gate editbox restoration.
function Conv.GetPreTargetedKey()
    return preTargetedKey
end

-- Activating a NON-conversation tab (or closing a conversation) restores the
-- default chat type — but only when whisper mode was OUR pre-target. A
-- user-typed /w is never fought (preTargetedKey is nil unless we set it).
--
-- NEVER read GetAttribute here — its return is SecretReturnsForAspect=
-- Attributes, so == comparison throws in restricted context. We restore to
-- SAY unconditionally based purely on preTargetedKey tracking.
--
-- Mid-compose guard: if the user has focused the editbox and started typing,
-- skip the SAY rewrite so we don't clobber a half-typed draft. The key
-- tracking (preTargetedKey = nil) still clears unconditionally — only the
-- ATTRIBUTE rewrite is deferred. The residue (editbox stays in WHISPER mode
-- after a pre-target close) is intentional and mirrors Blizzard's own sticky
-- whisper behaviour (the user can type their draft, then clear it themselves).
function Conv.ClearPreTarget()
    if not preTargetedKey then return end
    preTargetedKey = nil
    local eb = _G.ChatFrame1EditBox
    if not eb then return end
    -- Never clobber a draft mid-compose (same probe as PreTargetEditBox).
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

---------------------------------------------------------------------------
-- Creation paths
---------------------------------------------------------------------------
-- Called from blizzard_suppress's FCF_OpenTemporaryWindow post-hook
-- (signature per vendored FloatingChatFrame.lua:678: chatType, chatTarget,
-- sourceChatFrame, selectWindow). Covers the unit-frame popout flow AND
-- Blizzard's whisperMode=popout auto-popouts. The Blizzard temp frame itself
-- stays suppressed (the hook suppressed it before calling here).
function Conv.OnBlizzardPopout(chatType, chatTarget)
    local wt = WhisperSettings()
    if not (wt and wt.translatePopout) then return end
    if chatType ~= "WHISPER" and chatType ~= "BN_WHISPER" then return end
    if IsSecret(chatTarget) or type(chatTarget) ~= "string" or chatTarget == "" then return end
    local Display = ns.QUI.Chat.DisplayLayer
    local windowID = (Display and Display.GetActiveWindow and Display.GetActiveWindow()) or 1
    Conv.Open(chatType, chatTarget, windowID, true)
end

-- Auto-create on tagged whisper appends. Live events only — HISTORY/BACKFILL
-- replays never match WHISPER_EVENTS. Self-gates on the whisperTabs settings,
-- so installing unconditionally at load is inert until opted in (and no
-- entries append at all while the chat module is disabled).
Store.OnAppend(function(entry)
    if not entry.w or conversations[entry.w] then return end
    local info = WHISPER_EVENTS[entry.e]
    if not info then return end
    local wt = WhisperSettings()
    if not wt then return end
    local want
    if info.incoming then want = wt.autoIncoming else want = wt.autoOutgoing end
    if not want then return end
    if IsSecret(entry.wn) or type(entry.wn) ~= "string" or entry.wn == "" then return end
    Conv.Open(info.chatType, entry.wn, wt.targetWindow, false)
end)
