local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local GetSettings = Helpers.CreateDBGetter("general")

local ignoreSet = {}
local setEmpty = true

-- <<< QUI_TEST_EXTRACT normalize_name
local Fold = Helpers and Helpers.FoldUTF8 or string.lower
local function NormalizeName(name)
    if type(name) ~= "string" or name == "" then return nil end
    local base = name:match("^([^-]+)") or name
    base = base:gsub("%s+", "")
    if base == "" then return nil end
    return Fold(base)
end
-- <<< QUI_TEST_EXTRACT normalize_name

local function RebuildSet()
    wipe(ignoreSet)
    local settings = GetSettings()
    local cfg = settings and settings.extendedIgnore
    local text = cfg and cfg.names
    if type(text) == "string" then
        for token in string.gmatch(text, "[^,\n\r]+") do
            local norm = NormalizeName(token)
            if norm then ignoreSet[norm] = true end
        end
    end
    setEmpty = next(ignoreSet) == nil
end

local function IsInSet(name)
    if setEmpty then return false end
    local norm = NormalizeName(name)
    return norm ~= nil and ignoreSet[norm] == true
end

function ns.ShouldAutoDeclineFrom(name)
    local settings = GetSettings()
    local cfg = settings and settings.extendedIgnore
    if not cfg or not cfg.enabled or cfg.autoDecline == false then return false end
    return IsInSet(name)
end

local CHAT_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
    "CHAT_MSG_CHANNEL", "CHAT_MSG_WHISPER",
}

local function ChatFilter(_, _, _, sender)
    local settings = GetSettings()
    local cfg = settings and settings.extendedIgnore
    if not cfg or not cfg.enabled or cfg.suppressChat == false then return false end
    if IsInSet(sender) then return true end
    return false
end

local filtersInstalled = false
local function InstallChatFilters()
    if filtersInstalled then return end
    if not (_G.ChatFrameUtil and _G.ChatFrameUtil.AddMessageEventFilter) then return end
    for _, ev in ipairs(CHAT_EVENTS) do
        _G.ChatFrameUtil.AddMessageEventFilter(ev, ChatFilter)
    end
    filtersInstalled = true
end

local tradeWatcher = CreateFrame("Frame")
tradeWatcher:RegisterEvent("TRADE_SHOW")
tradeWatcher:SetScript("OnEvent", function()
    local partner = GetUnitName("NPC")
    if partner and ns.ShouldAutoDeclineFrom(partner) then
        CancelTrade()
    end
end)

local function Refresh()
    RebuildSet()
    InstallChatFilters()
end
ns.RefreshExtendedIgnore = Refresh

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(Refresh)
end

if ns.Registry then
    ns.Registry:Register("extendedIgnore", {
        refresh = Refresh,
        priority = 30,
        group = "qol",
        importCategories = { "qol" },
    })
end
