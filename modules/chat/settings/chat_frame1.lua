local ADDON_NAME, ns = ...

local Settings = ns.Settings
local ProviderFeatures = Settings and Settings.ProviderFeatures
if not ProviderFeatures or type(ProviderFeatures.Register) ~= "function" then
    return
end

-- ChatFrame1 size bounds. Lower limits match Blizzard's CHAT_FRAME_MIN_*; upper
-- limits are loose enough to allow large displays without being unbounded.
local CHAT_RESIZE_MIN_W, CHAT_RESIZE_MAX_W = 296, 1400
local CHAT_RESIZE_MIN_H, CHAT_RESIZE_MAX_H = 120, 900

local function ChatGetSize()
    local f = _G.ChatFrame1
    if not f then return CHAT_RESIZE_MIN_W, CHAT_RESIZE_MIN_H end
    return f:GetWidth() or 0, f:GetHeight() or 0
end

local function ChatSetSize(w, h)
    local f = _G.ChatFrame1
    if not f or type(w) ~= "number" or type(h) ~= "number" then return end
    if InCombatLockdown() then return end
    if _G.FCF_SetWindowSize then
        _G.FCF_SetWindowSize(f, w, h)
    else
        f:SetSize(w, h)
    end
    if _G.FCF_SavePositionAndDimensions then
        _G.FCF_SavePositionAndDimensions(f)
    end
    if _G.QUI_RefreshChatSizeSliders then
        _G.QUI_RefreshChatSizeSliders()
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
            widthDescription  = "ChatFrame1 width in pixels. Blizzard persists this across logout.",
            heightDescription = "ChatFrame1 height in pixels. Blizzard persists this across logout.",
        }, sections, relayout)
        relayout()
    end, function(msg) return msg end)
    U._layoutModePositionOnly = prevPosOnly
    if not ok and geterrorhandler then geterrorhandler()(err) end
    return host:GetHeight()
end

local function RegisterChatFeature(id, subPageIndex, chatSections, includeLayoutRenderer)
    ProviderFeatures:Register({
        id = id,
        moverKey = "chatFrame1",
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
    })
end

RegisterChatFeature("chatFrame1", 1, "general", true)
RegisterChatFeature("chatFrame1Filters", 2, "filters")
RegisterChatFeature("chatFrame1ButtonBar", 3, "buttonBar")
RegisterChatFeature("chatFrame1Alerts", 4, "alerts")
RegisterChatFeature("chatFrame1History", 5, "history")
