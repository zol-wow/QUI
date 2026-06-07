---------------------------------------------------------------------------
-- QUI Chat Module — Legacy Per-Frame Content Filtering Storage
-- Older builds persisted per-frame message group + channel selections at
-- db.profile.chat.tabs[<frameID>] = { customized, groups, channels }.
-- Live QUI chat tabs now use db.profile.chat.customDisplay.windows[i].tabs instead;
-- this module only preserves group-version upgrades and compatibility helpers.
-- NOTHING is applied to the Blizzard chat windows anymore — under the
-- takeover they are hidden and event-neutered, and with the module
-- disabled QUI does not touch chat at all.
---------------------------------------------------------------------------

local ADDON_NAME, ns = ...

local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: tab_filters.lua loaded before chat.lua. Check chat.xml — chat.lua must precede tab_filters.lua.")

ns.QUI.Chat.TabFilters = ns.QUI.Chat.TabFilters or {}
local TF = ns.QUI.Chat.TabFilters

local GROUPS_VERSION = 1
TF.GROUPS_VERSION = GROUPS_VERSION

local STANDARD_GROUPS = {
    "SAY", "EMOTE", "YELL",
    "GUILD", "OFFICER", "GUILD_ACHIEVEMENT", "ACHIEVEMENT",
    "WHISPER", "WHISPER_INFORM", "BN_WHISPER", "BN_WHISPER_INFORM",
    "AFK", "DND",
    "PARTY", "PARTY_LEADER",
    "RAID", "RAID_LEADER", "RAID_WARNING",
    "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER",
    "MONSTER_SAY", "MONSTER_EMOTE", "MONSTER_YELL", "MONSTER_WHISPER",
    "MONSTER_BOSS_EMOTE", "MONSTER_BOSS_WHISPER",
    "COMBAT_XP_GAIN", "COMBAT_HONOR_GAIN", "COMBAT_FACTION_CHANGE",
    "SKILL", "LOOT", "CURRENCY", "MONEY",
    "TRADESKILLS", "OPENING", "PET_INFO", "COMBAT_MISC_INFO",
    "BG_HORDE", "BG_ALLIANCE", "BG_NEUTRAL",
    "SYSTEM", "ERRORS", "IGNORED", "CHANNEL", "TARGETICONS",
    "BN_INLINE_TOAST_ALERT", "PET_BATTLE_COMBAT_LOG", "PET_BATTLE_INFO", "PING",
}

function TF.GetStandardGroups()
    local copy = {}
    for i = 1, #STANDARD_GROUPS do
        copy[i] = STANDARD_GROUPS[i]
    end
    return copy
end

local function listHas(list, value)
    if type(list) ~= "table" then return false end
    for i = 1, #list do
        if list[i] == value then return true end
    end
    return false
end

local function appendUnique(list, value)
    if listHas(list, value) then return end
    list[#list + 1] = value
end

-- Groups introduced after a stored entry was written. A pre-version entry
-- that whitelisted SYSTEM gets the split-out groups appended so its tab
-- keeps showing the same content.
local SYSTEM_GROUP_UPGRADE = {
    "ERRORS",
    "TARGETICONS",
    "BN_INLINE_TOAST_ALERT",
    "PET_BATTLE_COMBAT_LOG",
    "PET_BATTLE_INFO",
    "PING",
}

local function upgradeEntryGroups(entry)
    if type(entry) ~= "table" or entry._groupsVersion == GROUPS_VERSION then return end
    if type(entry.groups) ~= "table" then entry.groups = {} end

    if listHas(entry.groups, "SYSTEM") then
        for i = 1, #SYSTEM_GROUP_UPGRADE do
            appendUnique(entry.groups, SYSTEM_GROUP_UPGRADE[i])
        end
    end

    entry._groupsVersion = GROUPS_VERSION
end

-- One pass over legacy stored entries so old saved variables remain normalized.
local function upgradeAllStoredEntries()
    local settings = I.GetSettings and I.GetSettings()
    local tabs = settings and settings.tabs
    if type(tabs) ~= "table" then return end
    for _, entry in pairs(tabs) do
        upgradeEntryGroups(entry)
    end
end

-- ---------------------------------------------------------------------------
-- Settings helpers (used by the settings UI)
-- ---------------------------------------------------------------------------

-- Save a legacy per-frame filter config. `groups` and `channels` are arrays
-- of string keys. Retained for saved-variable compatibility.
function TF.SaveTabConfig(frameID, groups, channels)
    local settings = I.GetSettings and I.GetSettings()
    if not settings then return end
    settings.tabs = settings.tabs or {}
    settings.tabs[frameID] = {
        customized = true,
        groups = groups or {},
        channels = channels or {},
        _groupsVersion = GROUPS_VERSION,
    }
end

-- Reset a legacy per-frame filter config.
function TF.ResetTab(frameID)
    local settings = I.GetSettings and I.GetSettings()
    if not settings or not settings.tabs then return end
    settings.tabs[frameID] = nil
end

-- Upgrade stored entries once settings exist. ADDON_LOADED covers normal
-- login; PLAYER_LOGIN is the safety net (AceDB is constructed in
-- OnInitialize, before either fires for this addon).
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == ADDON_NAME then
        self:UnregisterEvent("ADDON_LOADED")
        upgradeAllStoredEntries()
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        upgradeAllStoredEntries()
    end
end)
