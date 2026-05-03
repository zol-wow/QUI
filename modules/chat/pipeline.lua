---------------------------------------------------------------------------
-- QUI Chat Module — Modifier Pipeline
-- Manages an ordered list of message modifiers and wires a single master
-- ChatFrameUtil message-event filter that runs the chain for in-scope events.
--
-- Whisper events are intentionally NOT registered — Blizzard HistoryKeeper
-- on Midnight is taint-protected; touching whispers in this filter chain
-- risks taint. Loot / XP / Honor / Faction events are also out of scope
-- here (Phase A.2 will register a separate filter for those).
--
-- Modifier signature: fn(msg, info, event) -> msg, info  (both required;
-- nil for either return means "no change for that value")
-- Modifiers run in ascending priority order; xpcall isolates each so a
-- single failure cannot break the chain.
---------------------------------------------------------------------------

local ADDON_NAME, ns = ...

local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: pipeline.lua loaded before chat.lua. Check chat.xml — chat.lua must precede pipeline.lua.")

ns.QUI.Chat.Pipeline = ns.QUI.Chat.Pipeline or {}
local Pipeline = ns.QUI.Chat.Pipeline
local Helpers = ns.Helpers

local function IsSecret(value)
    return Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(value)
end

local function SafeFilterValue(value)
    if IsSecret(value) then return nil end
    return value
end

local function AddMessageEventFilter(event, filter)
    if ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
        ChatFrameUtil.AddMessageEventFilter(event, filter)
    elseif ChatFrame_AddMessageEventFilter then
        ChatFrame_AddMessageEventFilter(event, filter)
    end
end

-- Ordered list of { name, priority, fn } entries. Sorted ascending by priority.
local modifiers = {}

-- Lookup by name for unregister + duplicate-detect.
local byName = {}

local function compare(a, b)
    return a.priority < b.priority
end

function Pipeline.Register(name, priority, fn)
    if type(name) ~= "string" or name == "" then
        error("Pipeline.Register: name must be a non-empty string", 2)
    end
    if type(priority) ~= "number" then
        error("Pipeline.Register: priority must be a number", 2)
    end
    if type(fn) ~= "function" then
        error("Pipeline.Register: fn must be a function", 2)
    end

    -- Re-registration: replace existing entry. Useful for live-toggle via
    -- setting changes (modifier files re-call Register on enable).
    if byName[name] then
        for i = #modifiers, 1, -1 do
            if modifiers[i].name == name then
                table.remove(modifiers, i)
                break
            end
        end
    end

    local entry = { name = name, priority = priority, fn = fn }
    table.insert(modifiers, entry)
    byName[name] = entry
    table.sort(modifiers, compare)
end

function Pipeline.Unregister(name)
    if not byName[name] then return end
    for i = #modifiers, 1, -1 do
        if modifiers[i].name == name then
            table.remove(modifiers, i)
            break
        end
    end
    byName[name] = nil
end

function Pipeline.Run(msg, info, event)
    for i = 1, #modifiers do
        local entry = modifiers[i]
        local ok, newMsg, newInfo = xpcall(entry.fn, geterrorhandler(), msg, info, event)
        if ok then
            -- Modifiers may return nil for either to mean "no change"
            if newMsg ~= nil then msg = newMsg end
            if newInfo ~= nil then info = newInfo end
        end
        -- If xpcall fails, geterrorhandler() already logged it; we just
        -- skip this modifier's effect and continue with prior values.
    end
    return msg, info
end

-- ---------------------------------------------------------------------------
-- Master filter wiring
-- ---------------------------------------------------------------------------

-- Events the pipeline transforms. Whispers, loot/xp/honor/faction, and
-- system events are intentionally excluded.
local PIPELINE_EVENTS = {
    "CHAT_MSG_SAY",
    "CHAT_MSG_YELL",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_GUILD",
    "CHAT_MSG_OFFICER",
    "CHAT_MSG_CHANNEL",
}

local masterFilter = function(self, event, msg, ...)
    -- IsSecret first: type(msg) on a secret string taints the dispatch
    -- chain, which then propagates into MessageEventHandler and breaks
    -- Blizzard's per-chatType formatter when it string-converts secret
    -- sender names (e.g. LookingForGroup channel). Same defensive
    -- ordering as copy.lua:135 and history.lua's captureToHistory.
    if IsSecret(msg) or not msg or type(msg) ~= "string" then
        return nil
    end

    if #modifiers == 0 then
        return nil
    end

    local canReturnArgs = not (Helpers and Helpers.HasSecretValue and Helpers.HasSecretValue(...))

    -- Build minimal info table for modifier consumption. Raw varargs are only
    -- exposed when every passthrough value can be safely returned unchanged.
    -- CHAT_MSG_* args (after msg): author, _, language, channelString, target,
    -- flags, channelNumber, channelName, _, lineID, guid, bnSenderID, ...
    local info = {
        event         = event,
        author        = SafeFilterValue(select(1, ...)),
        language      = SafeFilterValue(select(3, ...)),
        flags         = SafeFilterValue(select(6, ...)),
        channelNumber = SafeFilterValue(select(7, ...)),
        channelName   = SafeFilterValue(select(8, ...)),
        lineID        = SafeFilterValue(select(10, ...)),
        guid          = SafeFilterValue(select(11, ...)),
    }
    if canReturnArgs then
        info._raw = { ... }
    end

    local newMsg, _ = Pipeline.Run(msg, info, event)

    if not newMsg
        or IsSecret(newMsg)
        or newMsg == msg then
        return nil
    end

    if not canReturnArgs then
        return nil
    end

    -- Blizzard's filter chain expects the filter to return either:
    --   nil (no change)
    --   true (suppress message)
    --   false, msg, ... (don't suppress, pass modified msg + varargs)
    -- Only return the replacement tuple when a non-secret message changed.
    return false, newMsg, ...
end

local installed = false
local function InstallMasterFilter()
    if installed then return end
    installed = true
    for i = 1, #PIPELINE_EVENTS do
        AddMessageEventFilter(PIPELINE_EVENTS[i], masterFilter)
    end
end

-- Install at file-load time. The current ChatFrameUtil registry stores filters
-- in secure containers; older clients fall back to the legacy global.
InstallMasterFilter()

-- Expose for testability / introspection. NOT part of the documented API.
Pipeline._modifiers = modifiers
Pipeline._byName = byName
Pipeline._events = PIPELINE_EVENTS
