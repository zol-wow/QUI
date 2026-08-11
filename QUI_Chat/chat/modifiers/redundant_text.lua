local _, ns = ...

local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: redundant_text.lua loaded before chat.lua. Check chat.xml — chat.lua must precede redundant_text.lua.")

ns.QUI.Chat.RedundantText = ns.QUI.Chat.RedundantText or {}
local RT = ns.QUI.Chat.RedundantText

local function templateToLuaPattern(template)
    if type(template) ~= "string" or template == "" then return nil end
    local escaped = template:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", function(c)
        if c == "%" then return c end
        return "%" .. c
    end)
    escaped = escaped:gsub("%%%d+%%%$[sd]", "(.-)")
    escaped = escaped:gsub("%%[sd]", "(.-)")
    return "^" .. escaped .. "$"
end

local function buildHonor(captures) return "+" .. (captures[2] or captures[1] or "?") .. " Honor" end

local PATTERN_DEFS = {
    loot = {
        templates = { "LOOT_ITEM_SELF", "LOOT_ITEM" },
        builders = {
            function(captures) return "✓ " .. (captures[1] or "?") end,
            function(captures) return "✓ " .. (captures[1] or "?") .. " " .. (captures[2] or "?") end,
        },
    },
    currency = {
        templates = { "LOOT_CURRENCY_SELF", "LOOT_CURRENCY" },
        builders = {
            function(captures)
                if #captures >= 2 then
                    return "↑" .. (captures[1] or "?") .. "x " .. (captures[2] or "?")
                else
                    return "↑" .. (captures[1] or "?")
                end
            end,
            function(captures)
                if #captures >= 3 then
                    return (captures[1] or "?") .. " ↑" .. (captures[2] or "?") .. "x " .. (captures[3] or "?")
                else
                    return "↑" .. table.concat(captures, " ")
                end
            end,
        },
    },
    xp = {
        templates = { "COMBATLOG_XPGAIN_FIRSTPERSON", "COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED" },
        builders = {
            function(captures) return "+" .. (captures[2] or captures[1] or "?") .. " XP" end,
            function(captures) return "+" .. (captures[1] or "?") .. " XP" end,
        },
    },
    honor = {
        templates = { "COMBATLOG_HONORGAIN_NO_RANK", "COMBATLOG_HONORGAIN" },
        builders = {
            buildHonor,
            buildHonor,
        },
    },
    reputation = {
        templates = { "FACTION_STANDING_INCREASED", "FACTION_STANDING_DECREASED" },
        builders = {
            function(captures) return "↑" .. (captures[2] or "?") .. " " .. (captures[1] or "?") end,
            function(captures) return "↓" .. (captures[2] or "?") .. " " .. (captures[1] or "?") end,
        },
    },
}

local BUILT_PATTERNS = {}

local function buildPatterns()
    if next(BUILT_PATTERNS) ~= nil then return end
    for key, def in pairs(PATTERN_DEFS) do
        local patterns = {}
        for i, templateName in ipairs(def.templates) do
            local template = _G[templateName]
            if template then
                local luaPattern = templateToLuaPattern(template)
                if luaPattern then
                    patterns[#patterns + 1] = { luaPattern, def.builders[i] }
                end
            end
        end
        if #patterns > 0 then
            BUILT_PATTERNS[key] = patterns
        end
    end
end

local EVENT_TO_KEY = {
    CHAT_MSG_LOOT                  = "loot",
    CHAT_MSG_CURRENCY              = "currency",
    CHAT_MSG_COMBAT_XP_GAIN        = "xp",
    CHAT_MSG_COMBAT_HONOR_GAIN     = "honor",
    CHAT_MSG_COMBAT_FACTION_CHANGE = "reputation",
}

local Helpers = ns.Helpers

local function IsSecret(value)
    return Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(value)
end

local function IsChatMessagingLockedDown()
    return I.IsChatMessagingLockedDown and I.IsChatMessagingLockedDown()
end

local function NormalizeEvent(event)
    if IsSecret(event) or type(event) ~= "string" or event == "" then return nil end
    return event
end

local function getRedundantSettings()
    local settings = I.GetSettings and I.GetSettings()
    return (I.IsChatEnabled and I.IsChatEnabled(settings))
        and settings.modifiers and settings.modifiers.redundantText
end

local function SplitRenderedPrefix(message)
    if IsSecret(message) or type(message) ~= "string" then return "", message end

    local prefix, body = message:match("^(|cff%x%x%x%x%x%x%[%d%d?:%d%d%s?[AP]?[M]?%]|r%s)(.*)$")
    if prefix then return prefix, body end

    prefix, body = message:match("^(%[%d%d?:%d%d%s?[AP]?[M]?%]%s)(.*)$")
    if prefix then return prefix, body end

    return "", message
end

local function tryCollapse(msg, event)
    if IsSecret(msg) or IsChatMessagingLockedDown() then return msg end
    if not msg or type(msg) ~= "string" or msg == "" then return msg end

    event = NormalizeEvent(event)
    if not event then return msg end

    local key = EVENT_TO_KEY[event]
    if not key then return msg end

    local s = getRedundantSettings()
    if not s or not s.enabled then return msg end
    if not s.patterns or s.patterns[key] == false then return msg end

    local patterns = BUILT_PATTERNS[key]
    if not patterns then return msg end

    local prefix, body = SplitRenderedPrefix(msg)
    for i = 1, #patterns do
        local entry = patterns[i]
        local luaPattern, builder = entry[1], entry[2]
        local captures = { body:match(luaPattern) }
        if #captures > 0 then
            local replacement = builder(captures)
            if replacement then
                return prefix .. replacement
            end
        end
    end

    return msg
end

local function ShouldTryCollapse(event)
    event = NormalizeEvent(event)
    if not event then return false end

    local key = EVENT_TO_KEY[event]
    if not key then return false end

    local s = getRedundantSettings()
    if not s or not s.enabled then return false end
    if not s.patterns or s.patterns[key] == false then return false end
    if not BUILT_PATTERNS[key] then return false end

    return true
end

function RT.TryCollapseForCapture(message, event)
    if IsSecret(message) or type(message) ~= "string" or message == "" then return message end
    if not ShouldTryCollapse(event) then
        local s = getRedundantSettings()
        if not s or not s.enabled then return message end
        buildPatterns()
        if not ShouldTryCollapse(event) then return message end
    end
    local collapsed = tryCollapse(message, event)
    if collapsed and not IsSecret(collapsed) and type(collapsed) == "string" then
        return collapsed
    end
    return message
end
