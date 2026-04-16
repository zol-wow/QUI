--[[
    QUI Centralized Aura Event Dispatcher
    Single UNIT_AURA registration with pub-sub dispatch to all consumers.
    Eliminates 7+ independent event handlers each doing their own aura scanning.

    Usage:
        ns.AuraEvents:Subscribe("player", callback)    -- unit == "player" only
        ns.AuraEvents:Subscribe("group",  callback)    -- party1..4 / raid1..40 (not player)
        ns.AuraEvents:Subscribe("roster", callback)    -- player + party + raid
        ns.AuraEvents:Subscribe("all",    callback)    -- every UNIT_AURA incl. nameplates/target/focus/boss/arena

    Callback signature: callback(unit, updateInfo)

    Nameplates/target/focus/boss/arena/pet/mouseover never reach player/group/roster
    subscribers — use "all" if you need them.
]]

local ADDON_NAME, ns = ...

-- Upvalue hot-path globals
local pairs = pairs
local ipairs = ipairs
local type = type
local wipe = wipe
local tostring = tostring
local CreateFrame = CreateFrame

---------------------------------------------------------------------------
-- DISPATCHER
---------------------------------------------------------------------------
local AuraEvents = {}
ns.AuraEvents = AuraEvents

-- Subscriber lists by filter
local subscribers = {
    player = {},   -- only unit == "player"
    group  = {},   -- party/raid units (not player)
    roster = {},   -- player + party1..4 + raid1..40 only (skips target/focus/boss/nameplate/arena)
    all    = {},   -- every UNIT_AURA event
}

-- Static roster unit set. UNIT_AURA fires for every unit token in the world
-- (player, party1..4, raid1..40, target, focus, boss1..5, arena1..5, pet,
-- mouseover, nameplate1..40, targettarget, focustarget, ...). In a raid with
-- many nameplates, the non-roster events dominate — an O(1) table lookup here
-- avoids dispatching to subscribers that would just early-out anyway.
local rosterUnits = { player = true }
for i = 1, 4 do rosterUnits["party" .. i] = true end
for i = 1, 40 do rosterUnits["raid" .. i] = true end

function AuraEvents:Subscribe(filter, callback)
    local list = subscribers[filter]
    if not list then
        error("AuraEvents:Subscribe invalid filter '" .. tostring(filter) .. "', use 'player', 'group', 'roster', or 'all'")
    end
    -- Avoid duplicate subscriptions
    for _, cb in ipairs(list) do
        if cb == callback then return end
    end
    list[#list + 1] = callback
    if self._RecountSubscribers then self:_RecountSubscribers() end
end

function AuraEvents:Unsubscribe(filter, callback)
    local list = subscribers[filter]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == callback then
            table.remove(list, i)
            if self._RecountSubscribers then self:_RecountSubscribers() end
            return
        end
    end
end

---------------------------------------------------------------------------
-- COALESCING FRAME: batches all UNIT_AURA events within the same render
-- frame into a single dispatch pass (zero-allocation, automatic).
---------------------------------------------------------------------------
local pendingUnits = {}  -- [unit] = updateInfo or true
local coalesceFrame = CreateFrame("Frame")
coalesceFrame:Hide()

-- Cache subscriber list lengths in hot-path locals to avoid the ipairs
-- iterator cost on every pending unit. Updated inside Subscribe/Unsubscribe.
local nAll, nRoster, nPlayer, nGroup = 0, 0, 0, 0
local subAll, subRoster, subPlayer, subGroup = subscribers.all, subscribers.roster, subscribers.player, subscribers.group

coalesceFrame:SetScript("OnUpdate", function(self)
    self:Hide()
    for unit, updateInfo in pairs(pendingUnits) do
        local info = updateInfo ~= true and updateInfo or nil
        local isRoster = rosterUnits[unit]

        -- Dispatch to "all" subscribers (every UNIT_AURA, including
        -- nameplates/target/focus/boss/arena — use sparingly).
        for i = 1, nAll do subAll[i](unit, info) end

        if isRoster then
            -- Roster tier: player + party1..4 + raid1..40.
            for i = 1, nRoster do subRoster[i](unit, info) end

            -- Player/group split is roster-scoped: "group" means
            -- party+raid (not player). Non-roster units like nameplates,
            -- target, focus, boss, arena never reach player/group
            -- subscribers — they go through "all" if they need them.
            if unit == "player" then
                for i = 1, nPlayer do subPlayer[i](unit, info) end
            else
                for i = 1, nGroup do subGroup[i](unit, info) end
            end
        end

        -- Clear merged accumulator so it's ready for reuse next frame.
        -- info is nil when updateInfo was `true` (full-update sentinel), so
        -- the nil check is enough without a type() call.
        if info and info._isMerged then
            info._isMerged = nil
            wipe(info.addedAuras)
            wipe(info.removedAuraInstanceIDs)
            wipe(info.updatedAuraInstanceIDs)
        end
    end
    wipe(pendingUnits)
end)

local function RecountSubscribers()
    nAll = #subAll
    nRoster = #subRoster
    nPlayer = #subPlayer
    nGroup = #subGroup
end
AuraEvents._RecountSubscribers = RecountSubscribers

---------------------------------------------------------------------------
-- DELTA MERGING: When multiple UNIT_AURA events arrive for the same unit
-- in one render frame, merge deltas instead of falling back to a full scan.
-- This preserves the incremental update path downstream (group frame auras)
-- which is dramatically cheaper than a full C_UnitAuras.GetUnitAuras call.
---------------------------------------------------------------------------
-- Per-unit scratch tables for merging (pre-allocated, reused via wipe)
local mergedInfoPool = {}  -- [unit] = { addedAuras = {}, removed... = {}, updated... = {} }
do local mp = ns._memprobes or {}; ns._memprobes = mp; mp[#mp + 1] = { name = "AuraEvt_mergedInfoPool", tbl = mergedInfoPool } end

local function GetMergedInfo(unit)
    local m = mergedInfoPool[unit]
    if not m then
        m = { addedAuras = {}, removedAuraInstanceIDs = {}, updatedAuraInstanceIDs = {} }
        mergedInfoPool[unit] = m
    end
    return m
end

-- Copy delta arrays from updateInfo into the merged accumulator
local function AccumulateDelta(merged, updateInfo)
    if updateInfo.addedAuras then
        local dst = merged.addedAuras
        for _, v in ipairs(updateInfo.addedAuras) do
            dst[#dst + 1] = v
        end
    end
    if updateInfo.removedAuraInstanceIDs then
        local dst = merged.removedAuraInstanceIDs
        for _, v in ipairs(updateInfo.removedAuraInstanceIDs) do
            dst[#dst + 1] = v
        end
    end
    if updateInfo.updatedAuraInstanceIDs then
        local dst = merged.updatedAuraInstanceIDs
        for _, v in ipairs(updateInfo.updatedAuraInstanceIDs) do
            dst[#dst + 1] = v
        end
    end
end

---------------------------------------------------------------------------
-- NON-ROSTER INTEREST PREDICATE
--
-- Non-roster units (nameplates, target, focus, boss, arena, pet, mouseover,
-- targettarget, ...) only reach "all" subscribers. Current "all" consumers
-- want at most two things:
--   1. `unit == "target"`  — cdm_icons target-debuff refresh
--   2. GameTooltip is shown — tooltip.lua OnUnitAuraChanged
--
-- If neither condition holds at event time, no "all" subscriber would do
-- useful work for the event, so we drop it before it even reaches
-- pendingUnits. In raids/M+ this eliminates the overwhelming majority of
-- nameplate UNIT_AURA traffic from the dispatcher loop entirely.
---------------------------------------------------------------------------
local function IsNonRosterEventInteresting(unit)
    if unit == "target" then return true end
    local tt = _G.GameTooltip
    if tt and tt:IsShown() then return true end
    return false
end

---------------------------------------------------------------------------
-- SINGLE EVENT REGISTRATION
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:SetScript("OnEvent", function(self, event, unit, updateInfo)
    -- Drop non-roster events nobody will do work for (the common case in raids).
    if not rosterUnits[unit] and not IsNonRosterEventInteresting(unit) then
        return
    end

    -- Store updateInfo; if any event for this unit is a full update, mark full.
    local existing = pendingUnits[unit]
    if existing == true then
        -- Already marked as full update, nothing to do
    elseif updateInfo and updateInfo.isFullUpdate then
        pendingUnits[unit] = true
    elseif not updateInfo then
        pendingUnits[unit] = true
    elseif existing then
        -- Multiple deltas for same unit in one frame — merge instead of full scan.
        -- This preserves the incremental path downstream which avoids expensive
        -- C_UnitAuras.GetUnitAuras calls (20+ per cycle in a raid).
        local merged = GetMergedInfo(unit)
        if type(existing) == "table" and not existing._isMerged then
            -- First merge: copy existing delta into accumulator
            wipe(merged.addedAuras)
            wipe(merged.removedAuraInstanceIDs)
            wipe(merged.updatedAuraInstanceIDs)
            merged._isMerged = true
            AccumulateDelta(merged, existing)
        end
        AccumulateDelta(merged, updateInfo)
        pendingUnits[unit] = merged
    else
        pendingUnits[unit] = updateInfo
    end
    coalesceFrame:Show()
end)

-- Perf profiler opt-in: coalesceFrame.OnUpdate runs the aura subscriber fan-out
-- (group frames, CDM, raidbuffs, atonement, private auras, etc). Wrapping it
-- measures total aura dispatch cost as one "AuraDispatch" line.
ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "AuraDispatch", frame = coalesceFrame, scriptType = "OnUpdate" }
ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "AuraRouter", frame = eventFrame }
