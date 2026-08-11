-- luacheck: globals C_Reputation C_MajorFactions InCombatLockdown
local ADDON_NAME, ns = ...
local Storage = ns.Storage or {}; ns.Storage = Storage

local ScanReputations = {}
Storage.ScanReputations = ScanReputations

local hasDirty = false
local fullDirty = false
local incremental = {}

function ScanReputations.MarkFullDirty()
    fullDirty = true
    hasDirty = true
end

function ScanReputations.ScheduleFullScan()
    ScanReputations.MarkFullDirty()
    Storage.RequestDrain()
end

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
                if groups then groups[data.factionID] = currentGroup end
            end
        end
    end
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
