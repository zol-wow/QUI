--[[
    QUI Centralized Aura Event Dispatcher
    Single UNIT_AURA registration with pub-sub dispatch to all consumers.
    Eliminates 7+ independent event handlers each doing their own aura scanning.

    Usage:
        ns.AuraEvents:Subscribe("player", callback)    -- player auras only
        ns.AuraEvents:Subscribe("group", callback)      -- party/raid units
        ns.AuraEvents:Subscribe("all", callback)        -- all units
    Callback signature: callback(unit, updateInfo)
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
    all    = {},   -- every UNIT_AURA event
}

function AuraEvents:Subscribe(filter, callback)
    local list = subscribers[filter]
    if not list then
        error("AuraEvents:Subscribe invalid filter '" .. tostring(filter) .. "', use 'player', 'group', or 'all'")
    end
    -- Avoid duplicate subscriptions
    for _, cb in ipairs(list) do
        if cb == callback then return end
    end
    list[#list + 1] = callback
end

function AuraEvents:Unsubscribe(filter, callback)
    local list = subscribers[filter]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == callback then
            table.remove(list, i)
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

coalesceFrame:SetScript("OnUpdate", function(self)
    self:Hide()
    for unit, updateInfo in pairs(pendingUnits) do
        local info = updateInfo ~= true and updateInfo or nil

        -- Dispatch to "all" subscribers
        for _, cb in ipairs(subscribers.all) do
            cb(unit, info)
        end

        -- Dispatch to filtered subscribers
        if unit == "player" then
            for _, cb in ipairs(subscribers.player) do
                cb(unit, info)
            end
        else
            for _, cb in ipairs(subscribers.group) do
                cb(unit, info)
            end
        end

        -- Clear merged accumulator so it's ready for reuse next frame
        if type(updateInfo) == "table" and updateInfo._isMerged then
            updateInfo._isMerged = nil
        end
    end
    wipe(pendingUnits)
end)

---------------------------------------------------------------------------
-- DELTA MERGING: When multiple UNIT_AURA events arrive for the same unit
-- in one render frame, merge deltas instead of falling back to a full scan.
-- This preserves the incremental update path downstream (group frame auras)
-- which is dramatically cheaper than a full C_UnitAuras.GetUnitAuras call.
---------------------------------------------------------------------------
-- Per-unit scratch tables for merging (pre-allocated, reused via wipe)
local mergedInfoPool = {}  -- [unit] = { addedAuras = {}, removed... = {}, updated... = {} }

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
-- SINGLE EVENT REGISTRATION
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:SetScript("OnEvent", function(self, event, unit, updateInfo)
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
