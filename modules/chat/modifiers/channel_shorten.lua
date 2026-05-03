---------------------------------------------------------------------------
-- QUI Chat Modifier — Channel Shortening
-- Shortens channel-prefix tokens in chat messages after Blizzard has safely
-- formatted and added each line.
--
-- Two preset modes:
--   Letter -> [Guild]/[G], [Officer]/[O], [Party]/[P], [Raid]/[R],
--             [Instance]/[I], [Say]/[S], [Yell]/[Y]
--   Number -> same; numbered chat channels (handled by ChatFrame_GetMessageEventGroup)
--             keep their leading number ([2.T]) — but this modifier is for
--             the Blizzard CHAT_*_GET template events, not custom channels.
--
-- Important: do not override CHAT_<EVENT>_GET globals. Blizzard reads those
-- templates on protected chat paths before creating chat-history access IDs;
-- addon-tainted templates can make secret sender GUIDs unsafe to lowercase.
---------------------------------------------------------------------------

local ADDON_NAME, ns = ...

local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: channel_shorten.lua loaded before chat.lua. Check chat.xml — chat.lua must precede channel_shorten.lua.")

local Helpers = ns.Helpers

-- ---------------------------------------------------------------------------
-- Preset shortening tables
-- ---------------------------------------------------------------------------

-- Maps Blizzard chat-event-type tags to short labels. The actual global
-- key is "CHAT_<TAG>_GET" (e.g., CHAT_GUILD_GET, CHAT_PARTY_GET).
local letterShort = {
    GUILD                = "G",
    OFFICER              = "O",
    PARTY                = "P",
    PARTY_LEADER         = "PL",
    RAID                 = "R",
    RAID_LEADER          = "RL",
    RAID_WARNING         = "RW",
    INSTANCE_CHAT        = "I",
    INSTANCE_CHAT_LEADER = "IL",
    SAY                  = "S",
    YELL                 = "Y",
}

-- For now, "number" preset uses the same labels as "letter" for these
-- non-numbered chat types. Numbered chat channels (CHAT_MSG_CHANNEL) are
-- rendered by Blizzard differently — they don't use a CHAT_*_GET template
-- and the channel-name shortening for those would require a separate
-- approach (e.g., gsub on the channel-name token in messages). Out of
-- scope for this Phase A modifier.
local numberShort = letterShort

-- ---------------------------------------------------------------------------
-- Template manipulation
-- ---------------------------------------------------------------------------

local SAVED_TEMPLATES = {}  -- captures original Blizzard strings for locale-aware matching

local function captureOriginals()
    if next(SAVED_TEMPLATES) ~= nil then return end  -- already captured
    for tag in pairs(letterShort) do
        local key = "CHAT_" .. tag .. "_GET"
        SAVED_TEMPLATES[key] = _G[key]
    end
end

local function escapePattern(text)
    return (text:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end

local function buildReplacements(preset)
    captureOriginals()
    local table_ = (preset == "number") and numberShort or letterShort
    local replacements = {}

    for tag, shortLabel in pairs(table_) do
        local key = "CHAT_" .. tag .. "_GET"
        local original = SAVED_TEMPLATES[key]
        if type(original) == "string" then
            local longBracket = original:match("%[[^%]]+%]")
            if longBracket then
                replacements[tag] = {
                    pattern = escapePattern(longBracket),
                    replacement = "[" .. shortLabel .. "]",
                }
            end
        end
    end

    return replacements
end

-- ---------------------------------------------------------------------------
-- Rendered-line transform
-- ---------------------------------------------------------------------------

local EVENT_TO_TAG = {}
for tag in pairs(letterShort) do
    EVENT_TO_TAG["CHAT_MSG_" .. tag] = tag
end

local ACTIVE_REPLACEMENTS = nil
local CURRENT_PRESET = nil
local hookedFrames = setmetatable({}, { __mode = "k" })

local function IsSecret(value)
    return Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(value)
end

local function shouldTransformMessage(message, r, g, b, infoID, accessID, typeID, event)
    if not ACTIVE_REPLACEMENTS or not event then return false end
    if IsSecret(message) or type(message) ~= "string" or message == "" then return false end

    local tag = EVENT_TO_TAG[event]
    local replacement = tag and ACTIVE_REPLACEMENTS[tag]
    return replacement and message:find(replacement.pattern) ~= nil
end

local function transformMessage(message, r, g, b, infoID, accessID, typeID, event, eventArgs, formatter, ...)
    local tag = event and EVENT_TO_TAG[event]
    local replacement = tag and ACTIVE_REPLACEMENTS and ACTIVE_REPLACEMENTS[tag]

    if replacement and not IsSecret(message) and type(message) == "string" then
        message = message:gsub(replacement.pattern, replacement.replacement, 1)
    end

    return message, r, g, b, infoID, accessID, typeID, event, eventArgs, formatter, ...
end

local function onAddMessage(frame, message, r, g, b, infoID, accessID, typeID, event)
    if not ACTIVE_REPLACEMENTS or not event then return end
    local tag = EVENT_TO_TAG[event]
    if not tag or not ACTIVE_REPLACEMENTS[tag] then return end
    if not frame or not frame.TransformMessages then return end

    frame:TransformMessages(shouldTransformMessage, transformMessage)
end

local function hookFrame(frame)
    if not frame or hookedFrames[frame] then return end
    hookedFrames[frame] = true
    hooksecurefunc(frame, "AddMessage", onAddMessage)
end

local function hookAllChatFrames()
    local n = _G.NUM_CHAT_WINDOWS or 10
    for i = 1, n do
        hookFrame(_G["ChatFrame" .. i])
    end
end

-- ---------------------------------------------------------------------------
-- Apply based on settings (called from _afterRefresh and PLAYER_LOGIN)
-- ---------------------------------------------------------------------------

local function ApplyEnabled()
    local settings = I.GetSettings and I.GetSettings()
    local s = settings and settings.modifiers and settings.modifiers.channelShorten
    local enabled = s and s.enabled
    local preset = (s and s.preset) or "letter"

    if enabled then
        if CURRENT_PRESET ~= preset then
            ACTIVE_REPLACEMENTS = buildReplacements(preset)
            CURRENT_PRESET = preset
        end
        hookAllChatFrames()
    else
        ACTIVE_REPLACEMENTS = nil
        CURRENT_PRESET = nil
    end
end

-- Initial application. Runs at file-load time. Settings may not be ready
-- yet (AceDB constructed in OnInitialize), in which case this is a no-op
-- and PLAYER_LOGIN below picks up the actual activation.
ApplyEnabled()

-- ---------------------------------------------------------------------------
-- PLAYER_LOGIN re-evaluation + after-refresh hook registration
-- ---------------------------------------------------------------------------

-- PLAYER_LOGIN fires after all addons' OnInitialize, so QUI.db is ready.
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        ApplyEnabled()
    end
end)

-- Hook into chat module's centralized after-refresh dispatcher so live
-- setting toggles (and profile switch / import) re-apply.
table.insert(ns.QUI.Chat._afterRefresh, ApplyEnabled)

if hooksecurefunc and _G.FCF_OpenNewWindow then
    hooksecurefunc("FCF_OpenNewWindow", function()
        if C_Timer and C_Timer.After then
            C_Timer.After(0.1, hookAllChatFrames)
        else
            hookAllChatFrames()
        end
    end)
end

if hooksecurefunc and _G.FCF_OpenTemporaryWindow then
    hooksecurefunc("FCF_OpenTemporaryWindow", function()
        if C_Timer and C_Timer.After then
            C_Timer.After(0.1, hookAllChatFrames)
        else
            hookAllChatFrames()
        end
    end)
end
