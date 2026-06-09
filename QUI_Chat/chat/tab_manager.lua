-- modules/chat/tab_manager.lua
-- Window-scoped tab state for the custom display: builds filter closures from
-- QUI's saved chat windows (customDisplay.windows[]) and drives
-- DisplayLayer.Rebuild(windowID, filterFn) on tab switch. Each window carries
-- its own active filter; conversation tabs get a dedicated closure that shows
-- only their tagged entries. Visual tab buttons are Phase 2 (tab_ui.lua).
--
-- Secret message bodies are never inspected; filters only use event/channel
-- metadata captured separately from the message body.
local ADDON_NAME, ns = ...

local _I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: tab_manager.lua loaded before chat.lua. Check chat.xml — chat.lua must precede tab_manager.lua.")

ns.QUI.Chat.TabManager = ns.QUI.Chat.TabManager or {}
local TabManager = ns.QUI.Chat.TabManager

local activeFilters = {} -- dense array: windowID -> active filter closure

local function NormalizeSet(t)
    if type(t) ~= "table" then return nil end
    local out
    for k, v in pairs(t) do
        local key
        if type(k) == "string" and v then
            key = k
        elseif type(k) == "number" and type(v) == "string" and v ~= "" then
            key = v
        end
        if key then
            out = out or {}
            out[key] = true
        end
    end
    return out
end

-- Channel sets match case-insensitively: Blizzard's own routing compares
-- strupper(saved name) == strupper(arg9) (vendored FrameXML:
-- Blizzard_ChatFrameBase/Mainline/ChatFrameOverrides.lua:320), so stored
-- names with case drift must keep matching.
local function NormalizeSetUpper(t)
    local set = NormalizeSet(t)
    if not set then return nil end
    local out = {}
    for key in pairs(set) do
        out[key:upper()] = true
    end
    return out
end

local EVENT_GROUP_ALIAS = {
    RAID_BOSS_EMOTE = "MONSTER_BOSS_EMOTE",
    QUEST_BOSS_EMOTE = "MONSTER_BOSS_EMOTE",
    RAID_BOSS_WHISPER = "MONSTER_BOSS_WHISPER",
}

-- Returns a filter closure, or nil when tabData expresses no constraint
-- (nil filter = show everything; cheaper than an always-true closure).
--
function TabManager.BuildFilter(tabData)
    if type(tabData) ~= "table" then return nil end
    local groups = NormalizeSet(tabData.groups)
    local channels = NormalizeSetUpper(tabData.channels)
    if not groups and not channels then return nil end
    local invert = tabData.invert and true or false

    -- Named channel traffic is routed by channel name first (case-insensitive,
    -- matching Blizzard's routing). A tab that curates a channel list must not
    -- inherit Trade just because CHANNEL is present in its message groups —
    -- but a tab that never curated channels (empty set) shows default-category
    -- channels (zone/regional) through its CHANNEL group, like Blizzard's
    -- default frame carries zone channels without explicit listing. That heals
    -- seeds taken before the channels existed.
    return function(entry)
        local listed = false
        local channelName = entry.ch
        if type(channelName) == "string" and channelName ~= "" then
            if channels then
                listed = channels[channelName:upper()] or false
            elseif groups and groups.CHANNEL then
                local Reg = ns.QUI.Chat.ChannelRegistry
                listed = (Reg and Reg.IsDefault and Reg.IsDefault(channelName)) or false
            end
        else
            if groups and entry.k and groups[entry.k] then listed = true end
            -- Normalize typeKey -> message group (PARTY_LEADER lives in group
            -- PARTY): the stored/derived sets use GROUP names.
            if not listed and groups and entry.e then
                local grp = _G.ChatTypeGroupInverted and _G.ChatTypeGroupInverted[entry.e]
                if not grp then grp = EVENT_GROUP_ALIAS[entry.e] end
                if grp and groups[grp] then listed = true end
            end
        end
        if invert then
            return not listed
        end
        return listed
    end
end

-- Regional-channel auto-add (ChatFrame_CheckAddChannel parity): called by
-- capture when a YOU_CHANGED notice arrives for a regional channel. If no
-- window-1 tab lists the channel, the first tab inherits it — same as
-- Blizzard adding the channel to the default frame's saved list. Explicit
-- curation elsewhere wins: any tab already listing the name (any case)
-- means the user routed it deliberately.
function TabManager.EnsureDefaultChannelListed(name)
    if type(name) ~= "string" or name == "" then return end
    local tabs = TabManager.GetWindowTabs(1)
    if #tabs == 0 then return end
    local upper = name:upper()
    for i = 1, #tabs do
        local chs = type(tabs[i]) == "table" and tabs[i].channels
        if type(chs) == "table" then
            for stored, v in pairs(chs) do
                if v and type(stored) == "string" and stored:upper() == upper then
                    return -- already routed somewhere in window 1
                end
            end
        end
    end
    local first = tabs[1]
    if type(first) ~= "table" then return end
    if type(first.channels) ~= "table" then first.channels = {} end
    first.channels[name] = true
    TabManager.ReapplyAll()
end

-- Conversation-exclusion wrapper: while a conversation tab for entry.w is
-- open ANYWHERE, that conversation's lines render only in its own tab.
-- ConversationManager is a runtime lookup (nil-safe before its file loads;
-- conversation state is session-only so this can never go stale across
-- /reload). entry.w is nil for non-whisper traffic — one field test.
local function WrapWithConversationExclusion(baseFilter)
    return function(entry)
        if entry.w then
            local Conv = ns.QUI.Chat.ConversationManager
            if Conv and Conv.IsOpen and Conv.IsOpen(entry.w) then
                return false
            end
        end
        if not baseFilter then return true end
        return baseFilter(entry)
    end
end

-- Saved-tab filter for display/unread use. Unlike BuildFilter this never
-- returns nil: even a no-constraint tab must exclude open conversations.
function TabManager.BuildTabFilter(tabData)
    return WrapWithConversationExclusion(TabManager.BuildFilter(tabData))
end

-- A conversation tab shows exactly its conversation's tagged entries.
function TabManager.BuildConversationFilter(key)
    return function(entry)
        return entry.w == key
    end
end

function TabManager.SetActiveTab(windowID, tabData)
    windowID = tonumber(windowID) or 1
    activeFilters[windowID] = TabManager.BuildTabFilter(tabData)
    local Display = ns.QUI.Chat.DisplayLayer
    if Display and Display.Rebuild then
        Display.Rebuild(windowID, activeFilters[windowID])
    end
end

function TabManager.SetActiveConversation(windowID, key)
    windowID = tonumber(windowID) or 1
    activeFilters[windowID] = TabManager.BuildConversationFilter(key)
    local Display = ns.QUI.Chat.DisplayLayer
    if Display and Display.Rebuild then
        Display.Rebuild(windowID, activeFilters[windowID])
    end
end

function TabManager.GetActiveFilter(windowID)
    return activeFilters[tonumber(windowID) or 1]
end

-- Re-run every window's active filter (conversation open/close moves lines
-- between tabs; cost = one tab switch per window). Iterates the filter
-- slots only — windows that never activated a tab have nothing to reapply,
-- and this must stay free of GetWindowsConfig's seeding side-effect.
function TabManager.ReapplyAll()
    local Display = ns.QUI.Chat.DisplayLayer
    if not (Display and Display.Rebuild) then return end
    for id = 1, #activeFilters do
        Display.Rebuild(id, activeFilters[id])
    end
end

-- Display.DeleteWindow shifts window IDs down; keep filter slots aligned.
function TabManager.OnWindowDeleted(windowID)
    table.remove(activeFilters, tonumber(windowID) or 0)
end

local function SetFromReturns(...)
    local out = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "string" and v ~= "" then
            out[v] = true
        end
    end
    return out
end

local function ChannelSetFromReturns(...)
    local out = {}
    for i = 1, select("#", ...), 2 do
        local v = select(i, ...)
        if type(v) == "string" and v ~= "" then
            out[v] = true
        end
    end
    return out
end

local function ShouldSeedWindow(frameID)
    local frame = _G["ChatFrame" .. tostring(frameID)]
    if not frame then return nil end
    if frame and (frame.isCombatLog or frame.privateMessageList or frame.isTemporary) then
        return nil
    end

    local isTemp = _I.IsTemporaryChatFrame and _I.IsTemporaryChatFrame(frame)
    if isTemp then return nil end

    if type(_G.GetChatWindowInfo) ~= "function" then return nil end
    local name, _, _, _, _, _, shown, _, docked = _G.GetChatWindowInfo(frameID)
    if type(name) ~= "string" or name == "" then return nil end
    if not (shown or docked) then return nil end
    return name
end

-- Canonical empty-tab shape (window seeding, "Add window", settings Add Tab).
function TabManager.NewDefaultTab(name)
    return { name = name or "Tab 1", groups = {}, channels = {}, invert = false }
end

-- Fill `tabs` (empty array) with entries mirroring the user's Blizzard chat
-- windows — same rule as the old flat seed: combat log, private message
-- lists, temporary and hidden windows are skipped.
local function SeedTabsInto(tabs)
    local maxWindows = _G.NUM_CHAT_WINDOWS or 10
    for i = 1, maxWindows do
        local name = ShouldSeedWindow(i)
        if name then
            local groups = {}
            local channels = {}
            if type(_G.GetChatWindowMessages) == "function" then
                groups = SetFromReturns(_G.GetChatWindowMessages(i))
            end
            if type(_G.GetChatWindowChannels) == "function" then
                channels = ChannelSetFromReturns(_G.GetChatWindowChannels(i))
            end
            tabs[#tabs + 1] = {
                name = name,
                groups = groups,
                channels = channels,
                invert = false,
            }
        end
    end
    if #tabs == 0 then
        tabs[1] = { name = "General", groups = {}, channels = {}, invert = false }
    end
end

-- Battle.net friend online/offline lines arrive as the BN_INLINE_TOAST_ALERT
-- message group, captured on our own frame regardless of stock registration.
-- That group does NOT round-trip through GetChatWindowMessages, so a tab seeded
-- from the stock General window (or migrated from a pre-takeover profile) omits
-- it and the opt-in display filter silently drops "[Friend] has come online".
-- One-time pass: any non-inverted tab that already shows SYSTEM also shows
-- friend status -- the same pairing tab_filters.lua's SYSTEM_GROUP_UPGRADE
-- applies to the legacy per-frame store. Versioned so a later deliberate removal
-- sticks; inverted (opt-out) tabs already show it and are left untouched.
local FRIEND_STATUS_GROUP = "BN_INLINE_TOAST_ALERT"
local FRIEND_STATUS_UPGRADE_VERSION = 1

local function EnsureFriendStatusInSystemTabs(cd)
    if type(cd) ~= "table" or cd._friendStatusUpgrade == FRIEND_STATUS_UPGRADE_VERSION then
        return
    end
    local windows = cd.windows
    if type(windows) == "table" then
        for i = 1, #windows do
            local w = windows[i]
            local tabs = type(w) == "table" and w.tabs
            if type(tabs) == "table" then
                for j = 1, #tabs do
                    local tab = tabs[j]
                    if type(tab) == "table" and not tab.invert
                        and type(tab.groups) == "table"
                        and tab.groups.SYSTEM
                        and tab.groups[FRIEND_STATUS_GROUP] == nil then
                        tab.groups[FRIEND_STATUS_GROUP] = true
                    end
                end
            end
        end
    end
    cd._friendStatusUpgrade = FRIEND_STATUS_UPGRADE_VERSION
end

local function SeedWindows(settings)
    settings.customDisplay = settings.customDisplay or {}
    local cd = settings.customDisplay
    if type(cd.windows) ~= "table" then cd.windows = {} end
    if #cd.windows == 0 then
        cd.windows[1] = {
            width = 430,
            height = 190,
            position = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 35, y = 40 },
            tabs = {},
        }
    end
    for i = 1, #cd.windows do
        if type(cd.windows[i].tabs) ~= "table" then cd.windows[i].tabs = {} end
    end
    -- Window 1 inherits the Blizzard-derived tab seed once (same one-shot
    -- rule the old flat customDisplay.tabs used).
    if #cd.windows[1].tabs == 0 then
        SeedTabsInto(cd.windows[1].tabs)
    end
    EnsureFriendStatusInSystemTabs(cd)
    return cd.windows
end

-- customDisplay.windows is an ARRAY of { width, height, position, tabs }
-- where tabs is an ARRAY of SET-shaped entries ({ name, groups = {KEY=true},
-- channels = {Name=true}, invert }).
function TabManager.GetWindowsConfig()
    local settings = _I.GetSettings and _I.GetSettings()
    if type(settings) == "table" then
        return SeedWindows(settings)
    end
    return {}
end

function TabManager.GetWindowTabs(windowID)
    local w = TabManager.GetWindowsConfig()[tonumber(windowID) or 1]
    if type(w) == "table" and type(w.tabs) == "table" then return w.tabs end
    return {}
end

function TabManager.GetWindowTab(windowID, index)
    if type(index) ~= "number" then return nil end
    local t = TabManager.GetWindowTabs(windowID)[index]
    if type(t) == "table" then return t end
    return nil
end
