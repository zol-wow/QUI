-- modules/chat/blizzard_suppress.lua
-- COMPLETE Blizzard-chat suppression while the custom display is active:
-- chat frames + tab buttons are REPARENTED to a permanently hidden anchor —
-- no render, no mouse, no fade fighting. Suppressed frames are also fully
-- EVENT-NEUTERED (UnregisterAllEvents + keep only UPDATE_CHAT_COLOR) so no
-- legacy dispatch taint surface remains. A reentrancy-guarded RegisterEvent
-- post-hook strips any events re-added while active. Canonical event restore
-- on flip-back re-registers the fixed OnLoad base set then calls
-- RegisterForMessages/RegisterForChannels with Blizzard's own saved-settings
-- APIs — exactly what Blizzard's UPDATE_CHAT_WINDOWS handler does. Combat
-- log frame (ChatFrame2) is exempt from neuter/restore: Blizzard_CombatLog
-- hardcodes it.
--
-- Subsystem ownership (single-path):
--   sounds        → store subscriber  (sounds.lua)
--   keyword sound → ProcessForCapture (keyword_alert.lua)
--   history       → store subscriber  (history.lua)
-- The store path is the ONLY path — capture starts at ADDON_LOADED, so it
-- also covers the pre-suppression login window. The old AddMessage-hook
-- paths are deleted.
--
-- Caveat: temporary windows (whisper/BN popouts) born while suppressed get
-- the canonical group restore on flip-back but not the popout-specific
-- AddSingleMessageType extras (CHAT_MSG_SYSTEM on whisper popouts etc.) —
-- those self-heal when Blizzard next reconfigures the window.
--
-- Taint posture: SetParent only; NEVER Hide/SetPoint/SetSize on Blizzard
-- chat frames. First application is deferred past PLAYER_ENTERING_WORLD
-- (+ one timer tick) so the chat-color pipeline settles before frames move.
-- ChatFrame1EditBox lives INSIDE ChatFrame1 and would vanish with it — it
-- is parented out to UIParent while suppressed; DisplayFallback.Apply runs
-- editbox_basics.StyleEditBox, which anchors it to the custom display.
local ADDON_NAME, ns = ...

local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: blizzard_suppress.lua loaded before chat.lua. Check chat.xml — chat.lua must precede blizzard_suppress.lua.")

ns.QUI.Chat.BlizzardSuppress = ns.QUI.Chat.BlizzardSuppress or {}
local Suppress = ns.QUI.Chat.BlizzardSuppress

local function IsSecret(v)
    return ns.Helpers and ns.Helpers.IsSecretValue and ns.Helpers.IsSecretValue(v) or false
end

-- The chat frame's fixed OnLoad event set (vendored FrameXML,
-- Blizzard_ChatFrameBase/Mainline/ChatFrameOverrides.lua:1-28) — restored
-- verbatim on flip-back, then message events rebuild from saved settings.
local BASE_FRAME_EVENTS = {
    "PLAYER_ENTERING_WORLD", "SETTINGS_LOADED", "UPDATE_CHAT_COLOR",
    "UPDATE_CHAT_WINDOWS", "CHAT_MSG_CHANNEL", "CHAT_MSG_COMMUNITIES_CHANNEL",
    "CLUB_REMOVED", "UPDATE_INSTANCE_INFO", "UPDATE_CHAT_COLOR_NAME_BY_CLASS",
    "CHAT_SERVER_DISCONNECTED", "CHAT_SERVER_RECONNECTED", "BN_CONNECTED",
    "BN_DISCONNECTED", "PLAYER_REPORT_SUBMITTED", "NEUTRAL_FACTION_SELECT_RESULT",
    "ALTERNATIVE_DEFAULT_LANGUAGE_CHANGED", "NEWCOMER_GRADUATION",
    "CHAT_REGIONAL_STATUS_CHANGED", "CHAT_REGIONAL_SEND_FAILED",
    "NOTIFY_CHAT_SUPPRESSED", "CAUTIONARY_CHAT_MESSAGE",
}

-- Events a NEUTERED frame keeps: the color-sync handler mutates ChatTypeInfo
-- and other Blizzard code assumes it ran (reference-validated minimal set).
local NEUTER_ALLOWED = {
    UPDATE_CHAT_COLOR = true,
}

local neutered = {}        -- frame -> true while event-neutered
local registerHooked = {}  -- frame -> true (blocking hook installed)
local inOwnRegister = false

local function IsCombatLogFrame(frame)
    return frame == _G.ChatFrame2
end

-- ChatFrame1 additionally keeps CAUTIONARY_CHAT_MESSAGE: its handler routes
-- straight to ChatFrameUtil.HandleCautionaryChatMessage (the suspicious-link
-- confirm flow, ChatFrameOverrides.lua:273-275) and renders nothing — the
-- flow must keep one live listener while frames are hidden. Default frame
-- only, so a confirm fires once, not once per window.
local function IsNeuterAllowed(frame, event)
    if NEUTER_ALLOWED[event] then return true end
    return event == "CAUTIONARY_CHAT_MESSAGE" and frame == _G.ChatFrame1
end

local function HookRegisterEvent(frame)
    if registerHooked[frame] or not _G.hooksecurefunc then return end
    registerHooked[frame] = true
    -- While neutered, strip anything outside the allowed set the moment it
    -- is registered (Blizzard settings paths and other addons re-add message
    -- groups; dead frames must stay dead). Reentrancy-guarded.
    _G.hooksecurefunc(frame, "RegisterEvent", function(self, event)
        if inOwnRegister or not neutered[self] then return end
        if type(event) == "string" and not IsNeuterAllowed(self, event) then
            pcall(self.UnregisterEvent, self, event)
        end
    end)
end

local function NeuterOne(frame)
    if not frame or neutered[frame] or IsCombatLogFrame(frame) then return end
    if not frame.UnregisterAllEvents then return end
    neutered[frame] = true
    pcall(frame.UnregisterAllEvents, frame)
    inOwnRegister = true
    for event in pairs(NEUTER_ALLOWED) do
        pcall(frame.RegisterEvent, frame, event)
    end
    local valid = _G.C_EventUtils and _G.C_EventUtils.IsEventValid
    if frame == _G.ChatFrame1
        and (not valid or valid("CAUTIONARY_CHAT_MESSAGE")) then
        pcall(frame.RegisterEvent, frame, "CAUTIONARY_CHAT_MESSAGE")
    end
    inOwnRegister = false
    HookRegisterEvent(frame)
end

-- Canonical restore: the fixed OnLoad base set, then Blizzard's own
-- saved-settings rebuild (exactly what its UPDATE_CHAT_WINDOWS handler does:
-- RegisterForMessages(GetChatWindowMessages) + RegisterForChannels(...)).
local function RestoreEventsOne(frame)
    if not frame or not neutered[frame] then return end
    neutered[frame] = nil
    inOwnRegister = true
    -- Mirror Blizzard's UPDATE_CHAT_WINDOWS handler: wipe the message-group
    -- bookkeeping so RegisterForMessages doesn't leave stale tail entries.
    if frame.UnregisterAllMessageGroups then
        pcall(frame.UnregisterAllMessageGroups, frame)
    end
    pcall(frame.UnregisterAllEvents, frame)
    local valid = _G.C_EventUtils and _G.C_EventUtils.IsEventValid
    for i = 1, #BASE_FRAME_EVENTS do
        local event = BASE_FRAME_EVENTS[i]
        if not valid or valid(event) then
            pcall(frame.RegisterEvent, frame, event)
        end
    end
    -- :GetID has SecretReturnsForAspect=ID — probe before passing to any API.
    local id = frame.GetID and frame:GetID()
    if id and not IsSecret(id) then
        if frame.RegisterForMessages and _G.GetChatWindowMessages then
            pcall(frame.RegisterForMessages, frame, _G.GetChatWindowMessages(id))
        end
        if frame.RegisterForChannels and _G.GetChatWindowChannels then
            pcall(frame.RegisterForChannels, frame, _G.GetChatWindowChannels(id))
        end
    end
    inOwnRegister = false
end

local lastActive            -- nil until first applied state
local hiddenAnchor
local savedParents = {}     -- region -> original parent
local regionHooked = {}
local inOwnSetParent = false
local pewSeen = false
local pendingApply = false
local windowHooksInstalled = false
local dockScriptsHooked = false
local origDockSetScript
local managerNeutered = false
local fcfTempSwapped = false
local origFCFOpenTemp
local pewFrame
local channelRefreshFrame

local CHANNEL_REFRESH_EVENTS = {
    "UPDATE_CHAT_WINDOWS",
    "CHANNEL_UI_UPDATE",
    "CHANNEL_LEFT",
}

local CHAT_GLOBAL_REGIONS = {
    "ChatMenu",
    "TextToSpeechButtonFrame",
    "QuickJoinToastButton",
    "ChatFrameToggleVoiceDeafenButton",
    "ChatFrameToggleVoiceMuteButton",
}

local function WantActive()
    local settings = I.GetSettings and I.GetSettings()
    if not (I.IsChatEnabled and I.IsChatEnabled(settings)) then return false end
    return true -- chat enabled (checked above) IS the takeover
end

-- Consumed by hud_visibility's chat fade and the button bar's anchor chooser.
function Suppress.IsActive()
    return lastActive == true
end

local function SafeSetParent(region, parent)
    if not (region and region.SetParent and parent) then return end
    inOwnSetParent = true
    pcall(region.SetParent, region, parent)
    inOwnSetParent = false
end

-- Iterate all known chat frame names: prefer Blizzard's CHAT_FRAMES list so
-- temporary windows (whisper popouts, pet-battle log) are always included.
local function EachChatFrameName(fn)
    if type(_G.CHAT_FRAMES) == "table" then
        for _, name in pairs(_G.CHAT_FRAMES) do
            if type(name) == "string" then fn(name) end
        end
    else
        for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do
            fn("ChatFrame" .. i)
        end
    end
end

local function RefreshSuppressedFrameChannels(frame)
    if not frame or not neutered[frame] or IsCombatLogFrame(frame) then return end
    if not (frame.RegisterForChannels and _G.GetChatWindowChannels) then return end
    local id = frame.GetID and frame:GetID()
    if not id or IsSecret(id) then return end

    -- Hidden frames stay event-neutered, but their channel tables still need to
    -- track regional channel joins/leaves so Blizzard's chat filter context does
    -- not behave as if the default frame left city channels until /reload.
    frame.channelList = {}
    frame.zoneChannelList = {}
    pcall(frame.RegisterForChannels, frame, _G.GetChatWindowChannels(id))
end

local function RefreshSuppressedChannels()
    if lastActive ~= true then return end
    EachChatFrameName(function(name)
        RefreshSuppressedFrameChannels(_G[name])
    end)
end

local function EnsureChannelRefreshWatcher()
    if channelRefreshFrame or not _G.CreateFrame then return end
    channelRefreshFrame = CreateFrame("Frame")
    local valid = _G.C_EventUtils and _G.C_EventUtils.IsEventValid
    for i = 1, #CHANNEL_REFRESH_EVENTS do
        local event = CHANNEL_REFRESH_EVENTS[i]
        if not valid or valid(event) then
            channelRefreshFrame:RegisterEvent(event)
        end
    end
    channelRefreshFrame:SetScript("OnEvent", RefreshSuppressedChannels)
end

-- While suppressed, enforce the expected parent for any region that gets
-- reparented externally (e.g. DetachFromEditMode, dock layout passes).
-- enforcedParentFn returns the parent we require while suppression is active.
-- Idempotent: installs at most once per region.
local function HookRegion(region, enforcedParentFn)
    if regionHooked[region] or not _G.hooksecurefunc then return end
    regionHooked[region] = true
    _G.hooksecurefunc(region, "SetParent", function(self, parent)
        if inOwnSetParent or lastActive ~= true then return end
        local enforced = enforcedParentFn()
        if parent ~= enforced then
            -- Record the latest outside intent so RestoreAll honours it.
            savedParents[self] = parent
            SafeSetParent(self, enforced)
        end
    end)
end

local function SuppressRegion(region, enforcedParentFn)
    if not (region and region.GetParent and region.SetParent) then return end
    local enforced = enforcedParentFn()
    if region:GetParent() ~= enforced then
        savedParents[region] = savedParents[region] or region:GetParent()
        SafeSetParent(region, enforced)
    end
    HookRegion(region, enforcedParentFn)
end

local function SuppressGlobalChatRegions()
    for i = 1, #CHAT_GLOBAL_REGIONS do
        SuppressRegion(_G[CHAT_GLOBAL_REGIONS[i]], function() return hiddenAnchor end)
    end
end

-- Neutralize the dock's transient update driver. The dock carries only an
-- OnLoad by default (FrameXML FloatingChatFrame.xml), but FCFDock_OnPrimarySizeChanged
-- installs dock:SetScript("OnUpdate", FCFDock_OnUpdate) every time the primary
-- chat frame resizes. Left live on the dock we just reparented — which taints
-- the dock frame — that OnUpdate runs FCFDock_UpdateTabs -> FCF_CheckShowChatFrame
-- -> ChatFrame1:SetShown(AllowChatFramesToShow(...)) -> Show(): a protected call
-- reached on the tainted path, blocked as ADDON_ACTION_BLOCKED on QUI_Chat (and
-- AllowChatFramesToShow returns true unconditionally in-game, so it would also
-- un-hide ChatFrame1). Clear the dock's update scripts now and re-clear them on
-- every SetScript while suppression is active, so any re-install is undone the
-- instant it happens. origDockSetScript is captured BEFORE the hook so we can
-- re-nil without re-entering our own SetScript hook. Gated on lastActive so the
-- dock's normal tab-layout OnUpdate works again after a flip back to Blizzard.
local function NeutralizeDockUpdateScripts()
    local dock = _G.GeneralDockManager
    if not (dock and dock.SetScript) then return end
    if not origDockSetScript then origDockSetScript = dock.SetScript end
    origDockSetScript(dock, "OnUpdate", nil)
    origDockSetScript(dock, "OnSizeChanged", nil)
    if not dockScriptsHooked and _G.hooksecurefunc then
        dockScriptsHooked = true
        _G.hooksecurefunc(dock, "SetScript", function()
            if lastActive ~= true then return end
            origDockSetScript(dock, "OnUpdate", nil)
            origDockSetScript(dock, "OnSizeChanged", nil)
        end)
    end
end

-- ChatFrame2's enforced parent is dynamic: the combat-log host container while
-- its QUI tab is active (combat_log_tab.lua), the hidden anchor otherwise.
-- Passed by reference to SuppressRegion so the SetParent hook re-resolves live —
-- letting the combat-log tab embed ChatFrame2 instead of being yanked back.
-- Defined here (after the module-level `hiddenAnchor` local) so it captures it.
local function ChatFrame2EnforcedParent()
    local CL = ns.QUI.Chat.CombatLogTab
    local host = CL and CL.GetHostParent and CL.GetHostParent()
    return host or hiddenAnchor
end

-- Test/diagnostic hook.
function Suppress._ResolveChatFrame2Parent()
    return ChatFrame2EnforcedParent()
end

-- Suppress a single named frame+tab/button set. Idempotent: regions already parented
-- to hiddenAnchor are skipped so re-running on the full list is safe.
local function SuppressOne(name)
    local f = _G[name]
    if f then
        -- The combat log (ChatFrame2) gets the dynamic enforced parent; every
        -- other chat frame is pinned to the hidden anchor.
        local parentFn = IsCombatLogFrame(f)
            and ChatFrame2EnforcedParent
            or function() return hiddenAnchor end
        SuppressRegion(f, parentFn)
        NeuterOne(f)
    end
    SuppressRegion(_G[name .. "Tab"], function() return hiddenAnchor end)
    SuppressRegion(_G[name .. "ButtonFrame"], function() return hiddenAnchor end)
end

-- FloatingChatFrameManager auto-pops out incoming whispers (whisperMode
-- "popout"/"popout_and_inline"). Each popout calls FCF_OpenTemporaryWindow,
-- whose body docks the new temp frame on the reparented (tainted) dock ->
-- FCFDock_UpdateTabs -> FCF_CheckShowChatFrame -> ChatFrame1:Show() = blocked.
-- The manager registers ONLY whisper events, so neuter it wholesale while active
-- and rebuild from its OnLoad on flip-back.
local function NeuterChatFrameManager()
    local mgr = _G.FloatingChatFrameManager
    if managerNeutered or not (mgr and mgr.UnregisterAllEvents) then return end
    managerNeutered = true
    pcall(mgr.UnregisterAllEvents, mgr)
end

local function RestoreChatFrameManager()
    if not managerNeutered then return end
    managerNeutered = false
    local mgr = _G.FloatingChatFrameManager
    if mgr and type(_G.FloatingChatFrameManager_OnLoad) == "function" then
        pcall(_G.FloatingChatFrameManager_OnLoad, mgr)
    end
end

-- Neutering the manager is not enough: a user "whisper -> new window"
-- (UnitPopupPopoutChatButtonMixin) and the pet-battle combat log also call
-- FCF_OpenTemporaryWindow directly, and its body always docks the temp frame on
-- the tainted dock (same blocked ChatFrame1:Show()). While suppressed, REPLACE
-- the global with a forward-only wrapper: translate the whisper intent into a
-- QUI conversation tab (Conv.OnBlizzardPopout self-gates on whisper types +
-- translatePopout) and skip Blizzard's body entirely. The remaining callers
-- ignore the return; only the manager consumed it, and it is neutered. The
-- pristine original is restored on flip-back and the wrapper NEVER calls it, so
-- the Blizzard popout path stays untainted while the takeover is off.
local function QUIForwardTempWindow(chatType, chatTarget)
    local Conv = ns.QUI.Chat.ConversationManager
    if Conv and Conv.OnBlizzardPopout then
        Conv.OnBlizzardPopout(chatType, chatTarget)
    end
    return nil
end

local function SwapTempWindowFn()
    if fcfTempSwapped or type(_G.FCF_OpenTemporaryWindow) ~= "function" then return end
    if not origFCFOpenTemp then origFCFOpenTemp = _G.FCF_OpenTemporaryWindow end
    fcfTempSwapped = true
    _G.FCF_OpenTemporaryWindow = QUIForwardTempWindow
end

local function RestoreTempWindowFn()
    if not fcfTempSwapped then return end
    fcfTempSwapped = false
    if origFCFOpenTemp then _G.FCF_OpenTemporaryWindow = origFCFOpenTemp end
end

local function SuppressAll()
    if not hiddenAnchor then
        hiddenAnchor = CreateFrame("Frame", "QUI_ChatSuppressAnchor", _G.UIParent)
        hiddenAnchor:Hide()
    end

    EachChatFrameName(SuppressOne)
    EnsureChannelRefreshWatcher()
    RefreshSuppressedChannels()
    SuppressGlobalChatRegions()

    -- GeneralDockManager is UIParent-parented and resurfaces suppressed tabs;
    -- park it in the hidden anchor too. Reparenting taints the dock frame, so
    -- its update scripts must also be neutralized (below) or the dock's
    -- transient OnUpdate drives a blocked ChatFrame1:Show().
    SuppressRegion(_G.GeneralDockManager, function() return hiddenAnchor end)
    NeutralizeDockUpdateScripts()

    SuppressRegion(_G.ChatFrame1EditBox, function() return _G.UIParent end)

    -- Stop Blizzard driving the (tainted) dock to show ChatFrame1: kill the
    -- whisper-popout manager and intercept temp-window creation. Both reverse on
    -- flip-back (RestoreAll).
    NeuterChatFrameManager()
    SwapTempWindowFn()

    -- Install a post-hook on FCF_OpenNewWindow so a user-created chat window
    -- born AFTER the initial SuppressAll is caught immediately. (Temp windows go
    -- through the FCF_OpenTemporaryWindow swap above, which never creates a
    -- Blizzard frame to suppress.)
    if not windowHooksInstalled and _G.hooksecurefunc then
        windowHooksInstalled = true
        if _G.FCF_OpenNewWindow then
            _G.hooksecurefunc("FCF_OpenNewWindow", function()
                if lastActive ~= true then return end
                EachChatFrameName(SuppressOne)
                SuppressGlobalChatRegions()
            end)
        end
    end
end

local function RestoreAll()
    -- Hand the whisper-popout machinery back to Blizzard before reparenting.
    RestoreChatFrameManager()
    RestoreTempWindowFn()
    -- Tear down the combat-log embed first: this clears CombatLogTab's active
    -- state so ChatFrame2's enforced parent resolves away from our container,
    -- and the savedParents restore below then hands ChatFrame2 back to Blizzard.
    local CL = ns.QUI.Chat.CombatLogTab
    if CL and CL.Deactivate then CL.Deactivate(1) end
    for region, parent in pairs(savedParents) do
        SafeSetParent(region, parent)
    end
    -- Drop the snapshots: the SetParent hooks are inert while inactive, so a
    -- legitimate reparent during a disabled interlude would otherwise be
    -- shadowed by this table and the NEXT flip-back would restore a stale
    -- parent. The next activation re-snapshots whatever is live then.
    savedParents = {}
    -- Restore events for every frame we neutered, including temp windows born
    -- mid-suppression. Iterate a copy: RestoreEventsOne mutates `neutered`.
    local toRestore = {}
    for frame in pairs(neutered) do toRestore[#toRestore + 1] = frame end
    for i = 1, #toRestore do
        RestoreEventsOne(toRestore[i])
    end
end

local function ApplyNow()
    local active = WantActive()
    if active == lastActive then return end
    lastActive = active
    if active then
        SuppressAll()
    else
        RestoreAll()
    end
end

-- Idempotent; transition-latched. The FIRST application waits for
-- PLAYER_ENTERING_WORLD + one timer tick; later flips apply immediately.
function Suppress.Apply()
    if pewSeen then
        ApplyNow()
        return
    end
    pendingApply = true
    if not pewFrame and _G.CreateFrame then
        pewFrame = CreateFrame("Frame")
        pewFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        pewFrame:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            pewSeen = true
            if pendingApply then
                pendingApply = false
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, ApplyNow)
                else
                    ApplyNow()
                end
            end
        end)
    end
end
