local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- CDM Catalog
--
-- Non-combat catalog facade for Blizzard Cooldown Viewer data. Runtime
-- modules should consume this module instead of scattering
-- C_CooldownViewer walks across render/update code.
---------------------------------------------------------------------------

local CDMCatalog = {}
ns.CDMCatalog = CDMCatalog

local C_CooldownViewer = C_CooldownViewer
local Sources = ns.CDMSources
local ipairs = ipairs
local pairs = pairs
local type = type
local tostring = tostring
local table_sort = table.sort

local issecretvalue = issecretvalue or function() return false end

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

function CDMCatalog.GetCategoryForKind(kind)
    return CATEGORY_FOR_KIND[kind]
end

function CDMCatalog.GetKindForCategory(category)
    return KIND_FOR_CATEGORY[category]
end

function CDMCatalog.IsUsableID(id)
    return type(id) == "number" and id > 0 and not issecretvalue(id)
end

function CDMCatalog.ToBaseSpellID(id)
    if ns.CDMIndex and ns.CDMIndex.ToBaseSpellID then
        return ns.CDMIndex.ToBaseSpellID(id)
    end
    if not CDMCatalog.IsUsableID(id) then return nil end
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

local function HasCooldownViewerAPI()
    return C_CooldownViewer
        and C_CooldownViewer.GetCooldownViewerCategorySet
        and C_CooldownViewer.GetCooldownViewerCooldownInfo
end

function CDMCatalog.GetCategorySet(category, includeHidden)
    if not HasCooldownViewerAPI() then return nil end
    local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category, includeHidden and true or false)
    if ok and type(ids) == "table" then
        return ids
    end
    return nil
end

function CDMCatalog.GetCooldownInfo(cooldownID)
    if not HasCooldownViewerAPI() or not cooldownID then return nil end
    local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
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
    if not category then return {} end

    local cooldownIDs = CDMCatalog.GetCategorySet(category, false)
    if not cooldownIDs then return {} end

    local entries = {}
    local seen = {}
    local isAuraCategory = category == 2 or category == 3
    for _, cdID in ipairs(cooldownIDs) do
        local info = CDMCatalog.GetCooldownInfo(cdID)
        local sid = SelectPreferredSpellID(info, isAuraCategory)
        if sid and not seen[sid] then
            seen[sid] = true
            entries[#entries + 1] = { type = "spell", id = sid }
        end
    end
    return entries
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
        local fallback = info.overrideSpellID or info.spellID
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

                        if auraIDsForSpell and (info.hasAura == true or info.selfAura == true) then
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
        local cooldownIDs = CDMCatalog.GetCategorySet(category, false)
        if cooldownIDs then
            for _, cdID in ipairs(cooldownIDs) do
                local cdInfo = CDMCatalog.GetCooldownInfo(cdID)
                if cdInfo then
                    local sid = correctionMap[cdID]
                    if not sid then
                        sid = SelectPreferredSpellID(cdInfo, isAuraContainer)
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
