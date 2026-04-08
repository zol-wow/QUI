--[[
    QUI Party Tracker — Spec Cache
    Lightweight party member specialization detection and caching.
    Uses NotifyInspect + INSPECT_READY with GUID-keyed cache.
    Falls back to LibOpenRaid UnitInfoUpdate when available.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local SpecCache = {}
ns.PartyTracker_SpecCache = SpecCache

local UnitGUID = UnitGUID
local IsSecretValue = Helpers.IsSecretValue
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitIsUnit = UnitIsUnit
local UnitIsConnected = UnitIsConnected
local GetInspectSpecialization = GetInspectSpecialization
local NotifyInspect = NotifyInspect
local GetTime = GetTime
local select = select
local pcall = pcall

local CACHE_TTL = 300  -- 5 minutes
local INSPECT_INTERVAL = 0.5
local INSPECT_TIMEOUT = 10

local cache = {}   -- GUID → { specId, classToken, expiry }
local inspectQueue = {}  -- unit tokens needing inspection
local inspectPending = nil  -- unit currently being inspected
local inspectStartTime = 0
local inspectTicker = nil

---------------------------------------------------------------------------
-- PUBLIC API
---------------------------------------------------------------------------

function SpecCache.GetSpec(unit)
    if not unit or not UnitExists(unit) then return nil end

    -- Fast path for the player — no inspection needed.
    -- NOTE: do not call UnitIsUnit here. UnitIsUnit returns a SECRET BOOLEAN
    -- in combat for restricted unit tokens (target/targettarget/focus/etc.)
    -- which taints any caller that tests it. Match the literal "player"
    -- token instead — callers that pass party1..4 will fall through to the
    -- GUID cache below, which is the only path we want for party members.
    if unit == "player" then
        local spec = GetSpecialization and GetSpecialization()
        if spec then
            local specId = GetSpecializationInfo(spec)
            if specId and specId > 0 then return specId end
        end
    end

    local guid = UnitGUID(unit)
    if not guid or IsSecretValue(guid) then return nil end
    local entry = cache[guid]
    if entry and entry.specId and GetTime() < entry.expiry then
        return entry.specId
    end
    return nil
end

function SpecCache.GetClass(unit)
    if not unit or not UnitExists(unit) then return nil end
    local _, classToken = UnitClass(unit)
    return classToken
end

function SpecCache.SetSpec(unit, specId)
    if not unit or not specId or specId == 0 then return end
    local guid = UnitGUID(unit)
    if not guid or IsSecretValue(guid) then return end
    cache[guid] = {
        specId = specId,
        classToken = select(2, UnitClass(unit)),
        expiry = GetTime() + CACHE_TTL,
    }
end

function SpecCache.Clear()
    wipe(cache)
    wipe(inspectQueue)
    inspectPending = nil
end

function SpecCache.RequestInspect(unit)
    if not unit or not UnitExists(unit) or UnitIsUnit(unit, "player") then return end
    if not UnitIsConnected(unit) then return end

    local guid = UnitGUID(unit)
    if not guid or IsSecretValue(guid) then return end

    -- Already cached and fresh
    local entry = cache[guid]
    if entry and entry.specId and GetTime() < entry.expiry then return end

    -- Queue for inspection
    for _, queued in ipairs(inspectQueue) do
        if queued == unit then return end
    end
    inspectQueue[#inspectQueue + 1] = unit
    SpecCache.EnsureTicker()
end

---------------------------------------------------------------------------
-- INSPECT LOOP
---------------------------------------------------------------------------

local function ProcessInspectQueue()
    -- Timeout stale inspects
    if inspectPending and (GetTime() - inspectStartTime > INSPECT_TIMEOUT) then
        inspectPending = nil
    end

    -- Already inspecting someone
    if inspectPending then return end

    -- Find next valid unit
    while #inspectQueue > 0 do
        local unit = table.remove(inspectQueue, 1)
        if UnitExists(unit) and not UnitIsUnit(unit, "player") and UnitIsConnected(unit) then
            local guid = UnitGUID(unit)
            local entry = guid and not IsSecretValue(guid) and cache[guid]
            if not entry or not entry.specId or GetTime() >= entry.expiry then
                local ok = pcall(NotifyInspect, unit)
                if ok then
                    inspectPending = unit
                    inspectStartTime = GetTime()
                    return
                end
            end
        end
    end

    -- Nothing left, stop the ticker
    if inspectTicker then
        inspectTicker:Cancel()
        inspectTicker = nil
    end
end

function SpecCache.EnsureTicker()
    if inspectTicker then return end
    inspectTicker = C_Timer.NewTicker(INSPECT_INTERVAL, ProcessInspectQueue)
end

---------------------------------------------------------------------------
-- EVENT HANDLING
---------------------------------------------------------------------------

C_Timer.After(0, function()
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("INSPECT_READY")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

    local function QueueAllPartyInspects()
        local numGroup = GetNumGroupMembers() or 0
        if numGroup > 0 then
            local prefix = IsInRaid() and "raid" or "party"
            local max = IsInRaid() and numGroup or (numGroup - 1)
            for i = 1, max do
                SpecCache.RequestInspect(prefix .. i)
            end
        end
    end

    eventFrame:SetScript("OnEvent", function(_, event, arg1)
        if event == "INSPECT_READY" then
            if inspectPending then
                local specId = GetInspectSpecialization()
                if specId and specId > 0 and UnitExists(inspectPending) then
                    SpecCache.SetSpec(inspectPending, specId)
                end
                inspectPending = nil
                if #inspectQueue > 0 then
                    SpecCache.EnsureTicker()
                end
            end

        elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
            -- Party member changed spec mid-dungeon — invalidate their
            -- cached spec and re-inspect. Fires for any unit in the group.
            if arg1 and UnitExists(arg1) then
                local guid = UnitGUID(arg1)
                if guid and not IsSecretValue(guid) then cache[guid] = nil end
                SpecCache.RequestInspect(arg1)
            else
                -- No unit arg or unknown — re-inspect all party members
                QueueAllPartyInspects()
            end

        elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
            QueueAllPartyInspects()
        end
    end)
end)

---------------------------------------------------------------------------
-- LIBOPENRAID FALLBACK
---------------------------------------------------------------------------

C_Timer.After(2, function()
    local openRaidLib = LibStub and LibStub:GetLibrary("LibOpenRaid-1.0", true)
    if not openRaidLib then return end

    local callbackObj = {}
    function callbackObj.OnUnitInfoUpdate(unitId, unitInfo)
        if unitInfo and unitInfo.specId and unitInfo.specId > 0 then
            SpecCache.SetSpec(unitId, unitInfo.specId)
        end
    end
    openRaidLib.RegisterCallback(callbackObj, "UnitInfoUpdate", "OnUnitInfoUpdate")
end)
