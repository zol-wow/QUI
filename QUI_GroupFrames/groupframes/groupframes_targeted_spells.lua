local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local GroupFrames = ns.QUI_GroupFrames
if not GroupFrames then return end

local CreateFrame = CreateFrame
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitRace = UnitRace
local UnitSex = UnitSex
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
local CHROME_LEVELS = (ns.QUI_GroupFrameChrome and ns.QUI_GroupFrameChrome.LEVELS)
    or { TARGETED = 14 }

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
        return false -- @secret-policy: reject-secret-value
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

local MAX_NAMEPLATE_CASTERS = 150
local markerPools = setmetatable({}, { __mode = "k" })
local markerListsByCaster = {}
local activeByCaster = {}
local markerListCapacity = 0
local poolGrowthPending = false

for i = 1, MAX_NAMEPLATE_CASTERS do
    local caster = "nameplate" .. i
    markerListsByCaster[caster] = { count = 0, unit = false }
    activeByCaster[caster] = false
end

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
    marker:SetFrameLevel((marker:GetParent():GetFrameLevel() or 0) + CHROME_LEVELS.TARGETED)

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
    marker._targetedCaster = false
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

local function EnsureMarkerListCapacity(capacity)
    if capacity <= markerListCapacity then
        return
    end
    for _, markers in pairs(markerListsByCaster) do
        for i = markerListCapacity + 1, capacity do
            markers[i] = false
        end
    end
    markerListCapacity = capacity
end

local function PrepareFrame(frame, frameCopies)
    if not frame then
        return
    end
    if InCombatLockdown() then
        poolGrowthPending = true
        return
    end

    EnsureMarkerListCapacity(frameCopies or 1)
    local isRaid = frame._isRaid and true or false
    local pool = MarkerPool(frame, isRaid)
    local limit = MarkerLimit(isRaid)
    for i = #pool + 1, limit do
        pool[i] = NewMarker(frame, isRaid)
    end
end

local function PrepareMarkerPools()
    if InCombatLockdown() then
        poolGrowthPending = true
        return
    end

    poolGrowthPending = false
    for _, frameList in pairs(GroupFrames.unitFrameMap or {}) do
        for i = 1, #frameList do
            PrepareFrame(frameList[i], #frameList)
        end
    end
end

local function AcquireMarker(frame, isRaid)
    local pool = markerPools[frame]
    if not pool then
        if InCombatLockdown() then
            poolGrowthPending = true
            return nil
        end
        pool = MarkerPool(frame, isRaid)
    end

    local limit = MarkerLimit(isRaid)
    for i = 1, limit do
        local marker = pool[i]
        if not marker then
            if InCombatLockdown() then
                poolGrowthPending = true
                return nil
            end
            marker = NewMarker(frame, isRaid)
            pool[i] = marker
        end
        if not marker._targetedCaster then
            return marker
        end
    end
    return nil
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
    ns.SafeCallMethodIfPresent("best-effort-style", cooldown, "Clear")
    cooldown:Hide()
end

local function StartCooldown(cooldown, durationObject, startMS, endMS)
    if not cooldown then
        return
    end

    -- still routed to the SetCooldownFromDurationObject sink.
    local durSecret = IsSecretValue(durationObject)
    if (durSecret or durationObject) and cooldown.SetCooldownFromDurationObject then
        local ok = pcall(cooldown.SetCooldownFromDurationObject, cooldown, durationObject)
        if ok then
            if not durSecret and durationObject.IsZero and cooldown.SetAlphaFromBoolean then
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

-- Detection (nameplate tracking, cast events, delayed target reads, secret
-- handling) lives in the shared ns.IncomingCasts engine. This module only
-- resolves which group member a cast is aimed at and renders the markers.
local SUBSCRIBER_KEY = "groupFrameTargetedSpells"

local subscribed = false

local function HideMarkerSet(markers)
    if not markers then
        return
    end

    for i = 1, markers.count do
        local marker = markers[i]
        local frame = marker:GetParent()
        marker._targetedCaster = false
        marker:Hide()
        StopCooldown(marker._cooldown)
        markers[i] = false
        LayoutFrameMarkers(frame)
    end

    markers.count = 0
    markers.unit = false
end

local function ClearAllMarkers()
    for caster, markers in pairs(activeByCaster) do
        if markers then
            activeByCaster[caster] = false
            HideMarkerSet(markers)
        end
    end
end

local function ShowCastOnUnit(caster, unit, texture, durationObject, startMS, endMS)
    local frameList = GroupFrames.unitFrameMap and GroupFrames.unitFrameMap[unit]
    if not frameList then
        return
    end

    local markers = markerListsByCaster[caster]
    if not markers then
        if InCombatLockdown() then
            poolGrowthPending = true
            return
        end
        markers = { count = 0, unit = false }
        markerListsByCaster[caster] = markers
        for i = 1, markerListCapacity do
            markers[i] = false
        end
    end

    local markerCount = 0
    for i = 1, #frameList do
        local frame = frameList[i]
        if frame and frame:IsShown() then
            if markerCount >= markerListCapacity then
                if InCombatLockdown() then
                    poolGrowthPending = true
                    break
                end
                EnsureMarkerListCapacity(markerCount + 1)
            end
            local isRaid = frame._isRaid and true or false
            local marker = AcquireMarker(frame, isRaid)
            if marker then
                marker._targetedCaster = caster
                ApplyMarkerStyle(marker)

                if IsSecretValue(texture) then
                    marker._texture:SetTexture(texture) -- @secret-policy: sink-forward — never compare a secret texture
                elseif texture == nil then
                    marker._texture:SetTexture(FALLBACK_ICON)
                else
                    marker._texture:SetTexture(texture)
                end

                StartCooldown(marker._cooldown, durationObject, startMS, endMS)
                marker:Show()
                LayoutFrameMarkers(frame)

                markerCount = markerCount + 1
                markers[markerCount] = marker
            end
        end
    end

    markers.count = markerCount
    if markerCount > 0 then
        markers.unit = unit
        activeByCaster[caster] = markers
    end
end

local function OnCastShow(caster, unit, cast)
    local current = activeByCaster[caster]
    if current then
        activeByCaster[caster] = false
        HideMarkerSet(current)
    end
    ShowCastOnUnit(caster, unit, cast.texture, cast.durationObj, cast.startMS, cast.endMS)
end

local function OnCastHide(caster)
    local markers = activeByCaster[caster]
    if markers then
        activeByCaster[caster] = false
        HideMarkerSet(markers)
    end
end

local function ResolveGroupTarget(caster)
    -- The narrowing cascade cannot distinguish "not a group member" from
    -- "unreadable", so it never returns false; markers persist until the cast
    -- ends or the target resolves to a different member.
    return UnitFromCasterTarget(caster)
end

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

local function RefreshRuntimeState()
    local IncomingCasts = ns.IncomingCasts
    if not IncomingCasts then
        return
    end

    local shouldRun = FeatureShouldRun()
    if shouldRun then
        PrepareMarkerPools()
    end
    if shouldRun and not subscribed then
        IndexRoster()
        subscribed = IncomingCasts.Subscribe(SUBSCRIBER_KEY, {
            resolveTarget = ResolveGroupTarget,
            onShow = OnCastShow,
            onHide = OnCastHide,
        }) == true
        if subscribed then
            -- pick up casts already in flight when the engine was running
            -- for another subscriber before this one joined
            IncomingCasts.ResetSubscriber(SUBSCRIBER_KEY)
        end
    elseif not shouldRun and subscribed then
        IncomingCasts.Unsubscribe(SUBSCRIBER_KEY)
        subscribed = false
        ClearAllMarkers()
    elseif shouldRun then
        IndexRoster()
    end
end

function TargetedSpells:ApplySettings()
    RefreshRuntimeState()
    if not subscribed then
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

function TargetedSpells:PrepareFrame(frame, frameCopies)
    if subscribed then
        PrepareFrame(frame, frameCopies)
    end
end

-- Roster shape, roles, and world changes invalidate both the class-bucket
-- index and any marker-to-frame mapping; markers rebuild from the engine's
-- in-flight casts via ResetSubscriber.
local function HandleContextChanged()
    ClearAllMarkers()
    RefreshRuntimeState()
    if subscribed and ns.IncomingCasts then
        ns.IncomingCasts.ResetSubscriber(SUBSCRIBER_KEY)
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if poolGrowthPending then
            if FeatureShouldRun() then
                PrepareMarkerPools()
            else
                poolGrowthPending = false
            end
        end
        return
    end
    HandleContextChanged()
end)
