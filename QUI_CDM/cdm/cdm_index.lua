local _, ns = ...

local CDMIndex = {}
ns.CDMIndex = CDMIndex

local ipairs = ipairs
local pairs = pairs
local type = type
local wipe = wipe

local issecretvalue = issecretvalue or function() return false end

local function GetCooldownViewerAPI()
    return _G.C_CooldownViewer
end

local function GetSources()
    return ns.CDMSources
end

function CDMIndex.IsUsableID(id)
    if type(id) ~= "number" then return false end
    if issecretvalue(id) then return false end -- @secret-policy: reject-secret-ids
    return id > 0
end

function CDMIndex.ToBaseSpellID(id)
    if not CDMIndex.IsUsableID(id) then return nil end
    local Sources = GetSources()
    local base = Sources and Sources.QueryBaseSpell and Sources.QueryBaseSpell(id)
    if not CDMIndex.IsUsableID(base) then return id end
    return base
end

function CDMIndex.ForEachCooldownInfoID(info, callback)
    if not info then return end
    callback(info.overrideTooltipSpellID)
    callback(info.overrideSpellID)
    callback(info.spellID)
    if info.linkedSpellIDs then
        for _, id in ipairs(info.linkedSpellIDs) do
            callback(id)
        end
    end
end

local function SelectPrimaryCooldownInfoID(info)
    if not info then return nil end
    if CDMIndex.IsUsableID(info.overrideTooltipSpellID) then
        return info.overrideTooltipSpellID
    end
    if CDMIndex.IsUsableID(info.overrideSpellID) then
        return info.overrideSpellID
    end
    if CDMIndex.IsUsableID(info.spellID) then
        return info.spellID
    end
    return nil
end

local _spellIndex = {}
local _equipSlotIndex = {}
local _categoryIndex = {}
local _version = 0
local _built = false
local _orderedSpellMap = nil
local _orderedEquipSlotMap = nil
local _orderedCategoryMap = nil
local _orderedSpellMapByCategory = nil
local _orderedEquipSlotMapByCategory = nil
local _orderedCategoryMapByCategory = nil
local _orderedMapsVersion = -1

function CDMIndex.Version() return _version end

local CATEGORIES_FOR_INDEX = nil

local function GetIndexCategories()
    if CATEGORIES_FOR_INDEX then return CATEGORIES_FOR_INDEX end
    if not (Enum and Enum.CooldownViewerCategory) then return nil end
    local E = Enum.CooldownViewerCategory
    CATEGORIES_FOR_INDEX = {
        E.TrackedBuff,
        E.TrackedBar,
        E.Essential,
        E.Utility,
        E.SpecAgnosticTracked,
        E.SpecAgnosticEssential,
        E.EquipSlotTracked,
        E.EquipSlotEssential,
        E.HiddenSpell,
        E.HiddenAura,
    }
    return CATEGORIES_FOR_INDEX
end

function CDMIndex.Rebuild()
    wipe(_spellIndex)
    wipe(_equipSlotIndex)
    wipe(_categoryIndex)
    _built = true
    _version = _version + 1

    local api = GetCooldownViewerAPI()
    if not (api
            and api.GetCooldownViewerCategorySet
            and api.GetCooldownViewerCooldownInfo) then
        return
    end

    local cats = GetIndexCategories()
    if not cats then return end

    local seenCooldown = {}
    for _, cat in ipairs(cats) do
        if cat ~= nil then
            local ids = api.GetCooldownViewerCategorySet(cat, true)
            if ids then
                for _, cdID in ipairs(ids) do
                    if not seenCooldown[cdID] then
                        seenCooldown[cdID] = true
                        local info = api.GetCooldownViewerCooldownInfo(cdID)
                        if info then
                            local primarySid = SelectPrimaryCooldownInfoID(info)
                            local primaryBase = CDMIndex.ToBaseSpellID(primarySid)
                            local equipSlot = info.equipSlot
                            local spellCategoryID = info.spellCategoryID
                            local hasEquipSlot = type(equipSlot) == "number"
                                and not issecretvalue(equipSlot)
                            local hasCategory = type(spellCategoryID) == "number"
                                and not issecretvalue(spellCategoryID)
                            if primaryBase or hasEquipSlot or hasCategory then
                                local entry = {
                                    cooldownID     = cdID,
                                    category       = cat,
                                    primarySpellID = primaryBase,
                                    aliases        = {},
                                }
                                if primaryBase then
                                    local seenAlias = {}
                                    CDMIndex.ForEachCooldownInfoID(info, function(id)
                                        local b = CDMIndex.ToBaseSpellID(id)
                                        if b and not seenAlias[b] then
                                            seenAlias[b] = true
                                            entry.aliases[#entry.aliases + 1] = b
                                            if not _spellIndex[b] then
                                                _spellIndex[b] = entry
                                            end
                                        end
                                    end)
                                end
                                if hasEquipSlot and _equipSlotIndex[equipSlot] == nil then
                                    _equipSlotIndex[equipSlot] = entry
                                end
                                if hasCategory and _categoryIndex[spellCategoryID] == nil then
                                    _categoryIndex[spellCategoryID] = entry
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

function CDMIndex.Get(spellID)
    if not _built then CDMIndex.Rebuild() end
    local base = CDMIndex.ToBaseSpellID(spellID)
    if not base then return nil end
    return _spellIndex[base]
end

function CDMIndex.GetByEquipSlot(equipSlot)
    if not _built then CDMIndex.Rebuild() end
    if type(equipSlot) ~= "number" or issecretvalue(equipSlot) then return nil end
    return _equipSlotIndex[equipSlot]
end

function CDMIndex.GetByCategory(spellCategoryID)
    if not _built then CDMIndex.Rebuild() end
    if type(spellCategoryID) ~= "number" or issecretvalue(spellCategoryID) then return nil end
    return _categoryIndex[spellCategoryID]
end

local _subs = {}

local function SortSubs()
    table.sort(_subs, function(a, b)
        if a.priority ~= b.priority then
            return a.priority < b.priority
        end
        return a.name < b.name
    end)
end

function CDMIndex.Subscribe(name, callback, priority)
    if type(name) ~= "string" or type(callback) ~= "function" then return end
    for i = 1, #_subs do
        if _subs[i].name == name then
            _subs[i].cb = callback
            _subs[i].priority = priority or 100
            SortSubs()
            return
        end
    end
    _subs[#_subs + 1] = { name = name, cb = callback, priority = priority or 100 }
    SortSubs()
end

function CDMIndex.Unsubscribe(name)
    for i = #_subs, 1, -1 do
        if _subs[i].name == name then
            table.remove(_subs, i)
            return
        end
    end
end

local function Notify(reason, ...)
    _built = false
    _version = _version + 1
    for i = 1, #_subs do
        local s = _subs[i]
        local ok, err = pcall(s.cb, reason, ...)
        if not ok and ns.QUICore and ns.QUICore.DebugPrint then
            ns.QUICore.DebugPrint("CDMIndex broker subscriber '" .. s.name
                .. "' raised: " .. tostring(err))
        end
    end
end

CDMIndex.Notify = Notify

local _eventFrame = CreateFrame("Frame")
_eventFrame:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED")
_eventFrame:RegisterEvent("COOLDOWN_VIEWER_TABLE_HOTFIXED")
_eventFrame:RegisterEvent("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED")
_eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "COOLDOWN_VIEWER_DATA_LOADED" then
        Notify("data_loaded")
    elseif event == "COOLDOWN_VIEWER_TABLE_HOTFIXED" then
        Notify("hotfix")
    elseif event == "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED" then
        Notify("override", arg1, arg2)
    end
end)

local _securecall = securecallfunction or function(fn, ...) return fn(...) end
local function _OnSettingsRefreshLayout() Notify("refresh_layout") end

local _refreshLayoutHooked = false
local function InstallRefreshLayoutHook()
    if _refreshLayoutHooked then return end
    if not (CooldownViewerSettings and CooldownViewerSettings.RefreshLayout) then return end
    local ok = pcall(hooksecurefunc, CooldownViewerSettings, "RefreshLayout", function(...)
        _securecall(_OnSettingsRefreshLayout, ...)
    end)
    if ok then _refreshLayoutHooked = true end
end

InstallRefreshLayoutHook()
local _hookFrame = CreateFrame("Frame")
_hookFrame:RegisterEvent("PLAYER_LOGIN")
_hookFrame:SetScript("OnEvent", function(self)
    InstallRefreshLayoutHook()
    if _refreshLayoutHooked then
        self:UnregisterAllEvents()
    end
end)

local function BuildOrderedMaps()
    if _orderedSpellMap and _orderedMapsVersion == _version then
        return
    end

    local provider = CooldownViewerSettings and CooldownViewerSettings.GetDataProvider
        and CooldownViewerSettings:GetDataProvider()
    local displayData = provider and not provider.displayDataDirty and provider.displayData
    local ordered = type(displayData) == "table" and displayData.orderedCooldownIDs
    local infoByID = type(displayData) == "table" and displayData.cooldownInfoByID
    if provider and (type(ordered) ~= "table" or type(infoByID) ~= "table") then
        if not _orderedSpellMap then
            _orderedSpellMap, _orderedEquipSlotMap, _orderedCategoryMap = {}, {}, {}
            _orderedSpellMapByCategory, _orderedEquipSlotMapByCategory, _orderedCategoryMapByCategory =
                {}, {}, {}
        end
        return
    end

    local spellMap, equipSlotMap, categoryMap = {}, {}, {}
    local spellMapByCategory, equipSlotMapByCategory, categoryMapByCategory = {}, {}, {}
    _orderedSpellMap = spellMap
    _orderedEquipSlotMap = equipSlotMap
    _orderedCategoryMap = categoryMap
    _orderedSpellMapByCategory = spellMapByCategory
    _orderedEquipSlotMapByCategory = equipSlotMapByCategory
    _orderedCategoryMapByCategory = categoryMapByCategory
    _orderedMapsVersion = _version

    if not (CooldownViewerSettings and CooldownViewerSettings.GetDataProvider) then
        return
    end
    local api = GetCooldownViewerAPI()
    if not (api and api.GetCooldownViewerCooldownInfo) then
        return
    end
    if not provider then
        return
    end
    if not (Enum and Enum.CooldownViewerCategory) then return end

    local visibleCats = {
        Enum.CooldownViewerCategory.TrackedBuff,
        Enum.CooldownViewerCategory.TrackedBar,
        Enum.CooldownViewerCategory.Essential,
        Enum.CooldownViewerCategory.Utility,
    }
    for _, cat in ipairs(visibleCats) do
        if cat ~= nil then
            local catSpellMap = {}
            local catEquipSlotMap = {}
            local catCategoryMap = {}
            spellMapByCategory[cat] = catSpellMap
            equipSlotMapByCategory[cat] = catEquipSlotMap
            categoryMapByCategory[cat] = catCategoryMap
            for _, cdID in ipairs(ordered) do
                local snapshotInfo = infoByID[cdID]
                if snapshotInfo and snapshotInfo.category == cat
                    and not (_G.CDM_HIDE_INVISIBLE_ITEMS and snapshotInfo.isInvisible) then
                    local info = api.GetCooldownViewerCooldownInfo(cdID)
                    if info then
                        local entry = { cooldownID = cdID, category = cat }
                        local equipSlot = info.equipSlot
                        if type(equipSlot) == "number"
                            and not issecretvalue(equipSlot)
                            and not equipSlotMap[equipSlot] then
                            equipSlotMap[equipSlot] = entry
                        end
                        if type(equipSlot) == "number"
                            and not issecretvalue(equipSlot)
                            and not catEquipSlotMap[equipSlot] then
                            catEquipSlotMap[equipSlot] = entry
                        end
                        local spellCategoryID = info.spellCategoryID
                        if type(spellCategoryID) == "number"
                            and not issecretvalue(spellCategoryID)
                            and not categoryMap[spellCategoryID] then
                            categoryMap[spellCategoryID] = entry
                        end
                        if type(spellCategoryID) == "number"
                            and not issecretvalue(spellCategoryID)
                            and not catCategoryMap[spellCategoryID] then
                            catCategoryMap[spellCategoryID] = entry
                        end
                        CDMIndex.ForEachCooldownInfoID(info, function(id)
                            local b = CDMIndex.ToBaseSpellID(id)
                            if b and not spellMap[b] then
                                spellMap[b] = entry
                            end
                            if b and not catSpellMap[b] then
                                catSpellMap[b] = entry
                            end
                        end)
                    end
                end
            end
        end
    end
end

function CDMIndex.GetOrderedSpellMap()
    BuildOrderedMaps()
    return _orderedSpellMap
end

function CDMIndex.GetOrdered(spellID)
    local base = CDMIndex.ToBaseSpellID(spellID)
    if not base then return nil end
    return CDMIndex.GetOrderedSpellMap()[base]
end

local function GetCategoryForContainerKey(containerKey)
    if not (Enum and Enum.CooldownViewerCategory) then return nil end
    local E = Enum.CooldownViewerCategory
    if containerKey == "essential" then return E.Essential end
    if containerKey == "utility" then return E.Utility end
    if containerKey == "buff" then return E.TrackedBuff end
    if containerKey == "trackedBar" then return E.TrackedBar end
    return nil
end

function CDMIndex.GetOrderedForContainer(containerKey, spellID)
    local cat = GetCategoryForContainerKey(containerKey)
    if cat == nil then return nil end
    local base = CDMIndex.ToBaseSpellID(spellID)
    if not base then return nil end
    BuildOrderedMaps()
    local byCategory = _orderedSpellMapByCategory and _orderedSpellMapByCategory[cat]
    return byCategory and byCategory[base] or nil
end

function CDMIndex.GetOrderedByEquipSlot(equipSlot)
    if type(equipSlot) ~= "number" or issecretvalue(equipSlot) then return nil end
    BuildOrderedMaps()
    return _orderedEquipSlotMap[equipSlot]
end

function CDMIndex.GetOrderedByCategory(spellCategoryID)
    if type(spellCategoryID) ~= "number" or issecretvalue(spellCategoryID) then return nil end
    BuildOrderedMaps()
    return _orderedCategoryMap[spellCategoryID]
end

function CDMIndex.GetOrderedByEquipSlotForContainer(containerKey, equipSlot)
    if type(equipSlot) ~= "number" or issecretvalue(equipSlot) then return nil end
    local cat = GetCategoryForContainerKey(containerKey)
    if cat == nil then return nil end
    BuildOrderedMaps()
    local byCategory = _orderedEquipSlotMapByCategory and _orderedEquipSlotMapByCategory[cat]
    return byCategory and byCategory[equipSlot] or nil
end

function CDMIndex.GetOrderedByCategoryForContainer(containerKey, spellCategoryID)
    if type(spellCategoryID) ~= "number" or issecretvalue(spellCategoryID) then return nil end
    local cat = GetCategoryForContainerKey(containerKey)
    if cat == nil then return nil end
    BuildOrderedMaps()
    local byCategory = _orderedCategoryMapByCategory and _orderedCategoryMapByCategory[cat]
    return byCategory and byCategory[spellCategoryID] or nil
end
