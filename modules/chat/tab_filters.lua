---------------------------------------------------------------------------
-- QUI Chat Module — Per-Tab Content Filtering (Phase E)
-- Persists per-tab message group + channel selections at
-- db.profile.chat.tabs[<frameID>] = { customized, groups, channels }, then
-- reconciles each chat frame's actual messageTypeList / channelList against
-- the stored desired state. Inclusion-only (no inversion).
--
-- Reconcile triggers:
--   * ADDON_LOADED (after defaults wiring)
--   * PLAYER_LOGIN (after Blizzard finishes initializing chat windows)
--   * Settings change via TF.SaveTabConfig / TF.ResetTab (live update)
--   * Hooked FCF_OpenNewWindow for newly-created permanent windows
--
-- A small accent pill is placed on tabs with stored customized state so users
-- can see at a glance which tabs have user-defined filtering.
---------------------------------------------------------------------------

local ADDON_NAME, ns = ...

local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: tab_filters.lua loaded before chat.lua. Check chat.xml — chat.lua must precede tab_filters.lua.")

ns.QUI.Chat.TabFilters = ns.QUI.Chat.TabFilters or {}
local TF = ns.QUI.Chat.TabFilters

-- Forward declaration so closures (event handler, after-refresh, hooks) can
-- capture ApplyEnabled before its body is assigned later in the file.
local ApplyEnabled

-- ---------------------------------------------------------------------------
-- Reconciliation
-- ---------------------------------------------------------------------------

-- Convert array-of-strings to set-of-keys. lowerCase=true folds keys to
-- lowercase before insertion — needed for channel comparison because
-- Blizzard's frame.channelList stores lowercase names while GetChannelList
-- returns mixed-case (e.g. "Services"). Without folding, set membership
-- mismatches and reconcile fires both Add and Remove for the same channel.
local function listToSet(list, lowerCase)
    local set = {}
    if list then
        for i = 1, #list do
            local v = list[i]
            if v ~= nil then
                if lowerCase and type(v) == "string" then v = v:lower() end
                set[v] = true
            end
        end
    end
    return set
end

-- Diff `frame.messageTypeList` / `frame.channelList` against the stored
-- desired sets and call Add/Remove APIs to bring them in sync. No-op when
-- the frame has no stored entry, or `customized = false`.
local function reconcileFrame(frame, frameID)
    if not frame then return end
    if frame.IsForbidden and frame:IsForbidden() then return end

    local settings = I.GetSettings and I.GetSettings()
    local tabsConfig = settings and settings.tabs
    local entry = tabsConfig and tabsConfig[frameID]
    if not entry or not entry.customized then return end
    -- No empty-arrays early-return. customized=true with empty groups means
    -- "show nothing on this tab" — a valid intentional state. The fresh-toggle
    -- "don't blank the tab" concern is already handled by seedEntryFromCurrentFrame
    -- in the settings UI before any save happens.
    if type(entry.groups) ~= "table" then entry.groups = {} end
    if type(entry.channels) ~= "table" then entry.channels = {} end

    -- Group reconciliation. Groups are uppercase keys ("SAY", "EMOTE")
    -- consistently in both stored config and frame.messageTypeList — no
    -- case folding needed.
    local desiredGroups = listToSet(entry.groups)
    local actualGroups = listToSet(frame.messageTypeList)

    for group in pairs(desiredGroups) do
        if not actualGroups[group] then
            if ChatFrame_AddMessageGroup then
                ChatFrame_AddMessageGroup(frame, group)
            end
        end
    end
    for group in pairs(actualGroups) do
        if not desiredGroups[group] then
            if ChatFrame_RemoveMessageGroup then
                ChatFrame_RemoveMessageGroup(frame, group)
            end
        end
    end

    -- Channel reconciliation. Fold both sides to lowercase — entry.channels
    -- holds names from GetChannelList (mixed case) while frame.channelList
    -- stores lowercase. ChatFrame_AddChannel / ChatFrame_RemoveChannel
    -- accept either case (Blizzard lowercases internally).
    local desiredChannels = listToSet(entry.channels, true)
    local actualChannels = listToSet(frame.channelList, true)

    for channel in pairs(desiredChannels) do
        if not actualChannels[channel] then
            if ChatFrame_AddChannel then
                ChatFrame_AddChannel(frame, channel)
            end
        end
    end
    for channel in pairs(actualChannels) do
        if not desiredChannels[channel] then
            if ChatFrame_RemoveChannel then
                ChatFrame_RemoveChannel(frame, channel)
            end
        end
    end
end

local function reconcileAll()
    local n = _G.NUM_CHAT_WINDOWS or 10
    for i = 1, n do
        local f = _G["ChatFrame" .. i]
        if f then reconcileFrame(f, i) end
    end
end

TF.ReconcileFrame = reconcileFrame
TF.ReconcileAll   = reconcileAll

-- ---------------------------------------------------------------------------
-- Tab indicator (theme-accent pill on customized tabs)
-- ---------------------------------------------------------------------------
-- Indicators are stored in a local map keyed by tab frame to avoid attaching
-- arbitrary properties to Blizzard frames. The textures themselves are still
-- parented to the tab frame so they inherit show/hide on tab visibility.
-- The mark anchors to QUI's visible tab chrome when available so it sits on
-- the tab surface instead of the larger underlying Blizzard hitbox.

local indicators = {}  -- map: tab frame -> indicator texture
local FILTER_MARK_WIDTH = 12
local FILTER_MARK_HEIGHT = 2

local function getOrCreateIndicator(tab)
    if indicators[tab] then return indicators[tab] end

    local indicator = tab:CreateTexture(nil, "OVERLAY")
    indicator:SetSize(FILTER_MARK_WIDTH, FILTER_MARK_HEIGHT)
    indicator:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    indicators[tab] = indicator
    return indicator
end

local function layoutIndicator(tab, indicator)
    if not tab or not indicator then return end

    local anchor = (I.tabBackdrops and I.tabBackdrops[tab]) or tab
    indicator:ClearAllPoints()
    indicator:SetSize(FILTER_MARK_WIDTH, FILTER_MARK_HEIGHT)
    indicator:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 6, 3)
end

-- Re-applies the theme accent so a user changing their accent color propagates
-- to existing indicators on the next updateTabIndicators pass without /reload.
local function applyIndicatorColor(indicator)
    local accent = I.GetAccent and I.GetAccent()
    local r = (accent and accent[1]) or 0.376
    local g = (accent and accent[2]) or 0.647
    local b = (accent and accent[3]) or 0.980
    indicator:SetVertexColor(r, g, b, 0.95)
end

local function updateTabIndicators()
    local settings = I.GetSettings and I.GetSettings()
    local tabsConfig = settings and settings.tabs

    local n = _G.NUM_CHAT_WINDOWS or 10
    for i = 1, n do
        local tab = _G["ChatFrame" .. i .. "Tab"]
        if tab then
            local entry = tabsConfig and tabsConfig[i]
            if entry and entry.customized then
                local ind = getOrCreateIndicator(tab)
                layoutIndicator(tab, ind)
                applyIndicatorColor(ind)
                ind:Show()
            else
                if indicators[tab] then indicators[tab]:Hide() end
            end
        end
    end
end

TF.UpdateTabIndicators = updateTabIndicators

-- ---------------------------------------------------------------------------
-- Settings helpers (used by the settings UI)
-- ---------------------------------------------------------------------------

-- Save a tab's filter config and trigger immediate reconcile. `groups` and
-- `channels` are arrays of string keys; if both are empty, reconcile treats
-- the entry as unconfigured so a fresh toggle cannot blank the tab.
function TF.SaveTabConfig(frameID, groups, channels)
    local settings = I.GetSettings and I.GetSettings()
    if not settings then return end
    settings.tabs = settings.tabs or {}
    settings.tabs[frameID] = {
        customized = true,
        groups = groups or {},
        channels = channels or {},
    }
    local frame = _G["ChatFrame" .. frameID]
    if frame then reconcileFrame(frame, frameID) end
    updateTabIndicators()
end

-- Reset a tab to Blizzard defaults — clears our stored config. Note: we
-- cannot exactly restore Blizzard's original default group/channel set
-- without a full chat-frame re-init, so we surface a hint to /rl for a
-- complete reset. Subsequent reconcile calls become no-ops once the entry
-- is gone.
function TF.ResetTab(frameID)
    local settings = I.GetSettings and I.GetSettings()
    if not settings or not settings.tabs then return end
    settings.tabs[frameID] = nil
    updateTabIndicators()
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff34D399[QUI]|r Tab " .. frameID .. " reset; reload UI to fully restore Blizzard defaults.",
            1, 1, 1)
    end
end

-- ---------------------------------------------------------------------------
-- ApplyEnabled
-- ---------------------------------------------------------------------------

function ApplyEnabled()
    reconcileAll()
    updateTabIndicators()
end

-- Initial application. Defensive no-op if QUI.db isn't ready at file-load
-- time (GetSettings returns nil); PLAYER_LOGIN guarantees activation once
-- AceDB has been constructed in OnInitialize.
ApplyEnabled()

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
eventFrame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == ADDON_NAME then
        ApplyEnabled()
    elseif event == "PLAYER_LOGIN" then
        ApplyEnabled()
    elseif event == "CHAT_MSG_CHANNEL_NOTICE" then
        -- Channel list may have changed (join/leave). Settings UI re-reads
        -- the channel list when the tile opens, so no reconcile is needed
        -- here — joining a channel does not auto-add it to a customized
        -- tab; users must opt in via the settings tile.
    end
end)

-- Hook FCF_OpenNewWindow so newly-created permanent windows pick up
-- stored config (in case an entry already exists for the new frameID,
-- e.g. the user reset and recreated a window between reloads).
if hooksecurefunc and FCF_OpenNewWindow then
    hooksecurefunc("FCF_OpenNewWindow", function() ApplyEnabled() end)
end

-- Register ApplyEnabled with the chat module's centralized after-refresh
-- hook list so it runs after every chat refresh (settings change, profile
-- switch, profile import, etc.).
table.insert(ns.QUI.Chat._afterRefresh, ApplyEnabled)

-- TEMP DEBUG — remove after diagnosing tab-filter issue.
-- Usage: /qtf 6
SLASH_QUITABFILTERS1 = "/qtf"
SlashCmdList["QUITABFILTERS"] = function(msg)
    local id = tonumber(msg) or 1
    local f = _G["ChatFrame" .. id]
    local s = QUI and QUI.db and QUI.db.profile and QUI.db.profile.chat
                  and QUI.db.profile.chat.tabs and QUI.db.profile.chat.tabs[id]
    local function has(list, key)
        if type(list) ~= "table" then return "n/a" end
        for i = 1, #list do if list[i] == key then return true end end
        return false
    end
    print("=== QTF tab" .. id .. " ===")
    print("API AddMessageGroup:", type(ChatFrame_AddMessageGroup),
          "RemoveMessageGroup:", type(ChatFrame_RemoveMessageGroup),
          "AddChannel:", type(ChatFrame_AddChannel),
          "RemoveChannel:", type(ChatFrame_RemoveChannel))
    print("frame:", f and "ok" or "NIL", "entry:", s and "ok" or "NIL",
          "customized:", s and tostring(s.customized))
    print("entry.groups n=", s and s.groups and #s.groups,
          "has SAY:", s and tostring(has(s.groups, "SAY")))
    print("frame.messageTypeList n=", f and f.messageTypeList and #f.messageTypeList,
          "has SAY:", f and tostring(has(f.messageTypeList, "SAY")))
    print("frame:IsEventRegistered CHAT_MSG_SAY:",
          f and tostring(f:IsEventRegistered("CHAT_MSG_SAY")))
end
