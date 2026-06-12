---------------------------------------------------------------------------
-- Core storage: saved-instance lockouts. RequestRaidInfo() is issued by
-- the collector at login; UPDATE_INSTANCE_INFO marks dirty. Reset times
-- are stored as ABSOLUTE epoch (time() + reset) — countdowns rot.
--
-- API shape verified against vendored FrameXML/RaidFrame (Mainline):
--   Blizzard_RaidFrame/Mainline/RaidFrame.lua:155:
--     local name, instanceID, reset, difficulty, locked, extended,
--           instanceIDMostSig, isRaid, maxPlayers, difficultyName
--           = GetSavedInstanceInfo(index);
--   Same file line 248 confirms at least 14 returns; positions 11-12
--   are unnamed in both usages (encounter counts used via
--   GameTooltip:SetInstanceLockEncountersComplete, not direct reads).
--   Plan positions 11=numEncounters, 12=encounterProgress are consistent
--   with the blank slots — FrameXML does not contradict them, but cannot
--   confirm them either: consumers MUST nil-guard boss counts, and the
--   first in-game pass must eyeball them.
--
-- Filter: only entries where (locked or extended) AND reset > 0 are
-- kept. Expired/unlocked entries carry no actionable lockout data.
---------------------------------------------------------------------------
-- luacheck: globals GetNumSavedInstances GetSavedInstanceInfo
local ADDON_NAME, ns = ...
local Storage = ns.Storage or {}; ns.Storage = Storage

local ScanLockouts = {}
Storage.ScanLockouts = ScanLockouts

local hasDirty = false

function ScanLockouts.MarkAllDirty()
    hasDirty = true
end

function ScanLockouts.Drain()
    if not hasDirty then return false end
    if type(GetNumSavedInstances) ~= "function" then return false end
    local rec = Storage.Store.GetCurrentCharacter()
    if not rec then return false end
    hasDirty = false
    local now = time()
    local fresh = {}
    for i = 1, GetNumSavedInstances() do
        -- Positions verified against RaidFrame.lua:155 (10 named returns):
        --   1=name, 2=instanceID, 3=reset, 4=difficulty, 5=locked,
        --   6=extended, 7=instanceIDMostSig, 8=isRaid, 9=maxPlayers,
        --   10=difficultyName, 11=numEncounters, 12=encounterProgress
        local name, _, reset, _, locked, extended, _, isRaid, _,
              difficultyName, numEncounters, encounterProgress = GetSavedInstanceInfo(i)
        if name and (locked or extended) and (reset or 0) > 0 then
            fresh[#fresh + 1] = {
                name            = name,
                difficultyName  = difficultyName,
                isRaid          = isRaid or nil,
                resetAt         = now + reset,
                bossesTotal     = numEncounters,
                bossesKilled    = encounterProgress,
                extended        = extended or nil,
            }
        end
    end
    rec.lockouts = fresh
    Storage.Bus.Publish("LockoutsChanged", Storage.Store.GetCurrentCharacterKey())
    return true
end
