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

---------------------------------------------------------------------------
-- CONSTANTS
---------------------------------------------------------------------------
local HUD_MIN_WIDTH_DEFAULT = Helpers.HUD_MIN_WIDTH_DEFAULT or 200
local ROW_GAP = 0

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

local function SaveCurrentSpecProfile()
    -- Use _previousSpecID, not GetCurrentSpecID(). By the time
    -- PLAYER_SPECIALIZATION_CHANGED fires the current spec is already
    -- the NEW spec — saving under GetCurrentSpecID() would store the
    -- outgoing spec's data under the incoming spec's key.
    local specID = _previousSpecID
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

    for _, key in ipairs(containerKeys) do
        local containerDB = GetTrackerSettings(key)
        if containerDB and containerDB.ownedSpells ~= nil then
            local ownedCount = type(containerDB.ownedSpells) == "table" and #containerDB.ownedSpells or 0
            local removedCount = 0
            if type(containerDB.removedSpells) == "table" then
                for _ in pairs(containerDB.removedSpells) do removedCount = removedCount + 1 end
            end
            local dormantCount = 0
            if type(containerDB.dormantSpells) == "table" then
                for _ in pairs(containerDB.dormantSpells) do dormantCount = dormantCount + 1 end
            end
            specData[key] = {
                ownedSpells = CopyTable(containerDB.ownedSpells),
                removedSpells = CopyTable(containerDB.removedSpells or {}),
                dormantSpells = CopyTable(containerDB.dormantSpells or {}),
            }
        end
    end

    db._specProfiles[specID] = specData
end

local function LoadOrSnapshotSpecProfile(specID)
    if not specID then
        return
    end

    local db = GetDB()
    if not db then
        return
    end

    local containerKeys = CDMContainers_API:GetAllContainerKeys()
    local savedProfile = db._specProfiles and db._specProfiles[specID]

    if savedProfile then
        -- Restore each container's ownedSpells, removedSpells, and dormantSpells from saved profile
        for _, key in ipairs(containerKeys) do
            local containerDB = GetTrackerSettings(key)
            if containerDB then
                local savedContainer = savedProfile[key]
                if savedContainer then
                    local ownedCount = type(savedContainer.ownedSpells) == "table" and #savedContainer.ownedSpells or 0
                    local dormantCount = 0
                    if type(savedContainer.dormantSpells) == "table" then
                        for _ in pairs(savedContainer.dormantSpells) do dormantCount = dormantCount + 1 end
                    end
                    containerDB.ownedSpells = CopyTable(savedContainer.ownedSpells)
                    containerDB.removedSpells = CopyTable(savedContainer.removedSpells)
                    containerDB.dormantSpells = CopyTable(savedContainer.dormantSpells or {})
                else
                end
            end
        end
    else
        -- No saved profile for this spec — fresh snapshot from Blizzard CDM
        if ns.CDMSpellData then
            for _, key in ipairs(containerKeys) do
                local containerDB = GetTrackerSettings(key)
                if containerDB then
                    -- Clear ownedSpells so SnapshotBlizzardCDM will re-snapshot
                    containerDB.ownedSpells = nil
                end
            end
            -- Force scan so snapshot has data
            ns.CDMSpellData:ForceScan()
            for _, key in ipairs(containerKeys) do
                ns.CDMSpellData:SnapshotBlizzardCDM(key)
                -- Log the result
                local cDB = GetTrackerSettings(key)
                local count = (cDB and type(cDB.ownedSpells) == "table") and #cDB.ownedSpells or 0
            end
        else
        end
    end

    -- Dormant spell check is handled by the caller (spec change handler)
    -- after this function returns, ensuring correct ordering.
end

-- Initialize the previous spec ID on first load.
-- Also detects spec/class changes across login sessions (e.g. switching
-- characters that share the same AceDB profile) and performs a spec
-- profile save/load so stale spells from another class never display.

-- Cross-session detection extracted so the 1.0s retry can re-run it.
-- Returns true if a spec mismatch was detected and profiles were swapped.
local function RunCrossSessionDetection(specID)
    local db = GetDB()
    if not db or not specID or specID == 0 then return false end

    local lastSpecID = db._lastSpecID
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
        LoadOrSnapshotSpecProfile(specID)
    end
    -- Persist the current spec ID for next session
    db._lastSpecID = specID
    return lastSpecID ~= nil and lastSpecID ~= specID
end

local function InitSpecTracking()
    _previousSpecID = GetCurrentSpecID()

    if _previousSpecID and _previousSpecID ~= 0 then
        RunCrossSessionDetection(_previousSpecID)
    else
        -- GetSpecializationInfo isn't ready yet (returns 0 or nil during early
        -- load). Retry after a short delay — and re-run cross-session detection
        -- so character/spec switches across sessions are still caught.
        C_Timer.After(1.0, function()
            if not _previousSpecID or _previousSpecID == 0 then
                _previousSpecID = GetCurrentSpecID()
            end
            if _previousSpecID and _previousSpecID ~= 0 then
                local detected = RunCrossSessionDetection(_previousSpecID)
                if detected then
                    -- Delayed detection: run dormant cleanup and refresh
                    if ns.CDMSpellData then
                        ns.CDMSpellData:CheckAllDormantSpells()
                        ns.CDMSpellData:ReconcileAllContainers()
                    end
                    if ns.CDMContainers and ns.CDMContainers.RefreshAll then
                        ns.CDMContainers.RefreshAll()
                    end
                end
            end
        end)
    end
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

local BUILTIN_CONTAINER_TYPES = {
    essential  = "cooldown",
    utility    = "cooldown",
    buff       = "aura",
    trackedBar = "auraBar",
}

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
    settings.ownedSpells = {}  -- custom containers start empty

    db.containers[key] = settings

    -- Also write to top-level ncdm[key] for backward compat with existing code paths
    db[key] = settings

    -- Create the container frame
    local frameName = "QUI_CDM_" .. key
    local frame = CreateContainer(frameName)
    containers[key] = frame
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

    -- Register settings provider for layout mode toolbar
    if self._settingsBuilders and self._settingsBuilders[containerType] then
        local settingsPanel = ns.QUI_LayoutMode_Settings
        if settingsPanel and settingsPanel.RegisterProvider then
            local elementKey = "cdmCustom_" .. key
            settingsPanel:RegisterProvider(elementKey, {
                build = self._settingsBuilders[containerType],
            })
        end
    end

    -- Invalidate caches
    if ns.InvalidateCDMFrameCache then ns.InvalidateCDMFrameCache() end

    -- Refresh layout mode movers if layout mode is active
    local um = ns.QUI_LayoutMode
    if um and um.RefreshMovers then
        um:RefreshMovers()
    end

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
            displayName = settings.name or containerKey,
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
    viewerState[frame] = {}
    return frame
end

-- Tracker key → frameAnchoring key mapping
local ANCHOR_KEY_MAP = {
    essential  = "cdmEssential",
    utility    = "cdmUtility",
    buff       = "buffIcon",
    trackedBar = "buffBar",
}

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
        local anchorKey = ANCHOR_KEY_MAP[trackerKey]
        if anchorKey then
            local profile = QUICore and QUICore.db and QUICore.db.profile
            local anchoringDB = profile and profile.frameAnchoring
            local settings = anchoringDB and anchoringDB[anchorKey]
            if settings and settings.enabled then
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

    -- If the centralized frame anchoring system has an enabled override for
    -- this CDM key with a screen parent, use its CENTER offsets directly.
    -- When anchored to another frame (e.g. "playerFrame"), the offsets are
    -- relative to that parent — let the anchoring system handle it later.
    local anchorKey = ANCHOR_KEY_MAP[trackerKey]
    if anchorKey then
        local profile = QUICore and QUICore.db and QUICore.db.profile
        local anchoringDB = profile and profile.frameAnchoring
        local settings = anchoringDB and anchoringDB[anchorKey]
        if settings and settings.enabled then
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

-- Blizzard viewer name lookup (used by Edit Mode and position save)
local VIEWER_NAMES_MAP = {
    essential  = "EssentialCooldownViewer",
    utility    = "UtilityCooldownViewer",
    buff       = "BuffIconCooldownViewer",
    trackedBar = "BuffBarCooldownViewer",
}

local function InitContainers()
    if containers.essential then return end -- already created

    containers.essential  = CreateContainer("QUI_EssentialContainer")
    containers.utility    = CreateContainer("QUI_UtilityContainer")
    containers.buff       = CreateContainer("QUI_BuffContainer")
    containers.trackedBar = CreateContainer("QUI_BuffBarContainer")

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

    -- Phase G: Create frames for any custom containers in the unified table
    if db and db.containers then
        for key, settings in pairs(db.containers) do
            if not BUILTIN_NAMES[key] and not containers[key] then
                local frameName = "QUI_CDM_" .. key
                containers[key] = CreateContainer(frameName)
                InitContainerPosition(containers[key], key)
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
        containers.buff = CreateContainer("QUI_BuffContainer")
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

---------------------------------------------------------------------------
-- CORE: Layout icons in a container
-- Ported from cdm_viewer.lua:1069-1554 with taint safety removed.
---------------------------------------------------------------------------
local function LayoutContainer(trackerKey)
    local container = containers[trackerKey]
    if not container then return end

    -- Never rebuild during combat — Blizzard CooldownFrames adopted onto our
    -- icons are updated natively.  Rebuilding mid-combat destroys the working
    -- layout (ClearPool) and may produce wrong positions.
    -- A full rebuild fires on PLAYER_REGEN_ENABLED via _G.QUI_RefreshNCDM.
    if InCombatLockdown() then
        return
    end

    -- Edit Mode: containers are visible with overlays but skip layout
    -- to avoid flicker while the user is looking at overlays.  Icons are
    -- already rendered.  RefreshAll() on Edit Mode exit rebuilds everything.
    -- Exception: _forceLayoutKey allows the Composer to force layout for
    -- a specific container during edit mode (so it resizes when spells change).
    if _editModeActive and trackerKey ~= _forceLayoutKey then return end

    local settings = GetTrackerSettings(trackerKey)
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
        -- Size from the underlying Blizzard viewer which auto-sizes from its children.
        local cw = Helpers.SafeValue(container:GetWidth(), 0)
        local ch = Helpers.SafeValue(container:GetHeight(), 0)
        if cw <= 1 or ch <= 1 then
            local blizzViewer = _G["BuffIconCooldownViewer"]
            if blizzViewer then
                local bw = Helpers.SafeValue(blizzViewer:GetWidth(), 0)
                local bh = Helpers.SafeValue(blizzViewer:GetHeight(), 0)
                if bw > 1 and bh > 1 then
                    container:SetSize(bw, bh)
                end
            end
        end

        -- Fingerprint: skip rebuild when the same buff spellIDs are active.
        -- Aura events fire on stack/duration changes too, but the icon set
        -- only changes when buffs are gained or lost.
        local spellData = ns.CDMSpellData and ns.CDMSpellData:GetSpellList("buff") or {}
        local parts = {}
        for i, entry in ipairs(spellData) do
            parts[i] = tostring(entry.spellID or 0)
        end
        local fingerprint = table.concat(parts, ",")

        local currentPool = ns.CDMIcons:GetIconPool("buff")
        if fingerprint == (buffFingerprint or "") and #currentPool > 0 then
            -- Same buff set -- skip destructive rebuild
            applying[trackerKey] = false
            return
        end
        buffFingerprint = fingerprint

        -- Build addon-owned icons (adopts Blizzard CooldownFrames)
        local allIcons = ns.CDMIcons:BuildIcons("buff", container)
        for _, icon in ipairs(allIcons) do
            icon:Show()
            -- During Edit Mode, new icons need mouse disabled so clicks
            -- reach Blizzard's .Selection in secure context.
            if Helpers.IsEditModeActive() then
                icon:EnableMouse(false)
                _disabledMouseFrames[icon] = true
            end
        end

        applying[trackerKey] = false

        -- Notify buffbar.lua to position + style icons immediately
        -- (no delay -- icons are parented and visible, ready for layout)
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

        if not skipIcon then
            iconsToLayout[#iconsToLayout + 1] = icon
            icon:Show()
            if editModeActive then
                icon:EnableMouse(false)
                _disabledMouseFrames[icon] = true
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
                if _G.QUI_ApplyUtilityAnchor then
                    _G.QUI_ApplyUtilityAnchor()
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
                local containerName = container:GetName()
                _G.QUI_UpdateViewerKeybinds(containerName)
            end
        end)
    end
end

---------------------------------------------------------------------------
-- REFRESH ALL
---------------------------------------------------------------------------
local function RefreshAll(forceSync)
    if not initialized then
        return
    end

    -- Defer to combat end — rebuilding destroys the current layout.
    -- A follow-up refresh on PLAYER_REGEN_ENABLED routes here and provides
    -- recovery after combat lockdown ends.
    if InCombatLockdown() then
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
        -- window on combat /reload where InCombatLockdown() returns false.
        -- No timer stagger needed — nothing to interleave on initial boot.
        LayoutContainer("essential")
        LayoutContainer("utility")
        if _G.QUI_ApplyUtilityAnchor then
            _G.QUI_ApplyUtilityAnchor()
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
    else
        refreshTimers[1] = C_Timer.NewTimer(0.01, function()
            refreshTimers[1] = nil
            LayoutContainer("essential")
        end)
        refreshTimers[2] = C_Timer.NewTimer(0.02, function()
            refreshTimers[2] = nil
            LayoutContainer("utility")
            if _G.QUI_ApplyUtilityAnchor then
                _G.QUI_ApplyUtilityAnchor()
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
        end)
    end
end

---------------------------------------------------------------------------
-- UTILITY ANCHOR: Position Utility container below Essential
---------------------------------------------------------------------------
local function ApplyUtilityAnchor()
    local db = GetDB()
    if not db or not db.utility then
        return
    end

    local utilSettings = db.utility
    local utilContainer = containers.utility
    if not utilContainer then
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
    _disabledMouseFrames[container] = true

    -- Disable mouse on all icons/bars in this pool
    local pool = ns.CDMIcons and ns.CDMIcons:GetIconPool(viewerType) or {}
    for _, icon in ipairs(pool) do
        icon:EnableMouse(false)
        _disabledMouseFrames[icon] = true
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
            _disabledMouseFrames[bar] = true
        end
    end
end

-- Restore mouse on all frames we disabled
local function RestoreMouseAfterEditMode()
    for frame in pairs(_disabledMouseFrames) do
        frame:EnableMouse(true)
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
                -- Refresh to pick up newly owned spell lists
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
    -- During a combat /reload this runs in the ADDON_LOADED safe window where
    -- InCombatLockdown() returns false, matching the group frames pattern.
    InitContainers()
    InitBuffContainer()

    -- Start the CDMIcons update ticker
    if ns.CDMIcons then
        ns.CDMIcons:StartUpdateTicker()
    end

    initialized = true
    NCDM.initialized = true

    -- Initialize spec tracking for save-on-switch
    InitSpecTracking()

    -- Invalidate visibility frame cache so hud_visibility picks up new containers
    if ns.InvalidateCDMFrameCache then
        ns.InvalidateCDMFrameCache()
    end

    -- Synchronous initial layout: leverages the ADDON_LOADED safe window on
    -- combat /reload (InCombatLockdown() returns false).  If Blizzard viewers
    -- aren't populated yet (first login), layout produces empty containers —
    -- the deferred re-layout below fills them once spell data arrives.
    RefreshAll(true)

    -- Synchronous post-layout: apply frame anchoring overrides NOW while
    -- still in the ADDON_LOADED safe window (InCombatLockdown=false).
    -- Containers anchored to other frames (e.g. utility→essential) need
    -- the anchoring system to set their position. This MUST be synchronous
    -- because deferred timers fire after the safe window closes.
    if _G.QUI_ApplyAllFrameAnchors then
        _G.QUI_ApplyAllFrameAnchors()
    end
    UpdateAllLockedBars()

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
    if _G.QUI_RefreshCDMVisibility then
        _G.QUI_RefreshCDMVisibility()
    end

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
        if event == "PLAYER_REGEN_ENABLED" then
            -- Combat end: full rebuild to pick up any spell data changes
            -- that were deferred while LayoutContainer was combat-gated.
            C_Timer.After(0.1, function()
                if not InCombatLockdown() then
                    RefreshAll()
                end
            end)
            return
        elseif event == "ADDON_LOADED" and arg1 == "Blizzard_CooldownManager" then
            -- Viewer just loaded -- grab it as buff container
            InitBuffContainer()
            if initialized then
                if ns.InvalidateCDMFrameCache then ns.InvalidateCDMFrameCache() end
                RefreshAll()
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            local isLogin, isReload = arg1, arg2
            if isReload and not InCombatLockdown() then
                -- Second layout pass during combat /reload safe window.
                -- Catches Blizzard viewer children that populated after
                -- the initial ADDON_LOADED scan.
                if ns.CDMSpellData then
                    ns.CDMSpellData:ForceScan()
                end
                RefreshAll(true)
                if _G.QUI_ApplyAllFrameAnchors then
                    _G.QUI_ApplyAllFrameAnchors()
                end
            elseif isLogin then
                -- Fresh login (or character switch): run dormant spell cleanup
                -- so cross-class/spec spells are removed before the first
                -- meaningful RefreshAll fires from the deferred timer.
                C_Timer.After(0.5, function()
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
            if newSpecID and newSpecID == _previousSpecID then
            else
                -- Save outgoing spec profile before loading the new one
                if _previousSpecID and _previousSpecID ~= 0 then
                    SaveCurrentSpecProfile()
                else
                end
                -- Invalidate caches immediately — old spec data is stale
                if ns.InvalidateCDMFrameCache then ns.InvalidateCDMFrameCache() end
                if ns.CDMSpellData and ns.CDMSpellData.InvalidateLearnedCache then
                    ns.CDMSpellData:InvalidateLearnedCache()
                end
                -- Load the new spec profile synchronously so the DB is never in a
                -- stale state. This eliminates the race where SPELLS_CHANGED fires
                -- before the profile swap and corrupts spell lists.
                LoadOrSnapshotSpecProfile(newSpecID)
                _previousSpecID = newSpecID
                -- Persist for cross-session detection
                local specDB = GetDB()
                if specDB then specDB._lastSpecID = newSpecID end
                -- Profile is now correct — SPELLS_CHANGED can safely run
                -- dormant/reconcile on the new spec's data.
                buffFingerprint = nil
                if InCombatLockdown() then
                    local regenFrame = CreateFrame("Frame")
                    regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
                    regenFrame:SetScript("OnEvent", function(self2)
                        self2:UnregisterAllEvents()
                        RefreshAll()
                    end)
                else
                    RefreshAll()
                end
            end
        elseif event == "CHALLENGE_MODE_START" then
            C_Timer.After(0.5, RefreshAll)
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
-- REGISTER ENGINE
---------------------------------------------------------------------------
if ns.CDMProvider then
    ns.CDMProvider:RegisterEngine("owned", ownedEngine)
end

---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- NAMESPACE EXPORT
---------------------------------------------------------------------------
ns.CDMContainers = {
    GetContainer = function(viewerType) return containers[viewerType] end,
    LayoutContainer = LayoutContainer,
    RefreshAll = RefreshAll,
    GetTrackedBarContainer = function() return containers.trackedBar end,
    -- Phase G: Container management API
    CreateContainer = function(name, containerType) return CDMContainers_API:CreateContainer(name, containerType) end,
    DeleteContainer = function(key) return CDMContainers_API:DeleteContainer(key) end,
    RenameContainer = function(key, name) return CDMContainers_API:RenameContainer(key, name) end,
    GetContainers = function() return CDMContainers_API:GetContainers() end,
    GetContainerSettings = function(key) return CDMContainers_API:GetContainerSettings(key) end,
    GetContainersByType = function(containerType) return CDMContainers_API:GetContainersByType(containerType) end,
    GetAllContainerKeys = function() return CDMContainers_API:GetAllContainerKeys() end,
}

---------------------------------------------------------------------------
-- UNLOCK MODE ELEMENT REGISTRATION
---------------------------------------------------------------------------
do
    local function RegisterLayoutModeElements()
        local um = ns.QUI_LayoutMode
        if not um then return end

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
            isOwned = false,
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
            })
        end

        -- Phase G: Register layout mode elements for custom containers
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

---------------------------------------------------------------------------
-- UNLOCK MODE SETTINGS PROVIDERS
---------------------------------------------------------------------------
do
    local function RegisterSettingsProviders()
        local settingsPanel = ns.QUI_LayoutMode_Settings
        if not settingsPanel then return end

        local GUI = QUI and QUI.GUI
        if not GUI then return end

        local C = GUI.Colors or {}
        local U = ns.QUI_LayoutMode_Utils
        local P = U and U.PlaceRow
        local PADDING = 0
        local FORM_ROW = U and U.FORM_ROW or 32

        local function GetNcdmDB()
            local core = Helpers.GetCore()
            return core and core.db and core.db.profile and core.db.profile.ncdm
        end

        local function RefreshNCDM()
            if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end
        end

        -- Force layout for a specific container during edit mode
        local function RefreshNCDMForKey(containerKey)
            if _G.QUI_ForceLayoutContainer then
                _G.QUI_ForceLayoutContainer(containerKey)
            else
                RefreshNCDM()
            end
        end

        local function RefreshBuff()
            if _G.QUI_RefreshBuffBar then _G.QUI_RefreshBuffBar() end
        end

        local function RefreshUtilityAnchor()
            RefreshNCDM()
            if _G.QUI_ApplyUtilityAnchor then _G.QUI_ApplyUtilityAnchor() end
        end

        local function GetProfileDB()
            local core = Helpers.GetCore()
            return core and core.db and core.db.profile
        end

        local function GetCharCustomEntries(trackerKey)
            local core = Helpers.GetCore()
            if core and core.db and core.db.char and core.db.char.ncdm
                and core.db.char.ncdm[trackerKey] then
                return core.db.char.ncdm[trackerKey].customEntries
            end
            return nil
        end

        local function GetViewerDB(trackerKey)
            local profile = GetProfileDB()
            if not profile or not profile.viewers then return nil end
            if trackerKey == "essential" then
                return profile.viewers.EssentialCooldownViewer
            else
                return profile.viewers.UtilityCooldownViewer
            end
        end

        local function RefreshSwipe()
            if _G.QUI_RefreshCooldownSwipe then _G.QUI_RefreshCooldownSwipe() end
        end
        local function RefreshGlows()
            if _G.QUI_RefreshCustomGlows then _G.QUI_RefreshCustomGlows() end
        end
        local function RefreshKeybinds()
            if _G.QUI_RefreshKeybinds then _G.QUI_RefreshKeybinds() end
        end
        local function RefreshRotationHelper()
            if _G.QUI_RefreshRotationHelper then _G.QUI_RefreshRotationHelper() end
        end

        local anchorOptions = {
            {value = "TOPLEFT", text = "Top Left"},
            {value = "TOP", text = "Top"},
            {value = "TOPRIGHT", text = "Top Right"},
            {value = "LEFT", text = "Left"},
            {value = "CENTER", text = "Center"},
            {value = "RIGHT", text = "Right"},
            {value = "BOTTOMLEFT", text = "Bottom Left"},
            {value = "BOTTOM", text = "Bottom"},
            {value = "BOTTOMRIGHT", text = "Bottom Right"},
        }

        local directionOptions = {
            {value = "HORIZONTAL", text = "Horizontal"},
            {value = "VERTICAL", text = "Vertical"},
        }

        local function CreateCollapsible(parent, title, contentHeight, buildFunc, sections, relayout)
            return U.CreateCollapsible(parent, title, contentHeight, buildFunc, sections, relayout)
        end

        local function BuildPositionCollapsible(content, frameKey, anchorOpts, sections, relayout)
            U.BuildPositionCollapsible(content, frameKey, anchorOpts, sections, relayout)
        end

        -----------------------------------------------------------------------
        -- Row settings builder (Essential / Utility rows 1-3)
        -----------------------------------------------------------------------
        local function BuildRowCollapsible(content, rowNum, rowData, refreshFn, sections, relayout)
            -- Ensure defaults
            Helpers.EnsureDefaults(rowData, {
                xOffset = 0,
                durationSize = 14,
                durationOffsetX = 0,
                durationOffsetY = 0,
                durationTextColor = {1, 1, 1, 1},
                durationAnchor = "CENTER",
                stackSize = 14,
                stackOffsetX = 0,
                stackOffsetY = 0,
                stackTextColor = {1, 1, 1, 1},
                stackAnchor = "BOTTOMRIGHT",
                opacity = 1.0,
            })

            -- 22 controls × FORM_ROW + shape tip 20px
            local rowHeight = 22 * FORM_ROW + 20 + 8

            CreateCollapsible(content, "Row " .. rowNum, rowHeight, function(body)
                local sy = -4

                sy = P(GUI:CreateFormSlider(body, "Icons in Row", 0, 20, 1, "iconCount", rowData, refreshFn), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Icon Size", 5, 80, 1, "iconSize", rowData, refreshFn), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Border Size", 0, 5, 1, "borderSize", rowData, refreshFn), body, sy)
                sy = P(GUI:CreateFormColorPicker(body, "Border Color", "borderColorTable", rowData, refreshFn), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Icon Zoom", 0, 0.2, 0.01, "zoom", rowData, refreshFn), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Padding", -20, 20, 1, "padding", rowData, refreshFn), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Row Y-Offset", -500, 500, 1, "yOffset", rowData, refreshFn), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Row X-Offset", -500, 500, 1, "xOffset", rowData, refreshFn), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Row Opacity", 0, 1.0, 0.05, "opacity", rowData, refreshFn), body, sy)
                sy = P(GUI:CreateFormCheckbox(body, "Hide Duration Text", "hideDurationText", rowData, refreshFn), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Duration Text Size", 8, 50, 1, "durationSize", rowData, refreshFn), body, sy)
                sy = P(GUI:CreateFormDropdown(body, "Anchor Duration To", anchorOptions, "durationAnchor", rowData, refreshFn), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Duration X-Offset", -80, 80, 1, "durationOffsetX", rowData, refreshFn), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Duration Y-Offset", -80, 80, 1, "durationOffsetY", rowData, refreshFn), body, sy)
                sy = P(GUI:CreateFormColorPicker(body, "Duration Text Color", "durationTextColor", rowData, refreshFn), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Stack Text Size", 8, 50, 1, "stackSize", rowData, refreshFn), body, sy)
                sy = P(GUI:CreateFormDropdown(body, "Anchor Stack To", anchorOptions, "stackAnchor", rowData, refreshFn), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Stack X-Offset", -80, 80, 1, "stackOffsetX", rowData, refreshFn), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Stack Y-Offset", -80, 80, 1, "stackOffsetY", rowData, refreshFn), body, sy)
                sy = P(GUI:CreateFormColorPicker(body, "Stack Text Color", "stackTextColor", rowData, refreshFn), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Icon Shape", 1.0, 2.0, 0.01, "aspectRatioCrop", rowData, refreshFn), body, sy)

                local shapeTip = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                shapeTip:SetPoint("TOPLEFT", 0, sy)
                shapeTip:SetPoint("RIGHT", body, "RIGHT", 0, 0)
                shapeTip:SetJustifyH("LEFT")
                shapeTip:SetText("Higher values = flatter icons.")
                shapeTip:SetTextColor(0.5, 0.5, 0.5, 1)
            end, sections, relayout)
        end

        -----------------------------------------------------------------------
        -- Essential / Utility settings builder
        -----------------------------------------------------------------------
        local function BuildTrackerSettings(content, key, width)
            local ncdm = GetNcdmDB()
            if not ncdm then return 80 end

            -- Resolve DB key from layout element key
            local dbKey
            if key == "cdmEssential" then
                dbKey = "essential"
            elseif key == "cdmUtility" then
                dbKey = "utility"
            elseif key:find("^cdmCustom_") then
                dbKey = key:sub(11)  -- strip "cdmCustom_" prefix
            else
                dbKey = "essential"
            end
            local isEssential = (dbKey == "essential")
            local tracker = ncdm[dbKey] or (ncdm.containers and ncdm.containers[dbKey])
            if not tracker then return 80 end

            -- Refresh function that forces layout during edit mode
            local function Refresh() RefreshNCDMForKey(dbKey) end

            local sections = {}
            local function relayout() U.StandardRelayout(content, sections) end

            -- Enable toggle (standalone row)
            local enableRow = CreateFrame("Frame", nil, content)
            enableRow:SetHeight(FORM_ROW)
            local enableCheck = GUI:CreateFormCheckbox(enableRow, "Enable", "enabled", tracker, Refresh)
            enableCheck:SetPoint("TOPLEFT", 0, 0)
            enableCheck:SetPoint("RIGHT", enableRow, "RIGHT", 0, 0)
            sections[#sections + 1] = enableRow

            -- Open Spell Manager button
            local composerRow = CreateFrame("Frame", nil, content)
            composerRow:SetHeight(FORM_ROW + 4)
            local composerBtn = CreateFrame("Button", nil, composerRow, "BackdropTemplate")
            composerBtn:SetSize(180, 26)
            composerBtn:SetPoint("TOPLEFT", 0, 0)
            composerBtn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
            composerBtn:SetBackdropColor(U.ACCENT_R * 0.25, U.ACCENT_G * 0.25, U.ACCENT_B * 0.25, 0.9)
            composerBtn:SetBackdropBorderColor(U.ACCENT_R, U.ACCENT_G, U.ACCENT_B, 0.8)
            local composerBtnText = composerBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            composerBtnText:SetPoint("CENTER")
            composerBtnText:SetText("Open Spell Manager")
            composerBtnText:SetTextColor(U.ACCENT_R, U.ACCENT_G, U.ACCENT_B, 1)
            composerBtn:SetScript("OnClick", function()
                if _G.QUI_OpenCDMComposer then
                    _G.QUI_OpenCDMComposer(dbKey)
                end
            end)
            composerBtn:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(U.ACCENT_R, U.ACCENT_G, U.ACCENT_B, 1)
                self:SetBackdropColor(U.ACCENT_R * 0.35, U.ACCENT_G * 0.35, U.ACCENT_B * 0.35, 0.9)
                if not _G.QUI_OpenCDMComposer then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText("Coming soon", 1, 1, 1)
                    GameTooltip:AddLine("The Spell Manager will be available in a future update.", 0.7, 0.7, 0.7, true)
                    GameTooltip:Show()
                end
            end)
            composerBtn:SetScript("OnLeave", function(self)
                self:SetBackdropBorderColor(U.ACCENT_R, U.ACCENT_G, U.ACCENT_B, 0.8)
                self:SetBackdropColor(U.ACCENT_R * 0.25, U.ACCENT_G * 0.25, U.ACCENT_B * 0.25, 0.9)
                GameTooltip:Hide()
            end)
            sections[#sections + 1] = composerRow

            -- General section
            local generalRows = 5 -- display mode, layout dir, clickable, desaturate, grey out
            if not isEssential then generalRows = generalRows + 2 end -- anchor below + gap

            CreateCollapsible(content, "General", generalRows * FORM_ROW + 8, function(body)
                local sy = -4

                local displayModeOptions = {
                    {value = "always", text = "Always"},
                    {value = "active", text = "Active Only"},
                    {value = "combat", text = "Combat Only"},
                }
                tracker.iconDisplayMode = tracker.iconDisplayMode or "always"
                local dmDD = GUI:CreateFormDropdown(body, "Display Mode", displayModeOptions, "iconDisplayMode", tracker, Refresh)
                sy = U.PlaceRow(dmDD, body, sy)

                tracker.layoutDirection = tracker.layoutDirection or "HORIZONTAL"
                local dirDD = GUI:CreateFormDropdown(body, "Layout Direction", directionOptions, "layoutDirection", tracker, Refresh)
                sy = U.PlaceRow(dirDD, body, sy)

                local clickCheck = GUI:CreateFormCheckbox(body, "Clickable Icons", "clickableIcons", tracker, Refresh)
                sy = U.PlaceRow(clickCheck, body, sy)

                if not isEssential then
                    local anchorCheck = GUI:CreateFormCheckbox(body, "Anchor Below Essential", "anchorBelowEssential", tracker, RefreshUtilityAnchor)
                    sy = U.PlaceRow(anchorCheck, body, sy)

                    local gapSlider = GUI:CreateFormSlider(body, "Anchor Gap", -200, 200, 1, "anchorGap", tracker, RefreshUtilityAnchor)
                    sy = U.PlaceRow(gapSlider, body, sy)
                end

                local desatCheck = GUI:CreateFormCheckbox(body, "Desaturate On Cooldown", "desaturateOnCooldown", tracker, Refresh)
                sy = U.PlaceRow(desatCheck, body, sy)

                local greyOutCheck = GUI:CreateFormCheckbox(body, "Grey Out Inactive Debuffs", "greyOutInactive", tracker, Refresh)
                sy = U.PlaceRow(greyOutCheck, body, sy)

                local greyOutBuffCheck = GUI:CreateFormCheckbox(body, "Grey Out Inactive Buffs", "greyOutInactiveBuffs", tracker, Refresh)
                U.PlaceRow(greyOutBuffCheck, body, sy)
            end, sections, relayout)

            -- Row sections
            for i = 1, 3 do
                local rowData = tracker["row" .. i]
                if rowData then
                    BuildRowCollapsible(content, i, rowData, Refresh, sections, relayout)
                end
            end

            ---------------------------------------------------------------
            -- Custom Entries collapsible
            ---------------------------------------------------------------
            do
                local charCustom = GetCharCustomEntries(dbKey)
                if charCustom then
                    local entries = charCustom.entries or {}
                    local initialHeight = 2 * FORM_ROW + 58 + FORM_ROW + (#entries * 30) + 8

                    local ceSection = CreateCollapsible(content, "Custom Entries", initialHeight, function() end, sections, relayout)
                    local ceBody = ceSection._body

                    local function rebuildCustomEntries()
                        -- Wipe body
                        for _, child in pairs({ceBody:GetChildren()}) do
                            child:Hide()
                            child:SetParent(nil)
                        end
                        for _, region in pairs({ceBody:GetRegions()}) do
                            if region.Hide then region:Hide() end
                            if region.SetParent then region:SetParent(nil) end
                        end

                        local cc = GetCharCustomEntries(dbKey)
                        if not cc then return end

                        local sy = -4

                        -- Enable checkbox
                        local ceEnable = GUI:CreateFormCheckbox(ceBody, "Enable Custom Entries", "enabled", cc, Refresh)
                        sy = U.PlaceRow(ceEnable, ceBody, sy)

                        -- Placement dropdown
                        local placementOpts = {
                            {value = "before", text = "Before Blizzard Icons"},
                            {value = "after", text = "After Blizzard Icons"},
                        }
                        local placementDD = GUI:CreateFormDropdown(ceBody, "Icon Placement", placementOpts, "placement", cc, Refresh)
                        sy = U.PlaceRow(placementDD, ceBody, sy)

                        -- Drop zone
                        local dropZone = CreateFrame("Button", nil, ceBody, "BackdropTemplate")
                        dropZone:SetHeight(50)
                        dropZone:SetPoint("TOPLEFT", 0, sy)
                        dropZone:SetPoint("RIGHT", ceBody, "RIGHT", 0, 0)
                        dropZone:SetBackdrop({
                            bgFile = "Interface\\Buttons\\WHITE8x8",
                            edgeFile = "Interface\\Buttons\\WHITE8x8",
                            edgeSize = 1,
                        })
                        dropZone:SetBackdropColor(0.08, 0.08, 0.1, 0.8)
                        dropZone:SetBackdropBorderColor(U.ACCENT_R, U.ACCENT_G, U.ACCENT_B, 0.5)

                        local dropLabel = dropZone:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        dropLabel:SetPoint("CENTER", 0, 0)
                        dropLabel:SetText("Drop Spells or Items Here")
                        dropLabel:SetTextColor(0.5, 0.5, 0.5, 1)

                        dropZone:RegisterForDrag("LeftButton")
                        dropZone:EnableMouse(true)

                        local function HandleDrop()
                            local cursorType, id1, id2, id3, id4 = GetCursorInfo()
                            if cursorType == "item" then
                                local itemID = id1
                                if itemID and ns.CustomCDM then
                                    ns.CustomCDM:AddEntry(dbKey, "item", itemID)
                                    ClearCursor()
                                    rebuildCustomEntries()
                                end
                            elseif cursorType == "spell" then
                                local spellID = id4
                                if not spellID and id1 then
                                    local spellBank = (id2 == "pet") and Enum.SpellBookSpellBank.Pet or Enum.SpellBookSpellBank.Player
                                    local spellBookInfo = C_SpellBook.GetSpellBookItemInfo(id1, spellBank)
                                    if spellBookInfo then spellID = spellBookInfo.spellID end
                                end
                                if spellID then
                                    local overrideID = C_Spell.GetOverrideSpell(spellID)
                                    if overrideID and overrideID ~= spellID then spellID = overrideID end
                                    if ns.CustomCDM then
                                        ns.CustomCDM:AddEntry(dbKey, "spell", spellID)
                                        ClearCursor()
                                        rebuildCustomEntries()
                                    end
                                end
                            end
                        end

                        dropZone:SetScript("OnReceiveDrag", HandleDrop)
                        dropZone:SetScript("OnMouseUp", function(self)
                            local cursorType = GetCursorInfo()
                            if cursorType == "item" or cursorType == "spell" then HandleDrop() end
                        end)
                        dropZone:SetScript("OnEnter", function(self)
                            local cursorType = GetCursorInfo()
                            if cursorType == "item" or cursorType == "spell" then
                                self:SetBackdropBorderColor(U.ACCENT_R, U.ACCENT_G, U.ACCENT_B, 1)
                                dropLabel:SetTextColor(U.ACCENT_R, U.ACCENT_G, U.ACCENT_B, 1)
                            end
                        end)
                        dropZone:SetScript("OnLeave", function(self)
                            self:SetBackdropBorderColor(U.ACCENT_R, U.ACCENT_G, U.ACCENT_B, 0.5)
                            dropLabel:SetTextColor(0.5, 0.5, 0.5, 1)
                        end)

                        sy = sy - 58

                        -- Trinket buttons
                        local trinketRow = CreateFrame("Frame", nil, ceBody)
                        trinketRow:SetHeight(26)
                        trinketRow:SetPoint("TOPLEFT", 0, sy)
                        trinketRow:SetPoint("RIGHT", ceBody, "RIGHT", 0, 0)

                        local t1Btn = CreateFrame("Button", nil, trinketRow, "BackdropTemplate")
                        t1Btn:SetSize(130, 22)
                        t1Btn:SetPoint("LEFT", 0, 0)
                        t1Btn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
                        t1Btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
                        t1Btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                        local t1Text = t1Btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        t1Text:SetPoint("CENTER")
                        t1Text:SetText("Add Trinket 1")
                        t1Text:SetTextColor(0.9, 0.9, 0.9, 1)
                        t1Btn:SetScript("OnClick", function()
                            if ns.CustomCDM then
                                ns.CustomCDM:AddEntry(dbKey, "trinket", 13)
                                rebuildCustomEntries()
                            end
                        end)
                        t1Btn:SetScript("OnEnter", function(self)
                            self:SetBackdropBorderColor(U.ACCENT_R, U.ACCENT_G, U.ACCENT_B, 1)
                        end)
                        t1Btn:SetScript("OnLeave", function(self)
                            self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                        end)

                        local t2Btn = CreateFrame("Button", nil, trinketRow, "BackdropTemplate")
                        t2Btn:SetSize(130, 22)
                        t2Btn:SetPoint("LEFT", t1Btn, "RIGHT", 6, 0)
                        t2Btn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
                        t2Btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
                        t2Btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                        local t2Text = t2Btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        t2Text:SetPoint("CENTER")
                        t2Text:SetText("Add Trinket 2")
                        t2Text:SetTextColor(0.9, 0.9, 0.9, 1)
                        t2Btn:SetScript("OnClick", function()
                            if ns.CustomCDM then
                                ns.CustomCDM:AddEntry(dbKey, "trinket", 14)
                                rebuildCustomEntries()
                            end
                        end)
                        t2Btn:SetScript("OnEnter", function(self)
                            self:SetBackdropBorderColor(U.ACCENT_R, U.ACCENT_G, U.ACCENT_B, 1)
                        end)
                        t2Btn:SetScript("OnLeave", function(self)
                            self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                        end)

                        sy = sy - FORM_ROW

                        -- Entry rows
                        local ceEntries = cc.entries or {}
                        for i, entry in ipairs(ceEntries) do
                            local row = CreateFrame("Frame", nil, ceBody, "BackdropTemplate")
                            row:SetHeight(28)
                            row:SetPoint("TOPLEFT", 0, sy)
                            row:SetPoint("RIGHT", ceBody, "RIGHT", 0, 0)
                            row:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
                            row:SetBackdropColor(0.12, 0.12, 0.15, 0.6)

                            -- Icon
                            local iconTex = row:CreateTexture(nil, "ARTWORK")
                            iconTex:SetSize(20, 20)
                            iconTex:SetPoint("LEFT", 4, 0)
                            local texPath = "Interface\\Icons\\INV_Misc_QuestionMark"
                            if entry.type == "spell" then
                                local info = C_Spell.GetSpellInfo(entry.id)
                                if info and info.iconID then texPath = info.iconID end
                            elseif entry.type == "item" then
                                local ic = C_Item.GetItemIconByID(entry.id)
                                if ic then texPath = ic end
                            elseif entry.type == "trinket" then
                                local itemID = GetInventoryItemID("player", entry.id)
                                if itemID then
                                    local ic = C_Item.GetItemIconByID(itemID)
                                    if ic then texPath = ic end
                                end
                            end
                            iconTex:SetTexture(texPath)
                            iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

                            -- Name
                            local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                            nameLabel:SetPoint("LEFT", iconTex, "RIGHT", 4, 0)
                            nameLabel:SetPoint("RIGHT", row, "RIGHT", -120, 0)
                            nameLabel:SetJustifyH("LEFT")
                            local entryName = ns.CustomCDM and ns.CustomCDM:GetEntryName(entry) or "Unknown"
                            nameLabel:SetText(entryName)
                            nameLabel:SetTextColor(0.9, 0.9, 0.9, 1)

                            -- Toggle
                            local toggleBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
                            toggleBtn:SetSize(28, 20)
                            toggleBtn:SetPoint("RIGHT", row, "RIGHT", -88, 0)
                            toggleBtn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
                            toggleBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
                            toggleBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                            local toggleText = toggleBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                            toggleText:SetPoint("CENTER")
                            toggleText:SetText(entry.enabled ~= false and "On" or "Off")
                            toggleText:SetTextColor(entry.enabled ~= false and 0.3 or 0.6, entry.enabled ~= false and 1 or 0.4, entry.enabled ~= false and 0.5 or 0.4, 1)
                            local entryIdx = i
                            toggleBtn:SetScript("OnClick", function()
                                if ns.CustomCDM then
                                    ns.CustomCDM:SetEntryEnabled(dbKey, entryIdx, not (entry.enabled ~= false))
                                    rebuildCustomEntries()
                                end
                            end)

                            -- Move up
                            local upBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
                            upBtn:SetSize(22, 20)
                            upBtn:SetPoint("RIGHT", row, "RIGHT", -62, 0)
                            upBtn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
                            upBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
                            upBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                            local upText = upBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                            upText:SetPoint("CENTER")
                            upText:SetText("^")
                            upText:SetTextColor(0.8, 0.8, 0.8, 1)
                            upBtn:SetScript("OnClick", function()
                                if ns.CustomCDM then
                                    ns.CustomCDM:MoveEntry(dbKey, entryIdx, -1)
                                    rebuildCustomEntries()
                                end
                            end)

                            -- Move down
                            local downBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
                            downBtn:SetSize(22, 20)
                            downBtn:SetPoint("RIGHT", row, "RIGHT", -36, 0)
                            downBtn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
                            downBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
                            downBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                            local downText = downBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                            downText:SetPoint("CENTER")
                            downText:SetText("v")
                            downText:SetTextColor(0.8, 0.8, 0.8, 1)
                            downBtn:SetScript("OnClick", function()
                                if ns.CustomCDM then
                                    ns.CustomCDM:MoveEntry(dbKey, entryIdx, 1)
                                    rebuildCustomEntries()
                                end
                            end)

                            -- Remove
                            local removeBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
                            removeBtn:SetSize(22, 20)
                            removeBtn:SetPoint("RIGHT", row, "RIGHT", -6, 0)
                            removeBtn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
                            removeBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
                            removeBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                            local removeText = removeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                            removeText:SetPoint("CENTER")
                            removeText:SetText("X")
                            removeText:SetTextColor(U.ACCENT_R, U.ACCENT_G, U.ACCENT_B, 0.8)
                            removeBtn:SetScript("OnClick", function()
                                if ns.CustomCDM then
                                    ns.CustomCDM:RemoveEntry(dbKey, entryIdx)
                                    rebuildCustomEntries()
                                end
                            end)

                            sy = sy - 30
                        end

                        if #ceEntries == 0 then
                            local noEntries = ceBody:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                            noEntries:SetPoint("TOPLEFT", 0, sy)
                            noEntries:SetPoint("RIGHT", ceBody, "RIGHT", 0, 0)
                            noEntries:SetJustifyH("LEFT")
                            noEntries:SetText("No custom entries. Drag spells/items above.")
                            noEntries:SetTextColor(0.5, 0.5, 0.5, 1)
                            sy = sy - 20
                        end

                        -- Update height
                        local newHeight = math.abs(sy) + 8
                        ceBody:SetHeight(newHeight)
                        ceSection._contentHeight = newHeight
                        if ceSection._expanded then
                            ceSection:SetHeight(U.HEADER_HEIGHT + newHeight)
                        end
                        relayout()
                    end

                    rebuildCustomEntries()
                end
            end

            ---------------------------------------------------------------
            -- Effects collapsible (Swipe, Overlay, Hide, Custom Glow)
            ---------------------------------------------------------------
            do
                local profile = GetProfileDB()
                if profile then
                    -- Initialize tables if needed
                    if not profile.cooldownSwipe then profile.cooldownSwipe = {} end
                    if not profile.cooldownEffects then profile.cooldownEffects = {} end
                    if not profile.customGlow then profile.customGlow = {} end

                    local swipeDB = profile.cooldownSwipe
                    local effectsDB = profile.cooldownEffects
                    local glowDB = profile.customGlow
                    local glowPrefix = isEssential and "essential" or "utility"

                    -- Count rows: swipe(3) + overlay(4) + hide(1) + glow header tip(1) + glow controls(9) = 18
                    local effectsHeight = 18 * FORM_ROW + 4 * 16 + 8  -- 4 section labels + padding

                    CreateCollapsible(content, "Effects", effectsHeight, function(body)
                        local sy = -4

                        -- Section: Cooldown Swipe
                        local swipeLabel = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        swipeLabel:SetPoint("TOPLEFT", 0, sy)
                        swipeLabel:SetText("COOLDOWN SWIPE")
                        swipeLabel:SetTextColor(U.ACCENT_R, U.ACCENT_G, U.ACCENT_B, 0.8)
                        sy = sy - 16

                        sy = U.PlaceRow(GUI:CreateFormCheckbox(body, "Radial Darkening", "showCooldownSwipe", swipeDB, RefreshSwipe), body, sy)
                        sy = U.PlaceRow(GUI:CreateFormCheckbox(body, "GCD Swipe", "showGCDSwipe", swipeDB, RefreshSwipe), body, sy)
                        sy = U.PlaceRow(GUI:CreateFormCheckbox(body, "Buff Swipe", "showBuffSwipe", swipeDB, RefreshSwipe), body, sy)
                        sy = U.PlaceRow(GUI:CreateFormCheckbox(body, "Recharge Edge", "showRechargeEdge", swipeDB, RefreshSwipe), body, sy)

                        -- Section: Overlay Color
                        local overlayLabel = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        overlayLabel:SetPoint("TOPLEFT", 0, sy)
                        overlayLabel:SetText("OVERLAY COLOR")
                        overlayLabel:SetTextColor(U.ACCENT_R, U.ACCENT_G, U.ACCENT_B, 0.8)
                        sy = sy - 16

                        local colorModeOptions = {
                            {value = "default", text = "Default (Blizzard)"},
                            {value = "class",   text = "Class Color"},
                            {value = "accent",  text = "UI Accent Color"},
                            {value = "custom",  text = "Custom Color"},
                        }

                        local overlayColorPicker
                        local overlayMode = GUI:CreateFormDropdown(body, "Buff Overlay Color", colorModeOptions, "overlayColorMode", swipeDB, function()
                            RefreshSwipe()
                            if overlayColorPicker then
                                overlayColorPicker:SetEnabled((swipeDB.overlayColorMode or "default") == "custom")
                            end
                        end)
                        sy = U.PlaceRow(overlayMode, body, sy)

                        overlayColorPicker = GUI:CreateFormColorPicker(body, "Overlay Custom Color", "overlayColor", swipeDB, RefreshSwipe)
                        overlayColorPicker:SetEnabled((swipeDB.overlayColorMode or "default") == "custom")
                        sy = U.PlaceRow(overlayColorPicker, body, sy)

                        local swipeColorPicker
                        local swipeMode = GUI:CreateFormDropdown(body, "Cooldown Swipe Color", colorModeOptions, "swipeColorMode", swipeDB, function()
                            RefreshSwipe()
                            if swipeColorPicker then
                                swipeColorPicker:SetEnabled((swipeDB.swipeColorMode or "default") == "custom")
                            end
                        end)
                        sy = U.PlaceRow(swipeMode, body, sy)

                        swipeColorPicker = GUI:CreateFormColorPicker(body, "Swipe Custom Color", "swipeColor", swipeDB, RefreshSwipe)
                        swipeColorPicker:SetEnabled((swipeDB.swipeColorMode or "default") == "custom")
                        sy = U.PlaceRow(swipeColorPicker, body, sy)

                        -- Section: Hide Cooldown Effects
                        local hideLabel = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        hideLabel:SetPoint("TOPLEFT", 0, sy)
                        hideLabel:SetText("HIDE COOLDOWN EFFECTS")
                        hideLabel:SetTextColor(U.ACCENT_R, U.ACCENT_G, U.ACCENT_B, 0.8)
                        sy = sy - 16

                        local hideKey = isEssential and "hideEssential" or "hideUtility"
                        local hideLabel2 = isEssential and "Hide on Essential Cooldowns" or "Hide on Utility Cooldowns"
                        sy = U.PlaceRow(GUI:CreateFormCheckbox(body, hideLabel2, hideKey, effectsDB, function()
                            if _G.QUI_RefreshCooldownEffects then _G.QUI_RefreshCooldownEffects() end
                        end), body, sy)

                        -- Section: Custom Glow
                        local glowLabel = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        glowLabel:SetPoint("TOPLEFT", 0, sy)
                        glowLabel:SetText("CUSTOM GLOW")
                        glowLabel:SetTextColor(U.ACCENT_R, U.ACCENT_G, U.ACCENT_B, 0.8)
                        sy = sy - 16

                        local enabledKey = glowPrefix .. "Enabled"
                        local glowTypeKey = glowPrefix .. "GlowType"
                        local colorKey = glowPrefix .. "Color"
                        local linesKey = glowPrefix .. "Lines"
                        local thicknessKey = glowPrefix .. "Thickness"
                        local scaleKey = glowPrefix .. "Scale"
                        local frequencyKey = glowPrefix .. "Frequency"
                        local xOffsetKey = glowPrefix .. "XOffset"
                        local yOffsetKey = glowPrefix .. "YOffset"

                        local glowWidgets = {}

                        local function UpdateGlowWidgetStates()
                            local glowType = glowDB[glowTypeKey] or "Pixel Glow"
                            local isPixel = glowType == "Pixel Glow"
                            local isAutocast = glowType == "Autocast Shine"
                            local isButton = glowType == "Button Glow"
                            if glowWidgets.lines then glowWidgets.lines:SetEnabled(isPixel or isAutocast) end
                            if glowWidgets.thickness then glowWidgets.thickness:SetEnabled(isPixel) end
                            if glowWidgets.scale then glowWidgets.scale:SetEnabled(isAutocast) end
                            if glowWidgets.xOffset then glowWidgets.xOffset:SetEnabled(not isButton) end
                            if glowWidgets.yOffset then glowWidgets.yOffset:SetEnabled(not isButton) end
                        end

                        sy = U.PlaceRow(GUI:CreateFormCheckbox(body, "Enable Custom Glow", enabledKey, glowDB, RefreshGlows), body, sy)

                        local glowTypeOptions = {
                            {value = "Pixel Glow", text = "Pixel Glow"},
                            {value = "Autocast Shine", text = "Autocast Shine"},
                            {value = "Button Glow", text = "Button Glow"},
                        }
                        sy = U.PlaceRow(GUI:CreateFormDropdown(body, "Glow Type", glowTypeOptions, glowTypeKey, glowDB, function()
                            RefreshGlows()
                            UpdateGlowWidgetStates()
                        end), body, sy)

                        sy = U.PlaceRow(GUI:CreateFormColorPicker(body, "Glow Color", colorKey, glowDB, RefreshGlows), body, sy)

                        glowWidgets.lines = GUI:CreateFormSlider(body, "Lines", 1, 30, 1, linesKey, glowDB, RefreshGlows)
                        sy = U.PlaceRow(glowWidgets.lines, body, sy)

                        glowWidgets.thickness = GUI:CreateFormSlider(body, "Thickness", 1, 10, 1, thicknessKey, glowDB, RefreshGlows)
                        sy = U.PlaceRow(glowWidgets.thickness, body, sy)

                        glowWidgets.scale = GUI:CreateFormSlider(body, "Shine Scale", 0.5, 3.0, 0.1, scaleKey, glowDB, RefreshGlows)
                        sy = U.PlaceRow(glowWidgets.scale, body, sy)

                        sy = U.PlaceRow(GUI:CreateFormSlider(body, "Animation Speed", 0.1, 2.0, 0.05, frequencyKey, glowDB, RefreshGlows), body, sy)

                        glowWidgets.xOffset = GUI:CreateFormSlider(body, "X Offset", -20, 20, 1, xOffsetKey, glowDB, RefreshGlows)
                        sy = U.PlaceRow(glowWidgets.xOffset, body, sy)

                        glowWidgets.yOffset = GUI:CreateFormSlider(body, "Y Offset", -20, 20, 1, yOffsetKey, glowDB, RefreshGlows)
                        sy = U.PlaceRow(glowWidgets.yOffset, body, sy)

                        UpdateGlowWidgetStates()

                        -- Section: Cast Highlighter
                        if not profile.cooldownHighlighter then profile.cooldownHighlighter = {} end
                        local hlDB = profile.cooldownHighlighter
                        local function RefreshHighlighter()
                            if _G.QUI_RefreshCooldownHighlighter then _G.QUI_RefreshCooldownHighlighter() end
                        end

                        local hlLabel = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        hlLabel:SetPoint("TOPLEFT", 0, sy)
                        hlLabel:SetText("CAST HIGHLIGHTER")
                        hlLabel:SetTextColor(U.ACCENT_R, U.ACCENT_G, U.ACCENT_B, 0.8)
                        sy = sy - 16

                        local hlGlowTypeOptions = {
                            {value = "Pixel Glow", text = "Pixel Glow"},
                            {value = "Autocast Shine", text = "Autocast Shine"},
                            {value = "Button Glow", text = "Button Glow"},
                            {value = "Flash", text = "Flash"},
                            {value = "Hammer", text = "Hammer"},
                            {value = "Proc Glow", text = "Proc Glow"},
                        }

                        sy = U.PlaceRow(GUI:CreateFormCheckbox(body, "Enable Cast Highlighter", "enabled", hlDB, RefreshHighlighter), body, sy)
                        sy = U.PlaceRow(GUI:CreateFormDropdown(body, "Glow Type", hlGlowTypeOptions, "glowType", hlDB, RefreshHighlighter), body, sy)
                        sy = U.PlaceRow(GUI:CreateFormColorPicker(body, "Highlight Color", "color", hlDB, RefreshHighlighter), body, sy)
                        sy = U.PlaceRow(GUI:CreateFormSlider(body, "Highlight Duration", 0.1, 2.0, 0.1, "duration", hlDB, RefreshHighlighter), body, sy)

                        -- Adjust actual height
                        local realHeight = math.abs(sy) + FORM_ROW + 8
                        body:SetHeight(realHeight)
                        local sec = body:GetParent()
                        if sec then
                            sec._contentHeight = realHeight
                            if sec._expanded then
                                sec:SetHeight(U.HEADER_HEIGHT + realHeight)
                            end
                        end
                    end, sections, relayout)
                end
            end

            ---------------------------------------------------------------
            -- Keybinds collapsible
            ---------------------------------------------------------------
            do
                local viewerDB = GetViewerDB(dbKey)
                if viewerDB then
                    local keybindAnchorOptions = {
                        {value = "TOPLEFT", text = "Top Left"},
                        {value = "TOPRIGHT", text = "Top Right"},
                        {value = "BOTTOMLEFT", text = "Bottom Left"},
                        {value = "BOTTOMRIGHT", text = "Bottom Right"},
                        {value = "CENTER", text = "Center"},
                    }

                    CreateCollapsible(content, "Keybinds", 6 * FORM_ROW + 8, function(body)
                        local sy = -4
                        sy = U.PlaceRow(GUI:CreateFormCheckbox(body, "Show Keybinds", "showKeybinds", viewerDB, RefreshKeybinds), body, sy)
                        sy = U.PlaceRow(GUI:CreateFormDropdown(body, "Keybind Anchor", keybindAnchorOptions, "keybindAnchor", viewerDB, RefreshKeybinds), body, sy)
                        sy = U.PlaceRow(GUI:CreateFormSlider(body, "Text Size", 6, 18, 1, "keybindTextSize", viewerDB, RefreshKeybinds), body, sy)
                        sy = U.PlaceRow(GUI:CreateFormColorPicker(body, "Text Color", "keybindTextColor", viewerDB, RefreshKeybinds), body, sy)
                        sy = U.PlaceRow(GUI:CreateFormSlider(body, "X Offset", -20, 20, 1, "keybindOffsetX", viewerDB, RefreshKeybinds), body, sy)
                        U.PlaceRow(GUI:CreateFormSlider(body, "Y Offset", -20, 20, 1, "keybindOffsetY", viewerDB, RefreshKeybinds), body, sy)
                    end, sections, relayout)
                end
            end

            ---------------------------------------------------------------
            -- Rotation Assist collapsible
            ---------------------------------------------------------------
            do
                local viewerDB = GetViewerDB(dbKey)
                if viewerDB then
                    CreateCollapsible(content, "Rotation Assist", 3 * FORM_ROW + 8, function(body)
                        local sy = -4
                        sy = U.PlaceRow(GUI:CreateFormCheckbox(body, "Show Rotation Helper", "showRotationHelper", viewerDB, RefreshRotationHelper), body, sy)
                        sy = U.PlaceRow(GUI:CreateFormColorPicker(body, "Border Color", "rotationHelperColor", viewerDB, RefreshRotationHelper), body, sy)
                        U.PlaceRow(GUI:CreateFormSlider(body, "Border Thickness", 1, 6, 1, "rotationHelperThickness", viewerDB, RefreshRotationHelper), body, sy)
                    end, sections, relayout)
                end
            end

            -- HUD Minimum Width (Essential only)
            if isEssential then
                local Helpers = ns.Helpers
                local HUD_MIN_WIDTH_DEFAULT = Helpers and Helpers.HUD_MIN_WIDTH_DEFAULT or 200
                local HUD_MIN_WIDTH_MIN = Helpers and Helpers.HUD_MIN_WIDTH_MIN or 100
                local HUD_MIN_WIDTH_MAX = Helpers and Helpers.HUD_MIN_WIDTH_MAX or 500
                local anchoringDB = nil
                local core = Helpers and Helpers.GetCore and Helpers.GetCore()
                if core and core.db and core.db.profile then
                    if type(core.db.profile.frameAnchoring) ~= "table" then
                        core.db.profile.frameAnchoring = {}
                    end
                    anchoringDB = core.db.profile.frameAnchoring
                end
                local hudMinWidth = anchoringDB and anchoringDB.hudMinWidth
                if not hudMinWidth and anchoringDB then
                    if Helpers and Helpers.MigrateHUDMinWidthSettings then
                        hudMinWidth = Helpers.MigrateHUDMinWidthSettings(anchoringDB)
                    else
                        hudMinWidth = { enabled = false, width = HUD_MIN_WIDTH_DEFAULT }
                        anchoringDB.hudMinWidth = hudMinWidth
                    end
                end
                if hudMinWidth then
                    CreateCollapsible(content, "HUD Min Width", 2 * FORM_ROW + 20, function(body)
                        local sy = -4
                        local function RefreshHUDWidth()
                            if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM()
                            elseif _G.QUI_UpdateAnchoredFrames then _G.QUI_UpdateAnchoredFrames() end
                        end
                        sy = U.PlaceRow(GUI:CreateFormToggle(body, "Enable Min Width", "enabled", hudMinWidth, RefreshHUDWidth), body, sy)
                        sy = U.PlaceRow(GUI:CreateFormSlider(body, "Minimum Width", HUD_MIN_WIDTH_MIN, HUD_MIN_WIDTH_MAX, 1, "width", hudMinWidth, RefreshHUDWidth), body, sy)
                        local note = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        note:SetPoint("TOPLEFT", 4, sy)
                        note:SetPoint("RIGHT", body, "RIGHT", -4, 0)
                        note:SetTextColor(0.6, 0.6, 0.6, 0.8)
                        note:SetText(("Prevents HUD collapsing when anchored to CDM. Default: %d"):format(HUD_MIN_WIDTH_DEFAULT))
                        note:SetJustifyH("LEFT")
                    end, sections, relayout)
                end
            end

            -- Position / Anchoring
            BuildPositionCollapsible(content, key, nil, sections, relayout)

            relayout()
            return content:GetHeight()
        end

        -----------------------------------------------------------------------
        -- Buff Icon settings builder
        -----------------------------------------------------------------------
        local function BuildBuffIconSettings(content, key, width)
            local ncdm = GetNcdmDB()
            if not ncdm then return 80 end

            -- Resolve DB key from layout element key
            local dbKey = "buff"
            if key and key:find("^cdmCustom_") then
                dbKey = key:sub(11)
            end
            local buffData = ncdm[dbKey] or (ncdm.containers and ncdm.containers[dbKey])
            if not buffData then return 80 end

            local function Refresh() RefreshNCDMForKey(dbKey) end
            local RefreshBuff = Refresh  -- shadow outer RefreshBuff with force-layout version

            local sections = {}
            local function relayout() U.StandardRelayout(content, sections) end

            -- Enable toggle (standalone row)
            local enableRow = CreateFrame("Frame", nil, content)
            enableRow:SetHeight(FORM_ROW)
            local enableCheck = GUI:CreateFormCheckbox(enableRow, "Enable", "enabled", buffData, Refresh)
            enableCheck:SetPoint("TOPLEFT", 0, 0)
            enableCheck:SetPoint("RIGHT", enableRow, "RIGHT", 0, 0)
            sections[#sections + 1] = enableRow

            -- Open Spell Manager button
            local composerRow = CreateFrame("Frame", nil, content)
            composerRow:SetHeight(FORM_ROW + 4)
            local composerBtn = CreateFrame("Button", nil, composerRow, "BackdropTemplate")
            composerBtn:SetSize(180, 26)
            composerBtn:SetPoint("TOPLEFT", 0, 0)
            composerBtn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
            composerBtn:SetBackdropColor(U.ACCENT_R * 0.25, U.ACCENT_G * 0.25, U.ACCENT_B * 0.25, 0.9)
            composerBtn:SetBackdropBorderColor(U.ACCENT_R, U.ACCENT_G, U.ACCENT_B, 0.8)
            local composerBtnText = composerBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            composerBtnText:SetPoint("CENTER")
            composerBtnText:SetText("Open Spell Manager")
            composerBtnText:SetTextColor(U.ACCENT_R, U.ACCENT_G, U.ACCENT_B, 1)
            composerBtn:SetScript("OnClick", function()
                if _G.QUI_OpenCDMComposer then
                    _G.QUI_OpenCDMComposer("buff")
                end
            end)
            composerBtn:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(U.ACCENT_R, U.ACCENT_G, U.ACCENT_B, 1)
                self:SetBackdropColor(U.ACCENT_R * 0.35, U.ACCENT_G * 0.35, U.ACCENT_B * 0.35, 0.9)
                if not _G.QUI_OpenCDMComposer then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText("Coming soon", 1, 1, 1)
                    GameTooltip:AddLine("The Spell Manager will be available in a future update.", 0.7, 0.7, 0.7, true)
                    GameTooltip:Show()
                end
            end)
            composerBtn:SetScript("OnLeave", function(self)
                self:SetBackdropBorderColor(U.ACCENT_R, U.ACCENT_G, U.ACCENT_B, 0.8)
                self:SetBackdropColor(U.ACCENT_R * 0.25, U.ACCENT_G * 0.25, U.ACCENT_B * 0.25, 0.9)
                GameTooltip:Hide()
            end)
            sections[#sections + 1] = composerRow

            -- Display Mode dropdown (standalone row)
            local displayRow = CreateFrame("Frame", nil, content)
            displayRow:SetHeight(FORM_ROW)
            local buffDisplayModeOptions = {
                {value = "always", text = "Always"},
                {value = "active", text = "Active Only"},
                {value = "combat", text = "Combat Only"},
            }
            buffData.iconDisplayMode = buffData.iconDisplayMode or "active"
            local buffDmDD = GUI:CreateFormDropdown(displayRow, "Display Mode", buffDisplayModeOptions, "iconDisplayMode", buffData, RefreshBuff)
            buffDmDD:SetPoint("TOPLEFT", 0, 0)
            buffDmDD:SetPoint("RIGHT", displayRow, "RIGHT", 0, 0)
            sections[#sections + 1] = displayRow

            -- Appearance section (6 rows)
            CreateCollapsible(content, "Appearance", 6 * FORM_ROW + 8, function(body)
                local sy = -4

                sy = P(GUI:CreateFormSlider(body, "Icon Size", 20, 80, 1, "iconSize", buffData, RefreshBuff), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Border Size", 0, 8, 1, "borderSize", buffData, RefreshBuff), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Icon Zoom", 0, 0.2, 0.01, "zoom", buffData, RefreshBuff), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Icon Padding", -20, 20, 1, "padding", buffData, RefreshBuff), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Opacity", 0, 1.0, 0.05, "opacity", buffData, RefreshBuff), body, sy)
                P(GUI:CreateFormSlider(body, "Icon Shape", 1.0, 2.0, 0.01, "aspectRatioCrop", buffData, RefreshBuff), body, sy)
            end, sections, relayout)

            -- Growth & Text section (9 rows)
            CreateCollapsible(content, "Growth & Text", 9 * FORM_ROW + 8, function(body)
                local sy = -4

                sy = P(GUI:CreateFormDropdown(body, "Growth Direction", {
                    {value = "CENTERED_HORIZONTAL", text = "Centered"},
                    {value = "UP", text = "Grow Up"},
                    {value = "DOWN", text = "Grow Down"},
                }, "growthDirection", buffData, RefreshBuff), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Duration Size", 8, 50, 1, "durationSize", buffData, RefreshBuff), body, sy)
                sy = P(GUI:CreateFormDropdown(body, "Duration Anchor", anchorOptions, "durationAnchor", buffData, RefreshBuff), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Duration X Offset", -20, 20, 1, "durationOffsetX", buffData, RefreshBuff), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Duration Y Offset", -20, 20, 1, "durationOffsetY", buffData, RefreshBuff), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Stack Size", 8, 50, 1, "stackSize", buffData, RefreshBuff), body, sy)
                sy = P(GUI:CreateFormDropdown(body, "Stack Anchor", anchorOptions, "stackAnchor", buffData, RefreshBuff), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Stack X Offset", -20, 20, 1, "stackOffsetX", buffData, RefreshBuff), body, sy)
                P(GUI:CreateFormSlider(body, "Stack Y Offset", -20, 20, 1, "stackOffsetY", buffData, RefreshBuff), body, sy)
            end, sections, relayout)

            -- Position / Anchoring
            BuildPositionCollapsible(content, key, nil, sections, relayout)

            relayout()
            return content:GetHeight()
        end

        -----------------------------------------------------------------------
        -- Buff Bar (Tracked Bar) settings builder
        -----------------------------------------------------------------------
        local function BuildBuffBarSettings(content, key, width)
            local ncdm = GetNcdmDB()
            if not ncdm then return 80 end

            -- Resolve DB key from layout element key
            local dbKey = "trackedBar"
            if key and key:find("^cdmCustom_") then
                dbKey = key:sub(11)
            end
            local trackedData = ncdm[dbKey] or (ncdm.containers and ncdm.containers[dbKey])
            if not trackedData then return 80 end

            local function Refresh() RefreshNCDMForKey(dbKey) end
            local RefreshBuff = Refresh  -- shadow outer RefreshBuff with force-layout version

            local sections = {}
            local function relayout() U.StandardRelayout(content, sections) end

            -- Enable toggle (standalone row)
            local enableRow = CreateFrame("Frame", nil, content)
            enableRow:SetHeight(FORM_ROW)
            local enableCheck = GUI:CreateFormCheckbox(enableRow, "Enable", "enabled", trackedData, RefreshBuff)
            enableCheck:SetPoint("TOPLEFT", 0, 0)
            enableCheck:SetPoint("RIGHT", enableRow, "RIGHT", 0, 0)
            sections[#sections + 1] = enableRow

            -- Open Spell Manager button
            local composerRow = CreateFrame("Frame", nil, content)
            composerRow:SetHeight(FORM_ROW + 4)
            local composerBtn = CreateFrame("Button", nil, composerRow, "BackdropTemplate")
            composerBtn:SetSize(180, 26)
            composerBtn:SetPoint("TOPLEFT", 0, 0)
            composerBtn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
            composerBtn:SetBackdropColor(U.ACCENT_R * 0.25, U.ACCENT_G * 0.25, U.ACCENT_B * 0.25, 0.9)
            composerBtn:SetBackdropBorderColor(U.ACCENT_R, U.ACCENT_G, U.ACCENT_B, 0.8)
            local composerBtnText = composerBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            composerBtnText:SetPoint("CENTER")
            composerBtnText:SetText("Open Spell Manager")
            composerBtnText:SetTextColor(U.ACCENT_R, U.ACCENT_G, U.ACCENT_B, 1)
            composerBtn:SetScript("OnClick", function()
                if _G.QUI_OpenCDMComposer then
                    _G.QUI_OpenCDMComposer("trackedBar")
                end
            end)
            composerBtn:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(U.ACCENT_R, U.ACCENT_G, U.ACCENT_B, 1)
                self:SetBackdropColor(U.ACCENT_R * 0.35, U.ACCENT_G * 0.35, U.ACCENT_B * 0.35, 0.9)
                if not _G.QUI_OpenCDMComposer then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText("Coming soon", 1, 1, 1)
                    GameTooltip:AddLine("The Spell Manager will be available in a future update.", 0.7, 0.7, 0.7, true)
                    GameTooltip:Show()
                end
            end)
            composerBtn:SetScript("OnLeave", function(self)
                self:SetBackdropBorderColor(U.ACCENT_R, U.ACCENT_G, U.ACCENT_B, 0.8)
                self:SetBackdropColor(U.ACCENT_R * 0.25, U.ACCENT_G * 0.25, U.ACCENT_B * 0.25, 0.9)
                GameTooltip:Hide()
            end)
            sections[#sections + 1] = composerRow

            -- General section (3 rows — +1 for display mode)
            CreateCollapsible(content, "General", 3 * FORM_ROW + 8, function(body)
                local sy = -4

                local barDisplayModeOptions = {
                    {value = "always", text = "Always"},
                    {value = "active", text = "Active Only"},
                    {value = "combat", text = "Combat Only"},
                }
                trackedData.iconDisplayMode = trackedData.iconDisplayMode or "active"
                sy = P(GUI:CreateFormDropdown(body, "Display Mode", barDisplayModeOptions, "iconDisplayMode", trackedData, RefreshBuff), body, sy)
                sy = P(GUI:CreateFormCheckbox(body, "Hide Icon", "hideIcon", trackedData, RefreshBuff), body, sy)
                P(GUI:CreateFormCheckbox(body, "Hide Text", "hideText", trackedData, RefreshBuff), body, sy)
            end, sections, relayout)

            -- Inactive Behavior section (4 rows + tip)
            CreateCollapsible(content, "Inactive Behavior", 4 * FORM_ROW + 20 + 8, function(body)
                local sy = -4

                local inactiveAlphaSlider, desatCheck, reserveCheck

                local function updateInactive()
                    local mode = trackedData.inactiveMode or "hide"
                    inactiveAlphaSlider:SetAlpha(mode == "fade" and 1.0 or 0.4)
                    desatCheck:SetAlpha(mode ~= "always" and 1.0 or 0.4)
                    reserveCheck:SetAlpha(mode == "hide" and 1.0 or 0.4)
                end

                local inactiveModeDD = GUI:CreateFormDropdown(body, "Inactive Buffs", {
                    {value = "always", text = "Always Show"},
                    {value = "fade", text = "Fade When Inactive"},
                    {value = "hide", text = "Hide When Inactive"},
                }, "inactiveMode", trackedData, function()
                    RefreshBuff()
                    updateInactive()
                end)
                sy = P(inactiveModeDD, body, sy)

                inactiveAlphaSlider = GUI:CreateFormSlider(body, "Inactive Alpha", 0, 1, 0.05, "inactiveAlpha", trackedData, RefreshBuff)
                sy = P(inactiveAlphaSlider, body, sy)

                desatCheck = GUI:CreateFormCheckbox(body, "Desaturate Inactive", "desaturateInactive", trackedData, RefreshBuff)
                sy = P(desatCheck, body, sy)

                reserveCheck = GUI:CreateFormCheckbox(body, "Reserve Slot When Inactive", "reserveSlotWhenInactive", trackedData, RefreshBuff)
                sy = P(reserveCheck, body, sy)

                local tip = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                tip:SetPoint("TOPLEFT", 0, sy)
                tip:SetPoint("RIGHT", body, "RIGHT", 0, 0)
                tip:SetJustifyH("LEFT")
                tip:SetText("Reserve Slot only applies in Hide mode.")
                tip:SetTextColor(0.5, 0.5, 0.5, 1)

                updateInactive()
            end, sections, relayout)

            -- Dimensions & Appearance section (10 rows)
            CreateCollapsible(content, "Dimensions & Appearance", 10 * FORM_ROW + 8, function(body)
                local sy = -4

                sy = P(GUI:CreateFormSlider(body, "Bar Height", 2, 48, 1, "barHeight", trackedData, RefreshBuff), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Bar Width", 100, 400, 1, "barWidth", trackedData, RefreshBuff), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Border Size", 0, 4, 1, "borderSize", trackedData, RefreshBuff), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Bar Spacing", 0, 20, 1, "spacing", trackedData, RefreshBuff), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Text Size", 8, 24, 1, "textSize", trackedData, RefreshBuff), body, sy)

                -- Texture dropdown
                local textureList = {}
                if LSM then
                    local textures = LSM:HashTable("statusbar")
                    for name in pairs(textures) do
                        table.insert(textureList, {value = name, text = name})
                    end
                    table.sort(textureList, function(a, b) return a.text < b.text end)
                end
                if #textureList > 0 then
                    sy = P(GUI:CreateFormDropdown(body, "Bar Texture", textureList, "texture", trackedData, RefreshBuff), body, sy)
                end

                sy = P(GUI:CreateFormCheckbox(body, "Auto Width From Anchor", "autoWidth", trackedData, RefreshBuff), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Auto Width Adjust", -20, 20, 1, "autoWidthOffset", trackedData, RefreshBuff), body, sy)
                sy = P(GUI:CreateFormDropdown(body, "Stack Direction", {
                    {value = true, text = "Up / Right"},
                    {value = false, text = "Down / Left"},
                }, "growUp", trackedData, RefreshBuff), body, sy)
                P(GUI:CreateFormSlider(body, "Stack X Offset", -20, 20, 1, "stackOffsetX", trackedData, RefreshBuff), body, sy)
            end, sections, relayout)

            -- Color section (5 rows)
            CreateCollapsible(content, "Colors", 5 * FORM_ROW + 8, function(body)
                local sy = -4

                sy = P(GUI:CreateFormCheckbox(body, "Use Class Color", "useClassColor", trackedData, RefreshBuff), body, sy)
                sy = P(GUI:CreateFormColorPicker(body, "Bar Color (Fallback)", "barColor", trackedData, RefreshBuff), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Bar Opacity", 0, 1, 0.05, "barOpacity", trackedData, RefreshBuff), body, sy)
                sy = P(GUI:CreateFormColorPicker(body, "Background Color", "bgColor", trackedData, RefreshBuff), body, sy)
                P(GUI:CreateFormSlider(body, "Background Opacity", 0, 1, 0.1, "bgOpacity", trackedData, RefreshBuff), body, sy)
            end, sections, relayout)

            -- Orientation section (5 rows + tips)
            CreateCollapsible(content, "Orientation", 5 * FORM_ROW + 60 + 8, function(body)
                local sy = -4

                local fillDD, iconPosDD, showTextCheck

                local function updateVertical()
                    local isV = trackedData.orientation == "vertical"
                    local alpha = isV and 1.0 or 0.4
                    fillDD:SetAlpha(alpha)
                    iconPosDD:SetAlpha(alpha)
                    showTextCheck:SetAlpha(alpha)
                end

                sy = P(GUI:CreateFormDropdown(body, "Bar Orientation", {
                    {value = "horizontal", text = "Horizontal"},
                    {value = "vertical", text = "Vertical"},
                }, "orientation", trackedData, function()
                    RefreshBuff()
                    updateVertical()
                end), body, sy)

                local stackTip = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                stackTip:SetPoint("TOPLEFT", 0, sy)
                stackTip:SetPoint("RIGHT", body, "RIGHT", 0, 0)
                stackTip:SetJustifyH("LEFT")
                stackTip:SetText("Changing orientation may require a UI reload.")
                stackTip:SetTextColor(0.5, 0.5, 0.5, 1)
                sy = sy - 20

                fillDD = GUI:CreateFormDropdown(body, "Fill Direction", {
                    {value = "up", text = "Fill Up"},
                    {value = "down", text = "Fill Down"},
                }, "fillDirection", trackedData, RefreshBuff)
                sy = P(fillDD, body, sy)

                iconPosDD = GUI:CreateFormDropdown(body, "Icon Position", {
                    {value = "top", text = "Top"},
                    {value = "bottom", text = "Bottom"},
                }, "iconPosition", trackedData, RefreshBuff)
                sy = P(iconPosDD, body, sy)

                showTextCheck = GUI:CreateFormCheckbox(body, "Show Text (Vertical)", "showTextOnVertical", trackedData, RefreshBuff)
                sy = P(showTextCheck, body, sy)

                local textTip = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                textTip:SetPoint("TOPLEFT", 0, sy)
                textTip:SetPoint("RIGHT", body, "RIGHT", 0, 0)
                textTip:SetJustifyH("LEFT")
                textTip:SetText("Vertical-only settings are dimmed when horizontal.")
                textTip:SetTextColor(0.5, 0.5, 0.5, 1)
                sy = sy - 20

                -- Fill direction tip
                local fillTip = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                fillTip:SetPoint("TOPLEFT", 0, sy)
                fillTip:SetPoint("RIGHT", body, "RIGHT", 0, 0)
                fillTip:SetJustifyH("LEFT")
                fillTip:SetText("Enable text for bars 48+ pixels wide.")
                fillTip:SetTextColor(0.5, 0.5, 0.5, 1)

                updateVertical()
            end, sections, relayout)

            -- Position / Anchoring
            BuildPositionCollapsible(content, key, nil, sections, relayout)

            relayout()
            return content:GetHeight()
        end

        -----------------------------------------------------------------------
        -- Register all providers
        -----------------------------------------------------------------------
        settingsPanel:RegisterProvider({"cdmEssential", "cdmUtility"}, {
            build = BuildTrackerSettings,
        })

        settingsPanel:RegisterProvider("buffIcon", {
            build = BuildBuffIconSettings,
        })

        settingsPanel:RegisterProvider("buffBar", {
            build = BuildBuffBarSettings,
        })

        -- Register providers for any existing custom containers
        local allKeys = CDMContainers_API:GetAllContainerKeys()
        for _, cKey in ipairs(allKeys) do
            if not BUILTIN_NAMES[cKey] then
                local cSettings = GetTrackerSettings(cKey)
                if cSettings then
                    local elementKey = "cdmCustom_" .. cKey
                    local ct = cSettings.containerType
                    if ct == "cooldown" then
                        settingsPanel:RegisterProvider(elementKey, { build = BuildTrackerSettings })
                    elseif ct == "aura" then
                        settingsPanel:RegisterProvider(elementKey, { build = BuildBuffIconSettings })
                    elseif ct == "auraBar" then
                        settingsPanel:RegisterProvider(elementKey, { build = BuildBuffBarSettings })
                    end
                end
            end
        end

        -- Expose build functions for dynamic registration from CreateContainer
        CDMContainers_API._settingsBuilders = {
            cooldown = BuildTrackerSettings,
            aura     = BuildBuffIconSettings,
            auraBar  = BuildBuffBarSettings,
        }
    end

    C_Timer.After(3, RegisterSettingsProviders)
end

