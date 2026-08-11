local ADDON_NAME, ns = ...

local _I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: tab_manager.lua loaded before chat.lua. Check chat.xml — chat.lua must precede tab_manager.lua.")

ns.QUI.Chat.TabManager = ns.QUI.Chat.TabManager or {}
local TabManager = ns.QUI.Chat.TabManager

local activeFilters = {}

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

local function NormalizeSetUpper(t)
    local set = NormalizeSet(t)
    if not set then return nil end
    local out = {}
    for key in pairs(set) do
        out[key:upper()] = true
    end
    return out
end

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

local GROUP_FAMILY_FALLBACK = {
    GUILD_DISCORD = "GUILD",
}

function TabManager.BuildFilter(tabData)
    if type(tabData) ~= "table" then return nil end
    local groups = NormalizeSet(tabData.groups)
    local channels = NormalizeSetUpper(tabData.channels)
    local channelsOff = NormalizeFalseSetUpper(tabData.channels)
    if not groups and not channels and not channelsOff then return nil end
    local invert = tabData.invert and true or false
    local rawGroups = type(tabData.groups) == "table" and tabData.groups or nil

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
                listed = true
            end
        else
            if groups then
                if entry.k and groups[entry.k] then listed = true end
                if not listed and entry.k then
                    local fallbackFrom = GROUP_FAMILY_FALLBACK[entry.k]
                    if fallbackFrom and (not rawGroups or rawGroups[entry.k] == nil) then
                        listed = groups[fallbackFrom] or false
                    end
                end
                if not listed and entry.e then
                    local grp = _G.ChatTypeGroupInverted and _G.ChatTypeGroupInverted[entry.e]
                    if not grp then grp = EVENT_GROUP_ALIAS[entry.e] end
                    if grp and groups[grp] then listed = true end
                end
            elseif not channels then
                listed = true
            end
        end
        if invert then
            return not listed
        end
        return listed
    end
end

function TabManager.EnsureDefaultChannelListed(name)
    if type(name) ~= "string" or name == "" then return end
    local tabs = TabManager.GetWindowTabs(1)
    if #tabs == 0 then return end
    local upper = name:upper()
    for i = 1, #tabs do
        local chs = type(tabs[i]) == "table" and tabs[i].channels
        if type(chs) == "table" then
            for stored in pairs(chs) do
                if type(stored) == "string" and stored:upper() == upper then
                    return
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

function TabManager.ReapplyAll()
    local Display = ns.QUI.Chat.DisplayLayer
    if not (Display and Display.Rebuild) then return end
    for id = 1, #activeFilters do
        Display.Rebuild(id, activeFilters[id])
    end
end

local displayOrderRef
function TabManager.OnWindowDeleted(windowID)
    windowID = tonumber(windowID) or 0
    if windowID >= 1 then
        table.remove(activeFilters, windowID)
    end
    if displayOrderRef and windowID >= 1 then
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

function TabManager.NewDefaultTab(name)
    return { name = name or "Tab 1", groups = {}, channels = {}, invert = false }
end

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

local function ReconcileCombatLogTab(cd)
    if type(cd) ~= "table" then return end
    local tabs = cd.windows and cd.windows[1] and cd.windows[1].tabs
    if type(tabs) ~= "table" then return end
    local enabled = cd.combatLogTab ~= false
    local kept
    for i = #tabs, 1, -1 do
        if TabManager.IsCombatLogTab(tabs[i]) then
            if enabled and not kept then
                kept = true
            else
                table.remove(tabs, i)
            end
        end
    end
    if enabled and not kept then
        tabs[#tabs + 1] = { name = "Combat Log", combatLog = true }
    end
end
TabManager._ReconcileCombatLogTab = ReconcileCombatLogTab

local function SeedWindows(settings)
    settings.customDisplay = settings.customDisplay or {}
    local cd = settings.customDisplay
    if type(cd.windows) ~= "table" then cd.windows = {} end
    if #cd.windows == 0 then
        cd.windows[1] = {
            width = 430,
            height = 190,
            tabs = {},
        }
    end
    for i = 1, #cd.windows do
        if type(cd.windows[i].tabs) ~= "table" then cd.windows[i].tabs = {} end
    end
    if #cd.windows[1].tabs == 0 then
        SeedTabsInto(cd.windows[1].tabs)
    end
    EnsureFriendStatusInSystemTabs(cd)
    ReconcileCombatLogTab(cd)
    return cd.windows
end

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

local displayOrder = {}
displayOrderRef = displayOrder

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

function TabManager.MoveDisplayEntry(windowID, from, to)
    local tokens = ReconcileOrder(windowID)
    local n = #tokens
    if n < 2 or type(from) ~= "number" or from < 1 or from > n then return false end
    if type(to) ~= "number" then return false end
    if to < 1 then to = 1 elseif to > n then to = n end
    if to == from then return false end

    local moved = table.remove(tokens, from)
    table.insert(tokens, to, moved)

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
