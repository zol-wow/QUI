--[[
    QUI Custom Trackers
    User-configurable icon bars for tracking spells, items, trinkets, consumables
    Drag-and-drop spell/item input
]]

local ADDON_NAME, ns = ...
local QUI = QUI  -- Use global addon table, not ns.Addon (which is QUICore)
local LSM = LibStub("LibSharedMedia-3.0")
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)  -- For active state glow
local Helpers = ns.Helpers
local IsSecretValue = Helpers.IsSecretValue
local SafeValue = Helpers.SafeValue
local GetDB = Helpers.CreateDBGetter("customTrackers")

local GetCore = ns.Helpers.GetCore

---------------------------------------------------------------------------
-- MODULE NAMESPACE
---------------------------------------------------------------------------
local CustomTrackers = {}
CustomTrackers.activeBars = {}   -- Runtime bar frames indexed by barID
CustomTrackers.infoCache = {}    -- Cached spell/item info

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

-- Helper: Get recharge edge setting from global cooldownSwipe settings
local function GetRechargeEdgeSetting()
    local core = GetCore()
    if core and core.db and core.db.profile and core.db.profile.cooldownSwipe then
        return core.db.profile.cooldownSwipe.showRechargeEdge
    end
    return false  -- Default to off
end

---------------------------------------------------------------------------
-- POSITIONING SYSTEM (edge-anchored based on growth direction)
---------------------------------------------------------------------------
local function PositionBar(bar)
    if not bar or not bar.config then return end
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
            table.insert(specs, {
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
        table.insert(copiedEntries, {
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

---------------------------------------------------------------------------
-- COOLDOWN INFO HELPERS
---------------------------------------------------------------------------
local function GetSpellCooldownInfo(spellID)
    if not spellID then return 0, 0, false, nil end
    local cooldownInfo = C_Spell.GetSpellCooldown(spellID)
    if cooldownInfo then
        return cooldownInfo.startTime, cooldownInfo.duration, cooldownInfo.isEnabled, cooldownInfo.isOnGCD
    end
    return 0, 0, true, nil
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
    if not spellID then return 0, 1, 0, 0 end
    local chargeInfo = C_Spell.GetSpellCharges(spellID)

    if not chargeInfo then
        return 0, 1, 0, 0  -- Not a charge-based spell
    end

    local maxCharges = chargeInfo.maxCharges

    -- Check if maxCharges exists
    if not maxCharges then
        return 0, 1, 0, 0
    end

    -- Handle secret values (protected in combat)
    if IsSecretValue(maxCharges) then
        -- Can't read maxCharges directly - check our cache
        local cachedMax = knownChargeSpells[spellID]
        if cachedMax and cachedMax > 1 then
            -- Known charge spell - return charge cooldown values with cached maxCharges
            return chargeInfo.currentCharges, cachedMax,
                   chargeInfo.cooldownStartTime or 0,
                   chargeInfo.cooldownDuration or 0
        end
        -- Unknown or single-charge spell - treat as non-charge (safe default)
        return 0, 1, 0, 0
    end

    -- Normal case: safe to compare - also cache the result
    if maxCharges > 1 then
        knownChargeSpells[spellID] = maxCharges  -- Cache for future secret-value situations
        return chargeInfo.currentCharges or 0, maxCharges,
               chargeInfo.cooldownStartTime or 0,
               chargeInfo.cooldownDuration or 0
    end

    -- Single charge spell - cache that too
    knownChargeSpells[spellID] = 1
    return 0, 1, 0, 0
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
        return C_Item.IsEquippedItem(itemID)
    else
        -- Consumables: check stack count
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
        if iconFrame:GetAlpha() == 0 then return end  -- Don't show tooltip when visually hidden
        if iconFrame.entry then
            -- Respect tooltip anchor setting
            local core = GetCore()
            local tooltipSettings = core and core.db and core.db.profile and core.db.profile.tooltip
            if tooltipSettings and tooltipSettings.anchorToCursor then
                GameTooltip:SetOwner(iconFrame, "ANCHOR_CURSOR")
            else
                GameTooltip_SetDefaultAnchor(GameTooltip, iconFrame)
            end
            if iconFrame.entry.type == "spell" then
                GameTooltip:SetSpellByID(iconFrame.entry.id)
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
        GameTooltip:Hide()
    end)

    -- Forward drag events to parent bar (so clicking on icons still allows dragging)
    icon:RegisterForDrag("LeftButton")
    icon:SetScript("OnDragStart", function(self)
        local bar = self:GetParent()
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

    -- Collect only visible icons
    local visibleIcons = {}
    for _, icon in ipairs(bar.icons) do
        if icon.isVisible ~= false then
            table.insert(visibleIcons, icon)
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

        table.insert(bar.icons, icon)
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
local function FormatDuration(seconds)
    if seconds >= 3600 then
        return string.format("%dh", math.floor(seconds / 3600))
    elseif seconds >= 60 then
        return string.format("%dm", math.floor(seconds / 60))
    elseif seconds >= 10 then
        return string.format("%d", math.floor(seconds))
    elseif seconds > 0 then
        return string.format("%.1f", seconds)
    end
    return ""
end

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

    -- Iterate the FULL configured list (bar.icons), not activeIcons
    -- This ensures we pick up newly-talented spells when switching talent loadouts
    for _, icon in ipairs(bar.icons or {}) do
        local entry = icon.entry
        if entry and entry.id then
            local isUsable = true
            if entry.type == "spell" then
                isUsable = IsSpellUsable(entry.id)
            elseif entry.type == "item" then
                -- Items: equipment check is stable, consumables always in active set
                if IsEquipmentItem(entry.id) then
                    isUsable = C_Item.IsEquippedItem(entry.id)
                else
                    isUsable = true  -- Consumables always in active set (count checked in DoUpdate)
                end
            end

            -- Only add usable spells to activeIcons (CPU optimization)
            -- This ensures we never process unknown spells in DoUpdate, regardless of hideNonUsable toggle
            if isUsable then
                table.insert(bar.activeIcons, icon)
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

    -- Re-layout with the new active set (skip during combat — layout uses
    -- ClearAllPoints/SetPoint which are also protected on secure children)
    if inCombat then
        pendingActiveSetRebuilds[bar] = true
    else
        LayoutVisibleIcons(bar)
    end

    -- DEBUG: Remove this line after verifying the optimization works
    -- print("|cFF00FF00[QUI Debug]|r RebuildActiveSet: " .. #bar.activeIcons .. " of " .. #(bar.icons or {}) .. " icons active")
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
                local startTime, duration, enabled, isOnGCD
                local count = 0
                local maxCharges = 1
                local chargeStartTime, chargeDuration = 0, 0  -- For charge spell recharge display

                if entry.type == "spell" then
                    startTime, duration, enabled, isOnGCD = GetSpellCooldownInfo(entry.id)
                    count, maxCharges, chargeStartTime, chargeDuration = GetSpellChargeCount(entry.id)
                else
                    startTime, duration, enabled = GetItemCooldownInfo(entry.id)
                    count = GetItemStackCount(entry.id, config.showItemCharges)
                    isOnGCD = false  -- Items don't have GCD
                    -- Update item usability based on current count (consumables deplete during gameplay)
                    icon._usable = IsItemUsable(entry.id, count)
                end

                -- Check if spell/item is currently active (casting/channeling/buff)
                local isActive, activeStartTime, activeDuration, activeType = false, nil, nil, nil
                if showActiveState then
                    if entry.type == "spell" then
                        isActive, activeStartTime, activeDuration, activeType = GetSpellActiveInfo(entry.id)
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
                if isActive and activeStartTime and activeDuration and activeDuration > 0 and not showOnlyOnCooldown then
                    -- Active state: show buff/cast duration (reverse fill)
                    pcall(function()
                        icon.cooldown:SetReverse(true)
                        icon.cooldown:SetCooldown(activeStartTime, activeDuration)
                    end)
                    isOnCD = false  -- Active overrides cooldown state
                else
                    -- Normal cooldown display
                    local isChargeSpell = maxCharges > 1

                    icon.cooldown:SetReverse(false)

                    if isChargeSpell then
                        -- For charge spells: use charge cooldown values
                        if chargeStartTime and chargeDuration then
                            -- Set cooldown first (inside pcall for secret value safety)
                            pcall(function()
                                icon.cooldown:SetCooldown(chargeStartTime, chargeDuration)
                            end)
                            -- Check if cooldown is active AFTER setting it
                            rechargeActive = IsCooldownFrameActive(icon.cooldown)
                        else
                            icon.cooldown:Clear()
                        end

                        -- Control swipe/edge for charge spells (outside pcall for reliability)
                        if config.showRechargeSwipe then
                            pcall(icon.cooldown.SetSwipeColor, icon.cooldown, 0, 0, 0, 0.6)
                            pcall(icon.cooldown.SetDrawSwipe, icon.cooldown, true)
                        else
                            pcall(icon.cooldown.SetSwipeColor, icon.cooldown, 0, 0, 0, 0)
                            pcall(icon.cooldown.SetDrawSwipe, icon.cooldown, false)
                        end
                        local showEdge = rechargeActive and GetRechargeEdgeSetting()
                        pcall(icon.cooldown.SetDrawEdge, icon.cooldown, showEdge)

                        -- EXPLICIT show/hide (critical for cooldown visibility)
                        if rechargeActive then
                            icon.cooldown:Show()
                        else
                            icon.cooldown:Hide()
                        end

                        -- isOnCD for charge spells = out of charges
                        -- Use cooldown frame to detect main cooldown active (handles secret values internally)
                        -- Set cooldown with main values, check if frame is active
                        local mainCDActive = false

                        -- Temporarily set cooldown with MAIN spell cooldown values
                        -- Main cooldown is only active when ALL charges are depleted
                        -- Clear first to ensure clean state (SetCooldown(0,0) doesn't clear previous state)
                        icon.cooldown:Clear()
                        pcall(function()
                            icon.cooldown:SetCooldown(startTime, duration)
                        end)
                        -- Check if the frame shows this cooldown as active
                        -- IsCooldownFrameActive uses IsVisible() which handles secret values internally
                        mainCDActive = IsCooldownFrameActive(icon.cooldown)

                        -- Now restore charge cooldown values for display
                        if chargeStartTime and chargeDuration then
                            pcall(function()
                                icon.cooldown:SetCooldown(chargeStartTime, chargeDuration)
                            end)
                        end

                        -- Exclude GCD from triggering desaturation
                        -- Check both isOnGCD flag and duration <= 1.5s (GCD range)
                        if hideGCD then
                            local isJustGCD = isOnGCD
                            if not isJustGCD then
                                -- Fallback: check if main cooldown duration is within GCD range
                                local gcdCheckOk, gcdCheckResult = pcall(function()
                                    return duration and duration > 0 and duration <= 1.5
                                end)
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
                                local chargeCheckOk, hasMissingCharges = pcall(function()
                                    return count < maxCharges
                                end)
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
                        if startTime and duration then
                            pcall(function()
                                icon.cooldown:SetCooldown(startTime, duration)
                            end)
                        end

                        pcall(icon.cooldown.SetDrawSwipe, icon.cooldown, false)
                        pcall(icon.cooldown.SetDrawEdge, icon.cooldown, false)

                        if hideGCD then
                            -- Check if this is just GCD (not a real cooldown)
                            -- isOnGCD from API may not be reliable for all spells
                            -- Also check if duration is within GCD range (1.5s base, 0.75s min with haste)
                            local isJustGCD = isOnGCD
                            if not isJustGCD then
                                -- Fallback: check if duration is within GCD range
                                -- Wrap entire comparison in pcall to handle secret values
                                local gcdCheckOk, gcdCheckResult = pcall(function()
                                    return duration and duration > 0 and duration <= 1.5
                                end)
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
                                local checkSuccess, checkResult = pcall(function()
                                    return startTime and startTime > 0 and duration and duration > 0
                                end)
                                if checkSuccess then
                                    isOnCD = checkResult
                                else
                                    isOnCD = IsCooldownFrameActive(icon.cooldown)
                                end
                            end
                        else
                            -- hideGCD is disabled, treat any cooldown as "on cooldown"
                            local checkSuccess, checkResult = pcall(function()
                                return startTime and startTime > 0 and duration and duration > 0
                            end)
                            if checkSuccess then
                                isOnCD = checkResult
                            else
                                isOnCD = IsCooldownFrameActive(icon.cooldown)
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

                -- Apply keybind display
                ApplyKeybindToTrackerIcon(icon)
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
function CustomTrackers:RefreshBarPosition(barID)
    local bar = self.activeBars[barID]
    if bar then
        PositionBar(bar)
    end
end

---------------------------------------------------------------------------
-- BAR CREATION
---------------------------------------------------------------------------
function CustomTrackers:CreateBar(barID, config)
    if not barID or not config then return nil end

    if self.activeBars[barID] then
        return self.activeBars[barID]
    end

    local bar = CreateFrame("Frame", "QUI_CustomTracker_" .. barID, UIParent, "BackdropTemplate")
    bar:SetFrameStrata("MEDIUM")

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
    bar:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], config.bgOpacity or 0)

    -- Initialize icons array
    bar.icons = {}

    -- Setup dragging
    self:SetupDragging(bar)

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
-- BAR DELETION
---------------------------------------------------------------------------
function CustomTrackers:DeleteBar(barID)
    local bar = self.activeBars[barID]
    if bar then
        if bar.ticker then
            bar.ticker:Cancel()
        end
        -- Hide and clear icons
        for _, icon in ipairs(bar.icons or {}) do
            icon:Hide()
            icon:SetParent(nil)
        end
        bar:Hide()
        bar:SetParent(nil)
        self.activeBars[barID] = nil
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
            bar:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], barConfig.bgOpacity or 0)

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

            break
        end
    end
end

---------------------------------------------------------------------------
-- REFRESH ALL BARS
---------------------------------------------------------------------------
function CustomTrackers:RefreshAll()
    -- Delete all existing bars
    for barID in pairs(self.activeBars) do
        self:DeleteBar(barID)
    end

    -- Recreate from DB
    local db = GetDB()
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

            table.insert(entries, {
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
                        table.remove(entries, i)

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
            local entry = table.remove(entries, entryIndex)
            table.insert(entries, newIndex, entry)

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
initFrame:RegisterEvent("BAG_UPDATE_DELAYED")
initFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
initFrame:RegisterEvent("SPELL_UPDATE_USABLE")
initFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")  -- Performance: event-driven cooldown updates
initFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")  -- Performance: catches action bar cooldown changes
-- Active state detection events (casting/channeling/buff)
initFrame:RegisterEvent("UNIT_AURA")
initFrame:RegisterEvent("UNIT_SPELLCAST_START")
initFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
initFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
initFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
initFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
-- Spec change detection for spec-specific spells
initFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
-- Talent change detection for active icon rebuild (talent loadout swaps)
initFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
-- Pet change detection (warlock demons, hunter pets with unique abilities)
initFrame:RegisterEvent("UNIT_PET")
-- Combat state changes for showOnlyInCombat icon visibility
initFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
initFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
initFrame:SetScript("OnEvent", function(self, event, ...)
    -- Spec change: refresh all bars to load spec-appropriate spells
    -- PLAYER_SPECIALIZATION_CHANGED only fires for player, no unit check needed
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Small delay to ensure spec info is fully updated
        C_Timer.After(0.1, function()
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
                if bar then
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
        end

        for _, bar in pairs(CustomTrackers.activeBars) do
            if bar and bar:IsShown() and bar.DoUpdate then
                bar.DoUpdate()
            end
        end
        return
    end

    -- Event-driven cooldown updates (reduces ticker frequency)
    if event == "SPELL_UPDATE_COOLDOWN" or event == "ACTIONBAR_UPDATE_COOLDOWN" then
        -- Update all active bars immediately on cooldown change
        for _, bar in pairs(CustomTrackers.activeBars) do
            if bar and bar:IsShown() and bar.DoUpdate then
                bar.DoUpdate()
            end
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
            for _, bar in pairs(CustomTrackers.activeBars) do
                if bar and bar:IsShown() and bar.DoUpdate and bar.config and bar.config.showActiveState ~= false then
                    bar.DoUpdate()
                end
            end
        end
        return
    end

    if event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" then
            for _, bar in pairs(CustomTrackers.activeBars) do
                if bar and bar:IsShown() and bar.DoUpdate and bar.config and bar.config.showActiveState ~= false then
                    bar.DoUpdate()
                end
            end
        end
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        local core = GetCore()
        if core then
            core.CustomTrackers = CustomTrackers
        end

        C_Timer.After(0.6, function()
            CustomTrackers:RefreshAll()
        end)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- Item info loaded, refresh bars to update any "?" icons
        local itemID = ...
        if itemID then
            -- Clear cache for this item so it gets re-fetched
            CustomTrackers.infoCache["item_" .. itemID] = nil
            -- Quick refresh of all bars
            for _, bar in pairs(CustomTrackers.activeBars) do
                for _, icon in ipairs(bar.icons or {}) do
                    if icon.entry and icon.entry.type == "item" and icon.entry.id == itemID then
                        local info = GetCachedItemInfo(itemID)
                        if info and info.icon then
                            icon.tex:SetTexture(info.icon)
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
local CustomTrackersVisibility = {
    currentlyHidden = false,
    isFading = false,
    fadeStart = 0,
    fadeStartAlpha = 1,
    fadeTargetAlpha = 1,
    fadeFrame = nil,
    mouseOver = false,
    mouseoverDetector = nil,
}

local function GetCustomTrackersVisibilitySettings()
    local core = GetCore()
    if not core or not core.db or not core.db.profile then return nil end
    return core.db.profile.customTrackersVisibility
end

local function GetCustomTrackerFrames()
    local frames = {}
    if CustomTrackers and CustomTrackers.activeBars then
        for _, bar in pairs(CustomTrackers.activeBars) do
            -- Only include enabled bars that are shown
            if bar and bar.config and bar.config.enabled and bar:IsShown() then
                table.insert(frames, bar)
            end
        end
    end
    return frames
end

local function ShouldCustomTrackersBeVisible()
    local vis = GetCustomTrackersVisibilitySettings()
    if not vis then return true end

    -- Hide When Mounted overrides all other conditions (includes Druid flight form)
    if vis.hideWhenMounted and (IsMounted() or GetShapeshiftFormID() == 27) then return false end

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

    -- Clean up existing detector
    if CustomTrackersVisibility.mouseoverDetector then
        CustomTrackersVisibility.mouseoverDetector:SetScript("OnUpdate", nil)
        CustomTrackersVisibility.mouseoverDetector:Hide()
        CustomTrackersVisibility.mouseoverDetector = nil
    end

    -- Only create detector if mouseover is enabled and showAlways is disabled
    if not vis.showOnMouseover or vis.showAlways then
        return
    end

    local detector = CreateFrame("Frame")
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
visibilityEventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1.5, function()
            SetupCustomTrackersMouseoverDetector()
            UpdateCustomTrackersVisibility()
        end)
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Combat ended: update visibility and process any pending secure button updates
        UpdateCustomTrackersVisibility()
        ProcessPendingSecureUpdates()
    else
        UpdateCustomTrackersVisibility()
    end
end)

---------------------------------------------------------------------------
-- GLOBAL REFRESH FUNCTIONS FOR OPTIONS PANEL
---------------------------------------------------------------------------
_G.QUI_RefreshCustomTrackersVisibility = UpdateCustomTrackersVisibility
_G.QUI_RefreshCustomTrackersMouseover = SetupCustomTrackersMouseoverDetector

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
