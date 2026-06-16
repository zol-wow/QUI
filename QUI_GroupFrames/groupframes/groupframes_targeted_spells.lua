--[[
    QUI Group Frames - Targeted cast markers

    Tracks hostile nameplate casts whose Blizzard unit APIs expose a spell
    target, then places the spell icon on the matching QUI group frame.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local GroupFrames = ns.QUI_GroupFrames
if not GroupFrames then return end

local CreateFrame = CreateFrame
local C_NamePlate = C_NamePlate
local C_Timer = C_Timer
local GetTime = GetTime
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local UnitCanAttack = UnitCanAttack
local UnitCastingDuration = UnitCastingDuration
local UnitCastingInfo = UnitCastingInfo
local UnitChannelDuration = UnitChannelDuration
local UnitChannelInfo = UnitChannelInfo
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitRace = UnitRace
local UnitSex = UnitSex
local UnitShouldDisplaySpellTargetName = UnitShouldDisplaySpellTargetName
local ipairs = ipairs
local math_floor = math.floor
local pairs = pairs
local pcall = pcall
local table_remove = table.remove
local tonumber = tonumber
local type = type
local wipe = wipe

local GetGroupDB = Helpers.CreateDBGetter("quiGroupFrames")
local IsSecretValue = Helpers.IsSecretValue

local TargetedSpells = ns.QUI_GroupFrameTargetedSpells or {}
ns.QUI_GroupFrameTargetedSpells = TargetedSpells

local TIMING = {
    firstRead = 0.10,
    verifyRead = 0.15,
    targetChangeRead = 0.05,
}

local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local OPTION_DEFAULTS = {
    enabled = true,
    iconSize = 24,
    maxIcons = 3,
    spacing = 2,
    growDirection = "CENTER",
    position = "CENTER",
    offsetX = 0,
    offsetY = 0,
    reverseSwipe = true,
}

local POINTS = {
    TOPLEFT = true,
    TOP = true,
    TOPRIGHT = true,
    LEFT = true,
    CENTER = true,
    RIGHT = true,
    BOTTOMLEFT = true,
    BOTTOM = true,
    BOTTOMRIGHT = true,
}

local GROW = {
    LEFT = true,
    RIGHT = true,
    CENTER = true,
    UP = true,
    DOWN = true,
}

local PARTY_ROSTER = { "player", "party1", "party2", "party3", "party4" }
local RAID_ROSTER = {}
for i = 1, 40 do
    RAID_ROSTER[i] = "raid" .. i
end

local function ReadableString(value)
    if IsSecretValue(value) or type(value) ~= "string" then
        return nil
    end
    return value
end

local function ReadableNumber(value)
    if IsSecretValue(value) or type(value) ~= "number" then
        return nil
    end
    return value
end

local function ReadableTruthy(value)
    if IsSecretValue(value) then
        return false
    end
    return value and true or false
end

local function ClampNumber(value, fallback, minValue, maxValue)
    if IsSecretValue(value) then
        return fallback
    end
    local n = tonumber(value)
    if not n then
        return fallback
    end
    if minValue and n < minValue then
        n = minValue
    end
    if maxValue and n > maxValue then
        n = maxValue
    end
    return n
end

local function ContextDB(isRaid)
    local db = GetGroupDB()
    if type(db) ~= "table" then
        return nil
    end
    return isRaid and db.raid or db.party
end

local function Options(isRaid)
    local context = ContextDB(isRaid)
    local options = context and context.targetedSpells
    if type(options) == "table" then
        return options
    end
    return OPTION_DEFAULTS
end

local function Option(isRaid, key)
    local value = Options(isRaid)[key]
    if value == nil then
        return OPTION_DEFAULTS[key]
    end
    return value
end

local function UpperToken(value, fallback, allowed)
    local token = ReadableString(value)
    if token then
        token = string.upper(token)
    end
    if not token or not allowed[token] then
        return fallback
    end
    return token
end

local function AnchorPoint(isRaid)
    return UpperToken(Option(isRaid, "position"), OPTION_DEFAULTS.position, POINTS)
end

local function GrowthDirection(isRaid)
    return UpperToken(Option(isRaid, "growDirection"), OPTION_DEFAULTS.growDirection, GROW)
end

local function CurrentRosterTokens()
    return IsInRaid() and RAID_ROSTER or PARTY_ROSTER
end

---------------------------------------------------------------------------
-- Roster index
---------------------------------------------------------------------------
local Roster = {
    byClass = {},
    role = {},
    race = {},
    sex = {},
    candidates = {},
    lastIndexedAt = 0,
}

local function ClearRosterIndex()
    wipe(Roster.byClass)
    wipe(Roster.role)
    wipe(Roster.race)
    wipe(Roster.sex)
    wipe(Roster.candidates)
end

local function AddUnitToClassBucket(unit, classToken)
    local bucket = Roster.byClass[classToken]
    if not bucket then
        bucket = {}
        Roster.byClass[classToken] = bucket
    end
    bucket[#bucket + 1] = unit
end

local function IndexRoster()
    ClearRosterIndex()

    local roster = CurrentRosterTokens()
    for i = 1, #roster do
        local unit = roster[i]
        if ReadableTruthy(UnitExists(unit)) then
            local _, classToken = UnitClass(unit)
            classToken = ReadableString(classToken)
            if classToken then
                AddUnitToClassBucket(unit, classToken)
            end

            local role = ReadableString(UnitGroupRolesAssigned(unit))
            if role and role ~= "NONE" then
                Roster.role[unit] = role
            end

            local _, raceToken = UnitRace(unit)
            raceToken = ReadableString(raceToken)
            if raceToken then
                Roster.race[unit] = raceToken
            end

            local sex = ReadableNumber(UnitSex(unit))
            if sex then
                Roster.sex[unit] = sex
            end
        end
    end

    Roster.lastIndexedAt = GetTime()
end

local function LoadClassCandidates(classToken)
    local out = Roster.candidates
    wipe(out)

    local bucket = Roster.byClass[classToken]
    if not bucket then
        return out
    end

    for i = 1, #bucket do
        out[i] = bucket[i]
    end
    return out
end

local function NarrowCandidates(targetValue, indexedValues)
    local candidates = Roster.candidates
    if targetValue == nil or #candidates <= 1 then
        return
    end

    local hasMatch = false
    for i = 1, #candidates do
        if indexedValues[candidates[i]] == targetValue then
            hasMatch = true
            break
        end
    end
    if not hasMatch then
        return
    end

    for i = #candidates, 1, -1 do
        if indexedValues[candidates[i]] ~= targetValue then
            table_remove(candidates, i)
        end
    end
end

local function CompoundTargetAttribute(reader, unit)
    local ok, a, b = pcall(reader, unit)
    if not ok then
        return nil
    end
    return a, b
end

local function UnitFromCasterTarget(caster)
    local target = caster .. "target"
    local _, classToken = CompoundTargetAttribute(UnitClass, target)
    classToken = ReadableString(classToken)
    if not classToken then
        return nil
    end

    local candidates = LoadClassCandidates(classToken)
    if #candidates == 0 and GetTime() - Roster.lastIndexedAt > 1 then
        IndexRoster()
        candidates = LoadClassCandidates(classToken)
    end
    if #candidates == 0 then
        return nil
    end

    local role = ReadableString((CompoundTargetAttribute(UnitGroupRolesAssigned, target)))
    if role == "NONE" then
        role = nil
    end
    NarrowCandidates(role, Roster.role)

    local _, raceToken = CompoundTargetAttribute(UnitRace, target)
    NarrowCandidates(ReadableString(raceToken), Roster.race)

    NarrowCandidates(ReadableNumber((CompoundTargetAttribute(UnitSex, target))), Roster.sex)

    if #candidates ~= 1 then
        return nil
    end
    return candidates[1]
end

---------------------------------------------------------------------------
-- Frame markers
---------------------------------------------------------------------------
local markerPools = setmetatable({}, { __mode = "k" })

local function MarkerSize(isRaid)
    return ClampNumber(Option(isRaid, "iconSize"), OPTION_DEFAULTS.iconSize, 4, 96)
end

local function MarkerLimit(isRaid)
    return math_floor(ClampNumber(Option(isRaid, "maxIcons"), OPTION_DEFAULTS.maxIcons, 1, 10))
end

local function MarkerSpacing(isRaid)
    return ClampNumber(Option(isRaid, "spacing"), OPTION_DEFAULTS.spacing, 0, 32)
end

local function PositionOffset(isRaid, key)
    return ClampNumber(Option(isRaid, key), OPTION_DEFAULTS[key], -300, 300)
end

local function ApplyMarkerStyle(marker)
    local isRaid = marker._quiTargetedRaid and true or false
    local size = MarkerSize(isRaid)
    marker:SetSize(size, size)
    marker:SetFrameLevel((marker:GetParent():GetFrameLevel() or 0) + 12)

    if marker._border then
        marker._border:SetFrameLevel(marker:GetFrameLevel() + 1)
    end
    if marker._cooldown then
        marker._cooldown:SetReverse(Option(isRaid, "reverseSwipe") ~= false)
    end
end

local function NewMarker(frame, isRaid)
    local marker = CreateFrame("Frame", nil, frame)
    marker._quiTargetedRaid = isRaid and true or false
    marker:Hide()

    local texture = marker:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints()
    texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    marker._texture = texture

    local cooldown = CreateFrame("Cooldown", nil, marker, "CooldownFrameTemplate")
    cooldown:SetAllPoints()
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawSwipe(true)
    cooldown:SetSwipeColor(0, 0, 0, 0.6)
    cooldown:SetHideCountdownNumbers(true)
    marker._cooldown = cooldown

    local border = CreateFrame("Frame", nil, marker, "BackdropTemplate")
    border:SetAllPoints()
    border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    border:SetBackdropBorderColor(0, 0, 0, 1)
    marker._border = border

    ApplyMarkerStyle(marker)
    return marker
end

local function MarkerPool(frame, isRaid)
    local pool = markerPools[frame]
    if not pool then
        pool = { isRaid = isRaid and true or false }
        markerPools[frame] = pool
    end
    return pool
end

local function AcquireMarker(frame, isRaid)
    local pool = MarkerPool(frame, isRaid)

    for i = 1, #pool do
        if not pool[i]._targetedCaster then
            return pool[i]
        end
    end

    if #pool >= MarkerLimit(isRaid) then
        return nil
    end

    local marker = NewMarker(frame, isRaid)
    pool[#pool + 1] = marker
    return marker
end

local function PlaceFirstMarker(marker, host, point, x, y)
    if point == "TOPLEFT" then
        marker:SetPoint("TOPLEFT", host, "TOPLEFT", x, y)
    elseif point == "TOP" then
        marker:SetPoint("TOP", host, "TOP", x, y)
    elseif point == "TOPRIGHT" then
        marker:SetPoint("TOPRIGHT", host, "TOPRIGHT", x, y)
    elseif point == "LEFT" then
        marker:SetPoint("LEFT", host, "LEFT", x, y)
    elseif point == "RIGHT" then
        marker:SetPoint("RIGHT", host, "RIGHT", x, y)
    elseif point == "BOTTOMLEFT" then
        marker:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", x, y)
    elseif point == "BOTTOM" then
        marker:SetPoint("BOTTOM", host, "BOTTOM", x, y)
    elseif point == "BOTTOMRIGHT" then
        marker:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", x, y)
    else
        marker:SetPoint("CENTER", host, "CENTER", x, y)
    end
end

local function LayoutFrameMarkers(frame)
    local pool = markerPools[frame]
    if not pool then
        return
    end

    local isRaid = pool.isRaid and true or false
    local shown = 0
    for i = 1, #pool do
        if pool[i]._targetedCaster then
            shown = shown + 1
        end
    end
    if shown == 0 then
        return
    end

    local size = MarkerSize(isRaid)
    local spacing = MarkerSpacing(isRaid)
    local stride = size + spacing
    local grow = GrowthDirection(isRaid)
    local point = AnchorPoint(isRaid)
    local x = PositionOffset(isRaid, "offsetX")
    local y = PositionOffset(isRaid, "offsetY")
    local host = frame.healthBar or frame

    if grow == "CENTER" then
        x = x - ((shown - 1) * stride) / 2
    end

    local previous
    for i = 1, #pool do
        local marker = pool[i]
        if marker._targetedCaster then
            marker:ClearAllPoints()
            if not previous then
                PlaceFirstMarker(marker, host, point, x, y)
            elseif grow == "LEFT" then
                marker:SetPoint("RIGHT", previous, "LEFT", -spacing, 0)
            elseif grow == "UP" then
                marker:SetPoint("BOTTOM", previous, "TOP", 0, spacing)
            elseif grow == "DOWN" then
                marker:SetPoint("TOP", previous, "BOTTOM", 0, -spacing)
            else
                marker:SetPoint("LEFT", previous, "RIGHT", spacing, 0)
            end
            previous = marker
        end
    end
end

local function StopCooldown(cooldown)
    if not cooldown then
        return
    end
    if cooldown.Clear then
        pcall(cooldown.Clear, cooldown)
    end
    cooldown:Hide()
end

local function StartCooldown(cooldown, durationObject, startMS, endMS)
    if not cooldown then
        return
    end

    if durationObject and cooldown.SetCooldownFromDurationObject then
        local ok = pcall(cooldown.SetCooldownFromDurationObject, cooldown, durationObject)
        if ok then
            if durationObject.IsZero and cooldown.SetAlphaFromBoolean then
                cooldown:SetAlphaFromBoolean(durationObject:IsZero(), 0, 1)
            else
                cooldown:SetAlpha(1)
            end
            cooldown:SetDrawSwipe(true)
            cooldown:Show()
            return
        end
    end

    if IsSecretValue(startMS) or IsSecretValue(endMS)
        or type(startMS) ~= "number" or type(endMS) ~= "number"
        or endMS <= startMS then
        StopCooldown(cooldown)
        return
    end

    local start = startMS
    local duration = endMS - startMS
    if start > 100000 then
        start = start / 1000
        duration = duration / 1000
    end

    if cooldown.SetCooldown then
        cooldown:SetCooldown(start, duration)
        cooldown:Show()
    else
        StopCooldown(cooldown)
    end
end

---------------------------------------------------------------------------
-- Cast watching
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local activeByCaster = {}
local serialByCaster = {}
local watchedCaster = {}
local plateUnits = {}
local relayoutFrames = {}
local clearQueue = {}
local running = false

local function NextSerial(caster)
    local serial = (serialByCaster[caster] or 0) + 1
    serialByCaster[caster] = serial
    return serial
end

local function ReadCast(caster)
    local ok, spellName, _, texture, startMS, endMS = pcall(UnitCastingInfo, caster)
    if ok and spellName ~= nil then
        return spellName, texture, false, startMS, endMS
    end

    ok, spellName, _, texture, startMS, endMS = pcall(UnitChannelInfo, caster)
    if ok and spellName ~= nil then
        return spellName, texture, true, startMS, endMS
    end

    return nil
end

local function ReadDuration(caster, isChannel)
    local reader = isChannel and UnitChannelDuration or UnitCastingDuration
    if not reader then
        return nil
    end
    local ok, durationObject = pcall(reader, caster)
    if ok then
        return durationObject
    end
    return nil
end

local function SpellTargetIsDisplayable(caster)
    if not UnitShouldDisplaySpellTargetName then
        return true
    end

    local ok, display = pcall(UnitShouldDisplaySpellTargetName, caster)
    if ok and not IsSecretValue(display) and display == false then
        return false
    end
    return true
end

local function HideMarkerSet(markers)
    if not markers then
        return
    end

    wipe(relayoutFrames)
    for i = 1, #markers do
        local marker = markers[i]
        marker._targetedCaster = nil
        marker:Hide()
        StopCooldown(marker._cooldown)
        relayoutFrames[marker:GetParent()] = true
    end

    for frame in pairs(relayoutFrames) do
        LayoutFrameMarkers(frame)
    end
    wipe(relayoutFrames)
end

local function ClearCaster(caster)
    NextSerial(caster)
    watchedCaster[caster] = nil

    local markers = activeByCaster[caster]
    if markers then
        activeByCaster[caster] = nil
        HideMarkerSet(markers)
    end
end

local function ClearAllCasts()
    wipe(clearQueue)
    for caster in pairs(activeByCaster) do
        clearQueue[#clearQueue + 1] = caster
    end
    for caster in pairs(watchedCaster) do
        clearQueue[#clearQueue + 1] = caster
    end

    for i = 1, #clearQueue do
        ClearCaster(clearQueue[i])
    end
    wipe(clearQueue)
    wipe(watchedCaster)
end

local function ShowCastOnUnit(caster, unit, texture, durationObject, startMS, endMS)
    local frameList = GroupFrames.unitFrameMap and GroupFrames.unitFrameMap[unit]
    if not frameList then
        return
    end

    local markers
    for i = 1, #frameList do
        local frame = frameList[i]
        if frame and frame:IsShown() then
            local isRaid = frame._isRaid and true or false
            local marker = AcquireMarker(frame, isRaid)
            if marker then
                marker._targetedCaster = caster
                ApplyMarkerStyle(marker)

                if texture == nil then
                    marker._texture:SetTexture(FALLBACK_ICON)
                else
                    marker._texture:SetTexture(texture)
                end

                StartCooldown(marker._cooldown, durationObject, startMS, endMS)
                marker:Show()
                LayoutFrameMarkers(frame)

                if not markers then
                    markers = {}
                end
                markers[#markers + 1] = marker
            end
        end
    end

    if markers then
        markers.unit = unit
        activeByCaster[caster] = markers
    end
end

local function ResolveCastTarget(caster, expectedSerial)
    if serialByCaster[caster] ~= expectedSerial then
        return
    end

    local spellName, texture, isChannel, startMS, endMS = ReadCast(caster)
    if spellName == nil or not SpellTargetIsDisplayable(caster) then
        return
    end

    local unit = UnitFromCasterTarget(caster)
    if not unit then
        return
    end

    local current = activeByCaster[caster]
    if current and current.unit == unit then
        return
    end

    if current then
        activeByCaster[caster] = nil
        HideMarkerSet(current)
    end

    ShowCastOnUnit(caster, unit, texture, ReadDuration(caster, isChannel), startMS, endMS)
end

local function QueueResolve(caster, serial, delay)
    C_Timer.After(delay, function()
        ResolveCastTarget(caster, serial)
    end)
end

local function BeginCastWatch(caster)
    ClearCaster(caster)

    local ok, hostile = pcall(UnitCanAttack, "player", caster)
    if ok and not IsSecretValue(hostile) and hostile ~= true then
        return
    end
    if not SpellTargetIsDisplayable(caster) then
        return
    end

    watchedCaster[caster] = true
    local serial = serialByCaster[caster] or 0
    QueueResolve(caster, serial, TIMING.firstRead)
    QueueResolve(caster, serial, TIMING.firstRead + TIMING.verifyRead)
end

local function RecheckCasterTarget(caster)
    if not watchedCaster[caster] then
        return
    end

    local serial = NextSerial(caster)
    QueueResolve(caster, serial, TIMING.targetChangeRead)
    QueueResolve(caster, serial, TIMING.targetChangeRead + TIMING.verifyRead)
end

local function AdoptLiveCast(unit)
    if ReadCast(unit) ~= nil then
        BeginCastWatch(unit)
    end
end

local START_EVENTS = {
    UNIT_SPELLCAST_START = true,
    UNIT_SPELLCAST_CHANNEL_START = true,
}

local FINISH_EVENTS = {
    UNIT_SPELLCAST_STOP = true,
    UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_SPELLCAST_INTERRUPTED = true,
}

local WATCHED_EVENTS = {
    "NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED",
    "UNIT_TARGET",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_CHANNEL_START",
}

local function FeatureShouldRun()
    local db = GetGroupDB()
    if type(db) ~= "table" or db.enabled == false then
        return false
    end
    if not IsInGroup() then
        return false
    end

    local isRaid = IsInRaid() and true or false
    return Option(isRaid, "enabled") ~= false
end

local function SeedVisibleNameplates()
    if not C_NamePlate or not C_NamePlate.GetNamePlates then
        return
    end

    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" then
        return
    end

    for i = 1, #plates do
        local unit = plates[i] and plates[i].namePlateUnitToken
        if unit and not plateUnits[unit] then
            plateUnits[unit] = true
            AdoptLiveCast(unit)
        end
    end
end

local function SetWatchedEvents(enabled)
    for i = 1, #WATCHED_EVENTS do
        if enabled then
            eventFrame:RegisterEvent(WATCHED_EVENTS[i])
        else
            eventFrame:UnregisterEvent(WATCHED_EVENTS[i])
        end
    end
end

local function RefreshRuntimeState()
    local shouldRun = FeatureShouldRun()

    if shouldRun and not running then
        SetWatchedEvents(true)
        running = true
        IndexRoster()
        SeedVisibleNameplates()
    elseif not shouldRun and running then
        SetWatchedEvents(false)
        running = false
        ClearAllCasts()
        wipe(plateUnits)
    elseif shouldRun then
        IndexRoster()
        SeedVisibleNameplates()
    end
end

function TargetedSpells:ApplySettings()
    RefreshRuntimeState()
    if not running then
        return
    end

    for frame, pool in pairs(markerPools) do
        local hasActiveMarker = false
        for i = 1, #pool do
            if pool[i]._targetedCaster then
                ApplyMarkerStyle(pool[i])
                hasActiveMarker = true
            end
        end
        if hasActiveMarker then
            LayoutFrameMarkers(frame)
        end
    end
end

local function HandleNameplateAdded(unit)
    plateUnits[unit] = true
    AdoptLiveCast(unit)
end

local function HandleNameplateRemoved(unit)
    plateUnits[unit] = nil
    ClearCaster(unit)
end

local function HandleRosterChanged()
    IndexRoster()
    ClearAllCasts()
    RefreshRuntimeState()
end

local function HandleWorldChanged()
    ClearAllCasts()
    wipe(plateUnits)
    RefreshRuntimeState()
    if running then
        SeedVisibleNameplates()
    end
end

local BASE_EVENTS = {
    PLAYER_LOGIN = RefreshRuntimeState,
    GROUP_ROSTER_UPDATE = HandleRosterChanged,
    PLAYER_ROLES_ASSIGNED = HandleRosterChanged,
    PLAYER_ENTERING_WORLD = HandleWorldChanged,
    PLAYER_REGEN_ENABLED = ClearAllCasts,
    NAME_PLATE_UNIT_ADDED = HandleNameplateAdded,
    NAME_PLATE_UNIT_REMOVED = HandleNameplateRemoved,
}

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(_, event, unit)
    local baseHandler = BASE_EVENTS[event]
    if baseHandler then
        baseHandler(unit)
        return
    end

    if not plateUnits[unit] then
        return
    end

    if START_EVENTS[event] then
        BeginCastWatch(unit)
    elseif FINISH_EVENTS[event] then
        ClearCaster(unit)
    elseif event == "UNIT_TARGET" then
        RecheckCasterTarget(unit)
    end
end)
