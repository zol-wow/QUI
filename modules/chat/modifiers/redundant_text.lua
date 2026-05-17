---------------------------------------------------------------------------
-- QUI Chat Modifier — Redundant-Text Cleanup
-- Compresses verbose loot/XP/honor/reputation/currency messages into
-- short forms. Uses Blizzard's GLOBALSTRINGS templates as the basis for
-- locale-safe pattern construction.
--
-- Applies after Blizzard has rendered the line, rather than through a
-- pre-dispatch chat filter, so addon string work cannot taint Blizzard's
-- chat-history bookkeeping.
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
    escaped = escaped:gsub("%%%d+%%%$[sd]", "(.-)")
    escaped = escaped:gsub("%%[sd]", "(.-)")
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
-- Collapse function
-- ---------------------------------------------------------------------------

-- Map event name to pattern key
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

local function ReadPackedArg(eventArgs, index)
    if IsSecret(eventArgs) or type(eventArgs) ~= "table" then return nil end
    local value = eventArgs[index]
    if IsSecret(value) then return nil end
    return value
end

local function GetRenderedLineKey(event, eventArgs)
    event = NormalizeEvent(event)
    if not event then return nil end
    local lineID = ReadPackedArg(eventArgs, 11)
    if lineID == nil then return nil end
    local valueType = type(lineID)
    if valueType ~= "number" and valueType ~= "string" then return nil end
    return event .. ":" .. tostring(lineID)
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

    local settings = I.GetSettings and I.GetSettings()
    local s = (I.IsChatEnabled and I.IsChatEnabled(settings))
        and settings.modifiers and settings.modifiers.redundantText
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

-- ---------------------------------------------------------------------------
-- Rendered-line hook installation
-- ---------------------------------------------------------------------------

local HOOKS_INSTALLED = false
local hookedFrames = setmetatable({}, { __mode = "k" })
local renderedState = setmetatable({}, { __mode = "k" })

local function GetRenderedState(frame)
    local state = renderedState[frame]
    if not state then
        state = { lineKeys = {} }
        renderedState[frame] = state
    end
    return state
end

local function ShouldTryCollapse(event)
    event = NormalizeEvent(event)
    if not event then return false end

    local key = EVENT_TO_KEY[event]
    if not key then return false end

    local settings = I.GetSettings and I.GetSettings()
    local s = (I.IsChatEnabled and I.IsChatEnabled(settings))
        and settings.modifiers and settings.modifiers.redundantText
    if not s or not s.enabled then return false end
    if not s.patterns or s.patterns[key] == false then return false end
    if not BUILT_PATTERNS[key] then return false end

    return true
end

local function shouldTransformMessage(frame, message, r, g, b, infoID, accessID, typeID, event, eventArgs)
    if not frame then return false end
    if IsSecret(message) then return false end
    if type(message) ~= "string" or message == "" then return false end

    local state = GetRenderedState(frame)
    local lineKey = GetRenderedLineKey(event, eventArgs)
    if lineKey and state.lineKeys[lineKey] then
        return false
    end

    local function markSeenAndSkip()
        if lineKey then
            state.lineKeys[lineKey] = true
        end
        return false
    end

    if IsChatMessagingLockedDown() then return markSeenAndSkip() end
    if not ShouldTryCollapse(event) then return markSeenAndSkip() end

    return true
end

local function transformMessage(frame, message, r, g, b, infoID, accessID, typeID, event, eventArgs, formatter, ...)
    local state = GetRenderedState(frame)
    local lineKey = GetRenderedLineKey(event, eventArgs)
    if lineKey and state.lineKeys[lineKey] then
        return message, r, g, b, infoID, accessID, typeID, event, eventArgs, formatter, ...
    end

    local newMessage = tryCollapse(message, event)
    if lineKey then
        state.lineKeys[lineKey] = true
    end

    if newMessage and not IsSecret(newMessage) and type(newMessage) == "string" then
        message = newMessage
    end
    return message, r, g, b, infoID, accessID, typeID, event, eventArgs, formatter, ...
end

local function onAddMessage(frame)
    if not frame or not frame.TransformMessages then return end
    frame:TransformMessages(
        function(...) return shouldTransformMessage(frame, ...) end,
        function(...) return transformMessage(frame, ...) end
    )
end

local function markExistingRenderedLines(frame)
    if not frame or not frame.GetNumMessages or not frame.GetMessageInfo then return end
    local okCount, count = pcall(frame.GetNumMessages, frame)
    if not okCount or type(count) ~= "number" then return end

    local state = GetRenderedState(frame)
    for i = 1, count do
        local ok, _, _, _, _, _, _, _, event, eventArgs = pcall(frame.GetMessageInfo, frame, i)
        if ok then
            local lineKey = GetRenderedLineKey(event, eventArgs)
            if lineKey then
                state.lineKeys[lineKey] = true
            end
        end
    end
end

local function hookFrame(frame)
    if not frame or hookedFrames[frame] then return end
    if not frame.TransformMessages then return end
    if not hooksecurefunc then return end

    hookedFrames[frame] = true
    markExistingRenderedLines(frame)
    hooksecurefunc(frame, "AddMessage", onAddMessage)
end

local function hookAllFrames()
    local n = _G.NUM_CHAT_WINDOWS or 10
    for i = 1, n do
        hookFrame(_G["ChatFrame" .. i])
    end
end

local function installRenderedHooks()
    if HOOKS_INSTALLED then
        hookAllFrames()
        return
    end

    HOOKS_INSTALLED = true
    hookAllFrames()

    if hooksecurefunc and _G.FCF_OpenNewWindow then
        hooksecurefunc("FCF_OpenNewWindow", function()
            if C_Timer and C_Timer.After then
                C_Timer.After(0.1, hookAllFrames)
            else
                hookAllFrames()
            end
        end)
    end

    if hooksecurefunc and _G.FCF_OpenTemporaryWindow then
        hooksecurefunc("FCF_OpenTemporaryWindow", function()
            if C_Timer and C_Timer.After then
                C_Timer.After(0.1, hookAllFrames)
            else
                hookAllFrames()
            end
        end)
    end
end

-- ---------------------------------------------------------------------------
-- ApplyEnabled (called from PLAYER_LOGIN, file-load, _afterRefresh)
-- ---------------------------------------------------------------------------

function ApplyEnabled()
    local settings = I.GetSettings and I.GetSettings()
    local enabled = (I.IsChatEnabled and I.IsChatEnabled(settings))
        and settings.modifiers and settings.modifiers.redundantText
        and settings.modifiers.redundantText.enabled

    if enabled then
        buildPatterns()
        installRenderedHooks()
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
