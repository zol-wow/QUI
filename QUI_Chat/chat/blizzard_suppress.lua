local ADDON_NAME, ns = ...

local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: blizzard_suppress.lua loaded before chat.lua. Check chat.xml — chat.lua must precede blizzard_suppress.lua.")

ns.QUI.Chat.BlizzardSuppress = ns.QUI.Chat.BlizzardSuppress or {}
local Suppress = ns.QUI.Chat.BlizzardSuppress

local function IsSecret(v)
    return ns.Helpers and ns.Helpers.IsSecretValue and ns.Helpers.IsSecretValue(v) or false
end

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

local NEUTER_ALLOWED = {
    UPDATE_CHAT_COLOR = true,
}

local neutered = {}
local registerHooked = {}
local inOwnRegister = false

local timePlayedWanted = true

function Suppress.TimePlayedWanted()
    return timePlayedWanted
end

local function IsCombatLogFrame(frame)
    return frame == _G.ChatFrame2
end

local function IsNeuterAllowed(frame, event)
    if NEUTER_ALLOWED[event] then return true end
    return event == "CAUTIONARY_CHAT_MESSAGE" and frame == _G.ChatFrame1
end

local function HookRegisterEvent(frame)
    if registerHooked[frame] or not _G.hooksecurefunc then return end
    registerHooked[frame] = true
    _G.hooksecurefunc(frame, "RegisterEvent", function(self, event)
        if inOwnRegister then return end
        if event == "TIME_PLAYED_MSG" and self == _G.ChatFrame1 then
            timePlayedWanted = true
        end
        if not neutered[self] then return end
        if type(event) == "string" and not IsNeuterAllowed(self, event) then
            inOwnRegister = true
            ns.SafeCallMethod("best-effort-style", self, "UnregisterEvent", event)
            inOwnRegister = false
        end
    end)
    _G.hooksecurefunc(frame, "UnregisterEvent", function(self, event)
        if inOwnRegister then return end
        if event == "TIME_PLAYED_MSG" and self == _G.ChatFrame1 then
            timePlayedWanted = false
        end
    end)
end

local function NeuterOne(frame)
    if not frame or neutered[frame] or IsCombatLogFrame(frame) then return end
    if not frame.UnregisterAllEvents then return end
    neutered[frame] = true
    ns.SafeCallMethod("best-effort-style", frame, "UnregisterAllEvents")
    inOwnRegister = true
    for event in pairs(NEUTER_ALLOWED) do
        ns.SafeCallMethod("best-effort-style", frame, "RegisterEvent", event)
    end
    local valid = _G.C_EventUtils and _G.C_EventUtils.IsEventValid
    if frame == _G.ChatFrame1
        and (not valid or valid("CAUTIONARY_CHAT_MESSAGE")) then
        ns.SafeCallMethod("best-effort-style", frame, "RegisterEvent", "CAUTIONARY_CHAT_MESSAGE")
    end
    inOwnRegister = false
    HookRegisterEvent(frame)
end

local function RestoreEventsOne(frame)
    if not frame or not neutered[frame] then return end
    neutered[frame] = nil
    inOwnRegister = true
    ns.SafeCallMethodIfPresent("best-effort-style", frame, "UnregisterAllMessageGroups")
    ns.SafeCallMethod("best-effort-style", frame, "UnregisterAllEvents")
    local valid = _G.C_EventUtils and _G.C_EventUtils.IsEventValid
    for i = 1, #BASE_FRAME_EVENTS do
        local event = BASE_FRAME_EVENTS[i]
        if not valid or valid(event) then
            ns.SafeCallMethod("best-effort-style", frame, "RegisterEvent", event)
        end
    end
    local id = frame.GetID and frame:GetID()
    if id and not IsSecret(id) then
        if frame.RegisterForMessages and _G.GetChatWindowMessages then
            ns.SafeCallMethod("best-effort-style", frame, "RegisterForMessages", _G.GetChatWindowMessages(id))
        end
        if frame.RegisterForChannels and _G.GetChatWindowChannels then
            ns.SafeCallMethod("best-effort-style", frame, "RegisterForChannels", _G.GetChatWindowChannels(id))
        end
    end
    inOwnRegister = false
end

local lastActive
local hiddenAnchor
local savedParents = {}
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
    return true
end

function Suppress.IsActive()
    return lastActive == true
end

local pendingParents = setmetatable({}, { __mode = "k" })
local regenFlushFrame
local graceApply = false
local SafeSetParent

local function QueueParentForRegen(region, parent)
    pendingParents[region] = parent
    if not regenFlushFrame then
        if not _G.CreateFrame then return end
        regenFlushFrame = _G.CreateFrame("Frame")
        regenFlushFrame:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            for r, p in pairs(pendingParents) do
                pendingParents[r] = nil
                SafeSetParent(r, p)
            end
        end)
    end
    regenFlushFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

SafeSetParent = function(region, parent)
    if not (region and region.SetParent and parent) then return end
    if not graceApply
        and type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() then
        QueueParentForRegen(region, parent)
        return
    end
    inOwnSetParent = true
    ns.SafeCallMethod("best-effort-style", region, "SetParent", parent)
    inOwnSetParent = false
end

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

    frame.channelList = {}
    frame.zoneChannelList = {}
    ns.SafeCallMethod("best-effort-style", frame, "RegisterForChannels", _G.GetChatWindowChannels(id))
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

local function HookRegion(region, enforcedParentFn)
    if regionHooked[region] or not _G.hooksecurefunc then return end
    regionHooked[region] = true
    _G.hooksecurefunc(region, "SetParent", function(self, parent)
        if inOwnSetParent or lastActive ~= true then return end
        local enforced = enforcedParentFn()
        if parent ~= enforced then
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

local function ChatFrame2EnforcedParent()
    local CL = ns.QUI.Chat.CombatLogTab
    local host = CL and CL.GetHostParent and CL.GetHostParent()
    if host then return host end
    local park = CL and CL.GetParkParent and CL.GetParkParent()
    return park or hiddenAnchor
end

function Suppress._ResolveChatFrame2Parent()
    return ChatFrame2EnforcedParent()
end

local function SuppressOne(name)
    local f = _G[name]
    if f then
        local parentFn = IsCombatLogFrame(f)
            and ChatFrame2EnforcedParent
            or function() return hiddenAnchor end
        SuppressRegion(f, parentFn)
        NeuterOne(f)
    end
    SuppressRegion(_G[name .. "Tab"], function() return hiddenAnchor end)
    SuppressRegion(_G[name .. "ButtonFrame"], function() return hiddenAnchor end)
end

local function NeuterChatFrameManager()
    local mgr = _G.FloatingChatFrameManager
    if managerNeutered or not (mgr and mgr.UnregisterAllEvents) then return end
    managerNeutered = true
    ns.SafeCallMethod("best-effort-style", mgr, "UnregisterAllEvents")
end

local function RestoreChatFrameManager()
    if not managerNeutered then return end
    managerNeutered = false
    local mgr = _G.FloatingChatFrameManager
    if mgr and type(_G.FloatingChatFrameManager_OnLoad) == "function" then
        ns.SafeCall("best-effort-style", _G.FloatingChatFrameManager_OnLoad, mgr)
    end
end

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

local cf2Stripped = false
local cf2RegisterHooked = false
local COMBAT_LOG_BASE_CHAT_EVENTS = { "CHAT_MSG_CHANNEL", "CHAT_MSG_COMMUNITIES_CHANNEL" }

local function IsChatMessageEvent(event)
    if type(event) ~= "string" then return false end
    if event:sub(1, 9) == "CHAT_MSG_" then return true end
    local inv = _G.ChatTypeGroupInverted
    return type(inv) == "table" and inv[event] ~= nil
end

local function StripCombatLogChatMessages()
    local cf = _G.ChatFrame2
    if not (cf and cf.UnregisterEvent) then return end
    cf2Stripped = true
    inOwnRegister = true
    for i = 1, #COMBAT_LOG_BASE_CHAT_EVENTS do
        ns.SafeCallMethod("best-effort-style", cf, "UnregisterEvent", COMBAT_LOG_BASE_CHAT_EVENTS[i])
    end
    if type(_G.ChatTypeGroup) == "table" then
        for _, events in pairs(_G.ChatTypeGroup) do
            if type(events) == "table" then
                for i = 1, #events do
                    ns.SafeCallMethod("best-effort-style", cf, "UnregisterEvent", events[i])
                end
            end
        end
    end
    inOwnRegister = false
    if not cf2RegisterHooked and _G.hooksecurefunc then
        cf2RegisterHooked = true
        _G.hooksecurefunc(cf, "RegisterEvent", function(self, event)
            if inOwnRegister or not cf2Stripped then return end
            if IsChatMessageEvent(event) then
                inOwnRegister = true
                ns.SafeCallMethod("best-effort-style", self, "UnregisterEvent", event)
                inOwnRegister = false
            end
        end)
    end
end

local function RestoreCombatLogChatMessages()
    if not cf2Stripped then return end
    cf2Stripped = false
    local cf = _G.ChatFrame2
    if not cf then return end
    inOwnRegister = true
    local valid = _G.C_EventUtils and _G.C_EventUtils.IsEventValid
    for i = 1, #COMBAT_LOG_BASE_CHAT_EVENTS do
        local event = COMBAT_LOG_BASE_CHAT_EVENTS[i]
        if not valid or valid(event) then
            ns.SafeCallMethod("best-effort-style", cf, "RegisterEvent", event)
        end
    end
    local id = cf.GetID and cf:GetID()
    if id and not IsSecret(id) then
        if cf.RegisterForMessages and _G.GetChatWindowMessages then
            ns.SafeCallMethod("best-effort-style", cf, "RegisterForMessages", _G.GetChatWindowMessages(id))
        end
    end
    inOwnRegister = false
end

local function SuppressAll()
    if not hiddenAnchor then
        hiddenAnchor = CreateFrame("Frame", "QUI_ChatSuppressAnchor", _G.UIParent)
        hiddenAnchor:Hide()
    end

    EachChatFrameName(SuppressOne)
    StripCombatLogChatMessages()
    EnsureChannelRefreshWatcher()
    RefreshSuppressedChannels()
    SuppressGlobalChatRegions()

    SuppressRegion(_G.GeneralDockManager, function() return hiddenAnchor end)
    NeutralizeDockUpdateScripts()

    SuppressRegion(_G.ChatFrame1EditBox, function() return _G.UIParent end)

    NeuterChatFrameManager()
    SwapTempWindowFn()

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

    local CL = ns.QUI.Chat.CombatLogTab
    if CL and CL.Prime then CL.Prime() end
end

local function RestoreAll()
    RestoreChatFrameManager()
    RestoreTempWindowFn()
    local CL = ns.QUI.Chat.CombatLogTab
    if CL and CL.Deactivate then CL.Deactivate(1) end
    for region, parent in pairs(savedParents) do
        SafeSetParent(region, parent)
    end
    savedParents = {}
    local toRestore = {}
    for frame in pairs(neutered) do toRestore[#toRestore + 1] = frame end
    for i = 1, #toRestore do
        RestoreEventsOne(toRestore[i])
    end
    RestoreCombatLogChatMessages()
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

function Suppress.Apply()
    if pewSeen then
        ApplyNow()
        return
    end
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
    if type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() then
        pendingApply = false
        graceApply = true
        ApplyNow()
        graceApply = false
    else
        pendingApply = true
    end
end
