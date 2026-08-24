local ADDON_NAME, ns = ...

local Settings = ns.Settings or {}
ns.Settings = Settings

local Pins = Settings.Pins or {}
Settings.Pins = Pins

local abs = math.abs
local ipairs = ipairs
local pairs = pairs
local rawget = rawget
local setmetatable = setmetatable
local table_remove = table.remove
local tonumber = tonumber
local tostring = tostring
local type = type

local PIN_STORE_VERSION = 1
local PROFILE_FEATURE_PIN_VERSION = 1
local STALE_MISS_LIMIT = 3

local PROFILE_FEATURE_CATEGORIES = {
    auraDisplays = {
        topLevelKeys = { "auraDisplays" },
        frameAnchorPrefix = "auraDisplay_",
    },
    groupFrames = {
        topLevelKeys = { "quiGroupFrames", "raidBuffs" },
        frameAnchorKeys = { "partyFrames", "raidFrames", "spotlightFrames", "missingRaidBuffs" },
    },
}

Pins.ProfileFeatureCategories = PROFILE_FEATURE_CATEGORIES

Pins._subscribers = Pins._subscribers or {}
Pins._subscriptionSeq = Pins._subscriptionSeq or 0
Pins._profilePathCache = Pins._profilePathCache or setmetatable({}, { __mode = "k" })

local function GetTimeStamp()
    if type(time) == "function" then
        local ok, value = ns.SafeCall("chain-next", time)
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

local CloneValue = ns.Helpers.DeepCopy

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

local function IsTransientOptionsBinding(tableRef)
    return type(tableRef) == "table" and rawget(tableRef, "_quiTransientOptionsProxy") == true
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
    unitFramesIconsTab = { surfaceTabKey = "icons", subTabName = "Auras" },
    unitFramesPortraitTab = { surfaceTabKey = "portrait", subTabName = "Portrait" },
    unitFramesIndicatorsTab = { surfaceTabKey = "indicators", subTabName = "Indicators" },
}

local CHAT_SEARCH_CONTEXT = {
    tileId = "chat_tooltips",
}

local CHAT_FEATURE_SUBPAGE_INDEX = {
    chatFrame1 = 1,
    chatFrame1Filters = 2,
    chatFrame1ButtonBar = 3,
    chatFrame1Alerts = 4,
    chatFrame1History = 5,
}

local function NormalizeRouteKey(value)
    if type(value) ~= "string" or value == "" then
        return nil
    end
    local normalized = value:gsub("[^%w]", ""):lower()
    return normalized ~= "" and normalized or nil
end

local CHAT_FEATURE_BY_LEGACY_SECTION = {
    tabfilters = "chatFrame1Filters",
    buttonbar = "chatFrame1ButtonBar",
    timestamps = "chatFrame1Alerts",
    messagemodifiers = "chatFrame1Alerts",
    keywordalert = "chatFrame1Alerts",
    redundanttextcleanup = "chatFrame1Alerts",
    newmessagesound = "chatFrame1Alerts",
    commandhistory = "chatFrame1History",
    persistentmessagehistory = "chatFrame1History",
    uicleanup = "chatFrame1History",
    copybutton = "chatFrame1History",
    messagehistory = "chatFrame1History",
}

local CHAT_FEATURE_BY_DB_SEGMENT = {
    tabs = "chatFrame1Filters",
    buttonbars = "chatFrame1ButtonBar",
    timestamps = "chatFrame1Alerts",
    modifiers = "chatFrame1Alerts",
    newmessagesound = "chatFrame1Alerts",
    editboxhistory = "chatFrame1History",
    history = "chatFrame1History",
    messagehistory = "chatFrame1History",
    copybuttonmode = "chatFrame1History",
    hidebuttons = "chatFrame1History",
}

local function BuildChatRoute(featureId)
    local subPageIndex = CHAT_FEATURE_SUBPAGE_INDEX[featureId]
    if not subPageIndex then
        return nil
    end
    return {
        featureId = featureId,
        tileId = CHAT_SEARCH_CONTEXT.tileId,
        subPageIndex = subPageIndex,
    }
end

local function ResolveChatRouteFromPath(path)
    local segments = SplitPath(path)
    if #segments == 0 then
        return nil
    end

    local featureId = segments[1]
    if CHAT_FEATURE_SUBPAGE_INDEX[featureId] then
        if featureId == "chatFrame1" then
            local sectionKey = NormalizeRouteKey(segments[2])
            local sectionFeatureId = sectionKey and CHAT_FEATURE_BY_LEGACY_SECTION[sectionKey] or nil
            if sectionFeatureId then
                return BuildChatRoute(sectionFeatureId)
            end
        end
        return BuildChatRoute(featureId)
    end

    local chatIndex = nil
    if NormalizeRouteKey(segments[1]) == "chat" then
        chatIndex = 1
    elseif NormalizeRouteKey(segments[1]) == "profile" and NormalizeRouteKey(segments[2]) == "chat" then
        chatIndex = 2
    end
    if not chatIndex then
        return nil
    end

    local dbKey = NormalizeRouteKey(segments[chatIndex + 1])
    return BuildChatRoute((dbKey and CHAT_FEATURE_BY_DB_SEGMENT[dbKey]) or "chatFrame1")
end

local function ResolveFeatureRouteFromPath(path)
    if type(path) ~= "string" or path == "" then
        return nil
    end

    local featureId = path:match("^([^.]+)")
    if type(featureId) ~= "string" or featureId == "" then
        return nil
    end

    local chatRoute = ResolveChatRouteFromPath(path)
    if chatRoute then
        return chatRoute
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

    local function LookupSegment(candidate)
        if type(candidate) ~= "string" or candidate == "" or not nav then
            return nil, nil
        end
        if type(nav.GetRoute) == "function" then
            local directRoute = nav:GetRoute(candidate)
            if type(directRoute) == "table" then
                return directRoute, candidate
            end
        end
        if type(nav.GetLookupTarget) == "function" then
            local lookupRoute, lookupFeature = nav:GetLookupTarget(candidate)
            if type(lookupRoute) == "table" then
                local id = candidate
                if type(lookupFeature) == "table"
                    and type(lookupFeature.id) == "string"
                    and lookupFeature.id ~= "" then
                    id = lookupFeature.id
                end
                return lookupRoute, id
            end
        end
        return nil, nil
    end

    local route, resolvedFeatureId = LookupSegment(featureId)

    if type(route) ~= "table" then
        local segments = SplitPath(path)
        for i = 2, #segments - 1 do
            local nestedRoute, nestedId = LookupSegment(segments[i])
            if type(nestedRoute) == "table" then
                route = nestedRoute
                resolvedFeatureId = nestedId or segments[i]
                break
            end
        end
    end

    if type(route) ~= "table" then
        return nil
    end

    local resolved = {
        featureId = resolvedFeatureId,
    }
    if type(route.tileId) == "string" and route.tileId ~= "" then
        resolved.tileId = route.tileId
    end
    if route.subPageIndex ~= nil then
        resolved.subPageIndex = route.subPageIndex
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

local function GetProfileFeatureStore(db, create)
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

    local store = globalDB.profileFeaturePins
    if type(store) ~= "table" then
        if not create then
            return nil
        end
        store = {
            _version = PROFILE_FEATURE_PIN_VERSION,
            profiles = {},
        }
        globalDB.profileFeaturePins = store
    end

    if type(store._version) ~= "number" then
        store._version = PROFILE_FEATURE_PIN_VERSION
    end
    if type(store.profiles) ~= "table" then
        store.profiles = {}
    end
    return store
end

local function GetStoredProfiles(db)
    if not db then
        return nil
    end
    if type(db.profiles) == "table" then
        return db.profiles
    end
    return db.sv and db.sv.profiles or nil
end

local function MaterializeProfileDefaults(target, defaults)
    if type(target) ~= "table" or type(defaults) ~= "table" then
        return
    end

    for key, defaultValue in pairs(defaults) do
        if key == "*" or key == "**" then
            if type(defaultValue) == "table" then
                for targetKey, targetValue in pairs(target) do
                    if rawget(defaults, targetKey) == nil and type(targetValue) == "table" then
                        MaterializeProfileDefaults(targetValue, defaultValue)
                    end
                end
            end
        elseif type(defaultValue) == "table" then
            local targetValue = rawget(target, key)
            if targetValue == nil then
                targetValue = {}
                target[key] = targetValue
            end
            if type(targetValue) == "table" then
                MaterializeProfileDefaults(targetValue, defaultValue)
                if type(defaults["**"]) == "table" then
                    MaterializeProfileDefaults(targetValue, defaults["**"])
                end
            end
        elseif rawget(target, key) == nil then
            target[key] = defaultValue
        end
    end
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
        ns.SafeCall("bulkhead", callback, path, entry)
    end
end

function Pins:GetStore(db, create)
    return GetStore(db, create)
end

function Pins:IsProfileFeatureSupported(categoryID)
    return PROFILE_FEATURE_CATEGORIES[categoryID] ~= nil
end

function Pins:BuildInactiveProfileSnapshot(db, profileName)
    local profiles = GetStoredProfiles(db)
    local storedProfile = type(profiles) == "table" and rawget(profiles, profileName) or nil
    if type(storedProfile) ~= "table" then
        return nil
    end

    local snapshot = CloneValue(storedProfile)
    local defaults = db and db.defaults and db.defaults.profile
    MaterializeProfileDefaults(snapshot, defaults)
    return snapshot
end

function Pins:CopyProfileFeatureAnchors(targetProfile, sourceProfile, category)
    local keys = category and category.frameAnchorKeys
    local prefix = category and category.frameAnchorPrefix
    if type(targetProfile) ~= "table" or type(sourceProfile) ~= "table"
        or (type(keys) ~= "table" and type(prefix) ~= "string") then
        return false
    end

    local targetAnchors = targetProfile.frameAnchoring
    local sourceAnchors = sourceProfile.frameAnchoring
    if type(targetAnchors) ~= "table" then
        targetAnchors = {}
        targetProfile.frameAnchoring = targetAnchors
    end

    if type(keys) == "table" then
        for _, key in ipairs(keys) do
            targetAnchors[key] = type(sourceAnchors) == "table" and CloneValue(sourceAnchors[key]) or nil
        end
    end

    if type(prefix) == "string" then
        for key in pairs(targetAnchors) do
            if type(key) == "string" and key:sub(1, #prefix) == prefix then
                targetAnchors[key] = nil
            end
        end
        if type(sourceAnchors) == "table" then
            for key, value in pairs(sourceAnchors) do
                if type(key) == "string" and key:sub(1, #prefix) == prefix then
                    targetAnchors[key] = CloneValue(value)
                end
            end
        end
    end

    return true
end

function Pins:CopyProfileFeatureCategory(targetProfile, sourceProfile, categoryID)
    local category = PROFILE_FEATURE_CATEGORIES[categoryID]
    if type(targetProfile) ~= "table" or type(sourceProfile) ~= "table" or not category then
        return false, "Unsupported profile feature."
    end

    local targetClickCast
    if categoryID == "groupFrames" and type(targetProfile.quiGroupFrames) == "table" then
        targetClickCast = CloneValue(rawget(targetProfile.quiGroupFrames, "clickCast"))
    end

    for _, key in ipairs(category.topLevelKeys) do
        targetProfile[key] = CloneValue(sourceProfile[key])
    end

    if categoryID == "groupFrames" then
        if targetClickCast ~= nil and type(targetProfile.quiGroupFrames) ~= "table" then
            targetProfile.quiGroupFrames = {}
        end
        if type(targetProfile.quiGroupFrames) == "table" then
            targetProfile.quiGroupFrames.clickCast = targetClickCast
        end
    end

    self:CopyProfileFeatureAnchors(targetProfile, sourceProfile, category)
    return true
end

function Pins:GetProfileFeatureSource(categoryID, db, targetProfile)
    db = db or GetCurrentDB()
    targetProfile = targetProfile or self:GetCurrentProfileName(db)
    local store = GetProfileFeatureStore(db, false)
    local profilePins = store and store.profiles[targetProfile] or nil
    local source = type(profilePins) == "table" and profilePins[categoryID] or nil
    return type(source) == "string" and source ~= "" and source or nil
end

function Pins:SetProfileFeatureSource(sourceProfile, categoryID, db, targetProfile)
    db = db or GetCurrentDB()
    targetProfile = targetProfile or self:GetCurrentProfileName(db)
    if not PROFILE_FEATURE_CATEGORIES[categoryID] then
        return false, "Unsupported profile feature."
    end
    if type(targetProfile) ~= "string" or targetProfile == ""
        or type(sourceProfile) ~= "string" or sourceProfile == "" then
        return false, "Choose a source profile."
    end
    if targetProfile == sourceProfile then
        return false, "Choose a profile other than the current profile."
    end

    local profiles = GetStoredProfiles(db)
    if type(profiles) ~= "table" or type(rawget(profiles, sourceProfile)) ~= "table" then
        return false, ("No profile named '%s'."):format(sourceProfile)
    end
    if type(rawget(profiles, targetProfile)) ~= "table" then
        return false, ("No profile named '%s'."):format(targetProfile)
    end

    local existingStore = GetProfileFeatureStore(db, false)
    local sourcePins = existingStore and existingStore.profiles[sourceProfile] or nil
    if type(sourcePins) == "table" and sourcePins[categoryID] then
        return false, "Choose a source profile that is not pinned for this feature."
    end
    for _, profilePins in pairs(existingStore and existingStore.profiles or {}) do
        if type(profilePins) == "table" and profilePins[categoryID] == targetProfile then
            return false, "This profile is already a pinned source for this feature."
        end
    end

    local store = GetProfileFeatureStore(db, true)
    local profilePins = store.profiles[targetProfile]
    if type(profilePins) ~= "table" then
        profilePins = {}
        store.profiles[targetProfile] = profilePins
    end
    profilePins[categoryID] = sourceProfile
    return true
end

function Pins:ClearProfileFeatureSource(categoryID, db, targetProfile)
    db = db or GetCurrentDB()
    targetProfile = targetProfile or self:GetCurrentProfileName(db)
    local store = GetProfileFeatureStore(db, false)
    local profilePins = store and store.profiles[targetProfile] or nil
    if type(profilePins) ~= "table" or profilePins[categoryID] == nil then
        return false, "Profile feature pin not found."
    end

    profilePins[categoryID] = nil
    if next(profilePins) == nil then
        store.profiles[targetProfile] = nil
    end
    return true
end

function Pins:SyncProfileFeatureSources(db, categoryID)
    db = db or GetCurrentDB()
    local targetProfile = self:GetCurrentProfileName(db)
    local store = GetProfileFeatureStore(db, false)
    local profilePins = store and store.profiles[targetProfile] or nil
    if not db or type(db.profile) ~= "table" or type(profilePins) ~= "table"
        or (categoryID ~= nil and not PROFILE_FEATURE_CATEGORIES[categoryID]) then
        return false
    end

    local defaults = db.defaults
    local canStripDefaults = defaults and type(db.RegisterDefaults) == "function"
    if canStripDefaults then
        db:RegisterDefaults(nil)
    end

    local ok, changed = ns.SafeCall("bulkhead", function()
        local profiles = GetStoredProfiles(db)
        local didChange = false
        for _, pinnedCategoryID in ipairs({ "groupFrames", "auraDisplays" }) do
            local sourceName = profilePins[pinnedCategoryID]
            local sourceProfile = type(profiles) == "table" and type(sourceName) == "string"
                and rawget(profiles, sourceName) or nil
            if (categoryID == nil or categoryID == pinnedCategoryID) and type(sourceProfile) == "table" then
                self:CopyProfileFeatureCategory(sourceProfile, db.profile, pinnedCategoryID)
                didChange = true
            end
        end
        return didChange
    end)

    if canStripDefaults then
        db:RegisterDefaults(defaults)
    end
    return ok and changed or false
end

function Pins:ApplyProfileFeaturePins(db, categories)
    db = db or GetCurrentDB()
    local targetProfile = self:GetCurrentProfileName(db)
    local store = GetProfileFeatureStore(db, false)
    local profilePins = store and store.profiles[targetProfile] or nil
    if not db or type(db.profile) ~= "table" or type(profilePins) ~= "table" then
        return false
    end

    local allowed
    if type(categories) == "table" then
        allowed = {}
        for _, category in ipairs(categories) do
            if type(category) == "table" and type(category.id) == "string" then
                allowed[category.id] = true
            elseif type(category) == "string" then
                allowed[category] = true
            end
        end
    end

    local changed = false
    for _, categoryID in ipairs({ "groupFrames", "auraDisplays" }) do
        local sourceProfile = profilePins[categoryID]
        if type(sourceProfile) == "string" and sourceProfile ~= "" and (not allowed or allowed[categoryID]) then
            local sourceSnapshot = self:BuildInactiveProfileSnapshot(db, sourceProfile)
            if sourceSnapshot then
                self:CopyProfileFeatureCategory(db.profile, sourceSnapshot, categoryID)
                changed = true
            else
                DebugLog("Profile feature pin source unavailable:", tostring(sourceProfile), tostring(categoryID))
            end
        end
    end
    return changed
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

    if segments[1] == "auraDisplays" and segments[2] == "displays" then
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
    local ok, profileName = ns.SafeCallMethod("chain-next", db, "GetCurrentProfile")
    if ok and type(profileName) == "string" and profileName ~= "" then
        return profileName
    end
    return nil
end

local PROFILE_PATH_SKIP_KEYS = {
    _migrationBackup = true,
    _schemaVersion = true,
    _defaultsVersion = true,
}

function Pins:ResolveProfileTablePath(targetTable, db)
    db = db or GetCurrentDB()
    if type(targetTable) ~= "table" or not db then
        return nil
    end
    if IsTransientOptionsBinding(targetTable) then
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

    local visited = {}
    local function Walk(node, prefix)
        if type(node) ~= "table" or visited[node] then
            return false
        end
        visited[node] = true

        for key, value in pairs(node) do
            if type(value) == "table" and not PROFILE_PATH_SKIP_KEYS[key] and not IsTransientOptionsBinding(value) then
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
    if IsTransientOptionsBinding(binding.dbTable) then
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
        local inferred = ResolveFeatureRouteFromPath(path)
        local source = entry
        if inferred and type(inferred.tileId) == "string" and inferred.tileId ~= "" then
            source = inferred
        end

        items[#items + 1] = {
            path = path,
            entry = entry,
            kind = entry.kind,
            value = CloneValue(entry.value),
            label = entry.label or path,
            pinnedAt = tonumber(entry.pinnedAt) or 0,
            missCount = tonumber(entry.missCount) or 0,
            disabled = entry.disabled == true,
            tabIndex = source.tabIndex,
            tabName = source.tabName,
            subTabIndex = source.subTabIndex,
            subTabName = source.subTabName,
            sectionName = entry.sectionName,
            tileId = source.tileId,
            subPageIndex = source.subPageIndex,
            featureId = source.featureId,
            providerKey = entry.providerKey,
            category = entry.category,
            surfaceTabKey = source.surfaceTabKey,
            surfaceUnitKey = source.surfaceUnitKey,
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
        return value and ns.L["On"] or ns.L["Off"]
    end
    if valueType == "number" then
        local rounded = tonumber(value)
        if rounded and abs(rounded - math.floor(rounded)) < 0.0001 then
            return tostring(math.floor(rounded))
        end
        return tostring(value)
    end
    if valueType == "string" then
        return value ~= "" and value or ns.L["(empty)"]
    end
    if IsColorValue(value) then
        local alpha = value[4] ~= nil and (", " .. tostring(value[4])) or ""
        return ns.L["rgb(%1$s, %2$s, %3$s%4$s)"]:format(tostring(value[1]), tostring(value[2]), tostring(value[3]), alpha)
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
            ns.SafeCall("bulkhead", subscription.callback, path)
        end
    end
end

function Pins:Broadcast(path)
    NotifySubscribersForPath(self._subscribers[path], path)
    if path ~= "*" then
        NotifySubscribersForPath(self._subscribers["*"], path)
    end
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

function Pins:UpdateEntryMetadata(entry, descriptor, options)
    if type(entry) ~= "table" or type(descriptor) ~= "table" then
        return
    end

    local allowNavOverwrite = options and options.allowNavOverwrite == true

    if type(descriptor.kind) == "string" and descriptor.kind ~= "" then
        entry.kind = descriptor.kind
    end
    if type(descriptor.label) == "string" and descriptor.label ~= "" then
        entry.label = descriptor.label
    end
    if type(descriptor.pinLabel) == "string" and descriptor.pinLabel ~= "" then
        entry.label = descriptor.pinLabel
    end

    local function setNavString(key, value)
        if type(value) ~= "string" or value == "" then return end
        if allowNavOverwrite or type(entry[key]) ~= "string" or entry[key] == "" then
            entry[key] = value
        end
    end

    local function setNavValue(key, value)
        if value == nil then return end
        if allowNavOverwrite or entry[key] == nil then
            entry[key] = value
        end
    end

    setNavString("tabName", descriptor.tabName)
    setNavString("subTabName", descriptor.subTabName)
    setNavString("sectionName", descriptor.sectionName)
    setNavString("featureId", descriptor.featureId)
    setNavString("providerKey", descriptor.providerKey)
    setNavString("category", descriptor.category)
    setNavString("surfaceTabKey", descriptor.surfaceTabKey)
    setNavString("surfaceUnitKey", descriptor.surfaceUnitKey)
    setNavString("tileId", descriptor.tileId)
    setNavValue("tabIndex", descriptor.tabIndex)
    setNavValue("subTabIndex", descriptor.subTabIndex)
    setNavValue("subPageIndex", descriptor.subPageIndex)
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

    local store = GetProfileFeatureStore(db, false)
    if not store or type(store.profiles) ~= "table" then
        return
    end

    store.profiles[profileName] = nil
    for targetProfile, profilePins in pairs(store.profiles) do
        if type(profilePins) == "table" then
            for categoryID, sourceProfile in pairs(profilePins) do
                if sourceProfile == profileName then
                    profilePins[categoryID] = nil
                end
            end
            if next(profilePins) == nil then
                store.profiles[targetProfile] = nil
            end
        end
    end
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
        local value = entry.value
        if not self:IsPathPinnable(path, entry.kind, value) then
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

    self:UpdateEntryMetadata(entry, descriptor, { allowNavOverwrite = true })
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

    local source = entry
    if inferred and type(inferred.tileId) == "string" and inferred.tileId ~= "" then
        source = inferred
    end

    local route = nil
    if type(source.tileId) == "string" and source.tileId ~= "" then
        route = {
            tileId = source.tileId,
            subPageIndex = source.subPageIndex,
        }
    end

    local tabIndex = source.tabIndex
    if not route and tabIndex == nil then
        return nil
    end

    return {
        path = path,
        label = entry.label,
        tabIndex = tabIndex,
        tabName = source.tabName,
        subTabIndex = source.subTabIndex,
        subTabName = source.subTabName,
        sectionName = entry.sectionName,
        tileId = route and route.tileId or nil,
        subPageIndex = route and route.subPageIndex or nil,
        featureId = source.featureId,
        surfaceTabKey = source.surfaceTabKey,
        surfaceUnitKey = source.surfaceUnitKey,
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
        scrollToFeatureId = entry.featureId,
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
    self:ApplyProfileFeaturePins(db, categories)
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
    self:ApplyProfileFeaturePins(db)
    local store = GetStore(db, false)
    local currentProfile = self:GetCurrentProfileName(db)
    if not store or not currentProfile or type(importedProfile) ~= "table" then
        return false
    end

    self:ClearProfileShadow(currentProfile, nil, db)
    self:Snapshot(currentProfile, importedProfile, nil, db)
    return true
end
