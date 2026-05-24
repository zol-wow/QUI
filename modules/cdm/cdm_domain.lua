-- cdm_domain.lua
-- Consolidated CDM domain facts. Former file chunks remain scoped to preserve Lua 5.1 local limits.
do
-- Inlined from cdm_shared.lua
local _, ns = ...

---------------------------------------------------------------------------
-- CDM Shared Helpers
--
-- Small CDM-specific helpers used across runtime modules. Addon-wide helpers
-- stay in core/utils.lua; this file only owns cooldown-manager primitives.
---------------------------------------------------------------------------

local CDMShared = {}
ns.CDMShared = CDMShared

local type = type
local _G = _G
local issecretvalue = issecretvalue

local Helpers = ns.Helpers

CDMShared.BUILTIN_CONTAINER_KEYS = { "essential", "utility", "buff", "trackedBar" }
CDMShared.BUILTIN_COOLDOWN_CONTAINER_KEYS = { "essential", "utility" }
CDMShared.BUILTIN_AURA_CONTAINER_KEYS = { "buff", "trackedBar" }
CDMShared.BUILTIN_ICON_CONTAINER_KEYS = { "essential", "utility", "buff" }
CDMShared.BUILTIN_BAR_CONTAINER_KEYS = { "trackedBar" }

CDMShared.BUILTIN_CONTAINER_LABELS = {
    essential  = "Essential",
    utility    = "Utility",
    buff       = "Buff Icons",
    trackedBar = "Buff Bars",
}

-- Legacy persisted container type: describes the historical entry family,
-- not the renderer shape. New layout code should prefer container shape.
CDMShared.BUILTIN_CONTAINER_TYPES = {
    essential  = "cooldown",
    utility    = "cooldown",
    buff       = "aura",
    trackedBar = "auraBar",
}

CDMShared.BUILTIN_CONTAINER_SHAPES = {
    essential  = "icon",
    utility    = "icon",
    buff       = "icon",
    trackedBar = "bar",
}

local BUILTIN_CONTAINER_SET = {
    essential = true,
    utility = true,
    buff = true,
    trackedBar = true,
}

function CDMShared.IsBuiltinContainerKey(containerKey)
    return BUILTIN_CONTAINER_SET[containerKey] == true
end

function CDMShared.GetBuiltinContainerLabel(containerKey)
    return CDMShared.BUILTIN_CONTAINER_LABELS[containerKey]
end

function CDMShared.GetBuiltinContainerType(containerKey)
    return CDMShared.BUILTIN_CONTAINER_TYPES[containerKey]
end

function CDMShared.GetBuiltinContainerShape(containerKey)
    return CDMShared.BUILTIN_CONTAINER_SHAPES[containerKey]
end

function CDMShared.GetEntryKindForContainerType(containerType)
    if containerType == "cooldown" then return "cooldown" end
    if containerType == "aura" or containerType == "auraBar" then return "aura" end
    return nil
end

function CDMShared.GetBuiltinContainerEntryKind(containerKey)
    return CDMShared.GetEntryKindForContainerType(
        CDMShared.GetBuiltinContainerType(containerKey))
end

function CDMShared.ResolveKindForItemsTab(containerKey)
    local builtinKind = CDMShared.GetBuiltinContainerEntryKind(containerKey)
    if builtinKind == "aura" then return "aura" end
    return "cooldown"
end

function CDMShared.ShouldShowItemDisplayModeRow(entry, containerKey, containerDB)
    if type(entry) ~= "table" then return false end
    local etype = entry.type
    if etype ~= "item" and etype ~= "trinket" and etype ~= "slot" then
        return false
    end
    if CDMShared.IsBuiltinContainerKey(containerKey) then return false end
    if not CDMShared.IsCustomBarContainer(containerDB) then return false end
    return true
end

function CDMShared.GetBuiltinContainerKeysByEntryKind(entryKind)
    if entryKind == "cooldown" then
        return CDMShared.BUILTIN_COOLDOWN_CONTAINER_KEYS
    end
    if entryKind == "aura" then
        return CDMShared.BUILTIN_AURA_CONTAINER_KEYS
    end
    return nil
end

function CDMShared.GetBuiltinContainerKeysByShape(shape)
    if shape == "icon" then
        return CDMShared.BUILTIN_ICON_CONTAINER_KEYS
    end
    if shape == "bar" then
        return CDMShared.BUILTIN_BAR_CONTAINER_KEYS
    end
    return nil
end

function CDMShared.IsBuiltinCooldownContainerKey(containerKey)
    return CDMShared.GetBuiltinContainerEntryKind(containerKey) == "cooldown"
end

function CDMShared.IsBuiltinAuraContainerKey(containerKey)
    return CDMShared.GetBuiltinContainerEntryKind(containerKey) == "aura"
end

function CDMShared.IsBuiltinIconContainerKey(containerKey)
    return CDMShared.GetBuiltinContainerShape(containerKey) == "icon"
end

function CDMShared.IsBuiltinBarContainerKey(containerKey)
    return CDMShared.GetBuiltinContainerShape(containerKey) == "bar"
end

function CDMShared.IsCustomBarContainer(containerDB)
    return type(containerDB) == "table" and containerDB.containerType == "customBar"
end

function CDMShared.NormalizeCustomBarVisibilityFlags(containerDB)
    if not CDMShared.IsCustomBarContainer(containerDB) then return "always" end

    if containerDB.desaturateOnCooldown == nil then
        containerDB.desaturateOnCooldown = true
    end

    local mode = "always"
    if containerDB.showOnlyOnCooldown then
        mode = "onCooldown"
        containerDB.showOnlyWhenActive = false
        containerDB.showOnlyWhenOffCooldown = false
    elseif containerDB.showOnlyWhenActive then
        mode = "active"
        containerDB.showOnlyWhenOffCooldown = false
    elseif containerDB.showOnlyWhenOffCooldown then
        mode = "offCooldown"
    end

    containerDB.visibilityMode = mode

    if mode ~= "onCooldown" then
        containerDB.noDesaturateWithCharges = false
    end

    if containerDB.dynamicLayout == nil then
        containerDB.dynamicLayout = false
    end
    if containerDB.dynamicLayout and containerDB.clickableIcons then
        containerDB.clickableIcons = false
    end

    containerDB.tooltipContext = containerDB.tooltipContext or "customTrackers"
    containerDB.keybindContext = containerDB.keybindContext or "customTrackers"

    return mode
end

function CDMShared.GetCustomBarVisibilityMode(containerDB)
    if not CDMShared.IsCustomBarContainer(containerDB) then return "always" end
    return CDMShared.NormalizeCustomBarVisibilityFlags(containerDB)
end

function CDMShared.NormalizeMirrorCategory(category)
    if issecretvalue and issecretvalue(category) then return nil end
    if category == "essential"
        or category == "utility"
        or category == "buff"
        or category == "trackedBar" then
        return category
    end
    return nil
end

function CDMShared.IsAuraMirrorCategory(category)
    category = CDMShared.NormalizeMirrorCategory(category)
    return category == "buff" or category == "trackedBar"
end

function CDMShared.IsCooldownMirrorCategory(category)
    category = CDMShared.NormalizeMirrorCategory(category)
    return category == "essential" or category == "utility"
end

function CDMShared.IsRuntimeEnabled()
    local checker = _G.QUI_IsCDMMasterEnabled
    if type(checker) == "function" then
        return checker() ~= false
    end
    local ncdm = CDMShared.GetNcdmDB()
    return not ncdm or ncdm.enabled ~= false
end

function CDMShared.GetCore()
    if Helpers and Helpers.GetCore then
        local core = Helpers.GetCore()
        if core then return core end
    end
    return ns.Addon or _G.QUI
end

function CDMShared.GetNcdmDB()
    local core = CDMShared.GetCore()
    local db = core and core.db
    local profile = db and db.profile
    return profile and profile.ncdm or nil
end

function CDMShared.GetContainerDB(containerKey)
    local ncdm = CDMShared.GetNcdmDB()
    if not ncdm or type(containerKey) ~= "string" or containerKey == "" then
        return nil
    end
    if ncdm[containerKey] then
        return ncdm[containerKey]
    end
    return ncdm.containers and ncdm.containers[containerKey] or nil
end

function CDMShared.GetContainerType(containerKey, containerDB)
    local builtinType = CDMShared.GetBuiltinContainerType(containerKey)
    if builtinType then
        return builtinType
    end

    local db = containerDB or CDMShared.GetContainerDB(containerKey)
    return type(db) == "table" and db.containerType or nil
end

function CDMShared.GetContainerShape(containerKey, containerDB)
    local db = containerDB or CDMShared.GetContainerDB(containerKey)
    if type(db) == "table" then
        local shape = db.shape
        if shape == "icon" or shape == "bar" then
            return shape
        end
    end

    local builtinShape = CDMShared.GetBuiltinContainerShape(containerKey)
    if builtinShape then
        return builtinShape
    end

    if type(db) == "table" and db.containerType == "auraBar" then
        return "bar"
    end

    return "icon"
end

function CDMShared.GetContainerEntryKind(containerKey, containerDB)
    local builtinKind = CDMShared.GetBuiltinContainerEntryKind(containerKey)
    if builtinKind then
        return builtinKind
    end

    return CDMShared.GetEntryKindForContainerType(
        CDMShared.GetContainerType(containerKey, containerDB))
end

function CDMShared.IsSafeNumeric(value)
    if issecretvalue and issecretvalue(value) then
        return false
    end
    return type(value) == "number"
end

function CDMShared.SafeBoolean(value)
    if issecretvalue and issecretvalue(value) then
        return nil
    end
    if type(value) == "boolean" then
        return value
    end
    return nil
end

function CDMShared.SettingEnabled(value, fallback)
    if value == nil then
        return fallback == true
    end
    return value == true
end
end

do
-- Inlined from cdm_index.lua
local _, ns = ...

---------------------------------------------------------------------------
-- CDM Index — single source of truth for CDM spell-ID alias walking,
-- base-ID normalization, cross-event invalidation, and the
-- RefreshLayout silent-mutation gap.
--
-- Loads early in cdm.xml so every other CDM file can depend on it.
--
-- API:
--   ns.CDMIndex.ForEachCooldownInfoID(info, callback)
--     Walks overrideTooltipSpellID, overrideSpellID, spellID, then every
--     linkedSpellIDs[i]. Single canonical alias walk; every consumer
--     uses this so no field can be silently missed.
--
--   ns.CDMIndex.IsUsableID(id) -> bool
--     Returns false for nil, non-number, <= 0, or secret-tagged IDs.
--     Used as a key-validity gate at index-build time only — never on
--     a per-tick combat path.
--
--   ns.CDMIndex.ToBaseSpellID(id) -> baseID or nil
--     source-facade base spell lookup with raw-id fallback. Returns
--     nil if the input is not usable.
--
--   ns.CDMIndex.Get(spellID) -> entry or nil
--     entry = { cooldownID, category, primarySpellID, aliases = {} }.
--     Every aliased spellID for one cooldown returns the SAME entry
--     table (identity equality), so callers can compare entries with ==.
--
--   ns.CDMIndex.Version() -> number
--     Monotonic counter; increments on every wipe so consumers can
--     detect staleness.
--
--   ns.CDMIndex.Subscribe(name, callback, priority)
--   ns.CDMIndex.Unsubscribe(name)
--     Single broker for COOLDOWN_VIEWER_TABLE_HOTFIXED,
--     COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED, COOLDOWN_VIEWER_DATA_LOADED,
--     and CooldownViewerSettings:RefreshLayout (no public event).
--     Subscribers fire in ascending priority order on each invalidation.
---------------------------------------------------------------------------

local CDMIndex = {}
ns.CDMIndex = CDMIndex

local ipairs = ipairs
local pairs = pairs
local type = type
local wipe = wipe

-- issecretvalue is global on 12.0+. Stub when running outside WoW (the
-- profile test harness loads no CDM code, so this is defensive only).
local issecretvalue = issecretvalue or function() return false end

local function GetCooldownViewerAPI()
    return _G.C_CooldownViewer
end

local function GetSources()
    return ns.CDMSources
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

function CDMIndex.IsUsableID(id)
    if id == nil or type(id) ~= "number" then return false end
    if issecretvalue(id) then return false end
    return id > 0
end

function CDMIndex.ToBaseSpellID(id)
    if not CDMIndex.IsUsableID(id) then return nil end
    local Sources = GetSources()
    local base = Sources and Sources.QueryBaseSpell and Sources.QueryBaseSpell(id)
    if not CDMIndex.IsUsableID(base) then return id end
    return base
end

-- Centralized alias walk. Order matters for some callers (icon factory
-- probes overrideTooltipSpellID first as the "preferred display" ID);
-- preserve override -> tooltip -> spell -> linked.
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

---------------------------------------------------------------------------
-- Index — populated lazily and on broker invalidation
---------------------------------------------------------------------------

local _spellIndex = {}      -- baseID -> entry (entry shared across aliases)
local _version = 0
local _built = false
local _orderedSpellMap = nil
local _orderedSpellMapVersion = -1

function CDMIndex.Version() return _version end

local CATEGORIES_FOR_INDEX = nil  -- populated lazily once Enum is available

local function GetIndexCategories()
    if CATEGORIES_FOR_INDEX then return CATEGORIES_FOR_INDEX end
    if not (Enum and Enum.CooldownViewerCategory) then return nil end
    local E = Enum.CooldownViewerCategory
    -- Tracked first so they claim canonical entries before Essential/Utility
    -- duplicates: the same spell can appear in Essential as a cooldown and
    -- in TrackedBuff as its buff. The buff entry is the one consumers
    -- usually want when they ask "what does this aura belong to".
    CATEGORIES_FOR_INDEX = {
        E.TrackedBuff,
        E.TrackedBar,
        E.Essential,
        E.Utility,
        E.HiddenSpell,
        E.HiddenAura,
    }
    return CATEGORIES_FOR_INDEX
end

function CDMIndex.Rebuild()
    wipe(_spellIndex)
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
                            if primaryBase then
                                local entry = {
                                    cooldownID     = cdID,
                                    category       = cat,
                                    primarySpellID = primaryBase,
                                    aliases        = {},
                                }
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

---------------------------------------------------------------------------
-- Broker — subscribers fire in ascending priority on every invalidation
---------------------------------------------------------------------------

-- Subscribers: { name = string, cb = function, priority = number }
-- Sorted on every insert; sweep on every notify.
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
    -- Replace if same name already subscribed (idempotent during reload-paths).
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

-- Reason is a short string ("hotfix", "override", "data_loaded",
-- "refresh_layout", "manual"). Subscribers may inspect it.
local function Notify(reason, ...)
    -- Wipe BEFORE notifying so subscribers' first lookup repopulates
    -- with a coherent index. _built=false forces lazy rebuild on next Get.
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

---------------------------------------------------------------------------
-- Event sources — fan out to the broker
---------------------------------------------------------------------------

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
        -- arg1, arg2 = baseSpellID, overrideSpellID
        Notify("override", arg1, arg2)
    end
end)

---------------------------------------------------------------------------
-- RefreshLayout silent-mutation hook
---------------------------------------------------------------------------
-- CDM's settings UI fires no public event for category drag-drop, and
-- programmatic SetCooldownToCategory calls are similarly silent. Both
-- routes go through CooldownViewerSettings:RefreshLayout. Hooking it
-- closes the gap so the broker invalidates on those mutations the same
-- as it does for hotfix / override events.
local _refreshLayoutHooked = false
local function InstallRefreshLayoutHook()
    if _refreshLayoutHooked then return end
    if not (CooldownViewerSettings and CooldownViewerSettings.RefreshLayout) then return end
    local ok = pcall(hooksecurefunc, CooldownViewerSettings, "RefreshLayout", function()
        Notify("refresh_layout")
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

---------------------------------------------------------------------------
-- Ordered map — what CDM is currently RENDERING (per the user's ordering
-- and visibility), as distinct from CDMIndex.Get above which answers
-- "what does CDM KNOW about" (incl. HiddenSpell / HiddenAura entries
-- the user has hidden).
--
-- Use ordered for icon-binding and overlay decisions ("is this cooldown
-- visible to the user right now?"). Use the index for spell-metadata
-- and override resolution ("does this cooldown exist at all?").
--
-- Returned map: baseID -> { cooldownID, category }. Built fresh on each
-- call — callers can rebuild after a "refresh_layout" notification.
---------------------------------------------------------------------------
function CDMIndex.GetOrderedSpellMap()
    if _orderedSpellMap and _orderedSpellMapVersion == _version then
        return _orderedSpellMap
    end

    local map = {}
    _orderedSpellMap = map
    _orderedSpellMapVersion = _version

    if not (CooldownViewerSettings and CooldownViewerSettings.GetDataProvider) then
        return map
    end
    local api = GetCooldownViewerAPI()
    if not (api and api.GetCooldownViewerCooldownInfo) then
        return map
    end
    local provider = CooldownViewerSettings:GetDataProvider()
    if not (provider and provider.GetOrderedCooldownIDsForCategory) then
        return map
    end
    if not (Enum and Enum.CooldownViewerCategory) then return map end

    local visibleCats = {
        Enum.CooldownViewerCategory.TrackedBuff,
        Enum.CooldownViewerCategory.TrackedBar,
        Enum.CooldownViewerCategory.Essential,
        Enum.CooldownViewerCategory.Utility,
    }
    for _, cat in ipairs(visibleCats) do
        if cat ~= nil then
            local ids = provider.GetOrderedCooldownIDsForCategory(provider, cat, true)
            if ids then
                for _, cdID in ipairs(ids) do
                    local info = api.GetCooldownViewerCooldownInfo(cdID)
                    if info then
                        local entry = { cooldownID = cdID, category = cat }
                        CDMIndex.ForEachCooldownInfoID(info, function(id)
                            local b = CDMIndex.ToBaseSpellID(id)
                            if b and not map[b] then
                                map[b] = entry
                            end
                        end)
                    end
                end
            end
        end
    end
    return map
end

-- Convenience: return the ordered entry for a single spellID, or nil.
function CDMIndex.GetOrdered(spellID)
    local base = CDMIndex.ToBaseSpellID(spellID)
    if not base then return nil end
    return CDMIndex.GetOrderedSpellMap()[base]
end

-- Cheap "is this cooldown actually being rendered to the user right
-- now?" check used by overlay/binding decisions that should not act on
-- hidden cooldowns.
function CDMIndex.IsRendered(spellID)
    return CDMIndex.GetOrdered(spellID) ~= nil
end
end

do
-- Inlined from cdm_catalog.lua
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

function CDMCatalog.GetCategorySet(category, allowUnlearned)
    if not HasCooldownViewerAPI() then return nil end
    local api = GetCooldownViewerAPI()
    local ok, ids = pcall(api.GetCooldownViewerCategorySet, category, allowUnlearned and true or false)
    if ok and type(ids) == "table" then
        return ids
    end
    return nil
end

function CDMCatalog.GetTrackedCategorySet(category, allowUnlearned)
    local settings = _G.CooldownViewerSettings
    if settings and settings.GetDataProvider then
        local okProvider, provider = pcall(settings.GetDataProvider, settings)
        if okProvider
            and provider
            and provider.GetOrderedCooldownIDsForCategory then
            local ok, ids = pcall(
                provider.GetOrderedCooldownIDsForCategory,
                provider,
                category,
                allowUnlearned and true or false)
            if ok and type(ids) == "table" then
                return ids, true
            end
        end
    end

    local ids = CDMCatalog.GetCategorySet(category, allowUnlearned)
    return ids, ids ~= nil and #ids > 0
end

function CDMCatalog.GetCooldownInfo(cooldownID)
    if not HasCooldownViewerAPI() or not cooldownID then return nil end
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
    for _, cdID in ipairs(cooldownIDs) do
        local info = CDMCatalog.GetCooldownInfo(cdID)
        local sid = SelectPreferredSpellID(info, isAuraCategory)
        if sid and not seen[sid] then
            seen[sid] = true
            entries[#entries + 1] = { type = "spell", id = sid }
        end
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
end
