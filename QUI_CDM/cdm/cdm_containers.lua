-- luacheck: globals RegisterEventCallback

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local QUICore = ns.Addon
local UIKit = ns.UIKit
local LSM = ns.LSM
local CDMLayout = ns.CDMLayout
local Shared = ns.CDMShared

local type = type
local pairs = pairs
local ipairs = ipairs
local pcall = pcall
local C_Timer = C_Timer
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local hooksecurefunc = hooksecurefunc

local function IsCDMRuntimeEnabled()
    return not Shared or Shared.IsRuntimeEnabled()
end

local function BuildLinkedSpellIDsFingerprint(linkedSpellIDs)
    if type(linkedSpellIDs) ~= "table" then
        return ""
    end

    local parts = {}
    for i, linkedID in ipairs(linkedSpellIDs) do
        if issecretvalue and issecretvalue(linkedID) then
            parts[i] = "secret" -- @secret-policy: encode-secret-as-placeholder
        else
            parts[i] = tostring(linkedID or 0)
        end
    end
    return table.concat(parts, ";")
end

local FALLBACK_BUILTIN_COOLDOWN_CONTAINER_KEYS = { "essential", "utility" }

local function GetBuiltinCooldownContainerKeys()
    if Shared and Shared.GetBuiltinContainerKeysByEntryKind then
        return Shared.GetBuiltinContainerKeysByEntryKind("cooldown")
    end
    return FALLBACK_BUILTIN_COOLDOWN_CONTAINER_KEYS
end

local inInitSafeWindow = false

local HUD_MIN_WIDTH_DEFAULT = Helpers.HUD_MIN_WIDTH_DEFAULT or 200
local SETTINGS_FEATURE_ID = "cooldownManagerContainersPage"
local registeredSettingsLookupKeys = {}
local ANCHOR_KEY_MAP
local SyncSettingsFeatureLookups

local containers = {}
local viewerState = {}
local buffFingerprint = nil
local applying = {}
local refreshTimers = {}
local postLayoutRuntimeRefreshing = {}
local initialized = false
local runtimeEventFrame = nil
local RegisterContainerFrame
local SyncContainerMouseState
local SyncAllContainerMouseStates
local ApplyUtilityAnchor

local UtilityAnchorProxy = nil
local CreateContainer

local function CancelRefreshTimers()
    for i, handle in pairs(refreshTimers) do
        if handle and handle.Cancel then
            handle:Cancel()
        end
        refreshTimers[i] = nil
    end
end

local IsCooldownViewerReady
local initialReanchorDoneByKey = {}
local REANCHOR_KEYS = { "essential", "utility", "buff" }
local refreshAllReanchorBatchActive = false
local refreshAllReanchorBatchCounts

local function ResetInitialReanchorDone()
    for key in pairs(initialReanchorDoneByKey) do
        initialReanchorDoneByKey[key] = nil
    end
end

local function MarkInitialReanchorDone(key)
    if key then
        initialReanchorDoneByKey[key] = true
    end
end

local function IsInitialReanchorDone(key)
    return initialReanchorDoneByKey[key] == true
end

local function RefreshReanchoredBuiltin(boot, key, allowCachedBatch, requestedKeys)
    if not (boot and boot.RefreshBuiltin) then return nil end
    local refreshKeys = requestedKeys or REANCHOR_KEYS
    local result
    if boot.RefreshBuiltins then
        local counts
        if allowCachedBatch and refreshAllReanchorBatchActive
            and refreshAllReanchorBatchCounts then
            counts = refreshAllReanchorBatchCounts
        else
            counts = boot:RefreshBuiltins(refreshKeys) or {}
            if refreshAllReanchorBatchActive then
                refreshAllReanchorBatchCounts = counts
            end
        end
        result = counts[key] or 0
    else
        if requestedKeys then
            for i = 1, #refreshKeys do
                local refreshKey = refreshKeys[i]
                local count = boot:RefreshBuiltin(refreshKey)
                if refreshKey == key then result = count end
            end
        else
            result = boot:RefreshBuiltin(key)
        end
    end
    if not IsCooldownViewerReady or IsCooldownViewerReady() then
        if boot.RefreshBuiltins or requestedKeys then
            for i = 1, #refreshKeys do MarkInitialReanchorDone(refreshKeys[i]) end
        else
            MarkInitialReanchorDone(key)
        end
    end
    return result
end

local function BlankReanchoredNativeItemFrame(frame)
    if not frame then return end
    if frame.SetAlpha then frame:SetAlpha(0) end
end

local GetDB = Helpers.CreateDBGetter("ncdm")

local function GetTrackerSettings(trackerKey)
    if Shared and Shared.GetContainerDB then
        local containerDB = Shared.GetContainerDB(trackerKey)
        if containerDB then return containerDB end
    end

    local db = GetDB()
    if not db then return nil end
    if Shared and ((Shared.IsBuiltinContainerKey and Shared.IsBuiltinContainerKey(trackerKey))
        or (Shared.GetBuiltinContainerEntryKind and Shared.GetBuiltinContainerEntryKind(trackerKey))) then
        return db[trackerKey]
    end
    return db.containers and db.containers[trackerKey] or nil
end

local function IsHUDAnchoredToCDM()
    local profile = QUICore and QUICore.db and QUICore.db.profile
    if Helpers and Helpers.IsHUDAnchoredToCDM then
        return Helpers.IsHUDAnchoredToCDM(profile)
    end
    return false
end

local function GetHUDMinWidth()
    local profile = QUICore and QUICore.db and QUICore.db.profile
    if Helpers and Helpers.GetHUDMinWidthSettingsFromProfile then
        return Helpers.GetHUDMinWidthSettingsFromProfile(profile)
    end
    return false, HUD_MIN_WIDTH_DEFAULT
end

local CDMContainers_API
local _previousSpecID = nil
local specTrackingReady = false
local specTrackingPendingRefresh = false
local specTrackingRetryToken = 0
local profileCallbackSink = nil
local lastKnownProfile = nil
local RefreshAll
local _refreshAllFrameGuard = false

local SPEC_TRACKING_RETRY_DELAY = 0.5
local SPEC_TRACKING_MAX_RETRIES = 6

local _previousLoadoutID = nil
local _lastKnownSavedConfigID = nil
local _lastKnownHeroSubTree = nil
local loadoutListReady = false
local pendingLoadoutRefresh = false
local loadoutTrackingToken = 0
local loadoutDebounceTimer = nil
local NO_SAVED_LOADOUT_ID = -2
local pendingClassTalentSwitchSpecID = nil
local pendingClassTalentSwitchLoadoutSpecID = nil
local pendingClassTalentSwitchLoadoutID = nil
local classTalentSwitchCallbacksRegistered = false
local _hydratedLoadoutID = nil
local _initialLoadoutResolved = false

local _loadoutChangeCallbacks = {}

local function RegisterLoadoutChangeCallback(fn)
    if type(fn) == "function" then
        _loadoutChangeCallbacks[#_loadoutChangeCallbacks + 1] = fn
    end
end

local function FireLoadoutChangeCallbacks()
    for i = 1, #_loadoutChangeCallbacks do
        ns.SafeCall("bulkhead", _loadoutChangeCallbacks[i])
    end
end

local function GetCurrentSpecID()
    return Helpers.GetCurrentSpecID()
end

local function NormalizeLoadoutID(loadoutID)
    if loadoutID == nil then return nil end
    if loadoutID == NO_SAVED_LOADOUT_ID then return 0 end
    return loadoutID
end

local function GetCurrentHeroSubTree()
    local id = C_ClassTalents and C_ClassTalents.GetActiveHeroTalentSpec
        and C_ClassTalents.GetActiveHeroTalentSpec()
    if type(id) == "number" and id > 0 then return id end
    return -1
end

local function GetPlayerClassID()
    if not UnitClass then return nil end
    local _, _, classID = UnitClass("player")
    return classID
end

local function ResolveSpecIDByIndex(specIndex)
    if type(specIndex) ~= "number" then
        specIndex = tonumber(specIndex)
    end
    if not specIndex or specIndex <= 0 then return nil end
    if not GetSpecializationInfo then return nil end

    local classID = GetPlayerClassID()
    local specID = GetSpecializationInfo(specIndex, false, false, nil, nil, nil, classID)
    if type(specID) == "number" and specID ~= 0 then
        return specID
    end
    return nil
end

local function ResolveSpecIDByName(specName)
    if type(specName) ~= "string" or specName == "" then return nil end
    if not (C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID and GetSpecializationInfo) then
        return nil
    end

    local classID = GetPlayerClassID()
    if not classID then return nil end

    local specCount = C_SpecializationInfo.GetNumSpecializationsForClassID(classID)
    for specIndex = 1, specCount do
        local specID, name = GetSpecializationInfo(specIndex, false, false, nil, nil, nil, classID)
        if name == specName and type(specID) == "number" and specID ~= 0 then
            return specID
        end
    end
    return nil
end

local function ResolveLoadoutIDByIndex(specID, loadoutIndex)
    if type(loadoutIndex) ~= "number" then
        loadoutIndex = tonumber(loadoutIndex)
    end
    if not specID or specID == 0 or not loadoutIndex or loadoutIndex <= 0 then return nil end
    if not (C_ClassTalents and C_ClassTalents.GetConfigIDsBySpecID) then return nil end

    local configIDs = C_ClassTalents.GetConfigIDsBySpecID(specID)
    local configID = type(configIDs) == "table" and configIDs[loadoutIndex]
    return NormalizeLoadoutID(configID)
end

local function ResolveLoadoutIDByName(specID, loadoutName)
    if type(loadoutName) ~= "string" or loadoutName == "" then return nil end
    if not specID or specID == 0 then return nil end
    if not (C_ClassTalents and C_ClassTalents.GetConfigIDsBySpecID and C_Traits and C_Traits.GetConfigInfo) then
        return nil
    end

    local configIDs = C_ClassTalents.GetConfigIDsBySpecID(specID)
    if type(configIDs) ~= "table" then return nil end

    for _, configID in ipairs(configIDs) do
        local configInfo = C_Traits.GetConfigInfo(configID)
        if configInfo and configInfo.name == loadoutName then
            return NormalizeLoadoutID(configID)
        end
    end
    return nil
end

local function SetPendingClassTalentSpecSwitch(specID)
    if type(specID) == "number" and specID ~= 0 then
        pendingClassTalentSwitchSpecID = specID
    end
end

local function ConsumePendingClassTalentSpecSwitchID()
    local specID = pendingClassTalentSwitchSpecID
    pendingClassTalentSwitchSpecID = nil
    return specID
end

local function SetPendingClassTalentLoadoutSwitch(specID, loadoutID)
    if type(specID) == "number" and specID ~= 0 and loadoutID ~= nil then
        pendingClassTalentSwitchLoadoutSpecID = specID
        pendingClassTalentSwitchLoadoutID = loadoutID
    end
end

local function GetPendingClassTalentLoadoutIDForSpec(specID)
    if pendingClassTalentSwitchLoadoutSpecID == specID then
        return pendingClassTalentSwitchLoadoutID
    end
    return nil
end

local function ConsumePendingClassTalentLoadoutIDForSpec(specID)
    if pendingClassTalentSwitchLoadoutSpecID ~= specID then
        return nil
    end
    local loadoutID = pendingClassTalentSwitchLoadoutID
    pendingClassTalentSwitchLoadoutSpecID = nil
    pendingClassTalentSwitchLoadoutID = nil
    return loadoutID
end

local function ClearPendingClassTalentSwitchIntent()
    pendingClassTalentSwitchSpecID = nil
    pendingClassTalentSwitchLoadoutSpecID = nil
    pendingClassTalentSwitchLoadoutID = nil
end

local function GetCurrentCharacterKey()
    if not UnitName then return nil end
    local name, realm = UnitName("player")
    if issecretvalue and issecretvalue(name) then return nil end -- @secret-policy: reject-secret-ids
    if issecretvalue and issecretvalue(realm) then realm = nil end
    if type(name) ~= "string" or name == "" then
        return nil
    end
    if type(realm) ~= "string" or realm == "" then
        realm = nil
        if GetRealmName then
            realm = GetRealmName()
            if issecretvalue and issecretvalue(realm) then realm = nil end
        end
    end
    if type(realm) ~= "string" or realm == "" then
        return name
    end
    return name .. " - " .. realm
end

local function GetCurrentProfileName()
    local db = QUICore and QUICore.db
    if db and db.GetCurrentProfile then
        local ok, profileName = ns.SafeCallMethod("best-effort-style", db, "GetCurrentProfile")
        if ok and type(profileName) == "string" and profileName ~= "" then
            return profileName
        end
    end
    return "Default"
end

local function GetCharNcdmDB(create)
    local db = QUICore and QUICore.db
    local charDB = db and db.char
    if type(charDB) ~= "table" then
        return nil
    end
    if type(charDB.ncdm) ~= "table" then
        if not create then return nil end
        charDB.ncdm = {}
    end
    return charDB.ncdm
end

local function GetSpecStateDB(create)
    return GetCharNcdmDB(create) or GetDB()
end

local function LiveContainerOwnedByOtherCharacter()
    local profileDB = GetDB()
    local owner = profileDB and profileDB._lastSpecCharKey
    if not owner then return false end
    local currentCharKey = GetCurrentCharacterKey()
    return currentCharKey ~= nil and owner ~= currentCharKey
end

local function GetSpecProfileStore(create)
    local charNcdm = GetCharNcdmDB(create)
    if not charNcdm then
        return nil
    end

    if type(charNcdm._specProfilesByProfile) ~= "table" then
        if not create then return nil end
        charNcdm._specProfilesByProfile = {}
    end
    local profileName = GetCurrentProfileName()
    if type(charNcdm._specProfilesByProfile[profileName]) ~= "table" then
        if not create then return nil end
        charNcdm._specProfilesByProfile[profileName] = {}
    end
    return charNcdm._specProfilesByProfile[profileName]
end

local LEGACY_CONTAINER_KEYS = {
    essential  = true,
    utility    = true,
    buff       = true,
    trackedBar = true,
}

local function GetEffectiveLoadoutIDForSpec(specID)
    local profileDB = GetDB()
    if not profileDB or not profileDB.perLoadoutSpec then return 0 end
    if not specID or specID == 0 then return 0 end

    local pendingLoadoutID = GetPendingClassTalentLoadoutIDForSpec(specID)
    if pendingLoadoutID ~= nil then
        return pendingLoadoutID
    end

    local savedID
    if C_ClassTalents and C_ClassTalents.GetLastSelectedSavedConfigID then
        savedID = C_ClassTalents.GetLastSelectedSavedConfigID(specID)
    end

    if not savedID then
        local charNcdm = GetCharNcdmDB(false)
        local cache = charNcdm and charNcdm._lastLoadoutConfigID
        local cachedID = cache and cache[specID]
        if type(cachedID) == "number" and cachedID > 0 then
            return cachedID
        end
        return 0
    end

    return NormalizeLoadoutID(savedID)
end

local function GetEffectiveLoadoutID()
    return GetEffectiveLoadoutIDForSpec(GetCurrentSpecID())
end

local function RegisterClassTalentSwitchCallbacks()
    if classTalentSwitchCallbacksRegistered or type(RegisterEventCallback) ~= "function" then
        return
    end
    classTalentSwitchCallbacksRegistered = true

    RegisterEventCallback("CLASS_TALENTS_SWITCH_TO_SPECIALIZATION_BY_NAME", function(_, specName)
        SetPendingClassTalentSpecSwitch(ResolveSpecIDByName(specName))
    end)

    RegisterEventCallback("CLASS_TALENTS_SWITCH_TO_SPECIALIZATION_BY_INDEX", function(_, specIndex)
        SetPendingClassTalentSpecSwitch(ResolveSpecIDByIndex(specIndex))
    end)

    RegisterEventCallback("CLASS_TALENTS_SWITCH_TO_LOADOUT_BY_NAME", function(_, loadoutName)
        local specID = GetCurrentSpecID()
        SetPendingClassTalentLoadoutSwitch(specID, ResolveLoadoutIDByName(specID, loadoutName))
    end)

    RegisterEventCallback("CLASS_TALENTS_SWITCH_TO_LOADOUT_BY_INDEX", function(_, loadoutIndex)
        local specID = GetCurrentSpecID()
        SetPendingClassTalentLoadoutSwitch(specID, ResolveLoadoutIDByIndex(specID, loadoutIndex))
    end)
end

local function GetSpecLoadoutProfileStore(specID, loadoutID, create)
    if not specID or specID == 0 then return nil end
    local store = GetSpecProfileStore(create)
    if not store then return nil end

    local specSlot = store[specID]
    if type(specSlot) == "table" then
        local isLegacyShape = false
        for k in pairs(specSlot) do
            if LEGACY_CONTAINER_KEYS[k] then
                isLegacyShape = true
                break
            end
        end
        if isLegacyShape then
            store[specID] = { [0] = specSlot }
        end
    end

    if loadoutID == nil then return nil end

    if type(store[specID]) ~= "table" then
        if not create then return nil end
        store[specID] = {}
    end
    if type(store[specID][loadoutID]) ~= "table" then
        if not create then return nil end
        store[specID][loadoutID] = {}
    end
    return store[specID][loadoutID]
end

local function SeedActiveLoadoutFromSharedSlot()
    if not specTrackingReady then return end

    local specID = GetCurrentSpecID()
    if not specID or specID == 0 then return end

    local loadoutID = GetEffectiveLoadoutID()
    if loadoutID == 0 then return end

    local targetSlot = GetSpecLoadoutProfileStore(specID, loadoutID, false)
    if targetSlot and next(targetSlot) ~= nil then return end

    local sourceSlot = GetSpecLoadoutProfileStore(specID, 0, false)
    if not sourceSlot then return end

    local containerKeys = CDMContainers_API:GetAllContainerKeys()
    local hasData = false
    for _, key in ipairs(containerKeys) do
        local containerData = sourceSlot[key]
        if type(containerData) == "table"
            and (containerData.ownedSpells or containerData.removedSpells or containerData.dormantSpells)
        then
            hasData = true
            break
        end
    end
    if not hasData then return end

    local destSlot = GetSpecLoadoutProfileStore(specID, loadoutID, true)
    if not destSlot then return end

    for _, key in ipairs(containerKeys) do
        local containerData = sourceSlot[key]
        if type(containerData) == "table" then
            destSlot[key] = {
                ownedSpells   = CopyTable(containerData.ownedSpells   or {}),
                removedSpells = CopyTable(containerData.removedSpells or {}),
                dormantSpells = CopyTable(containerData.dormantSpells or {}),
            }
        end
    end
end

local function StampActiveProfileSpecOwner(specID)
    if not specID or specID == 0 then
        return
    end
    local db = GetDB()
    if not db then
        return
    end
    db._lastSpecID = specID
    db._lastSpecCharKey = GetCurrentCharacterKey()
end

local function IsSpecManagedContainer(containerDB)
    return containerDB ~= nil and containerDB.containerType ~= "customBar"
end

local function ClearContainerSpecState(containerDB)
    if not containerDB then
        return
    end
    containerDB.ownedSpells = nil
    containerDB.removedSpells = {}
    containerDB.dormantSpells = {}
    containerDB._dormantSequence = 0
end

local function TrySnapshotBuiltInContainers(containerKeys)
    if not ns.CDMSpellData then
        return false
    end

    local allReady = true
    for _, key in ipairs(containerKeys) do
        if key == "essential" or key == "utility" or key == "buff" or key == "trackedBar" then
            local containerDB = GetTrackerSettings(key)
            if containerDB and containerDB.ownedSpells == nil then
                local _, snapshotReady = ns.CDMSpellData:SnapshotBlizzardCDM(key)
                if not snapshotReady then
                    allReady = false
                end
            end
        end
    end

    return allReady
end

local function FinalizeSpecTracking()
    specTrackingReady = true

    if not specTrackingPendingRefresh then
        return
    end

    if InCombatLockdown() or not RefreshAll then
        return
    end

    specTrackingPendingRefresh = false

    if ns.CDMSpellData then
        ns.CDMSpellData:CheckAllDormantSpells()
        ns.CDMSpellData:ReconcileAllContainers()
    end

    RefreshAll()
end

local function SaveSpecProfileToLoadout(specID, loadoutID)
    if not specID or specID == 0 then
        return
    end
    if loadoutID == nil then
        return
    end
    loadoutID = NormalizeLoadoutID(loadoutID)

    local store = GetSpecLoadoutProfileStore(specID, loadoutID, true)
    if not store then
        return
    end

    local specData = {}
    local containerKeys = CDMContainers_API:GetAllContainerKeys()
    local hasAnySpells = false

    for _, key in ipairs(containerKeys) do
        local containerDB = GetTrackerSettings(key)
        if containerDB and containerDB.ownedSpells ~= nil then
            specData[key] = {
                ownedSpells = CopyTable(containerDB.ownedSpells),
                removedSpells = CopyTable(containerDB.removedSpells or {}),
            }
            if type(containerDB.ownedSpells) == "table" and #containerDB.ownedSpells > 0 then
                hasAnySpells = true
            end
        end
    end

    if hasAnySpells then
        for k, v in pairs(specData) do
            store[k] = v
        end
        StampActiveProfileSpecOwner(specID)
    end
end

local function SaveSpecProfile(specID)
    SaveSpecProfileToLoadout(specID, GetEffectiveLoadoutIDForSpec(specID))
end

local function SaveCurrentSpecProfile()
    local loadoutID = _previousLoadoutID
    if loadoutID == nil then
        loadoutID = GetEffectiveLoadoutIDForSpec(_previousSpecID)
    end
    SaveSpecProfileToLoadout(_previousSpecID, loadoutID)
end

local function SaveLoadoutProfile(loadoutID, specID)
    if not specTrackingReady then return end
    local profileDB = GetDB()
    if not (profileDB and profileDB.perLoadoutSpec) then return end
    SaveSpecProfileToLoadout(specID, loadoutID)
end

local function LoadLoadoutProfile(loadoutID, specID, myToken)
    if not specTrackingReady then return false end
    local profileDB = GetDB()
    if not (profileDB and profileDB.perLoadoutSpec) then return false end
    if myToken and myToken ~= loadoutTrackingToken then return false end
    if not specID or specID == 0 then return false end
    if loadoutID == nil then return false end
    loadoutID = NormalizeLoadoutID(loadoutID)

    local store = GetSpecLoadoutProfileStore(specID, loadoutID, false)
    if not store then return false end

    local containerKeys = CDMContainers_API:GetAllContainerKeys()
    local profileHasSpells = false
    for _, key in ipairs(containerKeys) do
        local sc = store[key]
        if sc and type(sc.ownedSpells) == "table" and #sc.ownedSpells > 0 then
            profileHasSpells = true
            break
        end
    end
    if not profileHasSpells then return false end

    for _, key in ipairs(containerKeys) do
        local containerDB = GetTrackerSettings(key)
        if IsSpecManagedContainer(containerDB) then
            local savedContainer = store[key]
            if savedContainer then
                containerDB.ownedSpells   = CopyTable(savedContainer.ownedSpells)
                containerDB.removedSpells = CopyTable(savedContainer.removedSpells)
                containerDB.dormantSpells = CopyTable(savedContainer.dormantSpells or {})
                containerDB._dormantSequence = savedContainer.dormantSequence or 0
            else
                ClearContainerSpecState(containerDB)
            end
        end
    end

    if ns.CDMSpellData then
        ns.CDMSpellData:CheckAllDormantSpells()
        ns.CDMSpellData:ReconcileAllContainers()
    end
    if RefreshAll then RefreshAll() end
    _hydratedLoadoutID = loadoutID
    return true
end

local function ResolveInitialLoadoutSlot()
    if _initialLoadoutResolved then return end
    if not specTrackingReady then return end

    local profileDB = GetDB()
    if not profileDB then return end
    if not profileDB.perLoadoutSpec then
        _initialLoadoutResolved = true
        return
    end

    local specID = GetCurrentSpecID()
    if not specID or specID == 0 then return end

    local savedID
    if C_ClassTalents and C_ClassTalents.GetLastSelectedSavedConfigID then
        savedID = C_ClassTalents.GetLastSelectedSavedConfigID(specID)
    end
    if savedID == nil then return end

    _initialLoadoutResolved = true

    _lastKnownHeroSubTree = GetCurrentHeroSubTree()

    if savedID ~= NO_SAVED_LOADOUT_ID then
        local charNcdm = GetCharNcdmDB(true)
        if charNcdm then
            if type(charNcdm._lastLoadoutConfigID) ~= "table" then
                charNcdm._lastLoadoutConfigID = {}
            end
            charNcdm._lastLoadoutConfigID[specID] = savedID
        end
    end

    local resolvedSlot = NormalizeLoadoutID(savedID)
    local hydratedSlot = _hydratedLoadoutID or 0

    if resolvedSlot == hydratedSlot then
        _lastKnownSavedConfigID = savedID
        _previousLoadoutID = resolvedSlot
        return
    end

    if InCombatLockdown() then
        pendingLoadoutRefresh = true
        return
    end

    loadoutTrackingToken = loadoutTrackingToken + 1
    local myToken = loadoutTrackingToken
    SaveLoadoutProfile(_hydratedLoadoutID, specID)
    _previousLoadoutID = resolvedSlot
    _lastKnownSavedConfigID = savedID
    LoadLoadoutProfile(resolvedSlot, specID, myToken)
    FireLoadoutChangeCallbacks()
end

local function LoadOrSnapshotSpecProfile(specID, attempt, retryToken)
    if not specID then
        return false
    end

    attempt = attempt or 1

    local db = GetDB()
    if not db then
        return false
    end

    local containerKeys = CDMContainers_API:GetAllContainerKeys()
    local loadoutID = GetEffectiveLoadoutID()
    _hydratedLoadoutID = loadoutID
    _previousLoadoutID = loadoutID
    local store = GetSpecLoadoutProfileStore(specID, loadoutID, false)
    local savedProfile = store

    if savedProfile then
        local profileHasSpells = false
        for _, key in ipairs(containerKeys) do
            local sc = savedProfile[key]
            if sc and type(sc.ownedSpells) == "table" and #sc.ownedSpells > 0 then
                profileHasSpells = true
                break
            end
        end
        if not profileHasSpells then
            local parentStore = GetSpecProfileStore(false)
            if parentStore and parentStore[specID] then
                parentStore[specID][loadoutID] = nil
            end
            savedProfile = nil
        end
    end

    if not savedProfile then
        local currentCharKey = GetCurrentCharacterKey()
        local profileCharKey = db._lastSpecCharKey
        local profileSpecID = db._lastSpecID
        local profileSpecMatches = profileSpecID == specID or (not profileSpecID and _previousSpecID == specID)
        if profileSpecMatches and ((not profileCharKey) or profileCharKey == currentCharKey) then
            local specData = {}
            local hasAnySpells = false
            for _, key in ipairs(containerKeys) do
                local containerDB = GetTrackerSettings(key)
                if containerDB and containerDB.ownedSpells ~= nil then
                    specData[key] = {
                        ownedSpells = CopyTable(containerDB.ownedSpells),
                        removedSpells = CopyTable(containerDB.removedSpells or {}),
                    }
                    if type(containerDB.ownedSpells) == "table" and #containerDB.ownedSpells > 0 then
                        hasAnySpells = true
                    end
                end
            end
            if hasAnySpells then
                store = GetSpecLoadoutProfileStore(specID, loadoutID, true)
                if store then
                    for k, v in pairs(specData) do
                        store[k] = v
                    end
                    savedProfile = specData
                end
            end
        end
    end

    if savedProfile then
        for _, key in ipairs(containerKeys) do
            local containerDB = GetTrackerSettings(key)
            if IsSpecManagedContainer(containerDB) then
                local savedContainer = savedProfile[key]
                if savedContainer then
                    containerDB.ownedSpells = CopyTable(savedContainer.ownedSpells)
                    containerDB.removedSpells = CopyTable(savedContainer.removedSpells)
                    containerDB.dormantSpells = CopyTable(savedContainer.dormantSpells or {})
                    containerDB._dormantSequence = savedContainer.dormantSequence or 0
                else
                    ClearContainerSpecState(containerDB)
                end
            end
        end
        if ns.CDMSpellData then
            ns.CDMSpellData:CheckAllDormantSpells()
        end
        StampActiveProfileSpecOwner(specID)
        return true
    else
        if ns.CDMSpellData then
            for _, key in ipairs(containerKeys) do
                local containerDB = GetTrackerSettings(key)
                if IsSpecManagedContainer(containerDB) then
                    ClearContainerSpecState(containerDB)
                end
            end
            local snapshotReady = TrySnapshotBuiltInContainers(containerKeys)
            if snapshotReady or attempt >= SPEC_TRACKING_MAX_RETRIES then
                SaveSpecProfile(specID)
                return true
            end

            C_Timer.After(SPEC_TRACKING_RETRY_DELAY, function()
                if retryToken ~= specTrackingRetryToken then
                    return
                end
                if InCombatLockdown() then
                    return
                end
                local currentSpecID = GetCurrentSpecID()
                if currentSpecID ~= specID then
                    return
                end
                local readyNow = LoadOrSnapshotSpecProfile(specID, attempt + 1, retryToken)
                if readyNow then
                    FinalizeSpecTracking()
                end
            end)
            return false
        end
        return true
    end
end

local function RunCrossSessionDetection(specID)
    local db = GetSpecStateDB(true)
    if not db or not specID or specID == 0 then return false end

    local lastSpecID = db._lastSpecID
    local currentCharKey = GetCurrentCharacterKey()
    local profileDB = GetDB()
    local profileCharKey = profileDB and profileDB._lastSpecCharKey
    local liveStateOwnedByCurrentChar = (not profileCharKey) or profileCharKey == currentCharKey
    if lastSpecID and lastSpecID ~= specID and liveStateOwnedByCurrentChar then
        local oldPrevious = _previousSpecID
        _previousSpecID = lastSpecID
        SaveCurrentSpecProfile()
        _previousSpecID = oldPrevious
    end

    if ns.InvalidateCDMFrameCache then ns.InvalidateCDMFrameCache() end
    if ns.CDMSpellData and ns.CDMSpellData.InvalidateLearnedCache then
        ns.CDMSpellData:InvalidateLearnedCache()
    end

    specTrackingRetryToken = specTrackingRetryToken + 1
    local readyNow = LoadOrSnapshotSpecProfile(specID, 1, specTrackingRetryToken)
    db._lastSpecID = specID
    db._lastSpecCharKey = currentCharKey
    return readyNow
end

local function ScheduleInitialSpecTrackingRetry(attempt, retryToken)
    C_Timer.After(1.0, function()
        if retryToken ~= specTrackingRetryToken then
            return
        end

        if not _previousSpecID or _previousSpecID == 0 then
            _previousSpecID = GetCurrentSpecID()
        end

        if _previousSpecID and _previousSpecID ~= 0 then
            local readyNow = RunCrossSessionDetection(_previousSpecID)
            specTrackingReady = readyNow
            if readyNow then
                FinalizeSpecTracking()
            end
            return
        end

        if attempt >= SPEC_TRACKING_MAX_RETRIES then
            FinalizeSpecTracking()
            return
        end

        ScheduleInitialSpecTrackingRetry(attempt + 1, retryToken)
    end)
end

local function InitSpecTracking()
    specTrackingReady = false
    specTrackingPendingRefresh = false
    _previousSpecID = GetCurrentSpecID()

    if (not _previousSpecID) or _previousSpecID == 0 then
        local db = GetSpecStateDB(false)
        local cached = db and db._lastSpecID
        local currentCharKey = GetCurrentCharacterKey()
        local cachedCharKey = db and db._lastSpecCharKey
        if not cached then
            local profileDB = GetDB()
            local profileCached = profileDB and profileDB._lastSpecID
            local profileCharKey = profileDB and profileDB._lastSpecCharKey
            if profileCached and profileCached ~= 0
                and (profileCharKey == currentCharKey or (not profileCharKey and InCombatLockdown()))
            then
                cached = profileCached
                cachedCharKey = profileCharKey
            end
        end
        if cached and cached ~= 0
            and (cachedCharKey == currentCharKey or (not cachedCharKey and InCombatLockdown()))
        then
            _previousSpecID = cached
        end
    end

    if _previousSpecID and _previousSpecID ~= 0 then
        local readyNow = RunCrossSessionDetection(_previousSpecID)
        specTrackingReady = readyNow
        return readyNow
    else
        specTrackingPendingRefresh = true
        specTrackingRetryToken = specTrackingRetryToken + 1
        local retryToken = specTrackingRetryToken
        ScheduleInitialSpecTrackingRetry(1, retryToken)
        return false
    end
end

local function IsChallengeModeProfileTransition()
    if not C_ChallengeMode then
        return false
    end

    return (C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive())
        or (C_ChallengeMode.GetActiveChallengeMapID and C_ChallengeMode.GetActiveChallengeMapID() ~= nil)
end

local function SyncCurrentProfileSpecState(event, _, profileKey)
    if not initialized then
        return
    end

    local currentProfile = QUICore and QUICore.db and QUICore.db.GetCurrentProfile and QUICore.db:GetCurrentProfile()
    if event == "OnProfileChanged" and profileKey and profileKey == lastKnownProfile and profileKey == currentProfile then
        return
    end

    lastKnownProfile = currentProfile or profileKey or lastKnownProfile

    if IsChallengeModeProfileTransition() then
        return
    end

    specTrackingRetryToken = specTrackingRetryToken + 1

    if loadoutDebounceTimer then
        loadoutDebounceTimer:Cancel()
        loadoutDebounceTimer = nil
    end
    loadoutTrackingToken = loadoutTrackingToken + 1
    _previousLoadoutID = nil
    _lastKnownSavedConfigID = nil
    pendingLoadoutRefresh = false
    _hydratedLoadoutID = nil
    _initialLoadoutResolved = false

    local specReadyNow = InitSpecTracking()
    if not specReadyNow then
        specTrackingPendingRefresh = true
    end

    ResolveInitialLoadoutSlot()

    FireLoadoutChangeCallbacks()
end

local function RegisterProfileCallbacks()
    if profileCallbackSink or not (QUICore and QUICore.db and QUICore.db.RegisterCallback) then
        return
    end

    profileCallbackSink = {}

    function profileCallbackSink:OnProfileChanged(event, db, profileKey)
        SyncCurrentProfileSpecState(event, db, profileKey)
    end

    QUICore.db.RegisterCallback(profileCallbackSink, "OnProfileChanged", "OnProfileChanged")
    QUICore.db.RegisterCallback(profileCallbackSink, "OnProfileCopied", "OnProfileChanged")
    QUICore.db.RegisterCallback(profileCallbackSink, "OnProfileReset", "OnProfileChanged")

    lastKnownProfile = QUICore.db:GetCurrentProfile()
end

local BUILTIN_KEYS = Shared and Shared.BUILTIN_CONTAINER_KEYS
    or { "essential", "utility", "buff", "trackedBar" }

local BUILTIN_NAMES = Shared and Shared.BUILTIN_CONTAINER_LABELS
    or {
        essential  = "Essential",
        utility    = "Utility",
        buff       = "Buff Icons",
        trackedBar = "Buff Bars",
    }

local BUILTIN_CONTAINER_TYPES = Shared and Shared.BUILTIN_CONTAINER_TYPES
    or {
        essential  = "cooldown",
        utility    = "cooldown",
        buff       = "aura",
        trackedBar = "auraBar",
    }

local BUILTIN_SHAPES = Shared and Shared.BUILTIN_CONTAINER_SHAPES
    or {
        essential  = "icon",
        utility    = "icon",
        buff       = "icon",
        trackedBar = "bar",
    }

local function GetContainerShape(viewerType)
    if not viewerType then return "icon" end

    if Shared and Shared.GetContainerShape then
        return Shared.GetContainerShape(viewerType)
    end

    local db = ns.Addon and ns.Addon.db and ns.Addon.db.profile
    local cDB
    if db then
        cDB = db[viewerType]
        if not cDB and db.ncdm and db.ncdm.containers then
            cDB = db.ncdm.containers[viewerType]
        end
    end

    if cDB then
        local s = cDB.shape
        if s == "icon" or s == "bar" then return s end
    end

    local builtinShape = Shared and Shared.GetBuiltinContainerShape
        and Shared.GetBuiltinContainerShape(viewerType)
        or BUILTIN_SHAPES[viewerType]
    if builtinShape then
        return builtinShape
    end

    if cDB and cDB.containerType == "auraBar" then
        return "bar"
    end

    return "icon"
end

local function IsBarShape(viewerType)
    return GetContainerShape(viewerType) == "bar"
end

local function ShouldDeferContainerLayoutInCombat(trackerKey, settings, runtimeVisibilityRelayout)
    if not InCombatLockdown() then
        return false
    end

    local auraRuns = ns.CDMCustomAuraRuns
    local owner = containers[trackerKey]
    local hasActiveOverlays = auraRuns and auraRuns.HasAuraOverlays
        and auraRuns.HasAuraOverlays(owner)
    if hasActiveOverlays then return true end
    local hasPreparedOverlays = auraRuns and auraRuns.HasPreparedAuraOverlays
        and auraRuns.HasPreparedAuraOverlays(owner)
    if hasPreparedOverlays then return true end
    local hasActiveRuns = auraRuns and auraRuns.HasActiveRuns
        and auraRuns.HasActiveRuns(owner)
    if hasActiveRuns then
        local pool = ns.CDMIconFactory and ns.CDMIconFactory.GetIconPool
            and ns.CDMIconFactory:GetIconPool(trackerKey)
        if runtimeVisibilityRelayout
            and auraRuns.CanRelayoutInCombat
            and auraRuns.CanRelayoutInCombat(owner, settings, pool) then
            return false
        end
        return true
    end
    local usesAuraRuns = auraRuns and auraRuns.ShouldUseSettings(settings, trackerKey)
        and auraRuns.HasAuraEntries(settings, trackerKey)
    if usesAuraRuns then return true end

    if inInitSafeWindow then return false end

    if trackerKey == "essential" or trackerKey == "utility" then
        return true
    end

    if settings and settings.clickableIcons then
        return true
    end

    if ns.CDMIconFactory and ns.CDMIconFactory.PoolHasProtectedIcon
        and ns.CDMIconFactory:PoolHasProtectedIcon(trackerKey) then
        return true
    end

    return false
end

local function GetDefaultsByContainerType(containerType)
    if containerType == "cooldown" then
        return {
            enabled = true,
            pos = nil,
            desaturateOnCooldown = true,
            rangeIndicator = true,
            rangeColor = {0.8, 0.1, 0.1, 1},
            usabilityIndicator = true,
            clickableIcons = false,
            layoutDirection = "HORIZONTAL",
            row1 = {
                iconCount = 6, iconSize = 39, borderSize = 1,
                borderColorSource = "inherit", borderColor = {0, 0, 0, 1}, aspectRatioCrop = 1.0,
                zoom = 0, padding = 2, xOffset = 0, yOffset = 0,
                hideDurationText = false, durationSize = 16,
                durationOffsetX = 0, durationOffsetY = 0,
                stackSize = 12, stackOffsetX = 0, stackOffsetY = 2,
                durationTextColor = {1, 1, 1, 1}, durationAnchor = "CENTER",
                stackTextColor = {1, 1, 1, 1}, stackAnchor = "BOTTOMRIGHT",
            },
            row2 = {
                iconCount = 0, iconSize = 39, borderSize = 1,
                borderColorSource = "inherit", borderColor = {0, 0, 0, 1}, aspectRatioCrop = 1.0,
                zoom = 0, padding = 2, xOffset = 0, yOffset = 3,
                durationSize = 16, durationOffsetX = 0, durationOffsetY = 0,
                stackSize = 12, stackOffsetX = 0, stackOffsetY = 2,
                durationTextColor = {1, 1, 1, 1}, durationAnchor = "CENTER",
                stackTextColor = {1, 1, 1, 1}, stackAnchor = "BOTTOMRIGHT",
            },
            row3 = {
                iconCount = 0, iconSize = 39, borderSize = 1,
                borderColorSource = "inherit", borderColor = {0, 0, 0, 1}, aspectRatioCrop = 1.0,
                zoom = 0, padding = 2, xOffset = 0, yOffset = 0,
                durationSize = 16, durationOffsetX = 0, durationOffsetY = 0,
                stackSize = 12, stackOffsetX = 0, stackOffsetY = 2,
                durationTextColor = {1, 1, 1, 1}, durationAnchor = "CENTER",
                stackTextColor = {1, 1, 1, 1}, stackAnchor = "BOTTOMRIGHT",
            },
            ownedSpells = {},
            removedSpells = {},
            dormantSpells = {},
            spellOverrides = {},
            iconDisplayMode = "always",
            showKeybinds = false,
            keybindTextSize = 12,
            keybindTextColor = { 1, 0.82, 0, 1 },
            keybindAnchor = "TOPLEFT",
            keybindOffsetX = 2,
            keybindOffsetY = 2,
        }
    elseif containerType == "aura" then
        return {
            enabled = true,
            pos = nil,
            iconSize = 32, borderSize = 1,
            shape = "square",
            aspectRatioCrop = 1.0,
            growthDirection = "CENTERED_HORIZONTAL",
            zoom = 0, padding = 4,
            hideDurationText = false, durationSize = 14,
            durationOffsetX = 0, durationOffsetY = 8,
            durationAnchor = "TOP",
            stackSize = 14, stackOffsetX = 0, stackOffsetY = -8,
            stackAnchor = "BOTTOM",
            anchorTo = "disabled",
            anchorPlacement = "center",
            anchorSpacing = 0,
            anchorSourcePoint = "CENTER",
            anchorTargetPoint = "CENTER",
            anchorOffsetX = 0,
            anchorOffsetY = 0,
            ownedSpells = {},
            removedSpells = {},
            dormantSpells = {},
            spellOverrides = {},
            iconDisplayMode = "active",
        }
    elseif containerType == "auraBar" then
        return {
            enabled = true,
            hideIcon = false,
            barHeight = 25, barWidth = 215,
            texture = "Quazii v5",
            useClassColor = true,
            barColor = {0.376, 0.647, 0.980, 1},
            colorOverrides = {},
            barOpacity = 1.0,
            borderSize = 2,
            bgColor = {0, 0, 0, 1},
            bgOpacity = 0.5,
            textSize = 14,
            spacing = 2,
            growUp = true,
            inactiveMode = "hide",
            inactiveAlpha = 0.3,
            desaturateInactive = false,
            reserveSlotWhenInactive = false,
            autoWidth = false,
            autoWidthOffset = 0,
            anchorTo = "disabled",
            anchorPlacement = "center",
            anchorSpacing = 0,
            anchorSourcePoint = "CENTER",
            anchorTargetPoint = "CENTER",
            anchorOffsetX = 0,
            anchorOffsetY = 0,
            orientation = "horizontal",
            fillDirection = "up",
            iconPosition = "top",
            showTextOnVertical = false,
            pos = nil,
            ownedSpells = {},
            removedSpells = {},
            dormantSpells = {},
            spellOverrides = {},
            iconDisplayMode = "active",
        }
    end
    return {}
end

CDMContainers_API = {}

local function GenerateContainerKey()
    return "custom_" .. time() .. "_" .. math.random(1000, 9999)
end

function CDMContainers_API:GetContainers()
    local db = GetDB()
    local ct = db and db.containers
    if not ct then return {} end

    local result = {}
    for _, key in ipairs(BUILTIN_KEYS) do
        if ct[key] then
            result[#result + 1] = { key = key, settings = ct[key] }
        end
    end
    local customKeys = {}
    for key in pairs(ct) do
        if not BUILTIN_NAMES[key] then
            customKeys[#customKeys + 1] = key
        end
    end
    table.sort(customKeys)
    for _, key in ipairs(customKeys) do
        result[#result + 1] = { key = key, settings = ct[key] }
    end
    return result
end

function CDMContainers_API:GetContainerSettings(key)
    local db = GetDB()
    if not db then return nil end
    if Shared and ((Shared.IsBuiltinContainerKey and Shared.IsBuiltinContainerKey(key))
        or (Shared.GetBuiltinContainerEntryKind and Shared.GetBuiltinContainerEntryKind(key))) then
        return db[key]
    end
    return db.containers and db.containers[key] or nil
end

function CDMContainers_API:GetContainersByType(containerType)
    local all = self:GetContainers()
    local result = {}
    for _, entry in ipairs(all) do
        local ct = entry.settings.containerType
        if ct == containerType then
            result[#result + 1] = entry
        end
    end
    return result
end

function CDMContainers_API:CreateContainer(name, containerType)
    if InCombatLockdown() then return nil end
    if not name or name == "" then name = "Custom" end
    local shapeHint = containerType or "cooldown"

    local db = GetDB()
    if not db then return nil end
    if not db.containers then db.containers = {} end

    local key = GenerateContainerKey()
    local settings = GetDefaultsByContainerType(shapeHint)
    settings.builtIn = false
    settings.name = name
    settings.containerType = "customBar"
    settings.shape = (shapeHint == "auraBar") and "bar" or "icon"
    settings.entries = {}
    settings.ownedSpells = nil

    db.containers[key] = settings


    local frameName = "QUI_CDM_" .. key
    local frame = RegisterContainerFrame(key, CreateContainer(frameName))
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetSize(100, 40)
    frame:SetAlpha(1)
    frame:Show()

    settings.pos = { ox = 0, oy = 0 }

    if ns.CDMIconFactory then
        ns.CDMIconFactory:EnsurePool(key)
    end

    self:RegisterDynamicLayoutElement(key, settings)

    self:RegisterDynamicFrameResolver(key, settings)

    if ns.InvalidateCDMFrameCache then ns.InvalidateCDMFrameCache() end

    local um = ns.QUI_LayoutMode
    if um and um.RefreshMovers then
        um:RefreshMovers()
    end

    SyncSettingsFeatureLookups()

    return key
end

-- >>> QUI_TEST_EXTRACT PurgeContainerSatellites (sentinels used by
local function PurgeContainerSatellites(profile, containerKey)
    if type(profile) ~= "table" or type(containerKey) ~= "string" then return end
    local glow = profile.customGlow
    if type(glow) == "table" then
        for k in pairs(glow) do
            if type(k) == "string" and k:sub(1, #containerKey) == containerKey then
                glow[k] = nil
            end
        end
    end
    if type(profile.cooldownEffects) == "table" then
        profile.cooldownEffects["hide_" .. containerKey] = nil
    end
    if type(profile.frameAnchoring) == "table" then
        profile.frameAnchoring["cdmCustom_" .. containerKey] = nil
    end
end
-- <<< QUI_TEST_EXTRACT PurgeContainerSatellites
ns.CDMPurgeContainerSatellites = PurgeContainerSatellites

function CDMContainers_API:DeleteContainer(containerKey)
    if InCombatLockdown() then return false end

    local db = GetDB()
    if not db or not db.containers then return false end
    local settings = db.containers[containerKey]
    if not settings then return false end
    if settings.builtIn then return false end

    db.containers[containerKey] = nil
    db[containerKey] = nil

    local profile = QUICore and QUICore.db and QUICore.db.profile
    if profile then
        PurgeContainerSatellites(profile, containerKey)
    end

    local frame = containers[containerKey]
    if frame then
        frame:Hide()
        frame:ClearAllPoints()
        frame:SetParent(nil)
        containers[containerKey] = nil
        viewerState[frame] = nil
    end

    if ns.CDMIconFactory then
        ns.CDMIconFactory:ClearPool(containerKey)
    end

    local um = ns.QUI_LayoutMode
    if um and um.UnregisterElement then
        um:UnregisterElement("cdmCustom_" .. containerKey)
    end

    if _G.QUI_UnregisterFrameResolver then
        _G.QUI_UnregisterFrameResolver("cdmCustom_" .. containerKey)
    end

    if ns.InvalidateCDMFrameCache then ns.InvalidateCDMFrameCache() end

    SyncSettingsFeatureLookups()

    return true
end

function CDMContainers_API:RenameContainer(containerKey, newName)
    if not newName or newName == "" then return false end

    local db = GetDB()
    if not db or not db.containers then return false end
    local settings = db.containers[containerKey]
    if not settings then return false end

    settings.name = newName

    local um = ns.QUI_LayoutMode
    if um and um.UpdateElementLabel then
        um:UpdateElementLabel("cdmCustom_" .. containerKey, newName)
    end
    self:RegisterDynamicFrameResolver(containerKey, settings)

    return true
end

function CDMContainers_API:GetContainer(key)
    return containers[key]
end

function CDMContainers_API:RegisterDynamicLayoutElement(containerKey, settings)
    local um = ns.QUI_LayoutMode
    if not um then return end

    local elementKey = "cdmCustom_" .. containerKey
    um:RegisterElement({
        key = elementKey,
        label = settings.name or containerKey,
        group = ns.L["Cooldown Manager & Custom Tracker Bars"],
        order = 100,
        isOwned = true,
        isEnabled = function()
            local s = GetTrackerSettings(containerKey)
            return s and s.enabled ~= false
        end,
        setEnabled = function(val)
            local s = GetTrackerSettings(containerKey)
            if s then s.enabled = val end
            if _G.QUI_RefreshCDMVisibility then _G.QUI_RefreshCDMVisibility() end
        end,
        setGameplayHidden = function(hide)
            local f = containers[containerKey]
            if f then
                if hide then f:Hide() else f:Show() end
            end
        end,
        getFrame = function()
            return containers[containerKey]
        end,
    })

end

function CDMContainers_API:RegisterDynamicFrameResolver(containerKey, settings)
    if _G.QUI_RegisterFrameResolver then
        local resolverKey = "cdmCustom_" .. containerKey
        _G.QUI_RegisterFrameResolver(resolverKey, {
            resolver = function() return containers[containerKey] end,
            displayName = type(settings.name) == "string" and settings.name ~= "" and settings.name or containerKey,
            category = "Cooldown Manager & Custom Tracker Bars",
            order = 100,
        })
    end
end

function CDMContainers_API:GetAllContainerKeys()
    local db = GetDB()
    local ct = db and db.containers
    if not ct then return BUILTIN_KEYS end

    local result = {}
    for _, key in ipairs(BUILTIN_KEYS) do
        result[#result + 1] = key
    end
    local customKeys = {}
    for key in pairs(ct) do
        if not BUILTIN_NAMES[key] then
            customKeys[#customKeys + 1] = key
        end
    end
    table.sort(customKeys)
    for _, key in ipairs(customKeys) do
        result[#result + 1] = key
    end
    return result
end

local function UpdateLockedBarsForViewer(trackerKey)
    if trackerKey == "essential" then
        if _G.QUI_UpdateLockedPowerBar then _G.QUI_UpdateLockedPowerBar() end
        if _G.QUI_UpdateLockedSecondaryPowerBar then _G.QUI_UpdateLockedSecondaryPowerBar() end
        if _G.QUI_UpdateLockedCastbarToEssential then _G.QUI_UpdateLockedCastbarToEssential() end
    elseif trackerKey == "utility" then
        if _G.QUI_UpdateLockedPowerBarToUtility then _G.QUI_UpdateLockedPowerBarToUtility() end
        if _G.QUI_UpdateLockedSecondaryPowerBarToUtility then _G.QUI_UpdateLockedSecondaryPowerBarToUtility() end
        if _G.QUI_UpdateLockedCastbarToUtility then _G.QUI_UpdateLockedCastbarToUtility() end
    end
end

local function UpdateAllLockedBars()
    UpdateLockedBarsForViewer("essential")
    UpdateLockedBarsForViewer("utility")
end

local function GetUtilityAnchorProxy()
    if not UtilityAnchorProxy then
        UtilityAnchorProxy = UIKit.CreateAnchorProxy(nil, {
            combatFreeze = false,
            mirrorVisibility = false,
            sizeResolver = function(source)
                local vs = viewerState[source]
                local width = (vs and vs.cdmIconWidth) or (source:GetWidth() or 0)
                local height = (vs and vs.cdmTotalHeight) or (source:GetHeight() or 0)
                return width, height
            end,
        })
    end
    return UtilityAnchorProxy
end

local function UpdateUtilityAnchorProxy()
    local proxy = GetUtilityAnchorProxy()
    local essContainer = containers.essential
    if not essContainer then
        return proxy
    end
    proxy:SetSourceFrame(essContainer)
    proxy:Sync()
    return proxy
end

CreateContainer = function(name)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetSize(1, 1)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetAlpha(0)
    frame:Show()
    if not frame._quiAlphaMouseHooked then
        frame._quiAlphaMouseHooked = true
        hooksecurefunc(frame, "SetAlpha", function(self, alpha)
            if SyncContainerMouseState then
                SyncContainerMouseState(self, alpha)
            end
        end)
    end
    viewerState[frame] = {}
    return frame
end

RegisterContainerFrame = function(key, frame)
    containers[key] = frame
    if frame then
        frame._quiCdmKey = key
    end
    return frame
end

ANCHOR_KEY_MAP = {
    essential  = "cdmEssential",
    utility    = "cdmUtility",
    buff       = "buffIcon",
    trackedBar = "buffBar",
}

local function ResolveSettingsLookupKey(containerKey)
    if type(containerKey) ~= "string" or containerKey == "" then
        return nil
    end

    return ANCHOR_KEY_MAP[containerKey] or ("cdmCustom_" .. containerKey)
end

function SyncSettingsFeatureLookups(featureId)
    local Settings = ns.Settings
    local Registry = Settings and Settings.Registry
    if not Registry
        or type(Registry.GetFeature) ~= "function"
        or type(Registry.RegisterLookupKey) ~= "function"
        or type(Registry.UnregisterLookupKey) ~= "function" then
        return false
    end

    featureId = featureId or SETTINGS_FEATURE_ID
    if not Registry:GetFeature(featureId) then
        return false
    end

    local desiredLookupKeys = {}
    local db = GetDB()
    local customContainers = db and db.containers
    if type(customContainers) == "table" then
        for containerKey in pairs(customContainers) do
            if not BUILTIN_NAMES[containerKey] then
                local lookupKey = ResolveSettingsLookupKey(containerKey)
                if lookupKey then
                    desiredLookupKeys[lookupKey] = true
                    Registry:RegisterLookupKey(featureId, lookupKey)
                end
            end
        end
    end

    for lookupKey in pairs(registeredSettingsLookupKeys) do
        if not desiredLookupKeys[lookupKey] then
            Registry:UnregisterLookupKey(featureId, lookupKey)
        end
    end

    registeredSettingsLookupKeys = desiredLookupKeys
    return true
end

local function SaveContainerPosition(trackerKey)
    local container = containers[trackerKey]
    if not container then return end
    local db = GetTrackerSettings(trackerKey)
    if not db then return end
    local rawCx, rawCy = container:GetCenter()
    local rawSx, rawSy = UIParent:GetCenter()
    local cx = rawCx
    local cy = rawCy
    local sx = rawSx
    local sy = rawSy
    if cx and cx ~= 0 and cy and cy ~= 0 and sx and sy then
        local ox = cx - sx
        local oy = cy - sy
        db.pos = { ox = ox, oy = oy }

        local anchorKey = ANCHOR_KEY_MAP[trackerKey] or ("cdmCustom_" .. trackerKey)
        if anchorKey then
            local profile = QUICore and QUICore.db and QUICore.db.profile
            local anchoringDB = profile and profile.frameAnchoring
            local settings = anchoringDB and anchoringDB[anchorKey]
            if settings and settings.enabled ~= false then
                local parent = settings.parent or "screen"
                if parent == "screen" or parent == "disabled" then
                    local vs = viewerState[container]
                    local frameW = (vs and (vs.cdmIconWidth or vs.row1Width)) or (container:GetWidth() or 1) or 1
                    local frameH = (vs and vs.cdmTotalHeight) or (container:GetHeight() or 1)
                    local parentW = (UIParent:GetWidth() or 1)
                    local parentH = (UIParent:GetHeight() or 1)
                    settings.offsetX, settings.offsetY = CDMLayout.ComputeAnchorOffsets(
                        ox, oy,
                        settings.point or "CENTER",
                        settings.relative or "CENTER",
                        frameW, frameH, parentW, parentH)
                end
            end
        end
    end
end

local function RestoreContainerPosition(container, trackerKey)
    if not container then return false end

    local anchorKey = ANCHOR_KEY_MAP[trackerKey] or ("cdmCustom_" .. trackerKey)
    if anchorKey and _G.QUI_IsLayoutModeManaged and _G.QUI_IsLayoutModeManaged(anchorKey) then
        return true
    end

    if anchorKey then
        local profile = QUICore and QUICore.db and QUICore.db.profile
        local anchoringDB = profile and profile.frameAnchoring
        local settings = anchoringDB and anchoringDB[anchorKey]
        if settings and settings.enabled ~= false then
            local parent = settings.parent or "screen"
            if parent == "screen" or parent == "disabled" then
                local ox = settings.offsetX or 0
                local oy = settings.offsetY or 0
                if QUICore and QUICore.PixelRound then
                    ox = QUICore:PixelRound(ox, container)
                    oy = QUICore:PixelRound(oy, container)
                end
                container:ClearAllPoints()
                container:SetPoint("CENTER", UIParent, "CENTER", ox, oy)
                return true
            end
            return true
        end
    end

    local db = GetTrackerSettings(trackerKey)
    if not db or not db.pos then return false end
    local ox = db.pos.ox
    local oy = db.pos.oy
    if ox and oy then
        if QUICore and QUICore.PixelRound then
            ox = QUICore:PixelRound(ox, container)
            oy = QUICore:PixelRound(oy, container)
        end
        container:ClearAllPoints()
        container:SetPoint("CENTER", UIParent, "CENTER", ox, oy)
        return true
    end
    return false
end

local function InitContainerPosition(container, trackerKey)
    RestoreContainerPosition(container, trackerKey)
end

local function EnsureContainerBootstrapSize(container, trackerKey)
    if not container then return end
    local cw = (container:GetWidth() or 0)
    local ch = (container:GetHeight() or 0)
    local width, height = CDMLayout.GetBootstrapSize(trackerKey, cw, ch, viewerState[container], GetDB())
    if width and height then
        container:SetSize(width, height)
    end
end

local function InitContainers()
    if containers.essential then return end

    RegisterContainerFrame("essential", CreateContainer("QUI_EssentialContainer"))
    RegisterContainerFrame("utility", CreateContainer("QUI_UtilityContainer"))
    RegisterContainerFrame("buff", CreateContainer("QUI_CDMBuffIconContainer"))
    RegisterContainerFrame("trackedBar", CreateContainer("QUI_CDMBuffBarContainer"))

    InitContainerPosition(containers.essential, "essential")
    InitContainerPosition(containers.utility, "utility")
    local db = GetDB()
    local anchorTo = db and db.buff and db.buff.anchorTo or "disabled"
    if anchorTo == "disabled" then
        InitContainerPosition(containers.buff, "buff")
    end
    local barAnchorTo = db and db.trackedBar and db.trackedBar.anchorTo or "disabled"
    if barAnchorTo == "disabled" then
        InitContainerPosition(containers.trackedBar, "trackedBar")
    end

    EnsureContainerBootstrapSize(containers.essential, "essential")
    EnsureContainerBootstrapSize(containers.utility, "utility")
    EnsureContainerBootstrapSize(containers.buff, "buff")
    EnsureContainerBootstrapSize(containers.trackedBar, "trackedBar")

    if db and db.containers then
        for key, settings in pairs(db.containers) do
            if not BUILTIN_NAMES[key]
               and not containers[key]
               and settings then
                if settings.builtIn == false and settings.containerType == nil then
                    settings.containerType = "customBar"
                    if type(settings.ownedSpells) == "table" and #settings.ownedSpells > 0
                       and (type(settings.entries) ~= "table" or #settings.entries == 0) then
                        settings.entries = settings.ownedSpells
                        settings.ownedSpells = nil
                    end
                end
                local frameName = "QUI_CDM_" .. key
                local frame = RegisterContainerFrame(key, CreateContainer(frameName))
                InitContainerPosition(frame, key)
                if ns.CDMIconFactory then
                    ns.CDMIconFactory:EnsurePool(key)
                end
                CDMContainers_API:RegisterDynamicFrameResolver(key, settings)
            end
        end
    end
end

local function InitBuffContainer()
    if not containers.buff then
        RegisterContainerFrame("buff", CreateContainer("QUI_CDMBuffIconContainer"))
    end
    local db = GetDB()
    local anchorTo = db and db.buff and db.buff.anchorTo or "disabled"
    if anchorTo == "disabled" then
        InitContainerPosition(containers.buff, "buff")
    end
    if ns.InvalidateCDMFrameCache then ns.InvalidateCDMFrameCache() end
    if ns.CDMBuffLayout and ns.CDMBuffLayout.OnContainerReady then
        C_Timer.After(0.1, function()
            ns.CDMBuffLayout:OnContainerReady()
        end)
    end
end

local _editModeActive = false
local _disabledMouseFrames = {}
local _forceLayoutKey = nil
local _containerMouseSyncPending = false
local _challengeModeRecoveryPending = false

local function IsCDMMouseoverFadeEnabled()
    local vis = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.cdmVisibility
    return vis and not vis.showAlways and vis.showOnMouseover
end

local function SetFrameMouseDisabled(frame)
    if not frame then
        return
    end
    if frame.SetMouseClickEnabled then
        frame:SetMouseClickEnabled(false)
    end
    if frame.SetMouseMotionEnabled then
        frame:SetMouseMotionEnabled(false)
    end
    frame:EnableMouse(false)
    frame._quiMouseMode = "disabled"
end

local function SetFrameHoverOnly(frame)
    if not frame then
        return
    end
    frame:EnableMouse(true)
    if frame.SetMouseClickEnabled then
        frame:SetMouseClickEnabled(false)
    end
    if frame.SetMouseMotionEnabled then
        frame:SetMouseMotionEnabled(true)
    end
    frame._quiMouseMode = "hover"
end

local function SetIconMouseDefault(icon)
    if not icon then
        return
    end
    icon:EnableMouse(true)
    if icon.SetMouseClickEnabled then
        icon:SetMouseClickEnabled(true)
    end
    if icon.SetMouseMotionEnabled then
        icon:SetMouseMotionEnabled(true)
    end
    icon._quiMouseMode = "default"
end

local function SyncClickButtonForVisibility(icon, viewerType, hidden)
    if not icon or not icon.clickButton then
        return
    end

    if InCombatLockdown() then
        icon._pendingVisibilityMouseSync = true
        return
    end

    local button = icon.clickButton
    if hidden then
        if icon._quiClickButtonSuppressed then
            return
        end
        button:EnableMouse(false)
        if button.SetMouseClickEnabled then
            button:SetMouseClickEnabled(false)
        end
        if button.SetMouseMotionEnabled then
            button:SetMouseMotionEnabled(false)
        end
        button:Hide()
        icon._quiClickButtonSuppressed = true
        icon._pendingVisibilityMouseSync = nil
        return
    end

    if not icon._quiClickButtonSuppressed and not icon._pendingVisibilityMouseSync then
        return
    end

    button:EnableMouse(true)
    if button.SetMouseClickEnabled then
        button:SetMouseClickEnabled(true)
    end
    if button.SetMouseMotionEnabled then
        button:SetMouseMotionEnabled(true)
    end
    if ns.CDMIcons and ns.CDMIcons.OnContainerIconInteractionRestored then
        ns.CDMIcons.OnContainerIconInteractionRestored(icon, viewerType)
    end
    icon._quiClickButtonSuppressed = nil
    icon._pendingVisibilityMouseSync = nil
end

local function SyncContainerIconsForVisibility(containerKey, hidden, hoverOnly)
    if not ns.CDMIconFactory or not ns.CDMIconFactory.GetIconPool then
        return
    end

    local pool = ns.CDMIconFactory:GetIconPool(containerKey) or {}
    for _, icon in ipairs(pool) do
        if hidden then
            if hoverOnly then
                SetFrameHoverOnly(icon)
            else
                SetFrameMouseDisabled(icon)
            end
        else
            SetIconMouseDefault(icon)
        end

        if containerKey == "essential" or containerKey == "utility" then
            SyncClickButtonForVisibility(icon, containerKey, hidden)
        end
    end

    local container = containers and containers[containerKey]
    if not (container and container.GetChildren) then
        return
    end

    local children = { container:GetChildren() }
    for _, child in ipairs(children) do
        if child and child._quiCdmShell then
            if hidden then
                if hoverOnly then
                    SetFrameHoverOnly(child)
                else
                    SetFrameMouseDisabled(child)
                end
            else
                SetIconMouseDefault(child)
            end
            if containerKey == "essential" or containerKey == "utility" then
                SyncClickButtonForVisibility(child, containerKey, hidden)
            end
        end
    end
end

local function SyncContainerBarsForVisibility(container)
    if not ns.CDMBars or not ns.CDMBars.GetActiveBars then
        return
    end

    local bars = ns.CDMBars:GetActiveBars() or {}
    for _, bar in ipairs(bars) do
        if bar and bar.GetParent and bar:GetParent() == container then
            SetFrameMouseDisabled(bar)
        end
    end
end

SyncContainerMouseState = function(container, alphaOverride, force)
    if not container or _editModeActive or Helpers.IsEditModeActive() or Helpers.IsLayoutModeActive() then
        return
    end

    local containerKey = container._quiCdmKey
    if not containerKey then
        return
    end

    local alpha
    if alphaOverride ~= nil then
        alpha = alphaOverride
    end
    if alpha == nil and container.GetAlpha then
        alpha = (container:GetAlpha() or 1)
    end
    alpha = alpha or 1

    local hidden = alpha <= 0.001
    local hoverOnly = IsCDMMouseoverFadeEnabled()
    local stateChanged = (container._quiAlphaHidden ~= hidden) or (container._quiHoverOnly ~= hoverOnly)

    if not (force or stateChanged) then
        return
    end

    container._quiAlphaHidden = hidden
    container._quiHoverOnly = hoverOnly

    if InCombatLockdown() and not inInitSafeWindow then
        _containerMouseSyncPending = true
        return
    end

    if hoverOnly then
        SetFrameHoverOnly(container)
    else
        SetFrameMouseDisabled(container)
    end

    if GetContainerShape(containerKey) == "bar" then
        SyncContainerBarsForVisibility(container)
    else
        SyncContainerIconsForVisibility(containerKey, hidden, hoverOnly)
    end
end

SyncAllContainerMouseStates = function(force)
    if _editModeActive or Helpers.IsEditModeActive() or Helpers.IsLayoutModeActive() then
        return
    end

    for key, frame in pairs(containers) do
        if frame then
            frame._quiCdmKey = frame._quiCdmKey or key
            SyncContainerMouseState(frame, nil, force)
        end
    end
end

local function RefreshCustomBarRuntimeAfterLayout(trackerKey, settings)
    if not trackerKey or not settings or settings.containerType ~= "customBar" then return end
    if postLayoutRuntimeRefreshing[trackerKey] then return end
    if not (ns.CDMIcons and ns.CDMIcons.UpdateRuntimeForType) then return end

    postLayoutRuntimeRefreshing[trackerKey] = true
    ns.CDMIcons:UpdateRuntimeForType(trackerKey)
    postLayoutRuntimeRefreshing[trackerKey] = nil
end

local function ApplyViewerMetrics(vs, metrics, containerKey)
    local maxRowWidth = metrics.iconWidth or 0
    local proxyTotalHeight = metrics.totalHeight or 0

    vs.cdmIconWidth = maxRowWidth
    vs.cdmRawContentWidth = metrics.rawContentWidth or 0
    vs.cdmTotalHeight = proxyTotalHeight
    vs.cdmProxyYOffset = metrics.proxyYOffset or 0
    vs.cdmRow1IconHeight = metrics.row1IconHeight or 0
    vs.cdmRow1BorderSize = metrics.row1BorderSize or 0
    vs.cdmBottomRowBorderSize = metrics.bottomRowBorderSize or 0
    vs.cdmBottomRowYOffset = metrics.bottomRowYOffset or 0
    vs.cdmRow1Width = metrics.row1Width or maxRowWidth
    vs.cdmBottomRowWidth = metrics.bottomRowWidth or maxRowWidth
    vs.cdmRawRow1Width = metrics.rawRow1Width or (metrics.rawContentWidth or 0)
    vs.cdmRawBottomRowWidth = metrics.rawBottomRowWidth or (metrics.rawContentWidth or 0)
    vs.cdmPotentialRow1Width = metrics.potentialRow1Width or maxRowWidth
    vs.cdmPotentialBottomRowWidth = metrics.potentialBottomRowWidth or maxRowWidth

    local ncdm = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.ncdm
    if ncdm and maxRowWidth > 0 then
        if containerKey == "essential" then
            ncdm._lastEssentialWidth = maxRowWidth
            ncdm._lastEssentialHeight = proxyTotalHeight
        elseif containerKey == "utility" then
            ncdm._lastUtilityWidth = maxRowWidth
            ncdm._lastUtilityHeight = proxyTotalHeight
        end
    end

    return maxRowWidth, proxyTotalHeight
end

CDMContainers_API.HUD_LAYERING = {
    keys = {
        essential  = "essential",
        utility    = "utility",
        buff       = "buffIcon",
        trackedBar = "buffBar",
    },
    viewers = {
        essential  = "EssentialCooldownViewer",
        utility    = "UtilityCooldownViewer",
        buff       = "BuffIconCooldownViewer",
        trackedBar = "BuffBarCooldownViewer",
    },
}

local function LayoutContainer(trackerKey, runtimeVisibilityRelayout)
    if not IsCDMRuntimeEnabled() then
        return
    end

    local container = containers[trackerKey]
    if not container then
        return
    end

    if _editModeActive and trackerKey ~= _forceLayoutKey then
        return
    end

    local settings = GetTrackerSettings(trackerKey)
    if ShouldDeferContainerLayoutInCombat(trackerKey, settings, runtimeVisibilityRelayout) then
        specTrackingPendingRefresh = true
        if not runtimeVisibilityRelayout and ns.CDMCustomAuraRuns
            and ns.CDMCustomAuraRuns.InvalidatePreparedCombatRelayout then
            ns.CDMCustomAuraRuns.InvalidatePreparedCombatRelayout(container)
        end
        return
    end

    if not settings then
        if BUILTIN_NAMES[trackerKey] then
            settings = { enabled = true }
        else
            container:Hide()
            return
        end
    end
    if settings.enabled == false then
        container:Hide()
        return
    end

    if applying[trackerKey] then
        return
    end
    applying[trackerKey] = true

    if runtimeVisibilityRelayout and InCombatLockdown() then
        local auraRuns = ns.CDMCustomAuraRuns
        local pool = ns.CDMIconFactory and ns.CDMIconFactory.GetIconPool
            and ns.CDMIconFactory:GetIconPool(trackerKey)
        local metrics = auraRuns and auraRuns.RelayoutPreparedInCombat
            and auraRuns.RelayoutPreparedInCombat(container, settings, pool)
        local vs = viewerState[container]
        if not (metrics and vs) then
            specTrackingPendingRefresh = true
            applying[trackerKey] = false
            return
        end
        local maxRowWidth, proxyTotalHeight = ApplyViewerMetrics(vs, metrics, trackerKey)
        if maxRowWidth > 0 and proxyTotalHeight > 0 then
            if QUICore and QUICore.PixelRound then
                maxRowWidth = QUICore:PixelRound(maxRowWidth, container)
                proxyTotalHeight = QUICore:PixelRound(proxyTotalHeight, container)
            end
            container:SetSize(maxRowWidth, proxyTotalHeight)
        end
        applying[trackerKey] = false
        return true
    end

    local anchorHidden = false
    if _G.QUI_IsFrameHiddenByAnchor then
        local anchorKey = ANCHOR_KEY_MAP[trackerKey] or ("cdmCustom_" .. trackerKey)
        anchorHidden = _G.QUI_IsFrameHiddenByAnchor(anchorKey)
    end

    if not anchorHidden then
        container:Show()
    end

    local hudLayering = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.hudLayering
    local layerKey = CDMContainers_API.HUD_LAYERING.keys[trackerKey] or "customBars"
    local layerPriority = hudLayering and hudLayering[layerKey] or 5
    if QUICore and QUICore.GetHUDFrameLevel then
        local frameLevel = QUICore:GetHUDFrameLevel(layerPriority)
        container:SetFrameLevel(frameLevel)
        if (not InCombatLockdown()) or inInitSafeWindow then
            local viewerName = CDMContainers_API.HUD_LAYERING.viewers[trackerKey]
            local viewer = viewerName and _G[viewerName]
            if viewer and viewer.SetFrameLevel then
                if viewer.SetFrameStrata then
                    viewer:SetFrameStrata("MEDIUM")
                end
                viewer:SetFrameLevel(frameLevel)
            end
        end
    end

    local vs = viewerState[container]
    if not vs then
        viewerState[container] = {}
        vs = viewerState[container]
    end

    local layoutDirection = settings.layoutDirection or "HORIZONTAL"
    vs.cdmLayoutDirection = layoutDirection

    if trackerKey == "buff" then
        InitBuffContainer()
        container = containers.buff
        if not container then
            applying[trackerKey] = false
            return
        end

        local cw = (container:GetWidth() or 0)
        local ch = (container:GetHeight() or 0)
        if cw <= 1 or ch <= 1 then
            EnsureContainerBootstrapSize(container, "buff")
        end

        if ns._cdmBoot then
            RefreshReanchoredBuiltin(ns._cdmBoot, "buff", true)
            applying[trackerKey] = false
            return
        end

        local spellData = ns.CDMSpellData and ns.CDMSpellData:GetSpellList("buff") or {}
        local parts = {}
        for i, entry in ipairs(spellData) do
            parts[i] = table.concat({
                tostring(entry.spellID or 0),
                tostring(entry.id or 0),
                BuildLinkedSpellIDsFingerprint(entry.linkedSpellIDs),
                tostring(entry._isTotemInstance and 1 or 0),
                tostring(entry._totemSlot or 0),
                tostring(entry._instanceKey or ""),
            }, ":")
        end
        local fingerprint = table.concat(parts, ",")

        local currentPool = ns.CDMIconFactory and ns.CDMIconFactory:GetIconPool("buff") or {}
        if fingerprint == (buffFingerprint or "") and #currentPool > 0 then
            applying[trackerKey] = false
            return
        end
        buffFingerprint = fingerprint

        if not ns.CDMIcons then
            applying[trackerKey] = false
            return
        end

        local allIcons = ns.CDMIcons:BuildIcons("buff", container)
        for _, icon in ipairs(allIcons) do
            if Helpers.IsEditModeActive() then
                icon:Show()
                icon:EnableMouse(false)
                _disabledMouseFrames[icon] = "icon"
            end
        end

        applying[trackerKey] = false

        if ns.CDMIcons and ns.CDMIcons.UpdateAllCooldowns then
            ns.CDMIcons:UpdateAllCooldowns()
        end
        if ns.CDMBuffLayout and ns.CDMBuffLayout.OnLayoutReady then
            ns.CDMBuffLayout:OnLayoutReady()
        end
        return
    end

    if ns._cdmBoot and (trackerKey == "essential" or trackerKey == "utility") then
        if runtimeVisibilityRelayout then
            applying[trackerKey] = false
            return
        end
        RefreshReanchoredBuiltin(ns._cdmBoot, trackerKey, true)
        applying[trackerKey] = false

        RefreshCustomBarRuntimeAfterLayout(trackerKey, settings)
        if trackerKey == "essential" then
            local db = GetDB()
            if db and db.utility and db.utility.anchorBelowEssential then
                C_Timer.After(0.05, function()
                    if InCombatLockdown() then return end
                    if ApplyUtilityAnchor then
                        ApplyUtilityAnchor()
                    end
                end)
            end
        end
        if vs and not vs.cdmUpdatePending then
            vs.cdmUpdatePending = true
            C_Timer.After(0.05, function()
                vs.cdmUpdatePending = nil
                if InCombatLockdown() then return end
                UpdateLockedBarsForViewer(trackerKey)
                if _G.QUI_UpdateCDMAnchoredUnitFrames then
                    _G.QUI_UpdateCDMAnchoredUnitFrames()
                end
                if _G.QUI_UpdateViewerKeybinds then
                    _G.QUI_UpdateViewerKeybinds(trackerKey)
                end
            end)
        end
        return
    end

    local reuseOnly = runtimeVisibilityRelayout and InCombatLockdown()
    local allIcons = ns.CDMIcons:BuildIcons(trackerKey, container, reuseOnly)
    if not allIcons then
        specTrackingPendingRefresh = true
        applying[trackerKey] = false
        return
    end
    local totalCapacity = CDMLayout and CDMLayout.GetTotalIconCapacity and CDMLayout.GetTotalIconCapacity(settings) or 0
    local auraRuns = ns.CDMCustomAuraRuns
    if not InCombatLockdown() and auraRuns and auraRuns.ShouldUseSettings(settings, trackerKey)
        and auraRuns.HasAuraEntries(settings, trackerKey)
        and ns.CDMIcons.OnIconRowConfigApplied and CDMLayout.BuildRows then
        local rowConfig = CDMLayout.BuildRows(settings)[1]
        for i = 1, math.min(#allIcons, totalCapacity) do
            ns.CDMIcons.OnIconRowConfigApplied(allIcons[i], rowConfig)
        end
    end

    local displayMode = settings.iconDisplayMode or "always"
    local effectiveDisplayMode = displayMode
    if effectiveDisplayMode == "combat" then
        effectiveDisplayMode = InCombatLockdown() and "always" or "active"
    end
    local CDMSpellData = ns.CDMSpellData

    local editModeActive = Helpers.IsEditModeActive()
        or (_G.QUI_IsCDMEditModeActive and _G.QUI_IsCDMEditModeActive())
    local dynamicLayoutEnabled
    if settings.containerType == "customBar" then
        dynamicLayoutEnabled = settings.dynamicLayout == true
    else
        dynamicLayoutEnabled = settings.dynamicLayout ~= false
    end
    local ShouldPlaceLayoutIcon = ns.CDMIcons and ns.CDMIcons.ShouldContainerLayoutPlaceIcon
    local iconsToLayout = {}
    for i = 1, math.min(#allIcons, totalCapacity) do
        local icon = allIcons[i]
        local skipIcon = false

        if not editModeActive and effectiveDisplayMode == "active" and CDMSpellData then
            local entry = icon._spellEntry
            if entry then
                local lookupID = entry.spellID or entry.id
                if lookupID then
                    local spellOvr = CDMSpellData:GetSpellOverride(trackerKey, lookupID)
                    if spellOvr and spellOvr.hidden then
                        icon:Hide()
                        icon:ClearAllPoints()
                        skipIcon = true
                    end
                end
            end
        end

        if not skipIcon and not editModeActive
           and dynamicLayoutEnabled and ShouldPlaceLayoutIcon then
            local entry = icon._spellEntry
            if entry then
                local inCombatNow = UnitAffectingCombat and UnitAffectingCombat("player") or false
                if not ShouldPlaceLayoutIcon(icon, entry, settings, inCombatNow) then
                    icon:Hide()
                    icon:ClearAllPoints()
                    skipIcon = true
                end
            end
        end

        if not skipIcon then
            iconsToLayout[#iconsToLayout + 1] = icon
            icon:Show()
            if editModeActive then
                icon:EnableMouse(false)
                _disabledMouseFrames[icon] = "icon"
                if icon.clickButton and not InCombatLockdown() then
                    icon.clickButton:EnableMouse(false)
                    icon.clickButton:Hide()
                end
            end
        end
    end

    for i = totalCapacity + 1, #allIcons do
        if allIcons[i] then
            allIcons[i]:Hide()
            allIcons[i]:ClearAllPoints()
        end
    end

    local minWidthEnabled, minWidth = GetHUDMinWidth()
    local applyHUDMinWidth = minWidthEnabled
        and (trackerKey == "essential" or trackerKey == "utility")
        and IsHUDAnchoredToCDM()

    local layoutPlan = #iconsToLayout > 0 and CDMLayout and CDMLayout.BuildIconLayout
        and CDMLayout.BuildIconLayout(settings, iconsToLayout, {
            applyHUDMinWidth = applyHUDMinWidth,
            minWidth = minWidth,
        })
    if not layoutPlan or not layoutPlan.metrics or #layoutPlan.placements == 0 then
        if ns.CDMCustomAuraRuns and ns.CDMCustomAuraRuns.Apply then
            ns.CDMCustomAuraRuns.Apply(container, nil, nil, nil, InCombatLockdown(), trackerKey)
        end
        applying[trackerKey] = false
        return
    end

    for _, placement in ipairs(layoutPlan.placements) do
        local icon = placement.icon
        local rowConfig = placement.rowConfig
        local x = placement.x
        local y = placement.y

        if icon.GetScale and icon:GetScale() ~= 1 then
            icon:SetScale(1)
        end

        if QUICore and QUICore.PixelSnapRect and rowConfig and rowConfig.size then
            local aspect = rowConfig.aspectRatioCrop or 1.0
            if type(aspect) ~= "number" or aspect <= 0 then aspect = 1.0 end
            x, y = QUICore:PixelSnapRect(x, y, rowConfig.size, rowConfig.size / aspect, container)
        elseif QUICore and QUICore.PixelRound then
            x = QUICore:PixelRound(x, container)
            y = QUICore:PixelRound(y, container)
        end
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", container, "CENTER", x, y)
        icon:Show()

        ns.CDMIcons.OnContainerIconPlaced(icon, rowConfig)
    end

    if ns.CDMCustomAuraRuns and ns.CDMCustomAuraRuns.Apply then
        ns.CDMCustomAuraRuns.Apply(container, settings, layoutPlan, allIcons,
            InCombatLockdown(), trackerKey)
    end

    local maxRowWidth, proxyTotalHeight = ApplyViewerMetrics(vs, layoutPlan.metrics, trackerKey)

    if maxRowWidth > 0 and proxyTotalHeight > 0 then
        if QUICore and QUICore.PixelRound then
            maxRowWidth = QUICore:PixelRound(maxRowWidth, container)
            proxyTotalHeight = QUICore:PixelRound(proxyTotalHeight, container)
        end
        container:SetSize(maxRowWidth, proxyTotalHeight)
    end

    applying[trackerKey] = false
    RefreshCustomBarRuntimeAfterLayout(trackerKey, settings)

    if trackerKey == "essential" then
        local db = GetDB()
        if db and db.utility and db.utility.anchorBelowEssential then
            C_Timer.After(0.05, function()
                if InCombatLockdown() then return end
                if ApplyUtilityAnchor then
                    ApplyUtilityAnchor()
                end
            end)
        end
    end

    if not vs.cdmUpdatePending then
        vs.cdmUpdatePending = true
        C_Timer.After(0.05, function()
            vs.cdmUpdatePending = nil
            if InCombatLockdown() then return end
            UpdateLockedBarsForViewer(trackerKey)
            if _G.QUI_UpdateCDMAnchoredUnitFrames then
                _G.QUI_UpdateCDMAnchoredUnitFrames()
            end
            if _G.QUI_UpdateViewerKeybinds then
                _G.QUI_UpdateViewerKeybinds(trackerKey)
            end
        end)
    end
end

local function RunPostLayoutRefresh()
    UpdateAllLockedBars()
    if _G.QUI_UpdateCDMAnchoredUnitFrames then
        _G.QUI_UpdateCDMAnchoredUnitFrames()
    end
    if _G.QUI_RefreshCDMMouseover then
        _G.QUI_RefreshCDMMouseover()
    end
    if _G.QUI_RefreshCooldownSwipe then
        _G.QUI_RefreshCooldownSwipe()
    end
    local glows = ns._OwnedGlows
    local resync = glows and (glows.ResyncAllGlows or glows.RefreshAllGlows)
    if resync then
        resync()
    end
    if ns.CDMIcons and ns.CDMIcons.UpdateAllCooldowns then
        ns.CDMIcons:UpdateAllCooldowns()
    end
    SyncAllContainerMouseStates(true)
end

RefreshAll = function(forceSync)
    if not initialized then
        return
    end

    if not IsCDMRuntimeEnabled() then
        return
    end

    if not specTrackingReady then
        specTrackingPendingRefresh = true
        return
    end

    if InCombatLockdown() and not inInitSafeWindow then
        specTrackingPendingRefresh = true
        return
    end

    if _refreshAllFrameGuard then
        return
    end
    _refreshAllFrameGuard = true
    C_Timer.After(0, function() _refreshAllFrameGuard = false end)

    CancelRefreshTimers()

    applying["essential"] = false
    applying["utility"] = false
    applying["buff"] = false

    local allKeys = CDMContainers_API:GetAllContainerKeys()
    for _, trackerKey in ipairs(allKeys) do
        local container = containers[trackerKey]
        if container then
            RestoreContainerPosition(container, trackerKey)
        end
    end

    SyncSettingsFeatureLookups()

    refreshAllReanchorBatchActive = true
    refreshAllReanchorBatchCounts = nil
    if ns._cdmBoot and ns._cdmBoot.RefreshBuiltins then
        InitBuffContainer()
        RefreshReanchoredBuiltin(ns._cdmBoot, "essential", false)
    end

    local customKeys = {}
    local db2 = GetDB()
    if db2 and db2.containers then
        for key in pairs(db2.containers) do
            if not BUILTIN_NAMES[key] and containers[key] then
                customKeys[#customKeys + 1] = key
            end
        end
        table.sort(customKeys)
    end

    if forceSync then
        LayoutContainer("essential")
        LayoutContainer("utility")
        if ApplyUtilityAnchor then
            ApplyUtilityAnchor()
        end
        LayoutContainer("buff")
        for _, key in ipairs(customKeys) do
            LayoutContainer(key)
        end
        RunPostLayoutRefresh()
        refreshAllReanchorBatchActive = false
        refreshAllReanchorBatchCounts = nil
    else
        refreshTimers[1] = C_Timer.NewTimer(0.01, function()
            refreshTimers[1] = nil
            LayoutContainer("essential")
        end)
        refreshTimers[2] = C_Timer.NewTimer(0.02, function()
            refreshTimers[2] = nil
            LayoutContainer("utility")
            if ApplyUtilityAnchor then
                ApplyUtilityAnchor()
            end
        end)
        refreshTimers[3] = C_Timer.NewTimer(0.03, function()
            refreshTimers[3] = nil
            LayoutContainer("buff")
        end)

        local customTimerStart = 4
        for ci, key in ipairs(customKeys) do
            local timerIdx = customTimerStart + ci
            refreshTimers[timerIdx] = C_Timer.NewTimer(0.03 + ci * 0.01, function()
                refreshTimers[timerIdx] = nil
                LayoutContainer(key)
            end)
        end

        local finalTimerDelay = 0.10 + #customKeys * 0.01
        refreshTimers[100] = C_Timer.NewTimer(finalTimerDelay, function()
            refreshTimers[100] = nil
            refreshAllReanchorBatchActive = false
            refreshAllReanchorBatchCounts = nil
            if InCombatLockdown() and not inInitSafeWindow then
                specTrackingPendingRefresh = true
                return
            end
            RunPostLayoutRefresh()
        end)
    end
end

ApplyUtilityAnchor = function()
    if not IsCDMRuntimeEnabled() then return end

    local db = GetDB()
    if not db or not db.utility then
        return
    end

    local utilSettings = db.utility
    local utilContainer = containers.utility
    if not utilContainer then
        return
    end

    if InCombatLockdown() and not inInitSafeWindow then
        specTrackingPendingRefresh = true
        return
    end

    if _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("cdmUtility") then
        return
    end

    if not utilSettings.anchorBelowEssential then
        return
    end

    local essContainer = containers.essential
    if not essContainer then
        return
    end

    local totalOffset = CDMLayout.GetUtilityAnchorOffset(utilSettings)
    if QUICore and QUICore.PixelRound then
        totalOffset = QUICore:PixelRound(totalOffset, utilContainer)
    end

    local anchorParent = UpdateUtilityAnchorProxy() or essContainer

    local ok = ns.SafeCall("best-effort-style", function()
        utilContainer:ClearAllPoints()
        utilContainer:SetPoint("TOP", anchorParent, "BOTTOM", 0, -totalOffset)
    end)

    if not ok then
        utilContainer:ClearAllPoints()
        utilContainer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        utilSettings.anchorBelowEssential = false
        print("|cff60A5FAQUI:|r Anchor Utility below Essential failed (circular dependency). Setting has been disabled.")
    end
end

local _stateSnapshots = Helpers.CreateStateTable()

local function GetViewerState(viewer)
    if not viewer then return nil end
    local vs = viewerState[viewer]
    if not vs or not vs.cdmIconWidth then return nil end
    local snap = _stateSnapshots[viewer]
    if not snap then
        snap = {}
        _stateSnapshots[viewer] = snap
    end
    snap.iconWidth              = vs.cdmIconWidth
    snap.rawContentWidth        = vs.cdmRawContentWidth
    snap.totalHeight            = vs.cdmTotalHeight
    snap.row1Width              = vs.cdmRow1Width
    snap.bottomRowWidth         = vs.cdmBottomRowWidth
    snap.rawRow1Width           = vs.cdmRawRow1Width
    snap.rawBottomRowWidth      = vs.cdmRawBottomRowWidth
    snap.potentialRow1Width     = vs.cdmPotentialRow1Width
    snap.potentialBottomRowWidth = vs.cdmPotentialBottomRowWidth
    snap.row1IconHeight         = vs.cdmRow1IconHeight
    snap.row1BorderSize         = vs.cdmRow1BorderSize
    snap.bottomRowBorderSize    = vs.cdmBottomRowBorderSize
    snap.bottomRowYOffset       = vs.cdmBottomRowYOffset
    snap.layoutDir              = vs.cdmLayoutDirection
    snap.proxyYOffset           = vs.cdmProxyYOffset or 0
    return snap
end

local function SetViewerBounds(viewer, boundsW, boundsH)
    if not viewer then return end
    local vs = viewerState[viewer]
    if not vs then
        viewerState[viewer] = {}
        vs = viewerState[viewer]
    end
    vs.cdmIconWidth = boundsW
    vs.cdmRow1Width = boundsW
    vs.cdmBottomRowWidth = boundsW
    vs.cdmPotentialRow1Width = boundsW
    vs.cdmPotentialBottomRowWidth = boundsW
    vs.cdmTotalHeight = boundsH
end

local function RefreshViewerFromBounds(viewer, trackerKey)
    if not viewer then return end
    UpdateLockedBarsForViewer(trackerKey)
    if _G.QUI_UpdateAnchoredUnitFrames then
        _G.QUI_UpdateAnchoredUnitFrames()
    end
    local proxyKey = trackerKey == "essential" and "cdmEssential" or "cdmUtility"
    if _G.QUI_UpdateFramesAnchoredTo then
        _G.QUI_UpdateFramesAnchoredTo(proxyKey)
    end
end

_G.QUI_OnSpellDataChanged = function()
    if initialized then
        RefreshAll()
    end
end

_G.QUI_ForceLayoutContainer = function(containerKey, runtimeVisibilityRelayout)
    if not containerKey or not initialized then return end
    if not IsCDMRuntimeEnabled() then return end
    _forceLayoutKey = containerKey
    local didPreparedCombatRelayout = LayoutContainer(containerKey, runtimeVisibilityRelayout)
    _forceLayoutKey = nil
    if not didPreparedCombatRelayout
        and ns.CDMIcons and ns.CDMIcons.UpdateAllCooldowns then
        ns.CDMIcons:UpdateAllCooldowns()
    end
    local container = containers[containerKey]
    if container and _editModeActive then
        container:Show()
        local elementKey = BUILTIN_NAMES[containerKey] and containerKey or ("cdmCustom_" .. containerKey)
        if _G.QUI_LayoutModeSyncHandle then
            _G.QUI_LayoutModeSyncHandle(elementKey)
        end
    end
end

local function RebuildBuffContainer()
    if not initialized then return end
    buffFingerprint = nil
    local c = containers and containers["buff"]
    if c then c._lastBuildSignature = nil end
    LayoutContainer("buff")
    if ns.CDMIcons and ns.CDMIcons.UpdateAllCooldowns then
        ns.CDMIcons:UpdateAllCooldowns()
    end
end

_G.QUI_OnBuffDataChanged = function()
    if initialized and not applying["buff"] then
        LayoutContainer("buff")
    end
end

_G.QUI_IsCDMEditModeActive = function() return _editModeActive end

local function DisableMouseForEditMode(viewerType)
    local container = containers[viewerType]
    if not container then return end

    container:EnableMouse(false)
    _disabledMouseFrames[container] = "container"

    local pool = ns.CDMIconFactory and ns.CDMIconFactory:GetIconPool(viewerType) or {}
    for _, icon in ipairs(pool) do
        icon:EnableMouse(false)
        _disabledMouseFrames[icon] = "icon"
        if icon.clickButton and not InCombatLockdown() then
            icon.clickButton:EnableMouse(false)
            icon.clickButton:Hide()
        end
    end
    if viewerType == "trackedBar" and ns.CDMBars then
        local bars = ns.CDMBars:GetActiveBars()
        for _, bar in ipairs(bars) do
            bar:EnableMouse(false)
            _disabledMouseFrames[bar] = "bar"
        end
    end
end

local function RestoreMouseAfterEditMode()
    for frame, mouseRole in pairs(_disabledMouseFrames) do
        if mouseRole == "icon" then
            SetIconMouseDefault(frame)
        else
            SetFrameMouseDisabled(frame)
        end
    end
    wipe(_disabledMouseFrames)

    if not InCombatLockdown() and ns.CDMIconFactory then
        for _, viewerType in ipairs(GetBuiltinCooldownContainerKeys()) do
            local pool = ns.CDMIconFactory:GetIconPool(viewerType) or {}
            for _, icon in ipairs(pool) do
                if icon.clickButton then
                    icon.clickButton:EnableMouse(true)
                end
                if ns.CDMIcons.OnContainerIconInteractionRestored then
                    ns.CDMIcons.OnContainerIconInteractionRestored(icon, viewerType)
                end
            end
        end
    end

    SyncAllContainerMouseStates(true)
end

local function ForceBuffIconsVisible()
    local pool = ns.CDMIconFactory and ns.CDMIconFactory:GetIconPool("buff") or {}
    for _, icon in ipairs(pool) do
        icon:SetAlpha(1)
        icon:Show()
    end
end

_G.QUI_OnEditModeEnterCDM = function()
    if not IsCDMRuntimeEnabled() then return end

    LayoutContainer("buff")

    if containers.trackedBar then
        containers.trackedBar:Show()
        containers.trackedBar:SetAlpha(1)

        if ns.CDMBars then
            local db = GetDB()
            local tbSettings = db and db.trackedBar
            if tbSettings then
                ns.CDMBars:Refresh(containers.trackedBar, tbSettings, tbSettings.barWidth)
                ns.CDMBars:LayoutBars(containers.trackedBar, tbSettings)
            end
        end

        local cw = (containers.trackedBar:GetWidth() or 0)
        local ch = (containers.trackedBar:GetHeight() or 0)
        if cw <= 1 or ch <= 1 then
            local db2 = GetDB()
            local tbs2 = db2 and db2.trackedBar
            local barWidth = (tbs2 and tbs2.barWidth) or 215
            local barHeight = (tbs2 and tbs2.barHeight) or 25
            containers.trackedBar:SetSize(barWidth, barHeight)
        end
    end

    _editModeActive = true

    ForceBuffIconsVisible()

    if ns.CDMBuffLayout and ns.CDMBuffLayout.OnLayoutReady then
        ns.CDMBuffLayout:OnLayoutReady()
    end

    DisableMouseForEditMode("essential")
    DisableMouseForEditMode("utility")
    DisableMouseForEditMode("buff")
    DisableMouseForEditMode("trackedBar")
    for key in pairs(containers) do
        if not BUILTIN_NAMES[key] then
            DisableMouseForEditMode(key)
        end
    end

    local QUICore = ns.Addon
    if QUICore and QUICore.ShowViewerOverlays then
        QUICore:ShowViewerOverlays()
    end

    if _G.QUI_ApplyAllFrameAnchors then _G.QUI_ApplyAllFrameAnchors() end
end

_G.QUI_OnEditModeExitCDM = function()
    if not IsCDMRuntimeEnabled() then return end

    _editModeActive = false

    SaveContainerPosition("essential")
    SaveContainerPosition("utility")
    SaveContainerPosition("buff")
    SaveContainerPosition("trackedBar")
    for key in pairs(containers) do
        if not BUILTIN_NAMES[key] then
            SaveContainerPosition(key)
        end
    end

    RestoreMouseAfterEditMode()

    RefreshAll()

    C_Timer.After(0.5, function()
        if _G.QUI_ApplyAllFrameAnchors then
            _G.QUI_ApplyAllFrameAnchors()
        end
        UpdateAllLockedBars()
        if _G.QUI_UpdateCDMAnchoredUnitFrames then
            _G.QUI_UpdateCDMAnchoredUnitFrames()
        end
        if ns.CDMIcons and ns.CDMIcons.UpdateAllCooldowns then
            ns.CDMIcons:UpdateAllCooldowns()
        end
    end)
end

local NCDM = {
    initialized = false,
}

NCDM.Refresh = RefreshAll
NCDM.RefreshAll = RefreshAll
NCDM.LayoutViewer = function(name, key)
    LayoutContainer(key or name)
end

local ownedEngine = {}

local VIEWER_KEY_MAP = {
    essential = "essential",
    utility   = "utility",
    buffIcon  = "buff",
    buffBar   = "trackedBar",
}

local EDIT_LOCK_KEYS = { "essential", "utility", "buff", "trackedBar" }
local reanchorHooksReadyFrame
local reanchorHooksReadyQueued = false
local reanchorHooksReadyMarkDirty = false

IsCooldownViewerReady = function()
    local catalog = ns.CDMCatalog
    if catalog and catalog.IsCooldownViewerReady then
        return catalog.IsCooldownViewerReady()
    end

    local api = _G.C_CooldownViewer
    if not api then return false end
    if not api.IsCooldownViewerAvailable then return true end
    local ok, ready = pcall(api.IsCooldownViewerAvailable)
    return ok and ready == true
end

local function QueueReanchorHooksWhenCooldownViewerReady(markDirty)
    if markDirty then
        reanchorHooksReadyMarkDirty = true
    end
    if reanchorHooksReadyQueued then return true end
    if not CreateFrame then return false end

    reanchorHooksReadyQueued = true
    if not reanchorHooksReadyFrame then
        reanchorHooksReadyFrame = CreateFrame("Frame")
    end
    reanchorHooksReadyFrame:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED")
    reanchorHooksReadyFrame:SetScript("OnEvent", function(self, event)
        if event ~= "COOLDOWN_VIEWER_DATA_LOADED" then return end
        self:UnregisterEvent("COOLDOWN_VIEWER_DATA_LOADED")
        self:SetScript("OnEvent", nil)
        reanchorHooksReadyQueued = false
        if not IsCooldownViewerReady() then return end
        local canMarkDirty = (not InCombatLockdown) or not InCombatLockdown()
        local queuedMarkDirty = reanchorHooksReadyMarkDirty or canMarkDirty
        reanchorHooksReadyMarkDirty = false
        ownedEngine:RefreshReanchorRuntimeHooks(queuedMarkDirty)
    end)
    return true
end

local _reanchorGlowOverlays = setmetatable({}, { __mode = "k" })
local REANCHOR_PROC_GLOW_KEY = "_QUICDMReanchorProcGlow"

local function EnsureReanchorGlowOverlay(frame)
    if not (frame and CreateFrame) then return nil end
    local o = _reanchorGlowOverlays[frame]
    if not o then
        o = CreateFrame("Frame", nil, frame)
        if o.SetAllPoints then o:SetAllPoints(frame) end
        _reanchorGlowOverlays[frame] = o
    end
    return o
end
ns._CDMEnsureReanchorGlowOverlay = EnsureReanchorGlowOverlay

function ownedEngine:InstallReanchorProcGlowHooks(boot)
    if not (ns.CDMReanchorProcGlow and boot and boot.GetEntryForFrame) then return false end
    local manager = _G.ActionButtonSpellAlertManager
    if not manager then return false end
    local pg = ns._cdmReanchorProcGlow
    if not pg then
        pg = ns.CDMReanchorProcGlow.New({
            getEntryForFrame = function(frame) return boot:GetEntryForFrame(frame) end,
            ensureOverlay = EnsureReanchorGlowOverlay,
            resolveGlow = function(entry)
                local OG = ns._OwnedGlows
                return OG and OG.ResolveGlowForEntry and OG.ResolveGlowForEntry(entry) or nil
            end,
            startGlow = function(overlay, viewerSettings)
                local OG = ns._OwnedGlows
                if OG and OG.ApplyGlowWithKey then
                    OG.ApplyGlowWithKey(overlay, viewerSettings, REANCHOR_PROC_GLOW_KEY)
                end
            end,
            stopGlow = function(overlay)
                local OG = ns._OwnedGlows
                if OG and OG.StopGlowWithKey then
                    OG.StopGlowWithKey(overlay, REANCHOR_PROC_GLOW_KEY)
                end
            end,
            hooksecurefunc = hooksecurefunc,
        })
        ns._cdmReanchorProcGlow = pg
    end
    return pg:Install(manager)
end

function ownedEngine:RefreshReanchorRuntimeHooks(markDirty)
    local boot = ns._cdmBoot
    local wiring = boot and boot.wiring
    if not (wiring and wiring.GetViewerForKey) then return false end
    if not IsCooldownViewerReady() then
        QueueReanchorHooksWhenCooldownViewerReady(markDirty)
        return false
    end

    local function getViewer(key)
        return wiring:GetViewerForKey(key)
    end

    local touched = false
    local hk = ns._cdmReanchorHooks
    if hk then
        hk:InstallViewerHooks(getViewer)
        if hk.InstallViewerGlue then
            hk:InstallViewerGlue(getViewer,
                function(key)
                    return CDMContainers_API and CDMContainers_API:GetContainer(key) or nil
                end,
                { essential = true, utility = true },
                function()
                    return (not InCombatLockdown()) or ns._inInitSafeWindow == true
                end)
        end
        if hk.InstallGlobalMixinHooks and hk:InstallGlobalMixinHooks() then
            touched = true
        end
        if hk.InstallIndexSubscription then
            hk:InstallIndexSubscription(ns.CDMIndex)
        end
        if markDirty then
            hk:MarkAllDirty()
        end
        touched = true
    end
    local thk = ns._cdmTrackedBarLifecycleHooks
    if thk then
        thk:InstallViewerHooks(getViewer)
        if thk.InstallGlobalMixinHooks and thk:InstallGlobalMixinHooks() then
            touched = true
        end
        if markDirty then
            thk:MarkAllDirty()
        end
        touched = true
    end

    local el = ns._cdmReanchorEditLock
    if el then
        el:Install(getViewer)
        touched = true
    end

    if self:InstallReanchorProcGlowHooks(boot) then
        touched = true
    end

    return touched
end

function ownedEngine:BootstrapReanchorRuntime()
    if not (ns.CDMReanchorBoot and ns.CDMReanchorRealEnv) then return end
    ResetInitialReanchorDone()
    local ok, boot = ns.SafeCall("best-effort-style", function()
        local env = ns.CDMReanchorRealEnv.BuildEnv({
            getSettings = GetTrackerSettings,
            resolveAdditional = function(key)
                if ns.CDMIcons and ns.CDMIcons.ResolveCustomSpellEntries then
                    return ns.CDMIcons.ResolveCustomSpellEntries(key)
                end
                return {}
            end,
            onMetrics = function(container, metrics)
                local vs = viewerState[container]
                if not vs then return end
                ApplyViewerMetrics(vs, metrics, container._quiCdmKey)
            end,
        })
        return ns.CDMReanchorBoot.BuildRuntime(env)
    end)
    if ok and boot then
        ns._cdmBoot = boot
        if ns.CDMReanchorHooks then
            local scheduleActiveState = ns.CDMReanchorHooks.CreateActiveStateScheduler(CreateFrame)
            local hk = ns.CDMReanchorHooks.New({
                refresh = function(key) return RefreshReanchoredBuiltin(boot, key) end,
                refreshMany = function(keys)
                    return RefreshReanchoredBuiltin(boot, "essential", false, keys)
                end,
                keys = REANCHOR_KEYS,
                schedule = function(fn) C_Timer.After(0.05, fn) end,
                scheduleActiveState = scheduleActiveState,
                shouldTrackActiveState = function(key) return key == "buff" end,
                shouldTrackCooldownID = function(key) return key == "buff" end,
                ignoreIndexReasons = { refresh_layout = true },
                immediateRefreshLayoutKeys = { buff = true },
                immediateAcquireKeys = { buff = true },
                blank = BlankReanchoredNativeItemFrame,
                blankKeys = { buff = true },
                isClaimed = function(frame)
                    local bridge = boot.bridge
                    return (bridge and bridge.IsClaimed and bridge:IsClaimed(frame)) or false
                end,
                installGuard = function(frame)
                    local bridge = boot.bridge
                    if bridge and bridge.InstallAnchorGuard then
                        bridge:InstallAnchorGuard(frame)
                    end
                end,
                installGuardKeys = { essential = true, utility = true },
                isInitWindow = function() return ns._inInitSafeWindow == true end,
                isInitialReanchorDone = IsInitialReanchorDone,
            })
            ns._cdmReanchorHooks = hk

            local trackedHooks = ns.CDMReanchorHooks.New({
                refresh = function(key)
                    if ns.CDMBuffLayout and ns.CDMBuffLayout.LayoutBars then
                        ns.CDMBuffLayout.LayoutBars()
                        MarkInitialReanchorDone(key or "trackedBar")
                    end
                end,
                keys = { "trackedBar" },
                hooksecurefunc = hooksecurefunc,
                schedule = function(fn) C_Timer.After(0.05, fn) end,
                scheduleActiveState = scheduleActiveState,
                immediateRefreshLayoutKeys = { trackedBar = true },
                immediateAcquireKeys = { trackedBar = true },
                blank = BlankReanchoredNativeItemFrame,
                blankKeys = { trackedBar = true },
                isInitWindow = function() return ns._inInitSafeWindow == true end,
                isInitialReanchorDone = IsInitialReanchorDone,
            })
            ns._cdmTrackedBarLifecycleHooks = trackedHooks
            self:RefreshReanchorRuntimeHooks(false)

            if EventRegistry and EventRegistry.RegisterCallback
               and not ns._cdmReanchorSettingsCallbacksInstalled then
                ns._cdmReanchorSettingsCallbacksInstalled = true
                ns._cdmReanchorSettingsCallbackOwner = {}
                local function reanchorAfterSettings()
                    if ns._cdmReanchorHooks then
                        ns._cdmReanchorHooks:MarkAllDirty()
                    end
                    if ns._cdmTrackedBarLifecycleHooks then
                        ns._cdmTrackedBarLifecycleHooks:MarkAllDirty()
                    end
                end
                EventRegistry:RegisterCallback("CooldownViewerSettings.OnShow",
                    reanchorAfterSettings, ns._cdmReanchorSettingsCallbackOwner)
                EventRegistry:RegisterCallback("CooldownViewerSettings.OnHide",
                    reanchorAfterSettings, ns._cdmReanchorSettingsCallbackOwner)
            end
        end
        self:InstallReanchorProcGlowHooks(boot)
        if ns.CDMReanchorEditLock then
            local el = ns.CDMReanchorEditLock.New({
                hooksecurefunc = hooksecurefunc,
                keys = EDIT_LOCK_KEYS,
                getDialog = function() return _G.EditModeSystemSettingsDialog end,
            })
            local wiring = boot.wiring
            if wiring and wiring.GetViewerForKey then
                el:Install(function(key) return wiring:GetViewerForKey(key) end)
            end
            ns._cdmReanchorEditLock = el
        end
    else
        ns._cdmBootError = (not ok and tostring(boot))
            or "BuildRuntime returned nil"
        print("|cffff4444QUI:|r " .. ns.L["CDM re-anchor bootstrap failed; using legacy rendering."]
            .. " " .. ns._cdmBootError)
    end
end

function ownedEngine:Initialize()
    if not IsCDMRuntimeEnabled() then
        return
    end

    inInitSafeWindow = true
    local previousInitSafeWindow = ns._inInitSafeWindow
    ns._inInitSafeWindow = true

    if ns._OwnedGlows then
        QUI.CustomGlows = ns._OwnedGlows
        _G.QUI_RefreshCustomGlows = ns._OwnedGlows.RefreshAllGlows
    end
    if ns._OwnedSwipe then
        QUI.CooldownSwipe = ns._OwnedSwipe
        _G.QUI_RefreshCooldownSwipe = ns._OwnedSwipe.Apply
        _G.QUI_RefreshCooldownEffects = ns._OwnedSwipe.Apply
        ns.QUI_RefreshCDMReanchor = function()
            RefreshAll()
        end
    end

    if ns.Registry then
        ns.Registry:Register("cooldownEffects", {
            refresh = _G.QUI_RefreshCooldownEffects,
            priority = 10,
            group = "cooldowns",
            importCategories = { "cdm" },
        })
        ns.Registry:Register("cooldownSwipe", {
            refresh = _G.QUI_RefreshCooldownSwipe,
            priority = 10,
            group = "cooldowns",
            importCategories = { "cdm" },
        })
        ns.Registry:Register("cooldownGlows", {
            refresh = _G.QUI_RefreshCustomGlows,
            priority = 10,
            group = "cooldowns",
            importCategories = { "cdm" },
        })
    end

    if ns.CDMSpellData then
        ns.CDMSpellData:Initialize()
    end

    local function RetrySnapshotBuiltInContainers(attempt)
        if InCombatLockdown() then return end
        if not ns.CDMSpellData then return end

        local snapshotted = false
        local allReady = true
        for _, key in ipairs(BUILTIN_KEYS) do
            local didSnapshot, snapshotReady = ns.CDMSpellData:SnapshotBlizzardCDM(key)
            if didSnapshot then
                snapshotted = true
            end
            if not snapshotReady then
                allReady = false
            end
        end

        if snapshotted then
            RefreshAll()
        end
        if not allReady and attempt < SPEC_TRACKING_MAX_RETRIES then
            C_Timer.After(SPEC_TRACKING_RETRY_DELAY, function()
                RetrySnapshotBuiltInContainers(attempt + 1)
            end)
        end
    end

    C_Timer.After(2.0, function()
        RetrySnapshotBuiltInContainers(1)
    end)

    local ncdmDB = GetDB()
    if ncdmDB then
        for _, key in ipairs({"buff", "trackedBar"}) do
            if ncdmDB[key] and ncdmDB[key].enabled == nil then
                ncdmDB[key].enabled = true
            end
        end
    end

    InitContainers()
    InitBuffContainer()

    initialized = true
    NCDM.initialized = true

    local specReadyNow = InitSpecTracking()
    RegisterProfileCallbacks()

    if ns.InvalidateCDMFrameCache then
        ns.InvalidateCDMFrameCache()
    end

    self:BootstrapReanchorRuntime()

    if specReadyNow then
        RefreshAll(true)
    else
        specTrackingPendingRefresh = true
    end

    if _G.QUI_ApplyAllFrameAnchors then
        _G.QUI_ApplyAllFrameAnchors()
    end
    UpdateAllLockedBars()

    if _G.QUI_RefreshCDMVisibility and not ownedEngine._mouseSyncHooked then
        ownedEngine._mouseSyncHooked = true
        hooksecurefunc("QUI_RefreshCDMVisibility", function()
            SyncAllContainerMouseStates(true)
        end)
    end

    local shouldShow = _G.QUI_ShouldCDMBeVisible and _G.QUI_ShouldCDMBeVisible()
    local targetAlpha
    if shouldShow then
        targetAlpha = 1
    else
        local vis = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.cdmVisibility
        targetAlpha = vis and vis.fadeOutAlpha or 0
    end
    for _, frame in pairs(containers) do
        if frame and frame.SetAlpha then
            frame:SetAlpha(targetAlpha)
        end
    end
    SyncAllContainerMouseStates(true)
    if _G.QUI_RefreshCDMVisibility then
        _G.QUI_RefreshCDMVisibility()
    end

    inInitSafeWindow = false
    ns._inInitSafeWindow = previousInitSafeWindow

    local function DrainPendingLoadoutSwitch(cacheConfigID)
        pendingLoadoutRefresh = false
        loadoutTrackingToken = loadoutTrackingToken + 1
        local drainToken = loadoutTrackingToken

        local drainSpecID = GetCurrentSpecID()
        if not drainSpecID then return end

        SaveLoadoutProfile(_previousLoadoutID, drainSpecID)
        local newConfigID = nil
        if C_ClassTalents and C_ClassTalents.GetLastSelectedSavedConfigID then
            newConfigID = C_ClassTalents.GetLastSelectedSavedConfigID(drainSpecID)
        end
        _previousLoadoutID = newConfigID
        _lastKnownSavedConfigID = newConfigID

        if cacheConfigID then
            local charNcdm = GetCharNcdmDB(true)
            if charNcdm and newConfigID and newConfigID ~= NO_SAVED_LOADOUT_ID then
                if type(charNcdm._lastLoadoutConfigID) ~= "table" then
                    charNcdm._lastLoadoutConfigID = {}
                end
                charNcdm._lastLoadoutConfigID[drainSpecID] = newConfigID
            end
        end

        LoadLoadoutProfile(newConfigID, drainSpecID, drainToken)
        FireLoadoutChangeCallbacks()
    end

    local eventFrame = CreateFrame("Frame")
    runtimeEventFrame = eventFrame
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    eventFrame:RegisterEvent("ACTIVE_COMBAT_CONFIG_CHANGED")
    eventFrame:RegisterEvent("TRAIT_CONFIG_LIST_UPDATED")
    eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    eventFrame:RegisterEvent("SELECTED_LOADOUT_CHANGED")
    eventFrame:RegisterEvent("SPECIALIZATION_CHANGE_CAST_FAILED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("CHALLENGE_MODE_START")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:RegisterEvent("CINEMATIC_STOP")
    eventFrame:RegisterEvent("STOP_MOVIE")
    eventFrame:RegisterEvent("ADDON_LOADED")
    RegisterClassTalentSwitchCallbacks()

    eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2)
        if not IsCDMRuntimeEnabled() then
            self:UnregisterAllEvents()
            return
        end

        local viewerAddon = ns.CDMCooldownViewerAddon
        local cooldownViewerLoaded = (viewerAddon and viewerAddon.IsViewerAddon and viewerAddon.IsViewerAddon(arg1))
            or arg1 == "Blizzard_CooldownViewer"

        if event == "ADDON_LOADED" and cooldownViewerLoaded then
            InitBuffContainer()
            ownedEngine:RefreshReanchorRuntimeHooks(not InCombatLockdown())
            if initialized then
                if ns.InvalidateCDMFrameCache then ns.InvalidateCDMFrameCache() end
                RefreshAll()
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            local isLogin, isReload = arg1, arg2
            ownedEngine:RefreshReanchorRuntimeHooks(false)
            if isReload then
                local pewPreviousInitSafeWindow = ns._inInitSafeWindow
                inInitSafeWindow = true
                ns._inInitSafeWindow = true
                RefreshAll(true)
                if _G.QUI_ApplyAllFrameAnchors then
                    _G.QUI_ApplyAllFrameAnchors()
                end
                inInitSafeWindow = false
                ns._inInitSafeWindow = pewPreviousInitSafeWindow
                ResolveInitialLoadoutSlot()
            elseif isLogin then
                ResolveInitialLoadoutSlot()
                C_Timer.After(0.5, function()
                    if not specTrackingReady then
                        specTrackingReady = InitSpecTracking()
                        if not specTrackingReady then
                            specTrackingPendingRefresh = true
                            return
                        end
                    end
                    ResolveInitialLoadoutSlot()
                    local needsRefresh = false
                    if not InCombatLockdown() and LiveContainerOwnedByOtherCharacter() then
                        local specID = GetCurrentSpecID()
                        if specID and specID ~= 0 then
                            specTrackingRetryToken = specTrackingRetryToken + 1
                            needsRefresh = LoadOrSnapshotSpecProfile(specID, 1, specTrackingRetryToken)
                        end
                    end
                    if not InCombatLockdown() and ns.CDMSpellData then
                        needsRefresh = ns.CDMSpellData:CheckAllDormantSpells() or needsRefresh
                        ns.CDMSpellData:ReconcileAllContainers()
                    end
                    if needsRefresh then
                        RefreshAll()
                    end
                end)
            elseif not isReload then
                ResolveInitialLoadoutSlot()
                C_Timer.After(0.3, RefreshAll)
            end
        elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
            local newSpecID = ConsumePendingClassTalentSpecSwitchID() or GetCurrentSpecID()
            if not newSpecID or newSpecID ~= _previousSpecID then
                if _previousSpecID and _previousSpecID ~= 0 then
                    SaveCurrentSpecProfile()
                end
                if ns.InvalidateCDMFrameCache then ns.InvalidateCDMFrameCache() end
                if ns.CDMSpellData and ns.CDMSpellData.InvalidateLearnedCache then
                    ns.CDMSpellData:InvalidateLearnedCache()
                end
                specTrackingReady = false
                specTrackingPendingRefresh = true
                specTrackingRetryToken = specTrackingRetryToken + 1
                local readyNow = LoadOrSnapshotSpecProfile(newSpecID, 1, specTrackingRetryToken)
                _previousSpecID = newSpecID
                _previousLoadoutID = GetEffectiveLoadoutIDForSpec(newSpecID)
                local specDB = GetSpecStateDB(true)
                if specDB then
                    specDB._lastSpecID = newSpecID
                    specDB._lastSpecCharKey = GetCurrentCharacterKey()
                end
                buffFingerprint = nil
                if readyNow then
                    specTrackingReady = true
                    specTrackingPendingRefresh = false
                    RefreshAll()
                end
            end
        elseif event == "TRAIT_CONFIG_UPDATED" or event == "ACTIVE_COMBAT_CONFIG_CHANGED"
            or event == "SELECTED_LOADOUT_CHANGED" then
            if not _initialLoadoutResolved then
                ResolveInitialLoadoutSlot()
            end
            if loadoutDebounceTimer then loadoutDebounceTimer:Cancel() end

            loadoutTrackingToken = loadoutTrackingToken + 1
            local myToken = loadoutTrackingToken

            loadoutDebounceTimer = C_Timer.NewTimer(0.5, function()
                loadoutDebounceTimer = nil
                if myToken ~= loadoutTrackingToken then return end
                if not specTrackingReady then
                    pendingLoadoutRefresh = true
                    return
                end

                local specID = GetCurrentSpecID()
                if not specID then return end

                if ns.CDMContainers and ns.CDMContainers.ReconcileOnHeroSubTreeChange then
                    ns.CDMContainers.ReconcileOnHeroSubTreeChange()
                end

                local newConfigID = ConsumePendingClassTalentLoadoutIDForSpec(specID)
                if newConfigID == nil and C_ClassTalents and C_ClassTalents.GetLastSelectedSavedConfigID then
                    newConfigID = C_ClassTalents.GetLastSelectedSavedConfigID(specID)
                end

                if newConfigID == _lastKnownSavedConfigID then return end

                if InCombatLockdown() then
                    pendingLoadoutRefresh = true
                    return
                end

                SaveLoadoutProfile(_previousLoadoutID, specID)

                _previousLoadoutID = newConfigID
                _lastKnownSavedConfigID = newConfigID

                local charNcdm = GetCharNcdmDB(true)
                if charNcdm then
                    if type(charNcdm._lastLoadoutConfigID) ~= "table" then
                        charNcdm._lastLoadoutConfigID = {}
                    end
                    charNcdm._lastLoadoutConfigID[specID] = newConfigID
                end

                LoadLoadoutProfile(newConfigID, specID, myToken)
                FireLoadoutChangeCallbacks()
            end)
        elseif event == "PLAYER_TALENT_UPDATE" then
            if not specTrackingReady then
                local readyNow = InitSpecTracking()
                specTrackingReady = readyNow
                if readyNow and specTrackingPendingRefresh then
                    FinalizeSpecTracking()
                end
            end
            ResolveInitialLoadoutSlot()
        elseif event == "SPECIALIZATION_CHANGE_CAST_FAILED" then
            ClearPendingClassTalentSwitchIntent()
        elseif event == "TRAIT_CONFIG_LIST_UPDATED" then
            loadoutListReady = true

            local specID = GetCurrentSpecID()
            if specID and C_ClassTalents and C_ClassTalents.GetLastSelectedSavedConfigID then
                local configID = C_ClassTalents.GetLastSelectedSavedConfigID(specID)
                if configID and configID ~= NO_SAVED_LOADOUT_ID then
                    local charNcdm = GetCharNcdmDB(true)
                    if charNcdm then
                        if type(charNcdm._lastLoadoutConfigID) ~= "table" then
                            charNcdm._lastLoadoutConfigID = {}
                        end
                        charNcdm._lastLoadoutConfigID[specID] = configID
                    end
                end
            end

            ResolveInitialLoadoutSlot()

            if pendingLoadoutRefresh
                and specTrackingReady
                and not InCombatLockdown()
            then
                DrainPendingLoadoutSwitch(false)
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            if ns._cdmReanchorHooks and ns._cdmReanchorHooks.ReassertViewerGlue then
                ns._cdmReanchorHooks:ReassertViewerGlue()
            end

            if ns._cdmBoot and ns._cdmBoot.DrainPendingCombatRefresh then
                ns._cdmBoot:DrainPendingCombatRefresh()
            end

            local readyNow = specTrackingReady
            if not specTrackingReady then
                readyNow = InitSpecTracking()
                specTrackingReady = readyNow
            end

            if not readyNow then
                specTrackingPendingRefresh = true
                return
            end

            if specTrackingPendingRefresh then
                FinalizeSpecTracking()
            end

            if pendingLoadoutRefresh and loadoutListReady and specTrackingReady then
                DrainPendingLoadoutSwitch(true)
            end

            if _containerMouseSyncPending and not InCombatLockdown() then
                _containerMouseSyncPending = false
                SyncAllContainerMouseStates(true)
            end

            if _challengeModeRecoveryPending and not InCombatLockdown() then
                _challengeModeRecoveryPending = false
                if ns.CDMSpellData then
                    ns.CDMSpellData:CheckAllDormantSpells()
                    ns.CDMSpellData:ReconcileAllContainers()
                end
                RefreshAll()
            end
        elseif event == "CHALLENGE_MODE_START" then
            C_Timer.After(0.5, function()
                if not IsCDMRuntimeEnabled() then return end
                if InCombatLockdown() then
                    _challengeModeRecoveryPending = true
                    return
                end
                _challengeModeRecoveryPending = false
                if ns.CDMSpellData then
                    ns.CDMSpellData:CheckAllDormantSpells()
                    ns.CDMSpellData:ReconcileAllContainers()
                end
                RefreshAll()
            end)
        elseif event == "ZONE_CHANGED_NEW_AREA" then
            C_Timer.After(0.3, RefreshAll)
        elseif event == "CINEMATIC_STOP" or event == "STOP_MOVIE" then
            C_Timer.After(0.3, function()
                if ns.InvalidateCDMFrameCache then ns.InvalidateCDMFrameCache() end
                RefreshAll()
                if _G.QUI_RefreshCDMVisibility then
                    _G.QUI_RefreshCDMVisibility()
                end
                if _G.QUI_RefreshUnitframesVisibility then
                    _G.QUI_RefreshUnitframesVisibility()
                end
            end)
        end
    end)

    ns.DebugRegister(function()
        ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
        ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "CDM_Containers", frame = eventFrame }
    end)
end

function ownedEngine:DisableRuntime()
    initialized = false
    NCDM.initialized = false
    specTrackingPendingRefresh = false
    specTrackingRetryToken = specTrackingRetryToken + 1
    inInitSafeWindow = false
    ResetInitialReanchorDone()
    CancelRefreshTimers()

    if loadoutDebounceTimer then
        loadoutDebounceTimer:Cancel()
        loadoutDebounceTimer = nil
    end
    pendingLoadoutRefresh = false
    _challengeModeRecoveryPending = false
    loadoutTrackingToken = loadoutTrackingToken + 1

    if runtimeEventFrame then
        runtimeEventFrame:UnregisterAllEvents()
        runtimeEventFrame:SetScript("OnEvent", nil)
        runtimeEventFrame = nil
    end

    for _, frame in pairs(containers) do
        if frame and frame.SetAlpha then
            frame.SetAlpha(frame, 0)
        end
    end
end

function ownedEngine:Refresh()
    RefreshAll()
end

function ownedEngine:GetViewerFrame(key)
    local containerKey = VIEWER_KEY_MAP[key]
    if containerKey then
        local container = containers[containerKey]
        if container then return container end
    end
    if containers[key] then
        return containers[key]
    end
    return nil
end

function ownedEngine:GetViewerFrames()
    local frames = {}
    if containers.essential then frames[#frames + 1] = containers.essential end
    if containers.utility then frames[#frames + 1] = containers.utility end
    if containers.buff then frames[#frames + 1] = containers.buff end
    if containers.trackedBar then frames[#frames + 1] = containers.trackedBar end
    for key, frame in pairs(containers) do
        if not BUILTIN_NAMES[key] and frame then
            frames[#frames + 1] = frame
        end
    end
    return frames
end

function ownedEngine:GetViewerState(viewer)
    return GetViewerState(viewer)
end

function ownedEngine:SetViewerBounds(viewer, boundsW, boundsH)
    SetViewerBounds(viewer, boundsW, boundsH)
end

function ownedEngine:RefreshViewerFromBounds(viewer, trackerKey)
    RefreshViewerFromBounds(viewer, trackerKey)
end

function ownedEngine:GetIconState(icon)
    if not icon then return nil end
    return icon._spellEntry and icon or nil
end

function ownedEngine:ClearIconState(icon)
    if not icon then return end
    if ns.CDMIconFactory then
        ns.CDMIconFactory:ReleaseIcon(icon)
    end
end

function ownedEngine:IsHUDAnchoredToCDM()
    return IsHUDAnchoredToCDM()
end

function ownedEngine:GetHUDMinWidthSettings()
    return GetHUDMinWidth()
end

function ownedEngine:ApplyUtilityAnchor()
    ApplyUtilityAnchor()
end

function ownedEngine:IsSelectionKeepVisible(sel)
    return false
end

function ownedEngine:GetNCDM()
    return NCDM
end

function ownedEngine:GetCustomCDM()
    return ns.CDMIcons and ns.CDMIcons.CustomCDM or nil
end

function ownedEngine:LayoutViewer(name, key)
    LayoutContainer(key or name)
end

local CDMProvider = {
    initialized = false,
    disabled = false,
    emptyFrames = {},
}

local BLIZZARD_FRAME_KEYS = {
    essential = "EssentialCooldownViewer",
    utility = "UtilityCooldownViewer",
    buffIcon = "BuffIconCooldownViewer",
    buffBar = "BuffBarCooldownViewer",
}
CDMProvider.BLIZZARD_FRAME_KEYS = BLIZZARD_FRAME_KEYS

local function GetNCDMProfile()
    local addon = _G.QUI
    local db = addon and addon.db
    local profile = db and db.profile
    return profile and profile.ncdm or nil
end

function CDMProvider:IsMasterEnabled()
    local ncdm = GetNCDMProfile()
    return not ncdm or ncdm.enabled ~= false
end

function CDMProvider:IsDisabled()
    return self.disabled == true
end

function CDMProvider:IsRuntimeEnabled()
    return self:IsMasterEnabled() and not self:IsDisabled()
end

function CDMProvider:GetViewerFrameNames()
    return BLIZZARD_FRAME_KEYS
end

function CDMProvider:GetViewerFrame(key)
    if self.disabled then return nil end

    if self.initialized and ownedEngine.GetViewerFrame then
        local frame = ownedEngine:GetViewerFrame(key)
        if frame then return frame end
    end

    return nil
end

function CDMProvider:GetViewerFrames()
    if self.disabled then
        return self.emptyFrames
    end

    if self.initialized and ownedEngine.GetViewerFrames then
        return ownedEngine:GetViewerFrames()
    end

    return self.emptyFrames
end

local GLOBAL_WIRE_MAP = {
    { method = "Refresh",                 global = "QUI_RefreshNCDM" },
    { method = "ApplyUtilityAnchor",      global = "QUI_ApplyUtilityAnchor" },
    { method = "IsSelectionKeepVisible",  global = "QUI_IsSelectionKeepVisible" },
    { method = "GetViewerState",          global = "QUI_GetCDMViewerState" },
    { method = "SetViewerBounds",         global = "QUI_SetCDMViewerBounds" },
    { method = "RefreshViewerFromBounds", global = "QUI_RefreshCDMViewerFromBounds" },
    { method = "GetIconState",            global = "QUI_GetIconState" },
    { method = "ClearIconState",          global = "QUI_ClearIconState" },
    { method = "IsHUDAnchoredToCDM",      global = "QUI_IsHUDAnchoredToCDM" },
    { method = "GetHUDMinWidthSettings",  global = "QUI_GetHUDMinWidthSettings" },
}

local function WireProviderGlobals()
    for _, entry in ipairs(GLOBAL_WIRE_MAP) do
        if ownedEngine[entry.method] then
            _G[entry.global] = function(...)
                return ownedEngine[entry.method](ownedEngine, ...)
            end
        end
    end
end

local function DisableOwnedRuntime()
    if ownedEngine.DisableRuntime then
        ownedEngine:DisableRuntime()
    end
    if ns.CDMSpellData and ns.CDMSpellData.DisableRuntime then
        ns.CDMSpellData:DisableRuntime()
    end
    if ns.CDMIcons and ns.CDMIcons.DisableRuntime then
        ns.CDMIcons:DisableRuntime()
    end
    if ns._OwnedGlows and ns._OwnedGlows.DisableRuntime then
        ns._OwnedGlows.DisableRuntime()
    end
    if ns._OwnedHighlighter and ns._OwnedHighlighter.DisableRuntime then
        ns._OwnedHighlighter.DisableRuntime()
    end
end

function CDMProvider:DisableRuntime()
    self.disabled = true
    DisableOwnedRuntime()
    if ns.InvalidateCDMFrameCache then
        ns.InvalidateCDMFrameCache()
    end
end

function CDMProvider:InitializeEngine()
    if self.initialized then return end

    if not self:IsMasterEnabled() then
        self:DisableRuntime()
        return
    end

    self.disabled = false
    self.initialized = true

    if ownedEngine.Initialize then
        ownedEngine:Initialize()
    end

    WireProviderGlobals()

    if ns.Registry then
        ns.Registry:Register("ncdm", {
            refresh = _G.QUI_RefreshNCDM,
            priority = 10,
            group = "cooldowns",
            importCategories = { "cdm" },
        })
    end

    if ownedEngine.GetNCDM then
        ns.NCDM = ownedEngine:GetNCDM()
    end
    if ownedEngine.GetCustomCDM then
        ns.CustomCDM = ownedEngine:GetCustomCDM()
    end

    if ns.InvalidateCDMFrameCache then
        ns.InvalidateCDMFrameCache()
    end
end

_G.QUI_GetCDMViewerFrame = function(key)
    return CDMProvider:GetViewerFrame(key)
end

_G.QUI_IsCDMMasterEnabled = function()
    return CDMProvider:IsRuntimeEnabled()
end

_G.QUI_GetReanchoredCDMFrames = function(viewerName)
    local boot = ns._cdmBoot
    if not boot or not boot.GetReanchoredFrames then return nil end
    return boot:GetReanchoredFrames(viewerName)
end

_G.QUI_ResolveCDMFrameEntry = function(frame)
    local boot = ns._cdmBoot
    if not boot or not boot.GetEntryForFrame then return nil end
    return boot:GetEntryForFrame(frame)
end

ns.CDMProvider = CDMProvider

local providerEventFrame = CreateFrame("Frame")
providerEventFrame:RegisterEvent("ADDON_LOADED")
providerEventFrame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == ADDON_NAME then
        self:UnregisterEvent("ADDON_LOADED")
        CDMProvider:InitializeEngine()
    end
end)

_G.QUI_DebugCDM = _G.QUI_DebugCDM or {}
_G.QUI_DebugCDM.GetLayoutSettings = function() return ns.QUI_LayoutMode_Settings end
_G.QUI_DebugCDM.GetLayoutMode = function() return ns.QUI_LayoutMode end
_G.QUI_DebugCDM.GetContainersAPI = function() return CDMContainers_API end
_G.QUI_DebugCDM.BuffState = function()
    local function say(...) print("|cFF30D1FF[BuffState]|r", ...) end
    say("catalogReady:", IsCooldownViewerReady() and true or false,
        " initialReanchorDone(buff):", IsInitialReanchorDone("buff") and true or false,
        " boot:", ns._cdmBoot and true or false,
        " hooks:", ns._cdmReanchorHooks and true or false)
    local viewer = _G.BuffIconCooldownViewer
    if ns._cdmReanchorHooks and viewer then
        say("viewerHooked:", ns._cdmReanchorHooks._hooked[viewer] and true or false)
    end
    local curated = {}
    if ns.CDMSpellData and ns.CDMSpellData.BuildSpellListFromOwned then
        local ok, list = pcall(ns.CDMSpellData.BuildSpellListFromOwned, ns.CDMSpellData, "buff")
        if ok and type(list) == "table" then curated = list end
    end
    say("curated:", #curated)
    for i = 1, #curated do
        local e = curated[i]
        local sid = e.overrideSpellID or e.spellID or e.id
        local live = false
        say(("  entry %d: id=%s spellID=%s auraLive=%s"):format(
            i, tostring(e.id), tostring(sid), tostring(live)))
    end
    local reg = _G.QUI_GetReanchoredCDMFrames and _G.QUI_GetReanchoredCDMFrames("buff")
    say("claimedRegistry:", reg and #reg or 0)
    local settings = GetTrackerSettings("buff")
    say("iconDisplayMode:", tostring(settings and settings.iconDisplayMode))
    local runtime = ns._cdmBoot and ns._cdmBoot.runtime
    local diag = runtime and runtime.GetLastDiag and runtime:GetLastDiag("buff")
    if diag then
        if diag.earlyReturn then
            say(("lastPass: seq=%d at=%s EARLY-RETURN=%s"):format(
                diag.seq or -1, tostring(diag.at), diag.earlyReturn))
        else
            say(("lastPass: seq=%d at=%s mode=%s filter=%s edit=%s probe=%s"):format(
                diag.seq or -1, tostring(diag.at), tostring(diag.displayMode),
                tostring(diag.filterInactive), tostring(diag.editing),
                tostring(diag.auraProbe)))
            say(("  curated=%d matched=%d frameless=%d additional=%d"):format(
                diag.curated or -1, diag.matched or -1,
                diag.frameless or -1, diag.additional or -1))
            say(("  nativeClaimed=%d staleNative=%d fallbackLive=%d minted=%d mintFailed=%d"):format(
                diag.nativeClaimed or -1, diag.staleNative or -1,
                diag.fallbackLive or -1, diag.minted or -1, diag.mintFailed or -1))
            say(("  entriesOut=%d planNil=%s positioned=%s"):format(
                diag.entriesOut or -1, tostring(diag.planNil), tostring(diag.positioned)))
        end
        if _G.GetTime and diag.at then
            say(("  passAge: %.1fs ago"):format(_G.GetTime() - diag.at))
        end
    else
        say("lastPass: NO DIAG (no refresh pass has run)")
    end
    local ledger = runtime and runtime._mintedOwnedByKey and runtime._mintedOwnedByKey["buff"]
    say("ownedLedger:", ledger and #ledger or 0)
    for i = 1, (ledger and #ledger or 0) do
        local icon = ledger[i]
        local okV, shown = pcall(icon.IsShown, icon)
        local okAl, alpha = pcall(icon.GetAlpha, icon)
        local okW, w = pcall(icon.GetWidth, icon)
        local okP, np = pcall(icon.GetNumPoints, icon)
        say(("  owned %d: shown=%s alpha=%s w=%s points=%s"):format(
            i,
            okV and tostring(shown) or "ERR",
            okAl and tostring(alpha) or "ERR",
            okW and tostring(w) or "ERR",
            okP and tostring(np) or "ERR"))
    end
    if viewer and viewer.GetItemFrames then
        local okItems, items = pcall(viewer.GetItemFrames, viewer)
        if okItems and type(items) == "table" then
            say("nativeItems:", #items)
            for i = 1, #items do
                local f = items[i]
                local okC, cid = pcall(f.GetCooldownID, f)
                local okS, sid = pcall(f.GetSpellID, f)
                local okA, act = pcall(f.IsActive, f)
                local okV, shown = pcall(f.IsShown, f)
                local okAl, alpha = pcall(f.GetAlpha, f)
                say(("  item %d: cd=%s spell=%s info=%s active=%s shown=%s alpha=%s"):format(
                    i,
                    okC and tostring(cid) or "ERR",
                    okS and tostring(sid) or "ERR",
                    f.cooldownInfo and "yes" or "NO",
                    okA and tostring(act) or "ERR",
                    okV and tostring(shown) or "ERR",
                    okAl and tostring(alpha) or "ERR"))
            end
        end
    end
end

ns.CDMContainers = {
    GetContainer = function(viewerType) return containers[viewerType] end,
    LayoutContainer = LayoutContainer,
    RefreshAll = RefreshAll,
    RebuildBuffContainer = RebuildBuffContainer,
    RefreshReanchorRuntimeHooks = function(markDirty)
        return ownedEngine:RefreshReanchorRuntimeHooks(markDirty)
    end,
    ReconcileOnHeroSubTreeChange = function()
        local current = GetCurrentHeroSubTree()
        if current == _lastKnownHeroSubTree then return end
        _lastKnownHeroSubTree = current
        if not InCombatLockdown() and ns.CDMSpellData then
            ns.CDMSpellData:CheckAllDormantSpells()
            ns.CDMSpellData:ReconcileAllContainers()
            if RefreshAll then RefreshAll() end
        end
    end,
    GetTrackedBarContainer = function() return containers.trackedBar end,
    GetContainerShape = GetContainerShape,
    IsBarShape = IsBarShape,
    BUILTIN_SHAPES = BUILTIN_SHAPES,
    ResolveLayoutElementKey = function(containerKey)
        if containerKey == "essential" then return "cdmEssential" end
        if containerKey == "utility"   then return "cdmUtility"   end
        if containerKey == "buff"      then return "buffIcon"     end
        if containerKey == "trackedBar" then return "buffBar"     end
        return "cdmCustom_" .. containerKey
    end,
    CreateContainer = function(name, containerType) return CDMContainers_API:CreateContainer(name, containerType) end,
    DeleteContainer = function(key) return CDMContainers_API:DeleteContainer(key) end,
    RenameContainer = function(key, name) return CDMContainers_API:RenameContainer(key, name) end,
    GetContainers = function() return CDMContainers_API:GetContainers() end,
    GetContainerSettings = function(key) return CDMContainers_API:GetContainerSettings(key) end,
    GetContainersByType = function(containerType) return CDMContainers_API:GetContainersByType(containerType) end,
    GetAllContainerKeys = function() return CDMContainers_API:GetAllContainerKeys() end,
    RegisterDynamicLayoutElement = function(key, settings) return CDMContainers_API:RegisterDynamicLayoutElement(key, settings) end,
    SyncSettingsFeatureLookups = SyncSettingsFeatureLookups,
    SaveActiveSpecProfile = function()
        if not specTrackingReady then return end
        SaveSpecProfile(GetCurrentSpecID())
    end,
    ResnapshotForCurrentSpec = function()
        if not ns.CDMSpellData then return end
        local containerKeys = CDMContainers_API:GetAllContainerKeys()
        for _, key in ipairs(containerKeys) do
            local containerDB = GetTrackerSettings(key)
            if IsSpecManagedContainer(containerDB) then
                containerDB.ownedSpells = nil
                containerDB.dormantSpells = nil
            end
        end
        for _, key in ipairs(containerKeys) do
            if IsSpecManagedContainer(GetTrackerSettings(key)) then
                ns.CDMSpellData:SnapshotBlizzardCDM(key)
            end
        end
    end,

    SeedActiveLoadoutFromSharedSlot = SeedActiveLoadoutFromSharedSlot,

    RegisterLoadoutChangeCallback = RegisterLoadoutChangeCallback,
}
