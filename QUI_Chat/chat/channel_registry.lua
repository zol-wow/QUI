-- modules/chat/channel_registry.lua
-- Live channel identity for the custom display, mirroring the per-frame
-- channel model Blizzard chat frames keep (channelList/zoneChannelList,
-- vendored FrameXML: Blizzard_ChatFrameBase/Mainline/ChatFrameOverrides.lua
-- :316-337). Maintains:
--   * channelMap:   channel index -> display name (community identifiers
--                    resolved to "Club - Stream" form)
--   * default set:  channels whose category is NOT custom (zone/regional —
--                    "General", "Trade - City", "Services", ...), keyed by
--                    UPPERCASED name because Blizzard's own routing compares
--                    channel names case-insensitively (strupper both sides).
-- Refreshed on the same events Blizzard rebuilds frame channel tables from.
--
-- All reads are local C state (GetChannelList / GetNumDisplayChannels /
-- GetChannelDisplayInfo) — no secret payloads flow through this file.
local _, ns = ...

local _I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: channel_registry.lua loaded before chat.lua. Check chat.xml — chat.lua must precede channel_registry.lua.")

ns.QUI.Chat.ChannelRegistry = ns.QUI.Chat.ChannelRegistry or {}
local Registry = ns.QUI.Chat.ChannelRegistry

local channelMap = {}    -- index (number) -> display name
local defaultUpper = {}  -- strupper(display name) -> true (non-custom category)
local populated = false

-- "Community:1234:1" -> "Club - Stream" (or guild/officer stream name).
-- ChatFrameUtil.ResolveChannelName is Blizzard's own resolver (vendored
-- FrameXML: Blizzard_ChatFrameBase/Shared/ChatFrameUtil.lua:888) — pcall in
-- case club data is not yet initialized at login.
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

    -- Channel display list: numbered channels with category (zone/regional
    -- channels report a non-custom category; user /join channels are custom).
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

    -- Joined-channel list: covers communities channels that carry a numbered
    -- slot but may be absent from the display panel, and fills any slots the
    -- panel walk missed (GetChannelList returns id, name, disabled triplets).
    if type(_G.GetChannelList) == "function" then
        local list = { _G.GetChannelList() }
        for i = 1, #list, 3 do
            local index, name = list[i], list[i + 1]
            if type(index) == "number" and type(name) == "string" and name ~= ""
                and channelMap[index] == nil then
                if IsCommunityIdentifier(name) then
                    local display = ResolveCommunityName(name)
                    channelMap[index] = display
                    -- Communities channels behave like default channels: they
                    -- are configured/joined through Blizzard UI, not /join.
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

-- Canonical display name for a numbered-channel message: live map first
-- (keyed by arg8 channelIndex — NeverSecret per ChatInfoDocumentation), then
-- community resolution of the base name, then the base name itself.
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

-- True when the named channel is a default-category (zone/regional/community)
-- channel — Blizzard's default frame carries these without explicit listing.
function Registry.IsDefault(name)
    if type(name) ~= "string" or name == "" then return false end
    EnsurePopulated()
    return defaultUpper[name:upper()] == true
end

-- Sorted display names of all live channels (settings UI channel cards).
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

-- Refresh on the events Blizzard's chat frames rebuild channel state from,
-- plus PLAYER_ENTERING_WORLD (zone channels join server-side after PEW).
local REFRESH_EVENTS = {
    "PLAYER_LOGIN",
    "PLAYER_ENTERING_WORLD",
    "UPDATE_CHAT_WINDOWS",
    "CHANNEL_UI_UPDATE",
    "CHANNEL_LEFT",
}

if _G.CreateFrame then -- headless test harness tolerance
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

-- Channel index swaps and communities channel add/remove don't fire the
-- events above reliably — mirror the state through post-hooks.
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
