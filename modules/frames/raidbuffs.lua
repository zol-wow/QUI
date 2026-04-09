local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local LSM = ns.LSM
local Helpers = ns.Helpers
local IsSecretValue = Helpers.IsSecretValue
local SafeValue = Helpers.SafeValue

-- Performance: cache frequently-called globals as locals
local CreateFrame = CreateFrame
local UIParent = UIParent
local pairs = pairs
local ipairs = ipairs
local type = type
local pcall = pcall
local wipe = wipe
local tostring = tostring
local GetTime = GetTime
local UnitExists = UnitExists
local C_Timer = C_Timer
local InCombatLockdown = InCombatLockdown
local IsPlayerSpell = IsPlayerSpell
local IsCurrentSpell = IsCurrentSpell
local GetWeaponEnchantInfo = GetWeaponEnchantInfo
local GetInventoryItemID = GetInventoryItemID
local table_insert = table.insert
local string_format = string.format
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

---------------------------------------------------------------------------
-- QUI Missing Raid Buffs Display
-- Shows missing raid buffs when a buff-providing class is in group
---------------------------------------------------------------------------

local QUI_RaidBuffs = {}
ns.RaidBuffs = QUI_RaidBuffs

---------------------------------------------------------------------------
-- CONSTANTS
---------------------------------------------------------------------------

local ICON_SIZE = 32
local ICON_SPACING = 4
local FRAME_PADDING = 6
local UPDATE_THROTTLE = 0.5
local MAX_AURA_INDEX = 40  -- WoW maximum buff slots

-- Raid buffs configuration
-- spellId: Primary spell ID for icon lookup and detection
-- buffIDs: All aura spell IDs to check (variant detection for talent/expansion differences)
-- castSpellId: The ability spell ID to cast (may differ from buff aura ID)
-- name: Buff name for fallback detection (catches talent variants)
-- stat: What the buff provides (for tooltip)
-- providerClass: Which class provides this buff
-- range: Range in yards for checking if provider/target is reachable
local RAID_BUFFS = {
    {
        spellId = 21562,
        buffIDs = { 21562 },
        castSpellId = 21562,
        name = "Power Word: Fortitude",
        stat = "Stamina",
        providerClass = "PRIEST",
        range = 40,
    },
    {
        spellId = 6673,
        buffIDs = { 6673 },
        castSpellId = 6673,
        name = "Battle Shout",
        stat = "Attack Power",
        providerClass = "WARRIOR",
        range = 100,
    },
    {
        spellId = 1459,
        buffIDs = { 1459, 432778 },
        castSpellId = 1459,
        name = "Arcane Intellect",
        stat = "Intellect",
        providerClass = "MAGE",
        range = 40,
    },
    {
        spellId = 1126,
        buffIDs = { 1126, 432661 },
        castSpellId = 1126,
        name = "Mark of the Wild",
        stat = "Versatility",
        providerClass = "DRUID",
        range = 40,
    },
    {
        -- 381748 is the buff that appears on players, 364342 is the ability
        spellId = 381748,
        buffIDs = { 381748 },
        castSpellId = 364342,
        name = "Blessing of the Bronze",
        stat = "Movement Speed",
        providerClass = "EVOKER",
        range = 40,
    },
    {
        spellId = 462854,
        buffIDs = { 462854 },
        castSpellId = 462854,
        name = "Skyfury",
        stat = "Mastery",
        providerClass = "SHAMAN",
        range = 100,
    },
    {
        spellId = 465,
        buffIDs = { 465 },
        castSpellId = 465,
        name = "Devotion Aura",
        stat = "Damage Reduction",
        providerClass = "PALADIN",
        range = 40,
        isToggleAura = true,  -- Toggle aura: caster doesn't get a HELPFUL buff when solo
    },
}

-- Self-buff configuration (class-specific maintenance buffs)
-- checkType: "playerAura" checks player buff IDs, "weaponEnchant" checks GetWeaponEnchantInfo
-- anyBuffIDs: set of aura spell IDs — any match means buff is present (playerAura)
-- anyEnchantIDs: set of weapon enchant IDs — any match means enchant is present (weaponEnchant)
-- castPriority: ordered list of spell IDs to try casting (first known wins)
-- requiresShield: only check if shield equipped in OH slot
local SELF_BUFFS = {
    -- Shaman: Main hand weapon enchant
    {
        name = "Weapon Enchant",
        stat = "Main Hand",
        providerClass = "SHAMAN",
        selfBuff = true,
        checkType = "weaponEnchant",
        anyEnchantIDs = { [5400] = true, [5401] = true, [6498] = true },
        castPriority = { 318038, 33757, 382021 },  -- Flametongue, Windfury, Earthliving
    },
    -- Shaman: Shield enchant (requires shield equipped)
    {
        name = "Shield Enchant",
        stat = "Off Hand",
        providerClass = "SHAMAN",
        selfBuff = true,
        checkType = "weaponEnchant",
        requiresShield = true,
        anyEnchantIDs = { [7587] = true, [7528] = true },
        castPriority = { 462757, 457481 },  -- Thunderstrike Ward, Tidecaller's Guard
    },
    -- Shaman: Lightning/Water Shield
    {
        name = "Shield",
        stat = "Self-Buff",
        providerClass = "SHAMAN",
        selfBuff = true,
        checkType = "playerAura",
        anyBuffIDs = { [192106] = true, [52127] = true },
        castPriority = { 192106, 52127 },  -- Lightning Shield, Water Shield
    },
    -- Paladin: Weapon rite
    {
        name = "Weapon Rite",
        stat = "Main Hand",
        providerClass = "PALADIN",
        selfBuff = true,
        checkType = "weaponEnchant",
        anyEnchantIDs = { [7143] = true, [7144] = true },
        castPriority = { 433568, 433583 },  -- Rite of Sanctification, Rite of Adjuration
    },
    -- Rogue: Lethal poison
    {
        name = "Lethal Poison",
        stat = "Lethal",
        providerClass = "ROGUE",
        selfBuff = true,
        checkType = "playerAura",
        anyBuffIDs = { [2823] = true, [315584] = true, [8679] = true, [381664] = true },
        castPriority = { 2823, 315584, 8679, 381664 },  -- Deadly, Instant, Wound, Amplifying
    },
    -- Rogue: Non-lethal poison
    {
        name = "Non-Lethal Poison",
        stat = "Non-Lethal",
        providerClass = "ROGUE",
        selfBuff = true,
        checkType = "playerAura",
        anyBuffIDs = { [3408] = true, [5761] = true, [381637] = true },
        castPriority = { 3408, 5761, 381637 },  -- Crippling, Numbing, Atrophic
    },
}

-- Get spell icon dynamically (handles expansion differences)
local function GetBuffIcon(spellId)
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(spellId)
    elseif GetSpellTexture then
        return GetSpellTexture(spellId)
    end
    return 134400  -- Question mark fallback
end

---------------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------------

local mainFrame
local buffIcons = {}
local lastUpdate = 0
local groupClasses = {}
local previewMode = false
local previewBuffs = nil  -- Cached preview buffs (don't reshuffle on every update)

-- Forward declarations
local UpdateDisplay

---------------------------------------------------------------------------
-- DATABASE ACCESS
---------------------------------------------------------------------------

local DEFAULTS = {
    enabled = true,
    showOnlyInGroup = true,
    showOnlyInInstance = false,  -- Only show in dungeon/raid instances
    providerMode = false,         -- Only show buffs the player can cast
    hideLabelBar = false,        -- Hide the "Raid Buffs" label bar
    iconSize = 32,
    labelFontSize = 12,
    labelTextColor = nil,        -- nil = white, otherwise {r, g, b, a}
    position = nil,
}

local function GetSettings()
    return Helpers.GetModuleSettings("raidBuffs", DEFAULTS)
end

---------------------------------------------------------------------------
-- HELPER FUNCTIONS
---------------------------------------------------------------------------

-- Safe value check - returns nil if secret value, otherwise returns the value
local function SafeBooleanCheck(value)
    if IsSecretValue(value) then
        return nil
    end
    return value
end

-- Check if unit is within a specific range (in yards)
-- Uses UnitDistanceSquared for accurate distance, falls back to other methods
local function IsUnitInRange(unit, rangeYards)
    rangeYards = rangeYards or 40  -- Default to 40 yards
    local rangeSquared = rangeYards * rangeYards

    -- Method 1: UnitDistanceSquared - most accurate for custom ranges
    if UnitDistanceSquared then
        local ok, distSq = pcall(UnitDistanceSquared, unit)
        if ok and distSq then
            local dist = SafeBooleanCheck(distSq)
            if dist and type(dist) == "number" then
                return dist <= rangeSquared
            end
        end
    end

    -- Method 2: CheckInteractDistance (1 = inspect, ~28 yards) - fallback for short range
    if rangeYards <= 30 then
        local ok2, canInteract = pcall(CheckInteractDistance, unit, 1)
        if ok2 and canInteract ~= nil then
            local result = SafeBooleanCheck(canInteract)
            if result ~= nil then
                return result
            end
        end
    end

    -- Method 3: UnitInRange (~28 yards) - fallback
    local ok, inRange, checkedRange = pcall(UnitInRange, unit)
    if ok then
        local safeChecked = SafeBooleanCheck(checkedRange)
        if safeChecked then
            local safeInRange = SafeBooleanCheck(inRange)
            if safeInRange ~= nil then
                -- UnitInRange is ~28 yards, if checking longer range assume in range if UnitInRange returns true
                if rangeYards > 28 and safeInRange then
                    return true
                end
                return safeInRange
            end
        end
    end

    -- Can't determine range, assume in range
    return true
end

-- Safe unit check for Midnight beta (multiple APIs return secret values)
-- Returns true if unit is valid, alive, connected, and in range
local function IsUnitAvailable(unit, rangeYards)
    -- Check each condition separately, handling secret values
    local exists = SafeBooleanCheck(UnitExists(unit))
    if not exists then return false end

    local dead = SafeBooleanCheck(UnitIsDeadOrGhost(unit))
    if dead == nil or dead then return false end  -- nil = secret, treat as unavailable

    local connected = SafeBooleanCheck(UnitIsConnected(unit))
    if connected == nil or not connected then return false end

    return IsUnitInRange(unit, rangeYards)
end

-- Safe wrapper for UnitClass (handles potential secret values in Midnight)
local function SafeUnitClass(unit)
    local ok, localized, class = pcall(UnitClass, unit)
    if ok and class and type(class) == "string" then
        return class
    end
    return nil
end

-- Safe aura field access for Midnight Beta
-- In 12.x Beta, aura data fields can be "secret values" that error on access
-- BUG-006: Also validate the value can be used in comparisons
local function SafeGetAuraField(auraData, fieldName)
    local success, value = pcall(function() return auraData[fieldName] end)
    if not success then return nil end
    -- Validate the value can be used in comparisons (secret values fail == operations)
    local compareOk = pcall(function() return value == value end)
    if not compareOk then return nil end
    return value
end

local function ScanGroupClasses()
    wipe(groupClasses)

    -- Always include player
    local playerClass = SafeUnitClass("player")
    if playerClass then
        groupClasses[playerClass] = true
    end

    -- Scan all group members for their classes (no range check - just need to know what classes exist)
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            local exists = SafeBooleanCheck(UnitExists(unit))
            local connected = SafeBooleanCheck(UnitIsConnected(unit))
            if exists and connected then
                local class = SafeUnitClass(unit)
                if class then
                    groupClasses[class] = true
                end
            end
        end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do
            local unit = "party" .. i
            local exists = SafeBooleanCheck(UnitExists(unit))
            local connected = SafeBooleanCheck(UnitIsConnected(unit))
            if exists and connected then
                local class = SafeUnitClass(unit)
                if class then
                    groupClasses[class] = true
                end
            end
        end
    end
end

-- Check if a unit has a buff by spell ID, with name-based fallback.
-- Uses point queries first (O(1)), falls back to iteration only as last resort.
-- buffIDs: optional table of variant spell IDs to check (e.g., {1459, 432778} for Arcane Intellect)
local function UnitHasBuff(unit, spellId, spellName, buffIDs)
    if not unit then return false end
    local exists = SafeBooleanCheck(UnitExists(unit))
    if not exists then return false end

    -- Method 1: Point query by spell ID (O(1) engine lookup)
    if C_UnitAuras then
        local idsToCheck = buffIDs or (spellId and { spellId })
        if idsToCheck then
            if unit == "player" and C_UnitAuras.GetPlayerAuraBySpellID then
                for _, id in ipairs(idsToCheck) do
                    local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
                    if ok and auraData then return true end
                end
            elseif C_UnitAuras.GetAuraDataBySpellName and spellName then
                local ok, auraData = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, spellName, "HELPFUL")
                if ok and auraData then return true end
            end
        end
    end

    -- Method 2: Name-based point query (for non-player units when Method 1 didn't try it)
    if spellName and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName and unit == "player" then
        local ok, auraData = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, spellName, "HELPFUL")
        if ok and auraData then return true end
    end

    -- Method 3: ForEachAura iteration (last resort — handles talent variants, spell ID mismatches)
    if AuraUtil and AuraUtil.ForEachAura then
        local idSet
        if buffIDs then
            idSet = {}
            for _, id in ipairs(buffIDs) do idSet[id] = true end
        end
        local found = false
        AuraUtil.ForEachAura(unit, "HELPFUL", nil, function(auraData)
            if auraData then
                local auraSpellId = SafeGetAuraField(auraData, "spellId")
                local auraName = SafeGetAuraField(auraData, "name")
                if auraSpellId then
                    if idSet and idSet[auraSpellId] then
                        found = true
                    elseif auraSpellId == spellId then
                        found = true
                    end
                end
                if not found and spellName and auraName and auraName == spellName then
                    found = true
                end
            end
            if found then return true end
        end, true)
        if found then return true end
    end

    return false
end

-- Check if player has a buff (convenience wrapper)
local function PlayerHasBuff(spellId, spellName, buffIDs)
    return UnitHasBuff("player", spellId, spellName, buffIDs)
end

-- Check if player has a buff, with toggle aura fallback (for raid buff entries)
-- Toggle auras (e.g. Devotion Aura) don't place a HELPFUL buff on the caster when solo
local function PlayerHasRaidBuff(buff)
    if PlayerHasBuff(buff.spellId, buff.name, buff.buffIDs) then
        return true
    end
    if buff.isToggleAura and buff.castSpellId and IsCurrentSpell then
        local ok, current = pcall(IsCurrentSpell, buff.castSpellId)
        if ok and current then return true end
    end
    return false
end

-- Check if any available group member is missing a specific buff
local function AnyGroupMemberMissingBuff(spellId, spellName, rangeYards, buffIDs)
    -- Check player first
    if not PlayerHasBuff(spellId, spellName, buffIDs) then
        return true
    end

    -- Check party/raid members
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            local isPlayer = UnitIsUnit(unit, "player")
            if IsUnitAvailable(unit, rangeYards) and not IsSecretValue(isPlayer) and not isPlayer then
                if not UnitHasBuff(unit, spellId, spellName, buffIDs) then
                    return true
                end
            end
        end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do
            local unit = "party" .. i
            if IsUnitAvailable(unit, rangeYards) then
                if not UnitHasBuff(unit, spellId, spellName, buffIDs) then
                    return true
                end
            end
        end
    end

    return false
end

-- Count how many group members have a specific buff and total group size
local function CountBuffedMembers(spellId, spellName, buffIDs)
    local buffed = 0
    local total = 0

    -- Check player
    total = total + 1
    if PlayerHasBuff(spellId, spellName, buffIDs) then
        buffed = buffed + 1
    end

    -- Check party/raid members
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            local isPlayer = UnitIsUnit(unit, "player")
            if not IsSecretValue(isPlayer) and not isPlayer then
                local exists = SafeBooleanCheck(UnitExists(unit))
                local connected = SafeBooleanCheck(UnitIsConnected(unit))
                if exists and connected then
                    total = total + 1
                    if UnitHasBuff(unit, spellId, spellName, buffIDs) then
                        buffed = buffed + 1
                    end
                end
            end
        end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do
            local unit = "party" .. i
            local exists = SafeBooleanCheck(UnitExists(unit))
            local connected = SafeBooleanCheck(UnitIsConnected(unit))
            if exists and connected then
                total = total + 1
                if UnitHasBuff(unit, spellId, spellName, buffIDs) then
                    buffed = buffed + 1
                end
            end
        end
    end

    return buffed, total
end

-- Get player's class
local function GetPlayerClass()
    return SafeUnitClass("player")
end

-- Check if the player can cast a specific raid buff (correct class + knows the spell)
local function PlayerCanCastBuff(buff)
    if not buff.castSpellId then return false end
    local playerClass = GetPlayerClass()
    if buff.providerClass ~= playerClass then return false end
    if IsPlayerSpell then
        return IsPlayerSpell(buff.castSpellId)
    end
    return false
end

-- Check if a self-buff requirement is satisfied
local function PlayerHasSelfBuff(entry)
    if entry.checkType == "playerAura" then
        if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
            for id in pairs(entry.anyBuffIDs) do
                local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
                if ok and aura then return true end
            end
        end
        return false
    elseif entry.checkType == "weaponEnchant" then
        local hasMH, _, _, mhID, hasOH, _, _, ohID = GetWeaponEnchantInfo()
        if entry.requiresShield then
            local ohItemID = GetInventoryItemID("player", 17)
            if not ohItemID then return true end  -- No OH item = skip this check
            local _, _, _, _, _, _, itemSubClass = C_Item.GetItemInfoInstant(ohItemID)
            if itemSubClass ~= 6 then return true end  -- Not a shield = skip
            return hasOH and entry.anyEnchantIDs[ohID] or false
        end
        return hasMH and entry.anyEnchantIDs[mhID] or false
    end
    return true  -- Unknown check type = assume satisfied
end

-- Resolve which spell to cast for a self-buff (first known spell from priority list)
local function ResolveSelfBuffCast(entry)
    if not entry.castPriority then return nil, nil end
    for _, id in ipairs(entry.castPriority) do
        if IsPlayerSpell and IsPlayerSpell(id) then
            local spellName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
            if spellName then return spellName, id end
        end
    end
    return nil, nil
end

-- Get icon for a self-buff (icon of the first known spell)
local function GetSelfBuffIcon(entry)
    if entry._resolvedSpellId then
        return GetBuffIcon(entry._resolvedSpellId)
    end
    for _, id in ipairs(entry.castPriority) do
        if IsPlayerSpell and IsPlayerSpell(id) then
            return GetBuffIcon(id)
        end
    end
    return GetBuffIcon(entry.castPriority[1])
end

-- Check if any unit of a given class is in range (for receiving buffs from them)
local function IsProviderClassInRange(providerClass, rangeYards)
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            local isPlayer = UnitIsUnit(unit, "player")
            if not IsSecretValue(isPlayer) and not isPlayer then
                local class = SafeUnitClass(unit)
                if class == providerClass and IsUnitAvailable(unit, rangeYards) then
                    return true
                end
            end
        end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do
            local unit = "party" .. i
            local class = SafeUnitClass(unit)
            if class == providerClass and IsUnitAvailable(unit, rangeYards) then
                return true
            end
        end
    end
    return false
end

local function GetRelevantBuffs()
    local result = {}
    local settings = GetSettings()

    -- Preview mode: return cached preview buffs (generated once when preview enabled)
    if previewMode and previewBuffs then
        return previewBuffs
    end

    -- Only show out of combat (always enforced)
    if InCombatLockdown() then
        return result
    end

    -- Disable during M+ keystones - aura data is protected during challenge mode
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() then
        return result
    end

    local playerClass = GetPlayerClass()

    -- Raid buffs: subject to group/instance filters
    local showRaidBuffs = true
    if settings.showOnlyInGroup and not IsInGroup() then
        showRaidBuffs = false
    end
    if settings.showOnlyInInstance and not ns.Utils.IsInInstancedContent() then
        showRaidBuffs = false
    end

    if showRaidBuffs then
        ScanGroupClasses()

        for _, buff in ipairs(RAID_BUFFS) do
            if settings.providerMode then
                -- Provider mode: only show buffs the player's class can provide that are missing
                if buff.providerClass == playerClass then
                    buff._hasBuff = PlayerHasRaidBuff(buff)
                    if not buff._hasBuff then
                        table_insert(result, buff)
                    end
                end
            else
                -- Default: show all buffs where provider class is in the group
                if groupClasses[buff.providerClass] then
                    buff._hasBuff = PlayerHasRaidBuff(buff)
                    table_insert(result, buff)
                end
            end
        end
    end

    -- Self-buffs: bypass group/instance filters (they matter solo)
    if settings.showSelfBuffs ~= false then
        for _, selfBuff in ipairs(SELF_BUFFS) do
            if selfBuff.providerClass == playerClass then
                local spellName, resolvedSpellId = ResolveSelfBuffCast(selfBuff)
                if spellName then
                    selfBuff._resolvedSpellName = spellName
                    selfBuff._resolvedSpellId = resolvedSpellId
                    selfBuff._hasBuff = PlayerHasSelfBuff(selfBuff)
                    if not selfBuff._hasBuff then
                        table_insert(result, selfBuff)
                    end
                end
            end
        end
    end

    return result
end

---------------------------------------------------------------------------
-- UI CREATION
---------------------------------------------------------------------------

local function CreateBuffIcon(parent, index)
    local button = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    button:SetSize(ICON_SIZE, ICON_SIZE)

    -- Background/border using backdrop (border settings applied in ApplyIconBorderSettings)
    local px = (QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(button)) or 1
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
        insets = { left = px, right = px, top = px, bottom = px }
    })
    button:SetBackdropColor(0, 0, 0, 0.8)

    -- Icon texture (inset dynamically based on border width)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", px, -px)
    button.icon:SetPoint("BOTTOMRIGHT", -px, px)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Buff count text (e.g., "11/18")
    button.countText = button:CreateFontString(nil, "OVERLAY")
    button.countText:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    button.countText:SetPoint("BOTTOM", button, "BOTTOM", 0, 2)
    button.countText:SetTextColor(1, 1, 1, 1)
    button.countText:Hide()

    -- Secure click-to-cast overlay (child of non-secure parent — hiding parent is safe in combat)
    button.clickButton = CreateFrame("Button", nil, button, "SecureActionButtonTemplate")
    button.clickButton:SetAllPoints()
    button.clickButton:RegisterForClicks("AnyUp", "AnyDown")
    button.isCastable = false

    -- Tooltip (on the secure overlay since it receives mouse events)
    button.clickButton:SetScript("OnEnter", function(self)
        local icon = self:GetParent()
        if icon.buffData then
            GameTooltip:SetOwner(icon, "ANCHOR_RIGHT")
            GameTooltip:AddLine(icon.buffData.name, 1, 1, 1)
            GameTooltip:AddLine(icon.buffData.stat, 0.7, 0.7, 0.7)
            GameTooltip:AddLine(" ")
            if icon.buffData.selfBuff then
                GameTooltip:AddLine("Self-buff", 0.5, 0.8, 1)
            else
                local className = LOCALIZED_CLASS_NAMES_MALE[icon.buffData.providerClass] or icon.buffData.providerClass
                GameTooltip:AddLine("Provided by: " .. className, 0.5, 0.8, 1)
                if icon.buffCount and icon.buffTotal then
                    GameTooltip:AddLine(string_format("Buffed: %d/%d", icon.buffCount, icon.buffTotal), 0.7, 1, 0.7)
                end
            end
            if icon.isCastable then
                GameTooltip:AddLine("Click to cast", 0.2, 1, 0.2)
            end
            GameTooltip:Show()
        end
    end)
    button.clickButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return button
end

-- Apply border settings to icons
local function ApplyIconBorderSettings()
    local settings = GetSettings()
    local borderSettings = settings.iconBorder or { show = true, width = 1, useClassColor = false, color = { 0.376, 0.647, 0.980, 1 } }
    local borderWidth = borderSettings.show and (borderSettings.width or 1) or 0

    -- Determine border color
    local br, bg, bb, ba = 0.376, 0.647, 0.980, 1
    if borderSettings.useClassColor then
        local _, class = UnitClass("player")
        if class and RAID_CLASS_COLORS[class] then
            local classColor = RAID_CLASS_COLORS[class]
            br, bg, bb = classColor.r, classColor.g, classColor.b
        end
    elseif borderSettings.useAccentColor then
        local QUI = _G.QUI
        if QUI and QUI.GetAddonAccentColor then
            br, bg, bb, ba = QUI:GetAddonAccentColor()
        end
    elseif borderSettings.color then
        br = borderSettings.color[1] or 0.2
        bg = borderSettings.color[2] or 1.0
        bb = borderSettings.color[3] or 0.6
        ba = borderSettings.color[4] or 1
    else
        -- Use QUI skin color as fallback
        local QUI = _G.QUI
        if QUI and QUI.GetSkinColor then
            br, bg, bb, ba = QUI:GetSkinColor()
        end
    end

    for _, icon in ipairs(buffIcons) do
        -- Update backdrop with new border width (pixel-perfect)
        local bpx = QUICore:Pixels(borderWidth, icon)
        icon:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = borderSettings.show and "Interface\\Buttons\\WHITE8x8" or nil,
            edgeSize = bpx,
            insets = { left = bpx, right = bpx, top = bpx, bottom = bpx }
        })
        icon:SetBackdropColor(0, 0, 0, 0.8)

        if borderSettings.show then
            icon:SetBackdropBorderColor(br, bg, bb, ba)
        end

        -- Update icon inset based on border width
        icon.icon:ClearAllPoints()
        icon.icon:SetPoint("TOPLEFT", bpx, -bpx)
        icon.icon:SetPoint("BOTTOMRIGHT", -bpx, bpx)
    end
end

local function CreateMainFrame()
    if mainFrame then return mainFrame end

    -- Main container (invisible, just for positioning and dragging)
    mainFrame = CreateFrame("Frame", "QUI_MissingRaidBuffs", UIParent)
    mainFrame:SetSize(200, 70)
    mainFrame:SetPoint("TOP", UIParent, "TOP", 0, -200)
    mainFrame:SetFrameStrata("MEDIUM")
    mainFrame:SetClampedToScreen(true)
    mainFrame:EnableMouse(true)
    mainFrame:SetMovable(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", function(self)
        if _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("missingRaidBuffs") then return end
        if not InCombatLockdown() then
            self:StartMoving()
        end
    end)
    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Save position using grow-direction-appropriate anchor
        local settings = GetSettings()
        if settings then
            local growDir = settings.growDirection or "RIGHT"

            -- Determine the anchor point based on grow direction
            local desiredAnchor
            if growDir == "LEFT" then
                desiredAnchor = "TOPRIGHT"
            elseif growDir == "RIGHT" then
                desiredAnchor = "TOPLEFT"
            elseif growDir == "UP" then
                desiredAnchor = "BOTTOMLEFT"
            elseif growDir == "DOWN" then
                desiredAnchor = "TOPLEFT"
            else -- CENTER_H or CENTER_V
                desiredAnchor = "CENTER"
            end

            -- Get current position and frame size
            local point, _, relPoint, x, y = self:GetPoint()
            local frameWidth, frameHeight = self:GetSize()

            -- Convert to desired anchor position
            local newX, newY = x, y

            -- Horizontal conversion
            if point:find("LEFT") and desiredAnchor:find("RIGHT") then
                newX = x + frameWidth
            elseif point:find("RIGHT") and desiredAnchor:find("LEFT") then
                newX = x - frameWidth
            elseif (point == "CENTER" or point == "TOP" or point == "BOTTOM") then
                if desiredAnchor:find("LEFT") then
                    newX = x - frameWidth / 2
                elseif desiredAnchor:find("RIGHT") then
                    newX = x + frameWidth / 2
                end
            elseif (point:find("LEFT") or point:find("RIGHT")) and (desiredAnchor == "CENTER" or desiredAnchor == "TOP" or desiredAnchor == "BOTTOM") then
                if point:find("LEFT") then
                    newX = x + frameWidth / 2
                else
                    newX = x - frameWidth / 2
                end
            end

            -- Vertical conversion
            if point:find("TOP") and desiredAnchor:find("BOTTOM") then
                newY = y - frameHeight
            elseif point:find("BOTTOM") and desiredAnchor:find("TOP") then
                newY = y + frameHeight
            elseif (point == "CENTER" or point == "LEFT" or point == "RIGHT") then
                if desiredAnchor:find("TOP") then
                    newY = y + frameHeight / 2
                elseif desiredAnchor:find("BOTTOM") then
                    newY = y - frameHeight / 2
                end
            elseif (point:find("TOP") or point:find("BOTTOM")) and (desiredAnchor == "CENTER" or desiredAnchor == "LEFT" or desiredAnchor == "RIGHT") then
                if point:find("TOP") then
                    newY = y - frameHeight / 2
                else
                    newY = y + frameHeight / 2
                end
            end

            -- Snap to pixel grid and save
            newX = QUICore:PixelRound(newX)
            newY = QUICore:PixelRound(newY)
            self:ClearAllPoints()
            self:SetPoint(desiredAnchor, UIParent, relPoint, newX, newY)
            settings.position = { point = desiredAnchor, relPoint = relPoint, x = newX, y = newY }
        end
    end)

    -- Container for buff icons (icons go here)
    mainFrame.iconContainer = CreateFrame("Frame", nil, mainFrame)
    mainFrame.iconContainer:SetPoint("TOP", mainFrame, "TOP", 0, 0)
    mainFrame.iconContainer:SetSize(200, ICON_SIZE)

    -- Label bar below icons (skinned background with text)
    mainFrame.labelBar = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    mainFrame.labelBar:SetPoint("TOP", mainFrame.iconContainer, "BOTTOM", 0, -2)
    mainFrame.labelBar:SetSize(100, 18)
    local labelPx = QUICore:GetPixelSize(mainFrame.labelBar)
    mainFrame.labelBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = labelPx,
        insets = { left = labelPx, right = labelPx, top = labelPx, bottom = labelPx }
    })
    mainFrame.labelBar:SetBackdropColor(0.05, 0.05, 0.05, 0.95)

    -- Label text
    mainFrame.labelBar.text = mainFrame.labelBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mainFrame.labelBar.text:SetPoint("CENTER", 0, 0)
    mainFrame.labelBar.text:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    mainFrame.labelBar.text:SetText("Raid Buffs")

    -- Pre-create icon slots
    for i = 1, #RAID_BUFFS do
        buffIcons[i] = CreateBuffIcon(mainFrame.iconContainer, i)
        buffIcons[i]:Hide()
    end

    mainFrame:Hide()

    return mainFrame
end

---------------------------------------------------------------------------
-- SKINNING
---------------------------------------------------------------------------

local function ApplySkin()
    if not mainFrame then return end

    local QUI = _G.QUI
    local sr, sg, sb, sa = 0.376, 0.647, 0.980, 1
    local bgr, bgg, bgb, bga = 0.05, 0.05, 0.05, 0.95

    if QUI and QUI.GetSkinColor then
        sr, sg, sb, sa = QUI:GetSkinColor()
    end
    if QUI and QUI.GetSkinBgColor then
        bgr, bgg, bgb, bga = QUI:GetSkinBgColor()
    end

    -- Apply skin to label bar
    if mainFrame.labelBar then
        mainFrame.labelBar:SetBackdropColor(bgr, bgg, bgb, bga)
        mainFrame.labelBar:SetBackdropBorderColor(sr, sg, sb, sa)
        if mainFrame.labelBar.text then
            -- Use custom text color if set, otherwise default to white for readability
            local settings = GetSettings()
            local textColor = settings.labelTextColor
            if textColor then
                mainFrame.labelBar.text:SetTextColor(textColor[1], textColor[2], textColor[3], 1)
            else
                mainFrame.labelBar.text:SetTextColor(1, 1, 1, 1)  -- White default
            end
        end
    end

    -- Apply icon border settings (handles border visibility, color, and width)
    ApplyIconBorderSettings()

    mainFrame.quiSkinColor = { sr, sg, sb, sa }
    mainFrame.quiBgColor = { bgr, bgg, bgb, bga }
end

-- Expose refresh function for live color updates
function QUI_RaidBuffs:RefreshColors()
    ApplySkin()
end

-- Full refresh (settings changed from options panel)
function QUI_RaidBuffs:Refresh()
    if mainFrame then
        ApplyIconBorderSettings()
        ApplySkin()
    end
    UpdateDisplay()
end


_G.QUI_RefreshRaidBuffs = function()
    QUI_RaidBuffs:Refresh()
end

---------------------------------------------------------------------------
-- UPDATE LOGIC
---------------------------------------------------------------------------

UpdateDisplay = function()
    local settings = GetSettings()
    local inCombat = InCombatLockdown()
    if not settings.enabled then
        if mainFrame then
            if inCombat then mainFrame:SetAlpha(0) else mainFrame:Hide() end
        end
        return
    end

    if not mainFrame then
        CreateMainFrame()
        ApplySkin()
    end

    local missing = GetRelevantBuffs()

    if #missing == 0 then
        if inCombat then mainFrame:SetAlpha(0) else mainFrame:Hide() end
        return
    end

    -- Position icons based on grow direction
    local iconSize = settings.iconSize or ICON_SIZE
    local iconSpacing = settings.iconSpacing or ICON_SPACING
    local growDir = settings.growDirection or "RIGHT"
    local isVertical = (growDir == "UP" or growDir == "DOWN" or growDir == "CENTER_V")
    local totalSize = (#missing * iconSize) + ((#missing - 1) * iconSpacing)

    for i, icon in ipairs(buffIcons) do
        if i <= #missing then
            local buff = missing[i]
            icon:SetSize(iconSize, iconSize)
            icon:ClearAllPoints()

            local offset = (i - 1) * (iconSize + iconSpacing)

            if growDir == "RIGHT" then
                icon:SetPoint("LEFT", mainFrame.iconContainer, "LEFT", offset, 0)
            elseif growDir == "LEFT" then
                icon:SetPoint("RIGHT", mainFrame.iconContainer, "RIGHT", -offset, 0)
            elseif growDir == "CENTER_H" then
                local startX = -totalSize / 2 + iconSize / 2
                icon:SetPoint("CENTER", mainFrame.iconContainer, "CENTER", startX + offset, 0)
            elseif growDir == "UP" then
                icon:SetPoint("BOTTOM", mainFrame.iconContainer, "BOTTOM", 0, offset)
            elseif growDir == "DOWN" then
                icon:SetPoint("TOP", mainFrame.iconContainer, "TOP", 0, -offset)
            elseif growDir == "CENTER_V" then
                local startY = -totalSize / 2 + iconSize / 2
                icon:SetPoint("CENTER", mainFrame.iconContainer, "CENTER", 0, startY + offset)
            end

            -- Set icon texture (self-buffs resolve dynamically)
            if buff.selfBuff then
                icon.icon:SetTexture(GetSelfBuffIcon(buff))
            else
                icon.icon:SetTexture(GetBuffIcon(buff.spellId))
            end
            icon.buffData = buff

            -- Visual states based on buff status
            local canCast = buff.selfBuff and buff._resolvedSpellName or (not buff.selfBuff and PlayerCanCastBuff(buff))
            local hasBuff = buff._hasBuff

            if hasBuff then
                -- Have the buff: saturated, no glow
                icon.icon:SetDesaturated(false)
                icon.icon:SetVertexColor(1, 1, 1, 1)
                if LCG then LCG.AutoCastGlow_Stop(icon) end
            elseif canCast then
                -- Missing, player can cast: desaturated + glow
                icon.icon:SetDesaturated(true)
                icon.icon:SetVertexColor(1, 1, 1, 1)
                if LCG then LCG.AutoCastGlow_Start(icon, { 0.2, 1, 0.2, 1 }, 8, 0.25) end
            else
                -- Missing, someone else provides: desaturated
                icon.icon:SetDesaturated(true)
                icon.icon:SetVertexColor(0.6, 0.6, 0.6, 1)
                if LCG then LCG.AutoCastGlow_Stop(icon) end
            end

            -- Configure click-to-cast — SetAttribute is protected, skip during combat
            if not inCombat then
                if not previewMode then
                    if buff.selfBuff and buff._resolvedSpellName then
                        icon.clickButton:SetAttribute("type", "spell")
                        icon.clickButton:SetAttribute("spell", buff._resolvedSpellName)
                        icon.isCastable = true
                    elseif not buff.selfBuff and PlayerCanCastBuff(buff) then
                        local spellName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(buff.castSpellId)
                        if spellName then
                            icon.clickButton:SetAttribute("type", "spell")
                            icon.clickButton:SetAttribute("spell", spellName)
                            icon.isCastable = true
                        else
                            icon.clickButton:SetAttribute("type", nil)
                            icon.clickButton:SetAttribute("spell", nil)
                            icon.isCastable = false
                        end
                    else
                        icon.clickButton:SetAttribute("type", nil)
                        icon.clickButton:SetAttribute("spell", nil)
                        icon.isCastable = false
                    end
                else
                    icon.clickButton:SetAttribute("type", nil)
                    icon.clickButton:SetAttribute("spell", nil)
                    icon.isCastable = false
                end
            end

            -- Update buff count display (skip for self-buffs — they're player-only)
            local countSettings = settings.buffCount or { show = false }
            if not buff.selfBuff and countSettings.show and icon.countText then
                local buffed, total = CountBuffedMembers(buff.spellId, buff.name, buff.buffIDs)
                icon.buffCount = buffed
                icon.buffTotal = total
                icon.countText:SetText(string_format("%d/%d", buffed, total))

                -- Apply font settings
                local countFontSize = countSettings.fontSize or 10
                local countFontName = countSettings.font or "Quazii"
                local countFontPath = STANDARD_TEXT_FONT
                if LSM then
                    countFontPath = LSM:Fetch("font", countFontName) or STANDARD_TEXT_FONT
                end
                icon.countText:SetFont(countFontPath, countFontSize, "OUTLINE")

                -- Apply color settings
                local countColor = countSettings.color or { 1, 1, 1, 1 }
                icon.countText:SetTextColor(countColor[1] or 1, countColor[2] or 1, countColor[3] or 1, countColor[4] or 1)

                -- Apply position with offsets
                icon.countText:ClearAllPoints()
                local countPos = countSettings.position or "BOTTOM"
                local offsetX = countSettings.offsetX or 0
                local offsetY = countSettings.offsetY or 0
                if countPos == "TOP" then
                    icon.countText:SetPoint("BOTTOM", icon, "TOP", offsetX, 2 + offsetY)
                elseif countPos == "BOTTOM" then
                    icon.countText:SetPoint("TOP", icon, "BOTTOM", offsetX, -2 + offsetY)
                elseif countPos == "LEFT" then
                    icon.countText:SetPoint("RIGHT", icon, "LEFT", -2 + offsetX, offsetY)
                elseif countPos == "RIGHT" then
                    icon.countText:SetPoint("LEFT", icon, "RIGHT", 2 + offsetX, offsetY)
                end

                if inCombat then icon.countText:SetAlpha(1) else icon.countText:Show() end
            elseif icon.countText then
                if inCombat then icon.countText:SetAlpha(0) else icon.countText:Hide() end
            end

            if inCombat then icon:SetAlpha(1) else icon:Show() end
        else
            if LCG then LCG.AutoCastGlow_Stop(icon) end
            if inCombat then
                icon:SetAlpha(0)
            else
                icon:Hide()
            end
            if icon.countText then
                if inCombat then icon.countText:SetAlpha(0) else icon.countText:Hide() end
            end
            -- Clear secure attributes on hidden icons (skip in combat)
            if not inCombat and icon.clickButton then
                icon.clickButton:SetAttribute("type", nil)
                icon.clickButton:SetAttribute("spell", nil)
                icon.isCastable = false
            end
        end
    end

    -- Layout, sizing, and positioning use protected APIs — skip during combat
    if not inCombat then
        -- Update label font size and calculate bar height
        local fontSize = settings.labelFontSize or 12
        local labelBarHeight = fontSize + 8  -- Font size + padding
        local labelBarGap = 2

        mainFrame.labelBar.text:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
        mainFrame.labelBar.text:SetText("Raid Buffs")

        -- Resize frames based on orientation
        local hideLabelBar = settings.hideLabelBar
        local minIconsSize = (3 * iconSize) + (2 * iconSpacing)  -- 3 icons minimum
        local minTextWidth = fontSize * 8 + 10  -- Approximate text width + padding

        -- Update icon container and label bar anchoring based on grow direction
        mainFrame.iconContainer:ClearAllPoints()
        mainFrame.labelBar:ClearAllPoints()

        if isVertical then
            -- Vertical layout
            local containerHeight = totalSize
            local containerWidth = iconSize
            mainFrame.iconContainer:SetSize(containerWidth, containerHeight)

            if hideLabelBar then
                mainFrame.labelBar:Hide()
                -- Position container based on vertical grow direction
                if growDir == "UP" then
                    mainFrame.iconContainer:SetPoint("BOTTOM", mainFrame, "BOTTOM", 0, 0)
                elseif growDir == "DOWN" then
                    mainFrame.iconContainer:SetPoint("TOP", mainFrame, "TOP", 0, 0)
                else -- CENTER_V
                    mainFrame.iconContainer:SetPoint("CENTER", mainFrame, "CENTER", 0, 0)
                end
                mainFrame:SetSize(containerWidth, containerHeight)
            else
                local frameWidth = math.max(containerWidth, minTextWidth)
                mainFrame.labelBar:SetSize(frameWidth, labelBarHeight)
                mainFrame.labelBar:Show()
                -- Label bar below icons for vertical
                mainFrame.iconContainer:SetPoint("TOP", mainFrame, "TOP", 0, 0)
                mainFrame.labelBar:SetPoint("TOP", mainFrame.iconContainer, "BOTTOM", 0, -labelBarGap)
                mainFrame:SetSize(frameWidth, containerHeight + labelBarGap + labelBarHeight)
            end
        else
            -- Horizontal layout
            local frameWidth = math.max(totalSize, hideLabelBar and 0 or math.max(minIconsSize, minTextWidth))
            mainFrame.iconContainer:SetSize(totalSize, iconSize)

            if hideLabelBar then
                mainFrame.labelBar:Hide()
                -- Position container based on horizontal grow direction
                if growDir == "LEFT" then
                    mainFrame.iconContainer:SetPoint("RIGHT", mainFrame, "RIGHT", 0, 0)
                elseif growDir == "RIGHT" then
                    mainFrame.iconContainer:SetPoint("LEFT", mainFrame, "LEFT", 0, 0)
                else -- CENTER_H
                    mainFrame.iconContainer:SetPoint("CENTER", mainFrame, "CENTER", 0, 0)
                end
                mainFrame:SetSize(totalSize, iconSize)
            else
                mainFrame.iconContainer:SetSize(frameWidth, iconSize)
                mainFrame.iconContainer:SetPoint("TOP", mainFrame, "TOP", 0, 0)
                mainFrame.labelBar:SetSize(frameWidth, labelBarHeight)
                mainFrame.labelBar:Show()
                mainFrame.labelBar:SetPoint("TOP", mainFrame.iconContainer, "BOTTOM", 0, -labelBarGap)
                mainFrame:SetSize(frameWidth, iconSize + labelBarGap + labelBarHeight)
            end
        end

        -- Restore saved position (skip if anchoring system has overridden this frame)
        -- Position is saved using grow-direction-appropriate anchor, so icons stay in place
        if settings.position and not (_G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("missingRaidBuffs")) then
            mainFrame:ClearAllPoints()
            mainFrame:SetPoint(settings.position.point, UIParent, settings.position.relPoint, settings.position.x, settings.position.y)
        end
    end

    if inCombat then mainFrame:SetAlpha(1) else mainFrame:Show() end
end

local function ThrottledUpdate()
    local now = GetTime()
    if now - lastUpdate < UPDATE_THROTTLE then return end
    lastUpdate = now
    UpdateDisplay()
end

---------------------------------------------------------------------------
-- EVENT HANDLING
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")

-- Forward declaration for range check functions (defined after event handling)
local StartRangeCheck, StopRangeCheck

local function OnEvent(self, event, ...)
    local settings = GetSettings()

    -- Handle range check ticker start/stop regardless of enabled state
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName ~= ADDON_NAME then return end
        self:UnregisterEvent("ADDON_LOADED")
    end

    if event == "ADDON_LOADED" or event == "GROUP_ROSTER_UPDATE" then
        if settings and settings.enabled and IsInGroup() then
            if StartRangeCheck then StartRangeCheck() end
        else
            if StopRangeCheck then StopRangeCheck() end
        end
    end

    if not settings or not settings.enabled then return end

    if event == "ADDON_LOADED" then
        CreateMainFrame()
        ApplySkin()
        C_Timer.After(2, UpdateDisplay)
    elseif event == "GROUP_ROSTER_UPDATE" then
        ThrottledUpdate()
    -- UNIT_AURA handled by centralized dispatcher subscription (above)
    elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        ThrottledUpdate()
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        C_Timer.After(1, UpdateDisplay)
    elseif event == "PLAYER_DEAD" or event == "PLAYER_UNGHOST" then
        -- Player death/resurrect
        ThrottledUpdate()
    end
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
-- UNIT_AURA handled by centralized dispatcher (below)
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
-- UNIT_FLAGS intentionally NOT registered: it's a global event that fires
-- constantly in raids (PvP/AFK/DND/in-combat/CC state changes on every unit
-- in the world, including nameplates and targets). We only want "dead/alive"
-- signals for raid members, which are covered by PLAYER_DEAD/PLAYER_UNGHOST
-- (self) and the periodic range ticker (others, every 5s, out of combat only
-- — which is the only time this display is visible anyway).
eventFrame:RegisterEvent("PLAYER_DEAD")
eventFrame:RegisterEvent("PLAYER_UNGHOST")
eventFrame:SetScript("OnEvent", OnEvent)

ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "RaidBuffs", frame = eventFrame }

-- Subscribe to centralized aura dispatcher
if ns.AuraEvents then
    -- Roster filter handles player/party/raid membership at the dispatcher
    -- level — no string.match per event.
    ns.AuraEvents:Subscribe("roster", function(unit, updateInfo)
        local settings = GetSettings()
        if not settings or not settings.enabled then return end
        ThrottledUpdate()
    end)
end

-- Periodic range check (every 5 seconds when out of combat and in group)
local rangeCheckTicker

StopRangeCheck = function()
    if rangeCheckTicker then
        rangeCheckTicker:Cancel()
        rangeCheckTicker = nil
    end
end

StartRangeCheck = function()
    if rangeCheckTicker then return end
    rangeCheckTicker = C_Timer.NewTicker(5, function()
        local settings = GetSettings()
        if not settings or not settings.enabled then
            StopRangeCheck()
            return
        end
        if InCombatLockdown() then return end
        if not IsInGroup() then
            StopRangeCheck()
            return
        end
        UpdateDisplay()
    end)
end

---------------------------------------------------------------------------
-- PUBLIC API
---------------------------------------------------------------------------

function QUI_RaidBuffs:Toggle()
    local settings = GetSettings()
    settings.enabled = not settings.enabled
    UpdateDisplay()
end


function QUI_RaidBuffs:Debug()
    local settings = GetSettings()
    local lines = {}
    local playerClass = SafeUnitClass("player")
    table_insert(lines, "QUI RaidBuffs Debug")
    table_insert(lines, "Player Class: " .. (playerClass or "UNKNOWN"))
    table_insert(lines, "In Group: " .. (IsInGroup() and "YES" or "NO"))
    table_insert(lines, "In Raid: " .. (IsInRaid() and "YES" or "NO"))
    table_insert(lines, "In Combat: " .. (InCombatLockdown() and "YES" or "NO"))

    -- Scan and show group classes
    ScanGroupClasses()
    local classes = {}
    for class, _ in pairs(groupClasses) do
        table_insert(classes, class)
    end
    table_insert(lines, "Group Classes: " .. (#classes > 0 and table.concat(classes, ", ") or "NONE"))

    -- Show party members and their status
    table_insert(lines, "")
    table_insert(lines, "Party Members:")
    local numMembers = GetNumGroupMembers()
    table_insert(lines, "  GetNumGroupMembers: " .. numMembers)
    if IsInGroup() and not IsInRaid() then
        for i = 1, numMembers - 1 do
            local unit = "party" .. i
            local exists = SafeBooleanCheck(UnitExists(unit))
            local connected = SafeBooleanCheck(UnitIsConnected(unit))
            local dead = SafeBooleanCheck(UnitIsDeadOrGhost(unit))
            local available = IsUnitAvailable(unit)
            local name = UnitName(unit) or "?"
            local uClass = SafeUnitClass(unit)

            -- Detailed range check info (wrap everything for secret values)
            local uirRange, uirChecked = "?", "?"
            local ok1, r1, r2 = pcall(UnitInRange, unit)
            if ok1 then
                uirRange = IsSecretValue(r1) and "SECRET" or tostring(r1)
                uirChecked = IsSecretValue(r2) and "SECRET" or tostring(r2)
            end
            local cidResult = "?"
            local ok2, cid = pcall(CheckInteractDistance, unit, 1)
            if ok2 then
                cidResult = IsSecretValue(cid) and "SECRET" or tostring(cid)
            end
            local udsResult = "N/A"
            if UnitDistanceSquared then
                local ok3, distSq = pcall(UnitDistanceSquared, unit)
                if ok3 then
                    udsResult = IsSecretValue(distSq) and "SECRET" or tostring(distSq)
                end
            end
            local rangeInfo = " UnitInRange:" .. uirRange .. "/" .. uirChecked .. " CheckInteract:" .. cidResult .. " DistSq:" .. udsResult

            table_insert(lines, "  " .. unit .. ": " .. name .. " (" .. (uClass or "?") .. ") exists:" .. tostring(exists) .. " connected:" .. tostring(connected) .. " dead:" .. tostring(dead) .. " available:" .. tostring(available))
            table_insert(lines, "    Range APIs:" .. rangeInfo)
        end
    end

    -- Check each buff
    table_insert(lines, "")
    table_insert(lines, "Buff Status:")
    for _, buff in ipairs(RAID_BUFFS) do
        local buffRange = buff.range or 40
        local hasProvider = groupClasses[buff.providerClass] and true or false
        local providerInRange = IsProviderClassInRange(buff.providerClass, buffRange)
        local playerHas = PlayerHasBuff(buff.spellId, buff.name, buff.buffIDs)
        local canProvide = PlayerCanCastBuff(buff)
        local anyMissing = AnyGroupMemberMissingBuff(buff.spellId, buff.name, buffRange, buff.buffIDs)
        local status = ""
        if hasProvider and not playerHas then
            if providerInRange then
                status = "MISSING"
            else
                status = "MISSING (out of range)"
            end
        elseif playerHas then
            status = "HAVE"
        else
            status = "No provider"
        end
        local providerInfo = " range:" .. buffRange .. "yd canProvide:" .. tostring(canProvide) .. " anyMissing:" .. tostring(anyMissing) .. " providerInRange:" .. tostring(providerInRange)
        table_insert(lines, "  " .. buff.name .. ": " .. status .. " (provider:" .. buff.providerClass .. " inGroup:" .. tostring(hasProvider) .. " hasBuff:" .. tostring(playerHas) .. providerInfo .. ")")

        -- If player can provide this buff, show who's missing it
        if canProvide and IsInGroup() and not IsInRaid() then
            for i = 1, numMembers - 1 do
                local unit = "party" .. i
                if IsUnitAvailable(unit, buffRange) then
                    local has = UnitHasBuff(unit, buff.spellId, buff.name, buff.buffIDs)
                    local name = UnitName(unit) or "?"
                    table_insert(lines, "    -> " .. unit .. " (" .. name .. "): " .. (has and "HAS" or "MISSING"))
                end
            end
        end
    end

    -- Output as error so it can be copied
    error(table.concat(lines, "\n"), 0)
end

-- Slash command for debug
SLASH_QUIRAIDBUFFS1 = "/quibuffs"
SlashCmdList["QUIRAIDBUFFS"] = function()
    if ns.RaidBuffs then
        ns.RaidBuffs:Debug()
    end
end

function QUI_RaidBuffs:GetFrame()
    return mainFrame
end

function QUI_RaidBuffs:TogglePreview()
    if previewMode then
        self:DisablePreview()
    else
        self:EnablePreview()
    end
    return previewMode
end

function QUI_RaidBuffs:EnablePreview()
    previewMode = true
    previewBuffs = {}
    for i, buff in ipairs(RAID_BUFFS) do
        previewBuffs[i] = buff
    end
    -- Include self-buffs for current class in preview
    local playerClass = GetPlayerClass()
    for _, selfBuff in ipairs(SELF_BUFFS) do
        if selfBuff.providerClass == playerClass then
            local spellName, resolvedId = ResolveSelfBuffCast(selfBuff)
            if spellName then
                selfBuff._resolvedSpellName = spellName
                selfBuff._resolvedSpellId = resolvedId
            end
            table_insert(previewBuffs, selfBuff)
        end
    end
    UpdateDisplay()
end

function QUI_RaidBuffs:DisablePreview()
    previewMode = false
    previewBuffs = nil
    UpdateDisplay()
end

function QUI_RaidBuffs:IsPreviewMode()
    return previewMode
end


if ns.Registry then
    ns.Registry:Register("raidbuffs", {
        refresh = _G.QUI_RefreshRaidBuffs,
        priority = 20,
        group = "frames",
        importCategories = { "groupFrames" },
    })
end
