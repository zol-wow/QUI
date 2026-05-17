---------------------------------------------------------------------------
-- QUI Chat Module — Modifier Pipeline
-- Manages an ordered list of message modifiers. The chain is consumed from
-- chat.lua's rendered-line transform hook, after Blizzard has finished its
-- chat-history bookkeeping.
--
-- Whisper events are intentionally out of scope — Blizzard HistoryKeeper on
-- Midnight is taint-protected. Loot / XP / Honor / Faction events are also
-- out of scope here; redundant_text.lua owns their separate rendered transform.
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
        local ok, newMsg, newInfo = xpcall(function()
            return entry.fn(msg, info, event)
        end, geterrorhandler())
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

local PIPELINE_EVENT_SET = {}
for i = 1, #PIPELINE_EVENTS do
    PIPELINE_EVENT_SET[PIPELINE_EVENTS[i]] = true
end

function Pipeline.ShouldRunForEvent(event)
    if IsSecret(event) or type(event) ~= "string" then return false end
    return PIPELINE_EVENT_SET[event] == true
end

-- Expose for testability / introspection. NOT part of the documented API.
Pipeline._modifiers = modifiers
Pipeline._byName = byName
Pipeline._events = PIPELINE_EVENTS
Pipeline._eventSet = PIPELINE_EVENT_SET
