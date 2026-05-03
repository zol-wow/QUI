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

local skinnedFrames   = I.skinnedFrames
local tabBackdrops    = I.tabBackdrops
local GetSurfaceState = I.GetSurfaceState
local GetScrollbackState = I.GetScrollbackState

-- URL detection patterns (standard protocol and www formats)
local URL_PATTERNS = {
    "%f[%S](%a[%w+.-]+://%S+)",             -- protocol://path
    "%f[%S](www%.[-%w_%%]+%.%a%a+/%S+)",    -- www.domain.tld/path
    "%f[%S](www%.[-%w_%%]+%.%a%a+)",        -- www.domain.tld
}

---------------------------------------------------------------------------
-- Get settings from database
---------------------------------------------------------------------------
local GetSettings = Helpers.CreateDBGetter("chat")

local SCROLLBACK_MAX_LINES = 5000
local blizzardTimestampFormat
local timestampOverrideActive = false

local function GetBlizzardTimestampCVar()
    if type(GetCVar) == "function" then
        return GetCVar("showTimestamps")
    end
    return nil
end

local function IsBlizzardTimestampCVarOff()
    local value = GetBlizzardTimestampCVar()
    return value == nil or value == "" or value == "none" or value == "0"
end

local function GetBlizzardTimestampFormat()
    if _G.CHAT_TIMESTAMP_FORMAT ~= nil then
        return _G.CHAT_TIMESTAMP_FORMAT
    end

    local value = GetBlizzardTimestampCVar()
    if not IsBlizzardTimestampCVarOff() and type(value) == "string" and value:find("%%", 1, true) then
        return value
    end
    return nil
end

local function ShouldUseQUITimestamps(settings)
    return settings
        and settings.enabled
        and settings.timestamps
        and settings.timestamps.enabled
end

local function ApplyTimestampMode(settings)
    settings = settings or GetSettings()

    if ShouldUseQUITimestamps(settings) then
        local nativeFormat = GetBlizzardTimestampFormat()
        if not timestampOverrideActive then
            blizzardTimestampFormat = nativeFormat
            timestampOverrideActive = true
        elseif nativeFormat ~= nil or IsBlizzardTimestampCVarOff() then
            blizzardTimestampFormat = nativeFormat
        end
        _G.CHAT_TIMESTAMP_FORMAT = nil
        return
    end

    if timestampOverrideActive then
        if _G.CHAT_TIMESTAMP_FORMAT == nil then
            _G.CHAT_TIMESTAMP_FORMAT = blizzardTimestampFormat
        end
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
    local bg = (glass and glass.bgColor) or {0, 0, 0}
    local alpha = glass and glass.bgAlpha
    if alpha == nil then
        alpha = bg[4] or 0.25
    end

    local accent = I.GetAccent and I.GetAccent() or I.QUI_COLORS.accent
    return {bg[1] or 0, bg[2] or 0, bg[3] or 0, alpha},
           {accent[1] or 1, accent[2] or 1, accent[3] or 1, 0.55}
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
I.IsTemporaryChatFrame= IsTemporaryChatFrame
I.GetTabChatFrame     = GetTabChatFrame
I.ApplySurfaceStyle   = ApplySurfaceStyle
I.GetChatSurfaceColors= GetChatSurfaceColors
I.ApplyScrollbackLines= ApplyScrollbackLines

---------------------------------------------------------------------------
-- Timestamp - Prepend time to messages
---------------------------------------------------------------------------
local function IsSecret(value)
    return Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(value)
end

local function HasSecretValue(...)
    return Helpers and Helpers.HasSecretValue and Helpers.HasSecretValue(...)
end

local function WrapChatText(text, prefix, suffix)
    if C_StringUtil and C_StringUtil.WrapString then
        local wrapped = C_StringUtil.WrapString(text, prefix, suffix)
        if wrapped ~= nil then
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

    if not text or type(text) ~= "string" or IsSecret(text) then
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
            processed = processed:gsub(pattern, wrap)
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

---------------------------------------------------------------------------
-- Chat Message Filters (safe alternative to AddMessage replacement)
-- Prefer ChatFrameUtil's secure registry on current clients; it wraps addon
-- callbacks so inaccessible secret chat args skip the filter without tainting
-- the rest of Blizzard's chat handler.
---------------------------------------------------------------------------
local messageFiltersInstalled = false

local function AddMessageEventFilter(event, filter)
    if ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
        ChatFrameUtil.AddMessageEventFilter(event, filter)
    elseif ChatFrame_AddMessageEventFilter then
        ChatFrame_AddMessageEventFilter(event, filter)
    end
end

local function InstallMessageFilters()
    if messageFiltersInstalled then return end
    messageFiltersInstalled = true

    local whisperEvents = {
        CHAT_MSG_WHISPER = true,
        CHAT_MSG_WHISPER_INFORM = true,
        CHAT_MSG_BN_WHISPER = true,
        CHAT_MSG_BN_WHISPER_INFORM = true,
    }

    -- Build a filter function that processes timestamps and URLs
    local function MessageFilter(self, event, msg, ...)
        -- IsSecret first: type(msg) on a secret string taints the
        -- dispatch chain and propagates into Blizzard's downstream
        -- string conversion of secret senders (HistoryKeeper:35,
        -- ChatFrameOverrides:542). Returning nil on secret is also
        -- functionally equivalent to letting it through — AddTimestamp's
        -- WrapString output is still secret-tagged, the IsSecret(modified)
        -- check below would discard it, and AddTimestamp itself contains
        -- another type(text) compare that would taint anyway.
        if IsSecret(msg) or not msg or type(msg) ~= "string" then
            return nil
        end

        -- Whisper history is now protected more aggressively in 12.x and
        -- rewriting those payloads can taint Blizzard's chat bookkeeping.
        if whisperEvents[event] then
            return nil
        end

        local settings = GetSettings()
        if not settings or not settings.enabled then return nil end

        local modified = msg
        local changed = false
        local success = pcall(function()
            -- Apply timestamps
            if settings.timestamps and settings.timestamps.enabled then
                local nextMessage, didChange = AddTimestamp(modified)
                modified = nextMessage
                changed = changed or didChange
            end

            -- Apply URL detection. msg is non-secret by construction
            -- (gated above), so no per-call IsSecret check needed here.
            if settings.urls and settings.urls.enabled then
                local nextMessage, didChange = MakeURLsClickable(modified)
                modified = nextMessage
                changed = changed or didChange
            end
        end)

        if not success or not changed or IsSecret(modified) then
            return nil
        end

        if HasSecretValue(...) then
            return nil
        end
        return false, modified, ...
    end

    -- Register filter for all standard chat events
    local chatEvents = {
        "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
        "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
        "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
        "CHAT_MSG_BN_INLINE_TOAST_ALERT",
        "CHAT_MSG_CHANNEL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
        "CHAT_MSG_SYSTEM", "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL",
        "CHAT_MSG_MONSTER_EMOTE", "CHAT_MSG_MONSTER_WHISPER", "CHAT_MSG_MONSTER_PARTY",
        "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "CHAT_MSG_COMBAT_XP_GAIN",
        "CHAT_MSG_COMBAT_HONOR_GAIN", "CHAT_MSG_COMBAT_FACTION_CHANGE",
        "CHAT_MSG_SKILL", "CHAT_MSG_TRADESKILLS", "CHAT_MSG_OPENING",
        "CHAT_MSG_ACHIEVEMENT", "CHAT_MSG_GUILD_ACHIEVEMENT",
        "CHAT_MSG_COMMUNITIES_CHANNEL",
    }

    for _, event in ipairs(chatEvents) do
        AddMessageEventFilter(event, MessageFilter)
    end
end

---------------------------------------------------------------------------
-- Refresh tab colors (used by tab-click hook to update selection state)
---------------------------------------------------------------------------
local function RefreshAllTabColors()
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
        local tabID = self:GetID()
        C_Timer.After(0.05, function()
            RefreshAllTabColors()

            local chatFrame = _G["ChatFrame" .. tabID]
            local settings = GetSettings()

            if chatFrame and settings and settings.editBox and settings.editBox.positionTop then
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
                    if ChatFrame1EditBox:HasFocus() then
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
    ApplyTimestampMode(settings)

    -- Handle each skinned frame
    for chatFrame in pairs(skinnedFrames) do
        -- Handle glass backdrop
        if not settings or not settings.enabled or not settings.glass or not settings.glass.enabled then
            ns.QUI.Chat.Skinning.RemoveBackdrop(chatFrame)
        end

        -- Handle button visibility
        if not settings or not settings.enabled or not settings.hideButtons then
            ns.QUI.Chat.Cleanup.ShowButtons(chatFrame)
        else
            ns.QUI.Chat.Cleanup.HideButtons(chatFrame)
        end

        -- Handle editbox styling
        if not settings or not settings.enabled or not settings.editBox or not settings.editBox.enabled then
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

        -- Handle copy button based on mode
        if not settings or not settings.enabled then
            ns.QUI.Chat.Copy.HideButton(chatFrame)
        else
            ns.QUI.Chat.Copy.ApplyButtonMode(chatFrame)
        end
    end

    -- Re-apply all styling if enabled
    if settings and settings.enabled then
        ns.QUI.Chat.Skinning.SkinAll()
        ns.QUI.Chat.Skinning.StyleAllTabs()
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
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("CVAR_UPDATE")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        self:UnregisterEvent("ADDON_LOADED")

        -- Setup new message sound (works independently of chat skinning)
        ns.QUI.Chat.Sounds.Setup()

        -- Always install hooks/filters so the GUI master toggle (chat.enabled)
        -- can flip without requiring a /reload. Each install is idempotent and
        -- the runtime branches that do real work re-check settings.enabled, so
        -- registering when the module is currently disabled is inert.
        ns.QUI.Chat.Copy.SetupURLClick()
        InstallMessageFilters()

        -- Hook chat frame opening to ensure edit box gets history initialization
        hooksecurefunc("ChatFrame_OpenChat", function(text, chatFrame)
            C_Timer.After(0.1, function()
                ns.QUI.Chat.EditBoxHistory.InitializeForFrame(chatFrame)
            end)
        end)

        -- Hook for new chat windows (handler re-checks settings.enabled internally)
        HookNewChatWindows()

        -- Skin existing chat frames + tabs (both gate on settings.enabled)
        ns.QUI.Chat.Skinning.SkinAll()
        ns.QUI.Chat.Skinning.StyleAllTabs()
        ApplyTimestampMode()
    elseif event == "PLAYER_LOGIN" or event == "CVAR_UPDATE" then
        ApplyTimestampMode()
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
