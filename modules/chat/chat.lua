---------------------------------------------------------------------------
-- QUI Chat Module
-- Glass-style chat frame customization with URL detection and copy support
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local QUI = ns.QUI or {}
ns.QUI = QUI
local QUICore = ns.Addon
local Helpers = ns.Helpers
local UIKit = ns.UIKit

---------------------------------------------------------------------------
-- Local references
---------------------------------------------------------------------------

-- Weak-keyed tables to store per-frame state WITHOUT writing properties to Blizzard frames
-- (avoids taint from `chatFrame.__quiXxx = value` writes). Surfaced on
-- ns.QUI.Chat._internals so sibling files (skinning.lua, cleanup.lua, copy.lua,
-- sounds.lua, editbox_basics.lua, editbox_history.lua) can share the same instances.
ns.QUI.Chat = ns.QUI.Chat or {}
ns.QUI.Chat._internals = ns.QUI.Chat._internals or {}
local I = ns.QUI.Chat._internals

-- Modifier files append callbacks here. RefreshAll runs them at end.
ns.QUI.Chat._afterRefresh = ns.QUI.Chat._afterRefresh or {}

-- Shared color palette. Single source of truth for the chat module —
-- skinning.lua's tab accent and copy.lua's popup styling read from here.
-- Local fallback palette. The accent here is only used when the options
-- framework hasn't loaded yet (or fails to load) — otherwise consumers
-- resolve the live theme accent through I.GetAccent below, so changing
-- theme preset in options propagates to chat surfaces without needing
-- a separate copy here that would silently go stale.
I.QUI_COLORS = I.QUI_COLORS or {
    bg       = {0.067, 0.094, 0.153, 0.97},
    accent   = {0.204, 0.827, 0.600, 1},     -- #34D399 fallback (mint)
    text     = {0.953, 0.957, 0.965, 1},
    textDim  = {0.72,  0.72,  0.76,  1},     -- inactive tab label
}

-- Live theme accent resolver. Reads QUI.GUI.Colors.accent (mutated in place
-- by GUI:ApplyAccentColor on theme preset change) so a user switching from
-- mint to a custom accent sees chat tabs follow on next repaint, instead of
-- being stuck on whatever value was captured at module load.
function I.GetAccent()
    -- _G.QUI here is the global addon (this file's local QUI is ns.QUI, the
    -- chat-module namespace — different table). The framework mutates
    -- _G.QUI.GUI.Colors.accent in place on preset change, so reading at call
    -- time picks up the current accent without a subscription.
    local guiColors = _G.QUI and _G.QUI.GUI and _G.QUI.GUI.Colors
    return (guiColors and guiColors.accent) or I.QUI_COLORS.accent
end

function I.GetThemeColors()
    local guiColors = _G.QUI and _G.QUI.GUI and _G.QUI.GUI.Colors
    local accent = I.GetAccent()
    return {
        bg = (guiColors and guiColors.bg) or I.QUI_COLORS.bg,
        bgDark = (guiColors and guiColors.bgDark) or {0.03, 0.04, 0.06, 1},
        bgContent = (guiColors and guiColors.bgContent) or {1, 1, 1, 0.02},
        text = (guiColors and guiColors.text) or I.QUI_COLORS.text,
        textDim = (guiColors and guiColors.textDim) or I.QUI_COLORS.textDim,
        textMuted = (guiColors and guiColors.textMuted) or I.QUI_COLORS.textDim,
        border = (guiColors and guiColors.border) or {1, 1, 1, 0.08},
        accent = accent,
        accentHover = (guiColors and guiColors.accentHover) or accent,
    }
end

-- skinnedFrames tracks which chat frames have been styled. Regular (non-weak)
-- table because the "already skinned" semantic must persist for the lifetime of
-- the addon. Promoted to _internals so skinning.lua's SkinChatFrame and
-- chat.lua's RefreshAll share the same instance.
I.skinnedFrames = I.skinnedFrames or {}

I.chatBackdrops       = I.chatBackdrops       or Helpers.CreateStateTable()
I.editBoxBackdrops    = I.editBoxBackdrops    or Helpers.CreateStateTable()
I.editBoxState        = I.editBoxState        or Helpers.CreateStateTable()
I.tabBackdrops        = I.tabBackdrops        or Helpers.CreateStateTable()
I._chatButtonsHidden  = I._chatButtonsHidden  or Helpers.CreateStateTable()
I.copyButtonHookState = I.copyButtonHookState or Helpers.CreateStateTable()
if not I.scrollbackState or not I.GetScrollbackState then
    I.scrollbackState, I.GetScrollbackState = Helpers.CreateStateTable()
end
if not I.surfaceState then
    I.surfaceState, I.GetSurfaceState = Helpers.CreateStateTable() -- backdrop/popup frame -> { bg, border }
end

function I.IsChatMessagingLockedDown()
    return C_ChatInfo
        and C_ChatInfo.InChatMessagingLockdown
        and C_ChatInfo.InChatMessagingLockdown()
        or false
end

local skinnedFrames   = I.skinnedFrames
local tabBackdrops    = I.tabBackdrops
local GetSurfaceState = I.GetSurfaceState
local GetScrollbackState = I.GetScrollbackState

-- URL detection patterns (standard protocol, www formats, and known invite
-- domains that are commonly posted without a scheme).
local URL_PATTERNS = {
    "%a[%w+.-]+://%S+",              -- protocol://path
    "www%.[-%w_%%]+%.%a%a+/%S+",     -- www.domain.tld/path
    "www%.[-%w_%%]+%.%a%a+",         -- www.domain.tld
    "discord%.gg/%S+",               -- discord.gg/invite
    "discord%.com/invite/%S+",       -- discord.com/invite/code
    "discordapp%.com/invite/%S+",    -- legacy invite host
}

local TRAILING_URL_PUNCTUATION = {
    ["."] = true,
    [","] = true,
    [";"] = true,
    [":"] = true,
    ["!"] = true,
    ["?"] = true,
    [")"] = true,
    ["]"] = true,
    ["}"] = true,
    [">"] = true,
}

local function IsURLStartBoundary(text, startIndex)
    if startIndex <= 1 then return true end
    local previous = text:sub(startIndex - 1, startIndex - 1)
    return previous:match("[%s%(\"'<]") ~= nil
end

local function SplitTrailingURLPunctuation(url)
    local suffix = ""
    while #url > 0 do
        local last = url:sub(-1)
        if not TRAILING_URL_PUNCTUATION[last] then break end
        suffix = last .. suffix
        url = url:sub(1, -2)
    end
    return url, suffix
end

---------------------------------------------------------------------------
-- Get settings from database
---------------------------------------------------------------------------
local GetSettings = Helpers.CreateDBGetter("chat")

local function IsChatEnabled(settings)
    return settings and settings.enabled ~= false
end

local SCROLLBACK_MAX_LINES = 5000
local BLIZZARD_TIMESTAMP_SETTING = "showTimestamps"
local BLIZZARD_TIMESTAMP_NONE = "none"
local blizzardTimestampFormat
local blizzardTimestampSetting
local timestampOverrideActive = false

local function GetBlizzardTimestampSetting()
    if Settings and Settings.GetValue then
        local ok, value = pcall(Settings.GetValue, BLIZZARD_TIMESTAMP_SETTING)
        if ok and value ~= nil then
            return value
        end
    end

    if type(GetCVar) == "function" then
        local ok, value = pcall(GetCVar, BLIZZARD_TIMESTAMP_SETTING)
        if ok then
            return value
        end
    end
    return nil
end

local function SetBlizzardTimestampSetting(value)
    if value == nil then return false end

    if Settings and Settings.SetValue then
        local ok = pcall(Settings.SetValue, BLIZZARD_TIMESTAMP_SETTING, value)
        if ok then
            return true
        end
    end

    if C_CVar and C_CVar.SetCVar then
        local ok = pcall(C_CVar.SetCVar, BLIZZARD_TIMESTAMP_SETTING, tostring(value))
        if ok then
            return true
        end
    end

    if type(SetCVar) == "function" then
        local ok = pcall(SetCVar, BLIZZARD_TIMESTAMP_SETTING, value)
        if ok then
            return true
        end
    end

    return false
end

local function IsBlizzardTimestampValueOff(value)
    return value == nil or value == "" or value == BLIZZARD_TIMESTAMP_NONE or value == "0"
end

local function IsBlizzardTimestampCVarOff()
    return IsBlizzardTimestampValueOff(GetBlizzardTimestampSetting())
end

local function GetSavedBlizzardTimestampSetting(settings)
    local timestamps = settings and settings.timestamps
    return timestamps and timestamps._blizzardTimestampSetting
end

local function SaveBlizzardTimestampSetting(settings, value)
    local timestamps = settings and settings.timestamps
    if timestamps then
        timestamps._blizzardTimestampSetting = value
    end
end

local function GetBlizzardTimestampFormat()
    if _G.CHAT_TIMESTAMP_FORMAT ~= nil then
        return _G.CHAT_TIMESTAMP_FORMAT
    end

    local value = GetBlizzardTimestampSetting()
    if not IsBlizzardTimestampValueOff(value) and type(value) == "string" and value:find("%%", 1, true) then
        return value
    end
    return nil
end

local function ShouldUseQUITimestamps(settings)
    return IsChatEnabled(settings)
        and settings.timestamps
        and settings.timestamps.enabled
end

local function ApplyTimestampMode(settings)
    settings = settings or GetSettings()

    if ShouldUseQUITimestamps(settings) then
        local nativeSetting = GetBlizzardTimestampSetting()
        local nativeFormat = GetBlizzardTimestampFormat()
        local savedSetting = GetSavedBlizzardTimestampSetting(settings)
        if not timestampOverrideActive then
            blizzardTimestampSetting = savedSetting or nativeSetting
            blizzardTimestampFormat = nativeFormat
            timestampOverrideActive = true
        elseif not IsBlizzardTimestampValueOff(nativeSetting) then
            blizzardTimestampSetting = nativeSetting
            blizzardTimestampFormat = nativeFormat
        elseif nativeFormat ~= nil then
            blizzardTimestampFormat = nativeFormat
        end
        _G.CHAT_TIMESTAMP_FORMAT = nil
        if not IsBlizzardTimestampValueOff(nativeSetting) then
            SaveBlizzardTimestampSetting(settings, nativeSetting)
            SetBlizzardTimestampSetting(BLIZZARD_TIMESTAMP_NONE)
        end
        return
    end

    if timestampOverrideActive then
        local restoreSetting = blizzardTimestampSetting or GetSavedBlizzardTimestampSetting(settings)
        if restoreSetting ~= nil and IsBlizzardTimestampCVarOff() then
            SetBlizzardTimestampSetting(restoreSetting)
        end
        if _G.CHAT_TIMESTAMP_FORMAT == nil then
            _G.CHAT_TIMESTAMP_FORMAT = blizzardTimestampFormat
        end
        SaveBlizzardTimestampSetting(settings, nil)
        blizzardTimestampSetting = nil
        blizzardTimestampFormat = nil
        timestampOverrideActive = false
    end
end

local function IsTemporaryChatFrame(chatFrame)
    if not chatFrame then return false end
    if chatFrame.isTemporary then return true end
    if type(FCF_IsTemporaryWindow) == "function" then
        return FCF_IsTemporaryWindow(chatFrame) and true or false
    end
    return false
end

local function GetTabChatFrame(tab)
    if not tab or not tab.GetID then return nil end
    local tabID = tab:GetID()
    if not tabID then return nil end
    return _G["ChatFrame" .. tabID]
end

local function ApplySurfaceStyle(frame, bgColor, borderColor, borderSizePixels)
    if not frame then return end

    local state = GetSurfaceState(frame)
    if not state.bg then
        state.bg = frame:CreateTexture(nil, "BACKGROUND")
        state.bg:SetAllPoints()
        state.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        if UIKit and UIKit.DisablePixelSnap then
            UIKit.DisablePixelSnap(state.bg)
        end
    end

    state.bg:SetVertexColor(bgColor[1] or 0, bgColor[2] or 0, bgColor[3] or 0, bgColor[4] or 1)

    if UIKit and UIKit.CreateBackdropBorder then
        state.border = UIKit.CreateBackdropBorder(
            frame,
            borderSizePixels or 1,
            borderColor[1] or 0,
            borderColor[2] or 0,
            borderColor[3] or 0,
            borderColor[4] or 1
        )
        state.border:SetFrameLevel(frame:GetFrameLevel() + 1)
    end
end

local function GetChatSurfaceColors(settings)
    settings = settings or GetSettings()

    local glass = settings and settings.glass
    local alpha = glass and glass.bgAlpha
    if alpha == nil then
        -- Fall back to glass.bgColor[4] if present, else a sensible default.
        local legacyBg = glass and glass.bgColor
        alpha = (legacyBg and legacyBg[4]) or 0.25
    end

    -- An explicit per-chat background color (picker writes {r,g,b,a}; factory
    -- default is legacy black {0,0,0}) overrides the skin; otherwise track the
    -- skin theme. The alpha slot lets users explicitly choose black.
    local legacyBg = glass and glass.bgColor
    local userSet = type(legacyBg) == "table"
        and (legacyBg[4] ~= nil or legacyBg[1] ~= 0 or legacyBg[2] ~= 0 or legacyBg[3] ~= 0)
    local bgR, bgG, bgB
    if userSet then
        bgR, bgG, bgB = legacyBg[1], legacyBg[2], legacyBg[3]
    else
        bgR, bgG, bgB = 0, 0, 0
        if Helpers and Helpers.GetSkinBgColorWithOverride then
            bgR, bgG, bgB = Helpers.GetSkinBgColorWithOverride(settings, "chat")
        elseif Helpers and Helpers.GetSkinBgColor then
            bgR, bgG, bgB = Helpers.GetSkinBgColor()
        end
    end

    -- Source border from the skin theme; preserve the 0.55 alpha used for the
    -- chat-frame border accent. Guarded for the same multi-return reason above.
    local brR, brG, brB = 1, 1, 1
    if Helpers and Helpers.GetSkinBorderColor then
        brR, brG, brB = Helpers.GetSkinBorderColor(settings, "chat")
    end

    return {bgR, bgG, bgB, alpha},
           {brR, brG, brB, 0.55}
end

local function EnsureChatTabBorderSettings(settings)
    if type(settings) ~= "table" then return nil end
    if settings.chatTabBorderColorSource == nil then
        -- Preserve the current selected-tab look: chat tabs used the live
        -- accent before the shared Border Coloring row existed.
        settings.chatTabBorderColorSource = "theme"
    end
    if type(settings.chatTabBorderColor) ~= "table" then
        settings.chatTabBorderColor = {0, 0, 0, 1}
    end
    return settings
end

local function GetChatTabBorderColor(settings)
    settings = EnsureChatTabBorderSettings(settings or GetSettings())

    local accent = I.GetAccent and I.GetAccent() or I.QUI_COLORS.accent
    local r, g, b, a = accent[1] or 1, accent[2] or 1, accent[3] or 1, accent[4] or 1
    if Helpers and Helpers.GetSkinBorderColor then
        r, g, b, a = Helpers.GetSkinBorderColor(settings, "chatTab")
    end
    return r, g, b, a
end

local function NormalizeScrollbackLines(settings)
    local lines = tonumber(settings and settings.scrollbackLines) or 0
    if lines <= 0 then return 0 end
    if lines > SCROLLBACK_MAX_LINES then lines = SCROLLBACK_MAX_LINES end
    return math.floor(lines + 0.5)
end

local function ReadCurrentMaxLines(chatFrame)
    if not chatFrame or not chatFrame.GetMaxLines then return nil end
    local ok, value = pcall(chatFrame.GetMaxLines, chatFrame)
    if not ok then return nil end
    if Helpers.IsSecretValue and Helpers.IsSecretValue(value) then return nil end
    return tonumber(value)
end

local function ApplyScrollbackLines(chatFrame, settings)
    if not chatFrame or not chatFrame.SetMaxLines then return end

    settings = settings or GetSettings()
    local state = GetScrollbackState(chatFrame)
    local current = ReadCurrentMaxLines(chatFrame)
    if current and not state.originalLines then
        state.originalLines = current
    end

    local configured = NormalizeScrollbackLines(settings)
    local target = configured
    if configured == 0 then
        target = state.originalLines or 0
    end

    if target <= 0 then
        state.appliedLines = nil
        return
    end

    if state.appliedLines == target or current == target then
        state.appliedLines = target
        return
    end

    local ok = pcall(chatFrame.SetMaxLines, chatFrame, target)
    if ok then
        state.appliedLines = target
    end
end

-- Expose helpers for sibling files. Functions are stored on _internals once their
-- locals are defined; siblings access via ns.QUI.Chat._internals.<name>.
I.GetSettings         = GetSettings
I.IsChatEnabled       = IsChatEnabled
I.IsTemporaryChatFrame= IsTemporaryChatFrame
I.GetTabChatFrame     = GetTabChatFrame
I.ApplySurfaceStyle   = ApplySurfaceStyle
I.GetChatSurfaceColors= GetChatSurfaceColors
I.GetChatTabBorderColor = GetChatTabBorderColor
I.ApplyScrollbackLines= ApplyScrollbackLines

---------------------------------------------------------------------------
-- Timestamp - Prepend time to messages
---------------------------------------------------------------------------
local function IsSecret(value)
    return Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(value)
end

local function WrapChatText(text, prefix, suffix)
    if C_StringUtil and C_StringUtil.WrapString then
        local ok, wrapped = pcall(C_StringUtil.WrapString, text, prefix, suffix)
        if ok and (IsSecret(wrapped) or wrapped ~= nil) then
            return wrapped, true
        end
    end

    if IsSecret(text) then
        return text, false
    end

    return (prefix or "") .. text .. (suffix or ""), true
end

local function AddTimestamp(text)
    local settings = GetSettings()
    if not settings or not settings.timestamps or not settings.timestamps.enabled then
        return text, false
    end
    ApplyTimestampMode(settings)

    if IsSecret(text) then
        local fmt = settings.timestamps.format == "12h" and "%I:%M %p" or "%H:%M"
        local timestamp = date(fmt)
        local color = settings.timestamps.color
        local prefix
        if color then
            local hex = string.format("%02x%02x%02x", color[1]*255, color[2]*255, color[3]*255)
            prefix = string.format("|cff%s[%s]|r ", hex, timestamp)
        else
            prefix = string.format("[%s] ", timestamp)
        end

        return WrapChatText(text, prefix, nil)
    end

    if not text or type(text) ~= "string" then
        return text, false
    end

    local fmt = settings.timestamps.format == "12h" and "%I:%M %p" or "%H:%M"
    local timestamp = date(fmt)
    local color = settings.timestamps.color
    local prefix
    if color then
        local hex = string.format("%02x%02x%02x", color[1]*255, color[2]*255, color[3]*255)
        prefix = string.format("|cff%s[%s]|r ", hex, timestamp)
    else
        prefix = string.format("[%s] ", timestamp)
    end

    return WrapChatText(text, prefix, nil)
end

---------------------------------------------------------------------------
-- URL Detection - Make URLs clickable
---------------------------------------------------------------------------
local function MakeURLsClickable(text)
    local settings = GetSettings()
    if not settings or not settings.urls or not settings.urls.enabled then
        return text, false
    end

    if IsSecret(text) then
        return text, false
    end
    if not text or type(text) ~= "string" then
        return text, false
    end

    -- URL detection inspects message text with Lua patterns, so only run it
    -- after secret payloads have been ruled out.
    local success, result = pcall(function()
        -- Get URL color
        local r, g, b = 0.078, 0.608, 0.992  -- Default blue
        if settings.urls.color then
            r, g, b = settings.urls.color[1] or r, settings.urls.color[2] or g, settings.urls.color[3] or b
        end
        local colorHex = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)

        -- Per-URL replacement so we can consult the Phase D friendly-label
        -- lookup before rendering. Defensive nil checks: hyperlinks.lua
        -- loads later in chat.xml, so during early init the lookup may not
        -- exist yet — fall back to the raw URL as the visible label.
        local function wrap(url)
            local label
            local HL = ns.QUI.Chat and ns.QUI.Chat.Hyperlinks
            if HL and HL.LookupFriendlyLabel then
                label = HL.LookupFriendlyLabel(url)
            end
            return "|cff" .. colorHex
                .. "|Haddon:quaziiuichat:url:" .. url
                .. "|h[" .. (label or url) .. "]|h|r"
        end

        local processed = text
        for _, pattern in ipairs(URL_PATTERNS) do
            local source = processed
            processed = source:gsub("()(" .. pattern .. ")", function(startIndex, url)
                if not IsURLStartBoundary(source, startIndex) then
                    return url
                end
                local cleanURL, suffix = SplitTrailingURLPunctuation(url)
                if cleanURL == "" then
                    return url
                end
                return wrap(cleanURL) .. suffix
            end)
        end
        return processed
    end)

    -- If protected content, return original unmodified text
    if success then
        return result, result ~= text
    else
        return text, false
    end
end

I.MakeURLsClickable = MakeURLsClickable

-- Rendered Message Transforms
-- Normal conversational chat events eventually call Blizzard's
-- ChatHistory_GetAccessID, which lowercases chat-type tokens while building
-- history keys. Running addon string modifiers in the pre-dispatch message
-- filter can taint that path when any chat payload is secret. Apply display
-- transforms only after Blizzard has added the rendered line.
---------------------------------------------------------------------------
local renderedTransformsInstalled = false
local renderedTransformFrames = setmetatable({}, { __mode = "k" })
local renderedTransformState = setmetatable({}, { __mode = "k" })

local RENDERED_DECORATION_EVENTS = {
    CHAT_MSG_SAY = true,
    CHAT_MSG_YELL = true,
    CHAT_MSG_GUILD = true,
    CHAT_MSG_OFFICER = true,
    CHAT_MSG_PARTY = true,
    CHAT_MSG_PARTY_LEADER = true,
    CHAT_MSG_RAID = true,
    CHAT_MSG_RAID_LEADER = true,
    CHAT_MSG_RAID_WARNING = true,
    CHAT_MSG_INSTANCE_CHAT = true,
    CHAT_MSG_INSTANCE_CHAT_LEADER = true,
    CHAT_MSG_BN_INLINE_TOAST_ALERT = true,
    CHAT_MSG_BN_INLINE_TOAST_BROADCAST = true,
    CHAT_MSG_BN_INLINE_TOAST_BROADCAST_INFORM = true,
    CHAT_MSG_CHANNEL = true,
    CHAT_MSG_PING = true,
    CHAT_MSG_EMOTE = true,
    CHAT_MSG_TEXT_EMOTE = true,
    CHAT_MSG_SYSTEM = true,
    CHAT_MSG_MONSTER_SAY = true,
    CHAT_MSG_MONSTER_YELL = true,
    CHAT_MSG_MONSTER_EMOTE = true,
    CHAT_MSG_MONSTER_WHISPER = true,
    CHAT_MSG_MONSTER_PARTY = true,
    CHAT_MSG_LOOT = true,
    CHAT_MSG_MONEY = true,
    CHAT_MSG_COMBAT_XP_GAIN = true,
    CHAT_MSG_COMBAT_HONOR_GAIN = true,
    CHAT_MSG_COMBAT_FACTION_CHANGE = true,
    CHAT_MSG_SKILL = true,
    CHAT_MSG_TRADESKILLS = true,
    CHAT_MSG_OPENING = true,
    CHAT_MSG_ACHIEVEMENT = true,
    CHAT_MSG_GUILD_ACHIEVEMENT = true,
    CHAT_MSG_COMMUNITIES_CHANNEL = true,
}

local function GetRenderedState(frame)
    local state = renderedTransformState[frame]
    if not state then
        state = { lineKeys = {} }
        renderedTransformState[frame] = state
    end
    return state
end

local function ReadPackedArg(eventArgs, index)
    if IsSecret(eventArgs) or type(eventArgs) ~= "table" then return nil end
    local value = eventArgs[index]
    if IsSecret(value) then return nil end
    return value
end

local function NormalizeRenderedEvent(event)
    if IsSecret(event) or type(event) ~= "string" or event == "" then return nil end
    return event
end

local function GetRenderedLineKey(event, eventArgs)
    event = NormalizeRenderedEvent(event)
    if not event then return nil end
    local lineID = ReadPackedArg(eventArgs, 11)
    if lineID == nil then return nil end
    local valueType = type(lineID)
    if valueType ~= "number" and valueType ~= "string" then return nil end
    return event .. ":" .. tostring(lineID)
end

local function HasQUITimestampPrefix(message)
    if IsSecret(message) or type(message) ~= "string" then return false end
    return message:match("^|cff%x%x%x%x%x%x%[%d%d?:%d%d%s?[AP]?[M]?%]|r%s") ~= nil
        or message:match("^%[%d%d?:%d%d%s?[AP]?[M]?%]%s") ~= nil
end

local function ShouldTryURLLinkify(message)
    if IsSecret(message) or type(message) ~= "string" then return false end
    if message:find("addon:quaziiuichat:url:", 1, true) then return false end
    return message:find("://", 1, true) ~= nil
        or message:find("www.", 1, true) ~= nil
        or message:find("discord.", 1, true) ~= nil
end

local function BuildRenderedInfo(event, eventArgs)
    local info = {
        event = NormalizeRenderedEvent(event),
        rendered = true,
        author = ReadPackedArg(eventArgs, 2),
        language = ReadPackedArg(eventArgs, 3),
        flags = ReadPackedArg(eventArgs, 6),
        channelNumber = ReadPackedArg(eventArgs, 7),
        channelName = ReadPackedArg(eventArgs, 9),
        lineID = ReadPackedArg(eventArgs, 11),
        guid = ReadPackedArg(eventArgs, 12),
    }
    return info
end

local function ShouldRunRenderedPipeline(event)
    event = NormalizeRenderedEvent(event)
    if not event then return false end
    local Pipeline = ns.QUI.Chat and ns.QUI.Chat.Pipeline
    return Pipeline
        and Pipeline.ShouldRunForEvent
        and Pipeline.ShouldRunForEvent(event)
        and Pipeline._modifiers
        and #Pipeline._modifiers > 0
end

local function ShouldTransformRenderedMessage(frame, message, r, g, b, infoID, accessID, typeID, event, eventArgs)
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

    local settings = GetSettings()
    if not IsChatEnabled(settings) then return markSeenAndSkip() end

    if I.IsChatMessagingLockedDown and I.IsChatMessagingLockedDown() then
        return markSeenAndSkip()
    end

    local cleanEvent = NormalizeRenderedEvent(event)
    if not cleanEvent then return markSeenAndSkip() end

    local canDecorate = RENDERED_DECORATION_EVENTS[cleanEvent] == true
    if canDecorate then
        if settings.timestamps and settings.timestamps.enabled and not HasQUITimestampPrefix(message) then
            return true
        end
        if settings.urls and settings.urls.enabled and ShouldTryURLLinkify(message) then
            return true
        end
    end

    if ShouldRunRenderedPipeline(cleanEvent) then
        return true
    end

    -- A line with a per-channel color override must be transformed even when it
    -- has no timestamp/URL/pipeline work (this is what pulls whispers in).
    local resolver = ns.QUI.Chat and ns.QUI.Chat._lineColorResolver
    if resolver and resolver(cleanEvent, eventArgs) then
        return true
    end

    return markSeenAndSkip()
end

local function TransformRenderedMessage(frame, message, r, g, b, infoID, accessID, typeID, event, eventArgs, formatter, ...)
    local state = GetRenderedState(frame)
    local lineKey = GetRenderedLineKey(event, eventArgs)
    if lineKey and state.lineKeys[lineKey] then
        return message, r, g, b, infoID, accessID, typeID, event, eventArgs, formatter, ...
    end

    local settings = GetSettings()
    local modified = message
    local cleanEvent = NormalizeRenderedEvent(event)
    local canDecorate = cleanEvent and RENDERED_DECORATION_EVENTS[cleanEvent] == true

    if canDecorate and settings and settings.timestamps and settings.timestamps.enabled and not HasQUITimestampPrefix(modified) then
        local nextMessage, didChange = AddTimestamp(modified)
        if didChange and not IsSecret(nextMessage) then
            modified = nextMessage
        end
    end

    if canDecorate and settings and settings.urls and settings.urls.enabled and ShouldTryURLLinkify(modified) then
        local nextMessage, didChange = MakeURLsClickable(modified)
        if didChange and not IsSecret(nextMessage) then
            modified = nextMessage
        end
    end

    local Pipeline = ns.QUI.Chat and ns.QUI.Chat.Pipeline
    if cleanEvent and ShouldRunRenderedPipeline(cleanEvent) and Pipeline and Pipeline.Run then
        local newMessage = Pipeline.Run(modified, BuildRenderedInfo(cleanEvent, eventArgs), cleanEvent)
        if newMessage ~= nil and not IsSecret(newMessage) and type(newMessage) == "string" then
            modified = newMessage
        end
    end

    -- Per-channel color override: substitute the line's r,g,b (reproduces native
    -- ChatTypeInfo tinting without ever writing that global). See channel_colors.lua.
    local colorResolver = ns.QUI.Chat and ns.QUI.Chat._lineColorResolver
    if colorResolver then
        local cr, cg, cb = colorResolver(cleanEvent, eventArgs)
        if cr ~= nil and not IsSecret(cr) then
            r, g, b = cr, cg, cb
        end
    end

    if lineKey then
        state.lineKeys[lineKey] = true
    end

    return modified, r, g, b, infoID, accessID, typeID, event, eventArgs, formatter, ...
end

local function MarkRenderedLineSeen(frame, event, eventArgs)
    if not frame then return end
    local lineKey = GetRenderedLineKey(event, eventArgs)
    if lineKey then
        GetRenderedState(frame).lineKeys[lineKey] = true
    end
end

local function MarkExistingRenderedLines(frame)
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

local function HookRenderedMessageFrame(frame)
    if not frame or renderedTransformFrames[frame] then return end
    if not frame.TransformMessages then return end
    if not hooksecurefunc then return end

    renderedTransformFrames[frame] = true
    MarkExistingRenderedLines(frame)

    hooksecurefunc(frame, "AddMessage", function(chatFrame, _, _, _, _, _, _, _, event, eventArgs)
        if I.IsChatMessagingLockedDown and I.IsChatMessagingLockedDown() then
            MarkRenderedLineSeen(chatFrame, event, eventArgs)
            return
        end
        if not chatFrame or not chatFrame.TransformMessages then return end
        chatFrame:TransformMessages(
            function(...) return ShouldTransformRenderedMessage(chatFrame, ...) end,
            function(...) return TransformRenderedMessage(chatFrame, ...) end
        )
    end)
end

local function HookAllRenderedMessageFrames()
    local nWindows = _G.NUM_CHAT_WINDOWS or 10
    for i = 1, nWindows do
        HookRenderedMessageFrame(_G["ChatFrame" .. i])
    end
end

local function InstallRenderedMessageTransforms()
    if renderedTransformsInstalled then return end
    renderedTransformsInstalled = true

    HookAllRenderedMessageFrames()

    if hooksecurefunc and _G.FCF_OpenNewWindow then
        hooksecurefunc("FCF_OpenNewWindow", function()
            if C_Timer and C_Timer.After then
                C_Timer.After(0.1, HookAllRenderedMessageFrames)
            else
                HookAllRenderedMessageFrames()
            end
        end)
    end

    if hooksecurefunc and _G.FCF_OpenTemporaryWindow then
        hooksecurefunc("FCF_OpenTemporaryWindow", function()
            if C_Timer and C_Timer.After then
                C_Timer.After(0.1, HookAllRenderedMessageFrames)
            else
                HookAllRenderedMessageFrames()
            end
        end)
    end
end

---------------------------------------------------------------------------
-- Refresh tab colors (used by tab-click hook to update selection state)
---------------------------------------------------------------------------
local function RefreshAllTabColors()
    if ns.QUI.Chat.Skinning and ns.QUI.Chat.Skinning.StyleAllTabs then
        ns.QUI.Chat.Skinning.StyleAllTabs()
        return
    end

    for i = 1, NUM_CHAT_WINDOWS do
        local tab = _G["ChatFrame" .. i .. "Tab"]
        if tab and tabBackdrops[tab] then
            ns.QUI.Chat.Skinning.UpdateTabColors(tab)
        end
    end
end

---------------------------------------------------------------------------
-- Hook new chat window creation
---------------------------------------------------------------------------
local function HookNewChatWindows()
    -- Hook temporary windows (whispers, etc.)
    hooksecurefunc("FCF_OpenTemporaryWindow", function(...)
        C_Timer.After(0.1, function()
            ns.QUI.Chat.Skinning.SkinAll()
            ns.QUI.Chat.Skinning.StyleAllTabs()
        end)
    end)

    -- Hook new permanent windows
    if FCF_OpenNewWindow then
        hooksecurefunc("FCF_OpenNewWindow", function(...)
            C_Timer.After(0.1, function()
                ns.QUI.Chat.Skinning.SkinAll()
                ns.QUI.Chat.Skinning.StyleAllTabs()
            end)
        end)
    end

    -- Blizzard's FCFTab_UpdateColors resets the tab's FontString color and the
    -- glow's vertex color from Blizzard's selectedColorTable on every call —
    -- not just on user clicks but also on dock changes, alert flashes, and
    -- chat type registration. Re-apply our theme-driven colors after each
    -- pass so accent/dim text and the reskinned glow color survive.
    if FCFTab_UpdateColors then
        hooksecurefunc("FCFTab_UpdateColors", function(tab)
            if tab and tabBackdrops[tab] then
                ns.QUI.Chat.Skinning.UpdateTabColors(tab)
            end
        end)
    end

    -- Hook tab clicks to update selection state colors AND editbox backdrop
    hooksecurefunc("FCF_Tab_OnClick", function(self)
        if (type(InCombatLockdown) == "function" and InCombatLockdown())
            or (I.IsChatMessagingLockedDown and I.IsChatMessagingLockedDown()) then
            return
        end

        local tabID = self:GetID()
        C_Timer.After(0.05, function()
            if (type(InCombatLockdown) == "function" and InCombatLockdown())
                or (I.IsChatMessagingLockedDown and I.IsChatMessagingLockedDown()) then
                return
            end

            RefreshAllTabColors()

            local chatFrame = _G["ChatFrame" .. tabID]
            local settings = GetSettings()

            if chatFrame and IsChatEnabled(settings) and settings.editBox and settings.editBox.positionTop then
                -- Use ChatFrame1's backdrop as the SINGLE shared backdrop for top position mode
                -- Parent to UIParent so it stays visible when ChatFrame1 is hidden
                -- (WoW hides ChatFrame1 when other tabs are selected)
                local sharedBackdrop = I.editBoxBackdrops[ChatFrame1]
                if sharedBackdrop then
                    sharedBackdrop:SetParent(UIParent)
                    sharedBackdrop:ClearAllPoints()
                    sharedBackdrop:SetFrameLevel(ChatFrame1:GetFrameLevel() + 10)
                    sharedBackdrop:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", 0, 0)
                    sharedBackdrop:SetPoint("BOTTOMRIGHT", ChatFrame1, "TOPRIGHT", 0, 0)
                    sharedBackdrop:SetHeight(24)
                    ApplySurfaceStyle(sharedBackdrop, {0, 0, 0, 1}, {0, 0, 0, 1}, 1)

                    -- Update editbox state reference (stored in local table, NOT on frame)
                    local ebState = I.editBoxState[ChatFrame1EditBox]
                    if ebState then
                        ebState.backdropRef = sharedBackdrop
                    end

                    -- If editbox has focus, show the backdrop
                    if ebState and ebState.hasFocus then
                        sharedBackdrop:Show()
                    end
                end
            end
        end)
    end)
end

---------------------------------------------------------------------------
-- Refresh all chat styling (called from options)
---------------------------------------------------------------------------
local function RefreshAll()
    local settings = GetSettings()
    local chatEnabled = IsChatEnabled(settings)
    ApplyTimestampMode(settings)

    -- Handle each skinned frame
    for chatFrame in pairs(skinnedFrames) do
        -- Handle glass backdrop
        if not chatEnabled or not settings.glass or not settings.glass.enabled then
            ns.QUI.Chat.Skinning.RemoveBackdrop(chatFrame)
        end

        -- Handle button visibility
        if not chatEnabled or not settings.hideButtons then
            ns.QUI.Chat.Cleanup.ShowButtons(chatFrame)
        else
            ns.QUI.Chat.Cleanup.HideButtons(chatFrame)
        end

        -- Handle editbox styling
        if not chatEnabled or not settings.editBox or not settings.editBox.enabled then
            ns.QUI.Chat.EditBoxBasics.RemoveEditBoxStyle(chatFrame)
        else
            -- Show editbox backdrop if it exists (for bottom position mode)
            -- Top position mode handles visibility via OnShow/OnHide hooks
            if I.editBoxBackdrops[chatFrame] and not settings.editBox.positionTop then
                I.editBoxBackdrops[chatFrame]:Show()
            end
        end

        -- Handle message fade (native API)
        ns.QUI.Chat.Skinning.SetupFade(chatFrame)

        if not chatEnabled and ns.QUI.Chat.Skinning.RemovePadding then
            ns.QUI.Chat.Skinning.RemovePadding(chatFrame)
        end

        -- Handle copy button based on mode
        if not chatEnabled then
            ns.QUI.Chat.Copy.HideButton(chatFrame)
        else
            ns.QUI.Chat.Copy.ApplyButtonMode(chatFrame)
        end
    end

    -- Re-apply all styling if enabled
    if chatEnabled then
        ns.QUI.Chat.Skinning.SkinAll()
        ns.QUI.Chat.Skinning.StyleAllTabs()
    elseif ns.QUI.Chat.Skinning.RemoveAllTabStyles then
        ns.QUI.Chat.Skinning.RemoveAllTabStyles()
    end

    -- Update new message sound registration (works even when chat module disabled)
    ns.QUI.Chat.Sounds.Setup()

    -- Modifier after-refresh hooks (e.g., class_colors, channel_shorten).
    -- Each modifier registers its ApplyEnabled here. pcall isolates failures.
    local hooks = ns.QUI.Chat._afterRefresh
    if hooks then
        for i = 1, #hooks do
            local ok, err = pcall(hooks[i])
            if not ok and geterrorhandler then
                geterrorhandler()(err)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Initialize
---------------------------------------------------------------------------
-- StyleEditBox (editbox_basics.lua) and ApplyMessagePadding (skinning.lua)
-- bail early when InCombatLockdown() or chat messaging lockdown is active.
-- If we /reload mid-combat or mid-key, the editbox strip stays unstyled
-- (no QUI backdrop, focus hooks, or texture stripping) until lockdown ends.
-- Track a pending flag and reapply when both lockdowns clear.
local pendingCombatReskin = false

local function IsAnyChatLayoutLocked()
    return (type(InCombatLockdown) == "function" and InCombatLockdown())
        or (I.IsChatMessagingLockedDown and I.IsChatMessagingLockedDown())
end

local function FlushPendingCombatReskin()
    if not pendingCombatReskin then return end
    if IsAnyChatLayoutLocked() then return end
    pendingCombatReskin = false
    ns.QUI.Chat.Skinning.SkinAll()
    ns.QUI.Chat.Skinning.StyleAllTabs()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("CVAR_UPDATE")
-- One-shot: re-apply the QUI-stored ChatFrame1 size after Edit Mode restores
-- its layout size on login (Edit Mode preset layouts can't persist a custom
-- chat size). Unregistered after the first fire.
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
-- Lockdown-end events. PLAYER_REGEN_ENABLED covers plain combat; the
-- remainder cover chat messaging lockdown sources (M+ keys, encounters,
-- PvP matches) that persist past combat exit.
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
eventFrame:RegisterEvent("CHALLENGE_MODE_RESET")
eventFrame:RegisterEvent("ENCOUNTER_END")
eventFrame:RegisterEvent("PVP_MATCH_COMPLETE")
eventFrame:RegisterEvent("PVP_MATCH_INACTIVE")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        self:UnregisterEvent("ADDON_LOADED")

        -- Only take ChatFrame1 out of Blizzard's Edit Mode when the chat module
        -- is enabled. The detach is a one-way customization step (it reparents
        -- the frame and pulls Edit Mode's resize/select widgets off-screen) with
        -- no reattach path, so doing it while the module is disabled would strand
        -- chat under QUI even though the user asked for Blizzard's default chat.
        -- When disabled we leave ChatFrame1 entirely to Blizzard. The early
        -- detach matters only because QUI's later geometry writes would taint
        -- chat dispatch -- and a disabled module issues no geometry writes, so
        -- skipping it here is taint-safe. SyncToStored re-checks the enabled flag
        -- on PLAYER_ENTERING_WORLD, so an enabled module still detaches even if
        -- the profile DB were somehow not ready at this instant.
        if IsChatEnabled(GetSettings()) then
            local Sizing = ns.QUI and ns.QUI.ChatFrame1Sizing
            if Sizing and Sizing.DetachFromEditMode then
                Sizing.DetachFromEditMode()
            end
        end

        -- Setup new message sound (works independently of chat skinning)
        ns.QUI.Chat.Sounds.Setup()

        -- Always install hooks so the GUI master toggle (chat.enabled)
        -- can flip without requiring a /reload. Each install is idempotent and
        -- the runtime branches that do real work re-check the master toggle, so
        -- registering when the module is currently disabled is inert.
        ns.QUI.Chat.Copy.SetupURLClick()
        InstallRenderedMessageTransforms()

        -- Hook chat frame opening to ensure edit box gets history initialization
        hooksecurefunc("ChatFrame_OpenChat", function(text, chatFrame)
            C_Timer.After(0.1, function()
                ns.QUI.Chat.EditBoxHistory.InitializeForFrame(chatFrame)
            end)
        end)

        -- Hook for new chat windows (handler re-checks the master toggle internally)
        HookNewChatWindows()

        -- Skin existing chat frames + tabs (both gate on the master toggle)
        ns.QUI.Chat.Skinning.SkinAll()
        ns.QUI.Chat.Skinning.StyleAllTabs()
        ApplyTimestampMode()

        -- If we loaded under any chat layout lockdown, the per-frame editbox
        -- styling bailed. Mark for retry on the next lockdown-end event.
        if IsAnyChatLayoutLocked() then
            pendingCombatReskin = true
        end
    elseif event == "PLAYER_LOGIN" or event == "CVAR_UPDATE" then
        ApplyTimestampMode()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Run after this frame's Edit Mode layout restore lands so QUI detaches
        -- ChatFrame1 from Edit Mode and re-asserts its owned position + size
        -- over the active (possibly preset) Edit Mode layout. SyncToStored is a
        -- no-op while chat is disabled and bails (for a lockdown-end retry) if
        -- we entered the world under combat/messaging lockdown.
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        C_Timer.After(0, function()
            local Sizing = ns.QUI and ns.QUI.ChatFrame1Sizing
            if Sizing and Sizing.SyncToStored then
                Sizing.SyncToStored()
            end
        end)
    elseif event == "PLAYER_REGEN_ENABLED"
        or event == "CHALLENGE_MODE_COMPLETED"
        or event == "CHALLENGE_MODE_RESET"
        or event == "ENCOUNTER_END"
        or event == "PVP_MATCH_COMPLETE"
        or event == "PVP_MATCH_INACTIVE" then
        FlushPendingCombatReskin()
        -- Retry the ChatFrame1 detach/geometry sync if the login attempt was
        -- skipped under lockdown. Idempotent once detached.
        local Sizing = ns.QUI and ns.QUI.ChatFrame1Sizing
        if Sizing and Sizing.SyncToStored then
            Sizing.SyncToStored()
        end
    end
end)

---------------------------------------------------------------------------
-- Global refresh function for GUI
---------------------------------------------------------------------------
_G.QUI_RefreshChat = RefreshAll

QUI.Chat.Refresh   = RefreshAll
-- QUI.Chat.SkinFrame / SkinAll aliases are assigned at the bottom of skinning.lua
-- (skinning.lua loads after chat.lua per chat.xml, so Skinning.* is not yet
-- defined here).

if ns.Registry then
    ns.Registry:Register("chat", {
        refresh = function() if _G.QUI_RefreshChat then _G.QUI_RefreshChat() end end,
        priority = 45,
        group = "chat",
        importCategories = { "chat" },
    })
end

if Helpers and Helpers.BorderRegistry then
    Helpers.BorderRegistry.Register({
        key      = "chat",
        label    = "Chat",
        category = "Skinning",
        prefix   = "chat",
        db       = function(p) return p.chat end,
        refresh  = function() if _G.QUI_RefreshChat then _G.QUI_RefreshChat() end end,
        legacy   = {},
    })
    Helpers.BorderRegistry.Register({
        key      = "chatTabs",
        label    = "Chat Tabs",
        category = "Skinning",
        prefix   = "chatTab",
        db       = function(p) return EnsureChatTabBorderSettings(p and p.chat) end,
        refresh  = function() if _G.QUI_RefreshChat then _G.QUI_RefreshChat() end end,
        legacy   = {},
    })
end
