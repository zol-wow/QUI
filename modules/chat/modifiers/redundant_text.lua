---------------------------------------------------------------------------
-- QUI Chat Modifier — Redundant-Text Cleanup
-- Compresses verbose loot/XP/honor/reputation/currency messages into
-- short forms. Uses Blizzard's GLOBALSTRINGS templates as the basis for
-- locale-safe pattern construction.
--
-- Registers its own secure message-event filter for LOOT, CURRENCY,
-- COMBAT_XP_GAIN, COMBAT_HONOR_GAIN, COMBAT_FACTION_CHANGE — these events
-- are deliberately NOT in the main pipeline's event list (the main
-- pipeline focuses on chat-message events; these are system messages
-- with different signatures).
---------------------------------------------------------------------------

local ADDON_NAME, ns = ...

local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: redundant_text.lua loaded before chat.lua. Check chat.xml — chat.lua must precede redundant_text.lua.")

ns.QUI.Chat.RedundantText = ns.QUI.Chat.RedundantText or {}
local RT = ns.QUI.Chat.RedundantText

-- Forward declaration so SetScript closures can call ApplyEnabled.
local ApplyEnabled

-- ---------------------------------------------------------------------------
-- Pattern construction from GLOBALSTRINGS
-- ---------------------------------------------------------------------------

-- Convert a Blizzard GLOBALSTRING template (with %s, %d, %1$s, etc.) into
-- a Lua pattern by escaping pattern magic and replacing format specifiers
-- with capture groups.
--
-- Example: "You receive item: %s." → "^You receive item: (.-)%.$"
-- Example: "%s receives item: %s." → "^(.-) receives item: (.-)%.$"
local function templateToLuaPattern(template)
    if type(template) ~= "string" or template == "" then return nil end
    -- Escape pattern magic chars
    local escaped = template:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", function(c)
        if c == "%" then return c end  -- leave % alone, we'll handle below
        return "%" .. c
    end)
    -- Replace format specifiers (%s, %d, %1$s, %2$d, etc.) with captures.
    -- Use a non-greedy capture so multi-format templates work correctly.
    escaped = escaped:gsub("%%%%[%d]?$?[sd]", "(.-)")
    -- Anchor start and end for stricter matching.
    return "^" .. escaped .. "$"
end

-- Pattern table: each entry has the GLOBALSTRINGS templates to match against
-- and a function that builds the short-form replacement from captures.
local PATTERN_DEFS = {
    loot = {
        templates = { "LOOT_ITEM_SELF", "LOOT_ITEM" },
        -- LOOT_ITEM_SELF: "You receive item: %s." → captures item link → "✓ %s"
        -- LOOT_ITEM:      "%s receives item: %s." → captures (player, item) → "✓ %s %s"
        builders = {
            function(captures) return "✓ " .. (captures[1] or "?") end,
            function(captures) return "✓ " .. (captures[1] or "?") .. " " .. (captures[2] or "?") end,
        },
    },
    currency = {
        templates = { "LOOT_CURRENCY_SELF", "LOOT_CURRENCY" },
        -- LOOT_CURRENCY_SELF: "You receive currency: %s." or "You receive %d %s." (varies)
        -- We collapse to "↑%s" / "↑%dx %s" depending on capture count
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
        -- "%s dies, you gain %d experience..." → "+%d XP"
        -- "You gain %d experience..." → "+%d XP"
        builders = {
            function(captures) return "+" .. (captures[2] or captures[1] or "?") .. " XP" end,
            function(captures) return "+" .. (captures[1] or "?") .. " XP" end,
        },
    },
    honor = {
        templates = { "COMBATLOG_HONORGAIN_NO_RANK", "COMBATLOG_HONORGAIN" },
        builders = {
            function(captures) return "+" .. (captures[2] or captures[1] or "?") .. " Honor" end,
            function(captures) return "+" .. (captures[2] or captures[1] or "?") .. " Honor" end,
        },
    },
    reputation = {
        templates = { "FACTION_STANDING_INCREASED", "FACTION_STANDING_DECREASED" },
        -- "Your reputation with %s has increased by %d." → "↑%d %s"
        -- "Your reputation with %s has decreased by %d." → "↓%d %s"
        builders = {
            function(captures) return "↑" .. (captures[2] or "?") .. " " .. (captures[1] or "?") end,
            function(captures) return "↓" .. (captures[2] or "?") .. " " .. (captures[1] or "?") end,
        },
    },
}

-- Built patterns: { [patternKey] = { { lua_pattern, builder }, ... } }
local BUILT_PATTERNS = {}

local function buildPatterns()
    if next(BUILT_PATTERNS) ~= nil then return end  -- already built
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

-- ---------------------------------------------------------------------------
-- Filter function
-- ---------------------------------------------------------------------------

local EVENTS = {
    "CHAT_MSG_LOOT",
    "CHAT_MSG_CURRENCY",
    "CHAT_MSG_COMBAT_XP_GAIN",
    "CHAT_MSG_COMBAT_HONOR_GAIN",
    "CHAT_MSG_COMBAT_FACTION_CHANGE",
}

-- Map event name to pattern key
local EVENT_TO_KEY = {
    CHAT_MSG_LOOT                  = "loot",
    CHAT_MSG_CURRENCY              = "currency",
    CHAT_MSG_COMBAT_XP_GAIN        = "xp",
    CHAT_MSG_COMBAT_HONOR_GAIN     = "honor",
    CHAT_MSG_COMBAT_FACTION_CHANGE = "reputation",
}

local Helpers = ns.Helpers

local function AddMessageEventFilter(event, filter)
    if ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
        ChatFrameUtil.AddMessageEventFilter(event, filter)
    elseif ChatFrame_AddMessageEventFilter then
        ChatFrame_AddMessageEventFilter(event, filter)
    end
end

local function RemoveMessageEventFilter(event, filter)
    if ChatFrameUtil and ChatFrameUtil.RemoveMessageEventFilter then
        ChatFrameUtil.RemoveMessageEventFilter(event, filter)
    elseif ChatFrame_RemoveMessageEventFilter then
        ChatFrame_RemoveMessageEventFilter(event, filter)
    end
end

local function tryCollapse(msg, event)
    if not msg or type(msg) ~= "string" or msg == "" then return msg end
    if Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(msg) then return msg end

    local key = EVENT_TO_KEY[event]
    if not key then return msg end

    local settings = I.GetSettings and I.GetSettings()
    local s = settings and settings.modifiers and settings.modifiers.redundantText
    if not s or not s.enabled then return msg end
    if not s.patterns or s.patterns[key] == false then return msg end

    local patterns = BUILT_PATTERNS[key]
    if not patterns then return msg end

    for i = 1, #patterns do
        local entry = patterns[i]
        local luaPattern, builder = entry[1], entry[2]
        local captures = { msg:match(luaPattern) }
        if #captures > 0 then
            local replacement = builder(captures)
            if replacement then
                return replacement
            end
        end
    end

    return msg
end

local function filter(self, event, msg, ...)
    if not msg or type(msg) ~= "string"
        or (Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(msg)) then
        return nil
    end

    local newMsg = tryCollapse(msg, event)
    if newMsg and not (Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(newMsg)) and newMsg ~= msg then
        if Helpers and Helpers.HasSecretValue and Helpers.HasSecretValue(...) then
            return nil
        end
        return false, newMsg, ...
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Filter installation / removal
-- ---------------------------------------------------------------------------

local INSTALLED = false

local function installFilter()
    if INSTALLED then return end
    buildPatterns()  -- ensure templates resolved (GLOBALSTRINGS available at file-load? probably yes; defensive)
    for i = 1, #EVENTS do
        AddMessageEventFilter(EVENTS[i], filter)
    end
    INSTALLED = true
end

local function removeFilter()
    if not INSTALLED then return end
    for i = 1, #EVENTS do
        RemoveMessageEventFilter(EVENTS[i], filter)
    end
    INSTALLED = false
end

-- ---------------------------------------------------------------------------
-- ApplyEnabled (called from PLAYER_LOGIN, file-load, _afterRefresh)
-- ---------------------------------------------------------------------------

function ApplyEnabled()
    local settings = I.GetSettings and I.GetSettings()
    local enabled = settings and settings.modifiers and settings.modifiers.redundantText
        and settings.modifiers.redundantText.enabled

    if enabled then
        installFilter()
    else
        removeFilter()
    end
end

-- Initial call at file-load. Defensive no-op when QUI.db is nil.
ApplyEnabled()

-- ---------------------------------------------------------------------------
-- PLAYER_LOGIN re-evaluation + after-refresh hook
-- ---------------------------------------------------------------------------

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        ApplyEnabled()
    end
end)

table.insert(ns.QUI.Chat._afterRefresh, ApplyEnabled)
