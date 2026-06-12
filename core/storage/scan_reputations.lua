---------------------------------------------------------------------------
-- Core storage: reputations scanner. Full walk (login-deferred) expands
-- collapsed headers to capture hidden children, then restores the user's
-- collapse state; FACTION_STANDING_CHANGED updates one faction in place
-- (GetFactionDataByID — no walk, no UI mutation). Faction names/groups are
-- interned in shared store maps (Store.GetFactionNames/Groups) so per-
-- character entries stay numeric. Full walks defer out of combat (the
-- expand/collapse dance mutates the rep pane state).
--
-- API shapes verified against vendored docs:
--   ReputationInfoDocumentation.lua: GetNumFactions, GetFactionDataByIndex
--     (luaIndex) / GetFactionDataByID (factionID) → FactionData (nilable),
--     ExpandFactionHeader/CollapseFactionHeader (luaIndex), IsFactionParagon,
--     GetFactionParagonInfo (MayReturnNothing → currentValue, threshold,
--     rewardQuestID, hasRewardPending, tooLowLevelForParagon, paragonStorageLevel),
--     IsMajorFaction.
--   MajorFactionsDocumentation.lua: GetMajorFactionData → MajorFactionData
--     (nilable) incl. renownLevel, renownReputationEarned, renownLevelThreshold.
---------------------------------------------------------------------------
-- luacheck: globals C_Reputation C_MajorFactions InCombatLockdown
local ADDON_NAME, ns = ...
local Storage = ns.Storage or {}; ns.Storage = Storage

local ScanReputations = {}
Storage.ScanReputations = ScanReputations

local hasDirty = false
local fullDirty = false
local incremental = {} -- [factionID] = true

function ScanReputations.MarkFullDirty()
    fullDirty = true
    hasDirty = true
end

--- Collector calls this once per login (after first paint).
function ScanReputations.ScheduleFullScan()
    ScanReputations.MarkFullDirty()
    Storage.RequestDrain()
end

--- FACTION_STANDING_CHANGED payload (factionID, updatedStanding).
function ScanReputations.OnFactionStandingChanged(factionID)
    if not factionID then return end
    incremental[factionID] = true
    hasDirty = true
end

local function ReadEntry(data)
    local entry = {
        standing = data.reaction,
        value = data.currentStanding,
        floor = data.currentReactionThreshold,
        ceiling = data.nextReactionThreshold,
        accountWide = data.isAccountWide or nil,
    }
    local id = data.factionID
    if C_Reputation.IsMajorFaction(id) then
        local mf = C_MajorFactions and C_MajorFactions.GetMajorFactionData
            and C_MajorFactions.GetMajorFactionData(id)
        if mf then
            entry.renownLevel = mf.renownLevel
            entry.renownEarned = mf.renownReputationEarned
            entry.renownThreshold = mf.renownLevelThreshold
        end
    end
    if C_Reputation.IsFactionParagon(id) then
        -- MayReturnNothing; store RAW values (currentValue accumulates past
        -- the threshold) — display math is the UI's job.
        local cur, threshold, _, pending = C_Reputation.GetFactionParagonInfo(id)
        if cur then
            entry.paragonValue = cur
            entry.paragonThreshold = threshold
            entry.paragonPending = pending or nil
        end
    end
    return entry
end

local function FullWalk(rec)
    local names = Storage.Store.GetFactionNames()
    local groups = Storage.Store.GetFactionGroups()
    -- 1) expand collapsed headers, remembering which (indices shift as we
    --    expand, so re-read the count every step and never cache it)
    local collapsedIDs = {}
    local i = 1
    while i <= C_Reputation.GetNumFactions() do
        local data = C_Reputation.GetFactionDataByIndex(i)
        if data and data.isHeader and data.isCollapsed then
            collapsedIDs[data.factionID] = true
            C_Reputation.ExpandFactionHeader(i)
        end
        i = i + 1
    end
    -- 2) scan everything visible; track the current top-level header as the
    --    group label
    local fresh = {}
    local currentGroup = nil
    for j = 1, C_Reputation.GetNumFactions() do
        local data = C_Reputation.GetFactionDataByIndex(j)
        if data then
            if data.isHeader and not data.isChild then
                currentGroup = data.name
            end
            local hasRep = (not data.isHeader) or data.isHeaderWithRep
            if hasRep and data.factionID and data.factionID > 0 then
                fresh[data.factionID] = ReadEntry(data)
                if names then names[data.factionID] = data.name end
                -- a faction listed under two headers keeps the LAST one seen
                if groups then groups[data.factionID] = currentGroup end
            end
        end
    end
    -- 3) restore collapse state bottom-up (collapsing shrinks the list;
    --    bottom-up keeps earlier indices valid)
    for j = C_Reputation.GetNumFactions(), 1, -1 do
        local data = C_Reputation.GetFactionDataByIndex(j)
        if data and data.isHeader and collapsedIDs[data.factionID] then
            C_Reputation.CollapseFactionHeader(j)
        end
    end
    rec.reputations = fresh
end

function ScanReputations.Drain()
    if not hasDirty then return false end
    if not (C_Reputation and C_Reputation.GetNumFactions) then return false end
    local rec = Storage.Store.GetCurrentCharacter()
    if not rec then return false end
    if fullDirty and InCombatLockdown and InCombatLockdown() then
        -- The expand/collapse dance mutates pane state; keep it out of
        -- combat. Dirty marks survive; the next drain retries.
        return false
    end
    hasDirty = false
    local changed = false
    if fullDirty then
        fullDirty = false
        incremental = {}
        FullWalk(rec)
        changed = true
    else
        local names = Storage.Store.GetFactionNames()
        local toUpdate = incremental
        incremental = {}
        for factionID in pairs(toUpdate) do
            local data = C_Reputation.GetFactionDataByID(factionID)
            if data then
                rec.reputations[factionID] = ReadEntry(data)
                if names then names[factionID] = data.name end
                changed = true
            end
        end
    end
    if changed then
        Storage.Bus.Publish("ReputationsChanged", Storage.Store.GetCurrentCharacterKey())
    end
    return changed
end
