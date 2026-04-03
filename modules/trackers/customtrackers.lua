--[[
    QUI Custom Trackers
    User-configurable icon bars for tracking spells, items, trinkets, consumables
    Drag-and-drop spell/item input
]]

local ADDON_NAME, ns = ...
local QUI = QUI  -- Use global addon table, not ns.Addon (which is QUICore)
local LSM = ns.LSM
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)  -- For active state glow
local Helpers = ns.Helpers
local IsSecretValue = Helpers.IsSecretValue
local SafeValue = Helpers.SafeValue
local GetDB = Helpers.CreateDBGetter("customTrackers")

local GetCore = ns.Helpers.GetCore

-- Performance: cache frequently-called WoW API globals as locals
local type = type
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local UnitAffectingCombat = UnitAffectingCombat
local math_min = math.min
local math_max = math.max
local table_insert = table.insert
local table_remove = table.remove
local wipe = wipe
local CopyTable = CopyTable
local pairs = pairs
local ipairs = ipairs
local pcall = pcall
local CreateFrame = CreateFrame

---------------------------------------------------------------------------
-- MODULE NAMESPACE
---------------------------------------------------------------------------
local CustomTrackers = {}
CustomTrackers.activeBars = {}   -- Runtime bar frames indexed by barID
CustomTrackers.infoCache = {}    -- Cached spell/item info

---------------------------------------------------------------------------
-- DETECTOR FRAME POOL
-- Avoids repeated CreateFrame calls when the mouseover detector is torn
-- down and rebuilt on settings changes / PLAYER_ENTERING_WORLD.
---------------------------------------------------------------------------
local _detectorPool = {}

local function AcquireDetector()
    local f = table_remove(_detectorPool)
    if not f then
        f = CreateFrame("Frame")
    end
    f:Show()
    return f
end

local function ReleaseDetector(f)
    f:Hide()
    f:SetScript("OnEvent", nil)
    f:SetScript("OnUpdate", nil)
    f:UnregisterAllEvents()
    table_insert(_detectorPool, f)
end

---------------------------------------------------------------------------
-- CONSTANTS
---------------------------------------------------------------------------
local ASPECT_RATIOS = {
    square = { w = 1, h = 1 },
    flat = { w = 4, h = 3 },
}

-- Migrate old 'shape' setting to 'aspectRatioCrop' for custom tracker bars
local function MigrateBarAspect(config)
    if config and config.aspectRatioCrop == nil and config.shape then
        if config.shape == "flat" then
            config.aspectRatioCrop = 1.33  -- 4:3 aspect ratio
        else
            config.aspectRatioCrop = 1.0   -- square
        end
    end
    return config.aspectRatioCrop or 1.0
end

local BASE_CROP = 0.08  -- Standard WoW icon crop

-- Performance: reusable scratch table for LayoutVisibleIcons (avoids per-call allocation)
local _visibleIconsScratch = {}

-- Forward declaration: shared by startup registration and dynamic tracker creation
local RegisterTrackerLayoutElement

-- Forward declaration: tracks whether active state events are needed
-- (set by UpdateEventRegistrations, checked by aura dispatcher subscription)
local _activeStateEventsRegistered = false

-- Performance: frame-show coalescing for event-driven DoUpdate.
-- Show() on an already-shown frame is a no-op, so rapid events within
-- the same render frame are automatically batched into a single OnUpdate.
local _ctCoalesceFrame = CreateFrame("Frame")
_ctCoalesceFrame:Hide()
_ctCoalesceFrame:SetScript("OnUpdate", function(self)
    self:Hide()
    for _, bar in pairs(CustomTrackers.activeBars) do
        if bar and bar:IsShown() and bar.DoUpdate then
            bar.DoUpdate()
        end
    end
end)

-- Spellcast event throttle: prevents redundant DoUpdate scans from rapid
-- UNIT_SPELLCAST_* events within the same GCD window.
local _lastEventUpdate = 0
local _eventUpdateThrottle = 0.1
local _eventUpdatePending = false

-- Separate coalescing frame for UNIT_AURA (only updates bars with active state)
local _ctAuraCoalesceFrame = CreateFrame("Frame")
_ctAuraCoalesceFrame:Hide()
_ctAuraCoalesceFrame:SetScript("OnUpdate", function(self)
    self:Hide()
    for _, bar in pairs(CustomTrackers.activeBars) do
        if bar and bar:IsShown() and bar.DoUpdate and bar.config and bar.config.showActiveState ~= false then
            bar.DoUpdate()
        end
    end
end)

-- Subscribe to centralized aura dispatcher (player only).
-- Checks _activeStateEventsRegistered so it only does work when needed.
if ns.AuraEvents then
    ns.AuraEvents:Subscribe("player", function(unit, updateInfo)
        if _activeStateEventsRegistered then
            _ctAuraCoalesceFrame:Show()
        end
    end)
end

-- Performance: hoisted pcall wrapper functions (avoids anonymous closure allocation per call)
local function SafeSetCooldown(cd, start, dur)
    if IsSecretValue and (IsSecretValue(start) or IsSecretValue(dur)) then return end
    cd:SetCooldown(start, dur)
end
local function SafeSetCooldownFromDurationObject(cd, durObj)
    if not cd or not durObj or not cd.SetCooldownFromDurationObject then return false end
    local ok = pcall(cd.SetCooldownFromDurationObject, cd, durObj)
    return ok and true or false
end
local function SafeSetReverse(cd, val) cd:SetReverse(val) end
local function SafeSetSwipeColor(cd, r, g, b, a) cd:SetSwipeColor(r, g, b, a) end
local function SafeSetDrawSwipe(cd, val) cd:SetDrawSwipe(val) end
local function SafeSetDrawEdge(cd, val) cd:SetDrawEdge(val) end
local function SafeCheckDuration(dur) return dur and dur > 0 and dur <= 1.5 end
local function SafeCheckCooldownActive(start, dur) return start and start > 0 and dur and dur > 0 end
local function SafeCheckCharges(count, maxCharges) return count < maxCharges end

-- Housing instance types - excluded from "Show in Instance" detection
local HOUSING_INSTANCE_TYPES = {
    ["neighborhood"] = true,  -- Founder's Point, Razorwind Shores
    ["interior"] = true,      -- Inside player houses
}

-- Helper: Check if player is in an instance (excludes housing zones)
local function IsPlayerInInstance()
    local _, instanceType = GetInstanceInfo()
    if instanceType == "none" or instanceType == nil then
        return false
    end
    if HOUSING_INSTANCE_TYPES[instanceType] then
        return false
    end
    return true
end

---------------------------------------------------------------------------
-- POSITIONING SYSTEM (edge-anchored based on growth direction)
---------------------------------------------------------------------------
local function PositionBar(bar)
    if not bar or not bar.config then return end

    -- Skip if anchoring system has overridden this frame
    if bar.barID and _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("customTracker:" .. bar.barID) then return end

    local config = bar.config

    -- Migration: if bar has old position format, convert to offsetX/offsetY
    if config.position and not config.offsetX then
        config.offsetX = config.position[3] or 0
        config.offsetY = config.position[4] or -300
    end

    bar:ClearAllPoints()

    -- LOCKED TO PLAYER: reparent and use relative positioning
    if config.lockedToPlayer then
        local playerFrame = _G["QUI_Player"]

        if not playerFrame then
            local findPlayer = Helpers.FindAnchorFrame("player")
            if findPlayer then playerFrame = findPlayer end
        end

        if playerFrame then
            bar:SetParent(playerFrame)
            bar:SetFrameLevel(playerFrame:GetFrameLevel() + 10)
            local lockPos = config.lockPosition or "bottomcenter"
            local borderSize = config.borderSize or 2
            -- User fine-tuning offsets (added to lock position)
            local userOffsetX = config.offsetX or 0
            local userOffsetY = config.offsetY or 0

            -- Position at corner (bar edge touches frame edge + border gap + user offset)
            if lockPos == "topleft" then
                bar:SetPoint("BOTTOMLEFT", playerFrame, "TOPLEFT", borderSize + userOffsetX, borderSize + userOffsetY)
            elseif lockPos == "topcenter" then
                bar:SetPoint("BOTTOM", playerFrame, "TOP", userOffsetX, borderSize + userOffsetY)
            elseif lockPos == "topright" then
                bar:SetPoint("BOTTOMRIGHT", playerFrame, "TOPRIGHT", -borderSize + userOffsetX, borderSize + userOffsetY)
            elseif lockPos == "bottomleft" then
                bar:SetPoint("TOPLEFT", playerFrame, "BOTTOMLEFT", borderSize + userOffsetX, -borderSize + userOffsetY)
            elseif lockPos == "bottomcenter" then
                bar:SetPoint("TOP", playerFrame, "BOTTOM", userOffsetX, -borderSize + userOffsetY)
            elseif lockPos == "bottomright" then
                bar:SetPoint("TOPRIGHT", playerFrame, "BOTTOMRIGHT", -borderSize + userOffsetX, -borderSize + userOffsetY)
            end
            return
        end
    end

    -- LOCKED TO TARGET: reparent and use relative positioning
    if config.lockedToTarget then
        local targetFrame = _G["QUI_Target"]

        if not targetFrame then
            local findTarget = Helpers.FindAnchorFrame("target")
            if findTarget then targetFrame = findTarget end
        end

        if targetFrame then
            bar:SetParent(targetFrame)
            bar:SetFrameLevel(targetFrame:GetFrameLevel() + 10)
            local lockPos = config.targetLockPosition or "bottomcenter"
            local borderSize = config.borderSize or 2
            local userOffsetX = config.offsetX or 0
            local userOffsetY = config.offsetY or 0

            -- Position at corner (bar edge touches frame edge + border gap + user offset)
            if lockPos == "topleft" then
                bar:SetPoint("BOTTOMLEFT", targetFrame, "TOPLEFT", borderSize + userOffsetX, borderSize + userOffsetY)
            elseif lockPos == "topcenter" then
                bar:SetPoint("BOTTOM", targetFrame, "TOP", userOffsetX, borderSize + userOffsetY)
            elseif lockPos == "topright" then
                bar:SetPoint("BOTTOMRIGHT", targetFrame, "TOPRIGHT", -borderSize + userOffsetX, borderSize + userOffsetY)
            elseif lockPos == "bottomleft" then
                bar:SetPoint("TOPLEFT", targetFrame, "BOTTOMLEFT", borderSize + userOffsetX, -borderSize + userOffsetY)
            elseif lockPos == "bottomcenter" then
                bar:SetPoint("TOP", targetFrame, "BOTTOM", userOffsetX, -borderSize + userOffsetY)
            elseif lockPos == "bottomright" then
                bar:SetPoint("TOPRIGHT", targetFrame, "BOTTOMRIGHT", -borderSize + userOffsetX, -borderSize + userOffsetY)
            end
            return
        end
    end

    -- UNLOCKED: normal UIParent positioning
    bar:SetParent(UIParent)

    -- Re-apply draggable state (SetParent can reset these properties)
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetClampedToScreen(true)

    local offsetX = config.offsetX or 0
    local offsetY = config.offsetY or -300
    local growDir = config.growDirection or "RIGHT"

    -- offsetX/offsetY represent the ANCHOR EDGE position directly (saved by OnDragStop)
    -- No width-based conversion needed - just use the appropriate anchor point
    -- This ensures icons don't shift when new ones are added
    if growDir == "RIGHT" then
        bar:SetPoint("LEFT", UIParent, "CENTER", offsetX, offsetY)
    elseif growDir == "LEFT" then
        bar:SetPoint("RIGHT", UIParent, "CENTER", offsetX, offsetY)
    elseif growDir == "DOWN" then
        bar:SetPoint("TOP", UIParent, "CENTER", offsetX, offsetY)
    elseif growDir == "UP" then
        bar:SetPoint("BOTTOM", UIParent, "CENTER", offsetX, offsetY)
    else
        bar:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
    end
end

---------------------------------------------------------------------------
-- DATABASE ACCESS
---------------------------------------------------------------------------
-- GetDB is imported from utils.lua via Helpers at the top of this file

local function GetGlobalDB()
    local core = GetCore()
    if core and core.db and core.db.global then
        return core.db.global
    end
    return nil
end

---------------------------------------------------------------------------
-- SPEC-SPECIFIC SPELL HELPERS
---------------------------------------------------------------------------
-- Get the current player's spec key in "CLASS-specID" format
-- Returns human-readable format for storage and display
local function GetCurrentSpecKey()
    local _, className = UnitClass("player")
    local specIndex = GetSpecialization()
    if specIndex then
        local specID = GetSpecializationInfo(specIndex)
        if specID and className then
            return className .. "-" .. specID
        end
    end
    return nil
end

-- Get human-readable "Class - Spec" name for display
local function GetClassSpecName(specKey)
    if not specKey then return "Unknown" end
    local className, specID = specKey:match("^(.+)-(%d+)$")
    if not className or not specID then return specKey end
    
    specID = tonumber(specID)
    if not specID then return specKey end
    
    local _, specName = GetSpecializationInfoByID(specID)
    if specName then
        -- Capitalize class name properly
        local classDisplay = className:sub(1, 1):upper() .. className:sub(2):lower()
        return classDisplay .. " - " .. specName
    end
    return specKey
end

-- Get all specs for the player's class
local function GetAllClassSpecs()
    local _, className = UnitClass("player")
    local specs = {}
    local numSpecs = GetNumSpecializations()
    
    for i = 1, numSpecs do
        local specID, specName = GetSpecializationInfo(i)
        if specID and specName then
            table_insert(specs, {
                key = className .. "-" .. specID,
                specID = specID,
                specIndex = i,
                name = className:sub(1, 1):upper() .. className:sub(2):lower() .. " - " .. specName,
                className = className,
                specName = specName,
            })
        end
    end
    
    return specs
end

local function GetTrackerBarConfigAndIndex(barID)
    local db = GetDB()
    if not db or not db.bars or not barID then
        return nil, nil
    end

    for index, barConfig in ipairs(db.bars) do
        if barConfig.id == barID then
            return barConfig, index
        end
    end

    return nil, nil
end

local function GetNextTrackerBarName()
    local db = GetDB()
    local usedNames = {}

    if db and db.bars then
        for _, barConfig in ipairs(db.bars) do
            if type(barConfig.name) == "string" and barConfig.name ~= "" then
                usedNames[barConfig.name] = true
            end
        end
    end

    local index = 1
    while true do
        local candidate = "Tracker " .. index
        if not usedNames[candidate] then
            return candidate
        end
        index = index + 1
    end
end

local function CreateFreshBarConfig(barID, displayName)
    local defaults = ns.defaults
        and ns.defaults.profile
        and ns.defaults.profile.customTrackers
        and ns.defaults.profile.customTrackers.bars
    local template = defaults and defaults[1]
    local barConfig = (template and CopyTable and CopyTable(template)) or {
        enabled = false,
        locked = false,
        offsetX = -406,
        offsetY = -152,
        growDirection = "RIGHT",
        iconSize = 28,
        spacing = 4,
        borderSize = 2,
        aspectRatioCrop = 1.0,
        zoom = 0,
        durationSize = 13,
        durationColor = {1, 1, 1, 1},
        durationAnchor = "CENTER",
        durationOffsetX = 0,
        durationOffsetY = 0,
        hideDurationText = false,
        stackSize = 9,
        stackColor = {1, 1, 1, 1},
        stackAnchor = "BOTTOMRIGHT",
        stackOffsetX = 3,
        stackOffsetY = -1,
        hideStackText = false,
        showItemCharges = true,
        bgOpacity = 0,
        bgColor = {0, 0, 0, 1},
        hideGCD = true,
        hideNonUsable = false,
        showOnlyOnCooldown = false,
        showOnlyWhenActive = false,
        showOnlyWhenOffCooldown = false,
        showOnlyInCombat = false,
        clickableIcons = false,
        showActiveState = true,
        activeGlowEnabled = true,
        activeGlowType = "Pixel Glow",
        activeGlowColor = {1, 0.85, 0.3, 1},
        entries = {},
    }

    barConfig.id = barID
    barConfig.name = displayName or GetNextTrackerBarName()
    barConfig.enabled = true
    barConfig.entries = {}
    barConfig.specSpecificSpells = false

    if barConfig.dynamicLayout and barConfig.clickableIcons then
        barConfig.clickableIcons = false
    end

    return barConfig
end

-- Get entries for a bar, resolving spec-specific storage if enabled
-- @param barConfig: The bar configuration from db.profile
-- @param specKey: Optional override spec key (for editing other specs in UI)
-- @return entries table (may be empty but never nil)
local function GetBarEntries(barConfig, specKey)
    if not barConfig then return {} end
    
    -- If spec-specific mode is not enabled, use profile entries
    if not barConfig.specSpecificSpells then
        return barConfig.entries or {}
    end
    
    -- Spec-specific mode: get entries from global storage
    local globalDB = GetGlobalDB()
    if not globalDB then
        return barConfig.entries or {}  -- Fallback to profile
    end
    
    -- Initialize global spec storage if needed
    if not globalDB.specTrackerSpells then
        globalDB.specTrackerSpells = {}
    end
    
    -- Get or create bar's spec spell storage
    local barSpecSpells = globalDB.specTrackerSpells[barConfig.id]
    if not barSpecSpells then
        barSpecSpells = {}
        globalDB.specTrackerSpells[barConfig.id] = barSpecSpells
    end
    
    -- Use provided specKey or current spec
    local key = specKey or GetCurrentSpecKey()
    if not key then
        return barConfig.entries or {}  -- Fallback if spec unavailable
    end
    
    -- Get entries for this spec, or empty table
    return barSpecSpells[key] or {}
end

-- Get/set entries for a specific spec (for UI use)
-- @param barConfig: Bar configuration
-- @param specKey: The spec key to get/set entries for
-- @param entries: If provided, sets the entries; if nil, gets them
-- @return entries table when getting
function CustomTrackers:GetSpecEntries(barConfig, specKey)
    if not barConfig or not specKey then return {} end
    
    local globalDB = GetGlobalDB()
    if not globalDB then return {} end
    
    if not globalDB.specTrackerSpells then
        globalDB.specTrackerSpells = {}
    end
    
    local barSpecSpells = globalDB.specTrackerSpells[barConfig.id]
    if not barSpecSpells then return {} end
    
    return barSpecSpells[specKey] or {}
end

function CustomTrackers:SetSpecEntries(barConfig, specKey, entries)
    if not barConfig or not specKey then return end
    
    local globalDB = GetGlobalDB()
    if not globalDB then return end
    
    if not globalDB.specTrackerSpells then
        globalDB.specTrackerSpells = {}
    end
    
    if not globalDB.specTrackerSpells[barConfig.id] then
        globalDB.specTrackerSpells[barConfig.id] = {}
    end
    
    globalDB.specTrackerSpells[barConfig.id][specKey] = entries
end

-- Copy profile entries to spec storage (used when enabling spec-specific mode)
function CustomTrackers:CopyEntriesToSpec(barConfig, specKey)
    if not barConfig or not specKey then return end
    if not barConfig.entries or #barConfig.entries == 0 then return end
    
    -- Deep copy entries
    local copiedEntries = {}
    for _, entry in ipairs(barConfig.entries) do
        table_insert(copiedEntries, {
            type = entry.type,
            id = entry.id,
            customName = entry.customName,
        })
    end
    
    self:SetSpecEntries(barConfig, specKey, copiedEntries)
end

-- Expose helper functions to module for use in options UI
CustomTrackers.GetCurrentSpecKey = GetCurrentSpecKey
CustomTrackers.GetClassSpecName = GetClassSpecName
CustomTrackers.GetAllClassSpecs = GetAllClassSpecs
CustomTrackers.GetBarEntries = GetBarEntries

---------------------------------------------------------------------------
-- FONT HELPERS (uses shared helpers)
---------------------------------------------------------------------------
local GetGeneralFont = Helpers.GetGeneralFont
local GetGeneralFontOutline = Helpers.GetGeneralFontOutline

---------------------------------------------------------------------------
-- INFO CACHE (prevents repeated API calls)
---------------------------------------------------------------------------
local function GetCachedSpellInfo(spellID)
    if not spellID then return nil end
    local cacheKey = "spell_" .. spellID
    if CustomTrackers.infoCache[cacheKey] then
        return CustomTrackers.infoCache[cacheKey]
    end
    local info = C_Spell.GetSpellInfo(spellID)
    if info then
        CustomTrackers.infoCache[cacheKey] = {
            name = info.name,
            icon = info.iconID,
            id = spellID,
            type = "spell",
        }
        return CustomTrackers.infoCache[cacheKey]
    end
    return nil
end

local function GetCachedItemInfo(itemID)
    if not itemID then return nil end
    local cacheKey = "item_" .. itemID
    if CustomTrackers.infoCache[cacheKey] then
        return CustomTrackers.infoCache[cacheKey]
    end
    local name, _, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
    if name then
        CustomTrackers.infoCache[cacheKey] = {
            name = name,
            icon = icon,
            id = itemID,
            type = "item",
        }
        return CustomTrackers.infoCache[cacheKey]
    end
    -- Item not cached yet, request it
    C_Item.RequestLoadItemDataByID(itemID)
    return nil
end

local function GetCachedSlotInfo(slotNum)
    if not slotNum then return nil end
    local cacheKey = "slot_" .. slotNum
    if CustomTrackers.infoCache[cacheKey] then
        return CustomTrackers.infoCache[cacheKey]
    end
    local itemID = GetInventoryItemID("player", slotNum)
    if not itemID then
        -- Empty slot: return placeholder
        CustomTrackers.infoCache[cacheKey] = {
            name = "Empty Slot",
            icon = "Interface\\Icons\\INV_Misc_QuestionMark",
            id = slotNum,
            itemID = nil,
            type = "slot",
        }
        return CustomTrackers.infoCache[cacheKey]
    end
    local name, _, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
    if name then
        CustomTrackers.infoCache[cacheKey] = {
            name = name,
            icon = icon,
            id = slotNum,
            itemID = itemID,
            type = "slot",
        }
        return CustomTrackers.infoCache[cacheKey]
    end
    -- Item not cached yet, request it
    C_Item.RequestLoadItemDataByID(itemID)
    return nil
end

---------------------------------------------------------------------------
-- COOLDOWN INFO HELPERS
---------------------------------------------------------------------------
local function GetSpellCooldownInfo(spellID)
    if not spellID then return 0, 0, false, nil, false, nil end
    local cooldownInfo = C_Spell.GetSpellCooldown(spellID)
    local durObj = nil
    if C_Spell.GetSpellCooldownDuration then
        local okDur, obj = pcall(C_Spell.GetSpellCooldownDuration, spellID)
        if okDur and obj then
            durObj = obj
        end
    end
    if cooldownInfo then
        return cooldownInfo.startTime, cooldownInfo.duration, cooldownInfo.isEnabled, cooldownInfo.isOnGCD, cooldownInfo.isActive, durObj
    end
    return 0, 0, true, nil, false, durObj
end

local function GetItemCooldownInfo(itemID)
    if not itemID then return 0, 0, false end
    local startTime, duration, enable = C_Item.GetItemCooldown(itemID)
    return startTime or 0, duration or 0, enable ~= 0
end

local function GetItemStackCount(itemID, includeCharges)
    if not itemID then return 0 end
    -- Parameters: itemID, includeBank, includeUses/Charges, includeReagentBank
    -- When includeCharges=true, count charges for items like Healthstones (3 charges = shows 3)
    -- When includeCharges=false, count items only (1 Healthstone = shows 1)
    local includeUses = includeCharges ~= false  -- Default to true if not specified
    local count = C_Item.GetItemCount(itemID, false, includeUses, true)
    -- Handle nil return
    if count == nil then return 0 end
    -- In Midnight, item counts can be secret values - return as-is for SetText to handle
    -- The caller will check issecretvalue() before comparisons
    return count
end

-- Cache for known charge spells (spellID -> maxCharges)
-- Populated when we can safely read maxCharges (outside combat/untainted)
local knownChargeSpells = {}

-- Track when charge spells were last cast (spellID -> GetTime())
-- Used to detect real recharge vs GCD in combat when charge count is secret
local chargeSpellLastCast = {}

local function GetSpellChargeCount(spellID)
    if not spellID then return 0, 1, 0, 0, false, nil end
    local chargeInfo = C_Spell.GetSpellCharges(spellID)
    local durObj = nil
    if C_Spell.GetSpellChargeDuration then
        local okDur, obj = pcall(C_Spell.GetSpellChargeDuration, spellID)
        if okDur and obj then
            durObj = obj
        end
    end

    if not chargeInfo then
        return 0, 1, 0, 0, false, durObj  -- Not a charge-based spell
    end

    local maxCharges = chargeInfo.maxCharges

    -- Check if maxCharges exists
    if not maxCharges then
        return 0, 1, 0, 0, false, durObj
    end

    -- Handle secret values (protected in combat)
    if IsSecretValue(maxCharges) then
        -- Can't read maxCharges directly - check our cache
        local cachedMax = knownChargeSpells[spellID]
        if cachedMax and cachedMax > 1 then
            -- Known charge spell - return charge cooldown values with cached maxCharges
            return chargeInfo.currentCharges, cachedMax,
                   chargeInfo.cooldownStartTime or 0,
                   chargeInfo.cooldownDuration or 0,
                   chargeInfo.isActive,
                   durObj
        end
        -- Unknown or single-charge spell - treat as non-charge (safe default)
        return 0, 1, 0, 0, false, durObj
    end

    -- Normal case: safe to compare - also cache the result
    if maxCharges > 1 then
        knownChargeSpells[spellID] = maxCharges  -- Cache for future secret-value situations
        return chargeInfo.currentCharges or 0, maxCharges,
               chargeInfo.cooldownStartTime or 0,
               chargeInfo.cooldownDuration or 0,
               chargeInfo.isActive,
               durObj
    end

    -- Single charge spell - cache that too
    knownChargeSpells[spellID] = 1
    return 0, 1, 0, 0, false, durObj
end

-- Helper to check if cooldown frame is actively showing a cooldown
local function IsCooldownFrameActive(cooldownFrame)
    if not cooldownFrame then return false end
    -- Use IsShown() instead of IsVisible(): IsVisible() returns false when a
    -- parent icon is hidden (e.g., dynamicLayout + showOnlyWhenOffCooldown),
    -- causing a Show/Hide oscillation. IsShown() reflects the cooldown frame's
    -- own state regardless of ancestor visibility.
    local ok, shown = pcall(cooldownFrame.IsShown, cooldownFrame)
    return ok and shown == true
end

-- Check if item is equipment (armor/weapon) vs consumable
local function IsEquipmentItem(itemID)
    local classID = select(6, C_Item.GetItemInfoInstant(itemID))
    if not classID then return false end
    return classID == Enum.ItemClass.Armor or classID == Enum.ItemClass.Weapon
end

-- Check if item is usable
-- Equipment: must be equipped (ignore bag count)
-- Consumables: must have count > 0
local function IsItemUsable(itemID, itemCount)
    if IsEquipmentItem(itemID) then
        -- Equipment: ONLY check if equipped, bag count irrelevant
        return C_Item.IsEquippedItem(itemID) and true or false
    else
        -- Consumables: C_Item.GetItemCount can return secret values during combat.
        -- Can't compare secrets with > so guard just this one Lua read.
        if IsSecretValue(itemCount) then return true end
        return itemCount and itemCount > 0
    end
end

-- Check if spell is known and usable
local function IsSpellUsable(spellID)
    -- Check if spell exists
    local spellInfo = C_Spell.GetSpellInfo(spellID)
    if not spellInfo then return false end

    -- Check if known (handles talent overrides)
    if IsSpellKnownOrOverridesKnown then
        return IsSpellKnownOrOverridesKnown(spellID)
    elseif IsPlayerSpell then
        return IsPlayerSpell(spellID)
    end

    return IsSpellKnown(spellID)
end

---------------------------------------------------------------------------
-- ACTIVE STATE DETECTION (casting/channeling/buff active)
---------------------------------------------------------------------------

-- Check if player is currently casting a specific spell
-- Returns: isActive, startTimeMS, endTimeMS (or nil if not casting)
local function GetSpellCastInfo(spellID)
    if not spellID then return false end
    local _, _, _, startTimeMS, endTimeMS, _, _, _, castSpellID = UnitCastingInfo("player")
    if castSpellID and castSpellID == spellID then
        return true, startTimeMS, endTimeMS
    end
    return false
end

-- Check if player is currently channeling a specific spell
-- Returns: isActive, startTimeMS, endTimeMS (or nil if not channeling)
local function GetSpellChannelInfo(spellID)
    if not spellID then return false end
    local _, _, _, startTimeMS, endTimeMS, _, _, _, channelSpellID = UnitChannelInfo("player")
    if channelSpellID and channelSpellID == spellID then
        return true, startTimeMS, endTimeMS
    end
    return false
end

-- Check if player has a buff with a specific spell ID
-- Returns: isActive, expirationTime, duration (or nil if no buff)
local function GetSpellBuffInfo(spellID)
    if not spellID then return false end

    -- Prefer SpellScanner whenever available.
    -- Reason: some spells apply a DIFFERENT aura spellID than the cast spellID
    -- (e.g. Angelic Feather), and SpellScanner maintains that cast→buff mapping.
    local scanner = QUI and QUI.SpellScanner
    if scanner and scanner.IsSpellActive then
        local isActive, expiration, duration = scanner.IsSpellActive(spellID)
        if isActive then
            return true, expiration, duration
        end
        -- If we're in combat and SpellScanner didn't detect it, we can't query auras safely.
        if InCombatLockdown() then
            return false
        end
    elseif InCombatLockdown() then
        -- No SpellScanner available, and we can't query auras in combat.
        return false
    end

    -- Out of combat: use direct API (more accurate)
    -- pcall guards against unexpected protection in instanced content
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        if ok and auraData then
            return true, auraData.expirationTime, auraData.duration
        end
    end
    return false
end

-- Unified active state detection: casting → channeling → buff
-- Returns: isActive, startTimeSec, durationSec, activeType ("cast"/"channel"/"buff")
local function GetSpellActiveInfo(spellID)
    if not spellID then return false end

    -- Check casting first (shortest duration typically)
    local isCasting, castStart, castEnd = GetSpellCastInfo(spellID)
    if isCasting and castStart and castEnd then
        local startSec = castStart / 1000
        local durationSec = (castEnd - castStart) / 1000
        return true, startSec, durationSec, "cast"
    end

    -- Check channeling
    local isChanneling, channelStart, channelEnd = GetSpellChannelInfo(spellID)
    if isChanneling and channelStart and channelEnd then
        local startSec = channelStart / 1000
        local durationSec = (channelEnd - channelStart) / 1000
        return true, startSec, durationSec, "channel"
    end

    -- Check buff (longest duration typically)
    local hasBuff, expiration, buffDuration = GetSpellBuffInfo(spellID)
    if hasBuff and expiration and buffDuration then
        local startSec = expiration - buffDuration
        return true, startSec, buffDuration, "buff"
    end

    return false
end

-- Check if an item's buff/effect is currently active
-- Returns: isActive, startTimeSec, durationSec, activeType
local function GetItemActiveInfo(itemID)
    if not itemID then return false end
    local itemSpellID = select(2, C_Item.GetItemSpell(itemID))
    if itemSpellID then
        return GetSpellActiveInfo(itemSpellID)
    end
    return false
end

---------------------------------------------------------------------------
-- ACTIVE STATE GLOW (LibCustomGlow integration)
---------------------------------------------------------------------------
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

-- Path to proc glow mask (rounds icon corners to match the proc glow)
local PROC_GLOW_MASK = "Interface\\AddOns\\QUI\\assets\\iconskin\\ProcGlowMask"

local function StartActiveGlow(icon, config)
    if not icon or not LCG then return end
    if icon._activeGlowShown then return end
    if icon._activeGlowPending then return end  -- Prevent duplicate deferred calls

    if config and config.activeGlowEnabled == false then return end

    -- Guard: Ensure icon has valid dimensions before starting glow effects.
    -- In dynamic/collapsing layout, icons may be shown before layout pass sets proper size.
    -- Without this check, Proc Glow's start animation renders at wrong (huge) dimensions.
    local iconWidth, iconHeight = icon:GetSize()
    if not iconWidth or not iconHeight or iconWidth < 10 or iconHeight < 10 then
        return  -- Icon not properly sized yet; glow will start on next update tick
    end

    local glowType = (config and config.activeGlowType) or "Pixel Glow"

    local color = (config and config.activeGlowColor) or { 1, 0.85, 0.3, 1 }
    local lines = (config and config.activeGlowLines) or 8
    local frequency = (config and config.activeGlowFrequency) or 0.25
    local thickness = (config and config.activeGlowThickness) or 2
    local scale = (config and config.activeGlowScale) or 1.0

    if glowType == "Proc Glow" then
        -- Use LibCustomGlow's ProcGlow (has start animation + proper sizing)
        -- Convert frequency to duration (LibCustomGlow uses duration for ProcGlow)
        local duration = 1.0 / (frequency * 4)
        duration = math.max(0.5, math.min(2.0, duration))
        
        -- Hide border during Proc Glow (its dark corners show through the rounded glow)
        if icon.border and icon.border:IsShown() then
            icon._borderWasShown = true
            icon.border:Hide()
        end
        
        -- Apply rounded corner mask to icon texture (matches proc glow shape)
        if icon.tex then
            if not icon._procGlowMask then
                icon._procGlowMask = icon:CreateMaskTexture()
                icon._procGlowMask:SetTexture(PROC_GLOW_MASK)
                icon._procGlowMask:SetAllPoints(icon.tex)
            end
            icon.tex:AddMaskTexture(icon._procGlowMask)
        end
        
        -- CRITICAL: Defer ProcGlow_Start to next frame.
        -- LibCustomGlow sets anchor points then immediately calls f:Show(), but the
        -- OnShow handler fires before anchors are resolved by a layout pass, causing
        -- GetSize() to return 0,0 and the start animation to render at wrong size.
        -- By deferring to next frame, we ensure the layout pass has completed.
        icon._activeGlowPending = true
        icon._activeGlowType = glowType
        C_Timer.After(0, function()
            icon._activeGlowPending = nil
            -- Double-check icon still exists and should show glow
            if not icon or not icon:IsShown() then return end
            if icon._activeGlowShown then return end
            
            LCG.ProcGlow_Start(icon, {
                color = color,
                duration = duration,
                startAnim = true,  -- Show the burst effect before looping
                key = "_QUIActiveGlow",
            })
            icon._activeGlowShown = true
        end)
    elseif glowType == "Pixel Glow" then
        LCG.PixelGlow_Start(icon, color, lines, frequency, nil, thickness, 0, 0, true, "_QUIActiveGlow")
        icon._activeGlowShown = true
        icon._activeGlowType = glowType
    elseif glowType == "Autocast Shine" then
        LCG.AutoCastGlow_Start(icon, color, lines, frequency, scale, 0, 0, "_QUIActiveGlow")
        icon._activeGlowShown = true
        icon._activeGlowType = glowType
    end
end

local function StopActiveGlow(icon)
    if not icon or not LCG then return end
    
    -- Clear pending flag (for deferred Proc Glow that hasn't started yet)
    icon._activeGlowPending = nil
    
    if not icon._activeGlowShown then
        -- Glow not started, but may need to cleanup border/mask from pending Proc Glow
        if icon._borderWasShown and icon.border then
            icon.border:Show()
            icon._borderWasShown = nil
        end
        if icon.tex and icon._procGlowMask then
            icon.tex:RemoveMaskTexture(icon._procGlowMask)
        end
        return
    end

    local glowType = icon._activeGlowType or "Pixel Glow"

    if glowType == "Proc Glow" then
        pcall(LCG.ProcGlow_Stop, icon, "_QUIActiveGlow")

        -- Remove mask from icon texture
        if icon.tex and icon._procGlowMask then
            icon.tex:RemoveMaskTexture(icon._procGlowMask)
        end

        -- Restore border if it was hidden
        if icon._borderWasShown and icon.border then
            icon.border:Show()
            icon._borderWasShown = nil
        end
    elseif glowType == "Pixel Glow" then
        pcall(LCG.PixelGlow_Stop, icon, "_QUIActiveGlow")
    elseif glowType == "Autocast Shine" then
        pcall(LCG.AutoCastGlow_Stop, icon, "_QUIActiveGlow")
    end

    icon._activeGlowShown = nil
    icon._activeGlowType = nil
end

---------------------------------------------------------------------------
-- ICON CREATION
---------------------------------------------------------------------------
local function CreateTrackerIcon(parent, clickable)
    local icon = CreateFrame("Frame", nil, parent)
    icon.__customTrackerIcon = true  -- Marker for tooltip visibility system
    icon:SetSize(36, 36)  -- Default, will be resized

    -- Border (BACKGROUND texture at sublevel -8, combat-safe)
    icon.border = icon:CreateTexture(nil, "BACKGROUND", nil, -8)
    icon.border:SetColorTexture(0, 0, 0, 1)

    -- Icon texture
    icon.tex = icon:CreateTexture(nil, "ARTWORK")
    icon.tex:SetAllPoints()

    -- Cooldown overlay - USE Blizzard's built-in countdown (handles secret values internally)
    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints()
    icon.cooldown:SetDrawSwipe(false)             -- NO swipe animation
    icon.cooldown:SetDrawEdge(false)              -- NO edge glow
    icon.cooldown:SetHideCountdownNumbers(false)  -- Still show countdown numbers!
    icon.cooldown:EnableMouse(false)              -- Don't block drag events
    if icon.cooldown.SetDrawBling then icon.cooldown:SetDrawBling(false) end  -- No ready flash

    -- Duration text (on icon, not cooldown - more control)
    icon.durationText = icon:CreateFontString(nil, "OVERLAY")
    icon.durationText:SetFont(GetGeneralFont(), 14, GetGeneralFontOutline())

    -- Stack text
    icon.stackText = icon:CreateFontString(nil, "OVERLAY")
    icon.stackText:SetFont(GetGeneralFont(), 12, GetGeneralFontOutline())

    -- Keybind text (top-left by default)
    icon.keybindText = icon:CreateFontString(nil, "OVERLAY")
    icon.keybindText:SetFont(GetGeneralFont(), 10, GetGeneralFontOutline())
    icon.keybindText:SetShadowOffset(1, -1)
    icon.keybindText:SetShadowColor(0, 0, 0, 1)
    icon.keybindText:Hide()

    -- Cooldown state persistence (prevents false "ready" states from bad API reads)
    icon.lastKnownCDEnd = 0

    local function SetupIconTooltip(iconFrame)
        if GameTooltip.IsForbidden and GameTooltip:IsForbidden() then return end
        if iconFrame:GetAlpha() == 0 then return end  -- Don't show tooltip when visually hidden
        if iconFrame.entry then
            local tooltipProvider = ns.TooltipProvider
            if tooltipProvider and tooltipProvider.ShouldShowTooltip then
                if not tooltipProvider:ShouldShowTooltip("customTrackers") then
                    pcall(GameTooltip.Hide, GameTooltip)
                    return
                end
            end

            -- Respect tooltip anchor setting
            local core = GetCore()
            local tooltipSettings = core and core.db and core.db.profile and core.db.profile.tooltip
            if tooltipSettings and tooltipSettings.anchorToCursor then
                local anchorTooltip = ns.QUI_AnchorTooltipToCursor
                if anchorTooltip then
                    anchorTooltip(GameTooltip, iconFrame, tooltipSettings)
                else
                    GameTooltip:SetOwner(iconFrame, "ANCHOR_CURSOR")
                end
            else
                GameTooltip_SetDefaultAnchor(GameTooltip, iconFrame)
            end
            if iconFrame.entry.type == "spell" then
                pcall(GameTooltip.SetSpellByID, GameTooltip, iconFrame.entry.id)
            elseif iconFrame.entry.type == "slot" then
                local itemID = GetInventoryItemID("player", iconFrame.entry.id)
                if itemID then
                    pcall(GameTooltip.SetItemByID, GameTooltip, itemID)
                else
                    GameTooltip:SetText("Empty Equipment Slot")
                end
            elseif iconFrame.entry.type == "item" then
                -- pcall to handle Blizzard MoneyFrame secret value bug in Midnight beta
                pcall(GameTooltip.SetItemByID, GameTooltip, iconFrame.entry.id)
            end
        end
    end

    -- Tooltip on mouseover (skip if icon is hidden via alpha for showOnlyOnCooldown mode)
    icon:SetScript("OnEnter", function(self)
        SetupIconTooltip(self)
    end)

    icon:SetScript("OnLeave", function()
        pcall(GameTooltip.Hide, GameTooltip)
    end)

    -- Forward drag events to parent bar (so clicking on icons still allows dragging)
    icon:RegisterForDrag("LeftButton")
    icon:SetScript("OnDragStart", function(self)
        local bar = self:GetParent()
        if bar and bar.barID and _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("customTracker:" .. bar.barID) then return end
        if bar and bar.config and not bar.config.locked and not bar.config.lockedToPlayer and not bar.config.lockedToTarget then
            bar:StartMoving()
        end
    end)
    icon:SetScript("OnDragStop", function(self)
        local bar = self:GetParent()
        if bar then
            bar:StopMovingOrSizing()
            -- Fire the bar's drag stop handler to save position
            local dragStopHandler = bar:GetScript("OnDragStop")
            if dragStopHandler then
                dragStopHandler(bar)
            end
        end
    end)

    -- Secure click button for item/spell usage (only created when clickable is true)
    -- Icons with SecureActionButtonTemplate children become protected during combat,
    -- so we only create them when needed (never for dynamicLayout bars).
    if clickable then
        icon.clickButton = CreateFrame("Button", nil, icon, "SecureActionButtonTemplate")
        icon.clickButton:SetAllPoints()
        icon.clickButton:RegisterForClicks("AnyUp", "AnyDown")
        icon.clickButton:EnableMouse(true)
        icon.clickButton:Hide()

        -- Forward drag events to parent bar (preserve bar dragging when clickable)
        icon.clickButton:RegisterForDrag("LeftButton")
        icon.clickButton:SetScript("OnDragStart", function(self)
            local bar = self:GetParent():GetParent()
            if bar and bar.barID and _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("customTracker:" .. bar.barID) then return end
            if bar and bar.config and not bar.config.locked and not bar.config.lockedToPlayer and not bar.config.lockedToTarget then
                bar:StartMoving()
            end
        end)
        icon.clickButton:SetScript("OnDragStop", function(self)
            local bar = self:GetParent():GetParent()
            if bar then
                bar:StopMovingOrSizing()
                local dragStopHandler = bar:GetScript("OnDragStop")
                if dragStopHandler then
                    dragStopHandler(bar)
                end
            end
        end)

        -- Forward tooltip events through the secure button
        icon.clickButton:SetScript("OnEnter", function(self)
            SetupIconTooltip(self:GetParent())
        end)
        icon.clickButton:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    return icon
end

---------------------------------------------------------------------------
-- SECURE BUTTON ATTRIBUTES (for clickable icons)
---------------------------------------------------------------------------

-- Update secure button attributes for item/spell usage
-- Must be called outside combat; queues update if in combat
local function UpdateIconSecureAttributes(icon, entry, config)
    if not icon or not icon.clickButton then return end

    -- Can't modify secure attributes during combat
    if InCombatLockdown() then
        icon._pendingSecureUpdate = true
        return
    end

    local function ClearClickButtonAttributes()
        icon.clickButton:SetAttribute("type", nil)
        icon.clickButton:SetAttribute("spell", nil)
        icon.clickButton:SetAttribute("item", nil)
    end

    -- Hide if feature disabled or no config
    if not config or not config.clickableIcons then
        ClearClickButtonAttributes()
        icon.clickButton:Hide()
        return
    end

    -- Hide if no entry assigned
    if not entry then
        ClearClickButtonAttributes()
        icon.clickButton:Hide()
        return
    end

    -- Set up secure attributes based on entry type
    if entry.type == "spell" then
        local info = GetCachedSpellInfo(entry.id)
        if info and info.name then
            icon.clickButton:SetAttribute("type", "spell")
            icon.clickButton:SetAttribute("spell", info.name)
            icon.clickButton:Show()
        else
            ClearClickButtonAttributes()
            icon.clickButton:Hide()
        end
    elseif entry.type == "slot" then
        local itemID = GetInventoryItemID("player", entry.id)
        if itemID then
            local name = C_Item.GetItemInfo(itemID)
            if name then
                icon.clickButton:SetAttribute("type", "item")
                icon.clickButton:SetAttribute("item", name)
                icon.clickButton:Show()
            else
                ClearClickButtonAttributes()
                icon.clickButton:Hide()
            end
        else
            ClearClickButtonAttributes()
            icon.clickButton:Hide()
        end
    elseif entry.type == "item" then
        local info = GetCachedItemInfo(entry.id)
        if info and info.name then
            icon.clickButton:SetAttribute("type", "item")
            icon.clickButton:SetAttribute("item", info.name)
            icon.clickButton:Show()
        else
            ClearClickButtonAttributes()
            icon.clickButton:Hide()
        end
    else
        ClearClickButtonAttributes()
        icon.clickButton:Hide()
    end

    icon._pendingSecureUpdate = nil
end

-- Process any pending secure attribute updates after combat ends
local function ProcessPendingSecureUpdates()
    if InCombatLockdown() then return end

    for _, bar in pairs(CustomTrackers.activeBars or {}) do
        if bar and bar.icons and bar.config then
            for _, icon in ipairs(bar.icons) do
                if icon._pendingSecureUpdate then
                    UpdateIconSecureAttributes(icon, icon.entry, bar.config)
                end
                -- Sync Show/Hide for icons that used alpha fallback during combat
                if icon.isVisible then
                    if not icon:IsShown() then
                        icon:Show()
                        icon:SetAlpha(1)
                    end
                else
                    if icon:IsShown() then
                        icon:Hide()
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- ICON STYLING
---------------------------------------------------------------------------
local function StyleTrackerIcon(icon, config)
    if not icon or not config then return end

    -- Calculate size based on aspect ratio
    MigrateBarAspect(config)
    local aspectRatio = config.aspectRatioCrop or 1.0
    local width = config.iconSize or 36
    local height = width / aspectRatio
    icon:SetSize(width, height)

    -- Border
    local bs = config.borderSize or 2
    if bs > 0 then
        icon.border:Show()
        icon.border:ClearAllPoints()
        icon.border:SetPoint("TOPLEFT", -bs, bs)
        icon.border:SetPoint("BOTTOMRIGHT", bs, -bs)
    else
        icon.border:Hide()
    end

    -- TexCoord (zoom + base crop + aspect ratio cropping)
    local zoom = config.zoom or 0
    local aspectRatio = config.aspectRatioCrop or 1.0

    -- Start with base crop + zoom
    local left = BASE_CROP + zoom
    local right = 1 - BASE_CROP - zoom
    local top = BASE_CROP + zoom
    local bottom = 1 - BASE_CROP - zoom

    -- Apply aspect ratio crop ON TOP of existing crop (crops from center)
    if aspectRatio > 1.0 then
        -- Wider/flatter: crop MORE from top/bottom to center the icon
        local cropAmount = 1.0 - (1.0 / aspectRatio)
        local availableHeight = bottom - top
        local offset = (cropAmount * availableHeight) / 2.0
        top = top + offset
        bottom = bottom - offset
    end

    icon.tex:SetTexCoord(left, right, top, bottom)

    -- Duration text style
    local fontOutline = GetGeneralFontOutline()
    local durationFontPath = config.durationFont and LSM:Fetch("font", config.durationFont) or GetGeneralFont()

    icon.durationText:SetFont(durationFontPath, config.durationSize or 14, fontOutline)
    local dColor = config.durationColor or {1, 1, 1, 1}
    icon.durationText:SetTextColor(dColor[1], dColor[2], dColor[3], dColor[4] or 1)
    icon.durationText:ClearAllPoints()
    icon.durationText:SetPoint(
        config.durationAnchor or "CENTER",
        icon,
        config.durationAnchor or "CENTER",
        config.durationOffsetX or 0,
        config.durationOffsetY or 0
    )

    -- ALSO style Blizzard's built-in countdown text for consistency
    -- (Used during combat when secret values prevent custom text display)
    if icon.cooldown then
        local cooldown = icon.cooldown
        if cooldown.text then
            cooldown.text:SetFont(durationFontPath, config.durationSize or 14, fontOutline)
            cooldown.text:SetTextColor(dColor[1], dColor[2], dColor[3], dColor[4] or 1)
            pcall(function()
                cooldown.text:ClearAllPoints()
                cooldown.text:SetPoint(
                    config.durationAnchor or "CENTER",
                    icon,
                    config.durationAnchor or "CENTER",
                    config.durationOffsetX or 0,
                    config.durationOffsetY or 0
                )
            end)
        end

        -- Also check GetRegions for FontStrings (fallback)
        local ok, regions = pcall(function() return { cooldown:GetRegions() } end)
        if ok and regions then
            for _, region in ipairs(regions) do
                if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                    region:SetFont(durationFontPath, config.durationSize or 14, fontOutline)
                    region:SetTextColor(dColor[1], dColor[2], dColor[3], dColor[4] or 1)
                    pcall(function()
                        region:ClearAllPoints()
                        region:SetPoint(
                            config.durationAnchor or "CENTER",
                            icon,
                            config.durationAnchor or "CENTER",
                            config.durationOffsetX or 0,
                            config.durationOffsetY or 0
                        )
                    end)
                end
            end
        end
    end

    -- Stack text style
    local stackFontPath = config.stackFont and LSM:Fetch("font", config.stackFont) or GetGeneralFont()
    icon.stackText:SetFont(stackFontPath, config.stackSize or 12, fontOutline)
    local sColor = config.stackColor or {1, 1, 1, 1}
    icon.stackText:SetTextColor(sColor[1], sColor[2], sColor[3], sColor[4] or 1)
    icon.stackText:ClearAllPoints()
    icon.stackText:SetPoint(
        config.stackAnchor or "BOTTOMRIGHT",
        icon,
        config.stackAnchor or "BOTTOMRIGHT",
        config.stackOffsetX or -2,
        config.stackOffsetY or 2
    )

    -- Keybind text style (uses global settings from customTrackers.keybinds)
    if icon.keybindText then
        local core = GetCore()
        local db = core and core.db and core.db.profile
        local keybindSettings = db and db.customTrackers and db.customTrackers.keybinds
        if keybindSettings then
            icon.keybindText:SetFont(GetGeneralFont(), keybindSettings.keybindTextSize or 10, fontOutline)
            local kColor = keybindSettings.keybindTextColor or {1, 0.82, 0, 1}
            icon.keybindText:SetTextColor(kColor[1], kColor[2], kColor[3], kColor[4] or 1)
            icon.keybindText:ClearAllPoints()
            icon.keybindText:SetPoint("TOPLEFT", icon, "TOPLEFT",
                keybindSettings.keybindOffsetX or 2,
                keybindSettings.keybindOffsetY or -2
            )
        end
    end
end

---------------------------------------------------------------------------
-- KEYBIND DISPLAY FOR TRACKER ICONS
---------------------------------------------------------------------------
local function ApplyKeybindToTrackerIcon(icon)
    if not icon or not icon.entry then return end

    local core = GetCore()
    local db = core and core.db and core.db.profile
    local keybindSettings = db and db.customTrackers and db.customTrackers.keybinds

    if not keybindSettings or not keybindSettings.showKeybinds then
        if icon.keybindText then
            icon.keybindText:SetText("")
            icon.keybindText:Hide()
        end
        return
    end

    -- Get keybind based on entry type
    -- Priority: User override > Auto-detected cache
    local keybind = nil
    local entry = icon.entry

    -- Access keybind functions from ns namespace (addon namespace, not AceAddon)
    local QUIKeybinds = ns and ns.Keybinds
    if not QUIKeybinds then
        if icon.keybindText then
            icon.keybindText:Hide()
        end
        return
    end

    -- Check tracker overrides toggle
    local trackersOverridesEnabled = true
    if db then
        trackersOverridesEnabled = db.keybindOverridesEnabledTrackers ~= false
    end

    -- Use centralized API for overrides
    local overrides = trackersOverridesEnabled and QUIKeybinds.GetOverrides and QUIKeybinds.GetOverrides() or nil

    if entry.type == "spell" and entry.id then
        -- Step 1: Check for user override (highest priority)
        if overrides and overrides[entry.id] and overrides[entry.id] ~= "" then
            keybind = overrides[entry.id]
        end

        -- Step 2: Try auto-detected cache by spell ID
        if not keybind then
            keybind = QUIKeybinds.GetKeybindForSpell(entry.id)
        end

        -- Step 3: Try spell name fallback (for macros)
        if not keybind and QUIKeybinds.GetKeybindForSpellName then
            local spellInfo = C_Spell.GetSpellInfo(entry.id)
            if spellInfo and spellInfo.name then
                keybind = QUIKeybinds.GetKeybindForSpellName(spellInfo.name)
            end
        end
    elseif entry.type == "slot" and entry.id then
        -- Slot entries: resolve current itemID, then look up keybinds for that item
        local itemID = GetInventoryItemID("player", entry.id)
        if itemID then
            if overrides then
                local overrideKey = -itemID
                if overrides[overrideKey] and overrides[overrideKey] ~= "" then
                    keybind = overrides[overrideKey]
                end
            end
            if not keybind then
                keybind = QUIKeybinds.GetKeybindForItem(itemID)
            end
            if not keybind and QUIKeybinds.GetKeybindForItemName then
                local itemName = C_Item.GetItemInfo(itemID)
                if itemName then
                    keybind = QUIKeybinds.GetKeybindForItemName(itemName)
                end
            end
        end
    elseif entry.type == "item" and entry.id then
        -- Step 1: Check for user override (highest priority)
        -- Items use negative itemID as key to avoid conflicts with spellIDs
        if overrides then
            local overrideKey = -entry.id
            if overrides[overrideKey] and overrides[overrideKey] ~= "" then
                keybind = overrides[overrideKey]
            end
        end

        -- Step 2: Try auto-detected cache by item ID
        if not keybind then
            keybind = QUIKeybinds.GetKeybindForItem(entry.id)
        end

        -- Step 3: Try item name fallback (for macros)
        if not keybind and QUIKeybinds.GetKeybindForItemName then
            local itemName = C_Item.GetItemInfo(entry.id)
            if itemName then
                keybind = QUIKeybinds.GetKeybindForItemName(itemName)
            end
        end
    end

    if not icon.keybindText then return end

    if keybind then
        icon.keybindText:SetText(keybind)
        icon.keybindText:Show()
    else
        icon.keybindText:SetText("")
        icon.keybindText:Hide()
    end
end

---------------------------------------------------------------------------
-- BAR ICON LAYOUT (two-pass pattern)
---------------------------------------------------------------------------
local function LayoutBarIcons(bar)
    if not bar or not bar.icons then return end

    local config = bar.config
    local growDir = config.growDirection or "RIGHT"
    local spacing = config.spacing or 4

    -- Calculate icon dimensions
    local aspectRatio = config.aspectRatioCrop or 1.0
    local iconWidth = config.iconSize or 36
    local iconHeight = iconWidth / aspectRatio

    -- PASS 1: Clear all points
    for _, icon in ipairs(bar.icons) do
        icon:ClearAllPoints()
    end

    -- PASS 2: Position based on grow direction
    local numIcons = #bar.icons
    for i, icon in ipairs(bar.icons) do
        local offset = (i - 1) * (iconWidth + spacing)

        if growDir == "RIGHT" then
            icon:SetPoint("LEFT", bar, "LEFT", offset, 0)
        elseif growDir == "LEFT" then
            icon:SetPoint("RIGHT", bar, "RIGHT", -offset, 0)
        elseif growDir == "DOWN" then
            offset = (i - 1) * (iconHeight + spacing)
            icon:SetPoint("TOP", bar, "TOP", 0, -offset)
        elseif growDir == "UP" then
            offset = (i - 1) * (iconHeight + spacing)
            icon:SetPoint("BOTTOM", bar, "BOTTOM", 0, offset)
        elseif growDir == "CENTER" then
            -- Center-based positioning: icons spread equally from center
            local totalWidth = (numIcons * iconWidth) + ((numIcons - 1) * spacing)
            local startX = -totalWidth / 2 + iconWidth / 2
            local x = startX + (i - 1) * (iconWidth + spacing)
            icon:SetPoint("CENTER", bar, "CENTER", x, 0)
        elseif growDir == "CENTER_VERTICAL" then
            -- Center-based vertical positioning: icons spread equally from center (top to bottom)
            local totalHeight = (numIcons * iconHeight) + ((numIcons - 1) * spacing)
            local startY = totalHeight / 2 - iconHeight / 2
            local y = startY - (i - 1) * (iconHeight + spacing)
            icon:SetPoint("CENTER", bar, "CENTER", 0, y)
        end

        icon:Show()
    end

    -- Update bar size to fit icons
    if numIcons == 0 then
        bar:SetSize(1, 1)
        return
    end

    if growDir == "RIGHT" or growDir == "LEFT" or growDir == "CENTER" then
        local totalWidth = (numIcons * iconWidth) + ((numIcons - 1) * spacing)
        bar:SetSize(totalWidth, iconHeight)
    else
        local totalHeight = (numIcons * iconHeight) + ((numIcons - 1) * spacing)
        bar:SetSize(iconWidth, totalHeight)
    end
end

---------------------------------------------------------------------------
-- LAYOUT VISIBLE ICONS (for hideNonUsable mode)
---------------------------------------------------------------------------
local function LayoutVisibleIcons(bar)
    if not bar or not bar.icons then return end

    local config = bar.config
    local growDir = config.growDirection or "RIGHT"
    local spacing = config.spacing or 4

    -- Calculate icon dimensions
    local aspectRatio = config.aspectRatioCrop or 1.0
    local iconWidth = config.iconSize or 36
    local iconHeight = iconWidth / aspectRatio

    -- Collect only visible icons (reuse scratch table to avoid per-call allocation)
    local visibleIcons = _visibleIconsScratch
    wipe(visibleIcons)
    for _, icon in ipairs(bar.icons) do
        if icon.isVisible ~= false then
            visibleIcons[#visibleIcons + 1] = icon
        end
    end

    -- PASS 1: Clear all points on ALL icons
    for _, icon in ipairs(bar.icons) do
        icon:ClearAllPoints()
    end

    -- PASS 2: Position only visible icons
    local numIcons = #visibleIcons
    for i, icon in ipairs(visibleIcons) do
        local offset = (i - 1) * (iconWidth + spacing)

        if growDir == "RIGHT" then
            icon:SetPoint("LEFT", bar, "LEFT", offset, 0)
        elseif growDir == "LEFT" then
            icon:SetPoint("RIGHT", bar, "RIGHT", -offset, 0)
        elseif growDir == "DOWN" then
            offset = (i - 1) * (iconHeight + spacing)
            icon:SetPoint("TOP", bar, "TOP", 0, -offset)
        elseif growDir == "UP" then
            offset = (i - 1) * (iconHeight + spacing)
            icon:SetPoint("BOTTOM", bar, "BOTTOM", 0, offset)
        elseif growDir == "CENTER" then
            -- Center-based positioning: icons spread equally from center
            local totalWidth = (numIcons * iconWidth) + ((numIcons - 1) * spacing)
            local startX = -totalWidth / 2 + iconWidth / 2
            local x = startX + (i - 1) * (iconWidth + spacing)
            icon:SetPoint("CENTER", bar, "CENTER", x, 0)
        elseif growDir == "CENTER_VERTICAL" then
            -- Center-based vertical positioning: icons spread equally from center (top to bottom)
            local totalHeight = (numIcons * iconHeight) + ((numIcons - 1) * spacing)
            local startY = totalHeight / 2 - iconHeight / 2
            local y = startY - (i - 1) * (iconHeight + spacing)
            icon:SetPoint("CENTER", bar, "CENTER", 0, y)
        end
    end

    -- Resize bar to fit only visible icons
    if numIcons == 0 then
        bar:SetSize(1, 1)
        return
    end

    if growDir == "RIGHT" or growDir == "LEFT" or growDir == "CENTER" then
        local totalWidth = (numIcons * iconWidth) + ((numIcons - 1) * spacing)
        bar:SetSize(totalWidth, iconHeight)
    else
        local totalHeight = (numIcons * iconHeight) + ((numIcons - 1) * spacing)
        bar:SetSize(iconWidth, totalHeight)
    end
end

---------------------------------------------------------------------------
-- UPDATE BAR ICONS (recreate icons for entries)
---------------------------------------------------------------------------
function CustomTrackers:UpdateBarIcons(bar)
    if not bar then return end

    local config = bar.config
    -- Use GetBarEntries to resolve entries from correct storage (profile or global/spec)
    local entries = GetBarEntries(config)

    -- Hide and clear existing icons
    for _, icon in ipairs(bar.icons or {}) do
        icon:Hide()
        icon:SetParent(nil)
    end
    bar.icons = {}

    if #entries == 0 then
        bar:SetSize(1, 1)
        if bar.bg then bar.bg:SetAlpha(0) end
        return
    end

    -- Create icons for each entry
    -- dynamicLayout bars must not have secure children (Show/Hide must work in combat)
    local clickable = config.clickableIcons and not config.dynamicLayout
    for i, entry in ipairs(entries) do
        local icon = CreateTrackerIcon(bar, clickable)
        StyleTrackerIcon(icon, config)

        -- Store entry reference
        icon.entry = entry
        icon.isVisible = true  -- Initialize visibility state for hideNonUsable tracking

        -- Set icon texture
        local info
        if entry.type == "spell" then
            info = GetCachedSpellInfo(entry.id)
        elseif entry.type == "slot" then
            info = GetCachedSlotInfo(entry.id)
        else
            info = GetCachedItemInfo(entry.id)
        end

        if info and info.icon then
            icon.tex:SetTexture(info.icon)
        else
            icon.tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end

        -- Set up secure button for clickable icons (if enabled)
        UpdateIconSecureAttributes(icon, entry, config)
        ApplyKeybindToTrackerIcon(icon)

        table_insert(bar.icons, icon)
    end

    -- Layout the icons (sets bar size)
    LayoutBarIcons(bar)

    -- Re-position bar with new size for edge-anchored growth
    -- This ensures the anchor edge stays fixed when icons are added/removed
    PositionBar(bar)

    -- Show background if there are icons
    if bar.bg then
        bar.bg:SetAlpha(config.bgOpacity or 0)
    end
end

---------------------------------------------------------------------------
-- COOLDOWN POLLING
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- ACTIVE SET MANAGEMENT (Performance optimization)
---------------------------------------------------------------------------
-- Instead of checking IsSpellUsable() on every update (50+ API calls/tick),
-- we pre-filter icons on spec/talent change and only update the active set.
-- This reduces update loop from O(all configured) to O(known spells only).

-- Bars that need a full RebuildActiveSet (with Show/Hide + layout) after combat ends.
-- During combat we update data but use alpha-based visibility to avoid ADDON_ACTION_BLOCKED.
local pendingActiveSetRebuilds = {}

-- Rebuild the active icon set for a bar
-- Called on: spec change, talent change, bar creation, hideNonUsable toggle
local function RebuildActiveSet(bar)
    if not bar then return end

    -- During combat lockdown, icon frames with SecureActionButtonTemplate children
    -- make Show/Hide protected. Use alpha-based visibility instead for those bars.
    -- Bars without secure children (dynamicLayout bars) can Show/Hide freely.
    -- Note: all icons on a bar share the same clickable state, so checking [1] suffices.
    local hasSecureChildren = bar.icons and bar.icons[1] and bar.icons[1].clickButton
    local inCombat = hasSecureChildren and InCombatLockdown()

    bar.activeIcons = bar.activeIcons or {}
    wipe(bar.activeIcons)

    local config = bar.config
    local hideNonUsable = config.hideNonUsable

    -- Performance: Track whether this bar has any spell entries (for lazy event registration)
    local hasSpells = false

    -- Iterate the FULL configured list (bar.icons), not activeIcons
    -- This ensures we pick up newly-talented spells when switching talent loadouts
    for _, icon in ipairs(bar.icons or {}) do
        local entry = icon.entry
        if entry and entry.id then
            if entry.type == "spell" then hasSpells = true end
            local isUsable = true
            if entry.type == "spell" then
                isUsable = IsSpellUsable(entry.id)
            elseif entry.type == "slot" then
                -- Slot entries: usable when an item is equipped in the slot
                local itemID = GetInventoryItemID("player", entry.id)
                isUsable = itemID ~= nil
            elseif entry.type == "item" then
                -- Items: check current usability (equipment or consumable count).
                -- Updated on ITEM_COUNT_CHANGED, not polled in DoUpdate.
                local count = GetItemStackCount(entry.id)
                isUsable = IsItemUsable(entry.id, count)
            end

            -- Only add usable spells to activeIcons (CPU optimization)
            -- This ensures we never process unknown spells in DoUpdate, regardless of hideNonUsable toggle
            if isUsable then
                table_insert(bar.activeIcons, icon)
                icon._usable = true
                icon.isVisible = true  -- Mark as visible for layout
                icon.tex:SetDesaturated(false)  -- Ensure known spells are full color
                if inCombat then
                    icon:SetAlpha(1)
                else
                    icon:Show()
                end
            else
                -- Unknown spell: hide if hideNonUsable is on, otherwise show desaturated (but not tracked)
                if hideNonUsable then
                    if inCombat then
                        icon:SetAlpha(0)
                    else
                        icon:Hide()
                    end
                    icon.isVisible = false  -- Mark as NOT visible for layout (allows collapse)
                else
                    if inCombat then
                        icon:SetAlpha(1)
                    else
                        icon:Show()
                    end
                    icon.isVisible = true  -- Still visible (just desaturated)
                    icon.tex:SetDesaturated(true)  -- Grey out unknown spells
                    icon.cooldown:Clear()  -- No cooldown tracking for unknown spells
                end
                icon._usable = false
            end
        end
    end

    -- Store hasSpells for lazy event registration
    bar.hasSpells = hasSpells

    -- Re-layout with the new active set (skip during combat — layout uses
    -- ClearAllPoints/SetPoint which are also protected on secure children)
    if inCombat then
        pendingActiveSetRebuilds[bar] = true
    else
        LayoutVisibleIcons(bar)
    end

    -- Performance: Update event registrations based on current bar configurations
    if CustomTrackers.UpdateEventRegistrations then
        CustomTrackers.UpdateEventRegistrations()
    end
end

-- Module-level reference for event handlers
CustomTrackers.RebuildActiveSet = RebuildActiveSet

function CustomTrackers:StartCooldownPolling(bar)
    if not bar then return end

    if bar.ticker then
        bar.ticker:Cancel()
    end

    -- Create update function that can be called from both ticker and events
    bar.DoUpdate = function()
        if not bar:IsShown() then return end

        local config = bar.config
        local hideNonUsable = config.hideNonUsable
        local showOnlyOnCooldown = config.showOnlyOnCooldown
        local showOnlyWhenActive = config.showOnlyWhenActive
        local showOnlyWhenOffCooldown = config.showOnlyWhenOffCooldown
        local showOnlyInCombat = config.showOnlyInCombat
        local dynamicLayout = config.dynamicLayout == true
        local showActiveState = config.showActiveState ~= false  -- Default true
        local stackColor = config.stackColor or {1, 1, 1, 1}
        local visibilityChanged = false

        -- PERFORMANCE: Iterate activeIcons (pre-filtered on spec/talent change)
        -- instead of all icons. This avoids 50+ IsSpellUsable() calls per update.
        for _, icon in ipairs(bar.activeIcons or bar.icons or {}) do
            local entry = icon.entry
            if entry and entry.id then
                local startTime, duration, enabled, isOnGCD, cooldownActive, cooldownDurObj
                local count = 0
                local maxCharges = 1
                local chargeStartTime, chargeDuration = 0, 0  -- For charge spell recharge display
                local chargeIsActive, chargeDurObj = false, nil

                if entry.type == "spell" then
                    startTime, duration, enabled, isOnGCD, cooldownActive, cooldownDurObj = GetSpellCooldownInfo(entry.id)
                    count, maxCharges, chargeStartTime, chargeDuration, chargeIsActive, chargeDurObj = GetSpellChargeCount(entry.id)
                elseif entry.type == "slot" then
                    local itemID = GetInventoryItemID("player", entry.id)
                    if itemID then
                        startTime, duration, enabled = GetItemCooldownInfo(itemID)
                        icon._usable = true
                    else
                        startTime, duration, enabled = 0, 0, false
                        icon._usable = false
                    end
                    isOnGCD = false
                else
                    startTime, duration, enabled = GetItemCooldownInfo(entry.id)
                    count = GetItemStackCount(entry.id, config.showItemCharges)
                    isOnGCD = false  -- Items don't have GCD
                    -- _usable for items is updated by ITEM_COUNT_CHANGED, not here.
                    -- Polling item counts every tick is wasteful and secret-prone.
                end

                -- Check if spell/item is currently active (casting/channeling/buff)
                local isActive, activeStartTime, activeDuration, activeType = false, nil, nil, nil
                if showActiveState then
                    if entry.type == "spell" then
                        isActive, activeStartTime, activeDuration, activeType = GetSpellActiveInfo(entry.id)
                    elseif entry.type == "slot" then
                        local itemID = GetInventoryItemID("player", entry.id)
                        if itemID then
                            isActive, activeStartTime, activeDuration, activeType = GetItemActiveInfo(itemID)
                        end
                    elseif entry.type == "item" then
                        isActive, activeStartTime, activeDuration, activeType = GetItemActiveInfo(entry.id)
                    end
                end

                -- Simplified cooldown handling - let Blizzard's Cooldown frame handle secrets
                local hideGCD = config.hideGCD ~= false

                -- Determine if on cooldown using API values directly
                -- Avoids frame-delay issues with IsVisible() on cooldown frames
                local isOnCD = false
                local rechargeActive = false  -- Track charge recharge separately (for visibility logic)

                -- If active, show active state progress instead of cooldown
                -- Skip active override when showOnlyOnCooldown: we need real CD state and swipe,
                -- not the buff duration (e.g., Power Word: Shield buff outlasting its cooldown)
                -- Skip active cooldown override for items/slots: show real item cooldown,
                -- not buff duration (trinkets/pots have meaningful cooldowns users want to track;
                -- active glow still indicates the buff is active)
                local isItemEntry = entry.type == "slot" or entry.type == "item"
                if isActive and activeStartTime and activeDuration and activeDuration > 0 and not showOnlyOnCooldown and not isItemEntry then
                    -- Active state: show buff/cast duration (reverse fill)
                    pcall(SafeSetReverse, icon.cooldown, true)
                    pcall(SafeSetCooldown, icon.cooldown, activeStartTime, activeDuration)
                    isOnCD = false  -- Active overrides cooldown state
                else
                    -- Normal cooldown display
                    local isChargeSpell = maxCharges > 1

                    icon.cooldown:SetReverse(false)

                    if isChargeSpell then
                        -- For charge spells: use charge cooldown values
                        if chargeDurObj and SafeSetCooldownFromDurationObject(icon.cooldown, chargeDurObj) then
                            rechargeActive = chargeIsActive == true
                        elseif chargeStartTime and chargeDuration then
                            -- Set cooldown first (pcall for secret value safety)
                            pcall(SafeSetCooldown, icon.cooldown, chargeStartTime, chargeDuration)
                            -- Check if cooldown is active AFTER setting it
                            rechargeActive = chargeIsActive == true or IsCooldownFrameActive(icon.cooldown)
                        else
                            icon.cooldown:Clear()
                        end

                        -- Control swipe for charge spells
                        if config.showRechargeSwipe then
                            pcall(SafeSetSwipeColor, icon.cooldown, 0, 0, 0, 0.6)
                            pcall(SafeSetDrawSwipe, icon.cooldown, true)
                        else
                            pcall(SafeSetSwipeColor, icon.cooldown, 0, 0, 0, 0)
                            pcall(SafeSetDrawSwipe, icon.cooldown, false)
                        end
                        pcall(SafeSetDrawEdge, icon.cooldown, false)

                        -- EXPLICIT show/hide (critical for cooldown visibility)
                        if rechargeActive then
                            icon.cooldown:Show()
                        else
                            icon.cooldown:Hide()
                        end

                        -- isOnCD for charge spells = out of charges
                        -- Use the new non-secret isActive signal when available; fall back
                        -- to the frame state only when we only have legacy numeric values.
                        local mainCDActive = cooldownActive == true
                        if cooldownActive == nil then
                            -- Temporarily set cooldown with MAIN spell cooldown values.
                            -- Main cooldown is only active when ALL charges are depleted.
                            icon.cooldown:Clear()
                            if cooldownDurObj and SafeSetCooldownFromDurationObject(icon.cooldown, cooldownDurObj) then
                                mainCDActive = IsCooldownFrameActive(icon.cooldown)
                            else
                                pcall(SafeSetCooldown, icon.cooldown, startTime, duration)
                                mainCDActive = IsCooldownFrameActive(icon.cooldown)
                            end

                            -- Restore charge cooldown values for display
                            if chargeDurObj and not SafeSetCooldownFromDurationObject(icon.cooldown, chargeDurObj) and chargeStartTime and chargeDuration then
                                pcall(SafeSetCooldown, icon.cooldown, chargeStartTime, chargeDuration)
                            elseif chargeStartTime and chargeDuration and not chargeDurObj then
                                pcall(SafeSetCooldown, icon.cooldown, chargeStartTime, chargeDuration)
                            end
                        end

                        -- Exclude GCD from triggering desaturation
                        -- Check both isOnGCD flag and duration <= 1.5s (GCD range)
                        if hideGCD then
                            local isJustGCD = isOnGCD
                            if not isJustGCD then
                                -- Fallback: check if main cooldown duration is within GCD range
                                local gcdCheckOk, gcdCheckResult = pcall(SafeCheckDuration, duration)
                                if gcdCheckOk and gcdCheckResult then
                                    isJustGCD = true
                                end
                            end
                            if isJustGCD then
                                mainCDActive = false
                            end
                        end

                        isOnCD = mainCDActive

                        -- Clear stale lastCast timestamps when spell is completely ready
                        -- (no recharge, no GCD = full charges, ready to cast)
                        if not rechargeActive and not isOnGCD then
                            chargeSpellLastCast[entry.id] = nil
                        end

                        -- Exclude GCD from rechargeActive for visibility purposes
                        -- Use isOnGCD from MAIN spell cooldown (not secret) to detect GCD
                        if hideGCD and rechargeActive then
                            if isOnGCD then
                                -- Main spell is on GCD. Could be just GCD (full charges) or
                                -- real recharge that started during GCD. Try to check charges.
                                local chargeCheckOk, hasMissingCharges = pcall(SafeCheckCharges, count, maxCharges)
                                if chargeCheckOk then
                                    if hasMissingCharges then
                                        -- We're missing charges = real recharge, keep showing
                                    else
                                        -- Full charges confirmed - this is just GCD
                                        -- Clear stale lastCast timestamp and hide
                                        chargeSpellLastCast[entry.id] = nil
                                        rechargeActive = false
                                    end
                                else
                                    -- Can't determine charge count (secret value)
                                    -- Fall back to checking if this spell was cast recently
                                    local lastCast = chargeSpellLastCast[entry.id]
                                    local now = GetTime()
                                    -- If spell was cast within last 120 seconds, it's likely recharging
                                    -- (most charge spells have recharge times under 60s, use 120s for safety)
                                    if lastCast and (now - lastCast) < 120 then
                                        -- Recently cast = real recharge, keep showing
                                    else
                                        -- Not cast recently = this is just GCD from another spell
                                        rechargeActive = false
                                    end
                                end
                            end
                            -- If isOnGCD = false, main spell not on GCD, so charge
                            -- cooldown must be real recharge - keep rechargeActive = true
                        end

                    else
                        -- Normal spell/item cooldown
                        if cooldownDurObj and SafeSetCooldownFromDurationObject(icon.cooldown, cooldownDurObj) then
                            -- DurationObject path handles secret cooldown values safely.
                        elseif startTime and duration then
                            pcall(SafeSetCooldown, icon.cooldown, startTime, duration)
                        end

                        pcall(SafeSetDrawSwipe, icon.cooldown, false)
                        pcall(SafeSetDrawEdge, icon.cooldown, false)

                        if hideGCD then
                            -- Check if this is just GCD (not a real cooldown)
                            -- isOnGCD from API may not be reliable for all spells
                            -- Also check if duration is within GCD range (1.5s base, 0.75s min with haste)
                            local isJustGCD = isOnGCD
                            if not isJustGCD then
                                -- Fallback: check if duration is within GCD range
                                local gcdCheckOk, gcdCheckResult = pcall(SafeCheckDuration, duration)
                                if gcdCheckOk and gcdCheckResult then
                                    isJustGCD = true
                                end
                            end

                            if isJustGCD then
                                -- It's just GCD - clear cooldown display, don't desaturate
                                icon.cooldown:Clear()
                                isOnCD = false
                            else
                                -- Real cooldown (> 1.5s duration)
                                if cooldownActive ~= nil then
                                    isOnCD = cooldownActive == true
                                else
                                    local checkSuccess, checkResult = pcall(SafeCheckCooldownActive, startTime, duration)
                                    if checkSuccess then
                                        isOnCD = checkResult
                                    else
                                        isOnCD = IsCooldownFrameActive(icon.cooldown)
                                    end
                                end
                            end
                        else
                            -- hideGCD is disabled, treat any cooldown as "on cooldown"
                            if cooldownActive ~= nil then
                                isOnCD = cooldownActive == true
                            else
                                local checkSuccess, checkResult = pcall(SafeCheckCooldownActive, startTime, duration)
                                if checkSuccess then
                                    isOnCD = checkResult
                                else
                                    isOnCD = IsCooldownFrameActive(icon.cooldown)
                                end
                            end
                        end
                    end
                end

                -- PERFORMANCE: Use cached usability from RebuildActiveSet()
                -- This eliminates 50+ IsSpellUsable() API calls per update tick.
                -- Usability is recalculated only on spec/talent change events.
                local isUsable = icon._usable ~= false

                -- Base visibility (Hide Non-Usable)
                local baseVisible = isUsable or (not hideNonUsable)

                -- Combat visibility check (alpha-based, never drives Show/Hide
                -- because icon frames may have SecureActionButton children
                -- that make Show/Hide protected during combat lockdown)
                local inCombat = UnitAffectingCombat("player")
                local combatVisible = (not showOnlyInCombat) or inCombat

                -- Dynamic layout visibility: icons truly hide and the bar collapses.
                -- Static layout: icons may use alpha=0 to preserve fixed slots.
                -- Note: combatVisible is NOT included here — it is handled via alpha
                -- in the shouldRender section below to avoid protected-frame errors.
                local layoutVisible = baseVisible
                if layoutVisible then
                    if showOnlyWhenActive then
                        layoutVisible = isActive
                    elseif showOnlyOnCooldown then
                        -- Show only during cooldown (isOnCD is never overridden by active state
                        -- when showOnlyOnCooldown is true, so it reflects the real CD)
                        -- For charge spells: also show when recharge is active (any charge on cooldown)
                        layoutVisible = isOnCD or rechargeActive
                    elseif showOnlyWhenOffCooldown then
                        -- Show only when ready (not on cooldown)
                        -- For charge spells with remaining charges, stay visible even during active state
                        -- (you can still cast the spell if you have charges)
                        local hasChargesRemaining = false
                        if maxCharges > 1 then
                            local chargeCheckOk, chargeCheckResult = pcall(function()
                                return count and count > 0
                            end)
                            hasChargesRemaining = chargeCheckOk and chargeCheckResult
                        end
                        layoutVisible = not isOnCD and (not isActive or hasChargesRemaining)
                    end
                end

                -- Combat-safe Show/Hide: icon frames with a SecureActionButton
                -- child (clickableIcons) make Show/Hide protected in combat.
                -- Fall back to alpha-based visibility only for those bars.
                local inCombatLockdown = icon.clickButton and InCombatLockdown()

                if dynamicLayout then
                    -- Track visibility state change (affects layout)
                    if layoutVisible ~= icon.isVisible then
                        visibilityChanged = true
                        icon.isVisible = layoutVisible
                        if layoutVisible then
                            if inCombatLockdown then
                                icon:SetAlpha(1)
                            else
                                icon:Show()
                            end
                        else
                            StopActiveGlow(icon)
                            if inCombatLockdown then
                                icon:SetAlpha(0)
                            else
                                icon:Hide()
                            end
                        end
                    end
                else
                    -- Static layout only tracks base visibility (hideNonUsable mode)
                    if baseVisible ~= icon.isVisible then
                        visibilityChanged = true
                        icon.isVisible = baseVisible
                        if baseVisible then
                            if inCombatLockdown then
                                icon:SetAlpha(1)
                            else
                                icon:Show()
                            end
                        else
                            StopActiveGlow(icon)
                            if inCombatLockdown then
                                icon:SetAlpha(0)
                            else
                                icon:Hide()
                            end
                        end
                    end
                end

                -- Apply visual state only if icon should render
                -- combatVisible is applied here (alpha-based) rather than in Show/Hide
                -- to avoid ADDON_ACTION_BLOCKED on secure child frames during combat
                local shouldRender = (dynamicLayout and layoutVisible or (not dynamicLayout and baseVisible)) and combatVisible
                if shouldRender then
                    if isActive and not showOnlyOnCooldown then
                        -- Active state: saturated + glow + full alpha
                        icon:SetAlpha(1)
                        icon.tex:SetDesaturated(false)
                        StartActiveGlow(icon, config)
                    elseif showOnlyWhenActive then
                        -- Static "Show Only When Active": keep slot, hide via alpha
                        StopActiveGlow(icon)
                        if dynamicLayout then
                            -- Dynamic layout would have hidden the icon already.
                            icon:SetAlpha(1)
                        else
                            icon:SetAlpha(0)
                        end
                        icon.tex:SetDesaturated(false)
                    elseif showOnlyOnCooldown then
                        StopActiveGlow(icon)
                        -- Determine desaturation based on noDesaturateWithCharges option
                        -- isOnCD = main cooldown active (0 charges) -> always desaturate
                        -- rechargeActive but not isOnCD = has charges remaining -> respect option
                        local shouldDesaturate = true
                        if config.noDesaturateWithCharges and not isOnCD and rechargeActive then
                            -- Has charges remaining, option enabled -> don't desaturate
                            shouldDesaturate = false
                        end

                        if dynamicLayout then
                            -- Dynamic layout shows only when on cooldown (or active handled above)
                            icon:SetAlpha(1)
                            icon.tex:SetDesaturated(shouldDesaturate)
                        else
                            -- Static layout: alpha-based visibility (preserves position)
                            -- For charge spells: show when recharge is active (any charge on cooldown)
                            if isOnCD or rechargeActive then
                                icon:SetAlpha(1)
                                icon.tex:SetDesaturated(shouldDesaturate)
                            else
                                icon:SetAlpha(0)
                                icon.tex:SetDesaturated(false)
                            end
                        end
                    elseif showOnlyWhenOffCooldown then
                        StopActiveGlow(icon)
                        if dynamicLayout then
                            -- Dynamic layout shows only when off cooldown
                            icon:SetAlpha(1)
                            icon.tex:SetDesaturated(false)
                        else
                            -- Static layout: alpha-based visibility (preserves position)
                            if not isOnCD then
                                icon:SetAlpha(1)
                                icon.tex:SetDesaturated(false)
                            else
                                icon:SetAlpha(0)
                                icon.tex:SetDesaturated(true)
                            end
                        end
                    else
                        -- Normal mode
                        StopActiveGlow(icon)
                        icon:SetAlpha(1)
                        if not isUsable then
                            -- Not usable but visible (hideNonUsable off): desaturated
                            icon.tex:SetDesaturated(true)
                            icon.cooldown:Clear()
                        elseif isOnCD then
                            -- On cooldown: desaturate icon
                            icon.tex:SetDesaturated(true)
                        else
                            -- Ready to use: normal color
                            icon.tex:SetDesaturated(false)
                        end
                    end
                else
                    -- Not rendering (e.g. showOnlyInCombat and out of combat)
                    StopActiveGlow(icon)
                    icon:SetAlpha(0)
                end

                -- Duration text: Always use Blizzard's built-in countdown
                -- (Styled in StyleTrackerIcon, handles secret values internally)
                icon.durationText:Hide()
                icon.cooldown:SetHideCountdownNumbers(config.hideDurationText == true)

                -- Update stack count (for items and spell charges)
                local showStack = (entry.type == "item") or (entry.type == "spell" and maxCharges > 1)

                if showStack then
                    -- Handle secret values: SetText handles them, but comparisons crash
                    local isSecret = IsSecretValue(count)
                    if isSecret then
                        -- Secret value: pass directly to SetText (it handles secrets)
                        icon.stackText:SetText(count)
                        icon.stackText:SetTextColor(stackColor[1], stackColor[2], stackColor[3], stackColor[4] or 1)
                        if not config.hideStackText then
                            icon.stackText:Show()
                        else
                            icon.stackText:Hide()
                        end
                    elseif count > 1 then
                        icon.stackText:SetText(count)
                        icon.stackText:SetTextColor(stackColor[1], stackColor[2], stackColor[3], stackColor[4] or 1)
                        if not config.hideStackText then
                            icon.stackText:Show()
                        else
                            icon.stackText:Hide()
                        end
                    elseif count == 1 then
                        icon.stackText:SetText("")
                        icon.stackText:Hide()
                    else
                        -- Show 0 in dimmed user color when depleted
                        icon.stackText:SetText("0")
                        icon.stackText:SetTextColor(stackColor[1] * 0.5, stackColor[2] * 0.5, stackColor[3] * 0.5, stackColor[4] or 1)
                        if not config.hideStackText then
                            icon.stackText:Show()
                        else
                            icon.stackText:Hide()
                        end
                    end
                else
                    icon.stackText:Hide()
                end

            end
        end

        -- Relayout if visibility changed (dynamic layout or hideNonUsable mode)
        -- Skip during combat only for bars with secure children (clickableIcons),
        -- where ClearAllPoints/SetPoint are protected. Layout syncs on combat end.
        -- Note: all icons on a bar share the same clickable state, so checking [1] suffices.
        if visibilityChanged then
            local hasSecureChildren = bar.icons and bar.icons[1] and bar.icons[1].clickButton
            if not hasSecureChildren or not InCombatLockdown() then
                LayoutVisibleIcons(bar)
            end
        end
    end

    -- Performance: Use slower fallback ticker (0.5s) since events handle immediate updates
    -- Events (SPELL_UPDATE_COOLDOWN, ACTIONBAR_UPDATE_COOLDOWN) call bar.DoUpdate() directly
    bar.ticker = C_Timer.NewTicker(0.5, bar.DoUpdate)
end

---------------------------------------------------------------------------
-- BAR DRAGGING (matches Datapanels pattern)
---------------------------------------------------------------------------
function CustomTrackers:SetupDragging(bar)
    if not bar then return end

    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetClampedToScreen(true)

    bar:SetScript("OnDragStart", function(self)
        if self.barID and _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("customTracker:" .. self.barID) then return end
        if not self.config.locked and not self.config.lockedToPlayer and not self.config.lockedToTarget then
            self:StartMoving()
        end
    end)

    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()

        -- Save the ANCHOR EDGE position based on growth direction
        -- This ensures icons don't shift when new ones are added
        local core = GetCore()
        local screenX, screenY = UIParent:GetCenter()
        local growDir = self.config.growDirection or "RIGHT"

        if growDir == "RIGHT" then
            -- Anchor at LEFT edge, Y stays center-based
            local left = self:GetLeft()
            local centerY = select(2, self:GetCenter())
            if left and screenX and centerY and screenY then
                self.config.offsetX = core:PixelRound(left - screenX)
                self.config.offsetY = core:PixelRound(centerY - screenY)
            end
        elseif growDir == "LEFT" then
            -- Anchor at RIGHT edge, Y stays center-based
            local right = self:GetRight()
            local centerY = select(2, self:GetCenter())
            if right and screenX and centerY and screenY then
                self.config.offsetX = core:PixelRound(right - screenX)
                self.config.offsetY = core:PixelRound(centerY - screenY)
            end
        elseif growDir == "DOWN" then
            -- Anchor at TOP edge, X stays center-based
            local centerX = self:GetCenter()
            local top = self:GetTop()
            if centerX and screenX and top and screenY then
                self.config.offsetX = core:PixelRound(centerX - screenX)
                self.config.offsetY = core:PixelRound(top - screenY)
            end
        elseif growDir == "UP" then
            -- Anchor at BOTTOM edge, X stays center-based
            local centerX = self:GetCenter()
            local bottom = self:GetBottom()
            if centerX and screenX and bottom and screenY then
                self.config.offsetX = core:PixelRound(centerX - screenX)
                self.config.offsetY = core:PixelRound(bottom - screenY)
            end
        else
            -- Fallback to center
            local barX, barY = self:GetCenter()
            if barX and screenX and barY and screenY then
                self.config.offsetX = core:PixelRound(barX - screenX)
                self.config.offsetY = core:PixelRound(barY - screenY)
            end
        end

        -- Re-position to ensure clean alignment
        PositionBar(self)

        -- Save to DB
        local db = GetDB()
        if db and db.bars then
            for _, barConfig in ipairs(db.bars) do
                if barConfig.id == self.barID then
                    barConfig.offsetX = self.config.offsetX
                    barConfig.offsetY = self.config.offsetY
                    break
                end
            end
        end

        -- Notify options UI to update sliders (if callback registered)
        if CustomTrackers.onPositionChanged then
            CustomTrackers.onPositionChanged(self.barID, self.config.offsetX, self.config.offsetY)
        end
    end)
end

---------------------------------------------------------------------------
-- REFRESH BAR POSITION (called when anchor settings change in options)
---------------------------------------------------------------------------
local function ApplyCustomTrackerAnchorOverride(barID)
    if type(barID) ~= "string" or barID == "" then
        return
    end
    if _G.QUI_ApplyFrameAnchor then
        _G.QUI_ApplyFrameAnchor("customTracker:" .. barID)
    end
end

function CustomTrackers:RefreshBarPosition(barID)
    local bar = self.activeBars[barID]
    if bar then
        PositionBar(bar)
        ApplyCustomTrackerAnchorOverride(barID)
    end
end

---------------------------------------------------------------------------
-- BAR FRAME POOL (reuse frames instead of leaking orphans)
---------------------------------------------------------------------------
local _barFramePool = {}  -- [barID] = frame (hidden, ready for reuse)
local _pendingBarDeletes = {}  -- [barID] = true (queued during combat lockdown)
local _pendingRefreshAll = false

local function BarHasSecureChildren(bar)
    local firstIcon = bar and bar.icons and bar.icons[1]
    return firstIcon and firstIcon.clickButton ~= nil
end

---------------------------------------------------------------------------
-- BAR CREATION (reuses existing frame if available)
---------------------------------------------------------------------------
function CustomTrackers:CreateBar(barID, config)
    if not barID or not config then return nil end

    if self.activeBars[barID] then
        return self.activeBars[barID]
    end

    -- Reuse pooled frame or create new one
    local bar = _barFramePool[barID]
    if bar then
        _barFramePool[barID] = nil
        bar:SetParent(UIParent)
    else
        bar = CreateFrame("Frame", "QUI_CustomTracker_" .. barID, UIParent, "BackdropTemplate")
        bar:SetFrameStrata("MEDIUM")
        -- Setup dragging (once per frame lifetime)
        self:SetupDragging(bar)
    end

    -- Apply HUD layer priority
    local core = GetCore()
    local hudLayering = core and core.db and core.db.profile and core.db.profile.hudLayering
    local layerPriority = hudLayering and hudLayering.customBars or 5
    local frameLevel = 50  -- Default fallback
    if core and core.GetHUDFrameLevel then
        frameLevel = core:GetHUDFrameLevel(layerPriority)
    end
    bar:SetFrameLevel(frameLevel)

    -- Store references (needed before PositionBar)
    bar.barID = barID
    bar.config = config

    -- Position using anchor system
    PositionBar(bar)

    -- Background
    bar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    local bgColor = config.bgColor or {0, 0, 0, 1}
    Helpers.SetFrameBackdropColor(bar, bgColor[1], bgColor[2], bgColor[3], config.bgOpacity or 0)

    -- Initialize icons array
    bar.icons = {}

    -- Create icons for entries
    self:UpdateBarIcons(bar)

    -- Build initial active icon set (performance optimization)
    -- This pre-filters icons to only known spells, avoiding expensive
    -- IsSpellUsable() checks in the update loop.
    RebuildActiveSet(bar)

    -- Start cooldown polling
    self:StartCooldownPolling(bar)

    self.activeBars[barID] = bar

    if config.enabled then
        bar:Show()
    else
        bar:Hide()
    end

    return bar
end

---------------------------------------------------------------------------
-- BAR DELETION (returns frame to pool for reuse)
---------------------------------------------------------------------------
function CustomTrackers:DeleteBar(barID)
    local bar = self.activeBars[barID]
    if bar then
        -- Bars with secure click children cannot be fully torn down in combat.
        -- Defer teardown to PLAYER_REGEN_ENABLED to avoid protected Hide/SetParent calls.
        if InCombatLockdown() and BarHasSecureChildren(bar) then
            _pendingBarDeletes[barID] = true
            return
        end

        _pendingBarDeletes[barID] = nil
        if bar.ticker then
            bar.ticker:Cancel()
            bar.ticker = nil
        end
        bar.DoUpdate = nil
        pendingActiveSetRebuilds[bar] = nil
        -- Clean up icons
        for _, icon in ipairs(bar.icons or {}) do
            icon:Hide()
            icon:ClearAllPoints()
            icon:SetParent(nil)
        end
        bar.icons = {}
        bar.activeIcons = nil
        -- Hide and pool the frame for reuse
        bar:Hide()
        bar:ClearAllPoints()
        self.activeBars[barID] = nil
        _barFramePool[barID] = bar
    end
end

---------------------------------------------------------------------------
-- UPDATE SINGLE BAR
---------------------------------------------------------------------------
function CustomTrackers:UpdateBar(barID)
    local bar = self.activeBars[barID]
    if not bar then return end

    local db = GetDB()
    if not db or not db.bars then return end

    for _, barConfig in ipairs(db.bars) do
        if barConfig.id == barID then
            bar.config = barConfig

            -- Update background
            local bgColor = barConfig.bgColor or {0, 0, 0, 1}
            Helpers.SetFrameBackdropColor(bar, bgColor[1], bgColor[2], bgColor[3], barConfig.bgOpacity or 0)

            -- Update icons
            self:UpdateBarIcons(bar)

            -- Rebuild active icon set (handles hideNonUsable toggle, etc.)
            RebuildActiveSet(bar)

            -- Show/hide
            if barConfig.enabled then
                bar:Show()
            else
                bar:Hide()
            end

            ApplyCustomTrackerAnchorOverride(barID)
            break
        end
    end
end

---------------------------------------------------------------------------
-- REFRESH ALL BARS
---------------------------------------------------------------------------
function CustomTrackers:RefreshAll()
    local db = GetDB()

    -- Refreshing can delete/recreate secure frames (clickable icons), which is forbidden
    -- during combat lockdown. Queue one refresh pass for after combat ends.
    if InCombatLockdown() then
        local hasSecureWork = false

        for _, bar in pairs(self.activeBars) do
            if BarHasSecureChildren(bar) then
                hasSecureWork = true
                break
            end
        end

        if not hasSecureWork and db and db.bars then
            for _, barConfig in ipairs(db.bars) do
                if barConfig and barConfig.clickableIcons and not barConfig.dynamicLayout then
                    hasSecureWork = true
                    break
                end
            end
        end

        if hasSecureWork then
            _pendingRefreshAll = true
            return
        end
    end

    _pendingRefreshAll = false

    -- Delete all existing bars
    for barID in pairs(self.activeBars) do
        self:DeleteBar(barID)
    end

    -- Recreate from DB
    if not db or not db.bars then return end

    for _, barConfig in ipairs(db.bars) do
        -- Legacy migration: clickableIcons and dynamicLayout are mutually exclusive.
        -- If both are enabled (from an older profile), dynamicLayout wins.
        if barConfig.dynamicLayout and barConfig.clickableIcons then
            barConfig.clickableIcons = false
        end
        if barConfig.id then
            self:CreateBar(barConfig.id, barConfig)
        end
    end

    -- Performance: Update lazy event registrations after all bars are created
    if CustomTrackers.UpdateEventRegistrations then
        CustomTrackers.UpdateEventRegistrations()
    end

    -- Keep frame-anchoring dropdown targets in sync with dynamic tracker bars.
    if ns.QUI_Anchoring and ns.QUI_Anchoring.RegisterAllFrameTargets then
        ns.QUI_Anchoring:RegisterAllFrameTargets()
    end
    if _G.QUI_ApplyAllFrameAnchors then
        _G.QUI_ApplyAllFrameAnchors()
    end
    if _G.QUI_RefreshCustomTrackersVisibility then
        _G.QUI_RefreshCustomTrackersVisibility()
    end
end

function CustomTrackers:CreateNewBar(displayName)
    local db = GetDB()
    if not db then
        return nil, nil, "Custom tracker database is not available."
    end

    db.bars = db.bars or {}

    local core = GetCore()
    local barID = (core and core.GenerateUniqueTrackerID and core:GenerateUniqueTrackerID())
        or ("tracker" .. tostring(GetTime()):gsub("%D", ""))
    local barConfig = CreateFreshBarConfig(barID, displayName)

    table_insert(db.bars, barConfig)
    self:CreateBar(barID, barConfig)

    if self.UpdateEventRegistrations then
        self.UpdateEventRegistrations()
    end

    self:RegisterDynamicLayoutElement(barID)

    if ns.QUI_Anchoring and ns.QUI_Anchoring.RegisterAllFrameTargets then
        ns.QUI_Anchoring:RegisterAllFrameTargets()
    end
    if _G.QUI_ApplyAllFrameAnchors then
        _G.QUI_ApplyAllFrameAnchors()
    end
    if _G.QUI_RefreshCustomTrackersVisibility then
        _G.QUI_RefreshCustomTrackersVisibility()
    end

    return barConfig, #db.bars
end

function CustomTrackers:RegisterDynamicLayoutElement(barID)
    local elementKey = RegisterTrackerLayoutElement and RegisterTrackerLayoutElement(barID)
    local uiModule = ns.QUI_LayoutMode_UI
    if uiModule and uiModule._RebuildDrawer then
        uiModule:_RebuildDrawer()
    end
    return elementKey
end

function CustomTrackers:UnregisterDynamicLayoutElement(barID)
    if type(barID) ~= "string" or barID == "" then
        return
    end

    local elementKey = "customTracker:" .. barID
    local um = ns.QUI_LayoutMode
    if um then
        um:UnregisterElement(elementKey)
    end

    local settingsPanel = ns.QUI_LayoutMode_Settings
    if settingsPanel and settingsPanel._providers then
        settingsPanel._providers[elementKey] = nil
        if settingsPanel._currentKey == elementKey then
            settingsPanel._currentKey = nil
        end
    end

    if ns.FRAME_ANCHOR_INFO then
        ns.FRAME_ANCHOR_INFO[elementKey] = nil
    end

    local uiModule = ns.QUI_LayoutMode_UI
    if uiModule and uiModule._RebuildDrawer then
        uiModule:_RebuildDrawer()
    end
end

local function ProcessPendingBarOperations()
    if InCombatLockdown() then return end

    if _pendingRefreshAll then
        _pendingRefreshAll = false
        CustomTrackers:RefreshAll()
        return
    end

    for barID in pairs(_pendingBarDeletes) do
        _pendingBarDeletes[barID] = nil
        CustomTrackers:DeleteBar(barID)
    end
end

---------------------------------------------------------------------------
-- ENTRY MANAGEMENT
---------------------------------------------------------------------------
function CustomTrackers:AddEntry(barID, entryType, entryID, specKeyOverride)
    local db = GetDB()
    if not db or not db.bars then return false end

    for _, barConfig in ipairs(db.bars) do
        if barConfig.id == barID then
            -- Determine target entries table based on spec-specific mode
            local entries
            local specKey
            
            if barConfig.specSpecificSpells then
                -- Spec-specific mode: use global storage
                specKey = specKeyOverride or GetCurrentSpecKey()
                if not specKey then
                    return false
                end
                
                local globalDB = GetGlobalDB()
                if not globalDB then return false end
                
                if not globalDB.specTrackerSpells then
                    globalDB.specTrackerSpells = {}
                end
                if not globalDB.specTrackerSpells[barID] then
                    globalDB.specTrackerSpells[barID] = {}
                end
                if not globalDB.specTrackerSpells[barID][specKey] then
                    globalDB.specTrackerSpells[barID][specKey] = {}
                end
                
                entries = globalDB.specTrackerSpells[barID][specKey]
            else
                -- Normal mode: use profile entries
                if not barConfig.entries then barConfig.entries = {} end
                entries = barConfig.entries
            end

            -- Check for duplicates
            for _, entry in ipairs(entries) do
                if entry.type == entryType and entry.id == entryID then
                    return false  -- Already exists
                end
            end

            table_insert(entries, {
                type = entryType,
                id = entryID,
            })

            -- Refresh the bar (only if viewing current spec or not spec-specific)
            if self.activeBars[barID] then
                local currentSpec = GetCurrentSpecKey()
                if not barConfig.specSpecificSpells or specKey == currentSpec then
                    self.activeBars[barID].config = barConfig
                    self:UpdateBarIcons(self.activeBars[barID])
                    RebuildActiveSet(self.activeBars[barID])
                end
            end

            return true
        end
    end
    return false
end

function CustomTrackers:RemoveEntry(barID, entryType, entryID, specKeyOverride)
    local db = GetDB()
    if not db or not db.bars then return false end

    for _, barConfig in ipairs(db.bars) do
        if barConfig.id == barID then
            -- Determine target entries table based on spec-specific mode
            local entries
            local specKey
            
            if barConfig.specSpecificSpells then
                -- Spec-specific mode: use global storage
                specKey = specKeyOverride or GetCurrentSpecKey()
                if not specKey then
                    return false
                end
                
                local globalDB = GetGlobalDB()
                if not globalDB then return false end
                
                if not globalDB.specTrackerSpells or
                   not globalDB.specTrackerSpells[barID] or
                   not globalDB.specTrackerSpells[barID][specKey] then
                    return false
                end
                
                entries = globalDB.specTrackerSpells[barID][specKey]
            else
                -- Normal mode: use profile entries
                entries = barConfig.entries
            end
            
            if entries then
                for i, entry in ipairs(entries) do
                    if entry.type == entryType and entry.id == entryID then
                        table_remove(entries, i)

                        -- Refresh the bar (only if viewing current spec or not spec-specific)
                        if self.activeBars[barID] then
                            local currentSpec = GetCurrentSpecKey()
                            if not barConfig.specSpecificSpells or specKey == currentSpec then
                                self.activeBars[barID].config = barConfig
                                self:UpdateBarIcons(self.activeBars[barID])
                                RebuildActiveSet(self.activeBars[barID])
                            end
                        end

                        return true
                    end
                end
            end
        end
    end
    return false
end

function CustomTrackers:MoveEntry(barID, entryIndex, direction, specKeyOverride)
    local db = GetDB()
    if not db or not db.bars then return false end

    for _, barConfig in ipairs(db.bars) do
        if barConfig.id == barID then
            -- Determine target entries table based on spec-specific mode
            local entries
            local specKey
            
            if barConfig.specSpecificSpells then
                -- Spec-specific mode: use global storage
                specKey = specKeyOverride or GetCurrentSpecKey()
                if not specKey then
                    return false
                end
                
                local globalDB = GetGlobalDB()
                if not globalDB or not globalDB.specTrackerSpells or
                   not globalDB.specTrackerSpells[barID] or
                   not globalDB.specTrackerSpells[barID][specKey] then
                    return false
                end
                
                entries = globalDB.specTrackerSpells[barID][specKey]
            else
                -- Normal mode: use profile entries
                entries = barConfig.entries
            end
            
            if not entries then return false end

            local newIndex = entryIndex + direction
            if newIndex < 1 or newIndex > #entries then return false end

            -- Swap entries
            local entry = table_remove(entries, entryIndex)
            table_insert(entries, newIndex, entry)

            -- Refresh bar display (only if viewing current spec or not spec-specific)
            if self.activeBars[barID] then
                local currentSpec = GetCurrentSpecKey()
                if not barConfig.specSpecificSpells or specKey == currentSpec then
                    self.activeBars[barID].config = barConfig
                    self:UpdateBarIcons(self.activeBars[barID])
                    RebuildActiveSet(self.activeBars[barID])
                end
            end
            return true
        end
    end
    return false
end

---------------------------------------------------------------------------
-- GLOBAL REFRESH FUNCTION
---------------------------------------------------------------------------
_G.QUI_RefreshCustomTrackers = function()
    -- Use local CustomTrackers directly since QUICore might not be set yet
    if CustomTrackers then
        CustomTrackers:RefreshAll()
    end
end

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------
-- Debounce flag for talent changes (prevents stacking timers on rapid talent swaps)
local pendingTalentRebuild = false

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
initFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
initFrame:RegisterEvent("ITEM_COUNT_CHANGED")
-- Performance: high-frequency combat events are registered lazily via UpdateEventRegistrations()
-- only when at least one active bar needs them. This avoids wasted processing when
-- the user has no spell-tracking or active-state bars configured.
-- Spec change detection for spec-specific spells
initFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
-- Talent change detection for active icon rebuild (talent loadout swaps)
initFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
-- Pet change detection (warlock demons, hunter pets with unique abilities)
initFrame:RegisterEvent("UNIT_PET")
-- Combat state changes for showOnlyInCombat icon visibility
initFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
initFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

-- Performance: Lazy event registration for high-frequency combat events.
-- Only register SPELL_UPDATE_COOLDOWN, ACTIONBAR_UPDATE_COOLDOWN, UNIT_AURA,
-- and spellcast events when at least one bar actually needs them.
local _cooldownEventsRegistered = false
-- _activeStateEventsRegistered declared above (forward declaration for aura dispatcher)

local function UpdateEventRegistrations()
    local needsCooldownEvents = false
    local needsActiveStateEvents = false

    for _, bar in pairs(CustomTrackers.activeBars) do
        if bar and bar.config then
            -- Any bar with spell entries needs cooldown events
            if bar.hasSpells then
                needsCooldownEvents = true
            end
            -- Any bar with active state enabled needs aura/spellcast events
            if bar.config.showActiveState ~= false then
                needsActiveStateEvents = true
            end
        end
    end

    -- Also register cooldown events if any bar exists (items have cooldowns too)
    if next(CustomTrackers.activeBars) then
        needsCooldownEvents = true
    end

    if needsCooldownEvents and not _cooldownEventsRegistered then
        _cooldownEventsRegistered = true
        initFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        initFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
    elseif not needsCooldownEvents and _cooldownEventsRegistered then
        _cooldownEventsRegistered = false
        initFrame:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
        initFrame:UnregisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
    end

    if needsActiveStateEvents and not _activeStateEventsRegistered then
        _activeStateEventsRegistered = true
        -- UNIT_AURA handled by centralized dispatcher subscription
        initFrame:RegisterEvent("UNIT_SPELLCAST_START")
        initFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
        initFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        initFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
        initFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    elseif not needsActiveStateEvents and _activeStateEventsRegistered then
        _activeStateEventsRegistered = false
        initFrame:UnregisterEvent("UNIT_SPELLCAST_START")
        initFrame:UnregisterEvent("UNIT_SPELLCAST_STOP")
        initFrame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        initFrame:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_START")
        initFrame:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    end
end
CustomTrackers.UpdateEventRegistrations = UpdateEventRegistrations
initFrame:SetScript("OnEvent", function(self, event, ...)
    -- Spec change: refresh all bars to load spec-appropriate spells
    -- PLAYER_SPECIALIZATION_CHANGED only fires for player, no unit check needed
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Memory cleanup: wipe charge-spell and info caches on spec change.
        -- Data is cheap to re-derive from the next DoUpdate cycle and prevents
        -- unbounded accumulation across specs.
        wipe(knownChargeSpells)
        wipe(chargeSpellLastCast)
        wipe(CustomTrackers.infoCache)

        -- Small delay to ensure spec info is fully updated
        C_Timer.After(0.1, function()
            -- RefreshAll calls Hide() which is protected — defer if in combat
            if InCombatLockdown() then
                local f = CreateFrame("Frame")
                f:RegisterEvent("PLAYER_REGEN_ENABLED")
                f:SetScript("OnEvent", function(s)
                    s:UnregisterAllEvents()
                    for _, bar in pairs(CustomTrackers.activeBars) do
                        if bar then RebuildActiveSet(bar) end
                    end
                    CustomTrackers:RefreshAll()
                end)
                return
            end
            -- Rebuild active icon sets for all bars (performance optimization)
            for _, bar in pairs(CustomTrackers.activeBars) do
                if bar then
                    RebuildActiveSet(bar)
                end
            end
            CustomTrackers:RefreshAll()
        end)
        return
    end

    -- Talent change: rebuild active icon sets (handles talent loadout swaps)
    -- When you switch talents within the same spec, newly-talented spells
    -- need to be added to activeIcons and un-talented ones removed.
    if event == "PLAYER_TALENT_UPDATE" then
        -- Debounce: prevent stacking timers if event fires rapidly
        if pendingTalentRebuild then return end
        pendingTalentRebuild = true
        C_Timer.After(0.1, function()
            pendingTalentRebuild = false
            for _, bar in pairs(CustomTrackers.activeBars) do
                if bar then
                    RebuildActiveSet(bar)
                end
            end
        end)
        return
    end

    -- Pet change: rebuild active icon sets (warlock demons, hunter pets)
    -- When summoning a different pet, old pet abilities become unavailable
    -- and new pet abilities need to be picked up.
    if event == "UNIT_PET" then
        local unit = ...
        if unit == "player" then
            -- Small delay to ensure pet spell info is fully updated
            C_Timer.After(0.2, function()
                for _, bar in pairs(CustomTrackers.activeBars) do
                    if bar then
                        RebuildActiveSet(bar)
                        -- Immediately apply visibility logic to prevent flash
                        -- (e.g., showOnlyOnCooldown would otherwise briefly show the icon)
                        if bar.DoUpdate then
                            bar.DoUpdate()
                        end
                    end
                end
            end)
        end
        return
    end

    -- Combat state change: update icon visibility
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        -- After combat ends, sync bars that used alpha-based visibility during combat.
        -- Data (activeIcons, _usable) is already current — just do proper Show/Hide + layout.
        if event == "PLAYER_REGEN_ENABLED" then
            for bar in pairs(pendingActiveSetRebuilds) do
                -- Validate bar is still active (may have been deleted during combat)
                if bar and bar.barID and CustomTrackers.activeBars[bar.barID] == bar then
                    -- Sync Show/Hide state to match the alpha-based visibility set during combat
                    for _, icon in ipairs(bar.icons or {}) do
                        if icon.isVisible then
                            icon:Show()
                        else
                            icon:Hide()
                        end
                    end
                    LayoutVisibleIcons(bar)
                end
            end
            wipe(pendingActiveSetRebuilds)
            ProcessPendingBarOperations()
        end

        for _, bar in pairs(CustomTrackers.activeBars) do
            if bar and bar:IsShown() and bar.DoUpdate then
                bar.DoUpdate()
            end
        end
        return
    end

    if event == "SPELL_UPDATE_USABLE" then
        -- Spell usability updates can happen after login/spec swaps; re-apply secure
        -- click attributes so spell icons don't stay non-clickable after info resolves.
        for _, bar in pairs(CustomTrackers.activeBars) do
            if bar and bar.config and bar.icons then
                for _, icon in ipairs(bar.icons) do
                    if icon.entry and icon.entry.type == "spell" then
                        UpdateIconSecureAttributes(icon, icon.entry, bar.config)
                    end
                end
            end
            if bar and bar:IsShown() and bar.DoUpdate then
                bar.DoUpdate()
            end
        end
        return
    end

    -- Performance: Throttled event-driven cooldown updates
    -- SPELL_UPDATE_COOLDOWN, ACTIONBAR_UPDATE_COOLDOWN, UNIT_AURA, and spellcast events
    -- can all fire multiple times per frame/GCD. Instead of calling DoUpdate on every event,
    -- we coalesce them with a minimum interval to prevent redundant full-bar scans.
    if event == "SPELL_UPDATE_COOLDOWN" or event == "ACTIONBAR_UPDATE_COOLDOWN" then
        -- Frame-show coalescing: batches rapid cooldown events within the
        -- same render frame into a single DoUpdate pass (zero allocation).
        if next(CustomTrackers.activeBars) then
            _ctCoalesceFrame:Show()
        end
        return
    end

    -- Active state events (casting/channeling/aura) - update bars with showActiveState enabled
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_STOP" or
       event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_CHANNEL_START" or
       event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        local unit, _, spellID = ...
        if unit == "player" then
            -- Track charge spell casts for GCD detection
            if event == "UNIT_SPELLCAST_SUCCEEDED" and spellID then
                local cachedMaxCharges = knownChargeSpells[spellID]
                if cachedMaxCharges and cachedMaxCharges > 1 then
                    chargeSpellLastCast[spellID] = GetTime()
                end
            end
            -- Throttle: reuse same coalescing as cooldown events
            local now = GetTime()
            if (now - _lastEventUpdate) >= _eventUpdateThrottle then
                _lastEventUpdate = now
                _eventUpdatePending = false
                for _, bar in pairs(CustomTrackers.activeBars) do
                    if bar and bar:IsShown() and bar.DoUpdate and bar.config and bar.config.showActiveState ~= false then
                        bar.DoUpdate()
                    end
                end
            elseif not _eventUpdatePending then
                _eventUpdatePending = true
                C_Timer.After(_eventUpdateThrottle, function()
                    _eventUpdatePending = false
                    _lastEventUpdate = GetTime()
                    for _, bar in pairs(CustomTrackers.activeBars) do
                        if bar and bar:IsShown() and bar.DoUpdate and bar.config and bar.config.showActiveState ~= false then
                            bar.DoUpdate()
                        end
                    end
                end)
            end
        end
        return
    end

    -- UNIT_AURA handled by centralized dispatcher subscription

    if event == "PLAYER_EQUIPMENT_CHANGED" then
        local slot = ...
        if slot then
            -- Invalidate cache for the changed slot
            CustomTrackers.infoCache["slot_" .. slot] = nil

            -- Check if any bar has a slot entry matching this slot
            local hasSlotEntry = false
            for _, bar in pairs(CustomTrackers.activeBars) do
                for _, icon in ipairs(bar.icons or {}) do
                    if icon.entry and icon.entry.type == "slot" and icon.entry.id == slot then
                        hasSlotEntry = true
                        -- Update icon texture immediately
                        local info = GetCachedSlotInfo(slot)
                        if info and info.icon then
                            icon.tex:SetTexture(info.icon)
                        else
                            icon.tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                        end
                        -- Defer secure attribute updates if in combat
                        if InCombatLockdown() then
                            icon._pendingSecureUpdate = true
                        else
                            UpdateIconSecureAttributes(icon, icon.entry, bar.config)
                        end
                    end
                end
            end

            -- Rebuild active sets and trigger DoUpdate for affected bars
            if hasSlotEntry then
                for _, bar in pairs(CustomTrackers.activeBars) do
                    local barHasSlot = false
                    for _, icon in ipairs(bar.icons or {}) do
                        if icon.entry and icon.entry.type == "slot" and icon.entry.id == slot then
                            barHasSlot = true
                            break
                        end
                    end
                    if barHasSlot then
                        RebuildActiveSet(bar)
                        if bar.DoUpdate then bar.DoUpdate() end
                    end
                end
            end
        end
        return
    end

    -- Item count changed: update _usable for item entries and re-layout affected bars.
    -- This is the ONLY place item usability is updated (not in DoUpdate),
    -- avoiding secret value polling in the per-tick update loop.
    if event == "ITEM_COUNT_CHANGED" then
        local itemID = ...
        for _, bar in pairs(CustomTrackers.activeBars) do
            local barAffected = false
            for _, icon in ipairs(bar.icons or {}) do
                if icon.entry and icon.entry.type == "item" then
                    -- Update specific item or all items if no itemID provided
                    if not itemID or icon.entry.id == itemID then
                        local count = GetItemStackCount(icon.entry.id, bar.config and bar.config.showItemCharges)
                        icon._usable = IsItemUsable(icon.entry.id, count)
                        barAffected = true
                    end
                end
            end
            if barAffected then
                RebuildActiveSet(bar)
                if bar.DoUpdate then bar.DoUpdate() end
            end
        end
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        local core = GetCore()
        if core then
            core.CustomTrackers = CustomTrackers
        end

        -- Memory cleanup: wipe caches on world entry to prevent unbounded growth
        -- across long play sessions. Data re-populates naturally from DoUpdate.
        wipe(chargeSpellLastCast)
        wipe(CustomTrackers.infoCache)

        C_Timer.After(0.6, function()
            CustomTrackers:RefreshAll()
            -- Apply HUD visibility instantly to prevent flash on /reload while mounted.
            if _G.QUI_RefreshCustomTrackersVisibility then
                _G.QUI_RefreshCustomTrackersVisibility()
            end
        end)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- Item info loaded, refresh bars to update any "?" icons and click buttons.
        local itemID = ...
        if itemID then
            -- Clear cache for this item so it gets re-fetched
            CustomTrackers.infoCache["item_" .. itemID] = nil
            -- Quick refresh of all bars (items and slot entries whose resolved itemID matches)
            for _, bar in pairs(CustomTrackers.activeBars) do
                for _, icon in ipairs(bar.icons or {}) do
                    if icon.entry and icon.entry.type == "item" and icon.entry.id == itemID then
                        local info = GetCachedItemInfo(itemID)
                        if info and info.icon then
                            icon.tex:SetTexture(info.icon)
                        end
                        -- Re-apply secure attributes once item info is available.
                        if InCombatLockdown() then
                            icon._pendingSecureUpdate = true
                        else
                            UpdateIconSecureAttributes(icon, icon.entry, bar.config)
                        end
                    elseif icon.entry and icon.entry.type == "slot" then
                        -- Check if this slot's current item matches the loaded itemID
                        local slotItemID = GetInventoryItemID("player", icon.entry.id)
                        if slotItemID == itemID then
                            -- Invalidate slot cache so it re-fetches with the now-available item info
                            CustomTrackers.infoCache["slot_" .. icon.entry.id] = nil
                            local info = GetCachedSlotInfo(icon.entry.id)
                            if info and info.icon then
                                icon.tex:SetTexture(info.icon)
                            end
                            -- Keep slot clickability in sync when delayed item data resolves.
                            if InCombatLockdown() then
                                icon._pendingSecureUpdate = true
                            else
                                UpdateIconSecureAttributes(icon, icon.entry, bar.config)
                            end
                        end
                    end
                end
            end
        end
    end
end)

---------------------------------------------------------------------------
-- VISIBILITY SYSTEM
---------------------------------------------------------------------------

-- During Edit Mode, fade-outs are suspended so trackers remain visible.
local IsInEditMode = Helpers.IsEditModeShown

local CustomTrackersVisibility = {
    currentlyHidden = false,
    isFading = false,
    fadeStart = 0,
    fadeStartAlpha = 1,
    fadeTargetAlpha = 1,
    fadeFrame = nil,
    mouseOver = false,
    mouseoverDetector = nil,
    anchoringPreviewAll = false,
    anchoringPreviewAlpha = 0.5,
    pendingPreviewSync = false,
}

local function GetCustomTrackersVisibilitySettings()
    local core = GetCore()
    if not core or not core.db or not core.db.profile then return nil end
    return core.db.profile.customTrackersVisibility
end

local function GetCustomTrackerFrames(includeAllBars)
    local frames = {}
    if CustomTrackers and CustomTrackers.activeBars then
        for _, bar in pairs(CustomTrackers.activeBars) do
            if bar and bar.config and (includeAllBars or (bar.config.enabled and bar:IsShown())) then
                table_insert(frames, bar)
            end
        end
    end
    return frames
end

local function IsSecureBarInCombat(bar)
    if not bar or not InCombatLockdown() then
        return false
    end
    local firstIcon = bar.icons and bar.icons[1]
    return firstIcon and firstIcon.clickButton
end

local function SetBarShownForPreview(bar, shouldShow)
    if not bar or not bar.config then
        return
    end

    if shouldShow then
        if not bar:IsShown() then
            if IsSecureBarInCombat(bar) then
                CustomTrackersVisibility.pendingPreviewSync = true
            else
                bar:Show()
            end
        end
    else
        if bar:IsShown() then
            if IsSecureBarInCombat(bar) then
                CustomTrackersVisibility.pendingPreviewSync = true
            else
                bar:Hide()
            end
        end
    end
end

local function ApplyAnchoringPreviewState()
    local frames = GetCustomTrackerFrames(true)
    for _, bar in ipairs(frames) do
        SetBarShownForPreview(bar, true)
        if bar:IsShown() then
            bar:SetAlpha(CustomTrackersVisibility.anchoringPreviewAlpha)
        end
    end
end

local function RestoreAfterAnchoringPreview()
    local frames = GetCustomTrackerFrames(true)
    for _, bar in ipairs(frames) do
        local shouldShow = bar.config and bar.config.enabled
        SetBarShownForPreview(bar, shouldShow == true)
        if shouldShow and bar:IsShown() then
            bar:SetAlpha(1)
        end
    end
end

local function ShouldCustomTrackersBeVisible()
    local vis = GetCustomTrackersVisibilitySettings()
    if not vis then return true end

    local ignoreHideRules = vis.dontHideInDungeonsRaids and Helpers.IsPlayerInDungeonOrRaid and Helpers.IsPlayerInDungeonOrRaid()
    if not ignoreHideRules then
        -- Hide rules override show conditions.
        if vis.hideWhenMounted and Helpers.IsPlayerMounted() then return false end
        if vis.hideWhenFlying and Helpers.IsPlayerFlying() then return false end
        if vis.hideWhenSkyriding and Helpers.IsPlayerSkyriding() then return false end
    end

    -- Show Always overrides all conditions
    if vis.showAlways then return true end

    -- OR logic: show if ANY condition is met
    if vis.showWhenTargetExists and UnitExists("target") then return true end
    if vis.showInCombat and UnitAffectingCombat("player") then return true end
    if vis.showInGroup and IsInGroup() then return true end
    if vis.showInInstance and IsPlayerInInstance() then return true end
    if vis.showOnMouseover and CustomTrackersVisibility.mouseOver then return true end

    return false
end

local function OnCustomTrackersFadeUpdate(self, elapsed)
    local now = GetTime()
    local vis = GetCustomTrackersVisibilitySettings()
    local duration = vis and vis.fadeDuration or 0.2

    local progress = (now - CustomTrackersVisibility.fadeStart) / duration
    if progress >= 1 then
        progress = 1
        CustomTrackersVisibility.isFading = false
        self:SetScript("OnUpdate", nil)
    end

    local alpha = CustomTrackersVisibility.fadeStartAlpha +
        (CustomTrackersVisibility.fadeTargetAlpha - CustomTrackersVisibility.fadeStartAlpha) * progress

    local frames = GetCustomTrackerFrames()
    for _, frame in ipairs(frames) do
        frame:SetAlpha(alpha)
    end
end

local function StartCustomTrackersFade(targetAlpha)
    -- Don't fade out during Edit Mode
    if targetAlpha < 1 and IsInEditMode() then return end

    local frames = GetCustomTrackerFrames()
    if #frames == 0 then return end

    local currentAlpha = frames[1]:GetAlpha()

    -- Skip if already at target
    if math.abs(currentAlpha - targetAlpha) < 0.01 and not CustomTrackersVisibility.isFading then
        return
    end

    CustomTrackersVisibility.fadeStart = GetTime()
    CustomTrackersVisibility.fadeStartAlpha = currentAlpha
    CustomTrackersVisibility.fadeTargetAlpha = targetAlpha
    CustomTrackersVisibility.isFading = true

    if not CustomTrackersVisibility.fadeFrame then
        CustomTrackersVisibility.fadeFrame = CreateFrame("Frame")
    end
    CustomTrackersVisibility.fadeFrame:SetScript("OnUpdate", OnCustomTrackersFadeUpdate)
end

local function UpdateCustomTrackersVisibility()
    -- Anchoring preview mode overrides all visibility logic.
    if CustomTrackersVisibility.anchoringPreviewAll then
        ApplyAnchoringPreviewState()
        CustomTrackersVisibility.currentlyHidden = false
        return
    end

    -- During Edit Mode, force all trackers visible
    if IsInEditMode() then
        local frames = GetCustomTrackerFrames()
        for _, frame in ipairs(frames) do
            frame:SetAlpha(1)
        end
        CustomTrackersVisibility.currentlyHidden = false
        return
    end

    local vis = GetCustomTrackersVisibilitySettings()
    if not vis then return end

    local shouldShow = ShouldCustomTrackersBeVisible()

    if shouldShow then
        StartCustomTrackersFade(1)
        CustomTrackersVisibility.currentlyHidden = false
    else
        StartCustomTrackersFade(vis.fadeOutAlpha or 0)
        CustomTrackersVisibility.currentlyHidden = true
    end
end

local function SetupCustomTrackersMouseoverDetector()
    local vis = GetCustomTrackersVisibilitySettings()
    if not vis then return end

    -- Release existing detector back to pool
    if CustomTrackersVisibility.mouseoverDetector then
        ReleaseDetector(CustomTrackersVisibility.mouseoverDetector)
        CustomTrackersVisibility.mouseoverDetector = nil
    end

    -- Only create detector if mouseover is enabled and showAlways is disabled
    if not vis.showOnMouseover or vis.showAlways then
        return
    end

    local detector = AcquireDetector()
    local lastCheck = 0
    detector:SetScript("OnUpdate", function(self, elapsed)
        -- Skip during combat for CPU efficiency
        if InCombatLockdown() then return end

        lastCheck = lastCheck + elapsed
        if lastCheck < 0.066 then return end  -- 66ms (~15 FPS) for CPU efficiency
        lastCheck = 0

        local wasOver = CustomTrackersVisibility.mouseOver
        local isOver = false

        local frames = GetCustomTrackerFrames()
        for _, frame in ipairs(frames) do
            if frame:IsMouseOver() then
                isOver = true
                break
            end
        end

        if isOver ~= wasOver then
            CustomTrackersVisibility.mouseOver = isOver
            UpdateCustomTrackersVisibility()
        end
    end)
    detector:Show()
    CustomTrackersVisibility.mouseoverDetector = detector
end

---------------------------------------------------------------------------
-- VISIBILITY EVENT HANDLING
---------------------------------------------------------------------------
local visibilityEventFrame = CreateFrame("Frame")
visibilityEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
visibilityEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
visibilityEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
visibilityEventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
visibilityEventFrame:RegisterEvent("GROUP_JOINED")
visibilityEventFrame:RegisterEvent("GROUP_LEFT")
visibilityEventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
visibilityEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
visibilityEventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
visibilityEventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
visibilityEventFrame:RegisterEvent("PLAYER_FLAGS_CHANGED")
visibilityEventFrame:RegisterEvent("PLAYER_IS_GLIDING_CHANGED")
visibilityEventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_FLAGS_CHANGED" then
        local unit = ...
        if unit ~= "player" then return end
    end

    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1.5, function()
            SetupCustomTrackersMouseoverDetector()
            UpdateCustomTrackersVisibility()
        end)
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Combat ended: update visibility and process any pending secure button updates
        UpdateCustomTrackersVisibility()
        ProcessPendingSecureUpdates()
        ProcessPendingBarOperations()
        if CustomTrackersVisibility.pendingPreviewSync then
            CustomTrackersVisibility.pendingPreviewSync = false
            if CustomTrackersVisibility.anchoringPreviewAll then
                ApplyAnchoringPreviewState()
            else
                RestoreAfterAnchoringPreview()
                UpdateCustomTrackersVisibility()
            end
        end
    else
        UpdateCustomTrackersVisibility()
    end
end)

---------------------------------------------------------------------------
-- GLOBAL REFRESH FUNCTIONS FOR OPTIONS PANEL
---------------------------------------------------------------------------
_G.QUI_RefreshCustomTrackersVisibility = UpdateCustomTrackersVisibility
_G.QUI_RefreshCustomTrackersMouseover = SetupCustomTrackersMouseoverDetector

_G.QUI_IsAnchoringPreviewAllCustomTrackers = function()
    return CustomTrackersVisibility.anchoringPreviewAll == true
end

_G.QUI_SetAnchoringPreviewAllCustomTrackers = function(enabled)
    local isEnabled = enabled and true or false
    if CustomTrackersVisibility.anchoringPreviewAll == isEnabled then
        if isEnabled then
            ApplyAnchoringPreviewState()
        end
        return
    end

    CustomTrackersVisibility.anchoringPreviewAll = isEnabled

    if CustomTrackersVisibility.fadeFrame then
        CustomTrackersVisibility.fadeFrame:SetScript("OnUpdate", nil)
    end
    CustomTrackersVisibility.isFading = false

    if isEnabled then
        ApplyAnchoringPreviewState()
    else
        RestoreAfterAnchoringPreview()
        UpdateCustomTrackersVisibility()
    end
end

-- Suspend/resume visibility rules during Edit Mode
-- Retry with a ticker until core is ready, then cancel
local _editModeRegTicker
_editModeRegTicker = C_Timer.NewTicker(1.5, function()
    local core = GetCore()
    if not core or not core.RegisterEditModeEnter then return end

    _editModeRegTicker:Cancel()
    _editModeRegTicker = nil

    core:RegisterEditModeEnter(function()
        -- Force all trackers visible while in Edit Mode (unless anchoring preview is active).
        CustomTrackersVisibility.isFading = false
        if CustomTrackersVisibility.fadeFrame then
            CustomTrackersVisibility.fadeFrame:SetScript("OnUpdate", nil)
        end
        if CustomTrackersVisibility.anchoringPreviewAll then
            ApplyAnchoringPreviewState()
            return
        end
        local frames = GetCustomTrackerFrames()
        for _, frame in ipairs(frames) do
            frame:SetAlpha(1)
        end
    end)

    core:RegisterEditModeExit(function()
        if CustomTrackersVisibility.anchoringPreviewAll then
            ApplyAnchoringPreviewState()
        else
            -- Re-apply normal visibility rules
            UpdateCustomTrackersVisibility()
        end
    end)
end)

-- Refresh keybind display on all custom tracker icons
_G.QUI_RefreshCustomTrackerKeybinds = function()
    for _, bar in pairs(CustomTrackers.activeBars or {}) do
        if bar and bar.icons then
            for _, icon in ipairs(bar.icons) do
                -- Re-style to update font/position
                StyleTrackerIcon(icon, bar.config)
                -- Re-apply keybind
                ApplyKeybindToTrackerIcon(icon)
            end
        end
    end
end

if ns.Registry then
    ns.Registry:Register("customTrackers", {
        refresh = _G.QUI_RefreshCustomTrackers,
        priority = 40,
        group = "trackers",
        importCategories = { "customTrackers" },
    })
end

---------------------------------------------------------------------------
-- LAYOUT MODE: SETTINGS PROVIDER
---------------------------------------------------------------------------

--- Register a settings provider for a custom tracker bar in layout mode.
--- Called from both startup registration and dynamic tracker creation.
local function RegisterCustomTrackerProvider(barID, elementKey)
    local settingsPanel = ns.QUI_LayoutMode_Settings
    if not settingsPanel then return end

    settingsPanel:RegisterProvider(elementKey, { build = function(content, key, width)
        local db = GetDB()
        if not db or not db.bars then return 80 end

        -- Find bar config by ID
        local barConfig = nil
        for _, bc in ipairs(db.bars) do
            if bc.id == barID then barConfig = bc; break end
        end
        if not barConfig then return 80 end

        local GUI = QUI and QUI.GUI
        if not GUI then return 80 end

        local U = ns.QUI_LayoutMode_Utils
        if not U then return 80 end
        local P = U.PlaceRow
        local FORM_ROW = U.FORM_ROW

        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh()
            local bar = CustomTrackers.activeBars and CustomTrackers.activeBars[barID]
            if bar then
                CustomTrackers:RefreshAll()
            end
            -- Sync the mover handle to reflect new size/position
            if _G.QUI_LayoutModeSyncHandle then
                _G.QUI_LayoutModeSyncHandle(elementKey)
            end
        end

        -- Items & Spells section
        U.CreateCollapsible(content, "Items & Spells", 6 * FORM_ROW + 40, function(body)
            local sy = -4

            -- Drop zone hint
            local dropHint = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            dropHint:SetPoint("TOPLEFT", 4, sy)
            dropHint:SetPoint("RIGHT", body, "RIGHT", -4, 0)
            dropHint:SetTextColor(0.6, 0.6, 0.6, 0.8)
            dropHint:SetText("Drag items or spells from your spellbook/bags onto the drop zone below")
            dropHint:SetJustifyH("LEFT")
            sy = sy - 16

            -- Drop zone frame
            local dropZone = CreateFrame("Button", nil, body)
            dropZone:SetSize(width - 20, 28)
            dropZone:SetPoint("TOPLEFT", 4, sy)

            local dropBg = dropZone:CreateTexture(nil, "BACKGROUND")
            dropBg:SetAllPoints()
            dropBg:SetColorTexture(0.1, 0.15, 0.1, 0.6)

            local dropText = dropZone:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            dropText:SetPoint("CENTER")
            dropText:SetText("|cff34D399Drop Item or Spell Here|r")

            dropZone:SetScript("OnReceiveDrag", function()
                local infoType, id, subType = GetCursorInfo()
                if infoType == "item" then
                    if not barConfig.entries then barConfig.entries = {} end
                    table_insert(barConfig.entries, { type = "item", id = id })
                    ClearCursor()
                    Refresh()
                    -- Force rebuild to show new entry
                    if settingsPanel then
                        settingsPanel._currentKey = nil
                        settingsPanel:Show(key)
                    end
                elseif infoType == "spell" then
                    if not barConfig.entries then barConfig.entries = {} end
                    table_insert(barConfig.entries, { type = "spell", id = id })
                    ClearCursor()
                    Refresh()
                    if settingsPanel then
                        settingsPanel._currentKey = nil
                        settingsPanel:Show(key)
                    end
                end
            end)
            dropZone:SetScript("OnMouseUp", dropZone:GetScript("OnReceiveDrag"))

            sy = sy - 34

            -- Trinket slot buttons
            local trinket1Btn = CreateFrame("Button", nil, body)
            trinket1Btn:SetSize((width - 30) / 2, 22)
            trinket1Btn:SetPoint("TOPLEFT", 4, sy)
            trinket1Btn:SetNormalFontObject("GameFontNormalSmall")
            trinket1Btn:SetText("|cff60A5FA+ Trinket 1|r")
            local t1bg = trinket1Btn:CreateTexture(nil, "BACKGROUND")
            t1bg:SetAllPoints()
            t1bg:SetColorTexture(0.15, 0.15, 0.2, 0.8)
            trinket1Btn:SetScript("OnClick", function()
                if not barConfig.entries then barConfig.entries = {} end
                table_insert(barConfig.entries, { type = "slot", id = 13, name = "Trinket 1" })
                Refresh()
                if settingsPanel then
                    settingsPanel._currentKey = nil
                    settingsPanel:Show(key)
                end
            end)

            local trinket2Btn = CreateFrame("Button", nil, body)
            trinket2Btn:SetSize((width - 30) / 2, 22)
            trinket2Btn:SetPoint("LEFT", trinket1Btn, "RIGHT", 4, 0)
            trinket2Btn:SetNormalFontObject("GameFontNormalSmall")
            trinket2Btn:SetText("|cff60A5FA+ Trinket 2|r")
            local t2bg = trinket2Btn:CreateTexture(nil, "BACKGROUND")
            t2bg:SetAllPoints()
            t2bg:SetColorTexture(0.15, 0.15, 0.2, 0.8)
            trinket2Btn:SetScript("OnClick", function()
                if not barConfig.entries then barConfig.entries = {} end
                table_insert(barConfig.entries, { type = "slot", id = 14, name = "Trinket 2" })
                Refresh()
                if settingsPanel then
                    settingsPanel._currentKey = nil
                    settingsPanel:Show(key)
                end
            end)

            sy = sy - 28

            -- Entry list
            if barConfig.entries and #barConfig.entries > 0 then
                for idx, entry in ipairs(barConfig.entries) do
                    local entryRow = CreateFrame("Frame", nil, body)
                    entryRow:SetHeight(22)
                    entryRow:SetPoint("TOPLEFT", 4, sy)
                    entryRow:SetPoint("RIGHT", body, "RIGHT", -4, 0)

                    -- Icon
                    local icon = entryRow:CreateTexture(nil, "ARTWORK")
                    icon:SetSize(18, 18)
                    icon:SetPoint("LEFT", 0, 0)
                    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    local entryName = entry.name or ""
                    if entry.type == "item" then
                        local itemName, _, _, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(entry.id)
                        icon:SetTexture(itemIcon or 134400)
                        entryName = itemName or entry.name or ("Item " .. (entry.id or "?"))
                    elseif entry.type == "spell" then
                        local spellInfo = C_Spell.GetSpellInfo(entry.id)
                        if spellInfo then
                            icon:SetTexture(spellInfo.iconID or 134400)
                            entryName = spellInfo.name or entry.name or ("Spell " .. (entry.id or "?"))
                        else
                            icon:SetTexture(134400)
                            entryName = entry.name or ("Spell " .. (entry.id or "?"))
                        end
                    elseif entry.type == "slot" then
                        local slotID = entry.id
                        local itemID = GetInventoryItemID("player", slotID)
                        if itemID then
                            local _, _, _, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(itemID)
                            icon:SetTexture(itemIcon or 134400)
                        else
                            icon:SetTexture(134400)
                        end
                        entryName = entry.name or ("Slot " .. (slotID or "?"))
                    end

                    local nameText = entryRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    nameText:SetPoint("LEFT", icon, "RIGHT", 4, 0)
                    nameText:SetPoint("RIGHT", entryRow, "RIGHT", -50, 0)
                    nameText:SetText(entryName)
                    nameText:SetTextColor(0.9, 0.9, 0.9, 1)
                    nameText:SetJustifyH("LEFT")

                    -- Remove button
                    local capturedIdx = idx
                    local removeBtn = CreateFrame("Button", nil, entryRow)
                    removeBtn:SetSize(18, 18)
                    removeBtn:SetPoint("RIGHT", 0, 0)
                    removeBtn:SetNormalFontObject("GameFontNormalSmall")
                    removeBtn:SetText("|cffFF4444X|r")
                    removeBtn:SetScript("OnClick", function()
                        table_remove(barConfig.entries, capturedIdx)
                        Refresh()
                        if settingsPanel then
                            settingsPanel._currentKey = nil
                            settingsPanel:Show(key)
                        end
                    end)

                    sy = sy - 24
                end
            end

            -- Adjust body height
            local realHeight = math.abs(sy) + 4
            body:SetHeight(realHeight)
            local sec = body:GetParent()
            if sec then
                sec._contentHeight = realHeight
                if sec._expanded then
                    sec:SetHeight((U.HEADER_HEIGHT or 24) + realHeight)
                end
            end
        end, sections, relayout)

        -- Layout
        local directionOptions = {
            {value = "RIGHT", text = "Right"}, {value = "LEFT", text = "Left"},
            {value = "UP", text = "Up"}, {value = "DOWN", text = "Down"},
            {value = "CENTER", text = "Center (H)"}, {value = "CENTER_VERTICAL", text = "Center (V)"},
        }
        U.CreateCollapsible(content, "Layout", 6 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormDropdown(body, "Growth Direction", directionOptions, "growDirection", barConfig, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Icon Size", 16, 64, 1, "iconSize", barConfig, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Spacing", 0, 20, 1, "spacing", barConfig, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Icon Shape", 1.0, 2.0, 0.05, "aspectRatioCrop", barConfig, Refresh, { precision = 2 }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Dynamic Layout (Collapsing)", "dynamicLayout", barConfig, Refresh), body, sy)
            P(GUI:CreateFormCheckbox(body, "Clickable Icons", "clickableIcons", barConfig, Refresh), body, sy)
        end, sections, relayout)

        -- Icon Style
        U.CreateCollapsible(content, "Icon Style", 2 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormSlider(body, "Border Size", 0, 8, 1, "borderSize", barConfig, Refresh), body, sy)
            P(GUI:CreateFormSlider(body, "Zoom", 0, 0.2, 0.01, "zoom", barConfig, Refresh, { precision = 2 }), body, sy)
        end, sections, relayout)

        -- Duration Text
        U.CreateCollapsible(content, "Duration Text", 6 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Hide Duration Text", "hideDurationText", barConfig, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Font Size", 8, 24, 1, "durationSize", barConfig, Refresh), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Duration Color", "durationColor", barConfig, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "X Offset", -20, 20, 1, "durationOffsetX", barConfig, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Y Offset", -20, 20, 1, "durationOffsetY", barConfig, Refresh), body, sy)
            -- Font dropdown
            local fontList = U.GetFontList()
            if #fontList > 0 then
                P(GUI:CreateFormDropdown(body, "Font", fontList, "durationFont", barConfig, Refresh), body, sy)
            end
        end, sections, relayout)

        -- Stack Text
        U.CreateCollapsible(content, "Stack Text", 6 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Hide Stack Text", "hideStackText", barConfig, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Show Item Charges", "showItemCharges", barConfig, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Font Size", 8, 24, 1, "stackSize", barConfig, Refresh), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Stack Color", "stackColor", barConfig, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "X Offset", -20, 20, 1, "stackOffsetX", barConfig, Refresh), body, sy)
            P(GUI:CreateFormSlider(body, "Y Offset", -20, 20, 1, "stackOffsetY", barConfig, Refresh), body, sy)
        end, sections, relayout)

        -- Buff Active
        local glowTypeOptions = {
            {value = "Pixel Glow", text = "Pixel Glow"},
            {value = "Autocast Shine", text = "Autocast Shine"},
            {value = "Proc Glow", text = "Proc Glow"},
        }
        U.CreateCollapsible(content, "Buff Active", 7 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Enable Active Glow", "activeGlowEnabled", barConfig, Refresh), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Glow Type", glowTypeOptions, "activeGlowType", barConfig, Refresh), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Glow Color", "activeGlowColor", barConfig, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Lines", 4, 16, 1, "activeGlowLines", barConfig, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Frequency", 0.1, 1.0, 0.05, "activeGlowFrequency", barConfig, Refresh, { precision = 2 }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Thickness", 1, 5, 1, "activeGlowThickness", barConfig, Refresh), body, sy)
            P(GUI:CreateFormSlider(body, "Scale", 0.5, 2.0, 0.1, "activeGlowScale", barConfig, Refresh, { precision = 1 }), body, sy)
        end, sections, relayout)

        -- Visibility
        U.CreateCollapsible(content, "Visibility", 5 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Show Only In Combat", "showOnlyInCombat", barConfig, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Show Only On Cooldown", "showOnlyOnCooldown", barConfig, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "No Desaturate With Charges", "noDesaturateWithCharges", barConfig, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Show Only When Active", "showOnlyWhenActive", barConfig, Refresh), body, sy)
            P(GUI:CreateFormCheckbox(body, "Show Only When Off Cooldown", "showOnlyWhenOffCooldown", barConfig, Refresh), body, sy)
        end, sections, relayout)

        -- Advanced
        U.CreateCollapsible(content, "Advanced", 4 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Show Recharge Swipe", "showRechargeSwipe", barConfig, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Hide Non-Usable Items", "hideNonUsable", barConfig, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Hide GCD", "hideGCD", barConfig, Refresh), body, sy)
            P(GUI:CreateFormCheckbox(body, "Spec-Specific Spells", "specSpecificSpells", barConfig, Refresh), body, sy)
        end, sections, relayout)

        -- Export & Delete buttons
        local actionSection = CreateFrame("Frame", nil, content)
        actionSection:SetHeight(2 * FORM_ROW + 8)

        -- Export button
        local exportBtn = CreateFrame("Button", nil, actionSection)
        exportBtn:SetSize(width - 20, 24)
        exportBtn:SetPoint("TOP", 0, -4)
        exportBtn:SetNormalFontObject("GameFontNormal")
        exportBtn:SetText("|cff60A5FAExport Bar|r")
        local exportBg = exportBtn:CreateTexture(nil, "BACKGROUND")
        exportBg:SetAllPoints()
        exportBg:SetColorTexture(0.1, 0.12, 0.18, 0.9)
        exportBtn:SetScript("OnClick", function()
            local QUICore = ns.Addon
            if QUICore and QUICore.ExportCustomTrackerBar then
                local exportStr, err = QUICore:ExportCustomTrackerBar(barID)
                if exportStr and GUI.ShowExportPopup then
                    GUI:ShowExportPopup("Export Tracker Bar", exportStr)
                elseif err then
                    print("|cffff0000QUI:|r " .. err)
                end
            end
        end)

        -- Delete button (hidden for default tracker)
        local isDefaultTracker = (barID == "default_tracker_1")
        local deleteBtn = CreateFrame("Button", nil, actionSection)
        deleteBtn:SetSize(width - 20, 24)
        deleteBtn:SetPoint("TOP", exportBtn, "BOTTOM", 0, -4)
        deleteBtn:SetNormalFontObject("GameFontNormal")
        if isDefaultTracker then
            deleteBtn:Hide()
            actionSection:SetHeight(FORM_ROW + 4)
        end
        deleteBtn:SetText("|cffFF4444Delete Tracker|r")
        local deleteBg = deleteBtn:CreateTexture(nil, "BACKGROUND")
        deleteBg:SetAllPoints()
        deleteBg:SetColorTexture(0.18, 0.08, 0.08, 0.9)
        deleteBtn:SetScript("OnClick", function()
            if GUI and GUI.ShowConfirmation then
                GUI:ShowConfirmation({
                    title = "Delete Tracker?",
                    message = "This will permanently remove this tracker bar.",
                    acceptText = "Delete",
                    cancelText = "Cancel",
                    onAccept = function()
                        -- Remove from DB
                        if db and db.bars then
                            for idx, bc in ipairs(db.bars) do
                                if bc.id == barID then
                                    table_remove(db.bars, idx)
                                    break
                                end
                            end
                        end
                        -- Delete runtime bar
                        CustomTrackers:DeleteBar(barID)
                        -- Close settings
                        if settingsPanel then settingsPanel:Reset() end
                        -- Unregister from layout mode
                        local um = ns.QUI_LayoutMode
                        if um then
                            local handle = um._handles and um._handles[elementKey]
                            if handle then
                                handle:Hide()
                                handle:SetParent(nil)
                                um._handles[elementKey] = nil
                            end
                            if um._elements then um._elements[elementKey] = nil end
                            if um._elementOrder then
                                for i, k in ipairs(um._elementOrder) do
                                    if k == elementKey then
                                        table_remove(um._elementOrder, i)
                                        break
                                    end
                                end
                            end
                        end
                        -- Rebuild drawer
                        local uiModule = ns.QUI_LayoutMode_UI
                        if uiModule and uiModule._RebuildDrawer then
                            uiModule:_RebuildDrawer()
                        end
                    end,
                })
            end
        end)
        table_insert(sections, actionSection)

        -- Position
        U.BuildPositionCollapsible(content, elementKey, nil, sections, relayout)

        relayout()
        return content:GetHeight()
    end })
end

RegisterTrackerLayoutElement = function(barID)
    local barConfig, order = GetTrackerBarConfigAndIndex(barID)
    if not barConfig then return nil end

    local elementKey = "customTracker:" .. barID
    local capturedID = barID
    local um = ns.QUI_LayoutMode

    if um then
        um:RegisterElement({
            key = elementKey,
            label = barConfig.name or ("Tracker " .. order),
            group = "Cooldown Manager & Custom Tracker Bars",
            order = order,
            isOwned = false,  -- proxy mover (LOW strata)
            getSize = function()
                -- Compute size from config to avoid feedback loop
                -- (frame may be reparented to mover via SetAllPoints)
                local db2 = GetDB()
                if not db2 or not db2.bars then return nil end
                local cfg = nil
                for _, bc in ipairs(db2.bars) do
                    if bc.id == capturedID then cfg = bc; break end
                end
                if not cfg or not cfg.entries then return nil end
                local iconSize = cfg.iconSize or 28
                local spacing = cfg.spacing or 4
                local numEntries = #cfg.entries
                if numEntries == 0 then numEntries = 1 end
                local crop = cfg.aspectRatioCrop or 1.0
                local iconW = iconSize
                local iconH = math.floor(iconSize / crop + 0.5)
                local dir = cfg.growDirection or "RIGHT"
                if dir == "RIGHT" or dir == "LEFT" or dir == "CENTER" then
                    return iconW * numEntries + spacing * (numEntries - 1), iconH
                else
                    return iconW, iconH * numEntries + spacing * (numEntries - 1)
                end
            end,
            isEnabled = function()
                local db2 = GetDB()
                if not db2 or not db2.bars then return false end
                for _, bc in ipairs(db2.bars) do
                    if bc.id == capturedID then return bc.enabled ~= false end
                end
                return false
            end,
            setEnabled = function(val)
                local db2 = GetDB()
                if not db2 or not db2.bars then return end
                for _, bc in ipairs(db2.bars) do
                    if bc.id == capturedID then
                        bc.enabled = val
                        break
                    end
                end
                -- Show/hide the bar
                local bar = CustomTrackers.activeBars and CustomTrackers.activeBars[capturedID]
                if bar then
                    if val then
                        SetBarShownForPreview(bar, true)
                    else
                        SetBarShownForPreview(bar, false)
                    end
                end
            end,
            setGameplayHidden = function(hide)
                local bar = CustomTrackers.activeBars and CustomTrackers.activeBars[capturedID]
                if not bar then return end
                if hide then bar:Hide() else bar:Show() end
            end,
            getFrame = function()
                return CustomTrackers.activeBars and CustomTrackers.activeBars[capturedID]
            end,
            onOpen = function()
                -- Show bar for preview during layout mode
                local bar = CustomTrackers.activeBars and CustomTrackers.activeBars[capturedID]
                if bar then
                    SetBarShownForPreview(bar, true)
                    bar:SetAlpha(bar.config and bar.config.enabled and 1 or 0.5)
                end
            end,
            onClose = function()
                -- Restore normal visibility
                local bar = CustomTrackers.activeBars and CustomTrackers.activeBars[capturedID]
                if bar then
                    local shouldShow = bar.config and bar.config.enabled
                    SetBarShownForPreview(bar, shouldShow == true)
                    if shouldShow and bar:IsShown() then
                        bar:SetAlpha(1)
                    end
                end
            end,
        })
    end

    RegisterCustomTrackerProvider(barID, elementKey)

    if ns.FRAME_ANCHOR_INFO then
        ns.FRAME_ANCHOR_INFO[elementKey] = {
            displayName = barConfig.name or ("Tracker " .. order),
            category = "Cooldown Manager & Custom Tracker Bars",
            order = order,
        }
    end

    return elementKey
end

-- Expose for dynamic registration
CustomTrackers.RegisterProvider = RegisterCustomTrackerProvider

---------------------------------------------------------------------------
-- UNLOCK MODE ELEMENT REGISTRATION
---------------------------------------------------------------------------
do
    local function RegisterLayoutModeElements()
        local function GetTrackerDB()
            local core = ns.Helpers.GetCore()
            return core and core.db and core.db.profile and core.db.profile.customTrackers
        end

        local trackerDB = GetTrackerDB()
        if not trackerDB or not trackerDB.bars then return end

        -- Register each tracker bar from DB
        for _, barConfig in ipairs(trackerDB.bars) do
            local barID = barConfig.id
            if barID then
                RegisterTrackerLayoutElement(barID)
            end
        end
    end

    C_Timer.After(3, RegisterLayoutModeElements)
end