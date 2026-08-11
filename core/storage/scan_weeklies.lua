-- luacheck: globals C_WeeklyRewards C_ChallengeMode C_MythicPlus
local ADDON_NAME, ns = ...
local Storage = ns.Storage or {}; ns.Storage = Storage

local ScanWeeklies = {}
Storage.ScanWeeklies = ScanWeeklies

local hasDirty = false

function ScanWeeklies.MarkAllDirty()
    hasDirty = true
end

function ScanWeeklies.Drain()
    if not hasDirty then return false end
    local rec = Storage.Store.GetCurrentCharacter()
    if not rec then return false end
    hasDirty = false
    local w = {}
    if C_WeeklyRewards and C_WeeklyRewards.GetActivities then
        w.activities = {}
        for _, a in ipairs(C_WeeklyRewards.GetActivities()) do
            w.activities[#w.activities + 1] = {
                type = a.type,
                index = a.index,
                threshold = a.threshold,
                progress = a.progress,
                level = a.level,
            }
        end
    end
    if C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore then
        w.mplusRating = C_ChallengeMode.GetOverallDungeonScore()
    end
    if C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID then
        local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
        if mapID then
            w.keystoneMapID = mapID
            w.keystoneLevel = C_MythicPlus.GetOwnedKeystoneLevel()
            if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
                local name = C_ChallengeMode.GetMapUIInfo(mapID)
                w.keystoneName = name
            end
        end
    end
    rec.weeklies = w
    Storage.Bus.Publish("WeekliesChanged", Storage.Store.GetCurrentCharacterKey())
    return true
end
