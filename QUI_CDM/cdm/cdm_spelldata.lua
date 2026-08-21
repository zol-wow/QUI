local _, ns = ...
local Helpers = ns.Helpers
local Sources = ns.CDMSources
local Shared = ns.CDMShared
local GetTime = GetTime

local function IsCDMRuntimeEnabled()
    return not Shared or Shared.IsRuntimeEnabled()
end

local cooldownViewerCVarFrame = CreateFrame("Frame")
cooldownViewerCVarFrame.dataEverLoaded = false
cooldownViewerCVarFrame:RegisterEvent("VARIABLES_LOADED")
cooldownViewerCVarFrame:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED")

local function IsCooldownViewerCVarEnabled()
    if GetCVarBool then
        local value = GetCVarBool("cooldownViewerEnabled")
        if value ~= nil then
            return value and true or false
        end
    end

    if GetCVar then
        local value = GetCVar("cooldownViewerEnabled")
        return tostring(value) == "1"
    end

    return nil
end

local function SyncCooldownViewerCVarToMasterToggle()
    local target = 1
    local current = IsCooldownViewerCVarEnabled()
    if current ~= nil and ((target == 0 and current == false) or (target == 1 and current == true)) then
        return true
    end

    local dataLoaded = cooldownViewerCVarFrame.dataEverLoaded
    if not dataLoaded then
        local catalog = ns.CDMCatalog
        if catalog and catalog.IsCooldownViewerReady and catalog.IsCooldownViewerReady() then
            cooldownViewerCVarFrame.dataEverLoaded = true
            dataLoaded = true
        end
    end
    if dataLoaded then
        return false
    end

    if SetCVar then
        SetCVar("cooldownViewerEnabled", target)
    end

    return true
end

cooldownViewerCVarFrame:SetScript("OnEvent", function(self, event)
    if event == "COOLDOWN_VIEWER_DATA_LOADED" then
        self.dataEverLoaded = true
        self:UnregisterEvent("COOLDOWN_VIEWER_DATA_LOADED")
        return
    end
    if event == "VARIABLES_LOADED" then
        self:UnregisterEvent("VARIABLES_LOADED")
        SyncCooldownViewerCVarToMasterToggle()
    end
end)

local CDMSpellData = {}
CDMSpellData.SyncCooldownViewerCVar = SyncCooldownViewerCVarToMasterToggle

CDMSpellData._cdmCooldownLearnedPreferred = {}

CDMSpellData._cdmAuraLearnedFamily = {}
CDMSpellData._cdmAuraLearnedCatalogReady = false

CDMSpellData._cdmClassApplicableSpellFamily = {}
CDMSpellData._cdmClassApplicableCatalogReady = false

local _inZoneTransition = false
local _spellsChangedDuringZoneTransition = false

local COLD_LOAD_SNAPSHOT_RETRY_DELAY = 0.5
local COLD_LOAD_SNAPSHOT_RETRY_MAX_ATTEMPTS = 20
local COLD_LOAD_SNAPSHOT_RETRY_SLOW_DELAY = 2.0
local BLIZZARD_CDM_ENTRY_SOURCE = "blizzardCDM"

local function IsBuiltinContainerKey(containerKey)
    if Shared and Shared.IsBuiltinContainerKey then
        return Shared.IsBuiltinContainerKey(containerKey)
    end
    return Shared and Shared.GetBuiltinContainerEntryKind
        and Shared.GetBuiltinContainerEntryKind(containerKey) ~= nil
        or false
end

local function GetBuiltinContainerKeys()
    if Shared and Shared.BUILTIN_CONTAINER_KEYS then
        return Shared.BUILTIN_CONTAINER_KEYS
    end
    return {}
end

local function GetBuiltinContainerEntryKind(containerKey)
    if Shared and Shared.GetBuiltinContainerEntryKind then
        return Shared.GetBuiltinContainerEntryKind(containerKey)
    end
    return nil
end

local function IsBuiltinAuraContainerKey(containerKey)
    return GetBuiltinContainerEntryKind(containerKey) == "aura"
end

local runtimeEventFrame = nil
local initialized = false
local FireChangeCallback

local STACK_SEARCH_UNITS = { "player", "pet" }
local SELF_AURA_CAPTURE_LOOKUP_UNITS = { "player", "pet" }
local AURA_CAPTURE_LOOKUP_UNITS = { "player", "pet", "target" }

local _capturedAuraBySpellID = {}
local _capturedAuraByName    = {}
local _capturedAuraByUnitSpellID = {}
local _capturedAuraByUnitName    = {}
local _capturedAuraByUnitInstanceID = {}
local TARGET_CAPTURED_AURA_FILTERS = { HELPFUL = true, HARMFUL = true }
local DEFAULT_CAPTURED_AURA_FILTERS = {
    player = "HELPFUL",
    pet = "HELPFUL",
    target = TARGET_CAPTURED_AURA_FILTERS,
}

local function IsUsableTableKey(key)
    if issecretvalue and issecretvalue(key) then return false end -- @secret-policy: reject-secret-ids
    if not key then return false end
    return true
end

local function IsUsableSpellIDKey(spellID)
    return IsUsableTableKey(spellID)
        and type(spellID) == "number"
end

local function IsUsableAuraName(name)
    return type(name) == "string"
end

local function GetCleanAuraSpellID(auraData)
    if not auraData then return nil end
    local sid = auraData.spellId
    if issecretvalue and issecretvalue(sid) then return nil end -- @secret-policy: reject-secret-ids
    if not sid then
        sid = auraData.spellID
    end
    return IsUsableSpellIDKey(sid) and sid or nil
end

local function GetCleanAuraName(auraData)
    if not auraData then return nil end
    local name = auraData.name
    if issecretvalue and issecretvalue(name) then return nil end -- @secret-policy: reject-secret-ids
    return IsUsableAuraName(name) and name or nil
end

local function GetCleanAuraInstanceID(auraData)
    if not auraData then return nil end
    local instID = auraData.auraInstanceID
    if issecretvalue and issecretvalue(instID) then return nil end -- @secret-policy: reject-secret-ids
    return instID
end

local function GetRawAuraInstanceID(auraData)
    if not auraData then return nil end
    return auraData.auraInstanceID
end

local function GetCleanAuraApplications(auraData)
    if not auraData then return nil end
    local apps = auraData.applications
    if issecretvalue and issecretvalue(apps) then return nil end -- @secret-policy: reject-secret-value
    return apps
end

local function GetDisplayableAuraApplications(auraData)
    local apps = GetCleanAuraApplications(auraData)
    if apps == nil then return nil end
    local appType = type(apps)
    if appType == "number" then
        return apps > 1 and apps or nil
    end
    if appType == "string" then
        if apps == "" or apps == "0" or apps == "1" then
            return nil
        end
        return apps
    end
    return nil
end

local function IsStrictOwnedAuraSource(auraData)
    if not auraData then return false end
    return Helpers.IsAuraOwnedByPlayerOrPet(auraData, true) == true
end

local function IsDefaultCapturedUnit(unit)
    return unit == "player" or unit == "pet"
end

local function GetCapturedUnitMap(root, unit)
    if type(unit) ~= "string" or unit == "" then return nil end
    local map = root[unit]
    if not map then
        map = {}
        root[unit] = map
    end
    return map
end

local function AuraInstancePassesFilter(unit, auraInstanceID, filter)
    return nil
end

local function TargetAuraMatchesPlayerFilter(auraData, filter)
    if not auraData then return false end
    local playerFilter = filter or "HARMFUL"
    if type(playerFilter) == "string"
        and not playerFilter:find("PLAYER", 1, true) then
        playerFilter = playerFilter .. "|PLAYER"
    end
    local instID = GetCleanAuraInstanceID(auraData)
    if instID then
        local passes = AuraInstancePassesFilter("target", instID, playerFilter)
        if passes ~= nil then return passes end
    end
    return IsStrictOwnedAuraSource(auraData)
end

local function NormalizeCapturedAuraFilter(filter)
    if filter == "HELPFUL" or filter == "HARMFUL" then
        return filter
    end
    return nil
end

local function ResolveCapturedAuraFilter(unit, ad, instID, explicitFilter)
    local filter = NormalizeCapturedAuraFilter(explicitFilter)
    if filter then return filter end

    if ad then
        local isHelpful = ad.isHelpful
        if issecretvalue and issecretvalue(isHelpful) then isHelpful = nil end -- @secret-policy: reject-secret-value
        if isHelpful == true then return "HELPFUL" end
        local isHarmful = ad.isHarmful
        if issecretvalue and issecretvalue(isHarmful) then isHarmful = nil end -- @secret-policy: reject-secret-value
        if isHarmful == true then return "HARMFUL" end
    end

    if AuraInstancePassesFilter(unit, instID, "HELPFUL") == true then
        return "HELPFUL"
    end
    if AuraInstancePassesFilter(unit, instID, "HARMFUL") == true then
        return "HARMFUL"
    end
    return nil
end

local function CapturePayloadAllowedForUnit(unit, auraData, auraFilter)
    if unit ~= "target" then return true end
    if auraFilter ~= "HELPFUL" and auraFilter ~= "HARMFUL" then return false end
    return TargetAuraMatchesPlayerFilter(auraData, auraFilter)
end

local function CapturedAuraMatchesFilter(entry, allowedFiltersByUnit)
    if not entry then return false end
    if allowedFiltersByUnit == false then return true end

    local unit = entry.unit
    local allowed = allowedFiltersByUnit and allowedFiltersByUnit[unit]
    if allowed == nil then
        allowed = DEFAULT_CAPTURED_AURA_FILTERS[unit]
    end
    if allowed == nil or allowed == true then return true end

    local filter = entry.filter
    if type(allowed) == "table" then
        return filter ~= nil and allowed[filter] == true
    end
    return filter == allowed
end

local CAST_CORRELATION_WINDOW = 0.1

local _recentCasts = {}

local function ClearDeprecatedLearnedCastToAuraDB()
    local QUI = ns.Addon
    if not QUI or not QUI.db or not QUI.db.global then return nil end
    if QUI.db.global.cdmLearnedCastToAura ~= nil then
        QUI.db.global.cdmLearnedCastToAura = nil
    end
end

local function PruneRecentCasts(now)
    local cutoff = now - CAST_CORRELATION_WINDOW
    while _recentCasts[1] and _recentCasts[1].time < cutoff do
        table.remove(_recentCasts, 1)
    end
end

local function RecordPlayerCast(spellID)
    if not IsUsableSpellIDKey(spellID) then return end
    local now = GetTime()
    PruneRecentCasts(now)
    _recentCasts[#_recentCasts + 1] = { spellID = spellID, time = now }
end

local function FindCorrelatedCast(now)
    PruneRecentCasts(now)
    local last = _recentCasts[#_recentCasts]
    if last then return last.spellID end
    return nil
end

local function StoreCapturedSpellKey(unit, spellID, entry)
    if not IsUsableSpellIDKey(spellID) then return end
    local unitMap = GetCapturedUnitMap(_capturedAuraByUnitSpellID, unit)
    if unitMap then
        unitMap[spellID] = entry
    end
    if IsDefaultCapturedUnit(unit) then
        _capturedAuraBySpellID[spellID] = entry
    end
end

local function StoreCapturedNameKey(unit, nameKey, entry)
    if not IsUsableTableKey(nameKey) then return end
    local unitMap = GetCapturedUnitMap(_capturedAuraByUnitName, unit)
    if unitMap then
        unitMap[nameKey] = entry
    end
    if IsDefaultCapturedUnit(unit) then
        _capturedAuraByName[nameKey] = entry
    end
end

local function CaptureAuraFromPayload(unit, ad, allowCastCorrelation, explicitFilter)
    if not ad then return end
    local instID = GetRawAuraInstanceID(ad)
    if issecretvalue and issecretvalue(instID) then return end
    if not instID then return end

    local sid = GetCleanAuraSpellID(ad)
    local nameRaw = GetCleanAuraName(ad)
    local name, nameKey
    local cleanName, cleanNameKey = (function()
        if type(nameRaw) == "string" and nameRaw ~= "" then
            return nameRaw, nameRaw:lower()
        end
        return nil, nil
    end)()
    if cleanName and IsUsableTableKey(cleanNameKey) then
        name = cleanName
        nameKey = cleanNameKey
    end

    local auraFilter = ResolveCapturedAuraFilter(unit, ad, instID, explicitFilter)
    if not CapturePayloadAllowedForUnit(unit, ad, auraFilter) then
        return
    end

    local castSID
    if allowCastCorrelation == nil then
        allowCastCorrelation = unit == "player" and auraFilter == "HELPFUL"
    end
    if allowCastCorrelation then
        castSID = FindCorrelatedCast(GetTime())
    end

    if not sid and not name and not castSID then return end

    local entry = {
        auraInstanceID = instID,
        unit = unit,
        spellID = sid or castSID,
        name = name,
        filter = auraFilter,
        auraData = ad,
    }
    if sid then
        StoreCapturedSpellKey(unit, sid, entry)
    end
    if nameKey then
        StoreCapturedNameKey(unit, nameKey, entry)
    end
    if castSID and castSID ~= sid and not _capturedAuraBySpellID[castSID] then
        StoreCapturedSpellKey(unit, castSID, entry)
    end
    local instMap = GetCapturedUnitMap(_capturedAuraByUnitInstanceID, unit)
    if instMap then
        instMap[instID] = entry
    end
end

local function ReleaseCapturedAurasForUnit(unit)
    if type(unit) ~= "string" or unit == "" then return end
    for k, entry in pairs(_capturedAuraBySpellID) do
        if entry and entry.unit == unit then
            _capturedAuraBySpellID[k] = nil
        end
    end
    for k, entry in pairs(_capturedAuraByName) do
        if entry and entry.unit == unit then
            _capturedAuraByName[k] = nil
        end
    end
    local unitSpellMap = _capturedAuraByUnitSpellID[unit]
    if unitSpellMap then wipe(unitSpellMap) end
    local unitNameMap = _capturedAuraByUnitName[unit]
    if unitNameMap then wipe(unitNameMap) end
    local unitInstMap = _capturedAuraByUnitInstanceID[unit]
    if unitInstMap then wipe(unitInstMap) end
end

local function ReleaseCapturedEntry(entry)
    if not entry then return end
    for k, v in pairs(_capturedAuraBySpellID) do
        if v == entry then _capturedAuraBySpellID[k] = nil end
    end
    for k, v in pairs(_capturedAuraByName) do
        if v == entry then _capturedAuraByName[k] = nil end
    end
    for _, map in pairs(_capturedAuraByUnitSpellID) do
        for k, v in pairs(map) do
            if v == entry then map[k] = nil end
        end
    end
    for _, map in pairs(_capturedAuraByUnitName) do
        for k, v in pairs(map) do
            if v == entry then map[k] = nil end
        end
    end
    local instMap = _capturedAuraByUnitInstanceID[entry.unit]
    if instMap and entry.auraInstanceID ~= nil
        and instMap[entry.auraInstanceID] == entry then
        instMap[entry.auraInstanceID] = nil
    end
end

local function ReleaseCapturedAurasByInstanceIDsForUnit(unit, auraInstanceIDs)
    if type(unit) ~= "string" or unit == "" then return false end
    if type(auraInstanceIDs) ~= "table" then return false end

    local instMap = _capturedAuraByUnitInstanceID[unit]
    if not instMap then return false end

    local released = false
    for _, auraInstanceID in ipairs(auraInstanceIDs) do
        if auraInstanceID ~= nil then
            local entry = instMap[auraInstanceID]
            if entry then
                ReleaseCapturedEntry(entry)
                released = true
            end
        end
    end
    return released
end

local function ReleaseCapturedAuraByInstanceID(unit, auraInstanceID)
    local instMap = _capturedAuraByUnitInstanceID[unit]
    local entry = instMap and instMap[auraInstanceID]
    if entry then ReleaseCapturedEntry(entry) end
end

local function CollectCurrentAuras(unit)
    local glue = ns.AuraGlue
    return glue and glue.CollectReadableAuras
        and glue.CollectReadableAuras(unit) or nil
end

local function RescanCapturedAurasForUnit(unit, updateInfo)
    if not updateInfo or not updateInfo.addedAuras
        or (issecretvalue and issecretvalue(updateInfo.addedAuras)) then
        local current = CollectCurrentAuras(unit)
        if not current then return false end
        ReleaseCapturedAurasForUnit(unit)
        for _, item in ipairs(current) do
            CaptureAuraFromPayload(unit, item[1], nil, item[2])
        end
        return true
    end
    for _, ad in ipairs(updateInfo.addedAuras) do
        CaptureAuraFromPayload(unit, ad)
    end
    return false
end

local function RefreshCapturedAurasByInstanceIDs(unit, instanceIDs)
    local glue = ns.AuraGlue
    local refresh = glue and glue.ReadAurasByInstanceID
    if not refresh then return false end
    return refresh(unit, instanceIDs, function(auraData, auraInstanceID)
        ReleaseCapturedAuraByInstanceID(unit, auraInstanceID)
        if auraData then CaptureAuraFromPayload(unit, auraData) end
    end)
end

local function NotifyAuraConsumers(unit, updateInfo)
    local icons = ns.CDMIcons
    if icons and icons.HandleRuntimeRefresh then
        icons.HandleRuntimeRefresh("UNIT_AURA", unit, updateInfo)
    end
    local glows = ns._OwnedGlows
    if glows and glows.HandleUnitAuraChanged then
        glows.HandleUnitAuraChanged(unit, updateInfo)
    end
end

local REGISTERED_UNITS = { "player", "pet", "target" }

local function AnyDeltaElementSecret(arr, isAuraData)
    if not arr then return false end
    for i = 1, #arr do
        local v = arr[i]
        if issecretvalue(v) then return true end -- @secret-policy: report-secret-detected
        if isAuraData and v ~= nil
            and (issecretvalue(v.auraInstanceID)
                or issecretvalue(v.spellId)
                or issecretvalue(v.spellID)) then
            return true
        end
    end
    return false
end

local function HandleUnitAura(unit, updateInfo)
    if updateInfo and issecretvalue and issecretvalue(updateInfo.isFullUpdate) then
        updateInfo = nil
    end
    if updateInfo and issecretvalue
        and (issecretvalue(updateInfo.addedAuras)
            or issecretvalue(updateInfo.updatedAuraInstanceIDs)
            or issecretvalue(updateInfo.removedAuraInstanceIDs)) then
        updateInfo = nil
    end
    if updateInfo and issecretvalue
        and (AnyDeltaElementSecret(updateInfo.addedAuras, true)
            or AnyDeltaElementSecret(updateInfo.updatedAuraInstanceIDs)
            or AnyDeltaElementSecret(updateInfo.removedAuraInstanceIDs)) then
        updateInfo = nil
    end
    if not updateInfo or updateInfo.isFullUpdate then
        RescanCapturedAurasForUnit(unit, updateInfo)
        NotifyAuraConsumers(unit, updateInfo)
        return
    end
    if updateInfo.addedAuras and not (issecretvalue and issecretvalue(updateInfo.addedAuras)) then
        local refreshed = false
        if updateInfo.updatedAuraInstanceIDs
            and not (issecretvalue and issecretvalue(updateInfo.updatedAuraInstanceIDs))
            and #updateInfo.updatedAuraInstanceIDs > 0 then
            refreshed = RefreshCapturedAurasByInstanceIDs(unit, updateInfo.updatedAuraInstanceIDs)
        end
        if not refreshed then
            for _, ad in ipairs(updateInfo.addedAuras) do
                CaptureAuraFromPayload(unit, ad)
            end
        end
    elseif updateInfo.updatedAuraInstanceIDs
        and not (issecretvalue and issecretvalue(updateInfo.updatedAuraInstanceIDs))
        and #updateInfo.updatedAuraInstanceIDs > 0 then
        RefreshCapturedAurasByInstanceIDs(unit, updateInfo.updatedAuraInstanceIDs)
    end
    if updateInfo.removedAuraInstanceIDs
        and not (issecretvalue and issecretvalue(updateInfo.removedAuraInstanceIDs))
        and #updateInfo.removedAuraInstanceIDs > 0 then
        local released = ReleaseCapturedAurasByInstanceIDsForUnit(unit, updateInfo.removedAuraInstanceIDs)
    end
    NotifyAuraConsumers(unit, updateInfo)
end

local auraCaptureFrame = CreateFrame("Frame")
local function AuraCaptureFrameOnEvent(self, event, ...)
    if not IsCDMRuntimeEnabled() then
        return
    end

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, _, spellID = ...
        RecordPlayerCast(spellID)
        return
    end
    if event == "PLAYER_TARGET_CHANGED" then
        ReleaseCapturedAurasForUnit("target")
        NotifyAuraConsumers("target", nil)
        return
    end
    if event ~= "UNIT_AURA" then return end
    local unit, updateInfo = ...
    if issecretvalue and issecretvalue(unit) then
        for i = 1, #REGISTERED_UNITS do
            HandleUnitAura(REGISTERED_UNITS[i], nil)
        end
        return
    end
    if issecretvalue and issecretvalue(updateInfo) then
        updateInfo = nil
    end
    HandleUnitAura(unit, updateInfo)
end

local function RegisterAuraCaptureFrame()
    auraCaptureFrame:SetScript("OnEvent", AuraCaptureFrameOnEvent)
    auraCaptureFrame:RegisterUnitEvent("UNIT_AURA", "player", "pet", "target")
    auraCaptureFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    auraCaptureFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
end

RegisterAuraCaptureFrame()

function CDMSpellData:DisableRuntime()
    initialized = false
    cooldownViewerCVarFrame:UnregisterAllEvents()
    auraCaptureFrame:UnregisterAllEvents()
    auraCaptureFrame:SetScript("OnEvent", nil)
    if runtimeEventFrame then
        runtimeEventFrame:UnregisterAllEvents()
        runtimeEventFrame:SetScript("OnEvent", nil)
        runtimeEventFrame = nil
    end
end

local function GetCapturedAuraForLookup(spellIDs, entryName, preferredUnits, allowGlobalFallback, allowedFiltersByUnit)
    if preferredUnits then
        for unitIdx = 1, #preferredUnits do
            local unit = preferredUnits[unitIdx]
            local spellMap = _capturedAuraByUnitSpellID[unit]
            if spellMap and spellIDs then
                for i = 1, #spellIDs do
                    local sid = spellIDs[i]
                    if IsUsableTableKey(sid) then
                        local entry = spellMap[sid]
                        if entry and entry.auraInstanceID
                           and CapturedAuraMatchesFilter(entry, allowedFiltersByUnit) then
                            return entry
                        end
                    end
                end
            end
            local nameMap = _capturedAuraByUnitName[unit]
            if nameMap and type(entryName) == "string" then
                local nameKey = (function()
                    if entryName ~= "" then
                        return entryName:lower()
                    end
                    return nil
                end)()
                if IsUsableTableKey(nameKey) then
                    local entry = nameMap[nameKey]
                    if entry and entry.auraInstanceID
                       and CapturedAuraMatchesFilter(entry, allowedFiltersByUnit) then
                        return entry
                    end
                end
            end
        end
    end

    if allowGlobalFallback == false then
        return nil
    end

    if spellIDs then
        for i = 1, #spellIDs do
            local sid = spellIDs[i]
            if IsUsableTableKey(sid) then
                local entry = _capturedAuraBySpellID[sid]
                if entry and entry.auraInstanceID
                   and CapturedAuraMatchesFilter(entry, allowedFiltersByUnit) then
                    return entry
                end
            end
        end
    end
    if type(entryName) == "string" then
        local nameKey = (function()
            if entryName ~= "" then
                return entryName:lower()
            end
            return nil
        end)()
        if IsUsableTableKey(nameKey) then
            local entry = _capturedAuraByName[nameKey]
            if entry and entry.auraInstanceID
               and CapturedAuraMatchesFilter(entry, allowedFiltersByUnit) then
                return entry
            end
        end
    end
    return nil
end

local function GetReadableAuraDurationState(auraData)
    if not auraData then return nil end
    local duration = auraData.duration
    if issecretvalue and issecretvalue(duration) then
        return nil -- @secret-policy: reject-secret-value
    end
    if duration == nil then
        return false
    end
    if type(duration) ~= "number" then
        return nil
    end
    if InCombatLockdown() then
        return nil
    end
    local hasNoDuration = duration <= 0
    if hasNoDuration then
        return false
    end
    return true
end

local function ApplyAuraExpirationState(result, auraUnit, auraInstanceID, auraData)
    local hasExpiration = GetReadableAuraDurationState(auraData)
    if hasExpiration ~= nil then
        result.hasExpirationTime = hasExpiration
        if hasExpiration == false then
            result.hideDurationText = true
        end
    end
    return hasExpiration
end

local IsAuraOwnedByPlayerOrPet = Helpers.IsAuraOwnedByPlayerOrPet

local function IsSelfUnit(auraUnit)
    return auraUnit == "player" or auraUnit == "pet" or auraUnit == "vehicle"
end

local function FilterWantsToken(filter, token)
    return type(filter) == "string"
        and type(token) == "string"
        and filter:find(token, 1, true) ~= nil
end

local function LookupCapturedAuraBySpellID(unit, spellID, filter)
    if not unit or not spellID then
        return nil
    end
    local allowed = {}
    allowed[unit] = unit == "target"
        and { HELPFUL = true, HARMFUL = true }
        or (filter == "HARMFUL" and "HARMFUL" or "HELPFUL")
    return GetCapturedAuraForLookup({ spellID }, nil, { unit }, false, allowed)
end

local function QueryCapturedAuraByName(unit, name, filter)
    if not unit or not IsUsableAuraName(name) then return nil end
    local allowed = {}
    allowed[unit] = unit == "target"
        and { HELPFUL = true, HARMFUL = true }
        or (filter == "HARMFUL" and "HARMFUL" or "HELPFUL")
    return GetCapturedAuraForLookup(nil, name, { unit }, false, allowed)
end

local function GetCapturedAuraData(entry)
    return entry and (entry.auraData or entry) or nil
end

local function IsUsableResolvedAuraData(auraUnit, auraData)
    if not auraData then return false end
    if IsSelfUnit(auraUnit) then
        return true
    end
    return IsAuraOwnedByPlayerOrPet(auraData, true)
end

local function ResolveAuraInstanceDurationState(result, auraUnit, auraInstanceID, auraData)
    if not auraUnit or not auraInstanceID then
        return false, nil
    end

    local hasExpiration = ApplyAuraExpirationState(result, auraUnit, auraInstanceID, auraData)
    if hasExpiration == false then
        return true, nil
    end

    if InCombatLockdown() then
        result.durationStateUnknown = true
        return true, nil
    end

    return true, nil
end

local function GetAuraApplications(unit, auraInstanceID)
    return false, nil
end

local function GetOwnedTargetFilter(filter)
    local base = filter or "HARMFUL"
    if FilterWantsToken(base, "PLAYER") then
        return base
    end
    return base .. "|PLAYER"
end

local function IsUsableTargetAuraData(auraData, filter)
    if not auraData then return false end
    return TargetAuraMatchesPlayerFilter(auraData, filter or "HARMFUL|PLAYER")
end

local function ScanOwnedTargetAuraBySpellID(spellID, filter)
    if not IsUsableSpellIDKey(spellID) then return nil end
    return GetCapturedAuraForLookup({ spellID }, nil, { "target" }, false,
        { target = { HELPFUL = true, HARMFUL = true } })
end

local function ScanOwnedTargetAuraByName(spellName, filter)
    if not IsUsableAuraName(spellName) then return nil end
    return GetCapturedAuraForLookup(nil, spellName, { "target" }, false,
        { target = { HELPFUL = true, HARMFUL = true } })
end

local function FindOwnedTargetAuraBySpellID(spellID, filter)
    if not spellID then return nil end

    local directFilter = GetOwnedTargetFilter(filter)
    local ad = LookupCapturedAuraBySpellID("target", spellID, directFilter)
    if ad then return ad end

    return ScanOwnedTargetAuraBySpellID(spellID, filter)
end

local function FindOwnedTargetAuraByName(spellName, filter)
    if not IsUsableAuraName(spellName) then return nil end
    return ScanOwnedTargetAuraByName(spellName, filter)
end

local function SafeMaybeNumber(value)
    return type(value) == "number" and value or tonumber(value)
end

local _linkedSpellIDCache = {}
local _linkedSpellIDCacheVersion = nil

local function GetLinkedSpellIDsForSpellID(spellID)
    local index = ns.CDMIndex
    local catalog = ns.CDMCatalog
    if not (index and index.Get and index.Version and catalog and catalog.GetCooldownInfo) then
        return nil
    end
    if not IsUsableSpellIDKey(spellID) then return nil end

    local version = index.Version()
    if version ~= _linkedSpellIDCacheVersion then
        wipe(_linkedSpellIDCache)
        _linkedSpellIDCacheVersion = version
    end

    local cached = _linkedSpellIDCache[spellID]
    if cached ~= nil then
        return cached or nil
    end

    local mapped = index.Get(spellID)
    local cooldownID = mapped and mapped.cooldownID
    local linked
    if IsUsableTableKey(cooldownID) then
        local info = catalog.GetCooldownInfo(cooldownID)
        if info then
            if type(info.linkedSpellIDs) == "table" then
                linked = info.linkedSpellIDs
            end
            local activeLinkedID = info.linkedSpellID
            if IsUsableSpellIDKey(activeLinkedID) then
                if not linked then
                    linked = { activeLinkedID }
                else
                    local found = false
                    for _, linkedID in ipairs(linked) do
                        if linkedID == activeLinkedID then
                            found = true
                            break
                        end
                    end
                    if not found then
                        local withActive = {}
                        for i, linkedID in ipairs(linked) do
                            withActive[i] = linkedID
                        end
                        withActive[#withActive + 1] = activeLinkedID
                        linked = withActive
                    end
                end
            end
        end
    end
    _linkedSpellIDCache[spellID] = linked or false
    return linked
end

local _totemCandidateIDs = {}
local _totemCandidateSeen = {}

local function AppendTotemCandidate(id)
    if not IsUsableSpellIDKey(id) then return end
    if _totemCandidateSeen[id] then return end
    _totemCandidateSeen[id] = true
    _totemCandidateIDs[#_totemCandidateIDs + 1] = id
end

local function BuildTotemCandidates(...)
    wipe(_totemCandidateIDs)
    wipe(_totemCandidateSeen)
    for i = 1, select("#", ...) do
        local id = select(i, ...)
        AppendTotemCandidate(id)
        local linked = GetLinkedSpellIDsForSpellID(id)
        if linked then
            for _, linkedID in ipairs(linked) do
                AppendTotemCandidate(linkedID)
            end
        end
    end
    return _totemCandidateIDs
end

local _totemScanReport = {}

local function FormatTotemSlotScan()
    if not (GetTotemInfo and GetNumTotemSlots) then return "no-api" end
    local slotCount = GetNumTotemSlots()
    if type(slotCount) ~= "number" then return "no-slot-count" end
    wipe(_totemScanReport)
    for slot = 1, slotCount do
        local hasTotem, _, _, _, _, _, totemSpellID = GetTotemInfo(slot)
        if issecretvalue and issecretvalue(hasTotem) then hasTotem = nil end
        if hasTotem == true then
            -- @secret-safe: guarded by IsUsableSpellIDKey, which probes issecretvalue and rejects secrets; the analyzer is non-interprocedural and cannot see through the helper
            local shown = IsUsableSpellIDKey(totemSpellID) and tostring(totemSpellID) or "?"
            _totemScanReport[#_totemScanReport + 1] = tostring(slot) .. ":" .. shown
        end
    end
    if #_totemScanReport == 0 then return "none-active" end
    return table.concat(_totemScanReport, ",")
end

local function FindTotemSlotForSpellIDs(...)
    if not (GetTotemInfo and GetNumTotemSlots) then return nil end
    local slotCount = GetNumTotemSlots()
    if type(slotCount) ~= "number" then return nil end
    local candidates = BuildTotemCandidates(...)
    if #candidates == 0 then return nil end
    for slot = 1, slotCount do
        local hasTotem, _, _, _, _, _, totemSpellID = GetTotemInfo(slot)
        if issecretvalue and issecretvalue(hasTotem) then hasTotem = nil end
        if hasTotem == true and IsUsableSpellIDKey(totemSpellID) then
            for i = 1, #candidates do
                -- @secret-safe: both operands cleared IsUsableSpellIDKey, which probes issecretvalue and rejects secrets; the analyzer is non-interprocedural and cannot see through the helper
                if candidates[i] == totemSpellID then
                    return slot
                end
            end
        end
    end
    return nil
end

local function ResolveVirtualAuraState(explicitSlot)
    local slot = SafeMaybeNumber(explicitSlot)
    local state = { slot = slot }

    if not (slot and GetTotemInfo) then return state end

    local haveTotem, totemName, _, _, totemIcon = GetTotemInfo(slot)
    if issecretvalue and issecretvalue(haveTotem) then return state end
    if haveTotem ~= true then return state end
    if issecretvalue and issecretvalue(totemName) then totemName = nil end
    if issecretvalue and issecretvalue(totemIcon) then totemIcon = nil end
    state.totemName = totemName
    state.totemIcon = totemIcon

    if GetTotemDuration then
        local durObj = GetTotemDuration(slot)
        if durObj and type(durObj) ~= "number" then
            state.isActive = true
            state.auraUnit = "player"
            state.durObj = durObj
            state.isTotemInstance = true
            return state
        end
    end

    return state
end

local _auraResult = {
    isActive = false,
    auraInstanceID = nil,
    auraUnit = "player",
    durObj = nil,
    auraData = nil,
    absorbPoints = nil,
    count = nil,
    resolvedAuraSpellID = nil,
    hasExpirationTime = nil,
    hideDurationText = nil,
    durationStateUnknown = nil,
    totemSlot = nil,
    totemName = nil,
    totemIcon = nil,
    isTotemInstance = false,
}

local _auraCountResult = {
    value = nil,
    sinkText = nil,
    shown = false,
    source = nil,
}
_auraResult.count = _auraCountResult

local function IsSecretCountValue(value)
    return issecretvalue and issecretvalue(value) or false
end

local function SafeCountNumber(value)
    if IsSecretCountValue(value) or value == nil then
        return nil
    end
    local valueType = type(value)
    if valueType == "number" then
        return value
    end
    if valueType == "string" then
        return tonumber(value)
    end
    return nil
end

local function SetAuraCount(result, value, source, shown)
    local count = result and result.count
    if not count then return end

    count.value = nil
    count.sinkText = nil
    count.shown = false
    count.source = nil

    if shown == false then
        return
    end
    if not IsSecretCountValue(value) and value == nil then
        return
    end

    count.value = SafeCountNumber(value)
    count.sinkText = value
    count.shown = true
    count.source = source
end

local function WipeAuraResult()
    _auraResult.isActive = false
    _auraResult.auraInstanceID = nil
    _auraResult.auraUnit = "player"
    _auraResult.durObj = nil
    _auraCountResult.value = nil
    _auraCountResult.sinkText = nil
    _auraCountResult.shown = false
    _auraCountResult.source = nil
    _auraResult.auraData = nil
    _auraResult.absorbPoints = nil
    _auraResult.resolvedAuraSpellID = nil
    _auraResult.hasExpirationTime = nil
    _auraResult.hideDurationText = nil
    _auraResult.durationStateUnknown = nil
    _auraResult.totemSlot = nil
    _auraResult.totemName = nil
    _auraResult.totemIcon = nil
    _auraResult.isTotemInstance = false
end

local function SetResolvedAuraSpellID(result, auraData, fallbackID)
    if not result then return end
    local pts = auraData and auraData.points
    if not (issecretvalue and issecretvalue(pts)) and pts ~= nil then
        result.absorbPoints = pts
    end
    local sid = GetCleanAuraSpellID(auraData)
    if not IsUsableTableKey(sid) then
        sid = fallbackID
    end
    if IsUsableTableKey(sid) then
        result.resolvedAuraSpellID = sid
    end
end

---@type fun(...): ... -- hot-swapped by QUI_Debug; the stub is narrower than d.ShouldAura
local ShouldDebugAuraState = function() return false end
---@type fun(...)
local AuraStateDebug       = function() end
---@type fun(...): string
local FormatIDList         = function() return "nil" end

local function FormatLinkedLookup(spellID)
    local index = ns.CDMIndex
    local catalog = ns.CDMCatalog
    if not (index and index.Get) then return "no-index" end
    if not (catalog and catalog.GetCooldownInfo) then return "no-catalog" end
    if not IsUsableSpellIDKey(spellID) then return "bad-spellid" end
    local mapped = index.Get(spellID)
    if not mapped then return "no-index-entry" end
    local cooldownID = mapped.cooldownID
    if not IsUsableTableKey(cooldownID) then return "no-cooldown-id" end
    -- @secret-safe: guarded by IsUsableTableKey, which probes issecretvalue and rejects secrets; the analyzer is non-interprocedural and cannot see through the helper
    local prefix = "cd=" .. tostring(cooldownID)
    local info = catalog.GetCooldownInfo(cooldownID)
    if not info then return prefix .. " no-info" end
    local function Show(value)
        if not IsUsableTableKey(value) then return "nil" end
        -- @secret-safe: guarded by IsUsableTableKey, which probes issecretvalue and rejects secrets; the analyzer is non-interprocedural and cannot see through the helper
        return tostring(value)
    end
    prefix = prefix
        .. " sid=" .. Show(info.spellID)
        .. " ovr=" .. Show(info.overrideSpellID)
        .. " tip=" .. Show(info.overrideTooltipSpellID)
        .. " link=" .. Show(info.linkedSpellID)
        .. " flags=" .. Show(info.flags)
    local linked = info.linkedSpellIDs
    if type(linked) ~= "table" then return prefix .. " no-linked-table" end
    if #linked == 0 then return prefix .. " linked-empty" end
    return prefix .. " linked=" .. FormatIDList(linked)
end

local _resolveAuraScratch = {
    spellID = nil, entrySpellID = nil, entryID = nil, entryName = nil,
    entryLinkedSpellID = nil, entryLinkedSpellIDs = nil,
    entryIsAura = false, entryTexture = nil, viewerType = nil,
    debugAura = false, isBuiltinAuraViewer = false,

    hasMappedAuraID = false,
}

local _scratchCandidateIDs  = {}
local _scratchCandidateSeen = {}
local _scratchProbeIDs      = {}
local _scratchProbeSeen     = {}

local function WipeResolveAuraScratch()
    local s = _resolveAuraScratch
    s.spellID = nil; s.entrySpellID = nil; s.entryID = nil; s.entryName = nil
    s.entryLinkedSpellID = nil; s.entryLinkedSpellIDs = nil
    s.entryIsAura = false; s.entryTexture = nil; s.viewerType = nil
    s.debugAura = false; s.isBuiltinAuraViewer = false
    s.hasMappedAuraID = false
    wipe(_scratchCandidateIDs)
    wipe(_scratchCandidateSeen)
    wipe(_scratchProbeIDs)
    wipe(_scratchProbeSeen)
end

local _abilityToAuraSpellID
local _auraIDsForSpell
local ResolveAuraDisplaySpellID

local function ResolveAuraAppendID(id)
    if not IsUsableTableKey(id) or _scratchCandidateSeen[id] then return end
    _scratchCandidateSeen[id] = true
    _scratchCandidateIDs[#_scratchCandidateIDs + 1] = id
end

local function ResolveAuraAppendMappedAuraIDs(id)
    if not IsUsableTableKey(id) then return end
    local auraIDs
    if CDMSpellData.GetAuraIDsForSpell then
        auraIDs = CDMSpellData:GetAuraIDsForSpell(id)
    elseif _auraIDsForSpell then
        auraIDs = _auraIDsForSpell[id]
    end
    if not auraIDs then return end
    for _, aid in ipairs(auraIDs) do
        if IsUsableTableKey(aid) then
            _resolveAuraScratch.hasMappedAuraID = true
        end
        ResolveAuraAppendID(aid)
    end
end

local function ResolveAuraAppendLinkedSpellIDs(id)
    local linked = GetLinkedSpellIDsForSpellID(id)
    if not linked then return end
    for _, linkedID in ipairs(linked) do
        if IsUsableTableKey(linkedID) then
            _resolveAuraScratch.hasMappedAuraID = true
        end
        ResolveAuraAppendID(linkedID)
    end
end

local function ResolveAuraTryCaptured(preferredUnits, allowGlobalFallback, phaseName)
    local s = _resolveAuraScratch
    local captured = GetCapturedAuraForLookup(_scratchCandidateIDs, s.entryName,
        preferredUnits, allowGlobalFallback)
    if not (captured and captured.auraInstanceID) then
        return false
    end

    local capturedUnit = captured.unit or "player"
    local r = _auraResult
    local auraData = not InCombatLockdown() and captured.auraData or nil
    local alive, durObj = ResolveAuraInstanceDurationState(r,
        capturedUnit, captured.auraInstanceID, auraData)
    if alive then
        AuraStateDebug(s.debugAura, phaseName,
            "spellID=", captured.spellID,
            "inst=", captured.auraInstanceID,
            "unit=", capturedUnit)
        r.durObj = durObj
        r.auraData = auraData
        SetResolvedAuraSpellID(r, auraData, captured.spellID)
        return true, captured.auraInstanceID, capturedUnit
    end

    ReleaseCapturedEntry(captured)
    return false
end

local function ResolveAuraRuntimeStateImpl(params)
    WipeAuraResult()
    WipeResolveAuraScratch()
    local r = _auraResult
    local s = _resolveAuraScratch

    local spellID = params.spellID
    if not spellID then return r end

    local entrySpellID = params.entrySpellID
    local entryID = params.entryID
    local entryName = params.entryName
    local entryLinkedSpellID = params.entryLinkedSpellID
    local entryLinkedSpellIDs = params.entryLinkedSpellIDs
    local entryKind = params.entryKind
    local entryIsAura = params.entryIsAura == true or entryKind == "aura"
    local entryTexture = params.entryTexture
    local viewerType = params.viewerType
    local debugAura = ShouldDebugAuraState(entryName, spellID, entryID)
    local isBuiltinAuraViewer = IsBuiltinAuraContainerKey(viewerType)

    s.spellID = spellID
    s.entrySpellID = entrySpellID
    s.entryID = entryID
    s.entryName = entryName
    s.entryLinkedSpellID = entryLinkedSpellID
    s.entryLinkedSpellIDs = entryLinkedSpellIDs
    s.entryIsAura = entryIsAura
    s.entryTexture = entryTexture
    s.viewerType = viewerType
    s.debugAura = debugAura
    s.isBuiltinAuraViewer = isBuiltinAuraViewer

    AuraStateDebug(debugAura,
        "begin",
        "name=", entryName or "?",
        "spellID=", spellID,
        "entrySpellID=", entrySpellID,
        "entryID=", entryID,
        "viewerType=", viewerType)

    local auraSpellID = spellID
    if ResolveAuraDisplaySpellID then
        local mappedAuraID, remapped = ResolveAuraDisplaySpellID(auraSpellID)
        if remapped == true then
            auraSpellID = mappedAuraID
        end
    end

    local explicitTotemSlot = params.totemSlot
    if explicitTotemSlot == nil and not entryIsAura then
        explicitTotemSlot = FindTotemSlotForSpellIDs(auraSpellID, entrySpellID, entryID)
        if debugAura then
            AuraStateDebug(debugAura, "cooldown-totem-slot",
                "slot=", explicitTotemSlot,
                "candidates=", FormatIDList(_totemCandidateIDs),
                "slots=", FormatTotemSlotScan(),
                "lookup=", FormatLinkedLookup(entrySpellID))
        end
    end
    local disableLooseVisibilityFallback = params.disableLooseVisibilityFallback

    if explicitTotemSlot then
        local virtualState = ResolveVirtualAuraState(explicitTotemSlot)
        if virtualState.slot then
            r.totemSlot = virtualState.slot
            r.totemName = virtualState.totemName
            r.totemIcon = virtualState.totemIcon
            r.isTotemInstance = true
            if virtualState.isActive then
                r.isActive = true
                r.auraUnit = virtualState.auraUnit or "player"
                r.durObj = virtualState.durObj
                return r
            end
        end
    end

    local isActive = false
    local childAuraInstID = nil
    local auraUnit = "player"
    local directAuraActiveUnit = nil
    local directAuraActivePhase = nil

    if entryIsAura and isBuiltinAuraViewer then
        ResolveAuraAppendID(auraSpellID)
        ResolveAuraAppendID(entrySpellID)
    else
        ResolveAuraAppendID(auraSpellID)
        ResolveAuraAppendID(entrySpellID)
        ResolveAuraAppendID(entryID)
        ResolveAuraAppendMappedAuraIDs(auraSpellID)
        ResolveAuraAppendMappedAuraIDs(entrySpellID)
        ResolveAuraAppendMappedAuraIDs(entryID)
        ResolveAuraAppendLinkedSpellIDs(auraSpellID)
        ResolveAuraAppendLinkedSpellIDs(entrySpellID)
        ResolveAuraAppendLinkedSpellIDs(entryID)
        if IsUsableSpellIDKey(entryLinkedSpellID) then
            s.hasMappedAuraID = true
            ResolveAuraAppendID(entryLinkedSpellID)
        end
        if type(entryLinkedSpellIDs) == "table" then
            for _, linkedID in ipairs(entryLinkedSpellIDs) do
                if IsUsableSpellIDKey(linkedID) then
                    s.hasMappedAuraID = true
                    ResolveAuraAppendID(linkedID)
                end
            end
        end
    end

    if not entryIsAura then
        local glue = ns.AuraGlue
        local resolveCooldownAura = glue and glue.GetCooldownAuraBySpellID
        if resolveCooldownAura then
            for i = 1, #_scratchCandidateIDs do
                local auraID = resolveCooldownAura(_scratchCandidateIDs[i])
                if IsUsableSpellIDKey(auraID) then
                    s.hasMappedAuraID = true
                    ResolveAuraAppendID(auraID)
                end
            end
        end
    end

    if not entryIsAura and not s.hasMappedAuraID then
        AuraStateDebug(debugAura, "cooldown-no-mirror", "skip-api-fallbacks",
            "hasMappedAuraID=", s.hasMappedAuraID,
            "candidates=", FormatIDList(_scratchCandidateIDs))
        return r
    end

    if InCombatLockdown() then
        local matched, newInstID, newUnit = ResolveAuraTryCaptured(
            SELF_AURA_CAPTURE_LOOKUP_UNITS, false,
            "phase3.1-event-self-captured")
        if matched then
            isActive = true
            childAuraInstID = newInstID
            auraUnit = newUnit
        end
    end

    if not isActive then
        for _, tryID in ipairs(_scratchCandidateIDs) do
            if childAuraInstID then break end
            for unitIdx = 1, #STACK_SEARCH_UNITS do
                if childAuraInstID then break end
                local unitID = STACK_SEARCH_UNITS[unitIdx]
                local ad = LookupCapturedAuraBySpellID(unitID, tryID, "HELPFUL")
                if ad then
                    local auraData = GetCapturedAuraData(ad)
                    local instID = GetCleanAuraInstanceID(ad)
                    if instID then
                        childAuraInstID = instID
                        auraUnit = unitID
                        r.auraData = not InCombatLockdown() and auraData or nil
                        SetResolvedAuraSpellID(r, auraData, tryID)
                    elseif IsSelfUnit(unitID) and not directAuraActiveUnit then
                        directAuraActiveUnit = unitID
                        directAuraActivePhase = "phase3.2-player-active-no-inst"
                        SetResolvedAuraSpellID(r, ad, tryID)
                    end
                end
            end
            if not childAuraInstID then
                local targetAura = FindOwnedTargetAuraBySpellID(tryID, "HARMFUL")
                local auraData = GetCapturedAuraData(targetAura)
                local targetInstID = GetCleanAuraInstanceID(targetAura)
                if targetInstID then
                    childAuraInstID = targetInstID
                    auraUnit = "target"
                    r.auraData = not InCombatLockdown() and auraData or nil
                    SetResolvedAuraSpellID(r, auraData, tryID)
                end
            end
        end
    end

    if childAuraInstID then
        local alive, durObj = ResolveAuraInstanceDurationState(r, auraUnit, childAuraInstID, r.auraData)
        if alive or r.auraData then
            AuraStateDebug(debugAura, "phase3.2-duration", "unit=", auraUnit, "inst=", childAuraInstID,
                "durObj=", durObj and "yes" or "no", "unknown=", r.durationStateUnknown and "yes" or "no")
            isActive = true
            r.durObj = durObj
        end
    end

    if not isActive then
        local matched, newInstID, newUnit = ResolveAuraTryCaptured(
            AURA_CAPTURE_LOOKUP_UNITS, nil,
            "phase3.4-event-captured")
        if matched then
            isActive = true
            childAuraInstID = newInstID
            auraUnit = newUnit
        end
    end

    if not isActive and directAuraActiveUnit then
        AuraStateDebug(debugAura, directAuraActivePhase or "phase3.2-active-no-inst",
            "unit=", directAuraActiveUnit)
        isActive = true
        auraUnit = directAuraActiveUnit
    end

    if not isActive then
        for _, tryID in ipairs(_scratchCandidateIDs) do
            if isActive then break end
            if tryID then
                local ad = LookupCapturedAuraBySpellID("player", tryID, "HELPFUL")
                local auraData = GetCapturedAuraData(ad)
                local instID = GetCleanAuraInstanceID(ad)
                if instID then
                    AuraStateDebug(debugAura, "phase4-player-id", "tryID=", tryID, "inst=", instID)
                    isActive = true
                    childAuraInstID = instID
                    auraUnit = "player"
                    r.auraData = not InCombatLockdown() and auraData or nil
                    SetResolvedAuraSpellID(r, auraData, tryID)
                elseif ad then
                    AuraStateDebug(debugAura, "phase4-player-id-active-no-inst", "tryID=", tryID)
                    isActive = true
                    auraUnit = "player"
                    SetResolvedAuraSpellID(r, ad, tryID)
                end
            end
        end
    end
    if not isActive
        and entryName and entryName ~= "" then
        local ad = QueryCapturedAuraByName("player", entryName, "HELPFUL")
        local auraData = GetCapturedAuraData(ad)
        local instID = GetCleanAuraInstanceID(ad)
        if instID then
            AuraStateDebug(debugAura, "phase4-player-name", "inst=", instID)
            isActive = true
            childAuraInstID = instID
            auraUnit = "player"
            r.auraData = not InCombatLockdown() and auraData or nil
            SetResolvedAuraSpellID(r, auraData, nil)
        elseif ad then
            AuraStateDebug(debugAura, "phase4-player-name-active-no-inst")
            isActive = true
            auraUnit = "player"
            SetResolvedAuraSpellID(r, ad, nil)
        end
    end
    if not isActive
        and entryName and entryName ~= "" then
        local ad = QueryCapturedAuraByName("pet", entryName, "HELPFUL")
        local auraData = GetCapturedAuraData(ad)
        local instID = GetCleanAuraInstanceID(ad)
        if instID then
            AuraStateDebug(debugAura, "phase4-pet-name", "inst=", instID)
            isActive = true
            childAuraInstID = instID
            auraUnit = "pet"
            r.auraData = not InCombatLockdown() and auraData or nil
            SetResolvedAuraSpellID(r, auraData, nil)
        end
    end
    if not isActive        and entryName and entryName ~= "" then
        local ad = FindOwnedTargetAuraByName(entryName, "HARMFUL")
        local auraData = GetCapturedAuraData(ad)
        local instID = GetCleanAuraInstanceID(ad)
        if instID then
            AuraStateDebug(debugAura, "phase4-target-harmful", "inst=", instID)
            isActive = true
            childAuraInstID = instID
            auraUnit = "target"
            r.auraData = not InCombatLockdown() and auraData or nil
            SetResolvedAuraSpellID(r, auraData, nil)
        end
    end
    if not isActive and childAuraInstID then
        if IsSelfUnit(auraUnit) then
            local alive, durObj = ResolveAuraInstanceDurationState(r, auraUnit, childAuraInstID, r.auraData)
            if alive then
                AuraStateDebug(debugAura, "phase5-validate-inst", "unit=", auraUnit, "inst=", childAuraInstID)
                isActive = true
                r.durObj = durObj
            end
        end
    end

    if isActive
        and not childAuraInstID        and entryName and entryName ~= "" then
        local tad = FindOwnedTargetAuraByName(entryName, "HARMFUL")
        local targetData = GetCapturedAuraData(tad)
        local tadInstID = GetCleanAuraInstanceID(tad)
        if tadInstID then
            childAuraInstID = tadInstID
            auraUnit = "target"
            r.auraData = not InCombatLockdown() and targetData or nil
            SetResolvedAuraSpellID(r, targetData, nil)
        end
        if not childAuraInstID then
            local pad = QueryCapturedAuraByName("player", entryName, "HELPFUL")
            local playerData = GetCapturedAuraData(pad)
            local padInstID = GetCleanAuraInstanceID(pad)
            if padInstID then
                childAuraInstID = padInstID
                auraUnit = "player"
                r.auraData = not InCombatLockdown() and playerData or nil
                SetResolvedAuraSpellID(r, playerData, nil)
            end
        end
        if not childAuraInstID then
            for _, tryID in ipairs(_scratchCandidateIDs) do
                if childAuraInstID then break end
                if tryID then
                    local ad = LookupCapturedAuraBySpellID("player", tryID, "HELPFUL")
                    local auraData = GetCapturedAuraData(ad)
                    local instID = GetCleanAuraInstanceID(ad)
                    if instID then
                        childAuraInstID = instID
                        auraUnit = "player"
                        r.auraData = not InCombatLockdown() and auraData or nil
                        SetResolvedAuraSpellID(r, auraData, tryID)
                    end
                end
            end
        end
    end

    if isActive and childAuraInstID and not r.durObj then
        ApplyAuraExpirationState(r, auraUnit, childAuraInstID, r.auraData)
    end

    if isActive then
        local apps
        local stackSource
        local appsResolved = false
        if childAuraInstID then
            local gotApps, stackApps = GetAuraApplications(auraUnit, childAuraInstID)
            if gotApps then
                apps = stackApps
                stackSource = "display-count"
                appsResolved = true
            end
        end
        if not appsResolved
            and childAuraInstID
            and not InCombatLockdown()
            and IsSelfUnit(auraUnit)
            and r.auraData then
            local directApps = GetDisplayableAuraApplications(r.auraData)
            if IsUsableResolvedAuraData(auraUnit, r.auraData) and directApps ~= nil then
                apps = directApps
                stackSource = "resolved-data"
                appsResolved = true
            end
        end
        if not appsResolved
            and not childAuraInstID            and entryName and entryName ~= "" then
            for i = 1, #STACK_SEARCH_UNITS do
                local stackUnit = STACK_SEARCH_UNITS[i]
                if not appsResolved then
                    local nad = QueryCapturedAuraByName(stackUnit, entryName, "HELPFUL")
                    local auraData = GetCapturedAuraData(nad)
                    local nadApps = GetDisplayableAuraApplications(auraData)
                    if auraData and nadApps ~= nil then
                        apps = nadApps
                        stackSource = "name-" .. stackUnit
                        appsResolved = true
                    end
                end
            end
            if not appsResolved then
                local tad = FindOwnedTargetAuraByName(entryName, "HARMFUL")
                local tadInstID = GetRawAuraInstanceID(tad)
                local gotApps, tadApps = GetAuraApplications("target", tadInstID)
                if gotApps then
                    apps = tadApps
                    stackSource = "display-count"
                    appsResolved = true
                end
            end
        end
        local appsShown = appsResolved
            and (IsSecretCountValue(apps) or apps ~= nil)
        SetAuraCount(r, apps, stackSource, appsShown)
        if debugAura then
            local appsLog = IsSecretCountValue(apps) and "<secret>" or apps
            AuraStateDebug(debugAura, "count",
                "shown=", tostring(_auraCountResult.shown == true),
                "source=", stackSource or "nil",
                "value=", appsLog)
        end
    end

    r.isActive = isActive
    r.auraInstanceID = childAuraInstID
    r.auraUnit = auraUnit
    if isActive and not r.resolvedAuraSpellID then
        SetResolvedAuraSpellID(r, r.auraData, auraSpellID)
    end
    AuraStateDebug(debugAura, "end", "active=", isActive, "unit=", auraUnit,
        "inst=", childAuraInstID, "hasExp=", r.hasExpirationTime,
        "hideDur=", r.hideDurationText)
    return r
end

if ns.CDMAuraRuntime and ns.CDMAuraRuntime.SetResolver then
    ns.CDMAuraRuntime.SetResolver(ResolveAuraRuntimeStateImpl)
end

local function ForceLoadCDM()
    if InCombatLockdown() and not ns._inInitSafeWindow then return end
    local viewerAddon = ns.CDMCooldownViewerAddon
    if viewerAddon and viewerAddon.Load then
        viewerAddon.Load()
    elseif C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_CooldownViewer")
    elseif LoadAddOn then
        LoadAddOn("Blizzard_CooldownViewer")
    end
end

local function GetNcdmDB()
    if Shared and Shared.GetNcdmDB then
        local ncdm = Shared.GetNcdmDB()
        if ncdm then return ncdm end
    end

    local QUICore = ns.Addon
    return QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.ncdm
end

local function GetContainerDB(containerKey)
    if Shared and Shared.GetContainerDB then
        local containerDB = Shared.GetContainerDB(containerKey)
        if containerDB then return containerDB end
    end

    local ncdm = GetNcdmDB()
    if not ncdm then return nil end
    if ncdm[containerKey] then
        return ncdm[containerKey]
    end
    if ncdm.containers and ncdm.containers[containerKey] then
        return ncdm.containers[containerKey]
    end
    return nil
end

local function NormalizeOwnedEntry(entry)
    if type(entry) == "number" then
        return { type = "spell", id = entry }
    end
    if type(entry) == "table" and entry.id then
        if not entry.type then
            local resolvedType = "spell"
            if type(entry.id) == "number" and Sources and Sources.QueryItemInfoInstant then
                local itemID = Sources.QueryItemInfoInstant(entry.id)
                if itemID then
                    resolvedType = "item"
                end
            end
            entry.type = resolvedType
        end
        return entry
    end
    return nil
end

local function NormalizeOwnedSpells(ownedSpells)
    if type(ownedSpells) ~= "table" then return ownedSpells end
    for i, entry in ipairs(ownedSpells) do
        ownedSpells[i] = NormalizeOwnedEntry(entry)
    end
    return ownedSpells
end

local function ResolveOverrideID(spellID)
    if not (Sources and Sources.QueryOverrideSpell) then return nil end
    local overrideID = Sources.QueryOverrideSpell(spellID)
    if overrideID and overrideID ~= spellID then return overrideID end
    return nil
end

local function ResolveBaseID(spellID)
    if not (Sources and Sources.QueryBaseSpell) then return nil end
    local baseID = Sources.QueryBaseSpell(spellID)
    if baseID and baseID ~= spellID then return baseID end
    return nil
end

function CDMSpellData.AddSpellIDFamily(set, spellID)
    local id = tonumber(spellID)
    if type(set) ~= "table" or not id then return end
    set[id] = true
    local overrideID = ResolveOverrideID(id)
    if overrideID then set[overrideID] = true end
    local baseID = ResolveBaseID(id)
    if baseID then set[baseID] = true end
end

function CDMSpellData.IsSpellIDFamilyInSet(set, spellID)
    local id = tonumber(spellID)
    if type(set) ~= "table" or not id then return false end
    if set[id] then return true end
    local overrideID = ResolveOverrideID(id)
    if overrideID and set[overrideID] then return true end
    local baseID = ResolveBaseID(id)
    if baseID and set[baseID] then return true end
    return false
end

function CDMSpellData.ResolveSpellFamilyKey(spellID)
    local id = tonumber(spellID)
    if not id then return nil end
    local overrideID = ResolveOverrideID(id)
    local anchor = overrideID or id
    return ResolveBaseID(anchor) or anchor
end

function CDMSpellData.BuildOwnedSet(db)
    local ownedSet = {}
    if type(db) ~= "table" then return ownedSet end

    local list = db.ownedSpells
    if db.containerType == "customBar" and type(db.entries) == "table" then
        list = db.entries
    end

    if type(list) == "table" then
        for _, rawEntry in ipairs(list) do
            local entry = NormalizeOwnedEntry(rawEntry)
            if entry and entry.id then
                local etype = entry.type or "spell"
                ownedSet[etype .. ":" .. tostring(entry.id)] = true
                if etype == "spell" then
                    CDMSpellData.AddSpellIDFamily(ownedSet, entry.id)
                else
                    ownedSet[entry.id] = true
                end
                if etype == "item" and Sources and Sources.QueryBestOwnedItemVariant then
                    local bestItemID = Sources.QueryBestOwnedItemVariant(entry.id)
                    if bestItemID then
                        ownedSet["item:" .. tostring(bestItemID)] = true
                        ownedSet[bestItemID] = true
                    end
                end
            end
        end
    end

    if type(db.dormantSpells) == "table" then
        for sid in pairs(db.dormantSpells) do
            if type(sid) == "number" then
                ownedSet["spell:" .. tostring(sid)] = true
                CDMSpellData.AddSpellIDFamily(ownedSet, sid)
            end
        end
    end

    return ownedSet
end

local WoW_IsSpellKnown = IsSpellKnown
local WoW_IsPlayerSpell = IsPlayerSpell
local function IsSpellKnownByPlayer(spellID)
    if not spellID then return false end
    if WoW_IsSpellKnown and WoW_IsSpellKnown(spellID) then return true end
    if WoW_IsPlayerSpell and WoW_IsPlayerSpell(spellID) then return true end
    local overrideID = Sources and Sources.QueryOverrideSpell and Sources.QueryOverrideSpell(spellID)
    if overrideID and overrideID ~= spellID then
        if WoW_IsSpellKnown and WoW_IsSpellKnown(overrideID) then return true end
        if WoW_IsPlayerSpell and WoW_IsPlayerSpell(overrideID) then return true end
    end
    local baseID = Sources and Sources.QueryBaseSpell and Sources.QueryBaseSpell(spellID)
    if baseID and baseID ~= spellID then
        if WoW_IsSpellKnown and WoW_IsSpellKnown(baseID) then return true end
        if WoW_IsPlayerSpell and WoW_IsPlayerSpell(baseID) then return true end
    end
    return false
end

local _cdIDToCorrectSID = {}
local _spellToCooldownID = {}
local _spellInCDMCooldowns = {}
local _spellInCDMAuras = {}
_abilityToAuraSpellID = {}
_auraIDsForSpell = {}

local function ResolveEntryKind(entry, viewerType)
    if not entry then return "cooldown" end

    if entry.kind == "aura" or entry.kind == "cooldown" then
        return entry.kind
    end

    if entry.type and entry.type ~= "spell" then
        return "cooldown"
    end

    local impliedKind = GetBuiltinContainerEntryKind(viewerType)
    if impliedKind then
        return impliedKind
    end

    return "cooldown"
end

local function IsAuraEntry(entry, viewerType)
    return ResolveEntryKind(entry, viewerType) == "aura"
end

local RebuildSpellToCooldownID

ResolveAuraDisplaySpellID = function(entryID)
    if RebuildSpellToCooldownID and not next(_spellToCooldownID) then
        RebuildSpellToCooldownID()
    end

    local AuraCatalog = ns.CDMAuraCatalog
    if AuraCatalog and AuraCatalog.ResolveEntryAuraDisplay then
        return AuraCatalog.ResolveEntryAuraDisplay(entryID, _abilityToAuraSpellID)
    end

    return entryID, false
end

if ns.CDMAuraRuntime and ns.CDMAuraRuntime.SetAbilityAuraSpellIDResolver then
    ns.CDMAuraRuntime.SetAbilityAuraSpellIDResolver(ResolveAuraDisplaySpellID)
end

local function AttachCatalogAuraIDs(resolved, ...)
    local AuraCatalog = ns.CDMAuraCatalog
    if AuraCatalog and AuraCatalog.AttachLinkedAuraIDs then
        AuraCatalog.AttachLinkedAuraIDs(resolved, _auraIDsForSpell, function(spellID)
            return CDMSpellData:GetAuraIDsForSpell(spellID)
        end, ...)
    end
end

local function ResolveOwnedEntry(entry, containerKey, index)
    if not entry or not entry.id then return nil end

    local resolved = {
        name = "",
        isAura = false,
        hasCharges = false,
        layoutIndex = index or 9999,
        viewerType = containerKey,
        _isOwnedEntry = true,
        type = entry.type,
        id = entry.id,
        source = entry.source,
    }

    if entry.type == "spell" then
        resolved.spellID = entry.id

        local isAuraEntry = ResolveEntryKind(entry, containerKey) == "aura"
        local displayID = entry.id

        if isAuraEntry then
            local auraDisplayID, remapped = ResolveAuraDisplaySpellID(entry.id)
            if remapped then
                displayID = auraDisplayID
                resolved.spellID = displayID
            end
            resolved.isAura = true
            resolved.kind = "aura"
        else
            resolved.kind = "cooldown"
        end

        if not isAuraEntry and Sources and Sources.QueryOverrideSpell then
            local overrideID = Sources.QueryOverrideSpell(displayID)
            if overrideID and overrideID ~= displayID then
                resolved.overrideSpellID = overrideID
            else
                resolved.overrideSpellID = displayID
            end
        else
            resolved.overrideSpellID = displayID
        end

        AttachCatalogAuraIDs(resolved, displayID, resolved.overrideSpellID, entry.id)

        local cachedName = ns._GetCachedSpellName
        if cachedName then
            local lookupID = resolved.overrideSpellID or displayID
            local n = cachedName(lookupID)
            if n then
                resolved.name = n
            elseif lookupID ~= entry.id then
                local n2 = cachedName(entry.id)
                if n2 then
                    resolved.name = n2
                end
            end
        end
        if resolved.name == "" then
            local storedName = entry.name
            if type(storedName) == "string"
               and storedName ~= "" then
                resolved.name = storedName
            end
        end
        if Sources and Sources.QuerySpellCharges then
            local checkID = resolved.overrideSpellID or displayID
            local ci, queryOk = Sources.QuerySpellCharges(checkID)
            local apiReadable = false
            if queryOk then
                if ci then
                    local maxC = ci.maxCharges
                    if maxC then
                        apiReadable = true
                        if maxC > 1 then
                            resolved.hasCharges = true
                        end
                    end
                else
                    apiReadable = true
                end
            end
            if not apiReadable and not resolved.hasCharges and checkID then
                local gdb = QUI and QUI.db and QUI.db.global
                local svCharges = gdb and gdb.cdmChargeSpells
                if svCharges and svCharges[checkID] then
                    resolved.hasCharges = true
                end
            end
        end

    elseif entry.type == "item" then
        local itemID = (Sources and Sources.QueryBestOwnedItemVariant
            and Sources.QueryBestOwnedItemVariant(entry.id)) or entry.id
        resolved.id = itemID
        resolved.itemID = itemID
        local itemName = Sources and Sources.QueryItemNameByID and Sources.QueryItemNameByID(itemID)
        if itemName then
            resolved.name = itemName
        end

    elseif entry.type == "slot" then
        resolved.id = entry.id
        local itemID = Sources and Sources.QueryInventoryItemID
            and Sources.QueryInventoryItemID("player", entry.id)
        if itemID then
            resolved.itemID = itemID
            local itemName = Sources and Sources.QueryItemNameByID and Sources.QueryItemNameByID(itemID)
            if itemName then
                resolved.name = itemName
            end
        end

    elseif entry.type == "consumable" then
        resolved.id = entry.id

    elseif entry.type == "macro" then
        resolved.macroName = entry.macroName
        resolved.name = entry.macroName or ""
        local macroIndex = entry.macroName and GetMacroIndexByName(entry.macroName)
        if macroIndex and macroIndex > 0 then
            local macroSpellID = GetMacroSpell(macroIndex)
            if macroSpellID then
                resolved.spellID = macroSpellID
                resolved.overrideSpellID = macroSpellID
            else
                local itemName, itemLink = GetMacroItem(macroIndex)
                if itemLink then
                    local itemID = Sources and Sources.QueryItemInfoInstant
                        and Sources.QueryItemInfoInstant(itemLink)
                    if itemID then
                        resolved.spellID = itemID
                        resolved.overrideSpellID = itemID
                    end
                end
            end
        end
    end

    return resolved
end

local function BuildAuraInstanceKey(containerKey)
    return (containerKey or "aura") .. ":entry:1"
end

local function ExpandResolvedAuraEntry(containerKey, resolved)
    if resolved then
        resolved._instanceKey = BuildAuraInstanceKey(containerKey)
    end
    return { resolved }
end

function CDMSpellData:SnapshotBlizzardCDM(containerKey)
    if InCombatLockdown() and not ns._inInitSafeWindow then
        return false, false
    end
    if not IsBuiltinContainerKey(containerKey) then return false, true end

    local db = GetContainerDB(containerKey)
    if not db then return false, false end

    if db.ownedSpells ~= nil then return false, true end

    local catalog = ns.CDMCatalog
    if not (catalog and catalog.SeedFromBlizzard) then return false, false end

    local seeded, seedReady = catalog.SeedFromBlizzard(containerKey)
    if not seedReady then return false, false end
    if not seeded then return false, false end

    db.ownedSpells = seeded
    local ncdm = GetNcdmDB()
    if ncdm then
        ncdm._snapshotVersion = (ncdm._snapshotVersion or 0) + 1
    end
    return true, true
end

local function SnapshotUnsetBuiltinContainers()
    local snapshotted = false
    local allReady = true
    for _, key in ipairs(GetBuiltinContainerKeys()) do
        local didSnapshot, snapshotReady = CDMSpellData:SnapshotBlizzardCDM(key)
        if didSnapshot then
            snapshotted = true
        end
        if not snapshotReady then
            allReady = false
        end
    end
    return snapshotted, allReady
end

local function CDMCatalogReady(family)
    if not next(_spellToCooldownID) then
        if RebuildSpellToCooldownID then
            RebuildSpellToCooldownID()
        end
    end
    if family == "aura" or family == "auraBar" then
        return next(_spellInCDMAuras) ~= nil
    elseif family == "cooldown" then
        return next(_spellInCDMCooldowns) ~= nil
    end
    return next(_spellToCooldownID) ~= nil
end

local function IsSpellInCDMCategoryInternal(spellID, family)
    local id = tonumber(spellID)
    if not id then return false end
    if not next(_spellToCooldownID) then
        RebuildSpellToCooldownID()
    end
    if family == "cooldown" then
        return _spellInCDMCooldowns[id] == true
    elseif family == "aura" or family == "auraBar" then
        return _spellInCDMAuras[id] == true
    end
    return _spellToCooldownID[id] ~= nil
end

function CDMSpellData:IsEntryApplicableForContainer(_containerKey, entry)
    local normalized = NormalizeOwnedEntry(entry)
    if not normalized or normalized.type ~= "spell" or type(normalized.id) ~= "number" then
        return true
    end
    if normalized.source ~= BLIZZARD_CDM_ENTRY_SOURCE then
        return true
    end
    if CDMSpellData._cdmClassApplicableCatalogReady ~= true then
        return true
    end
    local family = CDMSpellData._cdmClassApplicableSpellFamily
    return type(family) == "table" and family[normalized.id] == true
end

local function IsEntryDormantForContainerInternal(containerKey, entry)
    local normalized = NormalizeOwnedEntry(entry)
    if not normalized or normalized.type ~= "spell" or type(normalized.id) ~= "number" then
        return false
    end
    if not CDMSpellData:IsEntryApplicableForContainer(containerKey, normalized) then
        return false
    end
    if IsAuraEntry(normalized, containerKey) then
        if normalized.source ~= BLIZZARD_CDM_ENTRY_SOURCE then
            return false
        end
        if not CDMCatalogReady("aura") then return false end
        if not IsSpellInCDMCategoryInternal(normalized.id, "aura") then
            return true
        end
        if not CDMSpellData:_AuraLearnedCatalogReady() then return false end
        if not CDMSpellData:_IsAuraLearnedFamilyID(normalized.id) then
            return true
        end
        return CDMSpellData:_IsTrackedDisplayWrongSide(containerKey, normalized.id)
    end
    if not IsSpellKnownByPlayer(normalized.id) then return true end
    if normalized.source == BLIZZARD_CDM_ENTRY_SOURCE then
        if not CDMSpellData:_CooldownLearnedCatalogReady() then return false end
        return not CDMSpellData:_IsCooldownLearnedPreferred(normalized.id)
    end
    return false
end

function CDMSpellData:_CooldownLearnedCatalogReady()
    local set = self._cdmCooldownLearnedPreferred
    return type(set) == "table" and next(set) ~= nil
end

function CDMSpellData:_IsCooldownLearnedPreferred(spellID)
    local id = tonumber(spellID)
    if not id then return false end
    local set = self._cdmCooldownLearnedPreferred
    return type(set) == "table" and set[id] == true
end

function CDMSpellData:_AuraLearnedCatalogReady()
    return self._cdmAuraLearnedCatalogReady == true
end

function CDMSpellData:_EnsureTrackedDisplaySets()
    local broker = ns.CDMIndex
    local version = broker and broker.Version and broker.Version() or 0
    if self._cdmTrackedDisplayReady ~= nil
        and self._cdmTrackedDisplayVersion == version then
        return
    end
    local iconSet = self._cdmTrackedDisplayIconFamily
    if type(iconSet) ~= "table" then
        iconSet = {}
        self._cdmTrackedDisplayIconFamily = iconSet
    end
    local barSet = self._cdmTrackedDisplayBarFamily
    if type(barSet) ~= "table" then
        barSet = {}
        self._cdmTrackedDisplayBarFamily = barSet
    end
    wipe(iconSet)
    wipe(barSet)
    self._cdmTrackedDisplayVersion = version
    self._cdmTrackedDisplayReady = false
    local catalog = ns.CDMCatalog
    if catalog and catalog.RebuildTrackedDisplayFamilyIDs then
        self._cdmTrackedDisplayReady =
            catalog.RebuildTrackedDisplayFamilyIDs(iconSet, barSet) == true
    end
end

function CDMSpellData:_IsTrackedDisplayWrongSide(containerKey, spellID)
    local id = tonumber(spellID)
    if not id then return false end
    if containerKey ~= "buff" and containerKey ~= "trackedBar" then
        return false
    end
    self:_EnsureTrackedDisplaySets()
    if self._cdmTrackedDisplayReady ~= true then return false end
    local iconSet = self._cdmTrackedDisplayIconFamily
    local barSet = self._cdmTrackedDisplayBarFamily
    if containerKey == "buff" then
        return iconSet[id] ~= true and barSet[id] == true
    end
    return barSet[id] ~= true and iconSet[id] == true
end

function CDMSpellData:_IsAuraLearnedFamilyID(spellID)
    local id = tonumber(spellID)
    if not id then return false end
    local set = self._cdmAuraLearnedFamily
    return type(set) == "table" and set[id] == true
end

function CDMSpellData:_HeroSubTreeKey()
    local heroID = C_ClassTalents and C_ClassTalents.GetActiveHeroTalentSpec
        and C_ClassTalents.GetActiveHeroTalentSpec()
    if type(heroID) == "number" and heroID > 0 then return heroID end
    return -1
end

function CDMSpellData:_MigrateRemovedSpells(db)
    if type(db) ~= "table" then return end
    local rs = db.removedSpells
    if type(rs) ~= "table" or next(rs) == nil then return end
    for _, v in pairs(rs) do
        if type(v) ~= "table" then
            db.removedSpells = { [0] = rs }
            return
        end
    end
end

function CDMSpellData:_IsSpellRemovedForCurrentBuild(db, spellID)
    local rs = db and db.removedSpells
    if type(rs) ~= "table" then return false end
    local global = rs[0]
    if type(global) == "table" and global[spellID] then return true end
    local bucket = rs[self:_HeroSubTreeKey()]
    return type(bucket) == "table" and bucket[spellID] == true
end

function CDMSpellData:BuildSpellListFromOwned(containerKey)
    local db = GetContainerDB(containerKey)
    if not db or type(db.ownedSpells) ~= "table" then return {} end

    if not next(_spellToCooldownID) then
        RebuildSpellToCooldownID()
    end

    local ownedSpells = NormalizeOwnedSpells(db.ownedSpells)
    self:_MigrateRemovedSpells(db)

    local result = {}
    local seenInstanceKeys = {}
    local seenSpellFamilyKeys = {}
    for i, entry in ipairs(ownedSpells) do
        if entry and entry.id then
            local isRemoved = false
            if entry.type == "spell" and self:_IsSpellRemovedForCurrentBuild(db, entry.id) then
                isRemoved = true
            end
            local isDormant = not isRemoved
                and IsEntryDormantForContainerInternal(containerKey, entry)
            local isApplicable = not isRemoved
                and self:IsEntryApplicableForContainer(containerKey, entry)

            if not isRemoved and isApplicable and not isDormant then
                local resolved = ResolveOwnedEntry(entry, containerKey, i)
                if resolved then
                    resolved._assignedRow = entry.row
                    local expanded = resolved
                    if resolved.isAura then
                        expanded = ExpandResolvedAuraEntry(containerKey, resolved)
                    else
                        resolved._instanceKey = BuildAuraInstanceKey(containerKey)
                        expanded = { resolved }
                    end
                    for _, expandedEntry in ipairs(expanded) do
                        local instanceKey = expandedEntry and expandedEntry._instanceKey
                        local shouldDedupe = expandedEntry and (
                            expandedEntry._isTotemInstance
                            or (expandedEntry.isAura and instanceKey and not instanceKey:find(":entry:", 1, true))
                        )
                        local familyKey = nil
                        if expandedEntry and not expandedEntry.isAura
                            and expandedEntry.type == "spell" then
                            familyKey = CDMSpellData.ResolveSpellFamilyKey(
                                expandedEntry.overrideSpellID or expandedEntry.spellID)
                        end

                        if shouldDedupe and instanceKey then
                            if not seenInstanceKeys[instanceKey] then
                                seenInstanceKeys[instanceKey] = true
                                result[#result + 1] = expandedEntry
                            end
                        elseif familyKey then
                            if not seenSpellFamilyKeys[familyKey] then
                                seenSpellFamilyKeys[familyKey] = true
                                result[#result + 1] = expandedEntry
                            end
                        else
                            result[#result + 1] = expandedEntry
                        end
                    end
                end
            end
        end
    end

    return result
end

local RACE_RACIALS = {
    Scourge            = { 7744 },
    Tauren             = { 20549 },
    Orc                = { 20572, 33697, 33702 },
    BloodElf           = { 202719, 50613, 25046, 69179, 80483, 155145, 129597, 232633, 28730 },
    Dwarf              = { 20594 },
    Troll              = { 26297 },
    Draenei            = { 28880 },
    NightElf           = { 58984 },
    Human              = { 59752 },
    DarkIronDwarf      = { 265221 },
    Gnome              = { 20589 },
    HighmountainTauren = { 69041 },
    Worgen             = { 68992 },
    Goblin             = { 69070 },
    Pandaren           = { 107079 },
    MagharOrc          = { 274738 },
    LightforgedDraenei = { 255647 },
    VoidElf            = { 256948 },
    Nightborne         = { 260364 },
    KulTiran           = { 287712 },
    ZandalariTroll     = { 291944 },
    Vulpera            = { 312411 },
    Mechagnome         = { 312924 },
    Dracthyr           = { 357214, { 368970, class = "EVOKER" } },
    EarthenDwarf       = { 436344 },
    Haranir            = { 1287685 },
}

RebuildSpellToCooldownID = function()
    ClearDeprecatedLearnedCastToAuraDB()
    wipe(_spellToCooldownID)
    wipe(_spellInCDMCooldowns)
    wipe(_spellInCDMAuras)
    wipe(_abilityToAuraSpellID)
    wipe(_auraIDsForSpell)
    local catalog = ns.CDMCatalog
    if catalog and catalog.RebuildBlizzardCatalogMaps then
        catalog.RebuildBlizzardCatalogMaps(
            _spellToCooldownID, _spellInCDMCooldowns,
            _spellInCDMAuras, _abilityToAuraSpellID,
            _auraIDsForSpell)
    end

    local learnedSet = CDMSpellData._cdmCooldownLearnedPreferred
    if type(learnedSet) ~= "table" then
        learnedSet = {}
        CDMSpellData._cdmCooldownLearnedPreferred = learnedSet
    end
    wipe(learnedSet)
    if catalog and catalog.RebuildCooldownLearnedPreferredIDs then
        catalog.RebuildCooldownLearnedPreferredIDs(learnedSet)
    end

    local learnedAuraSet = CDMSpellData._cdmAuraLearnedFamily
    if type(learnedAuraSet) ~= "table" then
        learnedAuraSet = {}
        CDMSpellData._cdmAuraLearnedFamily = learnedAuraSet
    end
    wipe(learnedAuraSet)
    CDMSpellData._cdmAuraLearnedCatalogReady = false
    if catalog and catalog.RebuildAuraLearnedFamilyIDs then
        CDMSpellData._cdmAuraLearnedCatalogReady =
            catalog.RebuildAuraLearnedFamilyIDs(learnedAuraSet) == true
    end

    local applicableSet = CDMSpellData._cdmClassApplicableSpellFamily
    if type(applicableSet) ~= "table" then
        applicableSet = {}
        CDMSpellData._cdmClassApplicableSpellFamily = applicableSet
    end
    wipe(applicableSet)
    CDMSpellData._cdmClassApplicableCatalogReady = false
    if catalog and catalog.RebuildClassApplicableSpellIDs then
        CDMSpellData._cdmClassApplicableCatalogReady =
            catalog.RebuildClassApplicableSpellIDs(applicableSet) == true
    end

    CDMSpellData._cdmTrackedDisplayReady = nil
    CDMSpellData._cdmTrackedDisplayVersion = nil
end

local function LearnedCatalogSignature()
    local ids = {}
    local cooldowns = CDMSpellData._cdmCooldownLearnedPreferred
    if type(cooldowns) == "table" then
        for id in pairs(cooldowns) do ids[#ids + 1] = "c:" .. tostring(id) end
    end
    local auras = CDMSpellData._cdmAuraLearnedFamily
    if type(auras) == "table" then
        for id in pairs(auras) do ids[#ids + 1] = "a:" .. tostring(id) end
    end
    local applicable = CDMSpellData._cdmClassApplicableSpellFamily
    if type(applicable) == "table" then
        for id in pairs(applicable) do ids[#ids + 1] = "p:" .. tostring(id) end
    end
    ids[#ids + 1] = CDMSpellData._cdmAuraLearnedCatalogReady and "ar:1" or "ar:0"
    ids[#ids + 1] = CDMSpellData._cdmClassApplicableCatalogReady and "pr:1" or "pr:0"
    table.sort(ids)
    return table.concat(ids, ",")
end

local function RunReconcileSequence(guardUnchanged)
    local restored = CDMSpellData:CheckAllDormantSpells()
    local before = guardUnchanged and LearnedCatalogSignature() or nil
    CDMSpellData:ReconcileAllContainers()
    if guardUnchanged and not restored and before == LearnedCatalogSignature() then
        return
    end
    if FireChangeCallback then
        FireChangeCallback()
    end
end

function CDMSpellData:RunColdLoadReconcile()
    local function runAttempt(attempt)
        if not IsCDMRuntimeEnabled() then
            ns._cdmColdLoadActive = false
            return
        end
        if InCombatLockdown() then
            ns._cdmColdLoadActive = false
            return
        end
        if RebuildSpellToCooldownID then
            RebuildSpellToCooldownID()
        end
        local _, snapshotReady = SnapshotUnsetBuiltinContainers()
        if not snapshotReady then
            local delay = attempt < COLD_LOAD_SNAPSHOT_RETRY_MAX_ATTEMPTS
                and COLD_LOAD_SNAPSHOT_RETRY_DELAY
                or COLD_LOAD_SNAPSHOT_RETRY_SLOW_DELAY
            C_Timer.After(delay, function()
                runAttempt(attempt + 1)
            end)
            return
        end
        RunReconcileSequence()
        ns._cdmColdLoadActive = false
    end
    runAttempt(1)
end

function CDMSpellData:ReconcileAllContainers()
    if InCombatLockdown() then
        return
    end

    RebuildSpellToCooldownID()
end

local learnedCooldownsCache = nil
local learnedCooldownsCacheDirty = true

local function InvalidateLearnedCooldownsCache()
    learnedCooldownsCache = nil
    learnedCooldownsCacheDirty = true
end

local function CombatGuard()
    return InCombatLockdown()
end

FireChangeCallback = function()
    if _G.QUI_OnSpellDataChanged then
        _G.QUI_OnSpellDataChanged()
    end
    if ns.CDMContainers and ns.CDMContainers.SaveActiveSpecProfile then
        ns.CDMContainers.SaveActiveSpecProfile()
    end
end

local function ValidateEntry(entry)
    if type(entry) ~= "table" then return false end
    if not entry.type then return false end
    if entry.type == "macro" then
        return entry.macroName and type(entry.macroName) == "string"
    end
    return entry.id and type(entry.id) == "number"
end

local function GetEntryListField(db)
    if not db then return nil end
    if db.containerType == "customBar" then return "entries" end
    return "ownedSpells"
end

local function GetCurrentSpecID()
    return Helpers.GetCurrentSpecID()
end

local function GetSpecKeyForSpecID(specID)
    local class
    if UnitClass then
        local _
        _, class = UnitClass("player")
    end
    -- @secret-policy: collapse-only — UnitClass can return SECRET on 12.1 PTR7
    if issecretvalue and issecretvalue(class) then class = nil end
    if issecretvalue and issecretvalue(specID) then specID = nil end
    if not class or not specID then return class or "UNKNOWN" end
    return class .. "-" .. tostring(specID)
end

local function GetCurrentSpecKey()
    local specID = GetCurrentSpecID()
    if not specID then
        local class
        if UnitClass then
            local _
            _, class = UnitClass("player")
        end
        if issecretvalue and issecretvalue(class) then class = nil end -- @secret-policy: collapse-only
        return class or "UNKNOWN"
    end
    return GetSpecKeyForSpecID(specID)
end

local function GetNumericSpecKey(specKey)
    if type(specKey) ~= "string" then return nil end
    return specKey:match("%-(%d+)$") or specKey:match("^(%d+)$")
end

local function GetSpecTrackerRoot(createIfMissing)
    local core = ns.Addon
    local globalDB = core and core.db and core.db.global
    if not globalDB then return nil end
    if not globalDB.ncdm then
        if not createIfMissing then return nil end
        globalDB.ncdm = {}
    end
    if not globalDB.ncdm.specTrackerSpells then
        if not createIfMissing then return nil end
        globalDB.ncdm.specTrackerSpells = {}
    end
    return globalDB.ncdm.specTrackerSpells
end

local function GetSpecEntryList(containerKey, specKey, createIfMissing)
    local root = GetSpecTrackerRoot(createIfMissing)
    if not root then return nil end
    local byContainer = root[containerKey]
    if not byContainer then
        if not createIfMissing then return nil end
        byContainer = {}
        root[containerKey] = byContainer
    end
    specKey = specKey or GetCurrentSpecKey()
    local list = byContainer[specKey]
    if type(list) ~= "table" then
        local numericKey = GetNumericSpecKey(specKey)
        if numericKey and numericKey ~= specKey then
            list = byContainer[numericKey]
        end
    end
    if not list and createIfMissing then
        list = {}
        byContainer[specKey] = list
    end
    return list, specKey
end

local function CloneEntry(entry)
    if type(entry) ~= "table" then return entry end
    local out = {}
    for k, v in pairs(entry) do out[k] = v end
    return out
end

local function EntriesEquivalent(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    return a.type == b.type
        and a.id == b.id
        and a.macroName == b.macroName
        and a.customName == b.customName
end

local function MergeEntryLists(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then return false end
    local changed = false
    for _, entry in ipairs(src) do
        if type(entry) == "table" then
            local exists = false
            for _, existing in ipairs(dst) do
                if EntriesEquivalent(existing, entry) then
                    exists = true
                    break
                end
            end
            if not exists then
                dst[#dst + 1] = CloneEntry(entry)
                changed = true
            end
        end
    end
    return changed
end

local function ResolveContainerSourceSpecID(db)
    local sourceSpecID = db and db._sourceSpecID
    if type(sourceSpecID) == "number" and sourceSpecID > 0 then
        return sourceSpecID
    end
    local profile = ns.Addon and ns.Addon.db and ns.Addon.db.profile
    local lastSpecID = profile and profile.ncdm and profile.ncdm._lastSpecID
    if type(lastSpecID) == "number" and lastSpecID > 0 then
        return lastSpecID
    end
    return GetCurrentSpecID()
end

local function MoveLegacySpecEntriesToPerSpecStorage(containerKey, db)
    if type(db) ~= "table" or not db.specSpecific then return nil end
    if type(db.entries) ~= "table" or #db.entries == 0 then return nil end

    local sourceSpecID = ResolveContainerSourceSpecID(db)
    if type(sourceSpecID) ~= "number" or sourceSpecID <= 0 then return nil end

    local specKey = GetSpecKeyForSpecID(sourceSpecID)
    local list = GetSpecEntryList(containerKey, specKey, true)
    if type(list) ~= "table" then return nil end

    MergeEntryLists(list, db.entries)
    db._sourceSpecID = sourceSpecID
    db.entries = {}

    if sourceSpecID == GetCurrentSpecID() then
        return list
    end
    return nil
end

local function GetMutableEntryList(db, containerKey, createIfMissing, specKey)
    if not db then return nil end
    if db.specSpecific then
        if specKey == false then
            local field = GetEntryListField(db)
            if createIfMissing and db[field] == nil then db[field] = {} end
            return db[field]
        end
        return GetSpecEntryList(containerKey, specKey, createIfMissing)
    end
    local field = GetEntryListField(db)
    if createIfMissing and db[field] == nil then db[field] = {} end
    return db[field]
end

local function CompareShelfReturning(a, b)
    if a.slot ~= b.slot then
        return a.slot < b.slot
    end
    if a.seq ~= b.seq then
        return a.seq < b.seq
    end
    return a.id < b.id
end

function CDMSpellData:CheckDormantSpells(containerKey)
    local db = GetContainerDB(containerKey)
    if not db then return false end

    local shelf = db.dormantSpells
    if type(shelf) ~= "table" or next(shelf) == nil then return false end

    local createIfMissing = (db.containerType == "customBar")
    local list = GetMutableEntryList(db, containerKey, createIfMissing)
    if type(list) ~= "table" then return false end

    local returning = {}
    if type(shelf[1]) == "number" then
        for _, sid in ipairs(shelf) do
            if type(sid) == "number" then
                returning[#returning + 1] = { id = sid, slot = 9999, seq = 9999 }
            end
        end
    else
        for sid, saved in pairs(shelf) do
            if type(sid) == "number" then
                if type(saved) == "table" then
                    local slot = saved.slot or 9999
                    returning[#returning + 1] = {
                        id = sid,
                        slot = slot,
                        row = saved.row,
                        kind = saved.kind,
                        seq = saved.seq or slot,
                    }
                elseif type(saved) == "number" then
                    returning[#returning + 1] = { id = sid, slot = saved, seq = saved }
                end
            end
        end
    end
    table.sort(returning, CompareShelfReturning)

    local present = {}
    for _, entry in ipairs(list) do
        local norm = NormalizeOwnedEntry(entry)
        if type(norm) == "table" and norm.type == "spell" and type(norm.id) == "number" then
            present[norm.id] = true
        end
    end

    local restoredAny = false
    for _, info in ipairs(returning) do
        if not present[info.id] then
            present[info.id] = true
            local insertAt = math.min(info.slot, #list + 1)
            local restored = { type = "spell", id = info.id, row = info.row }
            if info.kind == "aura" or info.kind == "cooldown" then
                restored.kind = info.kind
            else
                restored.kind = ResolveEntryKind(restored, containerKey)
            end
            table.insert(list, insertAt, restored)
            restoredAny = true
        end
    end

    db.dormantSpells = {}
    db._dormantSequence = nil
    return restoredAny
end

function CDMSpellData:CheckAllDormantSpells()
    local containerKeys = GetBuiltinContainerKeys()
    if ns.CDMContainers and ns.CDMContainers.GetAllContainerKeys then
        containerKeys = ns.CDMContainers.GetAllContainerKeys()
    end
    local restoredAny = false
    for _, key in ipairs(containerKeys) do
        if self:CheckDormantSpells(key) then
            restoredAny = true
        end
    end
    return restoredAny
end

function CDMSpellData:GetSpecEntries(containerKey, specKey)
    local list = GetSpecEntryList(containerKey, specKey, false)
    if type(list) == "table" then
        return list
    end

    local db = GetContainerDB(containerKey)
    if type(db) == "table" and db.specSpecific then
        return MoveLegacySpecEntriesToPerSpecStorage(containerKey, db)
    end
    return list
end

function CDMSpellData:OnSpecSpecificToggled(containerKey)
    local db = GetContainerDB(containerKey)
    if not db then return end
    local field = GetEntryListField(db)
    if db.specSpecific then
        local specList = GetSpecEntryList(containerKey, nil, true)
        if specList and #specList == 0 and type(db[field]) == "table" and #db[field] > 0 then
            for i, e in ipairs(db[field]) do
                specList[i] = CloneEntry(e)
            end
        end
    else
        local specList = GetSpecEntryList(containerKey, nil, false)
        if specList and #specList > 0 then
            db[field] = {}
            for i, e in ipairs(specList) do
                db[field][i] = CloneEntry(e)
            end
        end
    end
    FireChangeCallback()
end

function CDMSpellData:AddEntry(containerKey, entry)
    if CombatGuard() then return false end
    if not ValidateEntry(entry) then return false end

    local db = GetContainerDB(containerKey)
    if not db then return false end

    local list = GetMutableEntryList(db, containerKey, true)
    if not list then return false end

    if entry.kind == nil then
        entry.kind = ResolveEntryKind(entry, containerKey)
    end
    entry.isKnown = nil

    for _, existing in ipairs(list) do
        local norm = NormalizeOwnedEntry(existing)
        local existingID = norm and norm.id
        local entryID = entry.id
        if norm and norm.type == "item" and entry.type == "item" then
            existingID = (Sources and Sources.QueryBestOwnedItemVariant
                and Sources.QueryBestOwnedItemVariant(existingID)) or existingID
            entryID = (Sources and Sources.QueryBestOwnedItemVariant
                and Sources.QueryBestOwnedItemVariant(entryID)) or entryID
        end
        if norm and norm.type == entry.type and existingID == entryID then
            return false
        end
    end

    if entry.type == "spell" and type(entry.id) == "number"
        and type(db.dormantSpells) == "table" then
        db.dormantSpells[entry.id] = nil
    end

    list[#list + 1] = entry
    FireChangeCallback()
    return true
end

function CDMSpellData:RemoveEntry(containerKey, index, specKey)
    if CombatGuard() then return false end

    local db = GetContainerDB(containerKey)
    if not db then return false end
    local list = GetMutableEntryList(db, containerKey, false, specKey)
    if type(list) ~= "table" then return false end
    if type(index) ~= "number" then return false end
    if index < 1 or index > #list then return false end

    local entry = list[index]
    table.remove(list, index)

    if not db.specSpecific and GetEntryListField(db) == "ownedSpells"
        and entry and entry.id then
        self:_MigrateRemovedSpells(db)
        if not db.removedSpells then db.removedSpells = {} end
        local key = self:_HeroSubTreeKey()
        db.removedSpells[key] = db.removedSpells[key] or {}
        db.removedSpells[key][entry.id] = true
    end

    FireChangeCallback()
    return true
end

function CDMSpellData:ClearRemoved(db, spellID)
    self:_MigrateRemovedSpells(db)
    local rs = db and db.removedSpells
    if type(rs) ~= "table" or type(spellID) ~= "number" then return end
    if type(rs[0]) == "table" then rs[0][spellID] = nil end
    local bucket = rs[self:_HeroSubTreeKey()]
    if type(bucket) == "table" then bucket[spellID] = nil end
end

function CDMSpellData:ReorderEntry(containerKey, fromIndex, toIndex, specKey)
    if CombatGuard() then return false end

    local db = GetContainerDB(containerKey)
    if not db then return false end
    local list = GetMutableEntryList(db, containerKey, false, specKey)
    if type(list) ~= "table" then return false end
    if type(fromIndex) ~= "number" or type(toIndex) ~= "number" then return false end

    local len = #list
    if fromIndex < 1 or fromIndex > len then return false end
    if toIndex < 1 then return false end
    if fromIndex == toIndex then return true end

    local entry = table.remove(list, fromIndex)
    local insertAt = math.min(toIndex, #list + 1)
    table.insert(list, insertAt, entry)

    FireChangeCallback()
    return true
end

function CDMSpellData:MoveEntryBetweenContainers(fromKey, toKey, index)
    if CombatGuard() then return false end

    local fromDB = GetContainerDB(fromKey)
    local toDB = GetContainerDB(toKey)
    if not fromDB or type(fromDB.ownedSpells) ~= "table" then return false end
    if not toDB then return false end
    if index < 1 or index > #fromDB.ownedSpells then return false end

    local entry = table.remove(fromDB.ownedSpells, index)

    if entry and (entry.type == "item" or entry.type == "trinket" or entry.type == "slot")
        and Shared and Shared.GetBuiltinContainerEntryKind then
        local destKind = Shared.GetBuiltinContainerEntryKind(toKey)
        if destKind == "aura" then
            entry.kind = "aura"
            entry.displayMode = nil
        elseif destKind == "cooldown" then
            entry.kind = "cooldown"
        end
    end

    if toDB.ownedSpells == nil then
        toDB.ownedSpells = {}
    end
    toDB.ownedSpells[#toDB.ownedSpells + 1] = entry

    FireChangeCallback()
    return true
end

function CDMSpellData:IsSpellKnown(spellID)
    return IsSpellKnownByPlayer(spellID)
end

function CDMSpellData:IsEntryDormantForContainer(containerKey, entry)
    return IsEntryDormantForContainerInternal(containerKey, entry)
end

function CDMSpellData:IsSpellInCDMCategory(spellID, family)
    return IsSpellInCDMCategoryInternal(spellID, family)
end

function CDMSpellData:ResnapshotFromBlizzard(containerKey)
    if CombatGuard() then return false end

    local db = GetContainerDB(containerKey)
    if not db then return false end

    db.ownedSpells = nil
    db.removedSpells = {}

    self:SnapshotBlizzardCDM(containerKey)

    FireChangeCallback()
    return true
end

function CDMSpellData:AddSpell(containerKey, spellID, kind, row, source)
    return self:AddEntry(containerKey, {
        type = "spell",
        id = spellID,
        kind = kind,
        row = row,
        source = source,
    })
end

function CDMSpellData:AddItem(containerKey, itemID, row, kind)
    return self:AddEntry(containerKey, {
        type = "item",
        id = itemID,
        kind = kind or "cooldown",
        row = row,
    })
end

function CDMSpellData:AddTrinketSlot(containerKey, slotID, row, kind, source)
    return self:AddEntry(containerKey, {
        type = "slot",
        id = slotID,
        kind = kind or "cooldown",
        row = row,
        source = source,
    })
end

function CDMSpellData:AddConsumable(containerKey, categoryID, row, kind, source)
    return self:AddEntry(containerKey, {
        type = "consumable",
        id = categoryID,
        kind = kind or "cooldown",
        row = row,
        source = source,
    })
end

function CDMSpellData:HasResolvableAuraForItem(itemID)
    if type(itemID) ~= "number" or itemID <= 0 then return nil end
    if not Sources then return nil end

    local useSpellID
    if Sources.QueryItemSpell then
        local _, sid = Sources.QueryItemSpell(itemID)
        useSpellID = sid
    end

    if useSpellID then
        local auraIDs = CDMSpellData:GetAuraIDsForSpell(useSpellID)
        if auraIDs and type(auraIDs[1]) == "number" and auraIDs[1] > 0 then
            return auraIDs[1]
        end
    end

    local scanner = _G.QUI and _G.QUI.SpellScanner
    if scanner and scanner.GetScannedItemInfo then
        local info = scanner.GetScannedItemInfo(itemID)
        if info and type(info.buffSpellID) == "number" and info.buffSpellID > 0 then
            return info.buffSpellID
        end
    end

    return nil
end

function CDMSpellData:SetEntryRow(containerKey, index, rowNum)
    if CombatGuard() then return false end

    local db = GetContainerDB(containerKey)
    if not db or type(db.ownedSpells) ~= "table" then return false end
    if index < 1 or index > #db.ownedSpells then return false end

    local entry = db.ownedSpells[index]
    if not entry then return false end

    entry.row = rowNum
    FireChangeCallback()
    return true
end

function CDMSpellData:SetSpellOverride(containerKey, spellID, key, value)
    if CombatGuard() then return false end

    local db = GetContainerDB(containerKey)
    if not db then return false end

    if not db.spellOverrides then
        db.spellOverrides = {}
    end
    if not db.spellOverrides[spellID] then
        db.spellOverrides[spellID] = {}
    end

    db.spellOverrides[spellID][key] = value

    FireChangeCallback()
    return true
end

function CDMSpellData:ClearSpellOverride(containerKey, spellID, key)
    if CombatGuard() then return false end

    local db = GetContainerDB(containerKey)
    if not db or not db.spellOverrides or not db.spellOverrides[spellID] then
        return false
    end

    db.spellOverrides[spellID][key] = nil

    if next(db.spellOverrides[spellID]) == nil then
        db.spellOverrides[spellID] = nil
    end

    FireChangeCallback()
    return true
end

function CDMSpellData:GetSpellOverride(containerKey, spellID)
    local db = GetContainerDB(containerKey)
    if not db or not db.spellOverrides then return nil end
    return db.spellOverrides[spellID]
end

function CDMSpellData:GetAvailableSpells(containerKey)
    local db = GetContainerDB(containerKey)

    local ownedSet = CDMSpellData.BuildOwnedSet(db)

    local containerType = db and db.containerType
    if not containerType then
        local ncdm = GetNcdmDB()
        if ncdm and ncdm.containers and ncdm.containers[containerKey] then
            containerType = ncdm.containers[containerKey].containerType
        end
    end

    local catalog = ns.CDMCatalog
    if catalog and catalog.GetAvailableSpellsForContainer then
        return catalog.GetAvailableSpellsForContainer(containerKey, containerType, ownedSet, _cdIDToCorrectSID)
    end
    return {}
end

function CDMSpellData:GetAllLearnedCooldowns()
    if learnedCooldownsCache and not learnedCooldownsCacheDirty then
        return learnedCooldownsCache
    end

    local result = {}
    local seen = {}

    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
local numTabs = C_SpellBook.GetNumSpellBookSkillLines()
        if numTabs then
            for tab = 1, numTabs do
local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(tab)
                if skillLineInfo and skillLineInfo.name ~= GENERAL then
                    local offset = skillLineInfo.itemIndexOffset or 0
                    local numEntries = skillLineInfo.numSpellBookItems or 0
                    for i = 1, numEntries do
                        local slotIndex = offset + i
local itemInfo = C_SpellBook.GetSpellBookItemInfo(slotIndex, Enum.SpellBookSpellBank.Player)
                        if itemInfo and itemInfo.spellID and not itemInfo.isPassive and not itemInfo.isOffSpec then
                            local sid = itemInfo.spellID
                            if not seen[sid] then
                                seen[sid] = true
                                local baseCDms = 0
                                if Sources and Sources.QuerySpellBaseCooldown then
                                    local ms = Sources.QuerySpellBaseCooldown(sid)
                                    if ms then baseCDms = ms end
                                end
                                if baseCDms <= 1500 and Sources and Sources.QuerySpellCharges then
                                    local ci = Sources.QuerySpellCharges(sid)
                                    if ci then
                                        local maxC = ci.maxCharges or 0
                                        if maxC > 1 then baseCDms = 2000 end
                                    end
                                end
                                local name, icon
                                local spellInfo = Sources and Sources.QuerySpellInfo and Sources.QuerySpellInfo(sid)
                                if spellInfo then
                                    name = spellInfo.name
                                    icon = spellInfo.iconID
                                end
                                result[#result + 1] = {
                                    spellID = sid,
                                    name = name or "",
                                    icon = icon or 0,
                                    cooldown = baseCDms / 1000,
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    do
        local _, raceFile = UnitRace("player")
        local _, classFile = UnitClass("player")
        -- @secret-policy: collapse-only — UnitRace/UnitClass can return SECRET on
        if issecretvalue and issecretvalue(raceFile) then raceFile = nil end
        if issecretvalue and issecretvalue(classFile) then classFile = nil end
        local racials = raceFile and RACE_RACIALS[raceFile]
        if racials then
            for _, racialEntry in ipairs(racials) do
                local sid, classFilter
                if type(racialEntry) == "table" then
                    sid = racialEntry[1]
                    classFilter = racialEntry.class
                else
                    sid = racialEntry
                end
                if sid and not seen[sid] and (not classFilter or classFilter == classFile) then
                    seen[sid] = true
                    local rName, rIcon
                    local spellInfo = Sources and Sources.QuerySpellInfo and Sources.QuerySpellInfo(sid)
                    if spellInfo then
                        rName = spellInfo.name
                        rIcon = spellInfo.iconID
                    end
                    if rName then
                        local baseCDms = 0
                        if Sources and Sources.QuerySpellBaseCooldown then
                            local ms = Sources.QuerySpellBaseCooldown(sid)
                            if ms then baseCDms = ms end
                        end
                        result[#result + 1] = {
                            spellID = sid,
                            name = rName,
                            icon = rIcon or 0,
                            cooldown = baseCDms / 1000,
                        }
                    end
                end
            end
        end
    end

    learnedCooldownsCache = result
    learnedCooldownsCacheDirty = false
    return result
end

function CDMSpellData:GetActiveAuras(filter)
    local result = {}
    local seen = {}

    local entries = _capturedAuraByUnitSpellID.player
    if not entries then return result end
    for sid, auraData in pairs(entries) do
        if sid and not seen[auraData] and CapturedAuraMatchesFilter(auraData, {
            player = filter or "HELPFUL",
        }) then
            seen[auraData] = true
            local rawAuraData = GetCapturedAuraData(auraData)
            local icon = rawAuraData and rawAuraData.icon
            local duration = rawAuraData and rawAuraData.duration
            if (issecretvalue and issecretvalue(icon)) or type(icon) ~= "number" then
                icon = 0
            end
            if (issecretvalue and issecretvalue(duration)) or type(duration) ~= "number" then
                duration = 0
            end
            result[#result + 1] = {
                spellID = GetCleanAuraSpellID(rawAuraData) or auraData.spellID or sid,
                name = auraData.name or "",
                icon = icon,
                duration = duration,
            }
        end
    end

    return result
end

function CDMSpellData:GetPassiveAuras()
    local result = {}
    local seen = {}

    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then
        return result
    end

local numTabs = C_SpellBook.GetNumSpellBookSkillLines()
    if not numTabs then return result end

    for tab = 1, numTabs do
local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(tab)
        if skillLineInfo and skillLineInfo.name ~= GENERAL then
            local offset = skillLineInfo.itemIndexOffset or 0
            local numEntries = skillLineInfo.numSpellBookItems or 0
            for i = 1, numEntries do
                local slotIndex = offset + i
local itemInfo = C_SpellBook.GetSpellBookItemInfo(slotIndex, Enum.SpellBookSpellBank.Player)
                if itemInfo and itemInfo.spellID and itemInfo.isPassive and not itemInfo.isOffSpec then
                    local sid = itemInfo.spellID
                    if not seen[sid] then
                        seen[sid] = true
                        local name, icon
                        local spellInfo = Sources and Sources.QuerySpellInfo and Sources.QuerySpellInfo(sid)
                        if spellInfo then
                            name = spellInfo.name
                            icon = spellInfo.iconID
                        end
                        result[#result + 1] = {
                            spellID = sid,
                            name = name or "",
                            icon = icon or 0,
                        }
                    end
                end
            end
        end
    end

    return result
end

local function GetItemProfessionQualityRank(itemInfo)
    if not itemInfo or not (Sources and Sources.QueryItemProfessionQualityInfo) then
        return 0
    end

    local info = Sources.QueryItemProfessionQualityInfo(itemInfo)
    if issecretvalue and issecretvalue(info) then return 0 end -- @secret-policy: reject-secret-value
    if type(info) ~= "table" then return 0 end
    local quality = info.quality
    if issecretvalue and issecretvalue(quality) then return 0 end -- @secret-policy: reject-secret-value
    if type(quality) == "number" then return quality end
    return 0
end

local function SortBagItemsByProfessionQuality(items)
    if type(items) ~= "table" or #items <= 1 then return end
    table.sort(items, function(a, b)
        local aq = (type(a) == "table" and a._professionQualityRank) or 0
        local bq = (type(b) == "table" and b._professionQualityRank) or 0
        if aq ~= bq then return aq > bq end
        local ao = (type(a) == "table" and a._bagOrder) or 0
        local bo = (type(b) == "table" and b._bagOrder) or 0
        return ao < bo
    end)
end

function CDMSpellData:GetUsableItems()
    local result = {}

    for _, slotID in ipairs({ 13, 14 }) do
        local itemID = Sources and Sources.QueryInventoryItemID
            and Sources.QueryInventoryItemID("player", slotID)
        if itemID then
            local name, icon
            local itemName = Sources and Sources.QueryItemNameByID and Sources.QueryItemNameByID(itemID)
            if itemName then name = itemName end
            local itemIcon = Sources and Sources.QueryItemIconByID and Sources.QueryItemIconByID(itemID)
            if itemIcon then icon = itemIcon end

            local hasSpell = false
            if Sources and Sources.QueryItemSpell then
                local spellName = Sources.QueryItemSpell(itemID)
                if spellName then hasSpell = true end
            end

            if hasSpell then
                result[#result + 1] = {
                    type = "slot",
                    id = slotID,
                    itemID = itemID,
                    name = name or "",
                    icon = icon or 0,
                    slotID = slotID,
                }
            end
        end
    end

    local bagItems = {}
    local seenItemIDs = {}
    if C_Container and C_Container.GetContainerNumSlots then
        for bag = 0, 4 do
local numSlots = C_Container.GetContainerNumSlots(bag)
            if numSlots then
                for slot = 1, numSlots do
local containerInfo = C_Container.GetContainerItemInfo(bag, slot)
                    if containerInfo and containerInfo.itemID then
                        local itemID = containerInfo.itemID
                        if Sources and Sources.QueryItemSpell then
                            local spellName = Sources.QueryItemSpell(itemID)
                            if spellName then
                                local name = containerInfo.itemName or ""
                                local icon = containerInfo.iconFileID or 0
                                local qualityLookup = itemID
                                local hyperlink = containerInfo.hyperlink
                                if hyperlink and not (issecretvalue and issecretvalue(hyperlink)) then
                                    qualityLookup = hyperlink
                                end
                                local qualityRank = GetItemProfessionQualityRank(qualityLookup)
                                local existingIdx = seenItemIDs[itemID]
                                if existingIdx then
                                    local existing = bagItems[existingIdx]
                                    local existingRank = existing and existing._professionQualityRank
                                    if qualityRank ~= nil
                                        and (existingRank == nil or qualityRank > existingRank) then
                                        existing.name = name
                                        existing.icon = icon
                                        existing._professionQualityRank = qualityRank
                                    end
                                else
                                    bagItems[#bagItems + 1] = {
                                        type = "item",
                                        id = itemID,
                                        itemID = itemID,
                                        name = name,
                                        icon = icon,
                                        slotID = nil,
                                        _bagOrder = #bagItems + 1,
                                        _professionQualityRank = qualityRank,
                                    }
                                    seenItemIDs[itemID] = #bagItems
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    SortBagItemsByProfessionQuality(bagItems)
    for _, item in ipairs(bagItems) do
        item._bagOrder = nil
        item._professionQualityRank = nil
        result[#result + 1] = item
    end

    return result
end

function CDMSpellData:GetSpellList(viewerType)
    local db = GetContainerDB(viewerType)
    if db and db.containerType == "customBar" then
        return {}
    end
    local hasOwned = db and db.ownedSpells ~= nil
    if hasOwned then
        local result = self:BuildSpellListFromOwned(viewerType)
        return result
    end
    return {}
end

function CDMSpellData:InvalidateLearnedCache()
    InvalidateLearnedCooldownsCache()
end

function CDMSpellData:GetCacheStats()
    local function size(t)
        if type(t) ~= "table" then return 0 end
        local n = 0
        for _ in pairs(t) do n = n + 1 end
        return n
    end
    local function capturedStats()
        local seenEntries = {}
        local seenUnits = {}
        local entryCount = 0
        local unitCount = 0

        local function addEntry(entry)
            if type(entry) == "table" and not seenEntries[entry] then
                seenEntries[entry] = true
                entryCount = entryCount + 1
            end
        end

        local function addUnit(unit)
            if unit and not seenUnits[unit] then
                seenUnits[unit] = true
                unitCount = unitCount + 1
            end
        end

        for _, entry in pairs(_capturedAuraBySpellID) do
            addEntry(entry)
            addUnit(entry and entry.unit)
        end
        for _, entry in pairs(_capturedAuraByName) do
            addEntry(entry)
            addUnit(entry and entry.unit)
        end
        for unit, map in pairs(_capturedAuraByUnitSpellID) do
            addUnit(unit)
            for _, entry in pairs(map) do
                addEntry(entry)
                addUnit(entry and entry.unit)
            end
        end
        for unit, map in pairs(_capturedAuraByUnitName) do
            addUnit(unit)
            for _, entry in pairs(map) do
                addEntry(entry)
                addUnit(entry and entry.unit)
            end
        end

        return entryCount, unitCount
    end
    local learnedSize = 0
    if type(learnedCooldownsCache) == "table" then
        learnedSize = #learnedCooldownsCache
    end
    local capturedAuraEntries, capturedAuraUnits = capturedStats()
    return {
        capturedAuraEntries = capturedAuraEntries,
        capturedAuraUnits   = capturedAuraUnits,
        capturedAuraSpellKeys = size(_capturedAuraBySpellID),
        capturedAuraNameKeys  = size(_capturedAuraByName),
        learnedDirty        = learnedCooldownsCacheDirty and true or false,
        learnedSize         = learnedSize,
    }
end

local function RegisterEditModeCallbacks()
    local QUICore = ns.Addon
    if not QUICore then return end

    if QUICore.RegisterEditModeEnter then
        QUICore:RegisterEditModeEnter(function()
            if _G.QUI_OnEditModeEnterCDM then
                _G.QUI_OnEditModeEnterCDM()
            end
        end)
    end

    if QUICore.RegisterEditModeExit then
        QUICore:RegisterEditModeExit(function()
            if _G.QUI_OnEditModeExitCDM then
                _G.QUI_OnEditModeExitCDM()
            end
        end)
    end
end

function CDMSpellData:Initialize()
    ClearDeprecatedLearnedCastToAuraDB()

    if not IsCDMRuntimeEnabled() then
        return
    end

    RegisterAuraCaptureFrame()

    ForceLoadCDM()
    C_Timer.After(0.5, function()
        if not IsCDMRuntimeEnabled() then return end
        RegisterEditModeCallbacks()
        initialized = true
        if not InCombatLockdown() then
            CDMSpellData:ReconcileAllContainers()
        end
    end)
    local _spellsChangedToken = 0
    local _cdmViewerReconcileToken = 0
    local _cooldownViewerRebuildPending = false
    local _cooldownViewerRebuildNeedsRefresh = false
    local function RefreshNativeReanchorHooks(markDirty)
        local containers = ns.CDMContainers
        local refreshHooks = containers and containers.RefreshReanchorRuntimeHooks
        if refreshHooks then
            refreshHooks(markDirty ~= false)
        end
    end
    ns._cdmColdLoadActive = true

    local eventFrame = CreateFrame("Frame")
    runtimeEventFrame = eventFrame
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("SPELLS_CHANGED")
    eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    eventFrame:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED")
    eventFrame:RegisterEvent("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED")
    eventFrame:RegisterEvent("COOLDOWN_VIEWER_TABLE_HOTFIXED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:SetScript("OnEvent", function(self, event, arg)
        if not IsCDMRuntimeEnabled() then
            self:UnregisterAllEvents()
            return
        end

        if event == "PLAYER_SPECIALIZATION_CHANGED" then
            InvalidateLearnedCooldownsCache()
        elseif event == "SPELLS_CHANGED" then
            InvalidateLearnedCooldownsCache()
            if _inZoneTransition then
                _spellsChangedDuringZoneTransition = true
                return
            end
            if ns._cdmColdLoadActive then
                return
            end
            _spellsChangedToken = _spellsChangedToken + 1
            local token = _spellsChangedToken
            C_Timer.After(0.3, function()
                if not IsCDMRuntimeEnabled() then return end
                if token ~= _spellsChangedToken then
                    return
                end
                if not InCombatLockdown() then
                    RunReconcileSequence(true)
                end
            end)
        elseif event == "PLAYER_EQUIPMENT_CHANGED" then
            if not InCombatLockdown() then
                CDMSpellData:ReconcileAllContainers()
            end
        elseif event == "COOLDOWN_VIEWER_DATA_LOADED"
            or event == "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED"
            or event == "COOLDOWN_VIEWER_TABLE_HOTFIXED" then
            if InCombatLockdown() then
                _cooldownViewerRebuildPending = true
                if event ~= "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED" then
                    _cooldownViewerRebuildNeedsRefresh = true
                end
                return
            end
            if ns._cdmColdLoadActive then
                return
            end
            RebuildSpellToCooldownID()
            local isOverrideUpdate = event == "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED"
            if not isOverrideUpdate then
                FireChangeCallback()
                RefreshNativeReanchorHooks(false)
            end
            _cdmViewerReconcileToken = _cdmViewerReconcileToken + 1
            local token = _cdmViewerReconcileToken
            C_Timer.After(0.5, function()
                if not IsCDMRuntimeEnabled() then return end
                if token ~= _cdmViewerReconcileToken then return end
                if not InCombatLockdown() then
                    local _, snapshotReady = SnapshotUnsetBuiltinContainers()
                    if not snapshotReady then
                        CDMSpellData:RunColdLoadReconcile()
                        return
                    end
                    RunReconcileSequence(isOverrideUpdate)
                    if not isOverrideUpdate then
                        RefreshNativeReanchorHooks(false)
                    end
                end
            end)
        elseif event == "PLAYER_REGEN_ENABLED" then
            if _cooldownViewerRebuildPending then
                _cooldownViewerRebuildPending = false
                local needsRefresh = _cooldownViewerRebuildNeedsRefresh
                _cooldownViewerRebuildNeedsRefresh = false
                RebuildSpellToCooldownID()
                if needsRefresh then
                    FireChangeCallback()
                    RefreshNativeReanchorHooks(false)
                end
            end
            for i = 1, #REGISTERED_UNITS do
                local unit = REGISTERED_UNITS[i]
                if RescanCapturedAurasForUnit(unit) then
                    NotifyAuraConsumers(unit, nil)
                end
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            _inZoneTransition = true
            C_Timer.After(2.0, function()
                _inZoneTransition = false
                if _spellsChangedDuringZoneTransition then
                    _spellsChangedDuringZoneTransition = false
                    if IsCDMRuntimeEnabled() and not InCombatLockdown()
                        and not ns._cdmColdLoadActive then
                        RunReconcileSequence()
                    end
                end
            end)
            C_Timer.After(1.0, function()
                if not IsCDMRuntimeEnabled() then return end
                if not initialized then
                    ForceLoadCDM()
                    C_Timer.After(0.5, function()
                        if not IsCDMRuntimeEnabled() then return end
                        RegisterEditModeCallbacks()
                        initialized = true
                    end)
                end
            end)
        end
    end)

    C_Timer.After(2.0, function()
        if ns._cdmColdLoadActive then
            CDMSpellData:RunColdLoadReconcile()
        end
    end)

    local reg = ns.DebugRegister; if reg then reg(function()
        ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
        ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "CDM_SpellData", frame = eventFrame }
    end) end
end

function CDMSpellData:GetAuraIDsForSpell(spellID)
    if not spellID then return nil end
    if not next(_spellToCooldownID) then
        RebuildSpellToCooldownID()
    end
    return _auraIDsForSpell[spellID]
end

function CDMSpellData:IsSelfAuraSpell(spellID)
    if not spellID then return nil end
    if not next(_spellToCooldownID) then
        RebuildSpellToCooldownID()
    end
    local cooldownID = _spellToCooldownID[spellID]
    local catalog = ns.CDMCatalog
    if not (cooldownID and catalog and catalog.GetCooldownInfo) then return nil end
    local info = catalog.GetCooldownInfo(cooldownID)
    if not info then return nil end
    return info.selfAura == true
end
CDMSpellData.ResolveEntryKind = ResolveEntryKind
CDMSpellData.IsAuraEntry = IsAuraEntry
CDMSpellData.GetContainerDB = GetContainerDB
CDMSpellData.GetEntryListField = GetEntryListField
CDMSpellData.GetCapturedAuraForLookup = GetCapturedAuraForLookup
if ns.CDMAuraRuntime then
    if ns.CDMAuraRuntime.SetApplicationsGetter then
        ns.CDMAuraRuntime.SetApplicationsGetter(GetAuraApplications)
    end
    if ns.CDMAuraRuntime.SetCapturedAuraGetter then
        ns.CDMAuraRuntime.SetCapturedAuraGetter(GetCapturedAuraForLookup)
    end
end

function CDMSpellData:ResolveDisplaySpellID(entry)
    return entry and (entry.overrideSpellID or entry.spellID or entry.id)
end

function CDMSpellData:ResolveDisplayName(entry)
    if entry and entry.isAura then
        local sid = self:ResolveDisplaySpellID(entry)
        if sid then
            local info = Sources and Sources.QuerySpellInfo and Sources.QuerySpellInfo(sid)
            if info and info.name then return info.name end
        end
    end
    return (entry and entry.name) or ""
end

ns.CDMSpellData = CDMSpellData

function CDMSpellData._BindDebugImports()
    local d = ns.CDMDebug
    if d then
        ShouldDebugAuraState  = d.ShouldAura            or ShouldDebugAuraState
        AuraStateDebug        = d.Aura                  or AuraStateDebug
        FormatIDList          = d.FormatIDList          or FormatIDList
    end
end
