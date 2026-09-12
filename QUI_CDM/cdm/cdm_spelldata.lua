local _, ns = ...
local Helpers = ns.Helpers
local Sources = ns.CDMSources
local Shared = ns.CDMShared

local function IsCDMRuntimeEnabled()
    return not Shared or Shared.IsRuntimeEnabled()
end

local CDMSpellData = {}

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

local function IsUsableTableKey(key)
    if issecretvalue and issecretvalue(key) then return false end -- @secret-policy: reject-secret-ids
    if not key then return false end
    return true
end

local function IsUsableSpellIDKey(spellID)
    return IsUsableTableKey(spellID)
        and type(spellID) == "number"
end

local function ClearDeprecatedLearnedCastToAuraDB()
    local QUI = ns.Addon
    if not QUI or not QUI.db or not QUI.db.global then return nil end
    if QUI.db.global.cdmLearnedCastToAura ~= nil then
        QUI.db.global.cdmLearnedCastToAura = nil
    end
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

function CDMSpellData:DisableRuntime()
    if ns.CDMAlerts and ns.CDMAlerts.RequestNativeSoundRefresh then
        ns.CDMAlerts.RequestNativeSoundRefresh(true)
    end
    initialized = false
    if runtimeEventFrame then
        runtimeEventFrame:UnregisterAllEvents()
        runtimeEventFrame:SetScript("OnEvent", nil)
        runtimeEventFrame = nil
    end
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

local _abilityToAuraSpellID
local _auraIDsForSpell
local ResolveAuraDisplaySpellID
local totemResult, totemCount = {}, {}

local function ResolveTotemRuntimeState(params)
    local result = totemResult
    wipe(result)
    wipe(totemCount)
    result.isActive, result.auraUnit, result.count = false, "player", totemCount
    totemCount.shown = false
    local spellID = params.spellID
    if not spellID then return result end
    if ResolveAuraDisplaySpellID then
        spellID = ResolveAuraDisplaySpellID(spellID)
    end
    local slot = params.totemSlot
    if slot == nil and params.entryIsAura ~= true and params.entryKind ~= "aura" then
        slot = FindTotemSlotForSpellIDs(spellID, params.entrySpellID, params.entryID)
    end
    if slot then
        local state = ResolveVirtualAuraState(slot)
        if state.slot then
            result.totemSlot = state.slot
            result.totemName = state.totemName
            result.totemIcon = state.totemIcon
            result.isTotemInstance = true
            result.isActive = state.isActive == true
            result.durObj = state.durObj
        end
    end
    return result
end

if ns.CDMAuraRuntime and ns.CDMAuraRuntime.SetResolver then
    ns.CDMAuraRuntime.SetResolver(ResolveTotemRuntimeState)
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
    if Shared and ((Shared.IsBuiltinContainerKey and Shared.IsBuiltinContainerKey(containerKey))
        or (Shared.GetBuiltinContainerEntryKind and Shared.GetBuiltinContainerEntryKind(containerKey))) then
        return ncdm[containerKey]
    end
    return ncdm.containers and ncdm.containers[containerKey] or nil
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
        quiAlerts = entry.quiAlerts,
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
    if ns.CDMNativeCallTrace then ns.CDMNativeCallTrace:Checkpoint("reconcile entry") end
    local restored = CDMSpellData:CheckAllDormantSpells()
    if ns.CDMNativeCallTrace then ns.CDMNativeCallTrace:Checkpoint("dormant spells checked") end
    local before = guardUnchanged and LearnedCatalogSignature() or nil
    CDMSpellData:ReconcileAllContainers()
    if ns.CDMNativeCallTrace then ns.CDMNativeCallTrace:Checkpoint("catalog reconciled") end
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
    if ns.CDMAlerts and ns.CDMAlerts.RequestNativeSoundRefresh then
        ns.CDMAlerts.RequestNativeSoundRefresh()
    end
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
    if type(entry.quiAlerts) == "table" then
        out.quiAlerts = CopyTable(entry.quiAlerts)
    end
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
    local db = GetContainerDB(containerKey)
    if type(db) == "table" and db.specSpecific then
        MoveLegacySpecEntriesToPerSpecStorage(containerKey, db)
    end
    return GetSpecEntryList(containerKey, specKey, false)
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
    return {
        learnedDirty = learnedCooldownsCacheDirty and true or false,
        learnedSize = type(learnedCooldownsCache) == "table" and #learnedCooldownsCache or 0,
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
    eventFrame:RegisterUnitEvent("UNIT_AURA", "player", "pet", "target")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:SetScript("OnEvent", function(self, event, arg)
        if ns.CDMNativeCallTrace then ns.CDMNativeCallTrace:Checkpoint("spelldata event entry: " .. event) end
        if not IsCDMRuntimeEnabled() then
            self:UnregisterAllEvents()
            return
        end

        if event == "UNIT_AURA" then
            if issecretvalue and issecretvalue(arg) then
                for _, unit in ipairs(REGISTERED_UNITS) do
                    NotifyAuraConsumers(unit, nil)
                end
            else
                NotifyAuraConsumers(arg, nil)
            end
        elseif event == "PLAYER_TARGET_CHANGED" then
            NotifyAuraConsumers("target", nil)
        elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
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
CDMSpellData.GetLinkedSpellIDsForSpellID = GetLinkedSpellIDsForSpellID
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
