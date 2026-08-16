local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local IsSecretValue = Helpers.IsSecretValue
local SafeValue = Helpers.SafeValue
local SafeToNumber = Helpers.SafeToNumber
local GetDB = Helpers.CreateDBGetter("quiGroupFrames")
local AuraModel = ns.QUI_GroupFramesAuraModel
local CHROME_LEVELS = (ns.QUI_GroupFrameChrome and ns.QUI_GroupFrameChrome.LEVELS)
    or { AURA_HOST = 12 }
local function GetFrameUnit(frame)
    local GF = ns.QUI_GroupFrames
    return GF and GF.GetFrameUnit and GF.GetFrameUnit(frame) or nil
end
local function GetRender() return ns.QUI_GroupFrameAuraRender end

local _bucketFnParty = function() return AuraModel.DefaultStripBucket("party") end
local _bucketFnRaid  = function() return AuraModel.DefaultStripBucket("raid") end
local function BucketFnFor(frame)
    return (frame and frame._isRaid) and _bucketFnRaid or _bucketFnParty
end

local pairs = pairs
local ipairs = ipairs
local type = type
local wipe = wipe
local C_UnitAuras = C_UnitAuras
local table_remove = table.remove

local QUI_GFA = {}
ns.QUI_GroupFrameAuras = QUI_GFA

local function EngineRendersElement(element)
    if not element then return false end
    local mode = element.mode
    if mode == "missingRaidBuff" then return true end
    -- healthTint left the engine path: its Lua aura cache freezes whenever
    -- ShouldAurasBeSecret (instanced combat), so presence now comes from a
    -- secure feeder slot (see FeederRendersElement + aura_slots feeder wiring).
    if mode == "tracked" and element.displayType == "border" then return true end
    return false
end
QUI_GFA.EngineRendersElement = EngineRendersElement

-- Tracked displays whose presence signal is a hidden secure aura slot
-- (OnShow/OnHide relay) instead of the Lua aura cache.
local function FeederRendersElement(element)
    return element ~= nil and element.mode == "tracked" and element.displayType == "healthTint"
end
QUI_GFA.FeederRendersElement = FeederRendersElement

-- Feeder attach/detach: parent the tint overlay into the secure slot so the
-- engine's (possibly secret) show/hide of the slot renders or hides the tint
-- without Lua ever observing aura presence.
local function OnFeederAttach(slotFrame, element)
    local container = slotFrame and slotFrame:GetParent()
    local host = container and container:GetParent()
    if not host or not element then return end
    local Render = GetRender()
    if Render and Render.AttachFeederTint then
        Render:AttachFeederTint(host, slotFrame, element)
    end
end

local function OnFeederDetach(slotFrame, element)
    local Render = GetRender()
    if Render and Render.DetachFeederTint then
        Render:DetachFeederTint(slotFrame, element)
    end
end
ns.AuraFeederAttach = OnFeederAttach
ns.AuraFeederDetach = OnFeederDetach

function QUI_GFA.ProfileOverrides(auras, gfdb, surfaceKey, dispelColorCurve)
    gfdb = gfdb or GetDB()
    return {
        showDispelBorder = auras and auras.debuffBorderByType == true,
        dispelColorCurve = dispelColorCurve,
        externalSkinning = gfdb and gfdb.externalSkinning == true,
        iconSkin = (gfdb and gfdb.iconSkin) or "Default",
        externalSkinKey = surfaceKey or "groupauras",
    }
end

local function BuildElementRenderList(auras, specID, cache, frame)
    local work = {}
    if not auras then return work end
    if AuraModel.EnsureSeeded then AuraModel.EnsureSeeded(auras, BucketFnFor(frame)) end
    if auras.enabled == false then return work end
    local elements = AuraModel.ActiveElementsForSpec(auras, specID)
    for _, element in ipairs(elements) do
        if EngineRendersElement(element) then
            local matches
            if element.mode == "tracked" then
                matches = AuraModel.PopulateElementMatches(element, cache)
            end
            work[#work + 1] = { element = element, matches = matches }
        end
    end
    return work
end
QUI_GFA.BuildElementRenderList = BuildElementRenderList

local unitAuraCache = {}
local auraStats
local function SetupDebugInstrumentation()
    auraStats = {
        fullScans = 0,
        slotScans = 0,
        legacyScans = 0,
        deltaApplied = 0,
        deltaFallback = 0,
        fastUpdates = 0,
        fullUpdateEvents = 0,
        deltaAddedAuras = 0,
        deltaRemovedAuras = 0,
        deltaUpdatedIDs = 0,
        deltaUpdatedSkipped = 0,
        deltaFreshFetches = 0,
        deltaMixedDeltas = 0,
        mixedIconRefreshes = 0,
        panelBuffRebuilds = 0,
        panelDebuffRebuilds = 0,
        panelBuffIncrementalAttempts = 0,
        panelBuffIncremental = 0,
        panelBuffIncrementalDirtySkip = 0,
        panelBuffIncrementalFilterSkip = 0,
        panelBuffIncrementalChanged = 0,
        panelBuffIncrementalNoop = 0,
        curatedMatchRefreshes = 0,
        indicatorMatchChanges = 0,
        pinnedMatchChanges = 0,
        indicatorFrameRefreshes = 0,
        indicatorFrameSkips = 0,
        pinnedFrameRefreshes = 0,
        pinnedFrameSkips = 0,
        panelFrameRefreshes = 0,
        panelFrameSkips = 0,
        panelFrameDisplaySkips = 0,
        panelNoDisplay = 0,
        panelIconUpdates = 0,
        panelIconSkips = 0,
        noConsumerSkips = 0,
        framesRefreshed = 0,
        heavyDeferred = 0,
        drainProcessed = 0,
        frameSkips = 0,
        elementSkips = 0,
        elementsDispatched = 0,
    }
    local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "GF_unitAuraCache", tbl = unitAuraCache }
    mp[#mp + 1] = { name = "GF_auraFullScans", fn = function() return auraStats.fullScans end, counter = true }
    mp[#mp + 1] = { name = "GF_auraSlotScans", fn = function() return auraStats.slotScans end, counter = true }
    mp[#mp + 1] = { name = "GF_auraLegacyScans", fn = function() return auraStats.legacyScans end, counter = true }
    mp[#mp + 1] = { name = "GF_auraDeltaApplied", fn = function() return auraStats.deltaApplied end, counter = true }
    mp[#mp + 1] = { name = "GF_auraDeltaFallback", fn = function() return auraStats.deltaFallback end, counter = true }
    mp[#mp + 1] = { name = "GF_auraFastUpdates", fn = function() return auraStats.fastUpdates end, counter = true }
    mp[#mp + 1] = { name = "GF_auraFullUpdateEvents", fn = function() return auraStats.fullUpdateEvents end, counter = true }
    mp[#mp + 1] = { name = "GF_auraDeltaAdded", fn = function() return auraStats.deltaAddedAuras end, counter = true }
    mp[#mp + 1] = { name = "GF_auraDeltaRemoved", fn = function() return auraStats.deltaRemovedAuras end, counter = true }
    mp[#mp + 1] = { name = "GF_auraDeltaUpdated", fn = function() return auraStats.deltaUpdatedIDs end, counter = true }
    mp[#mp + 1] = { name = "GF_auraDeltaUpdatedSkipped", fn = function() return auraStats.deltaUpdatedSkipped end, counter = true }
    mp[#mp + 1] = { name = "GF_auraFreshFetches", fn = function() return auraStats.deltaFreshFetches end, counter = true }
    mp[#mp + 1] = { name = "GF_auraMixedDeltas", fn = function() return auraStats.deltaMixedDeltas end, counter = true }
    mp[#mp + 1] = { name = "GF_auraMixedIconRefreshes", fn = function() return auraStats.mixedIconRefreshes end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPanelBuffRebuilds", fn = function() return auraStats.panelBuffRebuilds end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPanelDebuffRebuilds", fn = function() return auraStats.panelDebuffRebuilds end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPanelBuffIncAttempts", fn = function() return auraStats.panelBuffIncrementalAttempts end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPanelBuffIncremental", fn = function() return auraStats.panelBuffIncremental end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPanelBuffIncDirtySkip", fn = function() return auraStats.panelBuffIncrementalDirtySkip end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPanelBuffIncFilterSkip", fn = function() return auraStats.panelBuffIncrementalFilterSkip end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPanelBuffChanges", fn = function() return auraStats.panelBuffIncrementalChanged end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPanelBuffNoops", fn = function() return auraStats.panelBuffIncrementalNoop end, counter = true }
    mp[#mp + 1] = { name = "GF_auraCuratedRefreshes", fn = function() return auraStats.curatedMatchRefreshes end, counter = true }
    mp[#mp + 1] = { name = "GF_auraIndicatorMatchChanges", fn = function() return auraStats.indicatorMatchChanges end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPinnedMatchChanges", fn = function() return auraStats.pinnedMatchChanges end, counter = true }
    mp[#mp + 1] = { name = "GF_auraIndicatorRefreshes", fn = function() return auraStats.indicatorFrameRefreshes end, counter = true }
    mp[#mp + 1] = { name = "GF_auraIndicatorRefreshSkips", fn = function() return auraStats.indicatorFrameSkips end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPinnedRefreshes", fn = function() return auraStats.pinnedFrameRefreshes end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPinnedRefreshSkips", fn = function() return auraStats.pinnedFrameSkips end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPanelRefreshes", fn = function() return auraStats.panelFrameRefreshes end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPanelRefreshSkips", fn = function() return auraStats.panelFrameSkips end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPanelDisplaySkips", fn = function() return auraStats.panelFrameDisplaySkips end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPanelNoDisplay", fn = function() return auraStats.panelNoDisplay end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPanelIconUpdates", fn = function() return auraStats.panelIconUpdates end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPanelIconSkips", fn = function() return auraStats.panelIconSkips end, counter = true }
    mp[#mp + 1] = { name = "GF_auraNoConsumerSkips", fn = function() return auraStats.noConsumerSkips end, counter = true }
    mp[#mp + 1] = { name = "GF_auraFramesRefreshed", fn = function() return auraStats.framesRefreshed end, counter = true }
    mp[#mp + 1] = { name = "GF_auraHeavyDeferred", fn = function() return auraStats.heavyDeferred end, counter = true }
    mp[#mp + 1] = { name = "GF_auraDrainProcessed", fn = function() return auraStats.drainProcessed end, counter = true }
    mp[#mp + 1] = { name = "GF_auraFrameSkips", fn = function() return auraStats.frameSkips end, counter = true }
    mp[#mp + 1] = { name = "GF_auraElementSkips", fn = function() return auraStats.elementSkips end, counter = true }
    mp[#mp + 1] = { name = "GF_auraElementsDispatched", fn = function() return auraStats.elementsDispatched end, counter = true }
    QUI_GFA.auraStats = auraStats
end
if ns.DebugRegister then
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation()
end

local DISPEL_FILTER = "HARMFUL|RAID"
local MAX_SCAN_AURAS = 40

local IsAuraFilteredOut = C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID
local GetAuraSlots = C_UnitAuras and C_UnitAuras.GetAuraSlots
local GetAuraDataBySlot = C_UnitAuras and C_UnitAuras.GetAuraDataBySlot

local C_Secrets = C_Secrets
local function AurasAreSecret()
    return C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()
end

local function ClassifyDispellable(unit, instID)
    if not instID or IsSecretValue(instID) then return nil end
    if not IsAuraFilteredOut then return nil end
    local filteredOut = IsAuraFilteredOut(unit, instID, DISPEL_FILTER) -- @secret-safe: caller-gated: ClassifyDispellable runs only from the full-scan (703) / delta (766) paths behind AurasAreSecret
    if filteredOut == nil or IsSecretValue(filteredOut) then return nil end
    return filteredOut == false
end

local function CreateAuraCacheEntry()
    return {
        buffs = {},
        debuffs = {},
        buffsByID = {},
        debuffsByID = {},
        buffsIndexByID = {},
        debuffsIndexByID = {},
        buffsBySpellID = {},
        debuffsBySpellID = {},
        buffsByName = {},
        debuffsByName = {},
        playerDispellable = {},
        playerDispellableOrder = {},
        allDispellable = {},
        typedDebuffs = {},
        typedDebuffOrder = {},
        hasFullScan = false,
    }
end

local function EnsureAuraCache(unit)
    local cache = unitAuraCache[unit]
    if cache then
        return cache
    end
    cache = CreateAuraCacheEntry()
    unitAuraCache[unit] = cache
    return cache
end

local function ResetAuraCache(cache)
    wipe(cache.buffs)
    wipe(cache.debuffs)
    wipe(cache.buffsByID)
    wipe(cache.debuffsByID)
    wipe(cache.buffsIndexByID)
    wipe(cache.debuffsIndexByID)
    wipe(cache.buffsBySpellID)
    wipe(cache.debuffsBySpellID)
    wipe(cache.buffsByName)
    wipe(cache.debuffsByName)
    wipe(cache.playerDispellable)
    wipe(cache.playerDispellableOrder)
    wipe(cache.allDispellable)
    wipe(cache.typedDebuffs)
    wipe(cache.typedDebuffOrder)
    cache.hasFullScan = false
end

local function RebuildBuffMaps(_unit, cache)
    wipe(cache.buffsByID)
    wipe(cache.buffsIndexByID)
    wipe(cache.buffsBySpellID)
    wipe(cache.buffsByName)

    local buffs = cache.buffs
    local buffsByID = cache.buffsByID
    local buffsIndexByID = cache.buffsIndexByID
    local buffsBySpellID = cache.buffsBySpellID
    local buffsByName = cache.buffsByName

    for i = 1, #buffs do
        local auraData = buffs[i]
        if IsSecretValue(auraData) then
            -- @secret-policy: reject-secret-value
            auraData = nil
        end
        local instID = auraData and auraData.auraInstanceID
        if IsSecretValue(instID) then
            -- @secret-policy: reject-secret-ids
            instID = nil
        end
        if instID then
            buffsByID[instID] = auraData
            buffsIndexByID[instID] = i
        end

        local spellID = SafeValue(auraData and auraData.spellId, nil)
        if spellID then
            buffsBySpellID[spellID] = auraData
        end

        local spellName = SafeValue(auraData and auraData.name, nil)
        if spellName then
            buffsByName[spellName] = auraData
        end
    end
end

-- >>> QUI_TEST_EXTRACT RebuildDebuffMaps
local function RebuildDebuffMaps(unit, cache)
    wipe(cache.debuffsByID)
    wipe(cache.debuffsIndexByID)
    wipe(cache.debuffsBySpellID)
    wipe(cache.debuffsByName)
    wipe(cache.playerDispellable)
    wipe(cache.playerDispellableOrder)
    wipe(cache.allDispellable)
    wipe(cache.typedDebuffs)
    wipe(cache.typedDebuffOrder)

    local debuffs = cache.debuffs
    local debuffsByID = cache.debuffsByID
    local debuffsIndexByID = cache.debuffsIndexByID
    local debuffsBySpellID = cache.debuffsBySpellID
    local debuffsByName = cache.debuffsByName
    local playerDispellable = cache.playerDispellable
    local playerDispellableOrder = cache.playerDispellableOrder
    local allDispellable = cache.allDispellable
    local typedDebuffs = cache.typedDebuffs
    local typedDebuffOrder = cache.typedDebuffOrder

    for i = 1, #debuffs do
        local auraData = debuffs[i]
        if IsSecretValue(auraData) then
            -- @secret-policy: reject-secret-value — an opaque AuraData entry
            auraData = nil
        end
        local instID = auraData and auraData.auraInstanceID
        if IsSecretValue(instID) then
            -- @secret-policy: reject-secret-ids — cannot key maps on an
            instID = nil
        end
        if instID then
            debuffsByID[instID] = auraData
            debuffsIndexByID[instID] = i

            local dispelName = auraData.dispelName
            local hasDispelType = false
            if IsSecretValue(dispelName) then
                -- @secret-policy: reject-secret-value — a secret dispel type
                hasDispelType = false
            elseif dispelName ~= nil then
                hasDispelType = true
            end
            if hasDispelType then
                allDispellable[instID] = true
            end

            local dispelEnum = auraData.dispelType
            if IsSecretValue(dispelEnum) then
                -- @secret-policy: reject-secret-value — never compare an
                dispelEnum = nil
            end
            local classified = ClassifyDispellable(unit, instID)
            local hasTypedEnum = dispelEnum == 1 or dispelEnum == 2
                or dispelEnum == 3 or dispelEnum == 4
                or dispelEnum == 9 or dispelEnum == 11
            if hasDispelType or hasTypedEnum or classified == true then
                typedDebuffs[instID] = true
                typedDebuffOrder[#typedDebuffOrder + 1] = instID
            end
            if classified == true or (classified == nil and hasDispelType) then
                playerDispellable[instID] = true
                playerDispellableOrder[#playerDispellableOrder + 1] = instID
            end
        end

        local spellID = SafeValue(auraData and auraData.spellId, nil)
        if spellID then
            debuffsBySpellID[spellID] = auraData
        end

        local spellName = SafeValue(auraData and auraData.name, nil)
        if spellName then
            debuffsByName[spellName] = auraData
        end
    end
end
-- <<< QUI_TEST_EXTRACT RebuildDebuffMaps

local function ResolveAuraBucket(unit, auraData)
    if not auraData then return nil end

    local instID = auraData.auraInstanceID
    if instID and IsAuraFilteredOut then
        local buffFiltered = IsAuraFilteredOut(unit, instID, "HELPFUL") -- @secret-safe: caller-gated: ResolveAuraBucket runs only from the delta path behind the 766 AurasAreSecret gate
        if buffFiltered ~= nil and not IsSecretValue(buffFiltered) then
            if buffFiltered == false then
                return "buffs"
            end
            local debuffFiltered = IsAuraFilteredOut(unit, instID, "HARMFUL") -- @secret-safe: caller-gated: same delta-path AurasAreSecret gate as the HELPFUL probe above
            if debuffFiltered ~= nil and not IsSecretValue(debuffFiltered) then
                if debuffFiltered == false then
                    return "debuffs"
                end
            end
        end
    end

    local isHelpful = SafeValue(auraData.isHelpful, nil)
    if isHelpful == true then
        return "buffs"
    end

    local isHarmful = SafeValue(auraData.isHarmful, nil)
    if isHarmful == true then
        return "debuffs"
    end

    return nil
end

local function RefreshSpellIDLookupAfterRemoval(bucket, lookup, spellID)
    if not spellID or not lookup then return end
    lookup[spellID] = nil
    for i = 1, #bucket do
        local auraData = bucket[i]
        if SafeValue(auraData and auraData.spellId, nil) == spellID then
            lookup[spellID] = auraData
        end
    end
end

local function RefreshSpellNameLookupAfterRemoval(bucket, lookup, spellName)
    if not spellName or not lookup then return end
    lookup[spellName] = nil
    for i = 1, #bucket do
        local auraData = bucket[i]
        if SafeValue(auraData and auraData.name, nil) == spellName then
            lookup[spellName] = auraData
        end
    end
end

local function RemoveIDFromOrder(order, instID)
    if not order then return end
    for i = 1, #order do
        if order[i] == instID then
            table_remove(order, i)
            return
        end
    end
end

local function AddBuffDerivedData(_unit, cache, auraData)
    if IsSecretValue(auraData) then
        -- @secret-policy: reject-secret-value
        auraData = nil
    end
    local instID = auraData and auraData.auraInstanceID
    if IsSecretValue(instID) then
        -- @secret-policy: reject-secret-ids
        instID = nil
    end
    if not instID then return end

    local spellID = SafeValue(auraData.spellId, nil)
    if spellID then
        cache.buffsBySpellID[spellID] = auraData
    end

    local spellName = SafeValue(auraData.name, nil)
    if spellName then
        cache.buffsByName[spellName] = auraData
    end
end

local function RemoveBuffDerivedData(cache, auraData, instID)
    if not auraData or not instID then return end

    local spellID = SafeValue(auraData.spellId, nil)
    if spellID and cache.buffsBySpellID[spellID] == auraData then
        RefreshSpellIDLookupAfterRemoval(cache.buffs, cache.buffsBySpellID, spellID)
    end

    local spellName = SafeValue(auraData.name, nil)
    if spellName and cache.buffsByName[spellName] == auraData then
        RefreshSpellNameLookupAfterRemoval(cache.buffs, cache.buffsByName, spellName)
    end
end

local function AddDebuffDerivedData(unit, cache, auraData)
    if IsSecretValue(auraData) then
        -- @secret-policy: reject-secret-value — opaque AuraData carries no
        auraData = nil
    end
    local instID = auraData and auraData.auraInstanceID
    if IsSecretValue(instID) then
        -- @secret-policy: reject-secret-ids
        instID = nil
    end
    if not instID then return end

    local dispelName = auraData.dispelName
    local hasDispelType = false
    if IsSecretValue(dispelName) then
        -- @secret-policy: reject-secret-value — secret dispel type is
        hasDispelType = false
    elseif dispelName ~= nil then
        hasDispelType = true
    end
    if hasDispelType then
        cache.allDispellable[instID] = true
    end

    local dispelEnum = auraData.dispelType
    if IsSecretValue(dispelEnum) then
        -- @secret-policy: reject-secret-value
        dispelEnum = nil
    end
    local classified = ClassifyDispellable(unit, instID)
    local hasTypedEnum = dispelEnum == 1 or dispelEnum == 2
        or dispelEnum == 3 or dispelEnum == 4
        or dispelEnum == 9 or dispelEnum == 11
    if hasDispelType or hasTypedEnum or classified == true then
        if not cache.typedDebuffs[instID] then
            cache.typedDebuffOrder[#cache.typedDebuffOrder + 1] = instID
        end
        cache.typedDebuffs[instID] = true
    end
    if classified == true or (classified == nil and hasDispelType) then
        if not cache.playerDispellable[instID] then
            cache.playerDispellableOrder[#cache.playerDispellableOrder + 1] = instID
        end
        cache.playerDispellable[instID] = true
    end

    local spellID = SafeValue(auraData.spellId, nil)
    if spellID then
        cache.debuffsBySpellID[spellID] = auraData
    end

    local spellName = SafeValue(auraData.name, nil)
    if spellName then
        cache.debuffsByName[spellName] = auraData
    end
end

local function RemoveDebuffDerivedData(cache, auraData, instID)
    if not auraData or not instID then return end

    local spellID = SafeValue(auraData.spellId, nil)
    if spellID and cache.debuffsBySpellID[spellID] == auraData then
        RefreshSpellIDLookupAfterRemoval(cache.debuffs, cache.debuffsBySpellID, spellID)
    end

    local spellName = SafeValue(auraData.name, nil)
    if spellName and cache.debuffsByName[spellName] == auraData then
        RefreshSpellNameLookupAfterRemoval(cache.debuffs, cache.debuffsByName, spellName)
    end

    cache.playerDispellable[instID] = nil
    cache.allDispellable[instID] = nil
    cache.typedDebuffs[instID] = nil
    RemoveIDFromOrder(cache.playerDispellableOrder, instID)
    RemoveIDFromOrder(cache.typedDebuffOrder, instID)
end

local function AppendAuraToBucket(unit, cache, bucketName, auraData)
    local bucket = bucketName == "buffs" and cache.buffs or cache.debuffs
    local byID = bucketName == "buffs" and cache.buffsByID or cache.debuffsByID
    local indexByID = bucketName == "buffs" and cache.buffsIndexByID or cache.debuffsIndexByID
    local instID = auraData and auraData.auraInstanceID

    if instID and byID[instID] then
        local idx = indexByID[instID]
        if idx then bucket[idx] = auraData end
        byID[instID] = auraData
        return
    end

    bucket[#bucket + 1] = auraData
    if not instID then
        return
    end

    if bucketName == "buffs" then
        cache.buffsByID[instID] = auraData
        cache.buffsIndexByID[instID] = #bucket
        AddBuffDerivedData(unit, cache, auraData)
    else
        cache.debuffsByID[instID] = auraData
        cache.debuffsIndexByID[instID] = #bucket
        AddDebuffDerivedData(unit, cache, auraData)
    end
end

local function RemoveAuraFromBucket(cache, bucketName, instID)
    local bucket, indexMap, byInstanceID
    if bucketName == "buffs" then
        bucket = cache.buffs
        indexMap = cache.buffsIndexByID
        byInstanceID = cache.buffsByID
    else
        bucket = cache.debuffs
        indexMap = cache.debuffsIndexByID
        byInstanceID = cache.debuffsByID
    end

    local idx = indexMap[instID]
    if not idx then
        return false
    end

    local oldAura = byInstanceID[instID]
    table_remove(bucket, idx)
    indexMap[instID] = nil
    byInstanceID[instID] = nil

    for i = idx, #bucket do
        local auraData = bucket[i]
        local auraInstID = auraData and auraData.auraInstanceID
        if auraInstID then
            indexMap[auraInstID] = i
        end
    end

    if bucketName == "buffs" then
        RemoveBuffDerivedData(cache, oldAura, instID)
    else
        RemoveDebuffDerivedData(cache, oldAura, instID)
    end

    return true
end

local function ReplaceAuraInBucket(_unit, cache, bucketName, instID, auraData)
    local bucket, indexMap, byInstanceID, bySpellID, byName
    if bucketName == "buffs" then
        bucket = cache.buffs
        indexMap = cache.buffsIndexByID
        byInstanceID = cache.buffsByID
        bySpellID = cache.buffsBySpellID
        byName = cache.buffsByName
    else
        bucket = cache.debuffs
        indexMap = cache.debuffsIndexByID
        byInstanceID = cache.debuffsByID
        bySpellID = cache.debuffsBySpellID
        byName = cache.debuffsByName
    end

    local idx = indexMap[instID]
    if not idx then
        return false
    end

    local old = bucket[idx]
    if old then
        local oldSpell = SafeValue(old.spellId, nil)
        if oldSpell and bySpellID[oldSpell] == old then bySpellID[oldSpell] = nil end
        local oldName = SafeValue(old.name, nil)
        if oldName and byName[oldName] == old then byName[oldName] = nil end
    end

    bucket[idx] = auraData
    byInstanceID[instID] = auraData
    local newSpell = SafeValue(auraData.spellId, nil)
    if newSpell then bySpellID[newSpell] = auraData end
    local newName = SafeValue(auraData.name, nil)
    if newName then byName[newName] = auraData end

    return true
end

local function AppendSlotAuras(unit, dst, ...)
    local n = select("#", ...)
    for i = 2, n do
        local slot = select(i, ...)
        if slot then
            local auraData = GetAuraDataBySlot(unit, slot) -- @secret-safe: caller-gated: AppendSlotAuras is only reached via ScanUnitAuras, which bails at its AurasAreSecret gate
            if IsSecretValue(auraData) then
                -- @secret-policy: reject-secret-value — opaque entries can't
                auraData = nil
            end
            local instID = auraData and auraData.auraInstanceID
            if IsSecretValue(instID) then
                -- @secret-policy: reject-secret-ids
                instID = nil
            end
            if instID then
                dst[#dst + 1] = auraData
            end
        end
    end
    local token
    if n >= 1 then
        token = select(1, ...)
    end
    if IsSecretValue(token) then
        -- @secret-policy: reject-secret-value — an unreadable continuation
        token = nil
    end
    return token
end

local function ScanSlotFilter(unit, dst, filter)
    local token
    repeat
        token = AppendSlotAuras(unit, dst, GetAuraSlots(unit, filter, MAX_SCAN_AURAS, token)) -- @secret-safe: caller-gated: ScanSlotFilter is only reached via ScanUnitAuras, which bails at its AurasAreSecret gate
    until token == nil
end

local function ScanUnitAurasBySlot(unit, cache)
    if not GetAuraSlots or not GetAuraDataBySlot then
        return false
    end

    ScanSlotFilter(unit, cache.debuffs, "HARMFUL")
    ScanSlotFilter(unit, cache.buffs, "HELPFUL")
    return true
end

local function CopyReadableAuras(src, dst)
    local n = 0
    for i = 1, #src do
        local auraData = src[i]
        if IsSecretValue(auraData) then
            -- @secret-policy: reject-secret-value — opaque entries are
            auraData = nil
        end
        if auraData ~= nil then
            local instID = auraData.auraInstanceID
            if IsSecretValue(instID) then
                -- @secret-policy: reject-secret-ids — GetUnitAuras' return
                auraData = nil
            end
        end
        if auraData ~= nil then
            n = n + 1
            dst[n] = auraData
        end
    end
end

local function ScanUnitAurasLegacy(unit, cache)
    local GetUnitAuras = C_UnitAuras and C_UnitAuras.GetUnitAuras
    if not GetUnitAuras then return false end

    local debuffs = GetUnitAuras(unit, "HARMFUL") -- @secret-safe: caller-gated: ScanUnitAurasLegacy is only reached via ScanUnitAuras, which bails at its AurasAreSecret gate
    if debuffs then
        CopyReadableAuras(debuffs, cache.debuffs)
    end

    local buffs = GetUnitAuras(unit, "HELPFUL") -- @secret-safe: caller-gated: same ScanUnitAuras AurasAreSecret gate as the HARMFUL scan above
    if buffs then
        CopyReadableAuras(buffs, cache.buffs)
    end
    return true
end

local function ScanUnitAuras(unit)
    local cache = EnsureAuraCache(unit)
    if AurasAreSecret() then
        return cache
    end
    ResetAuraCache(cache)

    if auraStats then auraStats.fullScans = auraStats.fullScans + 1 end
    if ScanUnitAurasBySlot(unit, cache) then
        if auraStats then auraStats.slotScans = auraStats.slotScans + 1 end
    elseif ScanUnitAurasLegacy(unit, cache) then
        if auraStats then auraStats.legacyScans = auraStats.legacyScans + 1 end
    else
        return cache
    end

    RebuildDebuffMaps(unit, cache)
    RebuildBuffMaps(unit, cache)
    cache.hasFullScan = true
    return cache
end

local _deltaSummary = { helpful = false, harmful = false,
                        spellsUncertain = false, spells = {} }
local function ResetDeltaSummary()
    _deltaSummary.helpful = false
    _deltaSummary.harmful = false
    _deltaSummary.spellsUncertain = false
    wipe(_deltaSummary.spells)
end
local function SummaryAddSpell(auraData)
    if not auraData then _deltaSummary.spellsUncertain = true; return end
    local sid = SafeValue(auraData.spellId, nil)
    if sid then
        _deltaSummary.spells[sid] = true
    else
        _deltaSummary.spellsUncertain = true
    end
end

local function ApplyAuraDelta(unit, updateInfo)
    local cache = unitAuraCache[unit]
    if not cache or not cache.hasFullScan or type(updateInfo) ~= "table" then
        return false
    end

    if AurasAreSecret() then
        return false
    end

    ResetDeltaSummary()
    local buffsDirty = false
    local debuffsDirty = false
    local GetAuraByInstanceID = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
    local nAdded = updateInfo.addedAuras and #updateInfo.addedAuras or 0
    local nRemoved = updateInfo.removedAuraInstanceIDs and #updateInfo.removedAuraInstanceIDs or 0
    local nUpdated = updateInfo.updatedAuraInstanceIDs and #updateInfo.updatedAuraInstanceIDs or 0

    if auraStats then
        auraStats.deltaAddedAuras = auraStats.deltaAddedAuras + nAdded
        auraStats.deltaRemovedAuras = auraStats.deltaRemovedAuras + nRemoved
        auraStats.deltaUpdatedIDs = auraStats.deltaUpdatedIDs + nUpdated
        if nUpdated > 0 and (nAdded > 0 or nRemoved > 0) then
            auraStats.deltaMixedDeltas = auraStats.deltaMixedDeltas + 1
        end
    end
    local skipUpdatedFetches = nUpdated > 0
        and (nAdded > 0 or nRemoved > 0)
        and C_UnitAuras
        and C_UnitAuras.GetAuraDuration

    if updateInfo.addedAuras then
        for i = 1, #updateInfo.addedAuras do
            local auraData = updateInfo.addedAuras[i]
            local bucketName = ResolveAuraBucket(unit, auraData)
            if not bucketName then
                return false
            end
            AppendAuraToBucket(unit, cache, bucketName, auraData)
            SummaryAddSpell(auraData)
            if bucketName == "buffs" then
                buffsDirty = true
            else
                debuffsDirty = true
            end
        end
    end

    if updateInfo.updatedAuraInstanceIDs and #updateInfo.updatedAuraInstanceIDs > 0 then
        if skipUpdatedFetches then
            if auraStats then auraStats.deltaUpdatedSkipped = auraStats.deltaUpdatedSkipped + nUpdated end
            _deltaSummary.spellsUncertain = true
        else
            if not GetAuraByInstanceID then
                return false
            end

            for i = 1, #updateInfo.updatedAuraInstanceIDs do
                local instID = updateInfo.updatedAuraInstanceIDs[i]
                local bucketName = nil
                if cache.buffsByID[instID] then
                    bucketName = "buffs"
                elseif cache.debuffsByID[instID] then
                    bucketName = "debuffs"
                end

                if bucketName then
                    if auraStats then auraStats.deltaFreshFetches = auraStats.deltaFreshFetches + 1 end
                    local freshAura = GetAuraByInstanceID(unit, instID)
                    if IsSecretValue(freshAura) then
                        -- @secret-policy: reject-secret-value
                        return false
                    end
                    if not freshAura then
                        return false
                    end
                    local replaced = ReplaceAuraInBucket(unit, cache, bucketName, instID, freshAura)
                    if not replaced then
                        return false
                    end
                    SummaryAddSpell(freshAura)
                    if bucketName == "buffs" then
                        buffsDirty = true
                    else
                        debuffsDirty = true
                    end
                else
                    _deltaSummary.spellsUncertain = true
                end
            end
        end
    end

    if updateInfo.removedAuraInstanceIDs then
        for i = 1, #updateInfo.removedAuraInstanceIDs do
            local instID = updateInfo.removedAuraInstanceIDs[i]
            local rb = cache.buffsByID[instID]
            if rb then
                local removed = RemoveAuraFromBucket(cache, "buffs", instID)
                if removed then
                    buffsDirty = true
                    SummaryAddSpell(rb)
                end
            end
            local rd = cache.debuffsByID[instID]
            if rd and RemoveAuraFromBucket(cache, "debuffs", instID) then
                debuffsDirty = true
                SummaryAddSpell(rd)
            end
            if not rb and not rd then
                _deltaSummary.spellsUncertain = true
            end
        end
    end

    _deltaSummary.helpful = buffsDirty
    _deltaSummary.harmful = debuffsDirty
    return true
end

local function PruneAuraCache()
    local GF = ns.QUI_GroupFrames
    if not GF or not GF.unitFrameMap then return end
    for unit in pairs(unitAuraCache) do
        if not GF.unitFrameMap[unit] then
            unitAuraCache[unit] = nil
        end
    end
end

QUI_GFA.unitAuraCache = unitAuraCache
QUI_GFA.ScanUnitAuras = ScanUnitAuras
QUI_GFA.ApplyAuraDelta = ApplyAuraDelta
QUI_GFA.PruneAuraCache = PruneAuraCache

local GetFrameAuraSettings
local _renderCurrentIDs = {}

local function GetPlayerSpecID()
    local cached = QUI_GFA._cachedSpecID
    if cached ~= nil then
        return cached or nil
    end
    local specIndex = GetSpecialization and GetSpecialization()
    if specIndex and GetSpecializationInfo then
        cached = (GetSpecializationInfo(specIndex)) or false
    else
        cached = false
    end
    QUI_GFA._cachedSpecID = cached
    return cached or nil
end

do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_ENTERING_WORLD" or unit == "player" then
            QUI_GFA._cachedSpecID = nil
        end
    end)
end

local _activeElementsScratch = {}
local _trackedMatchesScratch = {}
local _missingRaidBuffMatchesScratch = {}

local function FrameRoleGate(frame)
    local unit = GetFrameUnit(frame)
    if not unit then return nil, false end
    -- @secret-policy: collapse-only — unreadable role = no role gate
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
    if IsSecretValue(role) then role = nil end
    if role == "NONE" then role = nil end
    local isSelf = false
    if UnitIsUnit then
        local raw = UnitIsUnit(unit, "player")
        if IsSecretValue(raw) then raw = nil end
        isSelf = raw == true
    end
    return role, isSelf
end

local function ReleaseAllRenderedElements(frame, Render)
    local prev = frame._quiRenderedAuraElementIDs
    if prev then
        for id in pairs(prev) do
            Render:Release(frame, id)
            prev[id] = nil
        end
    end
    if frame._quiAuraRenderHealthTintOwner then
        Render:Release(frame, frame._quiAuraRenderHealthTintOwner)
    end
end

local _relGeneration = 0
QUI_GFA._configGeneration = 0
local _relCache = setmetatable({}, { __mode = "k" })
local function GetAuraRelevance(auras, specID)
    local rel = _relCache[auras]
    if rel and rel.gen == _relGeneration and rel.specID == specID then
        return rel
    end
    if not rel then
        rel = { trackedSpells = {} }
        _relCache[auras] = rel
    end
    rel.gen = _relGeneration
    rel.specID = specID
    rel.hasMissingRaidBuff = false
    rel.hasTracked = false
    wipe(rel.trackedSpells)
    local elements = AuraModel.ActiveElementsForSpec(auras, specID)
    for i = 1, #elements do
        local e = elements[i]
        if EngineRendersElement(e) then
            if e.mode == "missingRaidBuff" then
                rel.hasMissingRaidBuff = true
            elseif e.mode == "tracked" then
                rel.hasTracked = true
                local spells = e.spells
                if spells then
                    for j = 1, #spells do rel.trackedSpells[spells[j]] = true end
                end
            end
        end
    end
    return rel
end

local function DeltaTouchesFrame(rel, dirty)
    if (dirty.helpful or dirty.spellsUncertain) and rel.hasMissingRaidBuff then return true end
    if rel.hasTracked then
        if dirty.spellsUncertain then return true end
        for sid in pairs(dirty.spells) do
            if rel.trackedSpells[sid] then return true end
        end
    end
    return false
end

local function RenderFrameElements(frame, cache, dirty)
    if not frame then return end
    local unit = GetFrameUnit(frame)
    if not unit then return end
    local pf = ns.QUI_PerfFlags
    if pf and pf.disabled and pf.disabled.auras then return end
    local Render = GetRender()
    if not Render then return end

    local auras = GetFrameAuraSettings(frame)

    if not auras or auras.enabled == false then
        ReleaseAllRenderedElements(frame, Render)
        return
    end

    local specID = GetPlayerSpecID()
    if AuraModel.EnsureSeeded then AuraModel.EnsureSeeded(auras, BucketFnFor(frame)) end

    local rel = GetAuraRelevance(auras, specID)
    if dirty and not DeltaTouchesFrame(rel, dirty) then
        if auraStats then auraStats.frameSkips = auraStats.frameSkips + 1 end
        return
    end

    local elements = AuraModel.ActiveElementsForSpec(auras, specID, _activeElementsScratch)

    local rendered = frame._quiRenderedAuraElementIDs
    if not rendered then
        rendered = {}
        frame._quiRenderedAuraElementIDs = rendered
    end

    local current = _renderCurrentIDs
    wipe(current)
    local frameRole, frameIsSelf = FrameRoleGate(frame)
    local borderFamilyDirty, tintFamilyDirty = false, false
    if dirty then
        if dirty.spellsUncertain then
            borderFamilyDirty, tintFamilyDirty = true, true
        else
            for i = 1, #elements do
                local e = elements[i]
                if e.mode == "tracked"
                    and (e.displayType == "border" or e.displayType == "healthTint")
                    and type(e.spells) == "table" then
                    for j = 1, #e.spells do
                        if dirty.spells[e.spells[j]] then
                            if e.displayType == "border" then
                                borderFamilyDirty = true
                            else
                                tintFamilyDirty = true
                            end
                            break
                        end
                    end
                end
            end
        end
    end
    for i = 1, #elements do
        local element = elements[i]
        if EngineRendersElement(element)
            and AuraModel.ElementAppliesToRole(element, frameRole, frameIsSelf) then
            local elementDirty = (dirty == nil)
            if not elementDirty then
                if element.mode == "missingRaidBuff" then
                    elementDirty = dirty.helpful or dirty.spellsUncertain
                elseif element.mode == "tracked" then
                    if dirty.spellsUncertain then
                        elementDirty = true
                    elseif element.displayType == "border" then
                        elementDirty = borderFamilyDirty
                    elseif element.displayType == "healthTint" then
                        elementDirty = tintFamilyDirty
                    else
                        local spells = element.spells
                        if spells then
                            for j = 1, #spells do
                                if dirty.spells[spells[j]] then elementDirty = true; break end
                            end
                        end
                    end
                end
            end
            current[element.id] = true
            if elementDirty then
                if auraStats then auraStats.elementsDispatched = auraStats.elementsDispatched + 1 end
                local matches
                if element.mode == "missingRaidBuff" then
                    local MRB = ns.QUI_GroupFrameMissingRaidBuffs
                    if MRB and MRB.BuildMatches then
                        matches = MRB:BuildMatches(unit, element, _missingRaidBuffMatchesScratch)
                    end
                elseif element.mode == "tracked" then
                    matches = AuraModel.PopulateElementMatches(element, cache, _trackedMatchesScratch)
                end
                Render:Dispatch(frame, element, matches)
            elseif auraStats then
                auraStats.elementSkips = auraStats.elementSkips + 1
            end
        elseif FeederRendersElement(element)
            and AuraModel.ElementAppliesToRole(element, frameRole, frameIsSelf) then
            -- Feeder-driven tint: the overlay lives inside the secure slot and
            -- the engine renders it; nothing to dispatch here. Marking current
            -- keeps the tint-owner reap below away while the element is live.
            current[element.id] = true
        end
    end

    for id in pairs(rendered) do
        if not current[id] then
            Render:Release(frame, id)
        end
    end
    wipe(rendered)
    for id in pairs(current) do rendered[id] = true end
    local tintOwner = frame._quiAuraRenderHealthTintOwner
    if tintOwner and not current[tintOwner] then
        Render:Release(frame, tintOwner)
    end
    local borderOwner = frame._quiAuraRenderBorderOwner
    if borderOwner and not current[borderOwner] then
        Render:Release(frame, borderOwner)
    end
end
QUI_GFA.RenderFrameElements = RenderFrameElements

local function GetVisualDBForContext(isRaid)
    local db = GetDB()
    if not db then return nil end

    return (isRaid and db.raid or db.party) or db
end

local function GetVisualDBForFrame(frame)
    return GetVisualDBForContext(frame and frame._isRaid)
end

function GetFrameAuraSettings(frame)
    local vdb = GetVisualDBForFrame(frame)
    return vdb and vdb.auras or nil
end

local AuraSkin = (ns.Addon and ns.Addon.AuraSkin) or (_G.QUI and _G.QUI.AuraSkin)
local AuraGlue = ns.AuraGlue
local AuraSlots = ns.AuraSlots
local function ResolveAuraDeps()
    AuraSkin  = AuraSkin  or (ns.Addon and ns.Addon.AuraSkin) or (_G.QUI and _G.QUI.AuraSkin)
    AuraGlue  = AuraGlue  or ns.AuraGlue
    AuraSlots = AuraSlots or ns.AuraSlots
    return AuraSkin and AuraGlue and AuraSlots
end

local ApplyStripContainers

-- Blizzard's BIG_DEFENSIVE / EXTERNAL_DEFENSIVE filters fail open on
-- distance-obfuscated aura data: for out-of-range units the engine matches
-- arbitrary buffs, so classification strips show icons with nothing up
-- (pre-engine fix: PR #484). Lua cannot re-verify engine-rendered auras,
-- so fail closed instead: blank gated strips while the unit is out of range.
-- >>> QUI_TEST_EXTRACT range_gate
local function ElementNeedsRangeGate(element)
    if not element or element.mode ~= "filterStrip" then return false end
    if element.filterMode ~= "classify" then return false end
    local c = element.classifications
    return type(c) == "table"
        and (c.bigDefensive == true or c.externalDefensive == true)
end

function QUI_GFA.ApplyRangeGate(frame, inRange)
    local pool = frame and frame._quiAuraContainers
    if not pool then return end
    if not IsSecretValue(inRange) and inRange == nil then
        local GF = ns.QUI_GroupFrames
        local unit = GetFrameUnit(frame)
        if not (unit and GF and GF.CheckUnitRange) then return end
        inRange = GF.CheckUnitRange(unit)
    end
    for i = 1, #pool do
        local container = pool[i]
        if container and container._quiRangeGated then
            if container.SetAlphaFromBoolean then
                container:SetAlphaFromBoolean(inRange, 1, 0)
            elseif not IsSecretValue(inRange) then
                container:SetAlpha(inRange == false and 0 or 1)
            end
        end
    end
end
-- <<< QUI_TEST_EXTRACT range_gate

local function QueueContainerCombatWork(frame)
    AuraGlue = AuraGlue or ns.AuraGlue
    if not AuraGlue then return end
    AuraGlue.QueueRegenWork(frame, function(f)
        if ApplyStripContainers then ApplyStripContainers(f) end
    end)
end

local _activeElems = {}
local function ResolveContainerElements(frame)
    for i = #_activeElems, 1, -1 do _activeElems[i] = nil end
    local auras = GetFrameAuraSettings(frame)
    if not auras or auras.enabled == false then return _activeElems end
    AuraModel.EnsureSeeded(auras, BucketFnFor(frame))
    local specID = GetPlayerSpecID()
    local elements = AuraModel.ActiveElementsForSpec(auras, specID)
    local role, isSelf = FrameRoleGate(frame)
    for i = 1, #elements do
        local e = elements[i]
        if (e.mode == "filterStrip"
            or (e.mode == "tracked" and e.displayType ~= "border"))
            and AuraModel.ElementAppliesToRole(e, role, isSelf) then
            _activeElems[#_activeElems + 1] = e
        end
    end
    return _activeElems
end

local function AnchorElementContainer(container, frame, element)
    local profile = AuraGlue.ElementProfile(element)
    container:ClearAllPoints()
    container:SetPoint(AuraSkin.LayoutAnchor(profile), frame, element.anchor or "TOPLEFT",
        (element.offsetX or 0), (element.offsetY or 0))
end

local function ApplyElementPass(frame, allowCreate)
    if not frame then return end
    local unit = GetFrameUnit(frame)
    if not unit then return end
    if not ResolveAuraDeps() then return end
    local AuraSurface = ns.AuraSurface
    if not AuraSurface then return end

    local auras = GetFrameAuraSettings(frame)
    local curve = ns.QUI_GroupFrameAuraBorderCurve
        and ns.QUI_GroupFrameAuraBorderCurve(frame._isRaid) or nil
    local profileOverrides = QUI_GFA.ProfileOverrides(auras, GetDB(), "groupauras", curve)
    local elems = ResolveContainerElements(frame)

    AuraSurface.ApplyElementPass(frame, elems, {
        unit = unit,
        allowCreate = allowCreate == true,
        cancelEligible = false,
        profileOverrides = profileOverrides,
        profileFor = function(element)
            return AuraGlue.ElementProfile(element, profileOverrides)
        end,
        anchorContainer = function(container, host, element)
            local gated = ElementNeedsRangeGate(element)
            if container._quiRangeGated and not gated then
                container:SetAlpha(1)
            end
            container._quiRangeGated = gated
            AnchorElementContainer(container, host, element)
        end,
        onContainerReady = function(container, host)
            local desiredLevel = host:GetFrameLevel() + CHROME_LEVELS.AURA_HOST
            if not InCombatLockdown() then
                container:SetFrameLevel(desiredLevel)
                return true
            end
            return container:GetFrameLevel() == desiredLevel
        end,
        onIncomplete = QueueContainerCombatWork,
    })
    QUI_GFA.ApplyRangeGate(frame)
end

function ApplyStripContainers(frame)
    ApplyElementPass(frame, true)
end
QUI_GFA.ApplyStripContainers = ApplyStripContainers

local function UpdateStripContainers(frame)
    if not frame or not GetFrameUnit(frame) then return end
    if InCombatLockdown() then
        local ok = ns.SafeCall("best-effort-style", ApplyElementPass, frame, true)
        if not ok then
            QueueContainerCombatWork(frame)
        end
        return
    end
    ApplyElementPass(frame, true)
end
QUI_GFA.UpdateStripContainers = UpdateStripContainers

function QUI_GFA.TrackedAssistStale(frame)
    local pool = frame and frame._quiAuraContainers
    if not pool then return false end
    local AuraSlots = ns.AuraSlots
    if not (AuraSlots and AuraSlots.LiveAssistProbe) then return false end
    local live, probed
    for i = 1, #pool do
        local container = pool[i]
        local applied = container and container._quiAssistApplied
        if applied ~= nil then
            if not probed then
                probed = true
                live = AuraSlots.LiveAssistProbe(GetFrameUnit(frame)) == true
            end
            if live ~= applied then return true end
        end
    end
    return false
end

local function RetireContainer(container, allowCreate)
    local ok = AuraGlue.RunConfigPass(container, container._quiProfile or {}, {}, allowCreate)
    AuraSlots.Park(container)
    container:SetEnabled(false)
    container:Hide()
    return ok
end

local function DisableStripContainers(frame)
    if not frame then return end
    local pool = frame._quiAuraContainers
    if not pool or #pool == 0 then return end
    if not ResolveAuraDeps() then return end
    local inCombat = InCombatLockdown()
    local incomplete = false
    for i = 1, #pool do
        local container = pool[i]
        if container then
            if inCombat then
                local ok, complete = ns.SafeCall("best-effort-style", RetireContainer, container, false)
                if not ok or not complete then incomplete = true end
            else
                if not RetireContainer(container, true) then incomplete = true end
            end
        end
    end
    if incomplete then
        QueueContainerCombatWork(frame)
    end
end
QUI_GFA.DisableStripContainers = DisableStripContainers

local function HasActiveAuraElements(vdb)
    local auras = vdb and vdb.auras
    if not auras or auras.enabled == false then return false end
    local elements = auras.elements
    if type(elements) ~= "table" then return false end
    for key, bucket in pairs(elements) do
        if (key == "*" or type(key) == "number") and type(bucket) == "table" then
            for _, e in ipairs(bucket) do
                if type(e) == "table" and e.enabled ~= false then
                    return true
                end
            end
        end
    end
    return false
end

local function HasDispelConsumer(vdb)
    local healer = vdb and vdb.healer
    local dispel = healer and healer.dispelOverlay
    local glow = healer and healer.cleanseGlow
    return (dispel and (dispel.enabled ~= false or dispel.showIcon == true))
        or (glow and glow.enabled == true)
end

local function HasActiveAuraConsumers(isRaid)
    local vdb = GetVisualDBForContext(isRaid)
    if not vdb then return false end

    if HasActiveAuraElements(vdb) then return true end
    if HasDispelConsumer(vdb) then return true end

    return false
end

local function FrameHasActiveAuraConsumers(frame)
    return frame and HasActiveAuraConsumers(frame._isRaid) == true
end

local function AnyVisibleFrameHasActiveAuraConsumers(frames, nFrames)
    local partyActive = nil
    local raidActive = nil
    for i = 1, nFrames do
        local frame = frames[i]
        if frame and frame:IsShown() then
            if frame._isRaid then
                if raidActive == nil then
                    raidActive = HasActiveAuraConsumers(true)
                end
                if raidActive then return true end
            else
                if partyActive == nil then
                    partyActive = HasActiveAuraConsumers(false)
                end
                if partyActive then return true end
            end
        end
    end
    return false
end

function QUI_GFA:HasActiveConsumersForFrame(frame)
    return FrameHasActiveAuraConsumers(frame)
end

local AURA_HEAVY_BUDGET = 10
local _auraFrameStamp = 0
local _auraBudgetUsed = 0
local _auraDirtyUnits = {}
local _auraDrainFrame

local function HeavyBudgetAvailable()
    local now = (GetTime and GetTime()) or 0
    if now ~= _auraFrameStamp then
        _auraFrameStamp = now
        _auraBudgetUsed = 0
    end
    if _auraBudgetUsed >= AURA_HEAVY_BUDGET then return false end
    _auraBudgetUsed = _auraBudgetUsed + 1
    return true
end

local function ProcessUnitAuraSetChange(unit, updateInfo)
    local GF = ns.QUI_GroupFrames
    if not GF or not GF.initialized then return end
    local frames = GF.unitFrameMap[unit]
    if not frames then return end
    local nFrames = #frames
    if nFrames == 0 then return end

    local cacheUpdated = false
    local triedDelta = false
    if type(updateInfo) == "table" and not updateInfo.isFullUpdate then
        triedDelta = true
        cacheUpdated = ApplyAuraDelta(unit, updateInfo)
    elseif type(updateInfo) == "table" and updateInfo.isFullUpdate then
        if auraStats then auraStats.fullUpdateEvents = auraStats.fullUpdateEvents + 1 end
    end
    if cacheUpdated then
        if auraStats then auraStats.deltaApplied = auraStats.deltaApplied + 1 end
    else
        if triedDelta then
            if auraStats then auraStats.deltaFallback = auraStats.deltaFallback + 1 end
        end
        ScanUnitAuras(unit)
    end

    local cache = unitAuraCache[unit]
    local Render = GetRender()
    local dirty = cacheUpdated and _deltaSummary or nil
    for f = 1, nFrames do
        local frame = frames[f]
        if frame:IsShown() then
            if auraStats then auraStats.framesRefreshed = auraStats.framesRefreshed + 1 end
            if GF.UpdateDispelOverlay then
                GF:UpdateDispelOverlay(frame)
            end
            RenderFrameElements(frame, cache, dirty)
        end
    end

    if cacheUpdated and Render and type(updateInfo) == "table"
        and updateInfo.updatedAuraInstanceIDs
        and (updateInfo.addedAuras or updateInfo.removedAuraInstanceIDs)
    then
        local updated = updateInfo.updatedAuraInstanceIDs
        if Render.RefreshUpdatedBars then
            if Render:RefreshUpdatedBars(frames, nFrames, unit, updated) then
                if auraStats then auraStats.mixedIconRefreshes = auraStats.mixedIconRefreshes + 1 end
            end
        end
    end
end

local function EnsureAuraDrainFrame()
    if _auraDrainFrame then return _auraDrainFrame end
    _auraDrainFrame = CreateFrame("Frame")
    _auraDrainFrame:Hide()
    _auraDrainFrame:SetScript("OnUpdate", function(self)
        for unit in pairs(_auraDirtyUnits) do
            if HeavyBudgetAvailable() then
                _auraDirtyUnits[unit] = nil
                ProcessUnitAuraSetChange(unit, nil)
                if auraStats then auraStats.drainProcessed = auraStats.drainProcessed + 1 end
            else
                break
            end
        end
        if not next(_auraDirtyUnits) then self:Hide() end
    end)
    return _auraDrainFrame
end

if ns.AuraEvents then
    ns.AuraEvents:Subscribe("roster", function(unit, updateInfo)
        local GF = ns.QUI_GroupFrames
        if not GF or not GF.initialized then return end

        local frames = GF.unitFrameMap[unit]
        if not frames then return end
        local nFrames = #frames
        if nFrames == 0 then return end
        if not AnyVisibleFrameHasActiveAuraConsumers(frames, nFrames) then
            if auraStats then auraStats.noConsumerSkips = auraStats.noConsumerSkips + 1 end
            return
        end

        if type(updateInfo) == "table"
            and not updateInfo.isFullUpdate
            and not updateInfo.addedAuras
            and not updateInfo.removedAuraInstanceIDs
            and updateInfo.updatedAuraInstanceIDs
            and unitAuraCache[unit]
            and unitAuraCache[unit].hasFullScan
        then
            local updated = updateInfo.updatedAuraInstanceIDs
            local nUpdated = #updated
            if nUpdated == 0 then return end
            if AurasAreSecret() then return end
            if auraStats then auraStats.fastUpdates = auraStats.fastUpdates + 1 end

            local Render = GetRender()
            if Render then
                if Render.RefreshUpdatedIcons then
                    Render:RefreshUpdatedIcons(frames, nFrames, unit, updated)
                end
                if Render.RefreshUpdatedBars then
                    Render:RefreshUpdatedBars(frames, nFrames, unit, updated)
                end
            end
            return
        end

        if HeavyBudgetAvailable() then
            if _auraDirtyUnits[unit] then
                _auraDirtyUnits[unit] = nil
                ProcessUnitAuraSetChange(unit, nil)
            else
                ProcessUnitAuraSetChange(unit, updateInfo)
            end
        else
            _auraDirtyUnits[unit] = true
            if auraStats then auraStats.heavyDeferred = auraStats.heavyDeferred + 1 end
            EnsureAuraDrainFrame():Show()
        end
    end)
end

function QUI_GFA:InvalidateLayout()
    _relGeneration = _relGeneration + 1
    QUI_GFA._configGeneration = _relGeneration
end

function QUI_GFA:RefreshAll()
    local GF = ns.QUI_GroupFrames
    if not GF or not GF.initialized then return end

    _relGeneration = _relGeneration + 1
    QUI_GFA._configGeneration = _relGeneration
    for unit, list in pairs(GF.unitFrameMap) do
        local shouldScan = AnyVisibleFrameHasActiveAuraConsumers(list, #list)
        if shouldScan then
            ScanUnitAuras(unit)
        end
        local cache = unitAuraCache[unit]
        for i = 1, #list do
            local frame = list[i]
            if frame and frame:IsShown() then
                RenderFrameElements(frame, cache)
            end
        end
    end
end

function QUI_GFA:RefreshFrame(frame)
    local unit = GetFrameUnit(frame)
    if unit and FrameHasActiveAuraConsumers(frame) then
        ScanUnitAuras(unit)
    end
    RenderFrameElements(frame, unit and unitAuraCache[unit] or nil)
end

function QUI_GFA:RenderFrame(frame)
    local unit = GetFrameUnit(frame)
    RenderFrameElements(frame, unit and unitAuraCache[unit] or nil)
end

-- /run QUI.DebugTintFeeders() — dump feeder slot + tint overlay state.
-- slotShown=secret in combat is EXPECTED and good: it means the engine is
-- driving the slot's visibility with secret aura presence (which is the whole
-- mechanism). overlay=shown only says QUI hasn't hidden it; whether it
-- actually renders is the slot's (possibly secret) visibility.
QUI_GFA.DebugTintFeeders = function()
    print(string.format("|cff33ff99QUI tint feeders|r (combat=%s)",
        tostring((InCombatLockdown and InCombatLockdown()) or false)))
    local GF = ns.QUI_GroupFrames
    local found = false
    if GF and GF.unitFrameMap then
        local seen = {}
        for unit, frames in pairs(GF.unitFrameMap) do
            for i = 1, #frames do
                local frame = frames[i]
                if frame and not seen[frame] then
                    seen[frame] = true
                    local pool = frame._quiAuraContainers
                    if pool then
                        for c = 1, #pool do
                            local slots = pool[c] and pool[c]._quiSlots
                            if slots then
                                for s = 1, #slots do
                                    local sf = slots[s] and slots[s].frame
                                    if sf and sf._quiFeederActive then
                                        found = true
                                        local el = sf._quiFeederElement
                                        local shownTxt
                                        local ok, shown = ns.SafeCall("report", sf.IsShown, sf)
                                        if not ok then
                                            shownTxt = "err"
                                        elseif issecretvalue and issecretvalue(shown) then
                                            shownTxt = "secret"
                                        else
                                            shownTxt = tostring(shown)
                                        end
                                        local ov = sf._quiFeederTint
                                        print(string.format(
                                            "  %s c%d s%d slotShown=%s overlay=%s elem=%s",
                                            tostring(unit), c, s, shownTxt,
                                            ov and (ov:IsShown() and "shown" or "hidden") or "nil",
                                            tostring(el and el.id)))
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if not found then
        print("  (no active feeder slots — no healthTint elements, or containers not built yet)")
    end
end
_G.QUI = _G.QUI or {}
_G.QUI.DebugTintFeeders = QUI_GFA.DebugTintFeeders
