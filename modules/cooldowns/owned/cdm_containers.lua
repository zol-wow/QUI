--[[
    QUI CDM Containers + Layout Engine (Owned Engine)

    All three trackers (Essential/Utility/Buff) use addon-owned containers
    with addon-owned icon frames created by the CDMIcons factory.
    Blizzard viewers are hidden (alpha=0). Only Blizzard CooldownFrames
    are adopted onto addon-owned icons for taint-safe rendering.

    Visibility is handled by hud_visibility.lua (loads before engines).
    Initialization is driven by cdm_provider.lua calling Initialize()
    at ADDON_LOADED (safe window for combat /reload support).
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local QUICore = ns.Addon
local UIKit = ns.UIKit
local LSM = ns.LSM

-- Upvalue caching for hot-path performance
local type = type
local pairs = pairs
local ipairs = ipairs
local pcall = pcall
local C_Timer = C_Timer
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local hooksecurefunc = hooksecurefunc

---------------------------------------------------------------------------
-- ADDON_LOADED / PLAYER_ENTERING_WORLD safe window flag: during a combat
-- /reload, InCombatLockdown() returns true but protected calls are still
-- allowed inside the synchronous event handler body. RefreshAll and other
-- combat-gated paths check this flag to bypass their combat guards during
-- the safe window so the initial layout renders.
---------------------------------------------------------------------------
local inInitSafeWindow = false

---------------------------------------------------------------------------
-- CONSTANTS
---------------------------------------------------------------------------
local HUD_MIN_WIDTH_DEFAULT = Helpers.HUD_MIN_WIDTH_DEFAULT or 200
local ROW_GAP = 0
local SETTINGS_FEATURE_ID = "cooldownManagerContainersPage"
local registeredSettingsLookupKeys = {}
local ANCHOR_KEY_MAP
-- Forward decl: defined later in the file but called from CreateContainer/
-- DeleteContainer above its definition. Without this, those callers would
-- bind the name as a global (nil) at parse time and crash on invocation.
local SyncSettingsFeatureLookups

-- Aspect ratio migration
local function MigrateRowAspect(rowData)
    if rowData and rowData.aspectRatioCrop == nil and rowData.shape then
        if rowData.shape == "rectangle" or rowData.shape == "flat" then
            rowData.aspectRatioCrop = 1.33
        else
            rowData.aspectRatioCrop = 1.0
        end
    end
    return rowData.aspectRatioCrop or 1.0
end

---------------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------------
local containers = {}  -- { essential = frame, utility = frame, buff = frame }
local viewerState = {} -- keyed by container frame
local buffFingerprint = nil  -- fingerprint string for buff icon rebuild skipping
local applying = {}    -- re-entry guard per tracker
local refreshTimers = {} -- stored timer handles so overlapping RefreshAll calls cancel prior timers
local initialized = false
local RegisterContainerFrame
local SyncContainerMouseState
local SyncAllContainerMouseStates
local ApplyUtilityAnchor

-- Anchor proxy for Utility below Essential
local UtilityAnchorProxy = nil
local CreateContainer  -- forward declaration; assigned in CONTAINER CREATION section

-- Point→center offset (mirrors anchoring.lua GetPointOffsetForRect).
-- Returns the offset of the named anchor point relative to the frame's center.
local function PointOffset(point, width, height)
    local halfW = (width or 0) * 0.5
    local halfH = (height or 0) * 0.5
    if point == "TOPLEFT" then     return -halfW,  halfH
    elseif point == "TOP" then     return 0,       halfH
    elseif point == "TOPRIGHT" then return  halfW,  halfH
    elseif point == "LEFT" then    return -halfW,  0
    elseif point == "RIGHT" then   return  halfW,  0
    elseif point == "BOTTOMLEFT" then  return -halfW, -halfH
    elseif point == "BOTTOM" then      return 0,      -halfH
    elseif point == "BOTTOMRIGHT" then return  halfW, -halfH
    end
    return 0, 0
end

---------------------------------------------------------------------------
-- DB ACCESS
---------------------------------------------------------------------------
local GetDB = Helpers.CreateDBGetter("ncdm")

local function GetTrackerSettings(trackerKey)
    local db = GetDB()
    if not db then return nil end
    -- Built-in containers (essential, utility, buff, trackedBar) live at
    -- the top-level ncdm[key] where the user's saved data resides.
    -- Custom containers only exist inside ncdm.containers[key].
    if db[trackerKey] then
        return db[trackerKey]
    end
    if db.containers and db.containers[trackerKey] then
        return db.containers[trackerKey]
    end
    return nil
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

---------------------------------------------------------------------------
-- SPEC PROFILE SAVE / LOAD
-- Save and restore per-spec ownedSpells + removedSpells so each spec
-- keeps its own spell configuration across spec changes.
---------------------------------------------------------------------------
local CDMContainers_API  -- forward declaration; table created in CONTAINER MANAGEMENT API section
local _previousSpecID = nil  -- Track outgoing spec for save-on-switch
local specTrackingReady = false
local specTrackingPendingRefresh = false
local specTrackingRetryToken = 0
local profileCallbackSink = nil
local lastKnownProfile = nil
local RefreshAll  -- forward declaration; finalized in REFRESH ALL section

local SPEC_TRACKING_RETRY_DELAY = 0.5
local SPEC_TRACKING_MAX_RETRIES = 6

local function GetCurrentSpecID()
    if not GetSpecialization then return nil end
    local specIndex = GetSpecialization()
    if not specIndex then return nil end
    if GetSpecializationInfo then
        local specID = GetSpecializationInfo(specIndex)
        return specID
    end
    return nil
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

    ns.CDMSpellData:ForceScan()

    local allReady = true
    for _, key in ipairs(containerKeys) do
        if key == "essential" or key == "utility" or key == "buff" or key == "trackedBar" then
            local containerDB = GetTrackerSettings(key)
            if containerDB and containerDB.ownedSpells == nil then
                ns.CDMSpellData:SnapshotBlizzardCDM(key)
                if containerDB.ownedSpells == nil then
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

local function SaveSpecProfile(specID)
    if not specID or specID == 0 then
        return
    end

    local db = GetDB()
    if not db then
        return
    end

    -- Ensure _specProfiles table exists
    if not db._specProfiles then
        db._specProfiles = {}
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
                dormantSpells = CopyTable(containerDB.dormantSpells or {}),
                dormantSequence = containerDB._dormantSequence or 0,
            }
            if type(containerDB.ownedSpells) == "table" and #containerDB.ownedSpells > 0 then
                hasAnySpells = true
            end
        end
    end

    -- Only persist when there are actual spells. If all containers are
    -- empty (e.g. snapshot failed on login), leave the existing saved
    -- profile untouched — it may contain good data from a previous session
    -- that we'll need when the user swaps back to this spec.
    if hasAnySpells then
        db._specProfiles[specID] = specData
    end
end

local function SaveCurrentSpecProfile()
    -- Use _previousSpecID, not GetCurrentSpecID(). By the time
    -- PLAYER_SPECIALIZATION_CHANGED fires the current spec is already
    -- the NEW spec — saving under GetCurrentSpecID() would store the
    -- outgoing spec's data under the incoming spec's key.
    SaveSpecProfile(_previousSpecID)
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
    local savedProfile = db._specProfiles and db._specProfiles[specID]

    -- Validate the saved profile actually contains spell data. An empty
    -- profile (all containers nil/empty) was likely persisted from a failed
    -- snapshot — discard it so we fall through to fresh snapshot below.
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
            db._specProfiles[specID] = nil
            savedProfile = nil
        end
    end

    if savedProfile then
        -- Restore each container's ownedSpells, removedSpells, and dormantSpells from saved profile
        for _, key in ipairs(containerKeys) do
            local containerDB = GetTrackerSettings(key)
            if containerDB then
                local savedContainer = savedProfile[key]
                if savedContainer then
                    containerDB.ownedSpells = CopyTable(savedContainer.ownedSpells)
                    containerDB.removedSpells = CopyTable(savedContainer.removedSpells)
                    containerDB.dormantSpells = CopyTable(savedContainer.dormantSpells or {})
                    containerDB._dormantSequence = savedContainer.dormantSequence or 0
                else
                    -- Container exists now but wasn't in the saved profile
                    -- (e.g. custom container created after the profile was
                    -- saved). Clear it so stale spells from the previous
                    -- spec don't leak through.
                    ClearContainerSpecState(containerDB)
                end
            end
        end
        -- Validate restored spells belong to the current spec/class.
        -- Saved profiles can contain spells from other specs or even other
        -- classes (shared AceDB profile across characters). Run a full
        -- dormant check synchronously so unrecognised spells are shelved
        -- before the first RefreshAll renders them.
        if ns.CDMSpellData then
            ns.CDMSpellData:CheckAllDormantSpells()
        end
        return true
    else
        -- No saved profile for this spec — fresh snapshot from Blizzard CDM
        if ns.CDMSpellData then
            for _, key in ipairs(containerKeys) do
                local containerDB = GetTrackerSettings(key)
                if containerDB then
                    -- Clear all spec-scoped state so a first-time snapshot never
                    -- inherits removals/dormant entries from a different class/spec.
                    ClearContainerSpecState(containerDB)
                end
            end
            local snapshotReady = TrySnapshotBuiltInContainers(containerKeys)
            if snapshotReady or attempt >= SPEC_TRACKING_MAX_RETRIES then
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

-- Initialize the previous spec ID on first load.
-- Also detects spec/class changes across login sessions (e.g. switching
-- characters that share the same AceDB profile) and performs a spec
-- profile save/load so stale spells from another class never display.

-- Cross-session detection extracted so the 1.0s retry can re-run it.
-- Returns true if a spec mismatch was detected and profiles were swapped.
local function RunCrossSessionDetection(specID)
    local db = GetDB()
    if not db or not specID or specID == 0 then return false, false end

    local lastSpecID = db._lastSpecID
    local detected = lastSpecID ~= nil and lastSpecID ~= specID
    local readyNow = true
    if lastSpecID and lastSpecID ~= specID then
        -- Save stale ownedSpells under the old spec before overwriting
        local oldPrevious = _previousSpecID
        _previousSpecID = lastSpecID
        SaveCurrentSpecProfile()
        _previousSpecID = oldPrevious

        -- Invalidate caches — old spec data is stale
        if ns.InvalidateCDMFrameCache then ns.InvalidateCDMFrameCache() end
        if ns.CDMSpellData and ns.CDMSpellData.InvalidateLearnedCache then
            ns.CDMSpellData:InvalidateLearnedCache()
        end

        -- Load the correct spec profile (or fresh snapshot if first time)
        specTrackingRetryToken = specTrackingRetryToken + 1
        readyNow = LoadOrSnapshotSpecProfile(specID, 1, specTrackingRetryToken)
    end
    -- Persist the current spec ID for next session
    db._lastSpecID = specID
    return readyNow, detected
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

    if _previousSpecID and _previousSpecID ~= 0 then
        local readyNow = RunCrossSessionDetection(_previousSpecID)
        specTrackingReady = readyNow
        return readyNow
    else
        -- GetSpecializationInfo isn't ready yet (returns 0 or nil during early
        -- load). Retry after a short delay — and re-run cross-session detection
        -- so character/spec switches across sessions are still caught.
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

    -- Cancel any stale async spec-load retries before hydrating the new profile.
    specTrackingRetryToken = specTrackingRetryToken + 1

    local specReadyNow = InitSpecTracking()
    if not specReadyNow then
        specTrackingPendingRefresh = true
    end
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

---------------------------------------------------------------------------
-- BUILT-IN CONTAINER KEYS (ordered)
---------------------------------------------------------------------------
local BUILTIN_KEYS = { "essential", "utility", "buff", "trackedBar" }

local BUILTIN_NAMES = {
    essential  = "Essential",
    utility    = "Utility",
    buff       = "Buff Icons",
    trackedBar = "Buff Bars",
}

-- Legacy 4-value taxonomy. Kept for backward-compat reads on profiles where
-- the v33 schema bump has not yet stamped db.shape. New code should use
-- BUILTIN_SHAPES + GetContainerShape (shape-only) and CDMSpellData.ResolveEntryKind
-- (entry-only) instead.
local BUILTIN_CONTAINER_TYPES = {
    essential  = "cooldown",
    utility    = "cooldown",
    buff       = "aura",
    trackedBar = "auraBar",
}

-- Shape is a layout/render concern — does the container draw icons or
-- StatusBars. Independent of whether entries are auras or cooldowns.
-- Only trackedBar is a true StatusBar today (real bar mirror); essential,
-- utility, buff, and migrated customBar containers all render as icons.
local BUILTIN_SHAPES = {
    essential  = "icon",
    utility    = "icon",
    buff       = "icon",
    trackedBar = "bar",
}

---------------------------------------------------------------------------
-- Resolve container shape ("icon" or "bar") for a given container key.
-- Reads db.shape if present, else falls back to BUILTIN_SHAPES, else
-- infers from legacy containerType (auraBar → bar; everything else → icon).
---------------------------------------------------------------------------
local function GetContainerShape(viewerType)
    if not viewerType then return "icon" end

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

    if BUILTIN_SHAPES[viewerType] then
        return BUILTIN_SHAPES[viewerType]
    end

    if cDB and cDB.containerType == "auraBar" then
        return "bar"
    end

    return "icon"
end

local function IsBarShape(viewerType)
    return GetContainerShape(viewerType) == "bar"
end

local function ShouldDeferContainerLayoutInCombat(trackerKey, settings)
    if not InCombatLockdown() or inInitSafeWindow then
        return false
    end

    -- Built-in essential/utility wrap Blizzard CDM viewer children whose
    -- start/dur become "secret" in combat — laying out then would taint.
    if trackerKey == "essential" or trackerKey == "utility" then
        return true
    end

    -- Clickable custom bars wire SecureActionButton children on each icon
    -- (see UpdateIconSecureAttributes); reflowing in combat would taint.
    -- Non-clickable custom cooldown bars are addon-owned with no secure
    -- attributes, so they may relayout in combat — required for filter
    -- flips (Mana Tea becoming usable, etc.) to collapse the bar without
    -- waiting for PLAYER_REGEN_ENABLED.
    if settings and settings.clickableIcons then
        return true
    end

    return false
end

---------------------------------------------------------------------------
-- CONTAINER DEFAULTS BY TYPE (used when creating new custom containers)
---------------------------------------------------------------------------
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
                borderColorTable = {0, 0, 0, 1}, aspectRatioCrop = 1.0,
                zoom = 0, padding = 2, xOffset = 0, yOffset = 0,
                hideDurationText = false, durationSize = 16,
                durationOffsetX = 0, durationOffsetY = 0,
                stackSize = 12, stackOffsetX = 0, stackOffsetY = 2,
                durationTextColor = {1, 1, 1, 1}, durationAnchor = "CENTER",
                stackTextColor = {1, 1, 1, 1}, stackAnchor = "BOTTOMRIGHT",
            },
            row2 = {
                iconCount = 0, iconSize = 39, borderSize = 1,
                borderColorTable = {0, 0, 0, 1}, aspectRatioCrop = 1.0,
                zoom = 0, padding = 2, xOffset = 0, yOffset = 3,
                durationSize = 16, durationOffsetX = 0, durationOffsetY = 0,
                stackSize = 12, stackOffsetX = 0, stackOffsetY = 2,
                durationTextColor = {1, 1, 1, 1}, durationAnchor = "CENTER",
                stackTextColor = {1, 1, 1, 1}, stackAnchor = "BOTTOMRIGHT",
            },
            row3 = {
                iconCount = 0, iconSize = 39, borderSize = 1,
                borderColorTable = {0, 0, 0, 1}, aspectRatioCrop = 1.0,
                zoom = 0, padding = 2, xOffset = 0, yOffset = 0,
                durationSize = 16, durationOffsetX = 0, durationOffsetY = 0,
                stackSize = 12, stackOffsetX = 0, stackOffsetY = 2,
                durationTextColor = {1, 1, 1, 1}, durationAnchor = "CENTER",
                stackTextColor = {1, 1, 1, 1}, stackAnchor = "BOTTOMRIGHT",
            },
            rangeColor = {0.8, 0.1, 0.1},
            ownedSpells = {},
            removedSpells = {},
            dormantSpells = {},
            spellOverrides = {},
            iconDisplayMode = "always",
            -- Keybind display
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

---------------------------------------------------------------------------
-- CONTAINER MANAGEMENT API
-- Dynamic container creation, deletion, rename, query.
---------------------------------------------------------------------------
CDMContainers_API = {}

--- Generate a unique container key for custom containers.
local function GenerateContainerKey()
    return "custom_" .. time() .. "_" .. math.random(1000, 9999)
end

--- Get all containers from the unified table, ordered: built-in first, then custom by key.
function CDMContainers_API:GetContainers()
    local db = GetDB()
    local ct = db and db.containers
    if not ct then return {} end

    local result = {}
    -- Built-in containers first, in canonical order
    for _, key in ipairs(BUILTIN_KEYS) do
        if ct[key] then
            result[#result + 1] = { key = key, settings = ct[key] }
        end
    end
    -- Custom containers sorted alphabetically by key
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

--- Get settings for a specific container from the unified table.
function CDMContainers_API:GetContainerSettings(key)
    local db = GetDB()
    if not db then return nil end
    if db.containers and db.containers[key] then
        return db.containers[key]
    end
    return db[key] or nil
end

--- Filter containers by containerType.
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

--- Create a new custom container. Returns the new containerKey.
function CDMContainers_API:CreateContainer(name, containerType)
    if InCombatLockdown() then return nil end
    if not name or name == "" then name = "Custom" end
    if not containerType then containerType = "cooldown" end

    local db = GetDB()
    if not db then return nil end
    if not db.containers then db.containers = {} end

    local key = GenerateContainerKey()
    local settings = GetDefaultsByContainerType(containerType)
    settings.builtIn = false
    settings.name = name
    settings.containerType = containerType
    settings.shape = (containerType == "auraBar") and "bar" or "icon"
    settings.ownedSpells = {}  -- custom containers start empty

    db.containers[key] = settings

    -- Also write to top-level ncdm[key] for backward compat with existing code paths
    db[key] = settings

    -- Create the container frame
    local frameName = "QUI_CDM_" .. key
    local frame = RegisterContainerFrame(key, CreateContainer(frameName))
    -- Position at center initially with a minimum size so the mover is visible.
    -- Override alpha=0 from CreateContainer (hud_visibility handles built-in containers,
    -- but custom containers created during edit mode need to be visible immediately).
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetSize(100, 40)
    frame:SetAlpha(1)
    frame:Show()

    -- Save initial position to DB so RestoreContainerPosition and layout mode find it
    settings.pos = { ox = 0, oy = 0 }

    -- Register icon pool for the new container
    if ns.CDMIcons then
        ns.CDMIcons:EnsurePool(key)
    end

    -- Register layout mode element dynamically
    self:RegisterDynamicLayoutElement(key, settings)

    -- Register frame resolver dynamically
    self:RegisterDynamicFrameResolver(key, settings)

    -- Invalidate caches
    if ns.InvalidateCDMFrameCache then ns.InvalidateCDMFrameCache() end

    -- Refresh layout mode movers if layout mode is active
    local um = ns.QUI_LayoutMode
    if um and um.RefreshMovers then
        um:RefreshMovers()
    end

    SyncSettingsFeatureLookups()

    return key
end

--- Delete a custom container. Returns true on success.
function CDMContainers_API:DeleteContainer(containerKey)
    if InCombatLockdown() then return false end

    local db = GetDB()
    if not db or not db.containers then return false end
    local settings = db.containers[containerKey]
    if not settings then return false end
    if settings.builtIn then return false end  -- cannot delete built-in

    -- Remove from DB
    db.containers[containerKey] = nil
    db[containerKey] = nil

    -- Destroy the frame
    local frame = containers[containerKey]
    if frame then
        frame:Hide()
        frame:ClearAllPoints()
        frame:SetParent(nil)
        containers[containerKey] = nil
        viewerState[frame] = nil
    end

    -- Release icon pool
    if ns.CDMIcons then
        ns.CDMIcons:ClearPool(containerKey)
    end

    -- Unregister layout mode element
    local um = ns.QUI_LayoutMode
    if um and um.UnregisterElement then
        um:UnregisterElement("cdmCustom_" .. containerKey)
    end

    -- Unregister frame resolver
    if _G.QUI_UnregisterFrameResolver then
        _G.QUI_UnregisterFrameResolver("cdmCustom_" .. containerKey)
    end

    -- Invalidate caches
    if ns.InvalidateCDMFrameCache then ns.InvalidateCDMFrameCache() end

    SyncSettingsFeatureLookups()

    return true
end

--- Rename a container. Updates both DB and layout mode label.
function CDMContainers_API:RenameContainer(containerKey, newName)
    if not newName or newName == "" then return false end

    local db = GetDB()
    if not db or not db.containers then return false end
    local settings = db.containers[containerKey]
    if not settings then return false end

    settings.name = newName

    -- Update layout mode label if registered
    local um = ns.QUI_LayoutMode
    if um and um.UpdateElementLabel then
        um:UpdateElementLabel("cdmCustom_" .. containerKey, newName)
    end

    return true
end

--- Get the container frame for a given key.
function CDMContainers_API:GetContainer(key)
    return containers[key]
end

--- Register a layout mode element for a custom container.
function CDMContainers_API:RegisterDynamicLayoutElement(containerKey, settings)
    local um = ns.QUI_LayoutMode
    if not um then return end

    local elementKey = "cdmCustom_" .. containerKey
    um:RegisterElement({
        key = elementKey,
        label = settings.name or containerKey,
        group = "Cooldown Manager & Custom Tracker Bars",
        order = 100,  -- custom containers sort after built-in
        isOwned = true,
        isEnabled = function()
            local core = ns.Helpers.GetCore()
            local ncdm = core and core.db and core.db.profile and core.db.profile.ncdm
            if not ncdm or ncdm.enabled == false then return false end
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

--- Register a frame resolver in the anchoring system for a custom container.
function CDMContainers_API:RegisterDynamicFrameResolver(containerKey, settings)
    -- Register via the global hook that anchoring.lua exposes
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

--- Get all container keys (built-in + custom), in order.
function CDMContainers_API:GetAllContainerKeys()
    local db = GetDB()
    local ct = db and db.containers
    if not ct then return BUILTIN_KEYS end

    -- Always include all built-in keys — they live at ncdm[key], not
    -- in ncdm.containers, so checking ct[key] would exclude them.
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

---------------------------------------------------------------------------
-- HELPER: Update locked power bars and castbars
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- HELPER: Get total icon capacity from row settings
---------------------------------------------------------------------------
local function GetTotalIconCapacity(settings)
    local total = 0
    for i = 1, 3 do
        local rowKey = "row" .. i
        if settings[rowKey] and settings[rowKey].iconCount then
            total = total + settings[rowKey].iconCount
        end
    end
    return total
end

---------------------------------------------------------------------------
-- UTILITY ANCHOR PROXY
---------------------------------------------------------------------------
local function GetUtilityAnchorProxy()
    if not UtilityAnchorProxy then
        UtilityAnchorProxy = UIKit.CreateAnchorProxy(nil, {
            -- Utility↔Essential spacing must track live Essential bounds in combat.
            combatFreeze = false,
            mirrorVisibility = false,
            sizeResolver = function(source)
                local vs = viewerState[source]
                local width = (vs and vs.cdmIconWidth) or Helpers.SafeToNumber(source:GetWidth(), 0)
                local height = (vs and vs.cdmTotalHeight) or Helpers.SafeToNumber(source:GetHeight(), 0)
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

---------------------------------------------------------------------------
-- CONTAINER CREATION
---------------------------------------------------------------------------
CreateContainer = function(name)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetSize(1, 1)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetAlpha(0)  -- start invisible; hud_visibility fades in after icons are built
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

-- Tracker key → frameAnchoring key mapping
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

-- Save a QUI container's current position to the DB.
-- Called after Edit Mode exit so positions persist across sessions.
-- Also updates frameAnchoring offsets (if enabled) so the anchoring
-- system doesn't overwrite the container with stale values on next refresh.
local function SaveContainerPosition(trackerKey)
    local container = containers[trackerKey]
    if not container then return end
    local db = GetTrackerSettings(trackerKey)
    if not db then return end
    local rawCx, rawCy = container:GetCenter()
    local rawSx, rawSy = UIParent:GetCenter()
    local cx = Helpers.SafeToNumber(rawCx)
    local cy = Helpers.SafeToNumber(rawCy)
    local sx = Helpers.SafeToNumber(rawSx)
    local sy = Helpers.SafeToNumber(rawSy)
    if cx and cx ~= 0 and cy and cy ~= 0 and sx and sy then
        local ox = cx - sx
        local oy = cy - sy
        db.pos = { ox = ox, oy = oy }

        -- Keep frameAnchoring in sync so ApplyAllFrameAnchors uses the
        -- updated position instead of overwriting with a stale offset.
        -- Only sync when parent is screen (offsets are UIParent-center based).
        local anchorKey = ANCHOR_KEY_MAP[trackerKey] or ("cdmCustom_" .. trackerKey)
        if anchorKey then
            local profile = QUICore and QUICore.db and QUICore.db.profile
            local anchoringDB = profile and profile.frameAnchoring
            local settings = anchoringDB and anchoringDB[anchorKey]
            if settings and settings.enabled ~= false then
                local parent = settings.parent or "screen"
                if parent == "screen" or parent == "disabled" then
                    -- ox/oy are CENTER→CENTER offsets. If the anchoring config
                    -- uses a non-CENTER point/relative pair, reverse the
                    -- ComputeCenterOffsetsForAnchor math so
                    -- ApplyFrameAnchor produces the correct screen position.
                    -- Equation: centerOff = targetOff + offset - sourceOff
                    -- So:       offset    = centerOff - targetOff + sourceOff
                    local pt  = settings.point or "CENTER"
                    local rel = settings.relative or "CENTER"
                    if pt == "CENTER" and rel == "CENTER" then
                        settings.offsetX = ox
                        settings.offsetY = oy
                    else
                        local vs = viewerState[container]
                        local frameW = (vs and (vs.cdmIconWidth or vs.row1Width)) or Helpers.SafeValue(container:GetWidth(), 1) or 1
                        local frameH = (vs and vs.cdmTotalHeight) or Helpers.SafeValue(container:GetHeight(), 1) or 1
                        local parentW = Helpers.SafeValue(UIParent:GetWidth(), 1) or 1
                        local parentH = Helpers.SafeValue(UIParent:GetHeight(), 1) or 1
                        local srcX, srcY = PointOffset(pt, frameW, frameH)
                        local tgtX, tgtY = PointOffset(rel, parentW, parentH)
                        settings.offsetX = ox - tgtX + srcX
                        settings.offsetY = oy - tgtY + srcY
                    end
                end
            end
        end
    end
end

-- Restore a QUI container's position from the DB.
-- Checks frameAnchoring first (if enabled with screen parent, its offsets
-- are the authoritative source since it would overwrite us on next refresh).
-- Falls back to ncdm.pos.  Returns true if a position was applied.
local function RestoreContainerPosition(container, trackerKey)
    if not container then return false end

    -- During layout mode, handles own frame positions — skip restoring
    -- from DB so we don't yank the container away from its mover.
    local anchorKey = ANCHOR_KEY_MAP[trackerKey] or ("cdmCustom_" .. trackerKey)
    if anchorKey and _G.QUI_IsLayoutModeManaged and _G.QUI_IsLayoutModeManaged(anchorKey) then
        return true
    end

    -- If the centralized frame anchoring system has an enabled override for
    -- this CDM key with a screen parent, use its CENTER offsets directly.
    -- When anchored to another frame (e.g. "playerFrame"), the offsets are
    -- relative to that parent — let the anchoring system handle it later.
    if anchorKey then
        local profile = QUICore and QUICore.db and QUICore.db.profile
        local anchoringDB = profile and profile.frameAnchoring
        local settings = anchoringDB and anchoringDB[anchorKey]
        if settings and settings.enabled ~= false then
            local parent = settings.parent or "screen"
            if parent == "screen" or parent == "disabled" then
                local ox = settings.offsetX or 0
                local oy = settings.offsetY or 0
                container:ClearAllPoints()
                container:SetPoint("CENTER", UIParent, "CENTER", ox, oy)
                return true
            end
            -- Anchored to another frame — return true to skip Blizzard seeding;
            -- the anchoring system will position us on the next refresh pass.
            return true
        end
    end

    -- Fall back to ncdm.pos
    local db = GetTrackerSettings(trackerKey)
    if not db or not db.pos then return false end
    local ox = db.pos.ox
    local oy = db.pos.oy
    if ox and oy then
        container:ClearAllPoints()
        container:SetPoint("CENTER", UIParent, "CENTER", ox, oy)
        return true
    end
    return false
end

-- Restore container position from DB.  If no saved position exists
-- (first-ever init), the container stays at screen center (0,0).
local function InitContainerPosition(container, trackerKey)
    RestoreContainerPosition(container, trackerKey)
end

local function EnsureContainerBootstrapSize(container, trackerKey)
    if not container then return end
    local cw = Helpers.SafeValue(container:GetWidth(), 0)
    local ch = Helpers.SafeValue(container:GetHeight(), 0)
    if cw > 1 and ch > 1 then return end

    local vs = viewerState[container]
    local boundsW = vs and Helpers.SafeToNumber(vs.cdmIconWidth, 0) or 0
    local boundsH = vs and Helpers.SafeToNumber(vs.cdmTotalHeight, 0) or 0
    if boundsW > 1 and boundsH > 1 then
        container:SetSize(boundsW, boundsH)
        return
    end

    if trackerKey == "trackedBar" then
        local db = GetDB()
        local tbs = db and db.trackedBar
        container:SetSize((tbs and tbs.barWidth) or 215, (tbs and tbs.barHeight) or 25)
    elseif trackerKey == "buff" then
        -- Match buffbar.lua's single-icon dims so the anchored edge's
        -- midpoint doesn't shift when LayoutBuffIcons resizes to real
        -- iconSize under a non-center anchor (e.g. anchored to Essential).
        local db = GetDB()
        local buff = db and db.buff
        local iconSize = (buff and buff.iconSize) or 30
        local aspectRatio = (buff and buff.aspectRatioCrop) or 1.0
        local iconWidth, iconHeight = iconSize, iconSize
        if aspectRatio > 1.0 then
            iconHeight = iconSize / aspectRatio
        elseif aspectRatio < 1.0 then
            iconWidth = iconSize * aspectRatio
        end
        container:SetSize(iconWidth, iconHeight)
    else
        container:SetSize(100, 40)
    end
end

-- Blizzard viewer name lookup (used by Edit Mode and position save)
local VIEWER_NAMES_MAP = {
    essential  = "EssentialCooldownViewer",
    utility    = "UtilityCooldownViewer",
    buff       = "BuffIconCooldownViewer",
    trackedBar = "BuffBarCooldownViewer",
}

local function InitContainers()
    if containers.essential then return end -- already created

    RegisterContainerFrame("essential", CreateContainer("QUI_EssentialContainer"))
    RegisterContainerFrame("utility", CreateContainer("QUI_UtilityContainer"))
    RegisterContainerFrame("buff", CreateContainer("QUI_BuffContainer"))
    RegisterContainerFrame("trackedBar", CreateContainer("QUI_BuffBarContainer"))

    InitContainerPosition(containers.essential, "essential")
    InitContainerPosition(containers.utility, "utility")
    -- Buff: skip position init when anchored — ApplyBuffIconAnchor manages position.
    local db = GetDB()
    local anchorTo = db and db.buff and db.buff.anchorTo or "disabled"
    if anchorTo == "disabled" then
        InitContainerPosition(containers.buff, "buff")
    end
    -- TrackedBar: skip position init when anchored — ApplyTrackedBarAnchor manages position.
    local barAnchorTo = db and db.trackedBar and db.trackedBar.anchorTo or "disabled"
    if barAnchorTo == "disabled" then
        InitContainerPosition(containers.trackedBar, "trackedBar")
    end

    EnsureContainerBootstrapSize(containers.essential, "essential")
    EnsureContainerBootstrapSize(containers.utility, "utility")
    EnsureContainerBootstrapSize(containers.buff, "buff")
    EnsureContainerBootstrapSize(containers.trackedBar, "trackedBar")

    -- Phase G: Create frames for any custom containers in the unified table.
    -- Phase B.3: customBar containers (migrated from legacy custom trackers)
    -- are rendered by the unified CDM renderer like any other custom
    -- container — no filter needed.
    if db and db.containers then
        for key, settings in pairs(db.containers) do
            if not BUILTIN_NAMES[key]
               and not containers[key]
               and settings then
                local frameName = "QUI_CDM_" .. key
                local frame = RegisterContainerFrame(key, CreateContainer(frameName))
                InitContainerPosition(frame, key)
                -- Ensure icon pool exists
                if ns.CDMIcons then
                    ns.CDMIcons:EnsurePool(key)
                end
                -- Register frame resolver so the anchoring system can find
                -- this container (hideWithParent, anchor chains, etc.)
                CDMContainers_API:RegisterDynamicFrameResolver(key, settings)
            end
        end
    end
end

-- Deferred init for buff container (viewer may load after us)
-- The addon-owned QUI_BuffContainer is created in InitContainers().
-- This function ensures it exists and notifies buffbar.lua.
local function InitBuffContainer()
    if not containers.buff then
        -- InitContainers hasn't run yet -- create the container now
        RegisterContainerFrame("buff", CreateContainer("QUI_BuffContainer"))
    end
    -- Restore position from DB (or seed from Blizzard viewer on first-ever init).
    -- Skip when anchored — ApplyBuffIconAnchor manages position.
    local db = GetDB()
    local anchorTo = db and db.buff and db.buff.anchorTo or "disabled"
    if anchorTo == "disabled" then
        InitContainerPosition(containers.buff, "buff")
    end
    if ns.InvalidateCDMFrameCache then ns.InvalidateCDMFrameCache() end
    -- Notify buffbar.lua to set up hooks on the new container
    if _G.QUI_OnBuffContainerReady then
        C_Timer.After(0.1, _G.QUI_OnBuffContainerReady)
    end
end

-- Forward declarations needed by LayoutContainer (Edit Mode guards).
local _editModeActive = false
local _disabledMouseFrames = {}
local _forceLayoutKey = nil  -- set temporarily to bypass edit mode check for one container

local function IsCDMMouseoverFadeEnabled()
    local vis = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.cdmVisibility
    return vis and not vis.showAlways and vis.showOnMouseover
end

local function SetFrameMouseDisabled(frame)
    if not frame or frame._quiMouseMode == "disabled" then
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
    if not frame or frame._quiMouseMode == "hover" then
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
    if not icon or icon._quiMouseMode == "default" then
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
    if ns.CDMIcons and ns.CDMIcons.UpdateIconSecureAttributes then
        ns.CDMIcons.UpdateIconSecureAttributes(icon, icon._spellEntry, viewerType)
    end
    icon._quiClickButtonSuppressed = nil
    icon._pendingVisibilityMouseSync = nil
end

local function SyncContainerIconsForVisibility(containerKey, hidden, hoverOnly)
    if not ns.CDMIcons or not ns.CDMIcons.GetIconPool then
        return
    end

    local pool = ns.CDMIcons:GetIconPool(containerKey) or {}
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
        alpha = Helpers.SafeToNumber(alphaOverride, nil)
    end
    if alpha == nil and container.GetAlpha then
        alpha = Helpers.SafeToNumber(container:GetAlpha(), 1)
    end
    alpha = alpha or 1

    local hidden = alpha <= 0.001
    local hoverOnly = IsCDMMouseoverFadeEnabled()
    local stateChanged = (container._quiAlphaHidden ~= hidden) or (container._quiHoverOnly ~= hoverOnly)

    if hoverOnly then
        SetFrameHoverOnly(container)
    else
        SetFrameMouseDisabled(container)
    end

    if not (force or stateChanged) then
        return
    end

    container._quiAlphaHidden = hidden
    container._quiHoverOnly = hoverOnly

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

---------------------------------------------------------------------------
-- CORE: Layout icons in a container
-- Ported from cdm_viewer.lua:1069-1554 for addon-owned containers.
---------------------------------------------------------------------------
local function LayoutContainer(trackerKey)
    local container = containers[trackerKey]
    if not container then return end

    -- Aura containers may rebuild during combat. Cooldown containers can have
    -- SecureActionButton children for click-to-cast, so their visibility/layout
    -- work is deferred until combat ends.

    -- Edit Mode: containers are visible with overlays but skip layout
    -- to avoid flicker while the user is looking at overlays.  Icons are
    -- already rendered.  RefreshAll() on Edit Mode exit rebuilds everything.
    -- Exception: _forceLayoutKey allows the Composer to force layout for
    -- a specific container during edit mode (so it resizes when spells change).
    if _editModeActive and trackerKey ~= _forceLayoutKey then return end

    local settings = GetTrackerSettings(trackerKey)
    if ShouldDeferContainerLayoutInCombat(trackerKey, settings) then
        specTrackingPendingRefresh = true
        return
    end

    -- Built-in containers default to enabled when no settings exist
    -- or when enabled is nil (never explicitly disabled by user).
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

    -- Re-entry guard
    if applying[trackerKey] then return end
    applying[trackerKey] = true

    -- Respect "hide with anchor" — the anchoring system hid this container
    -- because its anchor parent is hidden. Let layout proceed (so icons stay
    -- up-to-date) but don't re-show the container.
    local anchorHidden = false
    if _G.QUI_IsFrameHiddenByAnchor then
        local anchorKey = ANCHOR_KEY_MAP[trackerKey] or ("cdmCustom_" .. trackerKey)
        anchorHidden = _G.QUI_IsFrameHiddenByAnchor(anchorKey)
    end

    if not anchorHidden then
        container:Show()
    end

    -- Apply HUD layer priority
    local hudLayering = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.hudLayering
    local layerPriority = hudLayering and hudLayering[trackerKey] or 5
    if QUICore and QUICore.GetHUDFrameLevel then
        local frameLevel = QUICore:GetHUDFrameLevel(layerPriority)
        container:SetFrameLevel(frameLevel)
    end

    local vs = viewerState[container]
    if not vs then
        viewerState[container] = {}
        vs = viewerState[container]
    end

    -- Check for vertical layout mode
    local layoutDirection = settings.layoutDirection or "HORIZONTAL"
    local isVertical = (layoutDirection == "VERTICAL")
    vs.cdmLayoutDirection = layoutDirection

    -- Buff tracker: create addon-owned icons via icon factory, adopt
    -- Blizzard CooldownFrames for taint-safe aura display.
    -- Blizzard's children stay in the hidden viewer (alpha=0).
    -- buffbar.lua handles positioning and styling of addon-owned icons.
    if trackerKey == "buff" then
        InitBuffContainer()
        container = containers.buff
        if not container then
            applying[trackerKey] = false
            return
        end

        -- Ensure buff container has a minimum size so overlays and anchor
        -- proxies have valid bounds before any buffs are active.
        -- Do NOT size from Blizzard's BuffIconCooldownViewer: in some states
        -- it reports one-icon bounds, which shrinks the owned container and
        -- clips overlapping slot-backed icons. Prefer the owned-layout bounds
        -- cached by LayoutBuffIcons() via QUI_SetCDMViewerBounds().
        local cw = Helpers.SafeValue(container:GetWidth(), 0)
        local ch = Helpers.SafeValue(container:GetHeight(), 0)
        if cw <= 1 or ch <= 1 then
            EnsureContainerBootstrapSize(container, "buff")
        end

        -- Fingerprint: skip rebuild when the same buff spellIDs are active.
        -- Aura events fire on stack/duration changes too, but the icon set
        -- only changes when buffs are gained or lost.
        local spellData = ns.CDMSpellData and ns.CDMSpellData:GetSpellList("buff") or {}
        local parts = {}
        for i, entry in ipairs(spellData) do
            parts[i] = table.concat({
                tostring(entry.spellID or 0),
                tostring(entry.id or 0),
                tostring(entry._isTotemInstance and 1 or 0),
                tostring(entry._totemSlot or 0),
                tostring(entry._instanceKey or ""),
            }, ":")
        end
        local fingerprint = table.concat(parts, ",")

        local currentPool = ns.CDMIcons and ns.CDMIcons:GetIconPool("buff") or {}
        if fingerprint == (buffFingerprint or "") and #currentPool > 0 then
            -- Same buff set -- skip destructive rebuild
            applying[trackerKey] = false
            return
        end
        buffFingerprint = fingerprint

        if not ns.CDMIcons then
            applying[trackerKey] = false
            return
        end

        -- Build addon-owned icons (adopts Blizzard CooldownFrames)
        local allIcons = ns.CDMIcons:BuildIcons("buff", container)
        for _, icon in ipairs(allIcons) do
            -- During Edit Mode, new icons need mouse disabled so clicks
            -- reach Blizzard's .Selection in secure context.
            if Helpers.IsEditModeActive() then
                icon:Show()
                icon:EnableMouse(false)
                _disabledMouseFrames[icon] = "icon"
            end
        end

        applying[trackerKey] = false

        -- Apply full visibility rules before buff icon layout so the
        -- buffbar callback measures and positions the final shown/hidden
        -- set, instead of laying out once pre-visibility and again after
        -- active-only filtering settles.
        if ns.CDMIcons and ns.CDMIcons.UpdateAllCooldowns then
            ns.CDMIcons:UpdateAllCooldowns()
        end
        -- Notify buffbar.lua to position + style icons immediately once
        -- visibility has settled for this rebuild batch.
        if _G.QUI_OnBuffLayoutReady then
            _G.QUI_OnBuffLayoutReady()
        end
        return
    end

    -- Build icons via the icon factory (essential/utility only)
    local allIcons = ns.CDMIcons:BuildIcons(trackerKey, container)
    local totalCapacity = GetTotalIconCapacity(settings)

    -- Determine display mode for hidden-spell layout handling
    local displayMode = settings.iconDisplayMode or "always"
    local effectiveDisplayMode = displayMode
    if effectiveDisplayMode == "combat" then
        effectiveDisplayMode = InCombatLockdown() and "always" or "active"
    end
    local CDMSpellData = ns.CDMSpellData

    -- Select icons to layout (up to capacity)
    local editModeActive = Helpers.IsEditModeActive()
        or (_G.QUI_IsCDMEditModeActive and _G.QUI_IsCDMEditModeActive())
    -- When dynamicLayout is on (default), visibility filters must drop
    -- icons at layout time so row width / centering collapse around the
    -- missing slot. Otherwise filters hide the icon after layout and
    -- leave a gap in the bar.
    local dynamicLayoutEnabled
    if settings.containerType == "customBar" then
        dynamicLayoutEnabled = settings.dynamicLayout == true
    else
        dynamicLayoutEnabled = settings.dynamicLayout ~= false
    end
    local ComputeFilterHides = ns.CDMIcons and ns.CDMIcons.ComputeFilterHides
    local iconsToLayout = {}
    for i = 1, math.min(#allIcons, totalCapacity) do
        local icon = allIcons[i]
        local skipIcon = false

        -- In "active" display mode, skip hidden-override icons entirely
        -- (no space reserved). In "always" mode they still occupy a slot.
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

        -- Drop filtered icons (e.g. Hide Non-Usable items with 0 count,
        -- Show Only On Cooldown when off-cd) so the layout collapses.
        -- inCombat reflects whether layout is running mid-fight; for non-
        -- clickable custom cooldown bars ShouldDeferContainerLayoutInCombat
        -- now allows that path so filter flips during combat (mana-tea
        -- becoming usable, etc.) trigger a re-anchor instead of waiting
        -- for PLAYER_REGEN_ENABLED.
        if not skipIcon and not editModeActive
           and dynamicLayoutEnabled and ComputeFilterHides then
            local entry = icon._spellEntry
            if entry then
                local isOnCD = icon._hasCooldownActive or false
                local inCombatNow = UnitAffectingCombat and UnitAffectingCombat("player") or false
                local filterHides = ComputeFilterHides(icon, entry, settings, inCombatNow, isOnCD)
                icon._lastLayoutFilterHidden = filterHides and true or false
                if filterHides then
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

    -- Hide overflow icons
    for i = totalCapacity + 1, #allIcons do
        if allIcons[i] then
            allIcons[i]:Hide()
            allIcons[i]:ClearAllPoints()
        end
    end

    if #iconsToLayout == 0 then
        applying[trackerKey] = false
        return
    end

    -- Build row config
    local rows = {}
    for i = 1, 3 do
        local rowKey = "row" .. i
        if settings[rowKey] and settings[rowKey].iconCount and settings[rowKey].iconCount > 0 then
            MigrateRowAspect(settings[rowKey])
            rows[#rows + 1] = {
                rowNum = i,  -- actual row number (1, 2, or 3)
                count = settings[rowKey].iconCount,
                size = settings[rowKey].iconSize or 50,
                borderSize = settings[rowKey].borderSize or 2,
                borderColorTable = settings[rowKey].borderColorTable or {0, 0, 0, 1},
                aspectRatioCrop = settings[rowKey].aspectRatioCrop or 1.0,
                zoom = settings[rowKey].zoom or 0,
                padding = settings[rowKey].padding or 0,
                yOffset = settings[rowKey].yOffset or 0,
                xOffset = settings[rowKey].xOffset or 0,
                durationSize = settings[rowKey].durationSize or 14,
                durationOffsetX = settings[rowKey].durationOffsetX or 0,
                durationOffsetY = settings[rowKey].durationOffsetY or 0,
                durationTextColor = settings[rowKey].durationTextColor or {1, 1, 1, 1},
                durationAnchor = settings[rowKey].durationAnchor or "CENTER",
                stackSize = settings[rowKey].stackSize or 14,
                stackOffsetX = settings[rowKey].stackOffsetX or 0,
                stackOffsetY = settings[rowKey].stackOffsetY or 0,
                stackTextColor = settings[rowKey].stackTextColor or {1, 1, 1, 1},
                stackAnchor = settings[rowKey].stackAnchor or "BOTTOMRIGHT",
                opacity = settings[rowKey].opacity or 1.0,
            }
        end
    end

    if #rows == 0 then
        applying[trackerKey] = false
        return
    end

    -- Pre-sort iconsToLayout by assigned row so each row gets its assigned icons.
    -- Must happen BEFORE dimension calculations so row sizes are correct.
    -- Also overrides each row's effective count to match actual icon distribution.
    if #rows > 1 then
        local buckets = {}
        local noRow = {}
        for _, icon in ipairs(iconsToLayout) do
            local ar = icon._spellEntry and icon._spellEntry._assignedRow
            if ar then
                if not buckets[ar] then buckets[ar] = {} end
                buckets[ar][#buckets[ar] + 1] = icon
            else
                noRow[#noRow + 1] = icon
            end
        end
        local sorted = {}
        local noRowIdx = 1
        for ri, rowConfig in ipairs(rows) do
            local rn = rowConfig.rowNum
            local rowStart = #sorted + 1
            -- Add assigned icons for this row
            if buckets[rn] then
                for _, icon in ipairs(buckets[rn]) do
                    sorted[#sorted + 1] = icon
                end
            end
            -- Fill remaining capacity with unassigned icons
            local assigned = buckets[rn] and #buckets[rn] or 0
            local remaining = rowConfig.count - assigned
            for _ = 1, remaining do
                if noRowIdx <= #noRow then
                    sorted[#sorted + 1] = noRow[noRowIdx]
                    noRowIdx = noRowIdx + 1
                end
            end
            -- Override this row's count to the actual number of icons placed
            rowConfig._actualCount = #sorted - rowStart + 1
        end
        -- Append any leftover unassigned icons (overflow)
        while noRowIdx <= #noRow do
            sorted[#sorted + 1] = noRow[noRowIdx]
            noRowIdx = noRowIdx + 1
        end
        iconsToLayout = sorted
    end

    -- Migrated customBar containers store growth as the legacy `growDirection`
    -- field ("LEFT"/"RIGHT"/"UP"/"DOWN"), not `growthDirection`. The composer
    -- preview reverses the display for LEFT/UP so entries[1] ends up at the
    -- bar's anchor end; mirror that here so render matches preview.
    if settings.containerType == "customBar" then
        local gd = settings.growDirection
        if gd == "LEFT" or gd == "UP" then
            local reversed = {}
            for i = #iconsToLayout, 1, -1 do
                reversed[#reversed + 1] = iconsToLayout[i]
            end
            iconsToLayout = reversed
        end
    end

    -- Calculate potential row widths (for power bars / castbars)
    local potentialRow1Width = 0
    local potentialBottomRowWidth = 0
    if rows[1] then
        potentialRow1Width = (rows[1].count * rows[1].size) + ((rows[1].count - 1) * (rows[1].padding or 0))
    end
    if rows[#rows] then
        potentialBottomRowWidth = (rows[#rows].count * rows[#rows].size) + ((rows[#rows].count - 1) * (rows[#rows].padding or 0))
    end

    -- Calculate row/column dimensions
    -- Use first row's padding as vertical gap between rows so spacing is uniform
    local rowGap = (rows[1] and rows[1].padding) or ROW_GAP
    local iconIndex = 1
    local maxRowWidth = 0
    local maxColHeight = 0
    local rowWidths = {}
    local colHeights = {}
    local tempIndex = 1

    for rowNum, rowConfig in ipairs(rows) do
        local rowCount = rowConfig._actualCount or rowConfig.count
        local iconsInRow = math.min(rowCount, #iconsToLayout - tempIndex + 1)
        if iconsInRow > 0 then

        local iconWidth = rowConfig.size
        local aspectRatio = rowConfig.aspectRatioCrop or 1.0
        local iconHeight = rowConfig.size / aspectRatio

        if isVertical then
            local colHeight = (iconsInRow * iconHeight) + ((iconsInRow - 1) * rowConfig.padding)
            colHeights[rowNum] = colHeight
            rowWidths[rowNum] = iconWidth
            if colHeight > maxColHeight then maxColHeight = colHeight end
        else
            local rowWidth = (iconsInRow * iconWidth) + ((iconsInRow - 1) * rowConfig.padding)
            rowWidths[rowNum] = rowWidth
            if rowWidth > maxRowWidth then maxRowWidth = rowWidth end
        end
        tempIndex = tempIndex + iconsInRow
        end -- if iconsInRow > 0
    end

    -- Calculate total width/height for CENTER-based positioning
    local totalHeight = 0
    local totalWidth = 0
    local rowHeights = {}
    local numRowsUsed = 0
    local tempIdx = 1

    for rowNum, rowConfig in ipairs(rows) do
        local rowCount = rowConfig._actualCount or rowConfig.count
        local iconsInRow = math.min(rowCount, #iconsToLayout - tempIdx + 1)
        if iconsInRow > 0 then

        local aspectRatio = rowConfig.aspectRatioCrop or 1.0
        local iconHeight = rowConfig.size / aspectRatio
        local iconWidth = rowConfig.size
        rowHeights[rowNum] = iconHeight
        numRowsUsed = numRowsUsed + 1

        if isVertical then
            totalWidth = totalWidth + iconWidth
            if numRowsUsed > 1 then totalWidth = totalWidth + rowGap end
        else
            totalHeight = totalHeight + iconHeight
            if numRowsUsed > 1 then totalHeight = totalHeight + rowGap end
        end
        tempIdx = tempIdx + iconsInRow
        end -- if iconsInRow > 0
    end

    if isVertical then
        totalHeight = maxColHeight
        maxRowWidth = totalWidth
    end

    -- Compute yOffset-adjusted envelope for proxy sizing
    local baseTotalHeight = totalHeight
    local proxyTotalHeight = totalHeight
    vs.cdmProxyYOffset = 0
    local growReverse = (settings.growthDirection == "UP")
    local growUp = not isVertical and growReverse
    local growLeft = isVertical and growReverse
    if not isVertical and numRowsUsed > 0 then
        local pos = growUp and (-baseTotalHeight / 2) or (baseTotalHeight / 2)
        local actualTop = growUp and (baseTotalHeight / 2) or pos
        local actualBot = growUp and pos or (-baseTotalHeight / 2)
        local tmpIdx = 1
        for _, rc in ipairs(rows) do
            local n = math.min(rc._actualCount or rc.count, #iconsToLayout - tmpIdx + 1)
            if n > 0 then
            local ih = rc.size / (rc.aspectRatioCrop or 1.0)
            local yOff = rc.yOffset or 0
            if growUp then
                actualBot = math.min(actualBot, pos + yOff)
                actualTop = math.max(actualTop, pos + ih + yOff)
                pos = pos + ih + rowGap
            else
                actualTop = math.max(actualTop, pos + yOff)
                actualBot = math.min(actualBot, pos - ih + yOff)
                pos = pos - ih - rowGap
            end
            tmpIdx = tmpIdx + n
            end -- if n > 0
        end
        proxyTotalHeight = actualTop - actualBot
        vs.cdmProxyYOffset = (actualTop + actualBot) / 2
    end

    -- Save raw content width before min-width inflation (used by resource bars)
    local rawContentWidth = maxRowWidth

    -- HUD min-width floor
    local minWidthEnabled, minWidth = GetHUDMinWidth()
    local applyHUDMinWidth = minWidthEnabled and IsHUDAnchoredToCDM()
    if applyHUDMinWidth then
        maxRowWidth = math.max(maxRowWidth, minWidth)
        potentialRow1Width = math.max(potentialRow1Width, minWidth)
        potentialBottomRowWidth = math.max(potentialBottomRowWidth, minWidth)
    end

    -- Position icons using CENTER-based anchoring
    local currentY = growUp and (-baseTotalHeight / 2) or (baseTotalHeight / 2)
    local currentX = growLeft and (totalWidth / 2) or (-totalWidth / 2)

    for rowNum, rowConfig in ipairs(rows) do
        local rowIcons = {}
        local iconsInRow = 0

        for _ = 1, (rowConfig._actualCount or rowConfig.count) do
            if iconIndex <= #iconsToLayout then
                rowIcons[#rowIcons + 1] = iconsToLayout[iconIndex]
                iconIndex = iconIndex + 1
                iconsInRow = iconsInRow + 1
            end
        end

        if iconsInRow > 0 then

        local aspectRatio = rowConfig.aspectRatioCrop or 1.0
        local iconWidth = rowConfig.size
        local iconHeight = rowConfig.size / aspectRatio
        local rowWidth = rowWidths[rowNum] or (iconsInRow * iconWidth) + ((iconsInRow - 1) * rowConfig.padding)
        local colHeight = colHeights[rowNum] or (iconsInRow * iconHeight) + ((iconsInRow - 1) * rowConfig.padding)

        for i, icon in ipairs(rowIcons) do
            local x, y

            if isVertical then
                local colCenterX = growLeft and (currentX - iconWidth / 2) or (currentX + iconWidth / 2)
                local colStartY = baseTotalHeight / 2 - iconHeight / 2
                y = colStartY - ((i - 1) * (iconHeight + rowConfig.padding)) + rowConfig.yOffset
                x = colCenterX + (rowConfig.xOffset or 0)
            else
                local rowCenterY
                if growUp then
                    rowCenterY = currentY + (iconHeight / 2) + rowConfig.yOffset
                else
                    rowCenterY = currentY - (iconHeight / 2) + rowConfig.yOffset
                end
                local rowStartX = -rowWidth / 2 + iconWidth / 2
                x = rowStartX + ((i - 1) * (iconWidth + rowConfig.padding)) + (rowConfig.xOffset or 0)
                y = rowCenterY
            end

            -- Configure icon appearance (size, border, zoom, text)
            ns.CDMIcons.ConfigureIcon(icon, rowConfig)

            -- Reset scale (if somehow changed)
            if icon.GetScale and icon:GetScale() ~= 1 then
                icon:SetScale(1)
            end

            -- Pixel-snap position
            if QUICore and QUICore.PixelRound then
                x = QUICore:PixelRound(x, container)
                y = QUICore:PixelRound(y, container)
            end
            icon:ClearAllPoints()
            icon:SetPoint("CENTER", container, "CENTER", x, y)
            icon:Show()

            -- Update cooldown state
            ns.CDMIcons.UpdateIconCooldown(icon)
        end

        if isVertical then
            if growLeft then
                currentX = currentX - iconWidth - rowGap
            else
                currentX = currentX + iconWidth + rowGap
            end
        else
            if growUp then
                currentY = currentY + iconHeight + rowGap
            else
                currentY = currentY - iconHeight - rowGap
            end
        end
        end -- if iconsInRow > 0
    end

    -- Store dimensions in viewer state
    vs.cdmIconWidth = maxRowWidth
    vs.cdmRawContentWidth = rawContentWidth
    vs.cdmTotalHeight = proxyTotalHeight

    -- Persist for next reload
    local ncdm = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.ncdm
    if ncdm and maxRowWidth > 0 then
        if trackerKey == "essential" then
            ncdm._lastEssentialWidth = maxRowWidth
            ncdm._lastEssentialHeight = proxyTotalHeight
        elseif trackerKey == "utility" then
            ncdm._lastUtilityWidth = maxRowWidth
            ncdm._lastUtilityHeight = proxyTotalHeight
        end
    end

    -- Row-specific dimensions
    -- When growing UP, row 1 is visually at the bottom and the last row is at the top.
    -- Consumers expect cdmRow1* = visual top, cdmBottomRow* = visual bottom.
    local visualTopRow = growUp and rows[#rows] or rows[1]
    local visualBottomRow = growUp and rows[1] or rows[#rows]
    vs.cdmRow1IconHeight = visualTopRow and (visualTopRow.size / (visualTopRow.aspectRatioCrop or 1.0)) or 0
    vs.cdmRow1BorderSize = visualTopRow and visualTopRow.borderSize or 0
    vs.cdmBottomRowBorderSize = visualBottomRow and visualBottomRow.borderSize or 0
    vs.cdmBottomRowYOffset = visualBottomRow and visualBottomRow.yOffset or 0

    if isVertical then
        vs.cdmRow1Width = maxRowWidth
        vs.cdmBottomRowWidth = maxRowWidth
        vs.cdmRawRow1Width = rawContentWidth
        vs.cdmRawBottomRowWidth = rawContentWidth
        vs.cdmPotentialRow1Width = maxRowWidth
        vs.cdmPotentialBottomRowWidth = maxRowWidth
    else
        local visualTopRowWidth = growUp and (rowWidths[#rows] or rawContentWidth) or (rowWidths[1] or rawContentWidth)
        local visualBottomRowWidth = growUp and (rowWidths[1] or rawContentWidth) or (rowWidths[#rows] or rawContentWidth)
        local rawRow1Width = visualTopRowWidth
        local rawBottomRowWidth = visualBottomRowWidth
        local row1Width = rawRow1Width
        local bottomRowWidth = rawBottomRowWidth
        if applyHUDMinWidth then
            row1Width = math.max(row1Width, minWidth)
            bottomRowWidth = math.max(bottomRowWidth, minWidth)
        end
        vs.cdmRow1Width = row1Width
        vs.cdmBottomRowWidth = bottomRowWidth
        vs.cdmRawRow1Width = rawRow1Width
        vs.cdmRawBottomRowWidth = rawBottomRowWidth
        vs.cdmPotentialRow1Width = growUp and potentialBottomRowWidth or potentialRow1Width
        vs.cdmPotentialBottomRowWidth = growUp and potentialRow1Width or potentialBottomRowWidth
    end

    -- Size the container to match content bounds
    if maxRowWidth > 0 and proxyTotalHeight > 0 then
        container:SetSize(maxRowWidth, proxyTotalHeight)
    end

    applying[trackerKey] = false

    -- Trigger Utility anchor after Essential layout
    if trackerKey == "essential" then
        local db = GetDB()
        if db and db.utility and db.utility.anchorBelowEssential then
            C_Timer.After(0.05, function()
                -- Skip during combat — PLAYER_REGEN_ENABLED RefreshAll handles recovery
                if InCombatLockdown() then return end
                if ApplyUtilityAnchor then
                    ApplyUtilityAnchor()
                end
            end)
        end
    end

    -- Update dependent systems (debounced)
    if not vs.cdmUpdatePending then
        vs.cdmUpdatePending = true
        C_Timer.After(0.05, function()
            vs.cdmUpdatePending = nil
            -- Skip during combat — PLAYER_REGEN_ENABLED RefreshAll handles recovery
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

---------------------------------------------------------------------------
-- REFRESH ALL
---------------------------------------------------------------------------
RefreshAll = function(forceSync)
    if not initialized then
        return
    end

    if not specTrackingReady then
        specTrackingPendingRefresh = true
        return
    end

    -- Defer to combat end — rebuilding destroys the current layout.
    -- A follow-up refresh on PLAYER_REGEN_ENABLED routes here and provides
    -- recovery after combat lockdown ends.
    -- Exception: during the ADDON_LOADED / PEW safe window, protected calls
    -- are allowed even though InCombatLockdown() reports true on /reload.
    if InCombatLockdown() and not inInitSafeWindow then
        specTrackingPendingRefresh = true
        return
    end

    -- Cancel any pending refresh timers from a prior overlapping RefreshAll call.
    -- This prevents interleaved layouts when e.g. a 0.2s profile-change refresh
    -- races against a 0.5s spec-change refresh.
    for i, handle in pairs(refreshTimers) do
        if handle and handle.Cancel then
            handle:Cancel()
        end
        refreshTimers[i] = nil
    end

    -- Force-scan spell data synchronously BEFORE scheduling layouts.
    -- This ensures layouts read fresh spec data instead of stale lists.
    if ns.CDMSpellData then
        ns.CDMSpellData:UpdateCVar()
        ns.CDMSpellData:ForceScan()
    end

    applying["essential"] = false
    applying["utility"] = false
    applying["buff"] = false

    -- Restore container positions from the (possibly new) profile DB.
    -- LayoutContainer only sizes containers and positions icons within them —
    -- it never calls SetPoint on the container itself. Without this, containers
    -- keep the previous profile's screen position after a profile/spec switch.
    local allKeys = CDMContainers_API:GetAllContainerKeys()
    for _, trackerKey in ipairs(allKeys) do
        local container = containers[trackerKey]
        if container then
            RestoreContainerPosition(container, trackerKey)
        end
    end

    SyncSettingsFeatureLookups()

    -- Buff fingerprint is NOT reset here. ForceScan() above already refreshed
    -- the spell lists — if the buff set actually changed, the fingerprint
    -- comparison in LayoutContainer("buff") will detect the difference and
    -- rebuild. Unconditional reset causes a visible flash (ClearPool +
    -- BuildIcons destroys and recreates all icons even when nothing changed).

    -- Collect custom container keys for layout
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
        -- Synchronous layout: runs inline to leverage the ADDON_LOADED safe
        -- window on combat /reload while InCombatLockdown() still reports true.
        -- No timer stagger needed — nothing to interleave on initial boot.
        LayoutContainer("essential")
        LayoutContainer("utility")
        if ApplyUtilityAnchor then
            ApplyUtilityAnchor()
        end
        LayoutContainer("buff")
        -- Layout custom containers
        for _, key in ipairs(customKeys) do
            LayoutContainer(key)
        end
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
        if _G.QUI_RefreshCustomGlows then
            _G.QUI_RefreshCustomGlows()
        end
        if ns.CDMIcons and ns.CDMIcons.SyncRangePoll then
            ns.CDMIcons:SyncRangePoll()
        end
        -- Reapply icon visibility after layout so "active only" display
        -- mode hides inactive icons that LayoutContainer() showed.
        if ns.CDMIcons and ns.CDMIcons.UpdateAllCooldowns then
            ns.CDMIcons:UpdateAllCooldowns()
        end
        SyncAllContainerMouseStates(true)
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

        -- Layout custom containers (staggered after built-in)
        local customTimerStart = 4
        for ci, key in ipairs(customKeys) do
            local timerIdx = customTimerStart + ci
            refreshTimers[timerIdx] = C_Timer.NewTimer(0.03 + ci * 0.01, function()
                refreshTimers[timerIdx] = nil
                LayoutContainer(key)
            end)
        end

        -- Update locked bars and refresh swipe/glow after all layouts complete
        local finalTimerDelay = 0.10 + #customKeys * 0.01
        refreshTimers[100] = C_Timer.NewTimer(finalTimerDelay, function()
            refreshTimers[100] = nil
            if InCombatLockdown() and not inInitSafeWindow then
                specTrackingPendingRefresh = true
                return
            end
            UpdateAllLockedBars()
            if _G.QUI_UpdateCDMAnchoredUnitFrames then
                _G.QUI_UpdateCDMAnchoredUnitFrames()
            end
            if _G.QUI_RefreshCDMMouseover then
                _G.QUI_RefreshCDMMouseover()
            end
            -- Apply swipe settings and glow state to newly created/rebuilt icons
            if _G.QUI_RefreshCooldownSwipe then
                _G.QUI_RefreshCooldownSwipe()
            end
            if _G.QUI_RefreshCustomGlows then
                _G.QUI_RefreshCustomGlows()
            end
            -- Sync range poll OnUpdate based on current settings
            if ns.CDMIcons and ns.CDMIcons.SyncRangePoll then
                ns.CDMIcons:SyncRangePoll()
            end
            -- Reapply icon visibility after layout so "active only" display
            -- mode hides inactive icons that LayoutContainer() showed.
            if ns.CDMIcons and ns.CDMIcons.UpdateAllCooldowns then
                ns.CDMIcons:UpdateAllCooldowns()
            end
            SyncAllContainerMouseStates(true)
        end)
    end
end

---------------------------------------------------------------------------
-- UTILITY ANCHOR: Position Utility container below Essential
---------------------------------------------------------------------------
ApplyUtilityAnchor = function()
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

    -- Respect centralized frame anchoring overrides
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

    local utilityTopBorder = utilSettings.row1 and utilSettings.row1.borderSize or 0
    local totalOffset = (utilSettings.anchorGap or 0) - utilityTopBorder

    local anchorParent = UpdateUtilityAnchorProxy() or essContainer

    local ok = pcall(function()
        utilContainer:ClearAllPoints()
        utilContainer:SetPoint("TOP", anchorParent, "BOTTOM", 0, -totalOffset)
    end)

    if not ok then
        -- Fallback: center on screen
        utilContainer:ClearAllPoints()
        utilContainer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        utilSettings.anchorBelowEssential = false
        print("|cff60A5FAQUI:|r Anchor Utility below Essential failed (circular dependency). Setting has been disabled.")
    end
end

---------------------------------------------------------------------------
-- VIEWER STATE API (backward compatible with old cdm_viewer.lua API)
---------------------------------------------------------------------------
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

-- Callback for spell data changes (essential/utility)
_G.QUI_OnSpellDataChanged = function()
    if initialized then
        RefreshAll()
    end
end

-- Force layout for a specific container during edit mode (used by Composer)
_G.QUI_ForceLayoutContainer = function(containerKey)
    if not containerKey or not initialized then return end
    _forceLayoutKey = containerKey
    LayoutContainer(containerKey)
    _forceLayoutKey = nil
    -- Ensure container stays visible during edit mode even if layout found 0 icons
    local container = containers[containerKey]
    if container and _editModeActive then
        container:Show()
        -- Re-sync the layout mode mover handle to match the updated container size/position
        local elementKey = BUILTIN_NAMES[containerKey] and containerKey or ("cdmCustom_" .. containerKey)
        if _G.QUI_LayoutModeSyncHandle then
            _G.QUI_LayoutModeSyncHandle(elementKey)
        end
    end
end

-- Callback for buff aura events (from hooks on Blizzard buff children).
-- Runs LayoutContainer to rebuild buff icons, then notifies buffbar.
_G.QUI_OnBuffDataChanged = function()
    if initialized and not applying["buff"] then
        LayoutContainer("buff")
    end
end

-- Callback for buffbar.lua to style and position buff icons.
-- Fired by LayoutContainer("buff") after icon build completes.
_G.QUI_OnBuffLayoutReady = _G.QUI_OnBuffLayoutReady or function() end

---------------------------------------------------------------------------
-- EDIT MODE INTEGRATION
-- During Edit Mode, QUI containers stay visible with overlays.
-- Blizzard viewers remain alpha 0 always — zero Blizzard frame writes.
-- Clicking an overlay opens Blizzard CDM settings.  Nudge buttons
-- handle pixel-precise positioning.  Positions save to DB on exit.
---------------------------------------------------------------------------

-- _editModeActive and _disabledMouseFrames are forward-declared above
-- LayoutContainer (they are referenced inside it).
_G.QUI_IsCDMEditModeHidden = function() return false end  -- backward compat
_G.QUI_IsCDMEditModeActive = function() return _editModeActive end


-- Hide Blizzard .Selection frames during Edit Mode so only QUI overlays
-- are visible.  SetAlpha(0) is C-side and safe from taint.
-- .Selection uses IgnoreParentAlpha so it doesn't inherit viewer alpha 0.
local _selectionAlphaHooked = {}  -- [viewerName] = true

-- All CDM viewers whose .Selection should be hidden during Edit Mode.
-- BuffBarCooldownViewer is Blizzard-managed (alpha/visibility untouched)
-- but its .Selection is hidden so QUI's overlay is the only indicator.
local ALL_CDM_VIEWER_NAMES = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}

local function HideBlizzardSelections()
    for _, blizzName in ipairs(ALL_CDM_VIEWER_NAMES) do
        local viewer = _G[blizzName]
        if viewer and viewer.Selection then
            viewer.Selection:SetAlpha(0)
            -- Hook SetAlpha and Show so Blizzard's Edit Mode can't restore it
            if not _selectionAlphaHooked[blizzName] then
                _selectionAlphaHooked[blizzName] = true
                hooksecurefunc(viewer.Selection, "Show", function(self)
                    if _editModeActive then
                        C_Timer.After(0, function()
                            if _editModeActive then
                                self:SetAlpha(0)
                            end
                        end)
                    end
                end)
                hooksecurefunc(viewer.Selection, "SetAlpha", function(self, alpha)
                    if _editModeActive and alpha > 0 then
                        C_Timer.After(0, function()
                            if _editModeActive then
                                self:SetAlpha(0)
                            end
                        end)
                    end
                end)
            end
        end
    end
end

-- Disable mouse on a container and all its icon pool children so clicks
-- reach the QUI overlay.
-- EnableMouse(false) removes the frame from hit testing entirely — the
-- WoW C-side input system skips it.
local function DisableMouseForEditMode(viewerType)
    local container = containers[viewerType]
    if not container then return end

    container:EnableMouse(false)
    _disabledMouseFrames[container] = "container"

    -- Disable mouse on all icons/bars in this pool
    local pool = ns.CDMIcons and ns.CDMIcons:GetIconPool(viewerType) or {}
    for _, icon in ipairs(pool) do
        icon:EnableMouse(false)
        _disabledMouseFrames[icon] = "icon"
        -- Hide click-to-cast buttons so they don't intercept edit mode clicks
        if icon.clickButton and not InCombatLockdown() then
            icon.clickButton:EnableMouse(false)
            icon.clickButton:Hide()
        end
    end
    -- Also disable mouse on owned bar frames (trackedBar)
    if viewerType == "trackedBar" and ns.CDMBars then
        local bars = ns.CDMBars:GetActiveBars()
        for _, bar in ipairs(bars) do
            bar:EnableMouse(false)
            _disabledMouseFrames[bar] = "bar"
        end
    end
end

-- Restore mouse on all frames we disabled
local function RestoreMouseAfterEditMode()
    for frame, mouseRole in pairs(_disabledMouseFrames) do
        if mouseRole == "icon" then
            SetIconMouseDefault(frame)
        else
            SetFrameMouseDisabled(frame)
        end
    end
    wipe(_disabledMouseFrames)

    -- Re-enable click-to-cast buttons for essential/utility icons
    if not InCombatLockdown() and ns.CDMIcons then
        for _, viewerType in ipairs({"essential", "utility"}) do
            local pool = ns.CDMIcons:GetIconPool(viewerType) or {}
            for _, icon in ipairs(pool) do
                if icon.clickButton then
                    icon.clickButton:EnableMouse(true)
                end
                -- Refresh secure attributes (may have been pending)
                ns.CDMIcons.UpdateIconSecureAttributes(icon, icon._spellEntry, viewerType)
            end
        end
    end

    SyncAllContainerMouseStates(true)
end

-- Force all buff icons to full alpha (called on edit mode enter).
-- The 0.5s ticker also sets alpha 1 during edit mode, but this
-- provides immediate visibility without waiting for the next tick.
local function ForceBuffIconsVisible()
    local pool = ns.CDMIcons and ns.CDMIcons:GetIconPool("buff") or {}
    for _, icon in ipairs(pool) do
        icon:SetAlpha(1)
        icon:Show()
    end
end

_G.QUI_OnEditModeEnterCDM = function()
    -- Force a buff scan + rebuild BEFORE setting _editModeActive,
    -- because LayoutContainer bails out when _editModeActive is true.
    -- This ensures buff icons exist for the user to see during edit mode.
    if ns.CDMSpellData and ns.CDMSpellData.ForceScan then
        ns.CDMSpellData:ForceScan()
    end
    LayoutContainer("buff")

    -- Force trackedBar container visible and populated before Edit Mode
    -- so the overlay/mover is visible and draggable (not 1x1).
    -- CDMBars:Refresh() is called directly because LayoutBuffBars() bails
    -- when Blizzard's Edit Mode is active (IsEditModeActive() is already true
    -- at this point — Blizzard fires the callback before we get here).
    if containers.trackedBar then
        containers.trackedBar:Show()
        containers.trackedBar:SetAlpha(1)

        if ns.CDMBars then
            local db = GetDB()
            local tbSettings = db and db.trackedBar
            if tbSettings then
                ns.CDMBars:Refresh(containers.trackedBar, tbSettings, tbSettings.barWidth)
                -- Force all tracked bars visible for Edit Mode so the mover
                -- shows the full expected area (not just active buffs).
                ns.CDMBars:ForceAllActive()
                ns.CDMBars:LayoutBars(containers.trackedBar, tbSettings)
            end
        end

        -- Final fallback: if Refresh didn't size it (no CDMBars or no settings)
        local cw = Helpers.SafeValue(containers.trackedBar:GetWidth(), 0)
        local ch = Helpers.SafeValue(containers.trackedBar:GetHeight(), 0)
        if cw <= 1 or ch <= 1 then
            local db2 = GetDB()
            local tbs2 = db2 and db2.trackedBar
            local barWidth = (tbs2 and tbs2.barWidth) or 215
            local barHeight = (tbs2 and tbs2.barHeight) or 25
            containers.trackedBar:SetSize(barWidth, barHeight)
        end
    end

    _editModeActive = true

    -- Hide Blizzard .Selection frames so only QUI overlays show.
    -- .Selection uses IgnoreParentAlpha — viewer alpha 0 doesn't hide it.
    HideBlizzardSelections()

    -- Force buff icons visible immediately (don't wait for ticker).
    ForceBuffIconsVisible()

    -- Re-run buff layout so the owned container (and its layout mode
    -- mover) sizes to match every now-visible icon, mirroring the
    -- trackedBar path above. Without this, the mover reflects only the
    -- pre-ForceBuffIconsVisible count and clips icons during layout mode.
    if _G.QUI_OnBuffLayoutReady then
        _G.QUI_OnBuffLayoutReady()
    end

    -- Disable mouse on QUI icon frames so overlay catches clicks.
    DisableMouseForEditMode("essential")
    DisableMouseForEditMode("utility")
    DisableMouseForEditMode("buff")
    DisableMouseForEditMode("trackedBar")
    -- Also disable for custom containers
    for key in pairs(containers) do
        if not BUILTIN_NAMES[key] then
            DisableMouseForEditMode(key)
        end
    end

    -- Show overlays on QUI containers (containers stay visible).
    local QUICore = ns.Addon
    if QUICore and QUICore.ShowViewerOverlays then
        QUICore:ShowViewerOverlays()
    end

    if _G.QUI_ApplyAllFrameAnchors then _G.QUI_ApplyAllFrameAnchors() end
end

_G.QUI_OnEditModeExitCDM = function()
    _editModeActive = false

    -- Persist container positions to DB.
    SaveContainerPosition("essential")
    SaveContainerPosition("utility")
    SaveContainerPosition("buff")
    SaveContainerPosition("trackedBar")
    -- Also save custom container positions
    for key in pairs(containers) do
        if not BUILTIN_NAMES[key] then
            SaveContainerPosition(key)
        end
    end

    -- Restore mouse on icon frames.
    RestoreMouseAfterEditMode()

    -- Refresh layout (reapply positions, rebuild icons).
    RefreshAll()

    -- RefreshAll uses staggered timers (0.01–0.10s) to rebuild layouts.
    -- After the last timer completes, force a full refresh of anchors
    -- and locked resource bars so dependent frames pick up the correct
    -- QUI container dimensions.
    C_Timer.After(0.5, function()
        if _G.QUI_ApplyAllFrameAnchors then
            _G.QUI_ApplyAllFrameAnchors()
        end
        UpdateAllLockedBars()
        if _G.QUI_UpdateCDMAnchoredUnitFrames then
            _G.QUI_UpdateCDMAnchoredUnitFrames()
        end
        -- Force icon visibility update so "active only" display mode hides
        -- inactive icons that LayoutContainer() unconditionally showed.
        if ns.CDMIcons and ns.CDMIcons.UpdateAllCooldowns then
            ns.CDMIcons:UpdateAllCooldowns()
        end
    end)
end

---------------------------------------------------------------------------
-- NCDM COMPATIBILITY TABLE
-- Provides a Refresh() and LayoutViewer() interface for backward-compatible
-- consumer access.
---------------------------------------------------------------------------
local NCDM = {
    initialized = false,
}

NCDM.Refresh = RefreshAll
NCDM.LayoutViewer = function(name, key)
    LayoutContainer(key or name)
end

---------------------------------------------------------------------------
-- ENGINE TABLE (provider contract)
---------------------------------------------------------------------------
local ownedEngine = {}

-- Viewer key → container key mapping
local VIEWER_KEY_MAP = {
    essential = "essential",
    utility   = "utility",
    buffIcon  = "buff",
    buffBar   = "trackedBar",
}

-- Blizzard frame fallback for pre-container resolution and unmanaged viewers
local BLIZZARD_FALLBACKS = {
    essential = "EssentialCooldownViewer",
    utility   = "UtilityCooldownViewer",
    buffIcon  = "BuffIconCooldownViewer",
    buffBar   = "BuffBarCooldownViewer",
}

---------------------------------------------------------------------------
-- Initialize: called by cdm_provider.lua after engine selection
---------------------------------------------------------------------------
function ownedEngine:Initialize()
    -- During a combat /reload this runs inside the ADDON_LOADED safe window
    -- where protected calls are allowed even though InCombatLockdown() returns
    -- true. Set the flag before spell-data bootstrap so Blizzard CDM loading
    -- and the initial scans are not skipped.
    inInitSafeWindow = true
    local previousInitSafeWindow = ns._inInitSafeWindow
    ns._inInitSafeWindow = true

    -- Wire owned-engine exports that are populated after their modules load.
    if ns._OwnedGlows then
        QUI.CustomGlows = ns._OwnedGlows
        _G.QUI_RefreshCustomGlows = ns._OwnedGlows.RefreshAllGlows
        -- No-op effects refresh (owned engine has no effects.lua)
        _G.QUI_RefreshCooldownEffects = function() end
    end
    if ns._OwnedSwipe then
        QUI.CooldownSwipe = ns._OwnedSwipe
        _G.QUI_RefreshCooldownSwipe = ns._OwnedSwipe.Apply
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

    -- Bootstrap spell data harvesting
    if ns.CDMSpellData then
        ns.CDMSpellData:Initialize()
    end

    -- Phase A CDM Overhaul: Snapshot Blizzard CDM spell lists into owned DB.
    -- This runs after spell data init so the scan lists are populated.
    -- Only snapshots containers that haven't been snapshotted yet (ownedSpells == nil).
    -- Deferred to allow Blizzard viewers to fully populate.
    C_Timer.After(2.0, function()
        if InCombatLockdown() then return end
        if ns.CDMSpellData then
            local containerKeys = BUILTIN_KEYS  -- only built-in containers get Blizzard snapshots
            local snapshotted = false
            for _, key in ipairs(containerKeys) do
                if ns.CDMSpellData:SnapshotBlizzardCDM(key) then
                    snapshotted = true
                end
            end
            if snapshotted then
                RefreshAll()
            end
        end
    end)

    -- Ensure built-in containers with DB tables have enabled=true
    -- (the table may exist from Composer/snapshot without explicit enabled).
    local ncdmDB = GetDB()
    if ncdmDB then
        for _, key in ipairs({"buff", "trackedBar"}) do
            if ncdmDB[key] and ncdmDB[key].enabled == nil then
                ncdmDB[key].enabled = true
            end
        end
    end

    -- Create containers immediately (addon-owned frames, no external dependency).
    InitContainers()
    InitBuffContainer()

    -- Start the CDMIcons update ticker
    if ns.CDMIcons then
        ns.CDMIcons:StartUpdateTicker()
    end

    initialized = true
    NCDM.initialized = true

    -- Initialize spec tracking for save-on-switch. If the current spec is not
    -- available yet, delay the first meaningful layout until the profile swap
    -- / fresh snapshot has finished to avoid rendering another character's CDs.
    local specReadyNow = InitSpecTracking()
    RegisterProfileCallbacks()

    -- Invalidate visibility frame cache so hud_visibility picks up new containers
    if ns.InvalidateCDMFrameCache then
        ns.InvalidateCDMFrameCache()
    end

    -- Synchronous initial layout: leverages the ADDON_LOADED safe window on
    -- combat /reload (InCombatLockdown() still returns true). If Blizzard viewers
    -- aren't populated yet (first login), layout produces empty containers —
    -- the deferred re-layout below fills them once spell data arrives.
    if specReadyNow then
        RefreshAll(true)
    else
        specTrackingPendingRefresh = true
    end

    -- Synchronous post-layout: apply frame anchoring overrides NOW while
    -- still in the ADDON_LOADED safe window.
    -- Containers anchored to other frames (e.g. utility→essential) need
    -- the anchoring system to set their position. This MUST be synchronous
    -- because deferred timers fire after the safe window closes.
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

    -- Apply HUD visibility now that containers exist (covers /reload while mounted).
    -- Containers start at alpha=0 (CreateContainer). Set the correct target
    -- alpha instantly so StartCDMFade sees "already at target" and skips
    -- the animation — prevents a flash of fully-visible icons popping in.
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

    -- Close the safe window — subsequent C_Timer callbacks run outside the
    -- ADDON_LOADED handler and must respect combat lockdown normally.
    inInitSafeWindow = false
    ns._inInitSafeWindow = previousInitSafeWindow

    -- Deferred re-layout: catches first-login cases where Blizzard viewers
    -- populate after us, or where the immediate scan found empty data.
    C_Timer.After(1.0, function()
        if not InCombatLockdown() then
            RefreshAll()
        end
    end)

    -- Defensive: refresh all after Blizzard's layout system has fully settled.
    C_Timer.After(3.0, function()
        if initialized and not InCombatLockdown() then
            RefreshAll()
        end
    end)

    -- Register runtime events (spec change, zone change, cinematics, addon loads)
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("CHALLENGE_MODE_START")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:RegisterEvent("CINEMATIC_STOP")
    eventFrame:RegisterEvent("STOP_MOVIE")
    eventFrame:RegisterEvent("ADDON_LOADED")

    eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2)
        if event == "ADDON_LOADED" and arg1 == "Blizzard_CooldownManager" then
            -- Viewer just loaded -- grab it as buff container
            InitBuffContainer()
            if initialized then
                if ns.InvalidateCDMFrameCache then ns.InvalidateCDMFrameCache() end
                RefreshAll()
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            local isLogin, isReload = arg1, arg2
            if isReload then
                -- Second layout pass during combat /reload safe window.
                -- Catches Blizzard viewer children that populated after
                -- the initial ADDON_LOADED scan. PEW fires inside the
                -- safe window: protected calls are allowed even though
                -- InCombatLockdown() returns true on combat /reload.
                local previousInitSafeWindow = ns._inInitSafeWindow
                inInitSafeWindow = true
                ns._inInitSafeWindow = true
                if ns.CDMSpellData then
                    ns.CDMSpellData:ForceScan()
                end
                RefreshAll(true)
                if _G.QUI_ApplyAllFrameAnchors then
                    _G.QUI_ApplyAllFrameAnchors()
                end
                inInitSafeWindow = false
                ns._inInitSafeWindow = previousInitSafeWindow
            elseif isLogin then
                -- Fresh login (or character switch): run dormant spell cleanup
                -- so cross-class/spec spells are removed before the first
                -- meaningful RefreshAll fires from the deferred timer.
                C_Timer.After(0.5, function()
                    if not specTrackingReady then
                        specTrackingPendingRefresh = true
                        return
                    end
                    if not InCombatLockdown() and ns.CDMSpellData then
                        ns.CDMSpellData:CheckAllDormantSpells()
                        ns.CDMSpellData:ReconcileAllContainers()
                        RefreshAll()
                    end
                end)
            elseif not isReload then
                C_Timer.After(0.3, RefreshAll)
            end
        elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
            local newSpecID = GetCurrentSpecID()
            -- Guard: Blizzard can fire this event multiple times for a single
            -- spec change. Skip the duplicate if we already processed it.
            if not newSpecID or newSpecID ~= _previousSpecID then
                -- Save outgoing spec profile before loading the new one
                if _previousSpecID and _previousSpecID ~= 0 then
                    SaveCurrentSpecProfile()
                end
                -- Invalidate caches immediately — old spec data is stale
                if ns.InvalidateCDMFrameCache then ns.InvalidateCDMFrameCache() end
                if ns.CDMSpellData and ns.CDMSpellData.InvalidateLearnedCache then
                    ns.CDMSpellData:InvalidateLearnedCache()
                end
                -- Load the new spec profile synchronously so the DB is never in a
                -- stale state. This eliminates the race where SPELLS_CHANGED fires
                -- before the profile swap and corrupts spell lists.
                specTrackingReady = false
                specTrackingPendingRefresh = true
                specTrackingRetryToken = specTrackingRetryToken + 1
                local readyNow = LoadOrSnapshotSpecProfile(newSpecID, 1, specTrackingRetryToken)
                _previousSpecID = newSpecID
                -- Persist for cross-session detection
                local specDB = GetDB()
                if specDB then specDB._lastSpecID = newSpecID end
                -- Profile is now correct — SPELLS_CHANGED can safely run
                -- dormant/reconcile on the new spec's data.
                buffFingerprint = nil
                if readyNow then
                    specTrackingReady = true
                    specTrackingPendingRefresh = false
                    RefreshAll()
                end
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            if ns.CDMSpellData then
                ns.CDMSpellData:ForceScan()
                for _, key in ipairs(BUILTIN_KEYS) do
                    ns.CDMSpellData:SnapshotBlizzardCDM(key)
                end
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
            else
                if ns.CDMSpellData then
                    ns.CDMSpellData:CheckAllDormantSpells()
                    ns.CDMSpellData:ReconcileAllContainers()
                end
                RefreshAll()
            end
        elseif event == "CHALLENGE_MODE_START" then
            -- Restore dormant spells before refreshing — SPELLS_CHANGED
            -- may have incorrectly shelved spells during the zone
            -- transition when WoW APIs were temporarily stale.
            -- restoreOnly=true: only rescue spells from dormant, don't
            -- risk marking more spells dormant with still-settling APIs.
            -- If already in combat, PLAYER_REGEN_ENABLED handles recovery.
            C_Timer.After(0.5, function()
                if not InCombatLockdown() then
                    if ns.CDMSpellData then
                        ns.CDMSpellData:CheckAllDormantSpells(true)
                        ns.CDMSpellData:ReconcileAllContainers()
                    end
                    RefreshAll()
                end
            end)
        elseif event == "ZONE_CHANGED_NEW_AREA" then
            C_Timer.After(0.3, RefreshAll)
        elseif event == "CINEMATIC_STOP" or event == "STOP_MOVIE" then
            -- After cinematics, refresh everything and invalidate frame cache
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

    ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
    ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "CDM_Containers", frame = eventFrame }
end

function ownedEngine:Refresh()
    RefreshAll()
end

function ownedEngine:GetViewerFrame(key)
    -- Always return QUI containers (visible in/out of Edit Mode).
    local containerKey = VIEWER_KEY_MAP[key]
    if containerKey then
        local container = containers[containerKey]
        if container then return container end
    end
    -- Phase G: Direct container lookup for custom container keys
    if containers[key] then
        return containers[key]
    end
    -- Fall back to Blizzard frame (before containers exist or for unmanaged viewers)
    local blizzName = BLIZZARD_FALLBACKS[key]
    return blizzName and _G[blizzName] or nil
end

function ownedEngine:GetViewerFrames()
    local frames = {}
    if containers.essential then frames[#frames + 1] = containers.essential end
    if containers.utility then frames[#frames + 1] = containers.utility end
    if containers.buff then frames[#frames + 1] = containers.buff end
    if containers.trackedBar then frames[#frames + 1] = containers.trackedBar end
    -- Include custom containers
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
    -- Owned icons are addon-created; state is on the icon itself (no external table)
    if not icon then return nil end
    return icon._spellEntry and icon or nil
end

function ownedEngine:ClearIconState(icon)
    -- No external state table for owned icons; release handled by CDMIcons
    if not icon then return end
    if ns.CDMIcons then
        ns.CDMIcons:ReleaseIcon(icon)
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
    -- Owned frames don't use Blizzard's .Selection overlay
    return false
end

function ownedEngine:GetNCDM()
    return NCDM
end

function ownedEngine:GetCustomCDM()
    -- CustomCDM is defined in cdm_icons.lua; access via CDMIcons module
    return ns.CDMIcons and ns.CDMIcons.CustomCDM or nil
end

function ownedEngine:LayoutViewer(name, key)
    LayoutContainer(key or name)
end

---------------------------------------------------------------------------
-- HAND ENGINE TO PROVIDER
---------------------------------------------------------------------------
-- Phase B.3: the provider dropped its multi-engine abstraction since
-- there has only ever been one implementation. SetEngine replaces the
-- previous RegisterEngine("owned", ...) pattern.
if ns.CDMProvider then
    ns.CDMProvider:SetEngine(ownedEngine)
end

---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- NAMESPACE EXPORT
---------------------------------------------------------------------------
-- Phase B.3 diagnostic: expose to _G so /run can poke the panel for
-- provider/mover checks without needing the private ns.
_G.QUI_DebugCDM = _G.QUI_DebugCDM or {}
_G.QUI_DebugCDM.GetLayoutSettings = function() return ns.QUI_LayoutMode_Settings end
_G.QUI_DebugCDM.GetLayoutMode = function() return ns.QUI_LayoutMode end
_G.QUI_DebugCDM.GetContainersAPI = function() return CDMContainers_API end

ns.CDMContainers = {
    GetContainer = function(viewerType) return containers[viewerType] end,
    LayoutContainer = LayoutContainer,
    RefreshAll = RefreshAll,
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
    -- Phase G: Container management API
    CreateContainer = function(name, containerType) return CDMContainers_API:CreateContainer(name, containerType) end,
    DeleteContainer = function(key) return CDMContainers_API:DeleteContainer(key) end,
    RenameContainer = function(key, name) return CDMContainers_API:RenameContainer(key, name) end,
    GetContainers = function() return CDMContainers_API:GetContainers() end,
    GetContainerSettings = function(key) return CDMContainers_API:GetContainerSettings(key) end,
    GetContainersByType = function(containerType) return CDMContainers_API:GetContainersByType(containerType) end,
    GetAllContainerKeys = function() return CDMContainers_API:GetAllContainerKeys() end,
    SyncSettingsFeatureLookups = SyncSettingsFeatureLookups,
    -- Save current spec's ownedSpells to _specProfiles (called after Composer mutations).
    -- Guard: refuse to save while spec tracking is still initialising — the live
    -- containerDB may still hold stale data from a previous character/spec.
    SaveActiveSpecProfile = function()
        if not specTrackingReady then return end
        SaveSpecProfile(GetCurrentSpecID())
    end,
    -- Clear imported ownedSpells and re-snapshot from Blizzard CDM for the
    -- current spec. Called after profile import so foreign-class spells are
    -- replaced with the player's actual abilities.
    ResnapshotForCurrentSpec = function()
        if not ns.CDMSpellData then return end
        local containerKeys = CDMContainers_API:GetAllContainerKeys()
        for _, key in ipairs(containerKeys) do
            local containerDB = GetTrackerSettings(key)
            if containerDB then
                containerDB.ownedSpells = nil
                containerDB.dormantSpells = nil
            end
        end
        ns.CDMSpellData:ForceScan()
        for _, key in ipairs(containerKeys) do
            ns.CDMSpellData:SnapshotBlizzardCDM(key)
        end
    end,
}

---------------------------------------------------------------------------
-- UNLOCK MODE ELEMENT REGISTRATION
---------------------------------------------------------------------------
do
    local _retryCount = 0
    local function RegisterLayoutModeElements()
        local um = ns.QUI_LayoutMode
        if not um then
            if _retryCount < 20 then
                _retryCount = _retryCount + 1
                C_Timer.After(0.5, RegisterLayoutModeElements)
            end
            return
        end

        local CDM_ELEMENTS = {
            { key = "cdmEssential", label = "CDM Essential",  order = 1 },
            { key = "cdmUtility",   label = "CDM Utility",    order = 2 },
            { key = "buffIcon",     label = "Buff Icons",     order = 3 },
            { key = "buffBar",      label = "Buff Bars",      order = 4 },
        }

        local CDM_KEY_MAP = {
            cdmEssential = "essential",
            cdmUtility = "utility",
            buffIcon = "buff",
            buffBar = "trackedBar",
        }
        -- CDM viewer key (different from DB key for buff types)
        local CDM_VIEWER_MAP = {
            cdmEssential = "essential",
            cdmUtility = "utility",
            buffIcon = "buffIcon",
            buffBar = "buffBar",
        }

        local function GetCDMDB(cdmKey)
            local core = ns.Helpers.GetCore()
            local ncdm = core and core.db and core.db.profile and core.db.profile.ncdm
            if not ncdm then return nil end
            local dbKey = CDM_KEY_MAP[cdmKey]
            -- Built-in containers live at ncdm[key] (user's saved data).
            -- Custom containers only exist in ncdm.containers[key].
            if ncdm[dbKey] then
                return ncdm[dbKey]
            end
            if ncdm.containers and ncdm.containers[dbKey] then
                return ncdm.containers[dbKey]
            end
            return nil
        end

        local function GetNcdmDB()
            local core = ns.Helpers.GetCore()
            return core and core.db and core.db.profile and core.db.profile.ncdm
        end

        local function RefreshCDM()
            if _G.QUI_RefreshCDMVisibility then _G.QUI_RefreshCDMVisibility() end
        end

        -- Master CDM toggle — disabling hides all CDM containers
        um:RegisterElement({
            key = "cdm",
            label = "Cooldown Manager",
            group = "Cooldown Manager & Custom Tracker Bars",
            order = -1,
            isOwned = true,
            noHandle = true,
            isEnabled = function()
                local ncdm = GetNcdmDB()
                return ncdm and ncdm.enabled ~= false
            end,
            setEnabled = function(val)
                local ncdm = GetNcdmDB()
                if ncdm then ncdm.enabled = val end
                RefreshCDM()
            end,
            setGameplayHidden = function(hide)
                for _, info2 in ipairs(CDM_ELEMENTS) do
                    local viewerKey = CDM_VIEWER_MAP[info2.key]
                    local f = _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame(viewerKey)
                    if f then
                        if hide then f:Hide() else f:Show() end
                    end
                end
            end,
            getFrame = function()
                for _, info2 in ipairs(CDM_ELEMENTS) do
                    local viewerKey = CDM_VIEWER_MAP[info2.key]
                    local f = _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame(viewerKey)
                    if f then return f end
                end
            end,
        })

        -- Fallback sizes for when a CDM container is currently empty /
        -- disabled / pre-layout. CreateContainer initializes frames to
        -- SetSize(1, 1); LayoutContainer only sets a real size when
        -- maxRowWidth > 0. Without a getSize callback, the layout mode
        -- proxy mover would shrink to HANDLE_MIN_SIZE on disabled/empty
        -- containers. Prefer the cached width/height the CDM module
        -- persists on every layout pass.
        local function GetCachedContainerSize(elementKey)
            local ncdm = GetNcdmDB()
            if not ncdm then return nil, nil end
            if elementKey == "cdmEssential" then
                return ncdm._lastEssentialWidth, ncdm._lastEssentialHeight
            elseif elementKey == "cdmUtility" then
                return ncdm._lastUtilityWidth, ncdm._lastUtilityHeight
            end
            return nil, nil
        end

        for _, info in ipairs(CDM_ELEMENTS) do
            um:RegisterElement({
                key = info.key,
                label = info.label,
                group = "Cooldown Manager & Custom Tracker Bars",
                order = info.order,
                isOwned = true,
                isEnabled = function()
                    local ncdm = GetNcdmDB()
                    if not ncdm or ncdm.enabled == false then return false end
                    local db = GetCDMDB(info.key)
                    return db and db.enabled ~= false
                end,
                setEnabled = function(val)
                    local db = GetCDMDB(info.key)
                    if db then db.enabled = val end
                    RefreshCDM()
                end,
                setGameplayHidden = function(hide)
                    local viewerKey = CDM_VIEWER_MAP[info.key]
                    local f = _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame(viewerKey)
                    if f then
                        if hide then f:Hide() else f:Show() end
                    end
                end,
                getFrame = function()
                    local viewerKey = CDM_VIEWER_MAP[info.key]
                    return _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame(viewerKey)
                end,
                -- Size fallback: use the live frame's dimensions when they're
                -- real, otherwise fall back to the CDM module's last-layout
                -- cache so the mover handle stays the right size even when
                -- the container is disabled/empty (frame size = 1x1).
                getSize = function()
                    local viewerKey = CDM_VIEWER_MAP[info.key]
                    local f = _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame(viewerKey)
                    if f and f.GetSize then
                        local ok, fw, fh = pcall(f.GetSize, f)
                        if ok and fw and fh and fw > 2 and fh > 2 then
                            return fw, fh
                        end
                    end
                    -- Frame is 1x1 (unlaid-out/disabled) — use cache.
                    local cw, ch = GetCachedContainerSize(info.key)
                    if cw and ch and cw > 2 and ch > 2 then
                        return cw, ch
                    end
                    return nil, nil
                end,
            })
        end

        -- Phase G: Register layout mode elements for custom containers.
        -- Phase B.3: customBar containers are registered here alongside
        -- other custom container types — the unified renderer owns them.
        local ncdmDB = ns.Helpers.GetCore()
        local ncdm = ncdmDB and ncdmDB.db and ncdmDB.db.profile and ncdmDB.db.profile.ncdm
        if ncdm and ncdm.containers then
            for key, settings in pairs(ncdm.containers) do
                if not settings.builtIn then
                    CDMContainers_API:RegisterDynamicLayoutElement(key, settings)
                end
            end
        end
    end

    C_Timer.After(2, RegisterLayoutModeElements)
end
