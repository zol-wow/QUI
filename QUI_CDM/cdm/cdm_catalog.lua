local _, ns = ...

---------------------------------------------------------------------------
-- CDM Catalog
--
-- Non-combat catalog facade for Blizzard Cooldown Viewer data. Runtime
-- modules should consume this module instead of scattering
-- C_CooldownViewer walks across render/update code.
---------------------------------------------------------------------------

local CDMCatalog = {}
ns.CDMCatalog = CDMCatalog

local ipairs = ipairs
local pairs = pairs
local type = type
local tostring = tostring
local table_sort = table.sort

local issecretvalue = issecretvalue or function() return false end

local function GetCooldownViewerAPI()
    return _G.C_CooldownViewer
end

local function GetSources()
    return ns.CDMSources
end

local CATEGORY_FOR_KIND = {
    essential   = 0,
    utility     = 1,
    buff        = 2,
    trackedBar  = 3,
}

local KIND_FOR_CATEGORY = {
    [0] = "essential",
    [1] = "utility",
    [2] = "buff",
    [3] = "trackedBar",
}

local COOLDOWN_CATEGORIES = { 0, 1 }
local AURA_CATEGORIES = { 2, 3 }
local ALL_RENDERED_CATEGORIES = { 0, 1, 2, 3 }
local BLIZZARD_CDM_ENTRY_SOURCE = "blizzardCDM"

function CDMCatalog.GetCategoryForKind(kind)
    return CATEGORY_FOR_KIND[kind]
end

function CDMCatalog.GetKindForCategory(category)
    return KIND_FOR_CATEGORY[category]
end

function CDMCatalog.IsUsableID(id)
    if type(id) ~= "number" then return false end
    if issecretvalue(id) then return false end
    return id > 0
end

function CDMCatalog.ToBaseSpellID(id)
    if ns.CDMIndex and ns.CDMIndex.ToBaseSpellID then
        return ns.CDMIndex.ToBaseSpellID(id)
    end
    if not CDMCatalog.IsUsableID(id) then return nil end
    local Sources = GetSources()
    local base = Sources and Sources.QueryBaseSpell and Sources.QueryBaseSpell(id)
    if CDMCatalog.IsUsableID(base) then
        return base
    end
    return id
end

function CDMCatalog.ForEachCooldownInfoID(info, callback)
    if ns.CDMIndex and ns.CDMIndex.ForEachCooldownInfoID then
        return ns.CDMIndex.ForEachCooldownInfoID(info, callback)
    end
    if not info or type(callback) ~= "function" then return end
    callback(info.overrideTooltipSpellID)
    callback(info.overrideSpellID)
    callback(info.spellID)
    if info.linkedSpellIDs then
        for _, id in ipairs(info.linkedSpellIDs) do
            callback(id)
        end
    end
end

function CDMCatalog.IsAuraCategoryName(categoryName)
    if ns.CDMShared and ns.CDMShared.IsAuraMirrorCategory then
        return ns.CDMShared.IsAuraMirrorCategory(categoryName)
    end
    return categoryName == "buff" or categoryName == "trackedBar"
end

function CDMCatalog.MapCooldownInfoIDs(catMap, directMap, info, cooldownID, categoryName)
    if not (catMap and info and cooldownID) then return end

    local function selectPrimarySourceID()
        if CDMCatalog.IsUsableID(info.overrideSpellID) then
            return info.overrideSpellID
        end
        return info.spellID
    end

    local function add(map, id, overwrite)
        if not (map and CDMCatalog.IsUsableID(id)) then return end
        if overwrite or not map[id] then
            map[id] = cooldownID
        end
    end

    local isAuraCategory = CDMCatalog.IsAuraCategoryName(categoryName)
    local primarySourceID = selectPrimarySourceID()

    add(catMap, primarySourceID, true)
    add(catMap, info.spellID, false)
    add(catMap, info.overrideSpellID, false)
    if isAuraCategory then
        add(catMap, info.overrideTooltipSpellID, true)

        if type(info.linkedSpellIDs) == "table" then
            for _, linkedID in ipairs(info.linkedSpellIDs) do
                add(catMap, linkedID, false)
            end
        end
    end

    if isAuraCategory then
        add(directMap, info.overrideTooltipSpellID, true)
        if type(info.linkedSpellIDs) == "table" then
            for _, linkedID in ipairs(info.linkedSpellIDs) do
                add(directMap, linkedID, true)
            end
        end
        add(directMap, primarySourceID, false)
        add(directMap, info.spellID, false)
        add(directMap, info.overrideSpellID, false)
        return
    end

    add(directMap, primarySourceID, true)
    add(directMap, info.spellID, false)
    add(directMap, info.overrideSpellID, false)
end

local function HasCooldownViewerAPI()
    local api = GetCooldownViewerAPI()
    return api
        and api.GetCooldownViewerCategorySet
        and api.GetCooldownViewerCooldownInfo
end

local function IsCooldownViewerReady()
    local api = GetCooldownViewerAPI()
    if not api then return false end
    if not api.IsCooldownViewerAvailable then
        return true
    end

    local ok, isAvailable = pcall(api.IsCooldownViewerAvailable)
    if not ok then return false end
    if issecretvalue(isAvailable) then return false end
    return isAvailable == true
end

function CDMCatalog.GetCategorySet(category, allowUnlearned)
    if not HasCooldownViewerAPI() or not IsCooldownViewerReady() then return nil end
    local api = GetCooldownViewerAPI()
    local ok, ids = pcall(api.GetCooldownViewerCategorySet, category, allowUnlearned and true or false)
    if ok and type(ids) == "table" then
        return ids
    end
    return nil
end

function CDMCatalog.GetTrackedCategorySet(category, allowUnlearned)
    if not IsCooldownViewerReady() then
        return nil, false
    end

    local settings = _G.CooldownViewerSettings
    if settings and settings.GetDataProvider then
        local okProvider, provider = pcall(settings.GetDataProvider, settings)
        if not okProvider or not provider then
            return nil, false
        end

        local okManager, manager
        if provider.GetLayoutManager then
            okManager, manager = pcall(provider.GetLayoutManager, provider)
        end
        if not okManager or not manager then
            return nil, false
        end

        if provider.GetOrderedCooldownIDsForCategory then
            local ok, ids = pcall(
                provider.GetOrderedCooldownIDsForCategory,
                provider,
                category,
                allowUnlearned and true or false)
            if ok and type(ids) == "table" then
                return ids, true
            end
        end
        return nil, false
    end

    local ids = CDMCatalog.GetCategorySet(category, allowUnlearned)
    return ids, ids ~= nil and #ids > 0
end

function CDMCatalog.GetCooldownInfo(cooldownID)
    if not HasCooldownViewerAPI() or not IsCooldownViewerReady() or not cooldownID then return nil end
    local api = GetCooldownViewerAPI()
    local ok, info = pcall(api.GetCooldownViewerCooldownInfo, cooldownID)
    if ok then
        return info
    end
    return nil
end

local function SelectPreferredSpellID(info, isAuraCategory)
    if not info then return nil end
    if isAuraCategory then
        local tooltipSid = info.overrideTooltipSpellID
        if CDMCatalog.IsUsableID(tooltipSid) then
            return tooltipSid
        end
    end
    if CDMCatalog.IsUsableID(info.overrideSpellID) then
        return info.overrideSpellID
    end
    if CDMCatalog.IsUsableID(info.spellID) then
        return info.spellID
    end
    return nil
end

-- Persistent (catalog/entry) identity spell id for a cooldown slot.
--
-- SelectPreferredSpellID is display-oriented: it prefers the live
-- info.overrideSpellID so the icon shows the current override art. That id is
-- wrong for *identity* when the override is a TRANSIENT PROC override — e.g.
-- Hammer of Light (427453) overriding Wake of Ashes (255647) on a Light's
-- Guidance proc. The base ability stays independently learned while the proc
-- is live, so keying identity off the override makes the base drop out of the
-- learned-cooldown set every proc (the live icon goes dormant / disappears)
-- and surfaces the proc spell as an "unlearned" phantom entry in the composer.
--
-- A PERMANENT TALENT override is the opposite: it converts the base away, so
-- the base is no longer IsSpellKnown and the override id is the correct
-- surviving identity (the Death Charge / Augmentation conversion cases the
-- learned-preferred set exists to handle).
--
-- Discriminate on whether the base spellID is still independently known. Only
-- meaningful for cooldown categories; aura categories keep SelectPreferredSpellID.
local function SelectPersistentSpellID(info)
    if not info then return nil end
    local baseSid = info.spellID
    if CDMCatalog.IsUsableID(baseSid) then
        local Sources = GetSources()
        local baseKnown = Sources and Sources.QueryIsSpellKnownOrPlayerSpell
            and Sources.QueryIsSpellKnownOrPlayerSpell(baseSid)
        if baseKnown then
            return baseSid
        end
    end
    -- Base not independently known (talent conversion) -> the override id is
    -- the surviving identity.
    if CDMCatalog.IsUsableID(info.overrideSpellID) then
        return info.overrideSpellID
    end
    if CDMCatalog.IsUsableID(baseSid) then
        return baseSid
    end
    return nil
end

local function ResolveContainerCategories(containerKey, containerType)
    if containerType == "cooldown" then
        return COOLDOWN_CATEGORIES
    end
    if containerType == "aura" or containerType == "auraBar" then
        return AURA_CATEGORIES
    end
    local cat = CATEGORY_FOR_KIND[containerKey]
    if cat == 0 or cat == 1 then
        return COOLDOWN_CATEGORIES
    elseif cat == 2 or cat == 3 then
        return AURA_CATEGORIES
    end
    return ALL_RENDERED_CATEGORIES
end

function CDMCatalog.SeedFromBlizzard(containerKind)
    local category = CATEGORY_FOR_KIND[containerKind]
    if not category then return {}, false end

    local cooldownIDs, ready = CDMCatalog.GetTrackedCategorySet(category, true)
    if not cooldownIDs then return {}, false end

    local entries = {}
    local seen = {}
    local isAuraCategory = category == 2 or category == 3
    local missingInfo = false
    for _, cdID in ipairs(cooldownIDs) do
        local info = CDMCatalog.GetCooldownInfo(cdID)
        if not info then
            missingInfo = true
        else
            local sid = isAuraCategory and SelectPreferredSpellID(info, true)
                or SelectPersistentSpellID(info)
            if sid and not seen[sid] then
                seen[sid] = true
                entries[#entries + 1] = {
                    type = "spell",
                    id = sid,
                    source = BLIZZARD_CDM_ENTRY_SOURCE,
                }
            end
        end
    end
    if missingInfo then
        return {}, false
    end
    return entries, ready == true
end

local function AppendAuraIDs(map, key, auraIDs)
    if not (map and key and auraIDs and #auraIDs > 0) then return end
    local existing = map[key]
    if not existing then
        existing = {}
        map[key] = existing
    end

    for _, aid in ipairs(auraIDs) do
        local found = false
        for _, existingID in ipairs(existing) do
            if existingID == aid then
                found = true
                break
            end
        end
        if not found then
            existing[#existing + 1] = aid
        end
    end
end

local function AddFamilyID(spellToCDID, familySet, spellID, cooldownID)
    if CDMCatalog.IsUsableID(spellID) then
        spellToCDID[spellID] = cooldownID
        familySet[spellID] = true
    end
end

local function GetAuraIDsFromInfo(info)
    local auraIDs = {}
    if CDMCatalog.IsUsableID(info.overrideTooltipSpellID) then
        auraIDs[#auraIDs + 1] = info.overrideTooltipSpellID
    end
    if info.linkedSpellIDs then
        for _, linkedID in ipairs(info.linkedSpellIDs) do
            if CDMCatalog.IsUsableID(linkedID) then
                auraIDs[#auraIDs + 1] = linkedID
            end
        end
    end
    if #auraIDs == 0 then
        local fallback = CDMCatalog.IsUsableID(info.overrideSpellID)
            and info.overrideSpellID
            or info.spellID
        if CDMCatalog.IsUsableID(fallback) then
            auraIDs[1] = fallback
        end
    end
    return auraIDs
end

function CDMCatalog.RebuildBlizzardCatalogMaps(spellToCDID, inCooldowns, inAuras, abilityToAura, auraIDsForSpell)
    if type(spellToCDID) ~= "table"
        or type(inCooldowns) ~= "table"
        or type(inAuras) ~= "table"
        or type(abilityToAura) ~= "table" then
        return false
    end

    if not HasCooldownViewerAPI() then
        return false
    end

    for cat = 0, 3 do
        local ids = CDMCatalog.GetCategorySet(cat, true)
        local isAuraCategory = cat == 2 or cat == 3
        local familySet = isAuraCategory and inAuras or inCooldowns
        if ids then
            for _, cdID in ipairs(ids) do
                local info = CDMCatalog.GetCooldownInfo(cdID)
                if info then
                    AddFamilyID(spellToCDID, familySet, info.spellID, cdID)
                    AddFamilyID(spellToCDID, familySet, info.overrideSpellID, cdID)

                    if isAuraCategory then
                        AddFamilyID(spellToCDID, familySet, info.overrideTooltipSpellID, cdID)
                        if info.linkedSpellIDs then
                            for _, linkedID in ipairs(info.linkedSpellIDs) do
                                AddFamilyID(spellToCDID, familySet, linkedID, cdID)
                            end
                        end

                        local auraIDs = GetAuraIDsFromInfo(info)
                        local sid = CDMCatalog.IsUsableID(info.spellID) and info.spellID or nil
                        local ov = CDMCatalog.IsUsableID(info.overrideSpellID) and info.overrideSpellID or nil
                        local tooltip = CDMCatalog.IsUsableID(info.overrideTooltipSpellID) and info.overrideTooltipSpellID or nil

                        if auraIDsForSpell then
                            AppendAuraIDs(auraIDsForSpell, sid, auraIDs)
                            if ov and ov ~= sid then
                                AppendAuraIDs(auraIDsForSpell, ov, auraIDs)
                            end
                            if tooltip and tooltip ~= sid and tooltip ~= ov then
                                AppendAuraIDs(auraIDsForSpell, tooltip, auraIDs)
                            end
                        end

                        local auraID = auraIDs[1]
                        if auraID then
                            if sid and sid ~= auraID then
                                abilityToAura[sid] = auraID
                            end
                            if ov and ov ~= auraID and ov ~= sid then
                                abilityToAura[ov] = auraID
                            end
                        end
                    end
                end
            end
        end
    end

    return true
end

-- Learned/active cooldown catalog signal for dormancy classification.
--
-- _spellInCDMCooldowns (built above with allowUnlearned=TRUE) is a stable
-- superset that never drops a spell once the spec has ever known it, so it
-- cannot answer "is this still a live cooldown right now." When a talent
-- converts an active ability into a passive (different spell ID), the old
-- active ID lingers in that superset forever. This set instead collects the
-- PREFERRED spell id of each LEARNED cooldown slot (allowUnlearned=FALSE),
-- so the converted-away active ID drops out and the slot's new preferred id
-- (the passive / override target) takes its place. A blizzardCDM cooldown
-- entry whose id is absent here is dormant. Cooldown categories only (0,1);
-- aura families keep their own membership path.
function CDMCatalog.RebuildCooldownLearnedPreferredIDs(outSet)
    if type(outSet) ~= "table" then return false end
    if not HasCooldownViewerAPI() then return false end

    for _, cat in ipairs(COOLDOWN_CATEGORIES) do
        local ids = CDMCatalog.GetCategorySet(cat, false)
        if ids then
            for _, cdID in ipairs(ids) do
                local info = CDMCatalog.GetCooldownInfo(cdID)
                if info then
                    -- Persistent identity (not the live display override): a
                    -- proc override must not evict its still-learned base from
                    -- the learned set (else the base icon goes dormant on proc).
                    local sid = SelectPersistentSpellID(info)
                    if CDMCatalog.IsUsableID(sid) then
                        outSet[sid] = true
                    end
                end
            end
        end
    end
    return true
end

function CDMCatalog.GetAvailableSpellsForContainer(containerKey, containerType, ownedSet, correctionMap)
    if not HasCooldownViewerAPI() then
        return {}
    end

    ownedSet = ownedSet or {}
    correctionMap = correctionMap or {}

    local categories = ResolveContainerCategories(containerKey, containerType)
    local isAuraContainer = containerType == "aura" or containerType == "auraBar"
    local available = {}
    local seen = {}

    for _, category in ipairs(categories) do
        local cooldownIDs = CDMCatalog.GetCategorySet(category, true)
        if cooldownIDs then
            for _, cdID in ipairs(cooldownIDs) do
                local cdInfo = CDMCatalog.GetCooldownInfo(cdID)
                if cdInfo then
                    local sid = correctionMap[cdID]
                    if not sid then
                        sid = isAuraContainer and SelectPreferredSpellID(cdInfo, true)
                            or SelectPersistentSpellID(cdInfo)
                    end

                    if sid and not seen[sid] then
                        seen[sid] = true
                        if CDMCatalog.IsUsableID(cdInfo.spellID) then
                            seen[cdInfo.spellID] = true
                        end
                        if CDMCatalog.IsUsableID(cdInfo.overrideSpellID) then
                            seen[cdInfo.overrideSpellID] = true
                        end

                        if not ownedSet[sid] then
                            local displaySid = sid
                            local Sources = GetSources()
                            local ovDisplay = Sources and Sources.QueryOverrideSpell
                                and Sources.QueryOverrideSpell(sid)
                            if ovDisplay and ovDisplay ~= sid then
                                displaySid = ovDisplay
                            end

                            local name, icon
                            local spellInfo = Sources and Sources.QuerySpellInfo
                                and Sources.QuerySpellInfo(displaySid)
                            if spellInfo then
                                name = spellInfo.name
                                icon = spellInfo.iconID
                            end

                            available[#available + 1] = {
                                spellID = sid,
                                name = name or "",
                                icon = icon or 0,
                                isKnown = cdInfo.isKnown,
                                source = BLIZZARD_CDM_ENTRY_SOURCE,
                            }
                        end
                    end
                end
            end
        end
    end

    table_sort(available, function(a, b)
        local an = a.name or ""
        local bn = b.name or ""
        if an ~= bn then return an < bn end
        return tostring(a.spellID) < tostring(b.spellID)
    end)
    return available
end

function CDMCatalog.CollectKnownCDMSpellIDs(out)
    out = out or {}
    if not HasCooldownViewerAPI() then
        return out
    end

    for cat = 0, 3 do
        local ids = CDMCatalog.GetCategorySet(cat, true)
        if ids then
            for _, cdID in ipairs(ids) do
                local info = CDMCatalog.GetCooldownInfo(cdID)
                if info then
                    if CDMCatalog.IsUsableID(info.spellID) then
                        out[info.spellID] = true
                    end
                    if CDMCatalog.IsUsableID(info.overrideSpellID) then
                        out[info.overrideSpellID] = true
                    end
                end
            end
        end
    end
    return out
end

function CDMCatalog.GetOrderedSpellMap()
    if ns.CDMIndex and ns.CDMIndex.GetOrderedSpellMap then
        return ns.CDMIndex.GetOrderedSpellMap()
    end
    return {}
end

function CDMCatalog.GetIndexEntry(spellID)
    if ns.CDMIndex and ns.CDMIndex.Get then
        return ns.CDMIndex.Get(spellID)
    end
    return nil
end
