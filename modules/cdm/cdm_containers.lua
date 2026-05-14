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
local CDMLayout = ns.CDMLayout
local Shared = ns.CDMShared

-- Upvalue caching for hot-path performance
local type = type
local pairs = pairs
local ipairs = ipairs
local pcall = pcall
local C_Timer = C_Timer
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local hooksecurefunc = hooksecurefunc

local function IsCDMRuntimeEnabled()
    return not Shared or Shared.IsRuntimeEnabled()
end

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
local SETTINGS_FEATURE_ID = "cooldownManagerContainersPage"
local registeredSettingsLookupKeys = {}
local ANCHOR_KEY_MAP
-- Forward decl: defined later in the file but called from CreateContainer/
-- DeleteContainer above its definition. Without this, those callers would
-- bind the name as a global (nil) at parse time and crash on invocation.
local SyncSettingsFeatureLookups

---------------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------------
local containers = {}  -- { essential = frame, utility = frame, buff = frame }
local viewerState = {} -- keyed by container frame
local buffFingerprint = nil  -- fingerprint string for buff icon rebuild skipping
local applying = {}    -- re-entry guard per tracker
local refreshTimers = {} -- stored timer handles so overlapping RefreshAll calls cancel prior timers
local initialized = false
local runtimeEventFrame = nil
local RegisterContainerFrame
local SyncContainerMouseState
local SyncAllContainerMouseStates
local ApplyUtilityAnchor

-- Anchor proxy for Utility below Essential
local UtilityAnchorProxy = nil
local CreateContainer  -- forward declaration; assigned in CONTAINER CREATION section

local function CancelRefreshTimers()
    for i, handle in pairs(refreshTimers) do
        if handle and handle.Cancel then
            handle:Cancel()
        end
        refreshTimers[i] = nil
    end
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

-- Loadout tracking upvalues (parallel to spec tracking block above; D-11).
-- These are file-scoped so the OnEvent dispatcher and debounce closures
-- in this same file can close over them without forward-reference issues.
local _previousLoadoutID = nil       -- outgoing loadout ID; used by save-on-switch (mirrors _previousSpecID)
local _lastKnownSavedConfigID = nil  -- before/after compare filter: distinguishes loadout swap vs in-place talent edit
local loadoutListReady = false       -- flipped true by TRAIT_CONFIG_LIST_UPDATED
local pendingLoadoutRefresh = false  -- combat-deferred save/load flag; drained by PLAYER_REGEN_ENABLED
local loadoutTrackingToken = 0       -- abort-on-supersede token (parallels specTrackingRetryToken at line 130)
local loadoutDebounceTimer = nil     -- C_Timer.NewTimer handle; :Cancel() on new event; NOT C_Timer.After
local NO_SAVED_LOADOUT_ID = -2       -- Constants.TraitConsts.STARTER_BUILD_TRAIT_CONFIG_ID; nil and -2 both resolve to slot 0

-- Phase 2 / D-06: Live-refresh subscribers (settings label hook).
-- Subscribers register via ns.CDMContainers.RegisterLoadoutChangeCallback
-- and fire after every confirmed loadout-swap drain:
--   1. Out-of-combat debounce callback completes (line ~3178)
--   2. TRAIT_CONFIG_LIST_UPDATED drains a pending refresh (line ~3222)
--   3. PLAYER_REGEN_ENABLED drains a combat-deferred swap (line ~3266)
--   4. SyncCurrentProfileSpecState re-initialises on profile switch (line ~882)
-- Each dispatch wraps subscribers in pcall so a throwing subscriber
-- cannot break the event loop.
local _loadoutChangeCallbacks = {}

local function RegisterLoadoutChangeCallback(fn)
    if type(fn) == "function" then
        _loadoutChangeCallbacks[#_loadoutChangeCallbacks + 1] = fn
    end
end

local function FireLoadoutChangeCallbacks()
    for i = 1, #_loadoutChangeCallbacks do
        pcall(_loadoutChangeCallbacks[i])
    end
end

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

local function GetCurrentCharacterKey()
    if not UnitName then return nil end
    local name, realm = UnitName("player")
    if type(name) ~= "string" or name == "" then
        return nil
    end
    if type(realm) ~= "string" or realm == "" then
        realm = GetRealmName and GetRealmName() or nil
    end
    if type(realm) ~= "string" or realm == "" then
        return name
    end
    return name .. " - " .. realm
end

local function GetCurrentProfileName()
    local db = QUICore and QUICore.db
    if db and db.GetCurrentProfile then
        local ok, profileName = pcall(db.GetCurrentProfile, db)
        if ok and type(profileName) == "string" and profileName ~= "" then
            return profileName
        end
    end
    return "Default"
end

local function GetCharNcdmDB(create)
    local db = QUICore and QUICore.db
    local charDB = db and db.char
    if type(charDB) ~= "table" then
        return nil
    end
    if type(charDB.ncdm) ~= "table" then
        if not create then return nil end
        charDB.ncdm = {}
    end
    return charDB.ncdm
end

local function GetSpecStateDB(create)
    return GetCharNcdmDB(create) or GetDB()
end

local function GetSpecProfileStore(create)
    local charNcdm = GetCharNcdmDB(create)
    if not charNcdm then
        return nil
    end

    if type(charNcdm._specProfilesByProfile) ~= "table" then
        if not create then return nil end
        charNcdm._specProfilesByProfile = {}
    end
    local profileName = GetCurrentProfileName()
    if type(charNcdm._specProfilesByProfile[profileName]) ~= "table" then
        if not create then return nil end
        charNcdm._specProfilesByProfile[profileName] = {}
    end
    return charNcdm._specProfilesByProfile[profileName]
end

-- Pre-loadout container keys. Used by GetSpecLoadoutProfileStore's
-- in-place migration probe to detect the legacy 3-dim shape
-- (container keys directly under store[specID]) versus the new 4-dim
-- shape (integer loadoutID subkeys under store[specID]).
-- Custom user container keys (user-generated strings) cannot collide
-- with these four built-in container key names.
local LEGACY_CONTAINER_KEYS = {
    essential  = true,
    utility    = true,
    buff       = true,
    trackedBar = true,
}

-- Resolve the current effective loadout ID for storage keying (D-06).
-- Returns 0 (sentinel) when:
--   * perLoadoutSpec toggle is OFF
--   * GetLastSelectedSavedConfigID returns nil (e.g., login before TRAIT_CONFIG_LIST_UPDATED fires)
--   * Result is NO_SAVED_LOADOUT_ID (-2 = STARTER_BUILD_TRAIT_CONFIG_ID)
-- Returns the saved configID otherwise.
-- NEVER calls GetActiveConfigID itself — that is forbidden by LDST-04 (creates
-- orphaned keys from ephemeral staging configs that change each session).
local function GetEffectiveLoadoutID()
    local profileDB = GetDB()
    if not profileDB or not profileDB.perLoadoutSpec then return 0 end
    local specID = GetCurrentSpecID()
    if not specID or specID == 0 then return 0 end

    local savedID
    if C_ClassTalents and C_ClassTalents.GetLastSelectedSavedConfigID then
        savedID = C_ClassTalents.GetLastSelectedSavedConfigID(specID)
    end

    -- Combat-reload fast path (LDEV-04): when the live API is unavailable
    -- or returns nil (e.g. during ADDON_LOADED before TRAIT_CONFIG_LIST_UPDATED
    -- fires), fall back to the char-DB cached configID for this spec.
    -- STARTER_BUILD_TRAIT_CONFIG_ID (-2) is a legitimate "no saved loadout"
    -- state, not a missing-API state, so it bypasses the cache and routes
    -- to slot 0 directly.
    if not savedID then
        local charNcdm = GetCharNcdmDB(false)
        local cache = charNcdm and charNcdm._lastLoadoutConfigID
        local cachedID = cache and cache[specID]
        if type(cachedID) == "number" and cachedID > 0 then
            return cachedID
        end
        return 0
    end

    if savedID == NO_SAVED_LOADOUT_ID then return 0 end
    return savedID
end

-- Access the 4-dim loadout-scoped store slot for a (specID, loadoutID) pair.
-- Performs in-place read-time migration of the legacy 3-dim shape on
-- first access: when container keys (essential/utility/buff/trackedBar)
-- appear directly under store[specID], they are re-wrapped under
-- store[specID] = { [0] = <legacySpecSlot> } so the toggle-off sentinel
-- slot 0 receives the data (LDST-03).
--
-- Per D-05: does NOT auto-fallback to slot 0 when store[specID][loadoutID]
-- is empty, does NOT lazy-copy slot 0 contents. The toggle's first-enable
-- seed action is Phase 2's responsibility.
--
-- Returns nil when create=false and the slot doesn't exist; returns the
-- (possibly newly-created) slot table when create=true.
local function GetSpecLoadoutProfileStore(specID, loadoutID, create)
    if not specID or specID == 0 then return nil end
    local store = GetSpecProfileStore(create)
    if not store then return nil end

    -- In-place read-time migration probe: detect pre-loadout shape
    -- (LEGACY_CONTAINER_KEYS directly under store[specID]) and re-wrap
    -- the existing table under sentinel slot 0. The same table is
    -- reused by reference — no deep-copy, no AceDB-default mangling.
    local specSlot = store[specID]
    if type(specSlot) == "table" then
        local isLegacyShape = false
        for k in pairs(specSlot) do
            if LEGACY_CONTAINER_KEYS[k] then
                isLegacyShape = true
                break
            end
        end
        if isLegacyShape then
            store[specID] = { [0] = specSlot }
        end
    end

    if loadoutID == nil then return nil end

    if type(store[specID]) ~= "table" then
        if not create then return nil end
        store[specID] = {}
    end
    if type(store[specID][loadoutID]) ~= "table" then
        if not create then return nil end
        store[specID][loadoutID] = {}
    end
    return store[specID][loadoutID]
end

-- Phase 2 / D-05: One-shot first-enable seed.
-- Called by ns.CDMContainers.SeedActiveLoadoutFromSharedSlot from the
-- settings toggle when perLoadoutSpec transitions false → true. Copies
-- store[specID][0] container data into store[specID][activeLoadoutID]
-- via CopyTable, but ONLY when BOTH:
--   (a) the active loadout slot is absent or empty (no user data to overwrite)
--   (b) slot 0 has at least one container with data to copy
--
-- D-05b (true→false) is routing-only and never reaches this function —
-- the toggle handler in containers_page_surface.lua only fires this on
-- the false→true edge.
--
-- D-05a (combat-reload edge case where GetLastSelectedSavedConfigID
-- returns nil): no special-case handling needed — GetEffectiveLoadoutID
-- already falls back to db.char.ncdm._lastLoadoutConfigID[specID] when
-- the live API is unavailable, so the seed targets the correct slot.
local function SeedActiveLoadoutFromSharedSlot()
    if not specTrackingReady then return end

    local specID = GetCurrentSpecID()
    if not specID or specID == 0 then return end

    -- GetEffectiveLoadoutID returns 0 when perLoadoutSpec is off OR when
    -- no saved loadout is resolvable. The toggle handler sets
    -- perLoadoutSpec=true BEFORE calling this fn, so 0 here means
    -- "no saved loadout" — there's nothing to seed.
    local loadoutID = GetEffectiveLoadoutID()
    if loadoutID == 0 then return end

    -- (a) Active slot must be absent OR empty. GetSpecLoadoutProfileStore
    -- returns nil when the slot doesn't exist; an empty table also counts
    -- as "no user data" so seeding is safe.
    local targetSlot = GetSpecLoadoutProfileStore(specID, loadoutID, false)
    if targetSlot then
        for _ in pairs(targetSlot) do return end -- non-empty → don't overwrite
    end

    -- (b) Slot 0 must have at least one container with real spell data.
    local sourceSlot = GetSpecLoadoutProfileStore(specID, 0, false)
    if not sourceSlot then return end

    local containerKeys = CDMContainers_API:GetAllContainerKeys()
    local hasData = false
    for _, key in ipairs(containerKeys) do
        local containerData = sourceSlot[key]
        if type(containerData) == "table"
            and (containerData.ownedSpells or containerData.removedSpells or containerData.dormantSpells)
        then
            hasData = true
            break
        end
    end
    if not hasData then return end

    -- Both gates passed — materialise the target slot and per-container copy.
    -- Matches the existing CDM save/load CopyTable-per-container style
    -- at lines 537-539 (LoadLoadoutProfile read path).
    local destSlot = GetSpecLoadoutProfileStore(specID, loadoutID, true)
    if not destSlot then return end

    for _, key in ipairs(containerKeys) do
        local containerData = sourceSlot[key]
        if type(containerData) == "table" then
            destSlot[key] = {
                ownedSpells   = CopyTable(containerData.ownedSpells   or {}),
                removedSpells = CopyTable(containerData.removedSpells or {}),
                dormantSpells = CopyTable(containerData.dormantSpells or {}),
            }
        end
    end
end

local function StampActiveProfileSpecOwner(specID)
    if not specID or specID == 0 then
        return
    end
    local db = GetDB()
    if not db then
        return
    end
    db._lastSpecID = specID
    db._lastSpecCharKey = GetCurrentCharacterKey()
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

    local allReady = true
    for _, key in ipairs(containerKeys) do
        if key == "essential" or key == "utility" or key == "buff" or key == "trackedBar" then
            local containerDB = GetTrackerSettings(key)
            if containerDB and containerDB.ownedSpells == nil then
                -- Prefer the composer-owned seed path. Falls back to the
                -- legacy viewer-driven snapshot when the seed comes back
                -- empty (e.g., C_CooldownViewer not yet populated at very
                -- early ADDON_LOADED).
                local seeded
                if ns.CDMComposer and ns.CDMComposer.SeedFromBlizzard then
                    seeded = ns.CDMComposer.SeedFromBlizzard(key)
                end
                if seeded and #seeded > 0 then
                    containerDB.ownedSpells = seeded
                    containerDB.removedSpells = {}
                else
                    ns.CDMSpellData:SnapshotBlizzardCDM(key)
                end
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

    local loadoutID = GetEffectiveLoadoutID()
    local store = GetSpecLoadoutProfileStore(specID, loadoutID, true)
    if not store then
        return
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
        -- store IS store[specID][loadoutID] (the loadout slot). Write the
        -- per-container map directly INTO this leaf table. Wholesale slot
        -- replacement is fine because GetSpecLoadoutProfileStore returned a
        -- fresh table when create=true and the slot was empty; when it
        -- returned an existing slot, replacing its containers wholesale
        -- preserves sibling loadouts under store[specID][otherLoadoutID].
        for k, v in pairs(specData) do
            store[k] = v
        end
        StampActiveProfileSpecOwner(specID)
    end
end

local function SaveCurrentSpecProfile()
    -- Use _previousSpecID, not GetCurrentSpecID(). By the time
    -- PLAYER_SPECIALIZATION_CHANGED fires the current spec is already
    -- the NEW spec — saving under GetCurrentSpecID() would store the
    -- outgoing spec's data under the incoming spec's key.
    SaveSpecProfile(_previousSpecID)
end

-- Save the current live container state into the (specID, loadoutID) slot.
-- Used during a loadout swap to persist the OUTGOING loadout's containers
-- BEFORE loading the incoming loadout. Mirror of SaveSpecProfile (line ~381)
-- but indexed by an explicit loadoutID instead of GetEffectiveLoadoutID()
-- — because at swap time _previousLoadoutID is the outgoing slot, NOT the
-- value GetEffectiveLoadoutID() returns (which already reflects the new
-- saved-loadout the user just switched to).
local function SaveLoadoutProfile(loadoutID, specID)
    if not specTrackingReady then return end  -- LDEV-05
    if not specID or specID == 0 then return end
    if loadoutID == nil then return end

    local store = GetSpecLoadoutProfileStore(specID, loadoutID, true)
    if not store then return end

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

    if hasAnySpells then
        -- store IS store[specID][loadoutID]. Write per-container map directly.
        for k, v in pairs(specData) do
            store[k] = v
        end
        StampActiveProfileSpecOwner(specID)
    end
end

-- Load saved containers from the (specID, loadoutID) slot into live state.
-- Used during a loadout swap to restore the INCOMING loadout's containers
-- AFTER saving the outgoing loadout. Mirror of the savedProfile branch of
-- LoadOrSnapshotSpecProfile (line ~516 post-Plan-01).
--
-- myToken: caller passes the token snapshot taken before scheduling; the
-- helper aborts if a newer event has bumped loadoutTrackingToken in the
-- meantime (D-11 / LDEV-05).
--
-- Returns true if a profile was loaded; false if the slot was empty (no
-- destructive clear in that case — leaves current containers intact per
-- D-05's "no auto-fallback to slot 0").
local function LoadLoadoutProfile(loadoutID, specID, myToken)
    if not specTrackingReady then return false end  -- LDEV-05
    if myToken and myToken ~= loadoutTrackingToken then return false end  -- LDEV-05 abort
    if not specID or specID == 0 then return false end
    if loadoutID == nil then return false end

    local store = GetSpecLoadoutProfileStore(specID, loadoutID, false)
    if not store then return false end  -- empty slot: per D-05, leave containers as-is

    -- Validate the saved slot actually contains spell data.
    local containerKeys = CDMContainers_API:GetAllContainerKeys()
    local profileHasSpells = false
    for _, key in ipairs(containerKeys) do
        local sc = store[key]
        if sc and type(sc.ownedSpells) == "table" and #sc.ownedSpells > 0 then
            profileHasSpells = true
            break
        end
    end
    if not profileHasSpells then return false end  -- D-05: don't clear, just bail

    -- Restore each container's spell lists from the saved slot.
    for _, key in ipairs(containerKeys) do
        local containerDB = GetTrackerSettings(key)
        if containerDB then
            local savedContainer = store[key]
            if savedContainer then
                containerDB.ownedSpells   = CopyTable(savedContainer.ownedSpells)
                containerDB.removedSpells = CopyTable(savedContainer.removedSpells)
                containerDB.dormantSpells = CopyTable(savedContainer.dormantSpells or {})
                containerDB._dormantSequence = savedContainer.dormantSequence or 0
            else
                -- Container exists now but wasn't in this loadout slot.
                -- Mirror LoadOrSnapshotSpecProfile (line ~527-532): clear
                -- so stale spells from the previous loadout don't leak.
                ClearContainerSpecState(containerDB)
            end
        end
    end

    if ns.CDMSpellData then
        ns.CDMSpellData:CheckAllDormantSpells()
        ns.CDMSpellData:ReconcileAllContainers()
    end
    if RefreshAll then RefreshAll() end  -- Q10: containers must re-render for the new loadout slot
    return true
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
    local loadoutID = GetEffectiveLoadoutID()
    local store = GetSpecLoadoutProfileStore(specID, loadoutID, false)
    local savedProfile = store  -- store IS the loadout leaf; no extra [specID] index needed

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
            -- Discard the empty loadout slot via the parent store. `store` is
            -- the loadout leaf, so wiping store[specID] would do nothing useful.
            local parentStore = GetSpecProfileStore(false)
            if parentStore and parentStore[specID] then
                parentStore[specID][loadoutID] = nil
            end
            savedProfile = nil
        end
    end

    -- Upgrade path for the active character/profile: if no scoped spec store
    -- exists yet, seed it from the current live container state only when the
    -- shared profile state was last written by this character (or predates the
    -- character stamp entirely). If another character wrote the shared state,
    -- ignore it and snapshot clean data for this character instead.
    if not savedProfile then
        local currentCharKey = GetCurrentCharacterKey()
        local profileCharKey = db._lastSpecCharKey
        if (not profileCharKey) or profileCharKey == currentCharKey then
            local specData = {}
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
            if hasAnySpells then
                store = GetSpecLoadoutProfileStore(specID, loadoutID, true)
                if store then
                    -- Same shape as SaveSpecProfile: write per-container into
                    -- the loadout slot leaf.
                    for k, v in pairs(specData) do
                        store[k] = v
                    end
                    savedProfile = specData
                end
            end
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
        StampActiveProfileSpecOwner(specID)
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
                SaveSpecProfile(specID)
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
-- Returns profile hydration readiness and whether a spec mismatch was detected.
local function RunCrossSessionDetection(specID)
    local db = GetSpecStateDB(true)
    if not db or not specID or specID == 0 then return false, false end

    local lastSpecID = db._lastSpecID
    local currentCharKey = GetCurrentCharacterKey()
    local detected = lastSpecID ~= nil and lastSpecID ~= specID
    local readyNow = true
    local shouldLoadActiveSpec = true
    local profileDB = GetDB()
    local profileCharKey = profileDB and profileDB._lastSpecCharKey
    local liveStateOwnedByCurrentChar = (not profileCharKey) or profileCharKey == currentCharKey
    if lastSpecID and lastSpecID ~= specID and liveStateOwnedByCurrentChar then
        -- Save stale ownedSpells under the old spec before overwriting
        local oldPrevious = _previousSpecID
        _previousSpecID = lastSpecID
        SaveCurrentSpecProfile()
        _previousSpecID = oldPrevious
    end

    if shouldLoadActiveSpec then
        -- Invalidate caches before hydrating the active spec. Even when the
        -- spec ID did not change, the profile's live containers may belong
        -- to a different character sharing the same AceDB profile.
        if ns.InvalidateCDMFrameCache then ns.InvalidateCDMFrameCache() end
        if ns.CDMSpellData and ns.CDMSpellData.InvalidateLearnedCache then
            ns.CDMSpellData:InvalidateLearnedCache()
        end

        -- Load the correct spec profile (or fresh snapshot if first time).
        specTrackingRetryToken = specTrackingRetryToken + 1
        readyNow = LoadOrSnapshotSpecProfile(specID, 1, specTrackingRetryToken)
    end
    -- Persist the current spec ID for next session
    db._lastSpecID = specID
    db._lastSpecCharKey = currentCharKey
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

    -- On a combat /reload, GetCurrentSpecID() returns nil during the
    -- ADDON_LOADED safe window because Blizzard hasn't re-stamped the
    -- spec APIs yet. Spec can't change in combat, so the spec ID
    -- persisted from the previous session is still valid. Falling back
    -- to it lets the synchronous safe-window RefreshAll fire
    -- immediately; without this, the spec only resolves at the 1s
    -- retry, which runs outside the safe window and gets stuck behind
    -- combat lockdown until PLAYER_REGEN_ENABLED — making CDM invisible
    -- for the entire combat /reload. Cross-session character swap
    -- protection (the original reason for the spec gate) is preserved:
    -- _lastSpecID lives in character state, with a guarded legacy profile
    -- fallback for old combat reloads, and RunCrossSessionDetection still
    -- reconciles if the spec changed while logged out.
    if (not _previousSpecID) or _previousSpecID == 0 then
        local db = GetSpecStateDB(false)
        local cached = db and db._lastSpecID
        local currentCharKey = GetCurrentCharacterKey()
        local cachedCharKey = db and db._lastSpecCharKey
        if not cached then
            local profileDB = GetDB()
            local profileCached = profileDB and profileDB._lastSpecID
            local profileCharKey = profileDB and profileDB._lastSpecCharKey
            if profileCached and profileCached ~= 0
                and (profileCharKey == currentCharKey or (not profileCharKey and InCombatLockdown()))
            then
                cached = profileCached
                cachedCharKey = profileCharKey
            end
        end
        if cached and cached ~= 0
            and (cachedCharKey == currentCharKey or (not cachedCharKey and InCombatLockdown()))
        then
            _previousSpecID = cached
        end
    end

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

    -- Cancel any stale loadout debounce/drain from the previous profile.
    -- The new profile may have perLoadoutSpec set differently; reset all
    -- loadout state so the first event after switch re-primes from scratch.
    if loadoutDebounceTimer then
        loadoutDebounceTimer:Cancel()
        loadoutDebounceTimer = nil
    end
    loadoutTrackingToken = loadoutTrackingToken + 1
    _previousLoadoutID = nil
    _lastKnownSavedConfigID = nil
    pendingLoadoutRefresh = false
    -- NOTE: loadoutListReady is intentionally NOT reset — the talent list is
    -- a Blizzard-side session global, not profile-scoped. Resetting it would
    -- block all subsequent loadout drains until TRAIT_CONFIG_LIST_UPDATED fires.
    -- NOTE: db.char.ncdm._lastLoadoutConfigID is intentionally NOT cleared —
    -- it is the persistent fast-path cache for combat-reload recovery.

    local specReadyNow = InitSpecTracking()
    if not specReadyNow then
        specTrackingPendingRefresh = true
    end

    -- Phase 2 / D-06: profile switch may change perLoadoutSpec; refresh subscribers.
    FireLoadoutChangeCallbacks()
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
--
-- Custom containers do NOT carry a `containerType` — they're mixed-kind by
-- design (the composer's add-source tab determines each entry's kind).
-- The `containerType` argument is accepted only as a SHAPE hint (Custom
-- Icons vs Custom Bars) and is consumed locally to pick visual defaults;
-- it is never persisted in `settings.containerType`. The shape lives in
-- `settings.shape`.
function CDMContainers_API:CreateContainer(name, containerType)
    if InCombatLockdown() then return nil end
    if not name or name == "" then name = "Custom" end
    local shapeHint = containerType or "cooldown"

    local db = GetDB()
    if not db then return nil end
    if not db.containers then db.containers = {} end

    local key = GenerateContainerKey()
    local settings = GetDefaultsByContainerType(shapeHint)
    settings.builtIn = false
    settings.name = name
    settings.containerType = nil  -- custom bars have NO container type
    settings.shape = (shapeHint == "auraBar") and "bar" or "icon"
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
                local width = (vs and vs.cdmIconWidth) or (source:GetWidth() or 0)
                local height = (vs and vs.cdmTotalHeight) or (source:GetHeight() or 0)
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
    local cx = rawCx
    local cy = rawCy
    local sx = rawSx
    local sy = rawSy
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
                    -- ox/oy are center offsets; CDMLayout converts them back
                    -- to point/relative offsets for non-center anchors.
                    local vs = viewerState[container]
                    local frameW = (vs and (vs.cdmIconWidth or vs.row1Width)) or (container:GetWidth() or 1) or 1
                    local frameH = (vs and vs.cdmTotalHeight) or (container:GetHeight() or 1) or 1
                    local parentW = (UIParent:GetWidth() or 1) or 1
                    local parentH = (UIParent:GetHeight() or 1) or 1
                    settings.offsetX, settings.offsetY = CDMLayout.ComputeAnchorOffsets(
                        ox, oy,
                        settings.point or "CENTER",
                        settings.relative or "CENTER",
                        frameW, frameH, parentW, parentH)
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
    local cw = (container:GetWidth() or 0)
    local ch = (container:GetHeight() or 0)
    local width, height = CDMLayout.GetBootstrapSize(trackerKey, cw, ch, viewerState[container], GetDB())
    if width and height then
        container:SetSize(width, height)
    end
end

local function InitContainers()
    if containers.essential then return end -- already created

    RegisterContainerFrame("essential", CreateContainer("QUI_EssentialContainer"))
    RegisterContainerFrame("utility", CreateContainer("QUI_UtilityContainer"))
    RegisterContainerFrame("buff", CreateContainer("QUI_CDMBuffIconContainer"))
    RegisterContainerFrame("trackedBar", CreateContainer("QUI_CDMBuffBarContainer"))

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
-- The addon-owned CDM buff icon container is created in InitContainers().
-- This function ensures it exists and notifies CDMBuffLayout.
local function InitBuffContainer()
    if not containers.buff then
        -- InitContainers hasn't run yet -- create the container now
        RegisterContainerFrame("buff", CreateContainer("QUI_CDMBuffIconContainer"))
    end
    -- Restore position from DB (or seed from Blizzard viewer on first-ever init).
    -- Skip when anchored — ApplyBuffIconAnchor manages position.
    local db = GetDB()
    local anchorTo = db and db.buff and db.buff.anchorTo or "disabled"
    if anchorTo == "disabled" then
        InitContainerPosition(containers.buff, "buff")
    end
    if ns.InvalidateCDMFrameCache then ns.InvalidateCDMFrameCache() end
    -- Notify CDM buff layout to set up hooks on the new container.
    if ns.CDMBuffLayout and ns.CDMBuffLayout.OnContainerReady then
        C_Timer.After(0.1, function()
            ns.CDMBuffLayout:OnContainerReady()
        end)
    end
end

-- Forward declarations needed by LayoutContainer (Edit Mode guards).
local _editModeActive = false
local _disabledMouseFrames = {}
local _forceLayoutKey = nil  -- set temporarily to bypass edit mode check for one container
local _containerMouseSyncPending = false

local function IsCDMMouseoverFadeEnabled()
    local vis = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.cdmVisibility
    return vis and not vis.showAlways and vis.showOnMouseover
end

local function SetFrameMouseDisabled(frame)
    if not frame then
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
    if not frame then
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
    if not icon then
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
        alpha = alphaOverride
    end
    if alpha == nil and container.GetAlpha then
        alpha = (container:GetAlpha() or 1)
    end
    alpha = alpha or 1

    local hidden = alpha <= 0.001
    local hoverOnly = IsCDMMouseoverFadeEnabled()
    local stateChanged = (container._quiAlphaHidden ~= hidden) or (container._quiHoverOnly ~= hoverOnly)

    if not (force or stateChanged) then
        return
    end

    container._quiAlphaHidden = hidden
    container._quiHoverOnly = hoverOnly

    if InCombatLockdown() and not inInitSafeWindow then
        _containerMouseSyncPending = true
        return
    end

    if hoverOnly then
        SetFrameHoverOnly(container)
    else
        SetFrameMouseDisabled(container)
    end

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
    if not IsCDMRuntimeEnabled() then return end

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

    -- Store layout direction for external consumers; placement math lives in CDMLayout.
    local layoutDirection = settings.layoutDirection or "HORIZONTAL"
    vs.cdmLayoutDirection = layoutDirection

    -- Buff tracker: create addon-owned icons via icon factory, adopt
    -- Blizzard CooldownFrames for taint-safe aura display.
    -- Blizzard's children stay in the hidden viewer (alpha=0).
    -- CDMBuffLayout handles positioning and styling of addon-owned icons.
    if trackerKey == "buff" then
        InitBuffContainer()
        container = containers.buff
        if not container then
            applying[trackerKey] = false
            return
        end

        -- Ensure buff container has a minimum size so overlays and anchor
        -- proxies have valid bounds before any buffs are active. Sizing is
        -- driven by the owned-layout bounds cached by LayoutBuffIcons() via
        -- QUI_SetCDMViewerBounds(); never sourced from Blizzard's viewer
        -- (which can report one-icon bounds and clip overlapping slot icons).
        local cw = (container:GetWidth() or 0)
        local ch = (container:GetHeight() or 0)
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
        -- CDM buff layout pass measures and positions the final shown/hidden
        -- set, instead of laying out once pre-visibility and again after
        -- active-only filtering settles.
        if ns.CDMIcons and ns.CDMIcons.UpdateAllCooldowns then
            ns.CDMIcons:UpdateAllCooldowns()
        end
        -- Position and style icons immediately once visibility has settled
        -- for this rebuild batch.
        if ns.CDMBuffLayout and ns.CDMBuffLayout.OnLayoutReady then
            ns.CDMBuffLayout:OnLayoutReady()
        end
        return
    end

    -- Build icons via the icon factory (essential/utility only)
    local allIcons = ns.CDMIcons:BuildIcons(trackerKey, container)
    local totalCapacity = CDMLayout and CDMLayout.GetTotalIconCapacity and CDMLayout.GetTotalIconCapacity(settings) or 0

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
                if _G.QUI_CDM_ICON_DEBUG and ns.CDMIcons and ns.CDMIcons.DebugLayoutFilter then
                    ns.CDMIcons.DebugLayoutFilter(icon, filterHides, settings, isOnCD)
                end
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

    -- HUD min-width floor is computed here because it depends on broader HUD
    -- profile state; the layout module only receives the resulting scalar.
    local minWidthEnabled, minWidth = GetHUDMinWidth()
    local applyHUDMinWidth = minWidthEnabled
        and (trackerKey == "essential" or trackerKey == "utility")
        and IsHUDAnchoredToCDM()

    local layoutPlan = CDMLayout and CDMLayout.BuildIconLayout
        and CDMLayout.BuildIconLayout(settings, iconsToLayout, {
            applyHUDMinWidth = applyHUDMinWidth,
            minWidth = minWidth,
        })
    if not layoutPlan or not layoutPlan.metrics or #layoutPlan.placements == 0 then
        applying[trackerKey] = false
        return
    end

    for _, placement in ipairs(layoutPlan.placements) do
        local icon = placement.icon
        local rowConfig = placement.rowConfig
        local x = placement.x
        local y = placement.y

        ns.CDMIcons.ConfigureIcon(icon, rowConfig)

        if icon.GetScale and icon:GetScale() ~= 1 then
            icon:SetScale(1)
        end

        if QUICore and QUICore.PixelRound then
            x = QUICore:PixelRound(x, container)
            y = QUICore:PixelRound(y, container)
        end
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", container, "CENTER", x, y)
        icon:Show()

        ns.CDMIcons.UpdateIconCooldown(icon)
    end

    local metrics = layoutPlan.metrics
    local maxRowWidth = metrics.iconWidth or 0
    local proxyTotalHeight = metrics.totalHeight or 0

    -- Store dimensions in viewer state
    vs.cdmIconWidth = maxRowWidth
    vs.cdmRawContentWidth = metrics.rawContentWidth or 0
    vs.cdmTotalHeight = proxyTotalHeight
    vs.cdmProxyYOffset = metrics.proxyYOffset or 0

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

    vs.cdmRow1IconHeight = metrics.row1IconHeight or 0
    vs.cdmRow1BorderSize = metrics.row1BorderSize or 0
    vs.cdmBottomRowBorderSize = metrics.bottomRowBorderSize or 0
    vs.cdmBottomRowYOffset = metrics.bottomRowYOffset or 0
    vs.cdmRow1Width = metrics.row1Width or maxRowWidth
    vs.cdmBottomRowWidth = metrics.bottomRowWidth or maxRowWidth
    vs.cdmRawRow1Width = metrics.rawRow1Width or (metrics.rawContentWidth or 0)
    vs.cdmRawBottomRowWidth = metrics.rawBottomRowWidth or (metrics.rawContentWidth or 0)
    vs.cdmPotentialRow1Width = metrics.potentialRow1Width or maxRowWidth
    vs.cdmPotentialBottomRowWidth = metrics.potentialBottomRowWidth or maxRowWidth

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
-- Post-layout work shared by both sync and async paths: re-apply locked
-- bars, anchored unit frames, mouseover state, swipe/glow, range poll, icon
-- visibility, and container mouse state. Same body, same order; previously
-- duplicated inline.
local function RunPostLayoutRefresh()
    UpdateAllLockedBars()
    if _G.QUI_UpdateCDMAnchoredUnitFrames then
        _G.QUI_UpdateCDMAnchoredUnitFrames()
    end
    if _G.QUI_RefreshCDMMouseover then
        _G.QUI_RefreshCDMMouseover()
    end
    -- Apply swipe settings and glow state to newly created/rebuilt icons.
    if _G.QUI_RefreshCooldownSwipe then
        _G.QUI_RefreshCooldownSwipe()
    end
    if _G.QUI_RefreshCustomGlows then
        _G.QUI_RefreshCustomGlows()
    end
    -- Reapply icon visibility after layout so "active only" display mode
    -- hides inactive icons that LayoutContainer() showed.
    if ns.CDMIcons and ns.CDMIcons.UpdateAllCooldowns then
        ns.CDMIcons:UpdateAllCooldowns()
    end
    SyncAllContainerMouseStates(true)
end

RefreshAll = function(forceSync)
    if not initialized then
        return
    end

    if not IsCDMRuntimeEnabled() then
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
    CancelRefreshTimers()

    if ns.CDMSpellData then
        ns.CDMSpellData:UpdateCVar()
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

    -- Buff fingerprint is NOT reset here. Owned spell lists are kept in sync
    -- by composer changes — the fingerprint comparison in LayoutContainer("buff")
    -- will detect any actual change and rebuild. Unconditional reset causes a
    -- visible flash (ClearPool + BuildIcons destroys and recreates all icons
    -- even when nothing changed).

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
        for _, key in ipairs(customKeys) do
            LayoutContainer(key)
        end
        RunPostLayoutRefresh()
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

        -- Run shared post-layout work after all per-container timers complete.
        local finalTimerDelay = 0.10 + #customKeys * 0.01
        refreshTimers[100] = C_Timer.NewTimer(finalTimerDelay, function()
            refreshTimers[100] = nil
            if InCombatLockdown() and not inInitSafeWindow then
                specTrackingPendingRefresh = true
                return
            end
            RunPostLayoutRefresh()
        end)
    end
end

---------------------------------------------------------------------------
-- UTILITY ANCHOR: Position Utility container below Essential
---------------------------------------------------------------------------
ApplyUtilityAnchor = function()
    if not IsCDMRuntimeEnabled() then return end

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

    local totalOffset = CDMLayout.GetUtilityAnchorOffset(utilSettings)

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
-- and for settings-driven refreshes (RefreshContainer in containers_page_schema).
_G.QUI_ForceLayoutContainer = function(containerKey)
    if not containerKey or not initialized then return end
    if not IsCDMRuntimeEnabled() then return end
    _forceLayoutKey = containerKey
    LayoutContainer(containerKey)
    _forceLayoutKey = nil
    -- Reapply icon visibility after layout — mirrors RefreshAll's pattern
    -- (see "Reapply icon visibility after layout" call in RefreshAll above).
    -- LayoutContainer() Show()'s every laid-out icon and the buff path can
    -- short-circuit on its fingerprint, so without an explicit pass here
    -- container-level settings like iconDisplayMode = "active" don't take
    -- effect until the next event-scheduled CDM update tick — that's the
    -- gap users perceive as "this dropdown needs /reload".
    if ns.CDMIcons and ns.CDMIcons.UpdateAllCooldowns then
        ns.CDMIcons:UpdateAllCooldowns()
    end
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

-- EDIT MODE INTEGRATION
-- During Edit Mode, QUI containers stay visible with overlays. Clicking an
-- overlay opens Blizzard CDM settings. Nudge buttons handle pixel-precise
-- positioning. Positions save to DB on exit. Blizzard's own viewers are
-- managed by Blizzard's Edit Mode and untouched by QUI.
---------------------------------------------------------------------------

-- _editModeActive and _disabledMouseFrames are forward-declared above
-- LayoutContainer (they are referenced inside it).
_G.QUI_IsCDMEditModeHidden = function() return false end  -- backward compat
_G.QUI_IsCDMEditModeActive = function() return _editModeActive end

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
    if not IsCDMRuntimeEnabled() then return end

    -- Rebuild BEFORE setting _editModeActive, because LayoutContainer bails
    -- out when _editModeActive is true. This ensures buff icons exist for
    -- the user to see during edit mode.
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
        local cw = (containers.trackedBar:GetWidth() or 0)
        local ch = (containers.trackedBar:GetHeight() or 0)
        if cw <= 1 or ch <= 1 then
            local db2 = GetDB()
            local tbs2 = db2 and db2.trackedBar
            local barWidth = (tbs2 and tbs2.barWidth) or 215
            local barHeight = (tbs2 and tbs2.barHeight) or 25
            containers.trackedBar:SetSize(barWidth, barHeight)
        end
    end

    _editModeActive = true

    -- Force buff icons visible immediately (don't wait for ticker).
    ForceBuffIconsVisible()

    -- Re-run buff layout so the owned container (and its layout mode
    -- mover) sizes to match every now-visible icon, mirroring the
    -- trackedBar path above. Without this, the mover reflects only the
    -- pre-ForceBuffIconsVisible count and clips icons during layout mode.
    if ns.CDMBuffLayout and ns.CDMBuffLayout.OnLayoutReady then
        ns.CDMBuffLayout:OnLayoutReady()
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
    if not IsCDMRuntimeEnabled() then return end

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
NCDM.RefreshAll = RefreshAll
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

---------------------------------------------------------------------------
-- Initialize: called by cdm_provider.lua after engine selection
---------------------------------------------------------------------------
function ownedEngine:Initialize()
    if not IsCDMRuntimeEnabled() then
        return
    end

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

    -- Build the Blizzard CDM mirror catalog NOW, inside the safe window, so
    -- BuildIcons → TryBindIconToBlizz can resolve cooldownIDs for every
    -- Blizzard-mirrored icon. The mirror's own PLAYER_LOGIN / PLAYER_ENTERING_WORLD
    -- Walk fires on a separate event frame and can run after this window has
    -- closed; on a combat /reload it would otherwise bail until combat ends.
    if ns.CDMBlizzMirror and ns.CDMBlizzMirror.ForceRescan then
        ns.CDMBlizzMirror.ForceRescan()
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
    runtimeEventFrame = eventFrame
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    eventFrame:RegisterEvent("ACTIVE_COMBAT_CONFIG_CHANGED")
    eventFrame:RegisterEvent("TRAIT_CONFIG_LIST_UPDATED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("CHALLENGE_MODE_START")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:RegisterEvent("CINEMATIC_STOP")
    eventFrame:RegisterEvent("STOP_MOVIE")
    eventFrame:RegisterEvent("ADDON_LOADED")

    eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2)
        if not IsCDMRuntimeEnabled() then
            self:UnregisterAllEvents()
            return
        end

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
                if ns.CDMBlizzMirror and ns.CDMBlizzMirror.ForceRescan then
                    ns.CDMBlizzMirror.ForceRescan()
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
                -- Persist for cross-session detection.
                local specDB = GetSpecStateDB(true)
                if specDB then
                    specDB._lastSpecID = newSpecID
                    specDB._lastSpecCharKey = GetCurrentCharacterKey()
                end
                -- Profile is now correct — SPELLS_CHANGED can safely run
                -- dormant/reconcile on the new spec's data.
                buffFingerprint = nil
                if readyNow then
                    specTrackingReady = true
                    specTrackingPendingRefresh = false
                    RefreshAll()
                end
            end
        elseif event == "TRAIT_CONFIG_UPDATED" or event == "ACTIVE_COMBAT_CONFIG_CHANGED" then
            -- Both events route through one debounce timer. Cancel any prior
            -- fire so a rapid sequence (e.g. talent edit immediately followed
            -- by save) collapses to a single save/load pair.
            if loadoutDebounceTimer then loadoutDebounceTimer:Cancel() end

            loadoutTrackingToken = loadoutTrackingToken + 1
            local myToken = loadoutTrackingToken

            loadoutDebounceTimer = C_Timer.NewTimer(0.5, function()
                loadoutDebounceTimer = nil
                if myToken ~= loadoutTrackingToken then return end  -- newer event superseded us
                if not specTrackingReady then
                    pendingLoadoutRefresh = true
                    return
                end

                local specID = GetCurrentSpecID()
                if not specID then return end

                -- Re-resolve the saved-loadout ID fresh inside the callback.
                -- NEVER use the event payload's configID for the storage key
                -- (it's the active staging config, not the persistent saved one).
                local newConfigID = nil
                if C_ClassTalents and C_ClassTalents.GetLastSelectedSavedConfigID then
                    newConfigID = C_ClassTalents.GetLastSelectedSavedConfigID(specID)
                end

                -- Filter: in-place talent edit (saved ID unchanged) — ignore.
                -- Only proceed when the saved-loadout selection actually changed.
                if newConfigID == _lastKnownSavedConfigID then return end

                -- Real loadout swap detected.
                if InCombatLockdown() then
                    -- Defer save/load; PLAYER_REGEN_ENABLED drains as an atomic pair.
                    pendingLoadoutRefresh = true
                    return
                end

                -- Save outgoing, load incoming as a unit (D-10 / LDEV-03).
                SaveLoadoutProfile(_previousLoadoutID, specID)

                _previousLoadoutID = newConfigID
                _lastKnownSavedConfigID = newConfigID

                -- Prime the db.char fast-path cache for combat-reload (LDEV-04).
                local charNcdm = GetCharNcdmDB(true)
                if charNcdm then
                    if type(charNcdm._lastLoadoutConfigID) ~= "table" then
                        charNcdm._lastLoadoutConfigID = {}
                    end
                    charNcdm._lastLoadoutConfigID[specID] = newConfigID
                end

                LoadLoadoutProfile(newConfigID, specID, myToken)
                FireLoadoutChangeCallbacks()  -- Phase 2 / D-06
            end)
        elseif event == "TRAIT_CONFIG_LIST_UPDATED" then
            loadoutListReady = true

            -- Prime the db.char fast-path cache for the current spec
            -- as soon as the live API becomes available (LDEV-04).
            local specID = GetCurrentSpecID()
            if specID and C_ClassTalents and C_ClassTalents.GetLastSelectedSavedConfigID then
                local configID = C_ClassTalents.GetLastSelectedSavedConfigID(specID)
                if configID and configID ~= NO_SAVED_LOADOUT_ID then
                    local charNcdm = GetCharNcdmDB(true)
                    if charNcdm then
                        if type(charNcdm._lastLoadoutConfigID) ~= "table" then
                            charNcdm._lastLoadoutConfigID = {}
                        end
                        charNcdm._lastLoadoutConfigID[specID] = configID
                    end
                    if _lastKnownSavedConfigID == nil then
                        _lastKnownSavedConfigID = configID
                        _previousLoadoutID = configID
                    end
                end
            end

            -- If a swap-or-init was deferred at login (before the list was
            -- ready), drain it now — but only when out of combat. The combat
            -- branch is handled by PLAYER_REGEN_ENABLED.
            if pendingLoadoutRefresh
                and specTrackingReady
                and not InCombatLockdown()
            then
                pendingLoadoutRefresh = false
                loadoutTrackingToken = loadoutTrackingToken + 1
                local hydrationToken = loadoutTrackingToken
                local hydrateSpecID = GetCurrentSpecID()
                if hydrateSpecID then
                    SaveLoadoutProfile(_previousLoadoutID, hydrateSpecID)
                    local newConfigID = nil
                    if C_ClassTalents and C_ClassTalents.GetLastSelectedSavedConfigID then
                        newConfigID = C_ClassTalents.GetLastSelectedSavedConfigID(hydrateSpecID)
                    end
                    _previousLoadoutID = newConfigID
                    _lastKnownSavedConfigID = newConfigID
                    LoadLoadoutProfile(newConfigID, hydrateSpecID, hydrationToken)
                    FireLoadoutChangeCallbacks()  -- Phase 2 / D-06a
                end
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
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
            end

            -- Drain deferred loadout save/load (D-10 / LDEV-03).
            -- Save AND load happen as a unit: never load without saving outgoing first.
            if pendingLoadoutRefresh and loadoutListReady and specTrackingReady then
                pendingLoadoutRefresh = false
                loadoutTrackingToken = loadoutTrackingToken + 1
                local drainToken = loadoutTrackingToken

                local drainSpecID = GetCurrentSpecID()
                if drainSpecID then
                    SaveLoadoutProfile(_previousLoadoutID, drainSpecID)
                    local newConfigID = nil
                    if C_ClassTalents and C_ClassTalents.GetLastSelectedSavedConfigID then
                        newConfigID = C_ClassTalents.GetLastSelectedSavedConfigID(drainSpecID)
                    end
                    _previousLoadoutID = newConfigID
                    _lastKnownSavedConfigID = newConfigID

                    local charNcdm = GetCharNcdmDB(true)
                    if charNcdm and newConfigID and newConfigID ~= NO_SAVED_LOADOUT_ID then
                        if type(charNcdm._lastLoadoutConfigID) ~= "table" then
                            charNcdm._lastLoadoutConfigID = {}
                        end
                        charNcdm._lastLoadoutConfigID[drainSpecID] = newConfigID
                    end

                    LoadLoadoutProfile(newConfigID, drainSpecID, drainToken)
                    FireLoadoutChangeCallbacks()  -- Phase 2 / D-06
                end
            end

            if _containerMouseSyncPending and not InCombatLockdown() then
                _containerMouseSyncPending = false
                SyncAllContainerMouseStates(true)
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

function ownedEngine:DisableRuntime()
    initialized = false
    NCDM.initialized = false
    specTrackingPendingRefresh = false
    specTrackingRetryToken = specTrackingRetryToken + 1
    inInitSafeWindow = false
    CancelRefreshTimers()

    -- Loadout state teardown (parallels the spec-tracking lines above).
    -- A live debounce timer would fire into a nil runtimeEventFrame after
    -- DisableRuntime returns; bump the token and cancel the timer here.
    if loadoutDebounceTimer then
        loadoutDebounceTimer:Cancel()
        loadoutDebounceTimer = nil
    end
    pendingLoadoutRefresh = false
    loadoutTrackingToken = loadoutTrackingToken + 1

    if runtimeEventFrame then
        runtimeEventFrame:UnregisterAllEvents()
        runtimeEventFrame:SetScript("OnEvent", nil)
        runtimeEventFrame = nil
    end

    for _, frame in pairs(containers) do
        if frame and frame.SetAlpha then
            frame.SetAlpha(frame, 0)
        end
    end
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
    -- No QUI container yet (engine pre-init or unknown key): the provider
    -- handles Blizzard-frame pre-init resolution above this layer.
    return nil
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
    RegisterDynamicLayoutElement = function(key, settings) return CDMContainers_API:RegisterDynamicLayoutElement(key, settings) end,
    SyncSettingsFeatureLookups = SyncSettingsFeatureLookups,
    -- Save current spec's ownedSpells to the scoped spec profile store (called after Composer mutations).
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
        for _, key in ipairs(containerKeys) do
            ns.CDMSpellData:SnapshotBlizzardCDM(key)
        end
    end,

    -- Phase 2 / D-05: First-enable seed. Called from the perLoadoutSpec
    -- toggle handler in modules/cdm/settings/containers_page_surface.lua
    -- ONLY on the false→true transition. No-op if guards fail.
    SeedActiveLoadoutFromSharedSlot = SeedActiveLoadoutFromSharedSlot,

    -- Phase 2 / D-06: Live-refresh subscription. The settings active-context
    -- label registers here so it updates after every confirmed loadout swap
    -- without polling. Subscribers fire with no arguments.
    RegisterLoadoutChangeCallback = RegisterLoadoutChangeCallback,
}
