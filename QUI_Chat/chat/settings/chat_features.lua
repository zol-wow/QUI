---------------------------------------------------------------------------
-- QUI Chat — Options feature-page registration (load-on-demand)
-- Registers the five chat feature pages (general, Filters, Button Bar,
-- Alerts, History) with the settings ProviderFeatures registry, wiring the
-- chat_tooltips tile's subpages to the chatFrame1 provider sections.
--
-- Layout rendering targets the QUI chat display (QUI_CustomChatFrame):
-- under the takeover ChatFrame1 is suppressed and never sized/positioned;
-- the position collapsible rides the anchoring key "chatFrame1", which
-- resolves to the QUI display.
---------------------------------------------------------------------------

local _, ns = ...

local Settings = ns.Settings
local ProviderFeatures = Settings and Settings.ProviderFeatures
if not ProviderFeatures or type(ProviderFeatures.Register) ~= "function" then
    return
end

-- Size bounds for the QUI display. Lower limits match display_layer's
-- SetResizeBounds (MIN_W/MIN_H = 220/100); upper limits are loose enough
-- for large displays without being unbounded.
local CHAT_RESIZE_MIN_W, CHAT_RESIZE_MAX_W = 220, 1400
local CHAT_RESIZE_MIN_H, CHAT_RESIZE_MAX_H = 100, 900

local function IsSecret(v)
    local Helpers = ns.Helpers
    return Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(v)
end

local function SafeNumber(value, fallback)
    if IsSecret(value) or type(value) ~= "number" then return fallback end
    return value
end

local function GetDisplayContainer()
    local Display = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.DisplayLayer
    local container = Display and Display.GetContainer and Display.GetContainer()
    return container or _G.QUI_CustomChatFrame
end

local function ChatGetSize()
    local f = GetDisplayContainer()
    if not f then return CHAT_RESIZE_MIN_W, CHAT_RESIZE_MIN_H end
    return math.floor(SafeNumber(f:GetWidth(), CHAT_RESIZE_MIN_W) + 0.5),
        math.floor(SafeNumber(f:GetHeight(), CHAT_RESIZE_MIN_H) + 0.5)
end

local function ChatSetSize(w, h)
    local f = GetDisplayContainer()
    if not f or type(w) ~= "number" or type(h) ~= "number" then return end
    f:SetSize(w, h)
    local Display = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.DisplayLayer
    if Display and Display.PersistGeometry then
        Display.PersistGeometry()
    end
    -- Anchored window: keep the anchor point pinned — grow away from it,
    -- not from center (display_layer's Refresh skips position re-apply
    -- while Layout Mode is live, so this is the in-drawer path).
    if _G.QUI_ReassertAnchorAfterResize then
        _G.QUI_ReassertAnchorAfterResize("chatFrame1")
    end
    if Display and Display.Refresh then
        Display.Refresh()
    end
end

local function ApplyChat()
    if _G.QUI_RefreshChat then
        _G.QUI_RefreshChat()
    end
end

local function RenderChatLayout(host, options)
    local providerKey = (options and options.providerKey) or "chatFrame1"
    local U = ns.QUI_LayoutMode_Utils
    local Settings2 = ns.Settings
    local RenderAdapters = Settings2 and Settings2.RenderAdapters
    if not host or not U
        or type(U.BuildPositionCollapsible) ~= "function"
        or type(U.BuildSizeCollapsible) ~= "function"
        or type(U.StandardRelayout) ~= "function" then
        if RenderAdapters and type(RenderAdapters.RenderPositionOnly) == "function" then
            return RenderAdapters.RenderPositionOnly(host, providerKey)
        end
        return 80
    end

    local prevPosOnly = U._layoutModePositionOnly
    U._layoutModePositionOnly = false
    local sections = {}
    local function relayout() U.StandardRelayout(host, sections) end
    local ok, err = xpcall(function()
        U.BuildPositionCollapsible(host, providerKey, nil, sections, relayout)
        U.BuildSizeCollapsible(host, {
            getSize = ChatGetSize,
            setSize = ChatSetSize,
            minW = CHAT_RESIZE_MIN_W, maxW = CHAT_RESIZE_MAX_W,
            minH = CHAT_RESIZE_MIN_H, maxH = CHAT_RESIZE_MAX_H,
            widthDescription  = ns.L["QUI chat display width in pixels."],
            heightDescription = ns.L["QUI chat display height in pixels."],
        }, sections, relayout)
        relayout()
    end, function(msg) return msg end)
    U._layoutModePositionOnly = prevPosOnly
    if not ok and geterrorhandler then geterrorhandler()(err) end
    return host:GetHeight()
end

local function RegisterChatFeature(id, subPageIndex, chatSections, includeLayoutRenderer)
    local feature = {
        id = id,
        moverKey = "chatFrame1",
        lookupKeys = { id },
        category = "chat",
        nav = {
            tileId = "chat_tooltips",
            subPageIndex = subPageIndex,
        },
        getDB = function(profile)
            return profile and profile.chat
        end,
        apply = ApplyChat,
        providerKey = "chatFrame1",
        providerOptions = {
            chatSections = chatSections,
        },
        render = includeLayoutRenderer and {
            layout = RenderChatLayout,
        } or nil,
    }

    if includeLayoutRenderer then
        feature.layoutPositionOnly = false
    end

    ProviderFeatures:Register(feature)
end

RegisterChatFeature("chatFrame1", 1, "general", true)
RegisterChatFeature("chatFrame1Filters", 2, "filters")
RegisterChatFeature("chatFrame1ButtonBar", 3, "buttonBar")
RegisterChatFeature("chatFrame1Alerts", 4, "alerts")
RegisterChatFeature("chatFrame1History", 5, "history")
