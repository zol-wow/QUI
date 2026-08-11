local _, ns = ...

local CDMCatalog = {}
ns.CDMCatalog = CDMCatalog

local ipairs = ipairs
local pairs = pairs
local type = type
local tonumber = tonumber
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

local COOLDOWN_CATEGORIES = { 0, 1 }
local BUILTIN_COOLDOWN_PICKER_CATEGORIES = {
    essential = { 0, 1 },
    utility = { 1, 0 },
}
local PICKER_COOLDOWN_CATEGORIES = { 0, 1, 5, 7 }
local PICKER_AURA_CATEGORIES = { 2, 3, 6, 8 }
local ALL_RENDERED_CATEGORIES = { 0, 1, 2, 3, 5, 6, 7, 8 }
local CONSUMABLE_CATEGORY_META = {
    [4]    = { name = "Combat Potion", icon = "Interface/ICONS/INV_POTION_114" },
    [30]   = { name = "Health Potion", icon = "Interface/ICONS/INV_POTION_54" },
    [1711] = { name = "Healthstone",   icon = "Interface/ICONS/Warlock_ Healthstone" },
}
local BLIZZARD_CDM_ENTRY_SOURCE = "blizzardCDM"

function CDMCatalog.GetConsumableCategoryMeta(catID)
    return CONSUMABLE_CATEGORY_META[catID]
end

function CDMCatalog.IsUsableID(id)
    if type(id) ~= "number" then return false end
    if issecretvalue(id) then return false end -- @secret-policy: reject-secret-ids
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

function CDMCatalog.IsCooldownViewerReady()
    local api = GetCooldownViewerAPI()
    if not api then return false end
    if not api.IsCooldownViewerAvailable then
        return true
    end

    local ok, isAvailable = pcall(api.IsCooldownViewerAvailable)
    if not ok then return false end
    if issecretvalue(isAvailable) then return false end -- @secret-policy: reject-secret-value
    return isAvailable == true
end

function CDMCatalog.GetCategorySet(category, allowUnlearned)
    if not HasCooldownViewerAPI() or not CDMCatalog.IsCooldownViewerReady() then return nil end
    local api = GetCooldownViewerAPI()
    local ok, ids = ns.SafeCall("best-effort-style", api.GetCooldownViewerCategorySet, category, allowUnlearned and true or false)
    if ok and type(ids) == "table" then
        return ids
    end
    return nil
end

function CDMCatalog.GetTrackedCategorySet(category, allowUnlearned)
    if not CDMCatalog.IsCooldownViewerReady() then
        return nil, false
    end

    local settings = _G.CooldownViewerSettings
    if settings and settings.GetDataProvider then
        local okProvider, provider = ns.SafeCallMethod("best-effort-style", settings, "GetDataProvider")
        if not okProvider or not provider then
            return nil, false
        end

        if provider.displayDataDirty or provider.displayData == nil then
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
    if not HasCooldownViewerAPI() or not CDMCatalog.IsCooldownViewerReady() or not cooldownID then return nil end
    local api = GetCooldownViewerAPI()
    local ok, info = ns.SafeCall("best-effort-style", api.GetCooldownViewerCooldownInfo, cooldownID)
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
    if CDMCatalog.IsUsableID(info.overrideSpellID) then
        return info.overrideSpellID
    end
    if CDMCatalog.IsUsableID(baseSid) then
        return baseSid
    end
    return nil
end

local function AddCooldownInfoFamilyIDs(outSet, info)
    if type(outSet) ~= "table" or not info then return end
    if CDMCatalog.IsUsableID(info.spellID) then
        outSet[info.spellID] = true
    end
    if CDMCatalog.IsUsableID(info.overrideSpellID) then
        outSet[info.overrideSpellID] = true
    end
    if CDMCatalog.IsUsableID(info.overrideTooltipSpellID) then
        outSet[info.overrideTooltipSpellID] = true
    end
    if info.linkedSpellIDs then
        for _, linkedID in ipairs(info.linkedSpellIDs) do
            if CDMCatalog.IsUsableID(linkedID) then
                outSet[linkedID] = true
            end
        end
    end
end

local function CooldownInfoAppliesToPlayerClass(info)
    if not info then return nil end
    if info.isKnown == true then return true end
    local Sources = GetSources()
    local query = Sources and Sources.QuerySpellBookClassAffinity
    if not query then return nil end

    local sawDefinitiveAnswer = false
    local function CheckSpellID(spellID)
        if not CDMCatalog.IsUsableID(spellID) then return false end
        local applies = query(spellID)
        if applies == true then return true end
        if applies == false then sawDefinitiveAnswer = true end
        return false
    end

    if CheckSpellID(info.spellID)
        or CheckSpellID(info.overrideSpellID)
        or CheckSpellID(info.overrideTooltipSpellID) then
        return true
    end
    if info.linkedSpellIDs then
        for _, linkedID in ipairs(info.linkedSpellIDs) do
            if CheckSpellID(linkedID) then return true end
        end
    end
    if sawDefinitiveAnswer then return false end
    return nil
end

local function ResolveContainerCategories(containerKey, containerType)
    if containerType == "cooldown" and BUILTIN_COOLDOWN_PICKER_CATEGORIES[containerKey] then
        return BUILTIN_COOLDOWN_PICKER_CATEGORIES[containerKey], true
    end

    local cat = CATEGORY_FOR_KIND[containerKey]
    if cat ~= nil then
        return { cat }, true
    end
    if containerType == "cooldown" then
        return PICKER_COOLDOWN_CATEGORIES, false
    end
    if containerType == "aura" or containerType == "auraBar" then
        return PICKER_AURA_CATEGORIES, false
    end
    return ALL_RENDERED_CATEGORIES, false
end

local BUILTIN_CONTAINER_TYPES = {
    essential   = "cooldown",
    utility     = "cooldown",
    buff        = "aura",
    trackedBar  = "auraBar",
}

local function ResolveContainerType(containerKey)
    local Shared = ns.CDMShared
    if Shared and Shared.GetContainerType then
        local containerType = Shared.GetContainerType(containerKey)
        if containerType then
            return containerType
        end
    end
    if BUILTIN_CONTAINER_TYPES[containerKey] then
        return BUILTIN_CONTAINER_TYPES[containerKey]
    end
    return "cooldown"
end

local function GetCooldownRowLimits(db)
    local rows = {}
    if type(db) ~= "table" then return rows end
    for r = 1, 3 do
        local rowData = db["row" .. r]
        local iconCount = rowData and tonumber(rowData.iconCount)
        if iconCount and iconCount > 0 then
            rows[#rows + 1] = { rowNum = r, max = iconCount }
        end
    end
    return rows
end

function CDMCatalog.AssignCooldownRowsByCapacity(entries, containerKey)
    if type(entries) ~= "table" or ResolveContainerType(containerKey) ~= "cooldown" then
        return entries
    end

    local Shared = ns.CDMShared
    local db = Shared and Shared.GetContainerDB and Shared.GetContainerDB(containerKey)
    local rows = GetCooldownRowLimits(db)
    if #rows == 0 then return entries end

    local rowIdx = 1
    local rowUsed = 0
    for _, entry in ipairs(entries) do
        if type(entry) == "table" then
            local row = rows[rowIdx]
            if row and rowUsed < row.max then
                entry.row = row.rowNum
                rowUsed = rowUsed + 1
                if rowUsed >= row.max then
                    rowIdx = rowIdx + 1
                    rowUsed = 0
                end
            else
                entry.row = nil
            end
        end
    end
    return entries
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
        elseif info.equipSlot then
            local slot = info.equipSlot
            local key = "slot:" .. slot
            if not seen[key] then
                seen[key] = true
                entries[#entries + 1] = {
                    type = "slot",
                    id = slot,
                    source = BLIZZARD_CDM_ENTRY_SOURCE,
                }
            end
        elseif info.spellCategoryID then
            local catID = info.spellCategoryID
            local key = "consumable:" .. catID
            if not seen[key] then
                seen[key] = true
                entries[#entries + 1] = {
                    type = "consumable",
                    id = catID,
                    source = BLIZZARD_CDM_ENTRY_SOURCE,
                }
            end
        elseif CooldownInfoAppliesToPlayerClass(info) ~= false then
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

    local isReady = ready == true
    if isReady then
        CDMCatalog.AssignCooldownRowsByCapacity(entries, containerKind)
    end
    return entries, isReady
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

    for _, cat in ipairs(ALL_RENDERED_CATEGORIES) do
        local ids = CDMCatalog.GetCategorySet(cat, true)
        local isAuraCategory = cat == 2 or cat == 3 or cat == 6 or cat == 8
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

function CDMCatalog.RebuildCooldownLearnedPreferredIDs(outSet)
    if type(outSet) ~= "table" then return false end
    if not HasCooldownViewerAPI() then return false end

    for _, cat in ipairs(COOLDOWN_CATEGORIES) do
        local ids = CDMCatalog.GetCategorySet(cat, false)
        if ids then
            for _, cdID in ipairs(ids) do
                local info = CDMCatalog.GetCooldownInfo(cdID)
                if info then
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

function CDMCatalog.RebuildAuraLearnedFamilyIDs(outSet)
    if type(outSet) ~= "table" then return false end
    if not HasCooldownViewerAPI() then return false end

    local ready = true
    for _, cat in ipairs(PICKER_AURA_CATEGORIES) do
        local ids = CDMCatalog.GetCategorySet(cat, false)
        if not ids then
            ready = false
        else
            for _, cdID in ipairs(ids) do
                local info = CDMCatalog.GetCooldownInfo(cdID)
                if not info then
                    ready = false
                elseif not info.equipSlot and not info.spellCategoryID then
                    AddCooldownInfoFamilyIDs(outSet, info)
                end
            end
        end
    end
    return ready
end

function CDMCatalog.RebuildTrackedDisplayFamilyIDs(iconSet, barSet)
    if type(iconSet) ~= "table" or type(barSet) ~= "table" then return false end
    if not HasCooldownViewerAPI() then return false end

    local ready = true
    for category, outSet in pairs({ [2] = iconSet, [3] = barSet }) do
        local ids = CDMCatalog.GetTrackedCategorySet(category, true)
        if not ids then
            ready = false
        else
            for _, cdID in ipairs(ids) do
                local info = CDMCatalog.GetCooldownInfo(cdID)
                if not info then
                    ready = false
                elseif not info.equipSlot and not info.spellCategoryID then
                    AddCooldownInfoFamilyIDs(outSet, info)
                end
            end
        end
    end
    return ready
end

function CDMCatalog.RebuildClassApplicableSpellIDs(outSet)
    if type(outSet) ~= "table" then return false end
    if not HasCooldownViewerAPI() then return false end

    local ready = true
    for _, cat in ipairs(ALL_RENDERED_CATEGORIES) do
        local ids = CDMCatalog.GetCategorySet(cat, true)
        if not ids then
            ready = false
        else
            for _, cdID in ipairs(ids) do
                local info = CDMCatalog.GetCooldownInfo(cdID)
                if not info then
                    ready = false
                elseif not info.equipSlot and not info.spellCategoryID then
                    local applies = CooldownInfoAppliesToPlayerClass(info)
                    if applies == nil then ready = false end
                    if applies ~= false then
                        AddCooldownInfoFamilyIDs(outSet, info)
                    end
                end
            end
        end
    end
    return ready
end

function CDMCatalog.GetAvailableSpellsForContainer(containerKey, containerType, ownedSet, correctionMap)
    if not HasCooldownViewerAPI() then
        return {}
    end

    ownedSet = ownedSet or {}
    correctionMap = correctionMap or {}

    local categories, useTrackedCategories = ResolveContainerCategories(containerKey, containerType)
    local isAuraContainer = containerType == "aura" or containerType == "auraBar"
    local available = {}
    local seen = {}

    for _, category in ipairs(categories) do
        local cooldownIDs
        if useTrackedCategories then
            cooldownIDs = CDMCatalog.GetTrackedCategorySet(category, true)
        else
            cooldownIDs = CDMCatalog.GetCategorySet(category, true)
        end
        if cooldownIDs then
            for _, cdID in ipairs(cooldownIDs) do
                local cdInfo = CDMCatalog.GetCooldownInfo(cdID)
                if cdInfo and cdInfo.equipSlot then
                    local slot = cdInfo.equipSlot
                    local itemKey = "slot:" .. slot
                    if not seen[itemKey] and not ownedSet[itemKey] and not ownedSet[slot] then
                        seen[itemKey] = true
                        local Sources = GetSources()
                        local itemID = Sources and Sources.QueryInventoryItemID
                            and Sources.QueryInventoryItemID("player", slot)
                        local name, icon
                        if itemID and Sources then
                            if Sources.QueryItemNameByID then
                                name = Sources.QueryItemNameByID(itemID)
                            end
                            if Sources.QueryItemIconByID then
                                icon = Sources.QueryItemIconByID(itemID)
                            end
                        end
                        available[#available + 1] = {
                            spellID    = slot,
                            name       = name or ("Slot " .. slot),
                            icon       = icon or 0,
                            isKnown    = cdInfo.isKnown,
                            source     = BLIZZARD_CDM_ENTRY_SOURCE,
                            _entryType = "slot",
                            _entryID   = slot,
                            _slotID    = slot,
                        }
                    end
                elseif cdInfo and cdInfo.spellCategoryID then
                    local catID = cdInfo.spellCategoryID
                    local consKey = "consumable:" .. catID
                    if not seen[consKey] and not ownedSet[consKey] and not ownedSet[catID] then
                        seen[consKey] = true
                        local meta = CONSUMABLE_CATEGORY_META[catID]
                        local L = ns.L
                        local name = meta and ((L and L[meta.name]) or meta.name)
                            or ("Category " .. catID)
                        available[#available + 1] = {
                            spellID    = catID,
                            name       = name,
                            icon       = (meta and meta.icon) or 0,
                            isKnown    = cdInfo.isKnown,
                            source     = BLIZZARD_CDM_ENTRY_SOURCE,
                            _entryType = "consumable",
                            _entryID   = catID,
                        }
                    end
                elseif cdInfo and CooldownInfoAppliesToPlayerClass(cdInfo) ~= false then
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

    for _, cat in ipairs(ALL_RENDERED_CATEGORIES) do
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
