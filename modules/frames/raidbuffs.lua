local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local LSM = LibStub("LibSharedMedia-3.0")
local Helpers = ns.Helpers
local IsSecretValue = Helpers.IsSecretValue
local SafeValue = Helpers.SafeValue

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
-- spellId: Primary spell ID for icon lookup (can be single ID or table of IDs)
-- name: Buff name for fallback detection (catches talent variants)
-- stat: What the buff provides (for tooltip)
-- providerClass: Which class provides this buff
-- range: Range in yards for checking if provider/target is reachable
-- NOTE: Name-based fallback catches talent-modified buffs with different spell IDs
local RAID_BUFFS = {
    {
        spellId = 21562,
        name = "Power Word: Fortitude",
        stat = "Stamina",
        providerClass = "PRIEST",
        range = 40,
    },
    {
        spellId = 6673,
        name = "Battle Shout",
        stat = "Attack Power",
        providerClass = "WARRIOR",
        range = 100,
    },
    {
        spellId = 1459,
        name = "Arcane Intellect",
        stat = "Intellect",
        providerClass = "MAGE",
        range = 40,
    },
    {
        spellId = 1126,
        name = "Mark of the Wild",
        stat = "Versatility",
        providerClass = "DRUID",
        range = 40,
    },
    {
        -- 381748 is the buff that appears on players, 364342 is the ability
        spellId = 381748,
        name = "Blessing of the Bronze",
        stat = "Movement Speed",
        providerClass = "EVOKER",
        range = 40,
    },
    {
        spellId = 462854,
        name = "Skyfury",
        stat = "Mastery",
        providerClass = "SHAMAN",
        range = 100,
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
    providerMode = false,
    hideLabelBar = false,        -- Hide the "Missing Buffs" label bar
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

-- Check if a unit has a buff by spell ID, with name-based fallback
-- Uses 3-method approach for maximum compatibility across WoW versions
local function UnitHasBuff(unit, spellId, spellName)
    if not unit then return false end
    local exists = SafeBooleanCheck(UnitExists(unit))
    if not exists then return false end

    -- Method 1: AuraUtil.ForEachAura (most reliable)
    if AuraUtil and AuraUtil.ForEachAura then
        local found = false
        AuraUtil.ForEachAura(unit, "HELPFUL", nil, function(auraData)
            if auraData then
                -- Use safe field access for Midnight Beta (12.x) secret values
                local auraSpellId = SafeGetAuraField(auraData, "spellId")
                local auraName = SafeGetAuraField(auraData, "name")
                if auraSpellId and auraSpellId == spellId then
                    found = true
                elseif spellName and auraName and auraName == spellName then
                    found = true
                end
            end
            if found then return true end
        end, true)
        if found then return true end
    end

    -- Method 2: GetAuraDataBySpellName
    if spellName and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        local success, auraData = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, spellName, "HELPFUL")
        if success and auraData then return true end
    end

    -- Method 3: GetAuraDataByIndex iteration
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, MAX_AURA_INDEX do
            local success, auraData = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
            if not success or not auraData then break end
            -- Use safe field access for Midnight Beta (12.x) secret values
            local auraSpellId = SafeGetAuraField(auraData, "spellId")
            local auraName = SafeGetAuraField(auraData, "name")
            if auraSpellId and auraSpellId == spellId then
                return true
            elseif spellName and auraName and auraName == spellName then
                return true
            end
        end
    end

    return false
end

-- Check if player has a buff (convenience wrapper)
local function PlayerHasBuff(spellId, spellName)
    return UnitHasBuff("player", spellId, spellName)
end

-- Check if any available group member is missing a specific buff
local function AnyGroupMemberMissingBuff(spellId, spellName, rangeYards)
    -- Check player first
    if not PlayerHasBuff(spellId, spellName) then
        return true
    end

    -- Check party/raid members
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            local isPlayer = UnitIsUnit(unit, "player")
            if IsUnitAvailable(unit, rangeYards) and not IsSecretValue(isPlayer) and not isPlayer then
                if not UnitHasBuff(unit, spellId, spellName) then
                    return true
                end
            end
        end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do
            local unit = "party" .. i
            if IsUnitAvailable(unit, rangeYards) then
                if not UnitHasBuff(unit, spellId, spellName) then
                    return true
                end
            end
        end
    end

    return false
end

-- Count how many group members have a specific buff and total group size
local function CountBuffedMembers(spellId, spellName)
    local buffed = 0
    local total = 0

    -- Check player
    total = total + 1
    if PlayerHasBuff(spellId, spellName) then
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
                    if UnitHasBuff(unit, spellId, spellName) then
                        buffed = buffed + 1
                    end
                end
            end
        end
        -- Adjust total since player is counted in raid roster
        total = total - 1
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do
            local unit = "party" .. i
            local exists = SafeBooleanCheck(UnitExists(unit))
            local connected = SafeBooleanCheck(UnitIsConnected(unit))
            if exists and connected then
                total = total + 1
                if UnitHasBuff(unit, spellId, spellName) then
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

local function GetMissingBuffs()
    local missing = {}
    local settings = GetSettings()

    -- Preview mode: return cached preview buffs (generated once when preview enabled)
    if previewMode and previewBuffs then
        return previewBuffs
    end

    -- Check if we should only show in group
    if settings.showOnlyInGroup and not IsInGroup() then
        return missing
    end

    -- Check if we should only show in instance
    if settings.showOnlyInInstance and not ns.Utils.IsInInstancedContent() then
        return missing
    end

    -- Only show out of combat (always enforced)
    if InCombatLockdown() then
        return missing
    end

    -- Disable during M+ keystones - aura data is protected during challenge mode
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() then
        return missing
    end

    -- Scan group composition
    ScanGroupClasses()

    local playerClass = GetPlayerClass()

    -- Check each raid buff
    for _, buff in ipairs(RAID_BUFFS) do
        local buffRange = buff.range or 40

        if settings.providerMode then
            -- Provider mode: ONLY show buffs YOU can provide that anyone (including yourself) is missing
            if buff.providerClass == playerClass then
                if not PlayerHasBuff(buff.spellId, buff.name) or AnyGroupMemberMissingBuff(buff.spellId, buff.name, buffRange) then
                    table.insert(missing, buff)
                end
            end
        else
            -- Normal mode: show buffs YOU are missing when provider is in group AND in range
            if groupClasses[buff.providerClass] and not PlayerHasBuff(buff.spellId, buff.name) then
                if IsProviderClassInRange(buff.providerClass, buffRange) then
                    table.insert(missing, buff)
                end
            end
        end
    end

    return missing
end

---------------------------------------------------------------------------
-- UI CREATION
---------------------------------------------------------------------------

local function CreateBuffIcon(parent, index)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(ICON_SIZE, ICON_SIZE)

    -- Background/border using backdrop (border settings applied in ApplyIconBorderSettings)
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    button:SetBackdropColor(0, 0, 0, 0.8)

    -- Icon texture (inset dynamically based on border width)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 1, -1)
    button.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Buff count text (e.g., "11/18")
    button.countText = button:CreateFontString(nil, "OVERLAY")
    button.countText:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    button.countText:SetPoint("BOTTOM", button, "BOTTOM", 0, 2)
    button.countText:SetTextColor(1, 1, 1, 1)
    button.countText:Hide()

    -- Tooltip
    button:SetScript("OnEnter", function(self)
        if self.buffData then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.buffData.name, 1, 1, 1)
            GameTooltip:AddLine(self.buffData.stat, 0.7, 0.7, 0.7)
            GameTooltip:AddLine(" ")
            local className = LOCALIZED_CLASS_NAMES_MALE[self.buffData.providerClass] or self.buffData.providerClass
            GameTooltip:AddLine("Provided by: " .. className, 0.5, 0.8, 1)
            if self.buffCount and self.buffTotal then
                GameTooltip:AddLine(string.format("Buffed: %d/%d", self.buffCount, self.buffTotal), 0.7, 1, 0.7)
            end
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return button
end

-- Apply border settings to icons
local function ApplyIconBorderSettings()
    local settings = GetSettings()
    local borderSettings = settings.iconBorder or { show = true, width = 1, useClassColor = false, color = { 0.2, 1.0, 0.6, 1 } }
    local borderWidth = borderSettings.show and (borderSettings.width or 1) or 0

    -- Determine border color
    local br, bg, bb, ba = 0.2, 1.0, 0.6, 1
    if borderSettings.useClassColor then
        local _, class = UnitClass("player")
        if class and RAID_CLASS_COLORS[class] then
            local classColor = RAID_CLASS_COLORS[class]
            br, bg, bb = classColor.r, classColor.g, classColor.b
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
        -- Update backdrop with new border width
        icon:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = borderSettings.show and "Interface\\Buttons\\WHITE8x8" or nil,
            edgeSize = borderWidth,
            insets = { left = borderWidth, right = borderWidth, top = borderWidth, bottom = borderWidth }
        })
        icon:SetBackdropColor(0, 0, 0, 0.8)

        if borderSettings.show then
            icon:SetBackdropBorderColor(br, bg, bb, ba)
        end

        -- Update icon inset based on border width
        icon.icon:ClearAllPoints()
        icon.icon:SetPoint("TOPLEFT", borderWidth, -borderWidth)
        icon.icon:SetPoint("BOTTOMRIGHT", -borderWidth, borderWidth)
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

            -- Re-anchor with desired point and save
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
    mainFrame.labelBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    mainFrame.labelBar:SetBackdropColor(0.05, 0.05, 0.05, 0.95)

    -- Label text
    mainFrame.labelBar.text = mainFrame.labelBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mainFrame.labelBar.text:SetPoint("CENTER", 0, 0)
    mainFrame.labelBar.text:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    mainFrame.labelBar.text:SetText("Missing Buffs")

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
    local sr, sg, sb, sa = 0.2, 1.0, 0.6, 1
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

_G.QUI_RefreshRaidBuffColors = function()
    QUI_RaidBuffs:RefreshColors()
end

_G.QUI_RefreshRaidBuffs = function()
    QUI_RaidBuffs:Refresh()
end

---------------------------------------------------------------------------
-- UPDATE LOGIC
---------------------------------------------------------------------------

UpdateDisplay = function()
    local settings = GetSettings()
    if not settings.enabled then
        if mainFrame then mainFrame:Hide() end
        return
    end

    if not mainFrame then
        CreateMainFrame()
        ApplySkin()
    end

    local missing = GetMissingBuffs()

    if #missing == 0 then
        mainFrame:Hide()
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

            icon.icon:SetTexture(GetBuffIcon(buff.spellId))
            icon.buffData = buff

            -- Update buff count display
            local countSettings = settings.buffCount or { show = false }
            if countSettings.show and icon.countText then
                local buffed, total = CountBuffedMembers(buff.spellId, buff.name)
                icon.buffCount = buffed
                icon.buffTotal = total
                icon.countText:SetText(string.format("%d/%d", buffed, total))

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

                icon.countText:Show()
            elseif icon.countText then
                icon.countText:Hide()
            end

            icon:Show()
        else
            icon:Hide()
            if icon.countText then
                icon.countText:Hide()
            end
        end
    end

    -- Update label font size and calculate bar height
    local fontSize = settings.labelFontSize or 12
    local labelBarHeight = fontSize + 8  -- Font size + padding
    local labelBarGap = 2

    mainFrame.labelBar.text:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
    mainFrame.labelBar.text:SetText("Missing Buffs")

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

    -- Restore saved position
    -- Position is saved using grow-direction-appropriate anchor, so icons stay in place
    if settings.position then
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint(settings.position.point, UIParent, settings.position.relPoint, settings.position.x, settings.position.y)
    end

    mainFrame:Show()
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
    if event == "PLAYER_LOGIN" or event == "GROUP_ROSTER_UPDATE" then
        if settings and settings.enabled and IsInGroup() then
            if StartRangeCheck then StartRangeCheck() end
        else
            if StopRangeCheck then StopRangeCheck() end
        end
    end

    if not settings or not settings.enabled then return end

    if event == "PLAYER_LOGIN" then
        CreateMainFrame()
        ApplySkin()
        C_Timer.After(2, UpdateDisplay)
    elseif event == "GROUP_ROSTER_UPDATE" then
        ThrottledUpdate()
    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" then
            -- Player aura changes use short throttle to prevent spam during buff/debuff application
            ThrottledUpdate()
        elseif unit and settings.providerMode and (unit:match("^party") or unit:match("^raid")) then
            -- In provider mode, also update when party/raid members' auras change
            ThrottledUpdate()
        end
    elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        ThrottledUpdate()
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        C_Timer.After(1, UpdateDisplay)
    elseif event == "UNIT_FLAGS" then
        -- Triggers when unit dies or resurrects
        local unit = ...
        if unit and (unit:match("^party") or unit:match("^raid")) then
            ThrottledUpdate()
        end
    elseif event == "PLAYER_DEAD" or event == "PLAYER_UNGHOST" then
        -- Player death/resurrect
        ThrottledUpdate()
    end
end

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("UNIT_FLAGS")
eventFrame:RegisterEvent("PLAYER_DEAD")
eventFrame:RegisterEvent("PLAYER_UNGHOST")
eventFrame:SetScript("OnEvent", OnEvent)

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

function QUI_RaidBuffs:ForceUpdate()
    UpdateDisplay()
    ApplySkin()
end

function QUI_RaidBuffs:Debug()
    local settings = GetSettings()
    local lines = {}
    local playerClass = SafeUnitClass("player")
    table.insert(lines, "QUI RaidBuffs Debug")
    table.insert(lines, "Provider Mode: " .. (settings.providerMode and "ON" or "OFF"))
    table.insert(lines, "Player Class: " .. (playerClass or "UNKNOWN"))
    table.insert(lines, "In Group: " .. (IsInGroup() and "YES" or "NO"))
    table.insert(lines, "In Raid: " .. (IsInRaid() and "YES" or "NO"))
    table.insert(lines, "In Combat: " .. (InCombatLockdown() and "YES" or "NO"))

    -- Scan and show group classes
    ScanGroupClasses()
    local classes = {}
    for class, _ in pairs(groupClasses) do
        table.insert(classes, class)
    end
    table.insert(lines, "Group Classes: " .. (#classes > 0 and table.concat(classes, ", ") or "NONE"))

    -- Show party members and their status
    table.insert(lines, "")
    table.insert(lines, "Party Members:")
    local numMembers = GetNumGroupMembers()
    table.insert(lines, "  GetNumGroupMembers: " .. numMembers)
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

            table.insert(lines, "  " .. unit .. ": " .. name .. " (" .. (uClass or "?") .. ") exists:" .. tostring(exists) .. " connected:" .. tostring(connected) .. " dead:" .. tostring(dead) .. " available:" .. tostring(available))
            table.insert(lines, "    Range APIs:" .. rangeInfo)
        end
    end

    -- Check each buff
    table.insert(lines, "")
    table.insert(lines, "Buff Status:")
    for _, buff in ipairs(RAID_BUFFS) do
        local buffRange = buff.range or 40
        local hasProvider = groupClasses[buff.providerClass] and true or false
        local providerInRange = IsProviderClassInRange(buff.providerClass, buffRange)
        local playerHas = PlayerHasBuff(buff.spellId, buff.name)
        local canProvide = buff.providerClass == playerClass
        local anyMissing = AnyGroupMemberMissingBuff(buff.spellId, buff.name, buffRange)
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
        table.insert(lines, "  " .. buff.name .. ": " .. status .. " (provider:" .. buff.providerClass .. " inGroup:" .. tostring(hasProvider) .. " hasBuff:" .. tostring(playerHas) .. providerInfo .. ")")

        -- If player can provide this buff and provider mode is on, show who's missing it
        if canProvide and settings.providerMode and IsInGroup() and not IsInRaid() then
            for i = 1, numMembers - 1 do
                local unit = "party" .. i
                if IsUnitAvailable(unit, buffRange) then
                    local has = UnitHasBuff(unit, buff.spellId, buff.name)
                    local name = UnitName(unit) or "?"
                    table.insert(lines, "    -> " .. unit .. " (" .. name .. "): " .. (has and "HAS" or "MISSING"))
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
    previewMode = not previewMode
    if previewMode then
        -- Show all raid buffs in preview mode
        previewBuffs = {}
        for i, buff in ipairs(RAID_BUFFS) do
            previewBuffs[i] = buff
        end
    else
        previewBuffs = nil
    end
    UpdateDisplay()
    return previewMode
end

function QUI_RaidBuffs:IsPreviewMode()
    return previewMode
end

-- Global function for options panel
_G.QUI_ToggleRaidBuffsPreview = function()
    if ns.RaidBuffs then
        return ns.RaidBuffs:TogglePreview()
    end
    return false
end
