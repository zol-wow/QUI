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
