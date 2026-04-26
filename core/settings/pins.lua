local ADDON_NAME, ns = ...

local Settings = ns.Settings or {}
ns.Settings = Settings

local Pins = Settings.Pins or {}
Settings.Pins = Pins

local abs = math.abs
local ipairs = ipairs
local next = next
local pairs = pairs
local pcall = pcall
local rawget = rawget
local setmetatable = setmetatable
local table_insert = table.insert
local table_remove = table.remove
local tonumber = tonumber
local tostring = tostring
local type = type
local wipe = wipe

local PIN_STORE_VERSION = 1
local STALE_MISS_LIMIT = 3

Pins._subscribers = Pins._subscribers or {}
Pins._subscriptionSeq = Pins._subscriptionSeq or 0
Pins._profilePathCache = Pins._profilePathCache or setmetatable({}, { __mode = "k" })
Pins._autoApplySuppressed = Pins._autoApplySuppressed or 0

local function GetTimeStamp()
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok and type(value) == "number" then
            return value
        end
    end
    return 0
end

local function DebugLog(...)
    local addon = _G.QUI
    if addon and type(addon.DebugPrint) == "function" then
        addon:DebugPrint(...)
    end
end

local function CloneValue(value, seen)
    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] then
        return seen[value]
    end

    local copy = {}
    seen[value] = copy
    for key, nestedValue in pairs(value) do
        copy[CloneValue(key, seen)] = CloneValue(nestedValue, seen)
    end
    return copy
end

local function SplitPath(path)
    local segments = {}
    if type(path) ~= "string" or path == "" then
        return segments
    end

    for segment in path:gmatch("[^.]+") do
        segments[#segments + 1] = segment
    end

    return segments
end

local function JoinPath(base, leaf)
    if type(base) ~= "string" or base == "" then
        return leaf
    end
    if type(leaf) ~= "string" or leaf == "" then
        return base
    end
    return base .. "." .. leaf
end

local function IsNumberLike(value)
    return type(value) == "number" and value == value
end

local function IsColorValue(value)
    if type(value) ~= "table" then
        return false
    end

    if not IsNumberLike(value[1]) or not IsNumberLike(value[2]) or not IsNumberLike(value[3]) then
        return false
    end

    if value[4] ~= nil and not IsNumberLike(value[4]) then
        return false
    end

    for key, _ in pairs(value) do
        if type(key) ~= "number" or key < 1 or key > 4 then
            return false
        end
    end

    return true
end

local function IsSupportedPinnedValue(value)
    local valueType = type(value)
    if valueType == "boolean" or valueType == "number" or valueType == "string" then
        return true
    end
    return IsColorValue(value)
end

local function EnsureTable(parent, key)
    local child = parent[key]
    if type(child) ~= "table" then
        child = {}
        parent[key] = child
    end
    return child
end

local function IsPathExactOrNested(path, candidate)
    if type(path) ~= "string" or path == "" or type(candidate) ~= "string" or candidate == "" then
        return false
    end
    if path == candidate then
        return true
    end
    return path:sub(1, #candidate + 1) == (candidate .. ".")
end

local function ReadPath(root, path)
    if type(root) ~= "table" or type(path) ~= "string" or path == "" then
        return nil, false
    end

    local current = root
    local segments = SplitPath(path)
    for _, segment in ipairs(segments) do
        if type(current) ~= "table" then
            return nil, false
        end
        local nextValue = current[segment]
        if nextValue == nil then
            return nil, false
        end
        current = nextValue
    end

    return current, true
end

local function WritePath(root, path, value)
    if type(root) ~= "table" or type(path) ~= "string" or path == "" then
        return false, "invalid root or path"
    end

    local segments = SplitPath(path)
    if #segments == 0 then
        return false, "empty path"
    end

    local parent = root
    for index = 1, #segments - 1 do
        local segment = segments[index]
        local nextValue = parent[segment]
        if nextValue == nil then
            nextValue = {}
            parent[segment] = nextValue
        elseif type(nextValue) ~= "table" then
            return false, "non-table segment"
        end
        parent = nextValue
    end

    parent[segments[#segments]] = CloneValue(value)
    return true
end

local function RemovePath(root, path)
    if type(root) ~= "table" or type(path) ~= "string" or path == "" then
        return false
    end

    local segments = SplitPath(path)
    if #segments == 0 then
        return false
    end

    local parent = root
    for index = 1, #segments - 1 do
        parent = parent and parent[segments[index]]
        if type(parent) ~= "table" then
            return false
        end
    end

    parent[segments[#segments]] = nil
    return true
end

local function GetCurrentDB()
    if _G.QUI and _G.QUI.db then
        return _G.QUI.db
    end
    if ns.Addon and ns.Addon.db then
        return ns.Addon.db
    end
    return nil
end

local UNIT_FRAMES_SEARCH_CONTEXT = {
    tabIndex = 5,
    tabName = "Unit Frames",
    tileId = "unit_frames",
    subPageIndex = 1,
}

local UNIT_FRAMES_SUBTAB_INDEX = {
    player = 2,
    target = 3,
    targettarget = 4,
    pet = 5,
    focus = 6,
    boss = 7,
}

local UNIT_FRAMES_FEATURE_ROUTE = {
    unitFramesFrameTab = { surfaceTabKey = "frame", subTabName = "Frame" },
    unitFramesBarsTab = { surfaceTabKey = "bars", subTabName = "Bars" },
    unitFramesTextTab = { surfaceTabKey = "text", subTabName = "Text" },
    unitFramesIconsTab = { surfaceTabKey = "icons", subTabName = "Icons" },
    unitFramesPortraitTab = { surfaceTabKey = "portrait", subTabName = "Portrait" },
    unitFramesIndicatorsTab = { surfaceTabKey = "indicators", subTabName = "Indicators" },
    unitFramesPrivateAurasTab = { surfaceTabKey = "privateAuras", subTabName = "Priv. Auras" },
}

local function ResolveFeatureRouteFromPath(path)
    if type(path) ~= "string" or path == "" then
        return nil
    end

    local featureId = path:match("^([^.]+)")
    if type(featureId) ~= "string" or featureId == "" then
        return nil
    end

    if featureId == "unitFramesGeneralTab" then
        return {
            featureId = "unitFramesPage",
            tabIndex = UNIT_FRAMES_SEARCH_CONTEXT.tabIndex,
            tabName = UNIT_FRAMES_SEARCH_CONTEXT.tabName,
            subTabIndex = 1,
            subTabName = "General",
            tileId = UNIT_FRAMES_SEARCH_CONTEXT.tileId,
            subPageIndex = UNIT_FRAMES_SEARCH_CONTEXT.subPageIndex,
            surfaceTabKey = "general",
        }
    end

    local unitFeatureId, unitKey = featureId:match("^(unitFrames[%a]+Tab):(.-)$")
    local unitRoute = unitFeatureId and UNIT_FRAMES_FEATURE_ROUTE[unitFeatureId] or nil
    if unitRoute and type(unitKey) == "string" and unitKey ~= "" then
        return {
            featureId = "unitFramesPage",
            tabIndex = UNIT_FRAMES_SEARCH_CONTEXT.tabIndex,
            tabName = UNIT_FRAMES_SEARCH_CONTEXT.tabName,
            subTabIndex = UNIT_FRAMES_SUBTAB_INDEX[unitKey] or 2,
            subTabName = unitRoute.subTabName,
            tileId = UNIT_FRAMES_SEARCH_CONTEXT.tileId,
            subPageIndex = UNIT_FRAMES_SEARCH_CONTEXT.subPageIndex,
            surfaceTabKey = unitRoute.surfaceTabKey,
            surfaceUnitKey = unitKey,
        }
    end

    local nav = Settings and Settings.Nav
    local route = nav and type(nav.GetRoute) == "function" and nav:GetRoute(featureId) or nil
    if type(route) ~= "table" then
        return nil
    end

    local resolved = {
        featureId = featureId,
    }
    if type(route.tileId) == "string" and route.tileId ~= "" then
        resolved.tileId = route.tileId
    end
    if route.subPageIndex ~= nil then
        resolved.subPageIndex = route.subPageIndex
    end

    if next(resolved) == nil then
        return nil
    end

    return resolved
end

local function NormalizeStore(store)
    if type(store) ~= "table" then
        return nil
    end
    if type(store.entries) ~= "table" then
        store.entries = {}
    end
    if type(store._version) ~= "number" then
        store._version = PIN_STORE_VERSION
    end
    if type(store._updatedAt) ~= "number" then
        store._updatedAt = 0
    end
    return store
end

local function GetStore(db, create)
    db = db or GetCurrentDB()
    if not db then
        return nil
    end

    local globalDB = db.global
    if type(globalDB) ~= "table" then
        if not create then
            return nil
        end
        globalDB = {}
        db.global = globalDB
    end

    local store = globalDB.pinnedSettings
    if type(store) ~= "table" then
        if not create then
            return nil
        end
        store = {
            _version = PIN_STORE_VERSION,
            _updatedAt = 0,
            entries = {},
        }
        globalDB.pinnedSettings = store
    end

    return NormalizeStore(store)
end

local function TouchStore(store)
    if type(store) ~= "table" then
        return
    end
    store._updatedAt = GetTimeStamp()
end

local function SafeForEachEntry(store, callback)
    if type(store) ~= "table" or type(store.entries) ~= "table" or type(callback) ~= "function" then
        return
    end

    for path, entry in pairs(store.entries) do
        local ok, result = pcall(callback, path, entry)
        if not ok then
            DebugLog("Pinned settings callback failed for", tostring(path), tostring(result))
        end
    end
end

function Pins:GetStore(db, create)
    return GetStore(db, create)
end

function Pins:InvalidatePathCache()
    self._profilePathCache = setmetatable({}, { __mode = "k" })
end

function Pins:BuildPath(featureId, sectionId, field)
    if type(field) ~= "table" then
        return nil
    end

    if type(field.pinPath) == "string" and field.pinPath ~= "" then
        return field.pinPath
    end

    if type(featureId) ~= "string" or featureId == ""
        or type(sectionId) ~= "string" or sectionId == "" then
        return nil
    end

    local key = field.key or field.dbKey
    if type(key) ~= "string" or key == "" then
        return nil
    end

    return featureId .. "." .. sectionId .. "." .. key
end

function Pins:IsFieldPinnable(field, ctx)
    if type(field) ~= "table" then
        return false
    end

    if field.kind == "button" then
        return false
    end

    if field.kind == "custom" then
        return field.pinnable == true and type(field.pinGet) == "function" and type(field.pinSet) == "function"
    end

    if field.pinnable == false then
        return false
    end

    local kind = field.kind
    if kind ~= "checkbox" and kind ~= "slider" and kind ~= "dropdown" and kind ~= "color" then
        return false
    end

    local featureId = ctx and ctx.feature and ctx.feature.id or nil
    local sectionId = ctx and ctx.sectionId or nil
    local path = self:BuildPath(featureId, sectionId, field)
    if type(path) ~= "string" or path == "" then
        return false
    end

    return self:IsPathPinnable(path, kind)
end

function Pins:IsPathPinnable(path, kind, value)
    if type(path) ~= "string" or path == "" then
        return false
    end

    if kind == "button" or kind == "editbox" then
        return false
    end

    if kind ~= nil and kind ~= "checkbox" and kind ~= "slider" and kind ~= "dropdown" and kind ~= "color" then
        return false
    end

    local segments = SplitPath(path)
    if #segments == 0 then
        return false
    end

    if segments[1] == "frameAnchoring" then
        return false
    end

    for _, segment in ipairs(segments) do
        if segment == "pos" then
            return false
        end
        if segment:sub(1, 1) == "_" then
            return false
        end
    end

    if value ~= nil and not IsSupportedPinnedValue(value) then
        return false
    end

    return true
end

function Pins:GetCurrentProfileName(db)
    db = db or GetCurrentDB()
    if not db or type(db.GetCurrentProfile) ~= "function" then
        return nil
    end
    local ok, profileName = pcall(db.GetCurrentProfile, db)
    if ok and type(profileName) == "string" and profileName ~= "" then
        return profileName
    end
    return nil
end

function Pins:ResolveProfileTablePath(targetTable, db)
    db = db or GetCurrentDB()
    if type(targetTable) ~= "table" or not db then
        return nil
    end

    local profile = db.profile
    if type(profile) ~= "table" then
        return nil
    end

    if targetTable == profile then
        return ""
    end

    local cached = self._profilePathCache[targetTable]
    if type(cached) == "string" then
        return cached
    end

    -- Subtrees that can never host a pinnable setting. Descending into them
    -- walks tens of thousands of nested tables (e.g. _migrationBackup holds
    -- full per-slot snapshots of prior profile state) and trips the WoW
    -- script watchdog.
    local SKIP_KEYS = {
        _migrationBackup = true,
        _schemaVersion = true,
        _defaultsVersion = true,
    }

    local visited = {}
    local function Walk(node, prefix)
        if type(node) ~= "table" or visited[node] then
            return false
        end
        visited[node] = true

        for key, value in pairs(node) do
            if type(value) == "table" and not SKIP_KEYS[key] then
                local keyName = tostring(key)
                local childPath = JoinPath(prefix, keyName)
                if not self._profilePathCache[value] then
                    self._profilePathCache[value] = childPath
                end
                if value == targetTable then
                    return true
                end
                if Walk(value, childPath) then
                    return true
                end
            end
        end

        return false
    end

    if Walk(profile, "") then
        return self._profilePathCache[targetTable]
    end

    return nil
end

function Pins:GetResolvedWidgetPath(binding, db)
    if type(binding) ~= "table" then
        return nil
    end

    if type(binding.pinPath) == "string" and binding.pinPath ~= "" then
        return binding.pinPath
    end

    if type(binding.dbKey) ~= "string" or binding.dbKey == "" then
        return nil
    end

    local tablePath = self:ResolveProfileTablePath(binding.dbTable, db)
    if tablePath == nil then
        return nil
    end
    if tablePath == "" then
        return binding.dbKey
    end
    return tablePath .. "." .. binding.dbKey
end

function Pins:IsPinned(path, db)
    local store = GetStore(db, false)
    return store and store.entries and store.entries[path] ~= nil or false
end

function Pins:GetPinnedValue(path, db)
    local store = GetStore(db, false)
    local entry = store and store.entries and store.entries[path] or nil
    return entry and CloneValue(entry.value) or nil
end

function Pins:GetEntry(path, db)
    local store = GetStore(db, false)
    return store and store.entries and store.entries[path] or nil
end

function Pins:GetCount(db)
    local store = GetStore(db, false)
    if not store or type(store.entries) ~= "table" then
        return 0
    end

    local count = 0
    for _ in pairs(store.entries) do
        count = count + 1
    end
    return count
end

function Pins:List(db)
    local store = GetStore(db, false)
    local items = {}
    if not store or type(store.entries) ~= "table" then
        return items
    end

    for path, entry in pairs(store.entries) do
        items[#items + 1] = {
            path = path,
            entry = entry,
            kind = entry.kind,
            value = CloneValue(entry.value),
            label = entry.label or path,
            pinnedAt = tonumber(entry.pinnedAt) or 0,
            missCount = tonumber(entry.missCount) or 0,
            disabled = entry.disabled == true,
            tabIndex = entry.tabIndex,
            tabName = entry.tabName,
            subTabIndex = entry.subTabIndex,
            subTabName = entry.subTabName,
            sectionName = entry.sectionName,
            tileId = entry.tileId,
            subPageIndex = entry.subPageIndex,
        }
    end

    table.sort(items, function(a, b)
        local ap = tonumber(a.pinnedAt) or 0
        local bp = tonumber(b.pinnedAt) or 0
        if ap ~= bp then
            return ap > bp
        end
        return tostring(a.label) < tostring(b.label)
    end)

    return items
end

function Pins:FormatValue(value)
    local valueType = type(value)
    if valueType == "boolean" then
        return value and "On" or "Off"
    end
    if valueType == "number" then
        local rounded = tonumber(value)
        if rounded and abs(rounded - math.floor(rounded)) < 0.0001 then
            return tostring(math.floor(rounded))
        end
        return tostring(value)
    end
    if valueType == "string" then
        return value ~= "" and value or "(empty)"
    end
    if IsColorValue(value) then
        local alpha = value[4] ~= nil and (", " .. tostring(value[4])) or ""
        return ("rgb(%s, %s, %s%s)"):format(tostring(value[1]), tostring(value[2]), tostring(value[3]), alpha)
    end
    return tostring(value)
end

local function NotifySubscribersForPath(subscribers, path)
    if type(subscribers) ~= "table" then
        return
    end

    for index = #subscribers, 1, -1 do
        local subscription = subscribers[index]
        local owner = subscription and subscription.owner or nil
        if owner and owner.GetParent and owner:GetParent() == nil then
            table_remove(subscribers, index)
        elseif subscription and type(subscription.callback) == "function" then
            local ok, err = pcall(subscription.callback, path)
            if not ok then
                DebugLog("Pinned settings subscriber failed:", tostring(err))
            end
        end
    end
end

function Pins:Broadcast(path)
    NotifySubscribersForPath(self._subscribers[path], path)
    NotifySubscribersForPath(self._subscribers["*"], path)
end

function Pins:Subscribe(path, callback, owner)
    if type(callback) ~= "function" then
        return nil
    end

    path = (type(path) == "string" and path ~= "") and path or "*"
    self._subscribers[path] = self._subscribers[path] or {}
    self._subscriptionSeq = (self._subscriptionSeq or 0) + 1

    local token = self._subscriptionSeq
    self._subscribers[path][#self._subscribers[path] + 1] = {
        token = token,
        callback = callback,
        owner = owner,
    }
    return token
end

function Pins:Unsubscribe(token)
    if token == nil then
        return
    end

    for _, subscribers in pairs(self._subscribers) do
        for index = #subscribers, 1, -1 do
            if subscribers[index].token == token then
                table_remove(subscribers, index)
                return
            end
        end
    end
end

function Pins:PushAutoApplySuppression()
    self._autoApplySuppressed = (self._autoApplySuppressed or 0) + 1
end

function Pins:PopAutoApplySuppression()
    local current = self._autoApplySuppressed or 0
    if current > 0 then
        self._autoApplySuppressed = current - 1
    end
end

function Pins:IsAutoApplySuppressed()
    return (self._autoApplySuppressed or 0) > 0
end

function Pins:WithAutoApplySuppressed(callback)
    if type(callback) ~= "function" then
        return nil
    end

    self:PushAutoApplySuppression()
    local ok, resultA, resultB, resultC = pcall(callback)
    self:PopAutoApplySuppression()
    if not ok then
        error(resultA)
    end
    return resultA, resultB, resultC
end

function Pins:UpdateEntryMetadata(entry, descriptor)
    if type(entry) ~= "table" or type(descriptor) ~= "table" then
        return
    end

    if type(descriptor.kind) == "string" and descriptor.kind ~= "" then
        entry.kind = descriptor.kind
    end
    if type(descriptor.label) == "string" and descriptor.label ~= "" then
        entry.label = descriptor.label
    end
    if type(descriptor.pinLabel) == "string" and descriptor.pinLabel ~= "" then
        entry.label = descriptor.pinLabel
    end
    if type(descriptor.tabName) == "string" then entry.tabName = descriptor.tabName end
    if type(descriptor.subTabName) == "string" then entry.subTabName = descriptor.subTabName end
    if type(descriptor.sectionName) == "string" then entry.sectionName = descriptor.sectionName end
    if type(descriptor.featureId) == "string" and descriptor.featureId ~= "" then entry.featureId = descriptor.featureId end
    if type(descriptor.surfaceTabKey) == "string" and descriptor.surfaceTabKey ~= "" then entry.surfaceTabKey = descriptor.surfaceTabKey end
    if type(descriptor.surfaceUnitKey) == "string" and descriptor.surfaceUnitKey ~= "" then entry.surfaceUnitKey = descriptor.surfaceUnitKey end
    if descriptor.tabIndex ~= nil then entry.tabIndex = descriptor.tabIndex end
    if descriptor.subTabIndex ~= nil then entry.subTabIndex = descriptor.subTabIndex end
    if type(descriptor.tileId) == "string" and descriptor.tileId ~= "" then entry.tileId = descriptor.tileId end
    if descriptor.subPageIndex ~= nil then entry.subPageIndex = descriptor.subPageIndex end
end

function Pins:ClearProfileShadow(profileName, path, db)
    if type(profileName) ~= "string" or profileName == "" then
        return
    end

    local store = GetStore(db, false)
    if not store then
        return
    end

    if type(path) == "string" and path ~= "" then
        local entry = store.entries[path]
        if entry and type(entry.shadowed) == "table" then
            entry.shadowed[profileName] = nil
        end
        return
    end

    SafeForEachEntry(store, function(_, entry)
        if type(entry.shadowed) == "table" then
            entry.shadowed[profileName] = nil
        end
    end)
end

function Pins:DropProfile(profileName, db)
    self:ClearProfileShadow(profileName, nil, db)
end

function Pins:Snapshot(profileName, sourceProfile, specificPath, db)
    local store = GetStore(db, false)
    if not store or type(profileName) ~= "string" or profileName == "" then
        return false
    end

    db = db or GetCurrentDB()
    sourceProfile = sourceProfile or (db and db.profile) or nil
    if type(sourceProfile) ~= "table" then
        return false
    end

    local changed = false
    SafeForEachEntry(store, function(path, entry)
        if specificPath and specificPath ~= path then
            return
        end

        entry.shadowed = type(entry.shadowed) == "table" and entry.shadowed or {}
        if entry.shadowed[profileName] ~= nil then
            return
        end

        local value, found = ReadPath(sourceProfile, path)
        if not found then
            return
        end

        entry.shadowed[profileName] = CloneValue(value)
        changed = true
    end)

    if changed then
        TouchStore(store)
    end
    return changed
end

function Pins:PrepareActiveProfileForApply(db)
    db = db or GetCurrentDB()
    if not db then
        return false
    end

    local currentProfile = self:GetCurrentProfileName(db)
    if not currentProfile then
        return false
    end

    self:InvalidatePathCache()
    return self:Snapshot(currentProfile, db.profile, nil, db)
end

function Pins:HandleProfileEvent(event, db, profileKey)
    db = db or GetCurrentDB()
    if not db or type(db.profile) ~= "table" then
        return false
    end

    local activeProfile = self:GetCurrentProfileName(db)
    local currentProfile = activeProfile
    if event == "OnProfileChanged" or event == "OnNewProfile" then
        if type(profileKey) == "string" and profileKey ~= "" then
            currentProfile = profileKey
        end
    elseif type(currentProfile) ~= "string" or currentProfile == "" then
        currentProfile = profileKey
    end

    if type(currentProfile) ~= "string" or currentProfile == "" then
        return false
    end

    self:InvalidatePathCache()

    if event == "OnProfileCopied" or event == "OnProfileReset" then
        self:ClearProfileShadow(currentProfile, nil, db)
    end

    return self:Snapshot(currentProfile, db.profile, nil, db)
end

local function MarkEntryApplyFailure(entry, path, reason)
    entry.missCount = (tonumber(entry.missCount) or 0) + 1
    if entry.missCount >= STALE_MISS_LIMIT then
        entry.disabled = true
    end
    DebugLog("Pinned setting apply failed:", tostring(path), tostring(reason))
end

local function MarkEntryApplySuccess(entry)
    if entry.disabled or (tonumber(entry.missCount) or 0) > 0 then
        entry.disabled = false
        entry.missCount = 0
    end
end

function Pins:ApplyAllForDB(db)
    db = db or GetCurrentDB()
    local store = GetStore(db, false)
    if not store or not db or type(db.profile) ~= "table" then
        return false
    end

    local changed = false
    SafeForEachEntry(store, function(path, entry)
        local value = entry and entry.value
        if not self:IsPathPinnable(path, entry and entry.kind, value) then
            MarkEntryApplyFailure(entry, path, "path is no longer pinnable")
            return
        end

        local _, found = ReadPath(db.profile, path)
        if not found then
            MarkEntryApplyFailure(entry, path, "target path not found")
            return
        end

        local ok, reason = WritePath(db.profile, path, value)
        if ok then
            MarkEntryApplySuccess(entry)
            changed = true
        else
            MarkEntryApplyFailure(entry, path, reason)
        end
    end)

    if changed then
        TouchStore(store)
    end
    return changed
end

function Pins:ApplyAll()
    return self:ApplyAllForDB(GetCurrentDB())
end

function Pins:Pin(path, descriptor, db)
    db = db or GetCurrentDB()
    local store = GetStore(db, true)
    if not store or type(path) ~= "string" or path == "" or type(descriptor) ~= "table" then
        return false, "invalid pin request"
    end

    local value = descriptor.value
    if not self:IsPathPinnable(path, descriptor.kind, value) then
        return false, "setting cannot be pinned"
    end

    local entry = store.entries[path]
    if type(entry) ~= "table" then
        entry = {
            shadowed = {},
            pinnedAt = GetTimeStamp(),
            missCount = 0,
            disabled = false,
        }
        store.entries[path] = entry
    end

    local currentProfile = self:GetCurrentProfileName(db)
    if currentProfile and type(descriptor.sourceProfile) == "table" then
        self:Snapshot(currentProfile, descriptor.sourceProfile, path, db)
    elseif currentProfile and db and type(db.profile) == "table" then
        self:Snapshot(currentProfile, db.profile, path, db)
    end

    entry.value = CloneValue(value)
    entry.kind = descriptor.kind or entry.kind or "custom"
    entry.shadowed = type(entry.shadowed) == "table" and entry.shadowed or {}
    entry.pinnedAt = entry.pinnedAt or GetTimeStamp()
    entry.disabled = false
    entry.missCount = 0

    self:UpdateEntryMetadata(entry, descriptor)
    TouchStore(store)
    self:Broadcast(path)
    return true
end

function Pins:RestoreProfileValue(profileName, path, value, db)
    db = db or GetCurrentDB()
    if type(profileName) ~= "string" or profileName == "" or type(path) ~= "string" or path == "" then
        return false, "invalid restore request"
    end

    local root
    if profileName == self:GetCurrentProfileName(db) then
        root = db and db.profile or nil
    else
        local profiles = db and db.sv and db.sv.profiles or nil
        if type(profiles) ~= "table" then
            return false, "profile table unavailable"
        end
        profiles[profileName] = profiles[profileName] or {}
        root = profiles[profileName]
    end

    if type(root) ~= "table" then
        return false, "profile root unavailable"
    end

    if value == nil then
        return RemovePath(root, path), "removed path"
    end

    return WritePath(root, path, value)
end

function Pins:Unpin(path, db, options)
    db = db or GetCurrentDB()
    local store = GetStore(db, false)
    if not store or type(path) ~= "string" or path == "" then
        return false, "pin not found"
    end

    local entry = store.entries[path]
    if type(entry) ~= "table" then
        return false, "pin not found"
    end

    if type(entry.shadowed) == "table" then
        for profileName, value in pairs(entry.shadowed) do
            local ok, reason = self:RestoreProfileValue(profileName, path, value, db)
            if not ok then
                DebugLog("Pinned setting restore failed:", tostring(path), tostring(profileName), tostring(reason))
            end
        end
    end

    store.entries[path] = nil
    TouchStore(store)
    self:Broadcast(path)

    if not (options and options.skipRefresh) then
        self:RefreshRuntime()
    end

    return true
end

function Pins:UnpinAll(db)
    db = db or GetCurrentDB()
    local keys = {}
    local store = GetStore(db, false)
    if not store or type(store.entries) ~= "table" then
        return 0
    end

    for path in pairs(store.entries) do
        keys[#keys + 1] = path
    end

    for _, path in ipairs(keys) do
        self:Unpin(path, db, { skipRefresh = true })
    end

    if #keys > 0 then
        self:RefreshRuntime()
        self:Broadcast("*")
    end

    return #keys
end

function Pins:UpdatePinnedValue(path, value, descriptor, db)
    db = db or GetCurrentDB()
    local store = GetStore(db, false)
    local entry = store and store.entries and store.entries[path] or nil
    if type(entry) ~= "table" then
        return false, "pin not found"
    end

    if not self:IsPathPinnable(path, descriptor and descriptor.kind or entry.kind, value) then
        return false, "invalid pinned value"
    end

    entry.value = CloneValue(value)
    if descriptor then
        self:UpdateEntryMetadata(entry, descriptor)
    end
    entry.disabled = false
    entry.missCount = 0
    TouchStore(store)
    self:Broadcast(path)
    return true
end

function Pins:RewritePath(oldPath, newPath, db)
    db = db or GetCurrentDB()
    local store = GetStore(db, false)
    if not store or type(oldPath) ~= "string" or oldPath == ""
        or type(newPath) ~= "string" or newPath == "" or oldPath == newPath then
        return false
    end

    local oldEntry = store.entries[oldPath]
    if type(oldEntry) ~= "table" then
        return false
    end

    local newEntry = store.entries[newPath]
    if type(newEntry) ~= "table" then
        store.entries[newPath] = oldEntry
    else
        newEntry.value = CloneValue(oldEntry.value)
        newEntry.kind = oldEntry.kind or newEntry.kind
        newEntry.pinnedAt = oldEntry.pinnedAt or newEntry.pinnedAt
        newEntry.disabled = oldEntry.disabled == true
        newEntry.missCount = tonumber(oldEntry.missCount) or 0
        newEntry.shadowed = type(newEntry.shadowed) == "table" and newEntry.shadowed or {}
        if type(oldEntry.shadowed) == "table" then
            for profileName, value in pairs(oldEntry.shadowed) do
                if newEntry.shadowed[profileName] == nil then
                    newEntry.shadowed[profileName] = CloneValue(value)
                end
            end
        end
        self:UpdateEntryMetadata(newEntry, oldEntry)
    end

    store.entries[oldPath] = nil
    TouchStore(store)
    self:Broadcast(oldPath)
    self:Broadcast(newPath)
    return true
end

function Pins:DropPath(path, db)
    db = db or GetCurrentDB()
    local store = GetStore(db, false)
    if not store or type(path) ~= "string" or path == "" or not store.entries[path] then
        return false
    end

    store.entries[path] = nil
    TouchStore(store)
    self:Broadcast(path)
    return true
end

function Pins:GetNavigationEntry(path, db)
    local entry = self:GetEntry(path, db)
    if not entry then
        return nil
    end

    if type(entry.label) ~= "string" or entry.label == "" then
        return nil
    end

    local inferred = ResolveFeatureRouteFromPath(path)

    local route = nil
    if inferred and type(inferred.tileId) == "string" and inferred.tileId ~= "" then
        route = {
            tileId = inferred.tileId,
            subPageIndex = inferred.subPageIndex,
        }
    elseif type(entry.tileId) == "string" and entry.tileId ~= "" then
        route = {
            tileId = entry.tileId,
            subPageIndex = entry.subPageIndex,
        }
    end

    local tabIndex = inferred and inferred.tabIndex ~= nil and inferred.tabIndex or entry.tabIndex
    if not route and tabIndex == nil then
        return nil
    end

    return {
        path = path,
        label = entry.label,
        tabIndex = tabIndex,
        tabName = inferred and inferred.tabName or entry.tabName,
        subTabIndex = inferred and inferred.subTabIndex ~= nil and inferred.subTabIndex or entry.subTabIndex,
        subTabName = inferred and inferred.subTabName or entry.subTabName,
        sectionName = entry.sectionName,
        tileId = route and route.tileId or nil,
        subPageIndex = route and route.subPageIndex or nil,
        featureId = inferred and inferred.featureId or entry.featureId,
        surfaceTabKey = inferred and inferred.surfaceTabKey or entry.surfaceTabKey,
        surfaceUnitKey = inferred and inferred.surfaceUnitKey or entry.surfaceUnitKey,
    }
end

function Pins:NavigateToPinned(path)
    local gui = _G.QUI and _G.QUI.GUI or nil
    if not gui or type(gui.NavigateSearchResult) ~= "function" then
        return false
    end

    local entry = self:GetNavigationEntry(path)
    if not entry then
        return false
    end

    if not gui.MainFrame or not gui.MainFrame:IsShown() then
        if type(gui.Show) == "function" then
            gui:Show()
        end
    end

    gui:NavigateSearchResult(entry, {
        scrollToLabel = entry.label,
        scrollToPath = entry.path,
        pulse = true,
    })
    return true
end

function Pins:OpenManagePage()
    local gui = _G.QUI and _G.QUI.GUI or nil
    if not gui then
        return false
    end

    if not gui.MainFrame or not gui.MainFrame:IsShown() then
        if type(gui.Show) == "function" then
            gui:Show()
        end
    end

    local frame = gui.MainFrame
    if not frame or type(gui.FindV2TileByID) ~= "function" or type(gui.SelectFeatureTile) ~= "function" then
        return false
    end

    local _, index = gui:FindV2TileByID(frame, "global")
    if not index then
        return false
    end

    gui:SelectFeatureTile(frame, index, { subPageIndex = 2 })
    return true
end

function Pins:RefreshRuntime()
    if ns.Registry and type(ns.Registry.RefreshAll) == "function" then
        ns.Registry:RefreshAll()
        return
    end

    if ns.Addon and type(ns.Addon.RefreshAll) == "function" then
        ns.Addon:RefreshAll()
    end
end

local function CategoryTouchesPath(category, path)
    if type(category) ~= "table" or type(path) ~= "string" or path == "" then
        return false
    end

    if type(category.paths) == "table" then
        for _, candidate in ipairs(category.paths) do
            if IsPathExactOrNested(path, candidate) then
                return true
            end
        end
    end

    local generalKey = path:match("^general%.(.+)$")
    if generalKey and type(category.generalKeys) == "table" then
        for _, key in ipairs(category.generalKeys) do
            if IsPathExactOrNested(generalKey, key) then
                return true
            end
        end
    end

    if type(category.topLevelKeys) == "table" then
        for _, key in ipairs(category.topLevelKeys) do
            if IsPathExactOrNested(path, key) then
                return true
            end
        end
    end

    return false
end

function Pins:HandleSelectiveImport(db, categories)
    db = db or GetCurrentDB()
    local store = GetStore(db, false)
    local currentProfile = self:GetCurrentProfileName(db)
    if not store or type(categories) ~= "table" or not currentProfile or type(db.profile) ~= "table" then
        return false
    end

    local coveredPaths = {}
    SafeForEachEntry(store, function(path)
        for _, category in ipairs(categories) do
            if CategoryTouchesPath(category, path) then
                coveredPaths[#coveredPaths + 1] = path
                break
            end
        end
    end)

    if #coveredPaths == 0 then
        self:ApplyAllForDB(db)
        return false
    end

    for _, path in ipairs(coveredPaths) do
        self:ClearProfileShadow(currentProfile, path, db)
        self:Snapshot(currentProfile, db.profile, path, db)
    end

    self:ApplyAllForDB(db)
    self:Broadcast("*")
    return true
end

function Pins:HandleFullImportSnapshot(db, importedProfile)
    db = db or GetCurrentDB()
    local store = GetStore(db, false)
    local currentProfile = self:GetCurrentProfileName(db)
    if not store or not currentProfile or type(importedProfile) ~= "table" then
        return false
    end

    self:ClearProfileShadow(currentProfile, nil, db)
    self:Snapshot(currentProfile, importedProfile, nil, db)
    return true
end
