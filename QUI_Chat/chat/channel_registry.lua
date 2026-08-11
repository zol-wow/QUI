local _, ns = ...

assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: channel_registry.lua loaded before chat.lua. Check chat.xml — chat.lua must precede channel_registry.lua.")

ns.QUI.Chat.ChannelRegistry = ns.QUI.Chat.ChannelRegistry or {}
local Registry = ns.QUI.Chat.ChannelRegistry

local channelMap = {}
local defaultUpper = {}
local populated = false

local function ResolveCommunityName(identifier)
    local util = _G.ChatFrameUtil
    if util and util.ResolveChannelName then
        local ok, resolved = pcall(util.ResolveChannelName, identifier)
        if ok and type(resolved) == "string" and resolved ~= "" then
            return resolved
        end
    end
    return identifier
end

local function IsCommunityIdentifier(name)
    return type(name) == "string" and name:sub(1, 10) == "Community:"
end

function Registry.Refresh()
    if type(_G.GetNumDisplayChannels) ~= "function"
        or type(_G.GetChannelDisplayInfo) ~= "function" then
        return
    end
    populated = true
    for k in pairs(channelMap) do channelMap[k] = nil end
    for k in pairs(defaultUpper) do defaultUpper[k] = nil end

    for i = 1, _G.GetNumDisplayChannels() or 0 do
        local name, isHeader, _, channelNumber, _, _, category = _G.GetChannelDisplayInfo(i)
        if not isHeader and type(name) == "string" and name ~= "" then
            local display = IsCommunityIdentifier(name) and ResolveCommunityName(name) or name
            if type(channelNumber) == "number" and channelNumber > 0 then
                channelMap[channelNumber] = display
            end
            if category ~= "CHANNEL_CATEGORY_CUSTOM" then
                defaultUpper[display:upper()] = true
            end
        end
    end

    if type(_G.GetChannelList) == "function" then
        local list = { _G.GetChannelList() }
        for i = 1, #list, 3 do
            local index, name = list[i], list[i + 1]
            if type(index) == "number" and type(name) == "string" and name ~= ""
                and channelMap[index] == nil then
                if IsCommunityIdentifier(name) then
                    local display = ResolveCommunityName(name)
                    channelMap[index] = display
                    defaultUpper[display:upper()] = true
                else
                    channelMap[index] = name
                end
            end
        end
    end
end

local function EnsurePopulated()
    if not populated then
        Registry.Refresh()
    end
end

function Registry.ResolveName(channelIndex, channelBaseName)
    EnsurePopulated()
    if type(channelIndex) == "number" then
        local mapped = channelMap[channelIndex]
        if type(mapped) == "string" and mapped ~= "" then
            return mapped
        end
    end
    if IsCommunityIdentifier(channelBaseName) then
        return ResolveCommunityName(channelBaseName)
    end
    return channelBaseName
end

function Registry.IsDefault(name)
    if type(name) ~= "string" or name == "" then return false end
    EnsurePopulated()
    return defaultUpper[name:upper()] == true
end

function Registry.AllNames()
    EnsurePopulated()
    local seen, out = {}, {}
    for _, name in pairs(channelMap) do
        if not seen[name] then
            seen[name] = true
            out[#out + 1] = name
        end
    end
    table.sort(out)
    return out
end

local REFRESH_EVENTS = {
    "PLAYER_LOGIN",
    "PLAYER_ENTERING_WORLD",
    "UPDATE_CHAT_WINDOWS",
    "CHANNEL_UI_UPDATE",
    "CHANNEL_LEFT",
}

if _G.CreateFrame then
    local eventFrame = CreateFrame("Frame")
    local valid = _G.C_EventUtils and _G.C_EventUtils.IsEventValid
    for i = 1, #REFRESH_EVENTS do
        if not valid or valid(REFRESH_EVENTS[i]) then
            eventFrame:RegisterEvent(REFRESH_EVENTS[i])
        end
    end
    eventFrame:SetScript("OnEvent", function()
        Registry.Refresh()
    end)
end

if _G.hooksecurefunc then
    if _G.C_ChatInfo and _G.C_ChatInfo.SwapChatChannelsByChannelIndex then
        _G.hooksecurefunc(_G.C_ChatInfo, "SwapChatChannelsByChannelIndex", function()
            Registry.Refresh()
        end)
    end
    local util = _G.ChatFrameUtil
    if util and util.AddCommunitiesChannel then
        _G.hooksecurefunc(util, "AddCommunitiesChannel", function()
            Registry.Refresh()
        end)
    end
    if util and util.RemoveCommunitiesChannel then
        _G.hooksecurefunc(util, "RemoveCommunitiesChannel", function()
            Registry.Refresh()
        end)
    end
end
