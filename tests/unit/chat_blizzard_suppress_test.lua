-- tests/unit/chat_blizzard_suppress_test.lua
-- Run: lua tests/unit/chat_blizzard_suppress_test.lua
-- Verifies COMPLETE suppression by reparenting: chat frames + tabs go to the
-- hidden anchor, chat button containers and chat-adjacent global buttons are
-- hidden with them, the editbox goes to UIParent, everything restores on mode
-- flip, the enforcement hook is reentrancy-safe and self-gating, the first
-- application defers past PLAYER_ENTERING_WORLD (+After(0)), the dock is
-- suppressed, new windows created after activation are caught, and the
-- module NEVER calls Hide/SetPoint/SetSize on Blizzard frames (traps).

local function makeBlizzFrame(name, parent)
    local f = { name = name, parent = parent }
    f.GetName = function() return name end
    f.GetParent = function(s) return s.parent end
    f.SetParent = function(s, p) s.parent = p; if s._setParentHook then s._setParentHook(s, p) end end
    f.scripts = {}
    f.SetScript = function(s, k, v) s.scripts[k] = v end
    f.GetScript = function(s, k) return s.scripts[k] end
    f.Hide = function() error("Hide() on Blizzard chat frame is forbidden: " .. name) end
    f.SetPoint = function() error("SetPoint on Blizzard chat frame is forbidden: " .. name) end
    f.SetSize = function() error("SetSize on Blizzard chat frame is forbidden: " .. name) end
    -- Event machinery
    f.events = {}
    f.RegisterEvent = function(s, e)
        s.events[e] = true
        if s._registerHook then s._registerHook(s, e) end
    end
    f.UnregisterEvent = function(s, e) s.events[e] = nil end
    f.UnregisterAllEvents = function(s) s.events = {} end
    f.GetID = function(s) return s.id or 1 end
    f.RegisterForMessages = function(s, ...) s.messagesRegistered = { ... } end
    f.RegisterForChannels = function(s, ...)
        s.channelsRegistered = { ... }
        s.channelList = {}
        s.zoneChannelList = {}
        local index = 1
        for i = 1, select("#", ...), 2 do
            s.channelList[index], s.zoneChannelList[index] = select(i, ...)
            index = index + 1
        end
    end
    return f
end

_G.UIParent = { name = "UIParent" }
_G.NUM_CHAT_WINDOWS = 2
_G.CHAT_FRAMES = { "ChatFrame1", "ChatFrame2" }
_G.ChatFrame1 = makeBlizzFrame("ChatFrame1", _G.UIParent)
_G.ChatFrame1.id = 1
_G.ChatFrame1Tab = makeBlizzFrame("ChatFrame1Tab", { name = "Dock" })
_G.ChatFrame1ButtonFrame = makeBlizzFrame("ChatFrame1ButtonFrame", _G.ChatFrame1)
_G.ChatFrame2 = makeBlizzFrame("ChatFrame2", _G.UIParent)
_G.ChatFrame2.id = 2
_G.ChatFrame2Tab = makeBlizzFrame("ChatFrame2Tab", { name = "Dock" })
_G.ChatFrame2ButtonFrame = makeBlizzFrame("ChatFrame2ButtonFrame", _G.ChatFrame2)
_G.ChatFrame1EditBox = makeBlizzFrame("ChatFrame1EditBox", _G.ChatFrame1)
_G.GeneralDockManager = makeBlizzFrame("Dock", _G.UIParent)
_G.ChatMenu = makeBlizzFrame("ChatMenu", _G.UIParent)
_G.TextToSpeechButtonFrame = makeBlizzFrame("TextToSpeechButtonFrame", _G.UIParent)
_G.QuickJoinToastButton = makeBlizzFrame("QuickJoinToastButton", _G.UIParent)
_G.ChatFrameToggleVoiceDeafenButton = makeBlizzFrame("ChatFrameToggleVoiceDeafenButton", _G.UIParent)
_G.ChatFrameToggleVoiceMuteButton = makeBlizzFrame("ChatFrameToggleVoiceMuteButton", _G.UIParent)
-- Seed pre-suppression events
_G.ChatFrame1.events = { CHAT_MSG_SAY = true, UPDATE_CHAT_WINDOWS = true }
_G.ChatFrame2.events = { COMBAT_LOG_EVENT = true }

-- GetChatWindowMessages/Channels: Blizzard's saved-settings rebuild APIs
local channelReturns = { "Trade", 0 }
function _G.GetChatWindowMessages(i) return "SAY", "GUILD" end
function _G.GetChatWindowChannels(i) return unpack(channelReturns) end
_G.C_EventUtils = { IsEventValid = function() return true end }

-- FCF_OpenTemporaryWindow declared before loadfile: while suppressed the module
-- REPLACES it with a forward-only wrapper, restoring this pristine original on
-- flip-back. origTempCalled detects whether the wrapper ever delegates to it
-- (it must not while active).
local origTempCalled = false
local function origTempFn() origTempCalled = true end
_G.FCF_OpenTemporaryWindow = origTempFn
-- FCF_OpenNewWindow: the module post-hooks this to re-suppress user-created
-- windows born after activation.
_G.FCF_OpenNewWindow = function() end
-- FloatingChatFrameManager: auto whisper-popout driver. The module neuters it
-- (UnregisterAllEvents) while active and rebuilds via its OnLoad on flip-back.
_G.FloatingChatFrameManager = makeBlizzFrame("FloatingChatFrameManager", _G.UIParent)
function _G.FloatingChatFrameManager_OnLoad(self) self:RegisterEvent("CHAT_MSG_WHISPER") end
_G.FloatingChatFrameManager_OnLoad(_G.FloatingChatFrameManager)

-- hooksecurefunc: supports both frame-method hooks (tbl, name, fn) and global
-- function hooks (name-as-string, fn).  Frame-method chains via _setParentHook;
-- global hooks are stored in globalHooks for manual invocation in tests.
-- NOTE: global form is 2-arg (string, fn); frame-method form is 3-arg (tbl, name, fn).
local globalHooks = {}
function _G.hooksecurefunc(tbl, name, fn)
    if type(tbl) == "string" then
        -- Global function hook: hooksecurefunc("FuncName", hookFn)
        -- In this 2-arg form: tbl=funcName, name=hookFn, fn=nil
        globalHooks[tbl] = name
        return
    end
    assert(name == "SetParent" or name == "RegisterEvent" or name == "SetScript",
        "only SetParent/RegisterEvent/SetScript frame-method hooks expected, got: " .. tostring(name))
    if name == "SetParent" then
        tbl._setParentHook = function(self, p) fn(self, p) end
    elseif name == "RegisterEvent" then
        tbl._registerHook = function(self, e) fn(self, e) end
    elseif name == "SetScript" then
        -- Emulate WoW: hooksecurefunc replaces the method with a wrapper, while
        -- the pre-hook reference (captured by the module) stays raw so the
        -- module can re-nil without re-entering its own hook.
        local orig = tbl.SetScript
        tbl.SetScript = function(self, k, v) orig(self, k, v); fn(self, k, v) end
    end
end

-- QUI-owned frames (hidden anchor + PEW event frame): permissive recorder
local createdFrames = {}
function _G.CreateFrame(_, name, parent)
    local f = { name = name, parent = parent, events = {}, shown = true }
    f.Hide = function(s) s.shown = false end
    f.Show = function(s) s.shown = true end
    f.RegisterEvent = function(s, e) s.events[e] = true end
    f.UnregisterAllEvents = function(s) s.events = {} end
    f.SetScript = function(s, k, v) s["_" .. k] = v end
    f.GetParent = function(s) return s.parent end
    f.SetParent = function(s, p) s.parent = p end
    createdFrames[#createdFrames + 1] = f
    return f
end

local afterCalls = {}
_G.C_Timer = { After = function(_, fn) afterCalls[#afterCalls + 1] = fn end }

local settings = { enabled = true, customDisplay = {} }
local ns = {
    Helpers = { IsSecretValue = function() return false end },
    QUI = { Chat = { _internals = {
        GetSettings = function() return settings end,
        IsChatEnabled = function(s) return s and s.enabled ~= false end,
    } } },
}

assert(loadfile("QUI_Chat/chat/blizzard_suppress.lua"))("QUI", ns)
local SP = ns.QUI.Chat.BlizzardSuppress

-- Pre-PEW: Apply only arms the deferral; nothing moves yet
SP.Apply()
assert(not SP.IsActive(), "not active before PLAYER_ENTERING_WORLD")
assert(_G.ChatFrame1.parent == _G.UIParent, "no reparent before PEW")
local pewFrame
for _, f in ipairs(createdFrames) do
    if f.events.PLAYER_ENTERING_WORLD then pewFrame = f end
end
assert(pewFrame, "PEW deferral frame registered")

-- PEW fires -> After(0) -> suppression lands
pewFrame._OnEvent(pewFrame, "PLAYER_ENTERING_WORLD")
assert(#afterCalls == 1, "deferred one frame via C_Timer.After")
afterCalls[1]()
assert(SP.IsActive(), "active after deferred apply")
local hidden
for _, f in ipairs(createdFrames) do
    if f.name == "QUI_ChatSuppressAnchor" then hidden = f end
end
assert(hidden and hidden.shown == false, "hidden anchor exists and is hidden")
assert(_G.ChatFrame1.parent == hidden and _G.ChatFrame2.parent == hidden, "frames reparented")
assert(_G.ChatFrame1Tab.parent == hidden, "tabs reparented")
assert(_G.ChatFrame1ButtonFrame.parent == hidden, "button frame reparented")
assert(_G.QuickJoinToastButton.parent == hidden, "social quick-join button reparented")
assert(_G.TextToSpeechButtonFrame.parent == hidden, "text-to-speech button frame reparented")
assert(_G.ChatFrameToggleVoiceDeafenButton.parent == hidden, "voice deafen button reparented")
assert(_G.ChatFrameToggleVoiceMuteButton.parent == hidden, "voice mute button reparented")
assert(_G.ChatFrame1EditBox.parent == _G.UIParent, "editbox parented OUT to UIParent")

-- NEUTER: frames lose their events except the allowed color-sync set
assert(_G.ChatFrame1.events.CHAT_MSG_SAY == nil, "message events unregistered")
assert(_G.ChatFrame1.events.UPDATE_CHAT_WINDOWS == nil, "rebuild event unregistered")
assert(_G.ChatFrame1.events.UPDATE_CHAT_COLOR == true, "color sync stays registered")
assert(_G.ChatFrame2.events.COMBAT_LOG_EVENT == true, "combat log frame EXEMPT from neuter")

-- Regional channel refresh: hidden ChatFrame1 remains event-neutered, but its
-- channel bookkeeping tracks city-channel joins/leaves instead of waiting for /reload.
local channelWatcher
for _, f in ipairs(createdFrames) do
    if f.events.CHANNEL_UI_UPDATE then channelWatcher = f end
end
assert(channelWatcher and channelWatcher.events.UPDATE_CHAT_WINDOWS and channelWatcher.events.CHANNEL_LEFT,
    "channel refresh watcher registered")
_G.ChatFrame1.channelList = { "Stale", "Tail" }
_G.ChatFrame1.zoneChannelList = { 99, 98 }
channelReturns = { "General", 1, "Trade", 2 }
channelWatcher._OnEvent(channelWatcher, "CHANNEL_UI_UPDATE")
assert(_G.ChatFrame1.channelList[1] == "General" and _G.ChatFrame1.zoneChannelList[1] == 1,
    "channel refresh rebuilds first channel")
assert(_G.ChatFrame1.channelList[2] == "Trade" and _G.ChatFrame1.zoneChannelList[2] == 2,
    "channel refresh rebuilds second channel")
assert(_G.ChatFrame1.channelList[3] == nil and _G.ChatFrame1.zoneChannelList[3] == nil,
    "channel refresh clears stale tail entries")
assert(_G.ChatFrame1.events.CHAT_MSG_CHANNEL == nil and _G.ChatFrame1.events.UPDATE_CHAT_COLOR == true,
    "channel refresh does not re-enable hidden chat-frame events")
channelReturns = { "Trade", 0 }

-- RegisterEvent blocking: outside registrations stripped while active
_G.ChatFrame1:RegisterEvent("CHAT_MSG_YELL")
assert(_G.ChatFrame1.events.CHAT_MSG_YELL == nil, "outside RegisterEvent stripped while active")
assert(_G.ChatFrame1.events.UPDATE_CHAT_COLOR == true, "allowed event survives the blocker")

-- (a) Dock suppressed and restores
assert(_G.GeneralDockManager.parent == hidden, "dock reparented to hidden anchor")

-- (a2) Dock update-script neutralization. REGRESSION: ADDON_ACTION_BLOCKED
-- 'ChatFrame1:Show()' via FCFDock_OnUpdate. When the suppressed primary chat
-- frame resizes, Blizzard's FCFDock_OnPrimarySizeChanged installs a transient
-- dock OnUpdate (FCFDock_OnUpdate); on the reparented (tainted) dock it runs
-- FCFDock_UpdateTabs -> FCF_CheckShowChatFrame -> ChatFrame1:SetShown(true) ->
-- Show() = blocked. While active the dock's update scripts must be cleared AND
-- any re-install instantly undone.
assert(_G.GeneralDockManager.scripts.OnUpdate == nil
    and _G.GeneralDockManager.scripts.OnSizeChanged == nil,
    "dock update scripts cleared on activation")
_G.GeneralDockManager:SetScript("OnUpdate", function() error("FCFDock_OnUpdate must not run while suppressed") end)
assert(_G.GeneralDockManager.scripts.OnUpdate == nil, "dock OnUpdate re-install undone while active")
_G.GeneralDockManager:SetScript("OnSizeChanged", function() end)
assert(_G.GeneralDockManager.scripts.OnSizeChanged == nil, "dock OnSizeChanged re-install undone while active")

-- (a3) Whisper-popout neutralization. Closes the synchronous path to the tainted
-- dock: FloatingChatFrameManager / a user "whisper -> new window" call
-- FCF_OpenTemporaryWindow, whose body docks the temp frame -> FCFDock_UpdateTabs
-- -> ChatFrame1:Show() = blocked. While active the manager is neutered and the
-- global is swapped for a forward-only wrapper that never runs Blizzard's body.
assert(next(_G.FloatingChatFrameManager.events) == nil, "chat-frame manager neutered while active")
assert(_G.FCF_OpenTemporaryWindow ~= origTempFn, "temp-window fn swapped while active")
origTempCalled = false
_G.FCF_OpenTemporaryWindow("WHISPER", "Someone-Realm")
assert(not origTempCalled, "swapped wrapper never runs Blizzard's temp-window body while active")

-- Enforcement: a dock layout pass reparenting a tab gets forced back
_G.ChatFrame1Tab:SetParent({ name = "Dock" })
assert(_G.ChatFrame1Tab.parent == hidden, "tab forced back to hidden while active")
_G.QuickJoinToastButton:SetParent({ name = "SocialButtonOwner" })
assert(_G.QuickJoinToastButton.parent == hidden, "social button forced back to hidden while active")

-- (c) Frame enforcement: while active, external SetParent is overridden, but
-- latest intent is recorded so RestoreAll restores to it (not the original).
local container = { name = "Container" }
_G.ChatFrame1:SetParent(container)
assert(_G.ChatFrame1.parent == hidden, "frame forced back to hidden while active")

-- Restore on mode flip (disable): every original parent returns (including latest intent)
settings.enabled = false
SP.Apply()
assert(not SP.IsActive(), "inactive after flip")
assert(_G.ChatFrame1.parent.name == "Container",
    "frame restored to latest intent (Container), not original UIParent")
assert(_G.ChatFrame1Tab.parent.name == "Dock", "tab parent restored")
assert(_G.ChatFrame1EditBox.parent == _G.ChatFrame1, "editbox parent restored")
assert(_G.GeneralDockManager.parent == _G.UIParent, "dock restored")

-- Dock script hook is inert while inactive: Blizzard's own dock OnUpdate (the
-- normal tab-layout driver) must work again once the takeover is off.
local liveDockOnUpdate = function() end
_G.GeneralDockManager:SetScript("OnUpdate", liveDockOnUpdate)
assert(_G.GeneralDockManager.scripts.OnUpdate == liveDockOnUpdate, "dock OnUpdate hook inert while inactive")
_G.GeneralDockManager:SetScript("OnUpdate", nil)
-- Whisper-popout machinery handed back to Blizzard on flip-back.
assert(_G.FCF_OpenTemporaryWindow == origTempFn, "pristine FCF_OpenTemporaryWindow restored while inactive")
assert(_G.FloatingChatFrameManager.events.CHAT_MSG_WHISPER == true, "chat-frame manager rebuilt (OnLoad) on flip-back")
assert(_G.ChatFrame1ButtonFrame.parent == _G.ChatFrame1, "button frame parent restored")
assert(_G.QuickJoinToastButton.parent.name == "SocialButtonOwner",
    "social button restores latest outside parent intent")
assert(_G.TextToSpeechButtonFrame.parent == _G.UIParent, "text-to-speech button frame restored")
assert(_G.ChatFrameToggleVoiceDeafenButton.parent == _G.UIParent, "voice deafen button restored")
assert(_G.ChatFrameToggleVoiceMuteButton.parent == _G.UIParent, "voice mute button restored")

-- Canonical restore: base events + Blizzard's own saved-settings rebuild
assert(_G.ChatFrame1.events.CHAT_MSG_CHANNEL == true, "base event list re-registered")
assert(_G.ChatFrame1.events.PLAYER_ENTERING_WORLD == true, "base event list complete")
assert(_G.ChatFrame1.messagesRegistered and _G.ChatFrame1.messagesRegistered[1] == "SAY",
    "RegisterForMessages(GetChatWindowMessages) called")
assert(_G.ChatFrame1.channelsRegistered and _G.ChatFrame1.channelsRegistered[1] == "Trade",
    "RegisterForChannels(GetChatWindowChannels) called")
assert(_G.ChatFrame2.events.COMBAT_LOG_EVENT == true, "combat log frame untouched by restore")

-- Blocker inert while inactive
_G.ChatFrame1:RegisterEvent("CHAT_MSG_EMOTE")
assert(_G.ChatFrame1.events.CHAT_MSG_EMOTE == true, "RegisterEvent free while inactive")

-- Enforcement hook is inert while inactive
_G.ChatFrame1Tab:SetParent({ name = "Dock2" })
assert(_G.ChatFrame1Tab.parent.name == "Dock2", "hook inert while inactive")

-- Re-activate (post-PEW: immediate) — reset frame parents first for clean state
_G.ChatFrame1.parent = _G.UIParent
_G.ChatFrame2.parent = _G.UIParent
settings.enabled = true
SP.Apply()
assert(SP.IsActive() and _G.ChatFrame1.parent == hidden, "re-suppression immediate post-PEW")

-- Latch: same-state Apply is a no-op (parent identity unchanged)
local p = _G.ChatFrame1.parent
SP.Apply()
assert(_G.ChatFrame1.parent == p, "latched")

-- (b) Window-creation hook: a user window born after activation is caught when
-- the FCF_OpenNewWindow hook fires. (Temp windows never reach this path — they
-- go through the FCF_OpenTemporaryWindow swap, which creates no Blizzard frame.)
_G.ChatFrame3 = makeBlizzFrame("ChatFrame3", _G.UIParent)
_G.ChatFrame3.id = 3
_G.ChatFrame3Tab = makeBlizzFrame("ChatFrame3Tab", { name = "Dock" })
_G.ChatFrame3ButtonFrame = makeBlizzFrame("ChatFrame3ButtonFrame", _G.ChatFrame3)
_G.CHAT_FRAMES[#_G.CHAT_FRAMES + 1] = "ChatFrame3"
assert(globalHooks["FCF_OpenNewWindow"], "FCF_OpenNewWindow hook installed")
globalHooks["FCF_OpenNewWindow"]()
assert(_G.ChatFrame3.parent == hidden, "new window caught by FCF_OpenNewWindow hook")
assert(_G.ChatFrame3Tab.parent == hidden, "new window tab caught by FCF_OpenNewWindow hook")
assert(_G.ChatFrame3ButtonFrame.parent == hidden, "new window button frame caught by hook")

-- Windows born suppressed get the full canonical restore on flip-back
settings.enabled = false
SP.Apply()
assert(_G.ChatFrame3.events.UPDATE_CHAT_COLOR == true, "new window base events restored")
assert(_G.ChatFrame3.events.PLAYER_ENTERING_WORLD == true, "new window base list complete")
assert(_G.ChatFrame3.messagesRegistered ~= nil, "new window RegisterForMessages called")

-- (d) STALE-SNAPSHOT regression (adversarial review): a legitimate reparent
-- during a DISABLED interlude must survive the next enable/disable cycle.
-- The SetParent hooks are inert while inactive, so without the post-restore
-- snapshot wipe the next flip-back would restore the parent recorded in the
-- FIRST activation, not the latest external one.
local newHome = { name = "NewHome" }
_G.ChatFrame1:SetParent(newHome)
assert(_G.ChatFrame1.parent == newHome, "external reparent lands while inactive")
settings.enabled = true
SP.Apply()
assert(_G.ChatFrame1.parent == hidden, "third activation suppresses")
settings.enabled = false
SP.Apply()
assert(_G.ChatFrame1.parent == newHome,
    "flip-back restores the LATEST inactive parent (NewHome), not a stale snapshot")

-- FCF_OpenTemporaryWindow swap: the active wrapper forwards whisper intent to
-- ConversationManager (translate to a QUI tab) instead of running Blizzard's
-- docking body; the pristine original (no forward) is back while inactive.
local forwarded
ns.QUI.Chat.ConversationManager = {
    OnBlizzardPopout = function(ct, t) forwarded = { ct, t } end,
}
-- Ensure suppression is active (it was deactivated in the stale-snapshot block
-- above; re-activate it now).
settings.enabled = true
_G.ChatFrame1.parent = _G.UIParent
_G.ChatFrame2.parent = _G.UIParent
SP.Apply()
assert(SP.IsActive(), "active before popout-forwarding test")

forwarded, origTempCalled = nil, false
_G.FCF_OpenTemporaryWindow("WHISPER", "Someone-Realm", _G.ChatFrame1, true)
assert(forwarded ~= nil, "swapped wrapper forwards when suppression is active")
assert(forwarded[1] == "WHISPER", "forwarded chatType is correct")
assert(forwarded[2] == "Someone-Realm", "forwarded chatTarget is correct")
assert(not origTempCalled, "swapped wrapper does not run Blizzard's body")

-- Inactive path: the pristine original is restored, so QUI does NOT forward.
settings.enabled = false
SP.Apply()
assert(not SP.IsActive(), "inactive for no-forward test")
assert(_G.FCF_OpenTemporaryWindow == origTempFn, "original restored for no-forward test")
forwarded = nil
_G.FCF_OpenTemporaryWindow("WHISPER", "Someone-Realm")
assert(forwarded == nil, "pristine original does NOT forward when suppression is inactive")

print("OK: chat_blizzard_suppress_test")
