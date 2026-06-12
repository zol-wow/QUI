---------------------------------------------------------------------------
-- Core storage: weeklies scanner — Great Vault activity progress, M+
-- season rating, owned keystone. Whole-record rewrite per drain (the
-- surface is ~a dozen cheap C calls). All sub-APIs existence-guarded:
-- the vault/M+ surface varies by client flavor.
--
-- API shape verified against vendored docs:
--   C_WeeklyRewards.GetActivities(type?) → table<WeeklyRewardActivityInfo>
--     WeeklyRewardsDocumentation.lua:43 — SecretArguments "AllowedWhenUntainted";
--     struct fields: type, index, threshold, progress, id, activityTierID,
--     level (all non-Nilable), claimID/raidString (Nilable), rewards (table).
--   C_ChallengeMode.GetOverallDungeonScore() → overallDungeonScore (number, non-Nilable)
--     ChallengeModeInfoDocumentation.lua:187
--   C_MythicPlus.GetOwnedKeystoneChallengeMapID() → challengeMapID — MayReturnNothing
--     MythicPlusInfoDocumentation.lua:76
--   C_MythicPlus.GetOwnedKeystoneLevel() → keyStoneLevel — MayReturnNothing
--     MythicPlusInfoDocumentation.lua:86
--   C_ChallengeMode.GetMapUIInfo(mapChallengeModeID) → name, id, timeLimit, texture?,
--     backgroundTexture, mapID — MayReturnNothing, SecretArguments "AllowedWhenUntainted"
--     ChallengeModeInfoDocumentation.lua:163
---------------------------------------------------------------------------
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
    if not rec then return false end -- transient: dirty mark preserved
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
        local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID() -- MayReturnNothing
        if mapID then
            w.keystoneMapID = mapID
            w.keystoneLevel = C_MythicPlus.GetOwnedKeystoneLevel() -- MayReturnNothing, same session
            if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
                local name = C_ChallengeMode.GetMapUIInfo(mapID) -- MayReturnNothing
                w.keystoneName = name -- nil is fine; consumer checks
            end
        end
    end
    rec.weeklies = w
    Storage.Bus.Publish("WeekliesChanged", Storage.Store.GetCurrentCharacterKey())
    return true
end
