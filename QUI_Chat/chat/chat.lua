---------------------------------------------------------------------------
-- QUI Chat Module
-- Core internals for the chat takeover: settings access, timestamps, URL
-- detection, refresh orchestration. The QUI display owns all rendering.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local QUI = ns.QUI or {}
ns.QUI = QUI
local Helpers = ns.Helpers
local UIKit = ns.UIKit

---------------------------------------------------------------------------
-- Local references
---------------------------------------------------------------------------

-- Weak-keyed tables to store per-frame state WITHOUT writing properties to Blizzard frames
-- (avoids taint from `chatFrame.__quiXxx = value` writes). Surfaced on
-- ns.QUI.Chat._internals so sibling files (copy.lua, editbox_basics.lua,
-- editbox_history.lua) can share the same instances.
ns.QUI.Chat = ns.QUI.Chat or {}
ns.QUI.Chat._internals = ns.QUI.Chat._internals or {}
local I = ns.QUI.Chat._internals

-- Modifier files append callbacks here. RefreshAll runs them at end.
ns.QUI.Chat._afterRefresh = ns.QUI.Chat._afterRefresh or {}

-- Shared color palette. Single source of truth for the chat module —
-- copy.lua's popup styling and the custom display's chrome read from here.
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

-- Whisper-family chatTypeKeys. Shared by the history storeWhispers gate and
-- the message-capture whisper-popout routing so a new whisper type only has to
-- be added here. Keyed by chatTypeKey for O(1) membership tests.
I.WHISPER_TYPE_KEYS = I.WHISPER_TYPE_KEYS or {
    WHISPER           = true,
    WHISPER_INFORM    = true,
    BN_WHISPER        = true,
    BN_WHISPER_INFORM = true,
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

I.editBoxBackdrops    = I.editBoxBackdrops    or Helpers.CreateStateTable()
I.editBoxState        = I.editBoxState        or Helpers.CreateStateTable()
if not I.surfaceState then
    I.surfaceState, I.GetSurfaceState = Helpers.CreateStateTable() -- backdrop/popup frame -> { bg, border }
end

function I.IsChatMessagingLockedDown()
    return C_ChatInfo
        and C_ChatInfo.InChatMessagingLockdown
        and C_ChatInfo.InChatMessagingLockdown()
        or false
end

local GetSurfaceState = I.GetSurfaceState

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

local BLIZZARD_TIMESTAMP_SETTING = "showTimestamps"
local BLIZZARD_TIMESTAMP_NONE = "none"

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

-- Legacy CVar healing ONLY. Older builds forced the Blizzard timestamp CVar
-- to "none" while QUI timestamps were enabled (avoiding double stamps on the
-- rendered Blizzard frames) and saved the user's original value in the
-- profile. The takeover never renders through Blizzard frames, so the
-- override is gone — but a profile still carrying a saved value must get its
-- CVar restored, once. Idempotent; clears the saved key after healing.
local function ApplyTimestampMode(settings)
    settings = settings or GetSettings()
    local saved = GetSavedBlizzardTimestampSetting(settings)
    if saved ~= nil then
        if IsBlizzardTimestampCVarOff() then
            SetBlizzardTimestampSetting(saved)
        end
        SaveBlizzardTimestampSetting(settings, nil)
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
    local backgroundEnabled = not glass or glass.enabled ~= false
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

    return {bgR, bgG, bgB, backgroundEnabled and alpha or 0},
           {brR, brG, brB, 0.55}
end

-- Expose helpers for sibling files. Functions are stored on _internals once their
-- locals are defined; siblings access via ns.QUI.Chat._internals.<name>.
I.GetSettings         = GetSettings
I.IsChatEnabled       = IsChatEnabled
I.IsTemporaryChatFrame= IsTemporaryChatFrame
I.GetTabChatFrame     = GetTabChatFrame
I.ApplySurfaceStyle   = ApplySurfaceStyle
I.GetChatSurfaceColors= GetChatSurfaceColors

-- In-game structural mutations of chat settings data (window add/delete via
-- the tab context menu, tab moves/reorders) must bump the chat settings
-- provider revision: options surfaces only rebuild-on-show when the revision
-- changed, so without this an open or cached panel keeps listing windows and
-- tabs that no longer exist.
function I.NotifyChatSettingsChanged()
    local RA = ns.Settings and ns.Settings.RenderAdapters
    if RA and type(RA.NotifyProviderChanged) == "function" then
        RA.NotifyProviderChanged("chatFrame1", { structural = true })
    end
end

---------------------------------------------------------------------------
-- Timestamp - Prepend time to messages
---------------------------------------------------------------------------
local function IsSecret(value)
    return Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(value)
end

local function WrapChatText(text, prefix, suffix)
    if C_StringUtil and C_StringUtil.WrapString then
        local ok, wrapped = pcall(C_StringUtil.WrapString, text, prefix, suffix)
        if ok then
            return wrapped, true
        end
    end

    if IsSecret(text) then
        return text, false
    end

    return (prefix or "") .. text .. (suffix or ""), true
end

-- Build the "[HH:MM] " timestamp prefix (optionally color-wrapped) from the
-- current timestamp settings. Identical for the secret and non-secret paths.
local function BuildTimestampPrefix(settings)
    local fmt = settings.timestamps.format == "12h" and "%I:%M %p" or "%H:%M"
    local timestamp = date(fmt)
    local color = settings.timestamps.color
    if color then
        local hex = string.format("%02x%02x%02x", color[1]*255, color[2]*255, color[3]*255)
        return string.format("|cff%s[%s]|r ", hex, timestamp)
    end
    return string.format("[%s] ", timestamp)
end

local function AddTimestamp(text)
    local settings = GetSettings()
    if not settings or not settings.timestamps or not settings.timestamps.enabled then
        return text, false
    end

    if IsSecret(text) then
        return WrapChatText(text, BuildTimestampPrefix(settings), nil)
    end

    if not text or type(text) ~= "string" then
        return text, false
    end

    return WrapChatText(text, BuildTimestampPrefix(settings), nil)
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

-- Exposed for the custom display's capture path (message_capture.lua):
-- both are pure text decorators that self-gate on settings.
I.AddTimestamp     = AddTimestamp
I.MakeURLsClickable = MakeURLsClickable
---------------------------------------------------------------------------
-- Refresh all chat styling (called from options)
---------------------------------------------------------------------------
local function RefreshAll()
    local settings = GetSettings()
    ApplyTimestampMode(settings)

    -- Update new message sound registration.
    ns.QUI.Chat.Sounds.Setup()

    -- Modifier after-refresh hooks. Each modifier registers its ApplyEnabled here.
    -- pcall isolates failures.
    local hooks = ns.QUI.Chat._afterRefresh
    if hooks then
        for i = 1, #hooks do
            local ok, err = pcall(hooks[i])
            if not ok and geterrorhandler then
                geterrorhandler()(err)
            end
        end
    end

    -- Re-apply the chat takeover (handles enable/disable flips + setting
    -- changes from options / profile import without a /reload). Cheap when
    -- the state hasn't changed (full rebuild only on transitions).
    if ns.QUI.Chat.DisplayFallback then
        ns.QUI.Chat.DisplayFallback.Apply()
    end
end

---------------------------------------------------------------------------
-- Initialize
---------------------------------------------------------------------------
-- editbox_basics.lua bails early when InCombatLockdown() or chat messaging
-- lockdown is active. If we /reload mid-combat or mid-key, the editbox strip
-- stays unstyled until lockdown ends. Track a pending flag and reapply when
-- both lockdowns clear.
local pendingCombatReskin = false

local function IsAnyChatLayoutLocked()
    return (type(InCombatLockdown) == "function" and InCombatLockdown())
        or (I.IsChatMessagingLockedDown and I.IsChatMessagingLockedDown())
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("CVAR_UPDATE")
-- Lockdown-end event: retry editbox styling deferred during mid-combat /reload.
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        self:UnregisterEvent("ADDON_LOADED")

        -- Setup new message sound.
        ns.QUI.Chat.Sounds.Setup()

        -- Always install hooks so the GUI master toggle (chat.enabled)
        -- can flip without requiring a /reload. Each install is idempotent and
        -- the runtime branches that do real work re-check the master toggle, so
        -- registering when the module is currently disabled is inert.
        ns.QUI.Chat.Copy.SetupURLClick()

        -- Hook chat frame opening to ensure edit box gets history initialization
        hooksecurefunc("ChatFrame_OpenChat", function(_, chatFrame)
            C_Timer.After(0.1, function()
                ns.QUI.Chat.EditBoxHistory.InitializeForFrame(chatFrame)
            end)
        end)

        ApplyTimestampMode()

        -- Start the custom display from the addon-load safe window: capture
        -- now catches the login burst (MOTD, system welcome). AceDB is
        -- initialized before ADDON_LOADED. Idempotent — the PLAYER_LOGIN
        -- re-apply stays as a safety net.
        if ns.QUI.Chat.DisplayFallback then
            ns.QUI.Chat.DisplayFallback.Apply()
        end

        -- If we loaded under any chat layout lockdown, the per-frame editbox
        -- styling bailed. Mark for retry on the next lockdown-end event.
        if IsAnyChatLayoutLocked() then
            pendingCombatReskin = true
        end
    elseif event == "PLAYER_LOGIN" or event == "CVAR_UPDATE" then
        ApplyTimestampMode()
        if event == "PLAYER_LOGIN" then
            -- Chat takeover: start capture + show the QUI display when enabled.
            -- Idempotent; profile/options changes re-apply via RefreshAll.
            if ns.QUI.Chat.DisplayFallback then
                ns.QUI.Chat.DisplayFallback.Apply()
            end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingCombatReskin and not IsAnyChatLayoutLocked() then
            pendingCombatReskin = false
            -- editbox_basics.lua re-styles on its own next StyleEditBox call;
            -- a RefreshAll ensures it runs.
            RefreshAll()
        end
    end
end)

---------------------------------------------------------------------------
-- Global refresh function for GUI
---------------------------------------------------------------------------
_G.QUI_RefreshChat = RefreshAll

QUI.Chat.Refresh   = RefreshAll

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
end
