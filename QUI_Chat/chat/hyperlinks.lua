---------------------------------------------------------------------------
-- QUI Chat Module — Hyperlink Enhancements (Phase D)
-- Three independent features unified by addon-protocol hyperlinks:
--   1. Coordinate detection — wraps "(x, y)" / "[x, y]" patterns with a
--      clickable waypoint link that fires C_Map.SetUserWaypoint on click.
--   2. Friendly URL labels — lookup table consulted by chat.lua's URL
--      detection to swap raw URLs for human-readable labels (Wowhead, etc).
--   3. Player-name CLICK handling — kept for player-protocol links persisted
--      in old sessions' history (the producer, the rendered-path name
--      wrapper, was deleted with the takeover); clicks open a quick-action
--      dropdown (Whisper / Invite / Add Friend / Ignore).
--
-- All three click pathways funnel through a single SetItemRef hook that
-- dispatches based on protocol prefix, isolated from chat.lua's URL handler.
---------------------------------------------------------------------------

local ADDON_NAME, ns = ...

local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: hyperlinks.lua loaded before chat.lua. Check chat.xml — chat.lua must precede hyperlinks.lua.")

ns.QUI.Chat.Hyperlinks = ns.QUI.Chat.Hyperlinks or {}
local HL = ns.QUI.Chat.Hyperlinks

local Helpers = ns.Helpers

local function IsSecret(value)
    return Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(value)
end

local function IsChatMessagingLockedDown()
    return I.IsChatMessagingLockedDown and I.IsChatMessagingLockedDown()
end

-- ---------------------------------------------------------------------------
-- Coord detection modifier
-- ---------------------------------------------------------------------------
-- Match patterns: "(45.6, 78.9)" and "[45, 78]" only. Bare comma-separated
-- forms are intentionally NOT detected — too aggressive for general chat.
-- Numbers may be int or float. Captures x, y as strings.
local COORD_PATTERN_PAREN  = "%((%d+%.?%d*)%s*,%s*(%d+%.?%d*)%)"
local COORD_PATTERN_SQUARE = "%[(%d+%.?%d*)%s*,%s*(%d+%.?%d*)%]"

local function wrapCoord(x, y, originalText)
    return string.format("|Haddon:quaziiuichat:waypoint:%s:%s|h[%s]|h",
        x, y, originalText or string.format("(%s, %s)", x, y))
end

-- Capture-path export: pure text transform, self-gated on the coordinates
-- toggle per call (no registration plumbing). Runs in message_capture's
-- transform chain after redundant-text collapse, before keyword highlight —
-- the same relative order the old rendered pipeline used.
function HL.TryLinkifyCoordsForCapture(msg)
    if IsSecret(msg) or IsChatMessagingLockedDown() then return msg end
    if type(msg) ~= "string" or msg == "" then return msg end

    local settings = I.GetSettings and I.GetSettings()
    local s = (I.IsChatEnabled and I.IsChatEnabled(settings)) and settings.hyperlinks
    if not s or not s.coordinates then return msg end

    -- Skip if msg already contains our addon protocol (don't double-wrap).
    if msg:find("addon:quaziiuichat:waypoint:", 1, true) then return msg end

    msg = msg:gsub(COORD_PATTERN_PAREN, function(x, y)
        return wrapCoord(x, y, "(" .. x .. ", " .. y .. ")")
    end)
    msg = msg:gsub(COORD_PATTERN_SQUARE, function(x, y)
        return wrapCoord(x, y, "[" .. x .. ", " .. y .. "]")
    end)

    return msg
end

-- ---------------------------------------------------------------------------
-- Friendly URL labels (callable from chat.lua's existing URL handler)
-- ---------------------------------------------------------------------------
-- Ordered: more-specific patterns must precede general fallback for the
-- same domain so the first match wins.
local URL_LABELS = {
    { pattern = "wowhead%.com/spell=",       label = ns.L["Wowhead spell"] },
    { pattern = "wowhead%.com/item=",        label = ns.L["Wowhead item"] },
    { pattern = "wowhead%.com/quest=",       label = ns.L["Wowhead quest"] },
    { pattern = "wowhead%.com/",             label = ns.L["Wowhead"] },
    { pattern = "raidbots%.com/sim/",        label = ns.L["Raidbots sim"] },
    { pattern = "raidbots%.com/",            label = ns.L["Raidbots"] },
    { pattern = "warcraftlogs%.com/reports/", label = ns.L["Logs report"] },
    { pattern = "warcraftlogs%.com/",        label = ns.L["Logs"] },
}

function HL.LookupFriendlyLabel(url)
    if type(url) ~= "string" or url == "" then return nil end

    local settings = I.GetSettings and I.GetSettings()
    local s = (I.IsChatEnabled and I.IsChatEnabled(settings)) and settings.hyperlinks
    if not s or not s.friendlyURLs then return nil end

    for i = 1, #URL_LABELS do
        if url:find(URL_LABELS[i].pattern) then
            return URL_LABELS[i].label
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- SetItemRef hook for waypoint + player-name actions
-- ---------------------------------------------------------------------------
-- Use hooksecurefunc rather than full replacement: chat.lua's existing URL
-- handler also hooks SetItemRef. The addon-protocol prefix dispatch keeps
-- the two pathways isolated — each handler returns early for non-matching
-- prefixes.

local function handleWaypoint(link)
    local x, y = link:match("waypoint:([%d%.]+):([%d%.]+)")
    x, y = tonumber(x), tonumber(y)
    if not x or not y then return end

    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cff34D399[QUI]|r Cannot set waypoint: current map unknown.",
                1, 1, 1)
        end
        return
    end

    if C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x / 100, y / 100))
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format("|cff34D399[QUI]|r Waypoint set: (%.1f, %.1f)", x, y),
                1, 1, 1)
        end
    elseif DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(
            string.format("|cff34D399[QUI]|r Waypoint API unavailable. Coords: (%.1f, %.1f)", x, y),
            1, 1, 1)
    end
end

local function handlePlayer(link)
    -- Format: addon:quaziiuichat:player:<NAME>:<REALM-or-empty>
    local name, realm = link:match("player:([^:]+):?([^|]*)")
    if name and name ~= "" then
        HL.ShowPlayerMenu(name, realm)
    end
end

hooksecurefunc("SetItemRef", function(link, text, button, ...)
    if type(link) ~= "string" then return end
    local settings = I.GetSettings and I.GetSettings()
    if not (I.IsChatEnabled and I.IsChatEnabled(settings)) then return end

    if link:find("^addon:quaziiuichat:waypoint:") then
        handleWaypoint(link)
    elseif link:find("^addon:quaziiuichat:player:") then
        handlePlayer(link)
    end
end)

-- ---------------------------------------------------------------------------
-- Hover tooltips for normal game hyperlinks
-- ---------------------------------------------------------------------------
-- The chat frame emits EventRegistry notifications for hyperlink hover. QUI's
-- addon links are handled separately on click, so only pass known game links
-- through GameTooltip:SetHyperlink.

local TOOLTIP_LINK_TYPES = {
    achievement = true,
    battlepet = true,
    conduit = true,
    currency = true,
    enchant = true,
    instancelock = true,
    item = true,
    keystone = true,
    mount = true,
    profession = true,
    pvptalent = true,
    quest = true,
    recipe = true,
    runeforgepower = true,
    spell = true,
    talent = true,
    toy = true,
    transmogappearance = true,
    transmogillusion = true,
}

local tooltipShownByQUI = false
local tooltipCallbacksRegistered = false

local function getLinkType(link)
    if IsSecret(link) then return nil end
    if type(link) ~= "string" or link == "" then return nil end
    local linkType = link:match("^([^:]+):")
    return linkType and linkType:lower() or nil
end

local function shouldShowHyperlinkTooltip(link)
    local linkType = getLinkType(link)
    return linkType and TOOLTIP_LINK_TYPES[linkType] == true
end

local function showHyperlinkTooltip(chatFrame, link)
    if not shouldShowHyperlinkTooltip(link) then return end

    local settings = I.GetSettings and I.GetSettings()
    if not (I.IsChatEnabled and I.IsChatEnabled(settings)) then return end

    local tooltip = GameTooltip
    if not tooltip or not tooltip.SetHyperlink then return end

    local owner = chatFrame or UIParent
    if owner and owner.IsForbidden and owner:IsForbidden() then
        owner = UIParent
    end

    if tooltip.SetOwner then
        tooltip:SetOwner(owner or UIParent, "ANCHOR_CURSOR")
    end

    local ok = pcall(tooltip.SetHyperlink, tooltip, link)
    if ok then
        tooltipShownByQUI = true
        if tooltip.Show then
            tooltip:Show()
        end
    else
        tooltipShownByQUI = false
        if tooltip.Hide then
            tooltip:Hide()
        end
    end
end

local function hideHyperlinkTooltip()
    if tooltipShownByQUI and GameTooltip and GameTooltip.Hide then
        GameTooltip:Hide()
    end
    tooltipShownByQUI = false
end

local function setupHyperlinkTooltips()
    if tooltipCallbacksRegistered then return end
    if not (EventRegistry and EventRegistry.RegisterCallback) then return end

    EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkEnter", function(_, chatFrame, link)
        showHyperlinkTooltip(chatFrame, link)
    end, HL)
    EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkLeave", function()
        hideHyperlinkTooltip()
    end, HL)
    tooltipCallbacksRegistered = true
end

setupHyperlinkTooltips()
HL.SetupHyperlinkTooltips = setupHyperlinkTooltips

-- ---------------------------------------------------------------------------
-- Player quick-action dropdown
-- ---------------------------------------------------------------------------
-- Created lazily on first use. Single shared frame; reinitialized per show.

local playerMenu

-- Walk every well-known unit ID looking for one whose name matches `name`
-- (and realm, when supplied). Inspect requires a unit token, not a name —
-- this is the bridge. Returns nil when the player isn't in any reachable
-- slot (party/raid/target/mouseover/focus); the menu then shows an inline
-- "not in range" notice instead of running NotifyInspect on a dead unit.
local function findUnitForName(name, realm)
    if not name or name == "" then return nil end

    -- Build candidate list. Order biases toward the cheapest checks first
    -- and toward units the player is currently looking at.
    local units = { "target", "mouseover", "focus" }
    local groupSize = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if groupSize > 0 then
        if IsInRaid and IsInRaid() then
            for i = 1, groupSize do units[#units + 1] = "raid" .. i end
        else
            for i = 1, groupSize - 1 do units[#units + 1] = "party" .. i end
            units[#units + 1] = "player"
        end
    end

    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            local uname, urealm = UnitFullName(unit)
            if uname == name then
                if not realm or realm == "" then
                    return unit
                end
                if urealm == realm or (urealm == nil and realm == GetRealmName()) then
                    return unit
                end
            end
        end
    end
    return nil
end

function HL.ShowPlayerMenu(name, realm)
    if not name or name == "" then return end

    local fullName = (realm and realm ~= "") and (name .. "-" .. realm) or name

    playerMenu = playerMenu or CreateFrame(
        "Frame", "QUIChatPlayerMenu", UIParent, "UIDropDownMenuTemplate")

    local function init(self, level)
        local info

        info = UIDropDownMenu_CreateInfo()
        info.text = fullName
        info.isTitle = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)

        info = UIDropDownMenu_CreateInfo()
        info.text = ns.L["Whisper"]
        info.notCheckable = true
        info.func = function()
            if ChatFrame_SendTell then ChatFrame_SendTell(fullName) end
        end
        UIDropDownMenu_AddButton(info, level)

        info = UIDropDownMenu_CreateInfo()
        info.text = ns.L["Invite to Group"]
        info.notCheckable = true
        info.func = function()
            if C_PartyInfo and C_PartyInfo.InviteUnit then
                C_PartyInfo.InviteUnit(fullName)
            end
        end
        UIDropDownMenu_AddButton(info, level)

        -- Inspect: resolve the name to a unit token via party/raid/target/
        -- mouseover/focus. Cross-realm-but-different-realm players cannot
        -- be inspected at all (Blizzard limitation), so the entry is hidden
        -- when the resolver returns nothing. NotifyInspect is async; the
        -- InspectFrame opens immediately and populates as data arrives.
        if not realm or realm == "" or realm == GetRealmName() then
            local resolvedUnit = findUnitForName(name, realm)
            info = UIDropDownMenu_CreateInfo()
            info.text = ns.L["Inspect"]
            info.notCheckable = true
            if resolvedUnit then
                info.disabled = false
                info.func = function()
                    if NotifyInspect then NotifyInspect(resolvedUnit) end
                    if InspectFrame_Show then
                        InspectFrame_Show(resolvedUnit)
                    elseif _G.InspectFrame and _G.InspectFrame.Show then
                        _G.InspectFrame:Show()
                    end
                end
            else
                info.disabled = true
                info.tooltipTitle = ns.L["Inspect"]
                info.tooltipText  = ns.L["Player not in group/target/mouseover/focus."]
                info.tooltipOnButton = true
                ---@type fun(...)
                info.func = function() end
            end
            UIDropDownMenu_AddButton(info, level)
        end

        info = UIDropDownMenu_CreateInfo()
        info.text = ns.L["Add Friend"]
        info.notCheckable = true
        info.func = function()
            if C_FriendList and C_FriendList.AddFriend then
                C_FriendList.AddFriend(fullName)
            end
        end
        UIDropDownMenu_AddButton(info, level)

        info = UIDropDownMenu_CreateInfo()
        info.text = ns.L["Ignore"]
        info.notCheckable = true
        info.func = function()
            if C_FriendList and C_FriendList.AddIgnore then
                C_FriendList.AddIgnore(fullName)
            end
        end
        UIDropDownMenu_AddButton(info, level)
    end

    UIDropDownMenu_Initialize(playerMenu, init, "MENU")
    ToggleDropDownMenu(1, nil, playerMenu, "cursor", 0, 0)
end

-- (No registration plumbing: TryLinkifyCoordsForCapture self-gates per call;
-- friendlyURLs and interactiveNames are read on-demand by their consumers.)
