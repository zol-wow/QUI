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

-- A combat-log tab embeds Blizzard's ChatFrame2 (combat_log_tab.lua). It is a
-- pinned, non-filter tab: BuildTabFilter returns show-nothing for it, and the
-- embedded frame covers the render area while it is active.
function TabManager.IsCombatLogTab(tabData)
    return type(tabData) == "table" and tabData.combatLog == true
end

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

-- Explicitly DESELECTED channels: string keys stored with value false (the
-- settings UI writes false, not nil, on channel uncheck so "user removed this
-- channel" survives in the saved shape). Returns nil when none exist.
local function NormalizeFalseSetUpper(t)
    if type(t) ~= "table" then return nil end
    local out
    for k, v in pairs(t) do
        if type(k) == "string" and v == false then
            out = out or {}
            out[k:upper()] = true
        end
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
    local channelsOff = NormalizeFalseSetUpper(tabData.channels)
    if not groups and not channels and not channelsOff then return nil end
    local invert = tabData.invert and true or false

    -- Named channel traffic is routed by channel name first (case-insensitive,
    -- matching Blizzard's routing). A tab that curates a channel list must not
    -- inherit Trade just because CHANNEL is present in its message groups —
    -- but a tab that never curated channels (no keys at all) shows
    -- default-category channels (zone/regional) through its CHANNEL group,
    -- like Blizzard's default frame carries zone channels without explicit
    -- listing. That heals seeds taken before the channels existed. Explicit
    -- false keys are user deselections and always block their channel — a
    -- fully unchecked list must NOT fall back to "show Trade anyway"
    -- (deselect-all used to be stored as an empty table, indistinguishable
    -- from never-curated, so the fallback resurrected Trade/Services).
    return function(entry)
        local listed = false
        local channelName = entry.ch
        if type(channelName) == "string" and channelName ~= "" then
            if channels then
                listed = channels[channelName:upper()] or false
            elseif channelsOff and channelsOff[channelName:upper()] then
                listed = false
            elseif groups then
                if groups.CHANNEL then
                    local Reg = ns.QUI.Chat.ChannelRegistry
                    listed = (Reg and Reg.IsDefault and Reg.IsDefault(channelName)) or false
                end
            else
                -- No group constraint and no channel whitelist: an
                -- everything-tab minus its deselected channels.
                listed = true
            end
        else
            if groups then
                if entry.k and groups[entry.k] then listed = true end
                -- Normalize typeKey -> message group (PARTY_LEADER lives in
                -- group PARTY): the stored/derived sets use GROUP names.
                if not listed and entry.e then
                    local grp = _G.ChatTypeGroupInverted and _G.ChatTypeGroupInverted[entry.e]
                    if not grp then grp = EVENT_GROUP_ALIAS[entry.e] end
                    if grp and groups[grp] then listed = true end
                end
            elseif not channels then
                -- Deselected-channels-only tab: groups are unconstrained, so
                -- non-channel traffic shows (only the falses are filtered).
                -- A channel WHITELIST tab (channels set) keeps the original
                -- channel-only semantics: non-channel traffic stays hidden.
                listed = true
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
            for stored in pairs(chs) do
                -- An explicit false (deselected) entry is ALSO a deliberate
                -- routing decision — never resurrect a deselected channel.
                if type(stored) == "string" and stored:upper() == upper then
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

-- Saved-tab filter for display/unread use. Whisper conversation tabs are
-- ADDITIVE for QUI-created conversations: opening a conversation tab for
-- someone does NOT remove their whispers from the regular saved tabs. The
-- exception is Blizzard whisperMode=popout parity: capture marks those entries
-- as whisperPopoutOnly, and saved tabs skip them so the dedicated conversation
-- tab is the only visible destination.
--
-- Unlike BuildFilter this never returns nil: the activeFilters array must stay
-- dense for ReapplyAll's `for id = 1, #activeFilters` loop, so a no-constraint
-- tab gets an explicit show-all closure.
function TabManager.BuildTabFilter(tabData)
    if TabManager.IsCombatLogTab(tabData) then
        return function() return false end
    end
    local base = TabManager.BuildFilter(tabData) or function() return true end
    return function(entry)
        if entry and entry.whisperPopoutOnly then return false end
        return base(entry)
    end
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

-- Display.DeleteWindow shifts window IDs down; keep filter slots and the
-- session display order (declared below, captured upvalue) aligned.
local displayOrderRef
function TabManager.OnWindowDeleted(windowID)
    windowID = tonumber(windowID) or 0
    if windowID >= 1 then
        table.remove(activeFilters, windowID)
    end
    if displayOrderRef and windowID >= 1 then
        -- Sparse map (a window may never have been rebuilt): shift manually.
        local maxID = 0
        for id in pairs(displayOrderRef) do if id > maxID then maxID = id end end
        for id = windowID, maxID - 1 do
            displayOrderRef[id] = displayOrderRef[id + 1]
        end
        if maxID >= windowID then displayOrderRef[maxID] = nil end
    end
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
    -- Skip the combat log by IDENTITY: `frame.isCombatLog` is not a real
    -- property in modern FrameXML (only the IsCombatLog() FUNCTION exists,
    -- and it answers false until LoadOnDemand Blizzard_CombatLog loads).
    -- Relying on the property seeded ChatFrame2 as a regular filterable tab
    -- — the legacy "Log"/"Combat Log" tabs carrying COMBAT_MISC_INFO/
    -- TRADESKILLS/... groups in older profiles. Same belt-and-suspenders as
    -- editbox_history.lua's frame loop.
    if frame == _G.ChatFrame2
        or frame.isCombatLog or frame.privateMessageList or frame.isTemporary then
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

-- Ensure window 1 has exactly one combat-log tab iff customDisplay.combatLogTab
-- is on. Appends at the end on first add; removes all combat-log entries (and
-- any accidental extras) when off. Idempotent (runs on every GetWindowsConfig).
-- Window 1 only — there is a single Blizzard ChatFrame2.
local function ReconcileCombatLogTab(cd)
    if type(cd) ~= "table" then return end
    local tabs = cd.windows and cd.windows[1] and cd.windows[1].tabs
    if type(tabs) ~= "table" then return end
    local enabled = cd.combatLogTab ~= false
    local kept
    for i = #tabs, 1, -1 do
        if TabManager.IsCombatLogTab(tabs[i]) then
            if enabled and not kept then
                kept = true       -- keep the first; drop any extras
            else
                table.remove(tabs, i)
            end
        end
    end
    if enabled and not kept then
        tabs[#tabs + 1] = { name = "Combat Log", combatLog = true }
    end
end
TabManager._ReconcileCombatLogTab = ReconcileCombatLogTab -- test/diagnostic

local function SeedWindows(settings)
    settings.customDisplay = settings.customDisplay or {}
    local cd = settings.customDisplay
    if type(cd.windows) ~= "table" then cd.windows = {} end
    if #cd.windows == 0 then
        -- No position field: window position lives in the shared
        -- frameAnchoring DB ("chatFrame1"); display_layer falls back to the
        -- BOTTOMLEFT 35,40 default until the user moves it.
        cd.windows[1] = {
            width = 430,
            height = 190,
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
    ReconcileCombatLogTab(cd)
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

---------------------------------------------------------------------------
-- Mixed display order: conversation (whisper) tabs are orderable anywhere
-- among saved tabs on the bar. Per window, a SESSION-ONLY token list holds
-- the on-bar order; a token is either a saved-tab TABLE reference (identity
-- survives stored-array reorders) or a "conv:<key>" string. Saved tabs
-- remain the persistence source of truth for their RELATIVE order — moving
-- one rewrites the stored windows[].tabs array in place — while conversation
-- positions die with the session, like the conversations themselves.
---------------------------------------------------------------------------
local displayOrder = {} -- windowID -> array of tokens (session-only)
displayOrderRef = displayOrder -- OnWindowDeleted (above) shifts this map

-- Reconcile the session token list against the live worlds: prune tokens
-- whose tab/conversation is gone, re-seat saved tokens to the stored array's
-- relative order (so external reorders — options panel — win), then append
-- new saved tabs (array order) and new conversations (creation order).
local function ReconcileOrder(windowID)
    windowID = tonumber(windowID) or 1
    local saved = TabManager.GetWindowTabs(windowID)
    local savedIndex = {}
    for i = 1, #saved do savedIndex[saved[i]] = i end

    local convTokens, convByToken = {}, {}
    local Conv = ns.QUI.Chat.ConversationManager
    if Conv and Conv.EachForWindow then
        Conv.EachForWindow(windowID, function(c)
            local tok = "conv:" .. c.key
            convTokens[#convTokens + 1] = tok
            convByToken[tok] = c
        end)
    end

    local tokens = displayOrder[windowID]
    if type(tokens) ~= "table" then
        tokens = {}
        displayOrder[windowID] = tokens
    end

    -- Prune dead/duplicate tokens, compacting in place.
    local seen, n = {}, 0
    for i = 1, #tokens do
        local tok = tokens[i]
        local live = (type(tok) == "table" and savedIndex[tok] ~= nil)
            or (type(tok) == "string" and convByToken[tok] ~= nil)
        if live and not seen[tok] then
            n = n + 1
            tokens[n] = tok
            seen[tok] = true
        end
    end
    for i = #tokens, n + 1, -1 do tokens[i] = nil end

    -- Re-seat the saved tokens in stored-array order (slot positions kept).
    local slots = {}
    for i = 1, #tokens do
        if type(tokens[i]) == "table" then slots[#slots + 1] = i end
    end
    local k = 0
    for i = 1, #saved do
        if seen[saved[i]] then
            k = k + 1
            tokens[slots[k]] = saved[i]
        end
    end

    -- Append newcomers.
    for i = 1, #saved do
        if not seen[saved[i]] then
            tokens[#tokens + 1] = saved[i]
            seen[saved[i]] = true
        end
    end
    for i = 1, #convTokens do
        if not seen[convTokens[i]] then
            tokens[#tokens + 1] = convTokens[i]
            seen[convTokens[i]] = true
        end
    end
    return tokens, savedIndex, convByToken
end

-- On-bar order for tab_ui. Entries are
--   { kind = "saved", index = <stored-array index>, tab = <tab table> } or
--   { kind = "conv",  key = <conversation key>,     conv = <registry obj> }.
function TabManager.GetDisplayEntries(windowID)
    local tokens, savedIndex, convByToken = ReconcileOrder(windowID)
    local out = {}
    for i = 1, #tokens do
        local tok = tokens[i]
        if type(tok) == "table" then
            out[#out + 1] = { kind = "saved", index = savedIndex[tok], tab = tok }
        else
            out[#out + 1] = { kind = "conv", key = tok:sub(6), conv = convByToken[tok] }
        end
    end
    return out
end

-- Move display position `from` to final position `to` (drag-reorder).
-- Returns moved(boolean), savedChanged(boolean) — savedChanged is true when
-- the saved tabs' relative order changed (stored array rewritten in place;
-- the caller decides whether to notify the options panel).
function TabManager.MoveDisplayEntry(windowID, from, to)
    local tokens = ReconcileOrder(windowID)
    local n = #tokens
    if n < 2 or type(from) ~= "number" or from < 1 or from > n then return false end
    if type(to) ~= "number" then return false end
    if to < 1 then to = 1 elseif to > n then to = n end
    if to == from then return false end

    local moved = table.remove(tokens, from)
    table.insert(tokens, to, moved)

    -- Persist the saved tabs' new relative order into the stored array.
    local saved = TabManager.GetWindowTabs(windowID)
    local reordered = {}
    for i = 1, #tokens do
        if type(tokens[i]) == "table" then reordered[#reordered + 1] = tokens[i] end
    end
    local savedChanged = false
    for i = 1, #reordered do
        if saved[i] ~= reordered[i] then savedChanged = true end
        saved[i] = reordered[i]
    end
    return true, savedChanged
end
