local ADDON_NAME, ns = ...
local QUI = ns.QUI or {}
ns.QUI = QUI
local Helpers = ns.Helpers
local UIKit = ns.UIKit

ns.QUI.Chat = ns.QUI.Chat or {}
ns.QUI.Chat._internals = ns.QUI.Chat._internals or {}
local I = ns.QUI.Chat._internals

ns.QUI.Chat._afterRefresh = ns.QUI.Chat._afterRefresh or {}

I.QUI_COLORS = I.QUI_COLORS or {
    bg       = {0.067, 0.094, 0.153, 0.97},
    accent   = {0.204, 0.827, 0.600, 1},
    text     = {0.953, 0.957, 0.965, 1},
    textDim  = {0.72,  0.72,  0.76,  1},
}

I.WHISPER_TYPE_KEYS = I.WHISPER_TYPE_KEYS or {
    WHISPER           = true,
    WHISPER_INFORM    = true,
    BN_WHISPER        = true,
    BN_WHISPER_INFORM = true,
}

function I.GetAccent()
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
    I.surfaceState, I.GetSurfaceState = Helpers.CreateStateTable()
end

function I.IsChatMessagingLockedDown()
    return C_ChatInfo
        and C_ChatInfo.InChatMessagingLockdown
        and C_ChatInfo.InChatMessagingLockdown()
        or false
end

local GetSurfaceState = I.GetSurfaceState

local URL_PATTERNS = {
    "%a[%w+.-]+://%S+",
    "www%.[-%w_%%]+%.%a%a+/%S+",
    "www%.[-%w_%%]+%.%a%a+",
    "discord%.gg/%S+",
    "discord%.com/invite/%S+",
    "discordapp%.com/invite/%S+",
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

local GetSettings = Helpers.CreateDBGetter("chat")

local function IsChatEnabled(settings)
    return settings and settings.enabled ~= false
end

local BLIZZARD_TIMESTAMP_SETTING = "showTimestamps"
local BLIZZARD_TIMESTAMP_NONE = "none"

local function GetBlizzardTimestampSetting()
    if Settings and Settings.GetValue then
        local ok, value = ns.SafeCall("chain-next", Settings.GetValue, BLIZZARD_TIMESTAMP_SETTING)
        if ok and value ~= nil then
            return value
        end
    end

    if type(GetCVar) == "function" then
        local ok, value = ns.SafeCall("chain-next", GetCVar, BLIZZARD_TIMESTAMP_SETTING)
        if ok then
            return value
        end
    end
    return nil
end

local function SetBlizzardTimestampSetting(value)
    if value == nil then return false end

    if Settings and Settings.SetValue then
        local ok = ns.SafeCall("chain-next", Settings.SetValue, BLIZZARD_TIMESTAMP_SETTING, value)
        if ok then
            return true
        end
    end

    if C_CVar and C_CVar.SetCVar then
        local ok = ns.SafeCall("chain-next", C_CVar.SetCVar, BLIZZARD_TIMESTAMP_SETTING, tostring(value))
        if ok then
            return true
        end
    end

    if type(SetCVar) == "function" then
        local ok = ns.SafeCall("chain-next", SetCVar, BLIZZARD_TIMESTAMP_SETTING, value)
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
        local legacyBg = glass and glass.bgColor
        alpha = (legacyBg and legacyBg[4]) or 0.25
    end

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

    local brR, brG, brB = 1, 1, 1
    if Helpers and Helpers.GetSkinBorderColor then
        brR, brG, brB = Helpers.GetSkinBorderColor(settings, "chat")
    end

    return {bgR, bgG, bgB, backgroundEnabled and alpha or 0},
           {brR, brG, brB, 0.55}
end

I.GetSettings         = GetSettings
I.IsChatEnabled       = IsChatEnabled
I.IsTemporaryChatFrame= IsTemporaryChatFrame
I.GetTabChatFrame     = GetTabChatFrame
I.ApplySurfaceStyle   = ApplySurfaceStyle
I.GetChatSurfaceColors= GetChatSurfaceColors

function I.NotifyChatSettingsChanged()
    local RA = ns.Settings and ns.Settings.RenderAdapters
    if RA and type(RA.NotifyProviderChanged) == "function" then
        RA.NotifyProviderChanged("chatFrame1", { structural = true })
    end
end

local function IsSecret(value)
    return Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(value)
end

local function WrapChatText(text, prefix, suffix)
    if C_StringUtil and C_StringUtil.WrapString then
        local ok, wrapped = ns.SafeCall("chain-next", C_StringUtil.WrapString, text, prefix, suffix)
        if ok then
            return wrapped, true
        end
    end

    if IsSecret(text) then
        return text, false
    end

    return (prefix or "") .. text .. (suffix or ""), true
end

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

    local success, result = ns.SafeCall("report", function()
        local r, g, b = 0.078, 0.608, 0.992
        if settings.urls.color then
            r, g, b = settings.urls.color[1] or r, settings.urls.color[2] or g, settings.urls.color[3] or b
        end
        local colorHex = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)

        local function wrap(url)
            local label
            local HL = ns.QUI.Chat and ns.QUI.Chat.Hyperlinks
            if HL and HL.LookupFriendlyLabel then
                label = HL.LookupFriendlyLabel(url)
            end
            return "|cff" .. colorHex
                .. "|Haddon:quichat:url:" .. url
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

    if success then
        return result, result ~= text
    else
        return text, false
    end
end

I.AddTimestamp     = AddTimestamp
I.MakeURLsClickable = MakeURLsClickable
local function RefreshAll()
    local settings = GetSettings()
    ApplyTimestampMode(settings)

    ns.QUI.Chat.Sounds.Setup()

    local hooks = ns.QUI.Chat._afterRefresh
    if hooks then
        for i = 1, #hooks do
            ns.SafeCall("bulkhead", hooks[i])
        end
    end

    if ns.QUI.Chat.DisplayFallback then
        ns.QUI.Chat.DisplayFallback.Apply()
    end
end

local pendingCombatReskin = false

local function IsAnyChatLayoutLocked()
    return (type(InCombatLockdown) == "function" and InCombatLockdown())
        or (I.IsChatMessagingLockedDown and I.IsChatMessagingLockedDown())
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("CVAR_UPDATE")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        self:UnregisterEvent("ADDON_LOADED")

        ns.QUI.Chat.Sounds.Setup()

        ns.QUI.Chat.Copy.SetupURLClick()

        hooksecurefunc("ChatFrame_OpenChat", function(_, chatFrame)
            C_Timer.After(0.1, function()
                ns.QUI.Chat.EditBoxHistory.InitializeForFrame(chatFrame)
            end)
        end)

        ApplyTimestampMode()

        if ns.QUI.Chat.DisplayFallback then
            ns.QUI.Chat.DisplayFallback.Apply()
        end

        if IsAnyChatLayoutLocked() then
            pendingCombatReskin = true
        end
    elseif event == "PLAYER_LOGIN" or event == "CVAR_UPDATE" then
        ApplyTimestampMode()
        if event == "PLAYER_LOGIN" then
            if ns.QUI.Chat.DisplayFallback then
                ns.QUI.Chat.DisplayFallback.Apply()
            end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingCombatReskin and not IsAnyChatLayoutLocked() then
            pendingCombatReskin = false
            RefreshAll()
        end
    end
end)

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
        label    = ns.L["Chat"],
        category = "Skinning",
        prefix   = "chat",
        db       = function(p) return p.chat end,
        refresh  = function() if _G.QUI_RefreshChat then _G.QUI_RefreshChat() end end,
        legacy   = {},
    })
end
