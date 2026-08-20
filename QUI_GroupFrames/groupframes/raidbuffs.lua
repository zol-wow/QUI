local ADDON_NAME, ns = ...
local function CJKFont(fs, p, s, f)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fs, p, s, f)
    else
        fs:SetFont(p, s, f)
    end
end
local QUICore = ns.Addon
local LSM = ns.LSM
local Helpers = ns.Helpers
local IsSecretValue = Helpers.IsSecretValue
local MissingRaidBuffs = ns.QUI_GroupFrameMissingRaidBuffs

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

local QUI_RaidBuffs = {}
ns.RaidBuffs = QUI_RaidBuffs

local ICON_SIZE = 32
local ICON_SPACING = 4
local UPDATE_THROTTLE = 0.5

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
        spellId = 381748,
        buffIDs = { 381732, 381741, 381746, 381748, 381749, 381750, 381751, 381752, 381753, 381754, 381756, 381757, 381758 },
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
        isToggleAura = true,
    },
}

if MissingRaidBuffs and MissingRaidBuffs.RegisterSnapshotBuffIDs then
    for _, buff in ipairs(RAID_BUFFS) do
        MissingRaidBuffs:RegisterSnapshotBuffIDs(buff.buffIDs or buff.spellId)
    end
end

local SELF_BUFFS = {
    {
        name = "Weapon Enchant",
        stat = "Main Hand",
        providerClass = "SHAMAN",
        selfBuff = true,
        checkType = "weaponEnchant",
        anyEnchantIDs = { [5400] = true, [5401] = true, [6498] = true },
        castPriority = { 33757, 382021 },
    },
    {
        name = "Offhand Enchant",
        stat = "Off Hand",
        providerClass = "SHAMAN",
        selfBuff = true,
        checkType = "weaponEnchant",
        requiresDualWield = true,
        anyEnchantIDs = { [5400] = true, [5401] = true, [6498] = true },
        castPriority = { 318038 },
    },
    {
        name = "Shield Enchant",
        stat = "Off Hand",
        providerClass = "SHAMAN",
        selfBuff = true,
        checkType = "weaponEnchant",
        requiresShield = true,
        anyEnchantIDs = { [7587] = true, [7528] = true },
        castPriority = { 462757, 457481 },
    },
    {
        name = "Shield",
        stat = "Self-Buff",
        providerClass = "SHAMAN",
        selfBuff = true,
        checkType = "playerAura",
        anyBuffIDs = { [192106] = true, [52127] = true },
        castPriority = { 192106, 52127 },
    },
    {
        name = "Weapon Rite",
        stat = "Main Hand",
        providerClass = "PALADIN",
        selfBuff = true,
        checkType = "weaponEnchant",
        anyEnchantIDs = { [7143] = true, [7144] = true },
        castPriority = { 433568, 433583 },
    },
    {
        name = "Lethal Poison",
        stat = "Lethal",
        providerClass = "ROGUE",
        selfBuff = true,
        checkType = "playerAura",
        anyBuffIDs = { [2823] = true, [315584] = true, [8679] = true, [381664] = true },
        castPriority = { 2823, 315584, 8679, 381664 },
    },
    {
        name = "Non-Lethal Poison",
        stat = "Non-Lethal",
        providerClass = "ROGUE",
        selfBuff = true,
        checkType = "playerAura",
        anyBuffIDs = { [3408] = true, [5761] = true, [381637] = true },
        castPriority = { 3408, 5761, 381637 },
    },
    {
        name = "Combat Form",
        stat = "Self-Buff",
        providerClass = "DRUID",
        providerSpecIDs = { [103] = true },
        selfBuff = true,
        checkType = "shapeshiftForm",
        acceptableFormGlobals = { "DRUID_CAT_FORM", "DRUID_BEAR_FORM" },
        castPriority = { 768 },
    },
    {
        name = "Combat Form",
        stat = "Self-Buff",
        providerClass = "DRUID",
        providerSpecIDs = { [104] = true },
        selfBuff = true,
        checkType = "shapeshiftForm",
        acceptableFormGlobals = { "DRUID_BEAR_FORM", "DRUID_CAT_FORM" },
        castPriority = { 5487 },
    },
    {
        name = "Shadowform",
        stat = "Self-Buff",
        providerClass = "PRIEST",
        providerSpecIDs = { [258] = true },
        selfBuff = true,
        checkType = "shapeshiftForm",
        acceptableFormGlobals = { "PRIEST_SHADOWFORM" },
        castPriority = { 232698, 15473 },
    },
}

local ALLY_BUFFS = {
    {
        key = "beacon",
        name = "Beacon",
        label = "Beacon",
        providerClass = "PALADIN",
        providerSpecIDs = { [65] = true },
        ids = { 53563, 156910, 156322, 1244893 },
        iconSpellID = 53563,
    },
    {
        key = "earthShield",
        name = "Earth Shield",
        label = "Earth Shield",
        providerClass = "SHAMAN",
        providerSpecIDs = { [264] = true },
        ids = { 974, 383648 },
        iconSpellID = 974,
    },
    {
        key = "sourceOfMagic",
        name = "Source of Magic",
        label = "Source of Magic",
        providerClass = "EVOKER",
        providerSpecIDs = { [1473] = true },
        ids = { 369459 },
        iconSpellID = 369459,
    },
}
ns.QUI_AllyBuffs = ALLY_BUFFS

local function GetBuffIcon(spellId)
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(spellId)
    elseif GetSpellTexture then
        return GetSpellTexture(spellId)
    end
    return 134400
end

local mainFrame
local buffIcons = {}
local lastUpdate = 0
local lastLayoutKey
local groupClasses = {}
local previewMode = false
local previewBuffs = nil

local UpdateDisplay

local DEFAULTS = {
    enabled = true,
    showOnlyInGroup = true,
    showOnlyInInstance = false,
    providerMode = false,
    hideLabelBar = false,
    iconSize = 32,
    labelFontSize = 12,
    labelTextColor = nil,
    position = nil,
}

local function GetSettings()
    return Helpers.GetModuleSettings("raidBuffs", DEFAULTS)
end

if MissingRaidBuffs and MissingRaidBuffs.RegisterActivePredicate then
    MissingRaidBuffs:RegisterActivePredicate(function()
        local settings = GetSettings()
        return settings and settings.enabled
    end)
end

local function SafeBooleanCheck(value)
    if IsSecretValue(value) then
        return nil -- @secret-policy: reject-secret-value
    end
    return value
end

local function IsUnitInRange(unit, rangeYards)
    rangeYards = rangeYards or 40
    local rangeSquared = rangeYards * rangeYards

    if UnitDistanceSquared then
        local ok, distSq = pcall(UnitDistanceSquared, unit)
        if ok and distSq then
            local dist = SafeBooleanCheck(distSq)
            if dist and type(dist) == "number" then
                return dist <= rangeSquared
            end
        end
    end

    if rangeYards <= 30 then
        local ok2, canInteract = pcall(CheckInteractDistance, unit, 1)
        if ok2 and canInteract ~= nil then
            local result = SafeBooleanCheck(canInteract)
            if result ~= nil then
                return result
            end
        end
    end

    local ok, inRange, checkedRange = pcall(UnitInRange, unit)
    if ok then
        local safeChecked = SafeBooleanCheck(checkedRange)
        if safeChecked then
            local safeInRange = SafeBooleanCheck(inRange)
            if safeInRange ~= nil then
                return safeInRange
            end
        end
    end

    return true
end

local function IsUnitAvailable(unit, rangeYards)
    local exists = SafeBooleanCheck(UnitExists(unit))
    if not exists then return false end

    local dead = SafeBooleanCheck(UnitIsDeadOrGhost(unit))
    if dead == nil or dead then return false end

    local connected = SafeBooleanCheck(UnitIsConnected(unit))
    if connected == nil or not connected then return false end

    return IsUnitInRange(unit, rangeYards)
end

local function SafeUnitClass(unit)
    local ok, _, class = pcall(UnitClass, unit)
    if not ok then return nil end
    if IsSecretValue(class) then
        return nil -- @secret-policy: reject-secret-ids
    end
    if class and type(class) == "string" then
        return class
    end
    return nil
end

local function ScanGroupClasses()
    wipe(groupClasses)

    local playerClass = SafeUnitClass("player")
    if playerClass then
        groupClasses[playerClass] = true
    end

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

local function UnitHasBuff(unit, spellId, spellName, buffIDs)
    if not MissingRaidBuffs or not MissingRaidBuffs.UnitHasBuff then return false end
    return MissingRaidBuffs:UnitHasBuff(unit, buffIDs or spellId, spellName)
end

local function PlayerHasBuff(spellId, spellName, buffIDs)
    return UnitHasBuff("player", spellId, spellName, buffIDs)
end

local function PlayerHasRaidBuff(buff)
    local has = PlayerHasBuff(buff.spellId, buff.name, buff.buffIDs)
    if has == true then
        return true
    end
    if buff.isToggleAura and buff.castSpellId and IsCurrentSpell then
        local ok, current = pcall(IsCurrentSpell, buff.castSpellId)
        if ok and current then return true end
    end
    return has
end

local function AnyGroupMemberMissingBuff(spellId, spellName, rangeYards, buffIDs)
    if PlayerHasBuff(spellId, spellName, buffIDs) == false then
        return true
    end

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            local isPlayer = UnitIsUnit(unit, "player")
            if IsSecretValue(isPlayer) then isPlayer = true end
            if IsUnitAvailable(unit, rangeYards) and not isPlayer then
                if UnitHasBuff(unit, spellId, spellName, buffIDs) == false then
                    return true
                end
            end
        end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do
            local unit = "party" .. i
            if IsUnitAvailable(unit, rangeYards) then
                if UnitHasBuff(unit, spellId, spellName, buffIDs) == false then
                    return true
                end
            end
        end
    end

    return false
end

local function CountBuffedMembers(spellId, spellName, buffIDs)
    local buffed = 0
    local total = 0

    total = total + 1
    if PlayerHasBuff(spellId, spellName, buffIDs) then
        buffed = buffed + 1
    end

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            local isPlayer = UnitIsUnit(unit, "player")
            if IsSecretValue(isPlayer) then isPlayer = true end
            if not isPlayer then
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

local function GetPlayerClass()
    return SafeUnitClass("player")
end

local function PlayerCanCastBuff(buff)
    if not buff.castSpellId then return false end
    local playerClass = GetPlayerClass()
    if buff.providerClass ~= playerClass then return false end
    if IsPlayerSpell then
        return IsPlayerSpell(buff.castSpellId)
    end
    return false
end

local function OffhandEnchantSatisfied(entry, hasOH, ohID, fieldIndex, expected)
    local ohItemID = GetInventoryItemID("player", 17)
    if not ohItemID then return true end
    local field = select(fieldIndex, C_Item.GetItemInfoInstant(ohItemID))
    if field ~= expected then return true end
    return hasOH and entry.anyEnchantIDs[ohID] or false
end

local function PlayerHasSelfBuff(entry)
    if entry.checkType == "playerAura" then
        if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
            for id in pairs(entry.anyBuffIDs) do
                local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
                if ok then
                    if IsSecretValue(aura) then
                    elseif aura then
                        return true
                    end
                end
            end
        end
        return false
    elseif entry.checkType == "weaponEnchant" then
        local hasMH, _, _, mhID, hasOH, _, _, ohID = GetWeaponEnchantInfo()
        if entry.requiresShield then
            return OffhandEnchantSatisfied(entry, hasOH, ohID, 7, 6)
        end
        if entry.requiresDualWield then
            return OffhandEnchantSatisfied(entry, hasOH, ohID, 6, 2)
        end
        return hasMH and entry.anyEnchantIDs[mhID] or false
    elseif entry.checkType == "shapeshiftForm" then
        if not entry.acceptableFormGlobals or not GetShapeshiftFormID then return true end
        local form = GetShapeshiftFormID()
        if form == nil then return true end
        for _, gname in ipairs(entry.acceptableFormGlobals) do
            local fid = _G[gname]
            if fid and form == fid then return true end
        end
        return false
    end
    return true
end

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

local function IsProviderClassInRange(providerClass, rangeYards)
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            local isPlayer = UnitIsUnit(unit, "player")
            if IsSecretValue(isPlayer) then isPlayer = true end
            if not isPlayer then
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

    if previewMode and previewBuffs then
        return previewBuffs
    end

    if InCombatLockdown() then
        return result
    end

    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() then
        return result
    end

    local playerClass = GetPlayerClass()

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
                if buff.providerClass == playerClass then
                    buff._hasBuff = PlayerHasRaidBuff(buff)
                    if buff._hasBuff == false then
                        table_insert(result, buff)
                    end
                end
            else
                if groupClasses[buff.providerClass] then
                    buff._hasBuff = PlayerHasRaidBuff(buff)
                    if buff._hasBuff == false then
                        table_insert(result, buff)
                    end
                end
            end
        end

        if ns.QUI_AllyBuffs and MissingRaidBuffs then
            for _, buff in ipairs(ns.QUI_AllyBuffs) do
                if MissingRaidBuffs:PlayerIsProviderSpec(buff)
                    and MissingRaidBuffs._spellKnownProbe(buff)
                    and MissingRaidBuffs:AnyEligibleAllyHasMyBuff(buff.ids) == false
                then
                    table_insert(result, {
                        name = buff.label or buff.name,
                        stat = "Ally Buff",
                        spellId = buff.iconSpellID or buff.ids[1],
                        providerClass = buff.providerClass,
                        isAllyBuff = true,
                    })
                end
            end
        end
    end

    if settings.showSelfBuffs ~= false then
        local playerSpecID
        local CSI = C_SpecializationInfo
        local specIdx = CSI and CSI.GetSpecialization and CSI.GetSpecialization()
        if specIdx and CSI.GetSpecializationInfo then
            playerSpecID = CSI.GetSpecializationInfo(specIdx)
        end
        for _, selfBuff in ipairs(SELF_BUFFS) do
            if selfBuff.providerClass == playerClass
                and (not selfBuff.providerSpecIDs or (playerSpecID and selfBuff.providerSpecIDs[playerSpecID])) then
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
QUI_RaidBuffs._getRelevantBuffs = GetRelevantBuffs

local function CreateBuffIcon(parent, index)
    local button = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    button:SetSize(ICON_SIZE, ICON_SIZE)

    local px = (QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(button)) or 1
    local bgr, bgg, bgb = 0, 0, 0
    if Helpers and Helpers.GetSkinBgColor then bgr, bgg, bgb = Helpers.GetSkinBgColor() end
    ns.SkinBase.ApplyPixelBackdrop(button, 1, true, true, nil, { bgr, bgg, bgb, 0.8 }, nil, nil, 1)

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", px, -px)
    button.icon:SetPoint("BOTTOMRIGHT", -px, px)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button.countText = button:CreateFontString(nil, "OVERLAY")
    CJKFont(button.countText, Helpers.GetGeneralFont(), 10, Helpers.GetGeneralFontOutline())
    button.countText:SetPoint("BOTTOM", button, "BOTTOM", 0, 2)
    button.countText:SetTextColor(1, 1, 1, 1)
    button.countText:Hide()

    button.clickButton = CreateFrame("Button", nil, button, "SecureActionButtonTemplate")
    button.clickButton:SetAllPoints()
    button.clickButton:RegisterForClicks("AnyUp", "AnyDown")
    button.isCastable = false

    button.clickButton:SetScript("OnEnter", function(self)
        local icon = self:GetParent()
        if icon.buffData then
            GameTooltip:SetOwner(icon, "ANCHOR_RIGHT")
            GameTooltip:AddLine(icon.buffData.name, 1, 1, 1)
            GameTooltip:AddLine(icon.buffData.stat, 0.7, 0.7, 0.7)
            GameTooltip:AddLine(" ")
            if icon.buffData.selfBuff then
                GameTooltip:AddLine(ns.L["Self-buff"], 0.5, 0.8, 1)
            else
                local className = LOCALIZED_CLASS_NAMES_MALE[icon.buffData.providerClass] or icon.buffData.providerClass
                GameTooltip:AddLine(ns.L["Provided by: "] .. className, 0.5, 0.8, 1)
                if icon.buffCount and icon.buffTotal then
                    GameTooltip:AddLine(string_format(ns.L["Buffed: %d/%d"], icon.buffCount, icon.buffTotal), 0.7, 1, 0.7)
                end
            end
            if icon.isCastable then
                GameTooltip:AddLine(ns.L["Click to cast"], 0.2, 1, 0.2)
            end
            GameTooltip:Show()
        end
    end)
    button.clickButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return button
end

local function ApplyIconBorderSettings()
    local settings = GetSettings()
    local borderSettings = settings.iconBorder or { show = true, width = 1, useClassColor = false, color = { 0.376, 0.647, 0.980, 1 } }
    local borderWidth = borderSettings.show and (borderSettings.width or 1) or 0

    local br, bg, bb, ba = 0.376, 0.647, 0.980, 1
    if borderSettings.useClassColor then
        local _, class = UnitClass("player")
        -- @secret-policy: collapse-only — fixed default border color
        if IsSecretValue(class) then class = nil end
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
        local QUI = _G.QUI
        if QUI and QUI.GetSkinColor then
            br, bg, bb, ba = QUI:GetSkinColor()
        end
    end

    local iconBgR, iconBgG, iconBgB = 0, 0, 0
    if Helpers and Helpers.GetSkinBgColor then iconBgR, iconBgG, iconBgB = Helpers.GetSkinBgColor() end

    for _, icon in ipairs(buffIcons) do
        local bpx = QUICore:Pixels(borderWidth, icon)
        ns.SkinBase.ApplyPixelBackdrop(icon, borderWidth, true, true, { br, bg, bb, ba }, { iconBgR, iconBgG, iconBgB, 0.8 }, nil, nil, borderWidth)

        icon.icon:ClearAllPoints()
        icon.icon:SetPoint("TOPLEFT", bpx, -bpx)
        icon.icon:SetPoint("BOTTOMRIGHT", -bpx, bpx)
    end
end

local function CreateMainFrame()
    if mainFrame then return mainFrame end

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
        local settings = GetSettings()
        if settings then
            local growDir = settings.growDirection or "RIGHT"

            local desiredAnchor
            if growDir == "LEFT" then
                desiredAnchor = "TOPRIGHT"
            elseif growDir == "RIGHT" then
                desiredAnchor = "TOPLEFT"
            elseif growDir == "UP" then
                desiredAnchor = "BOTTOMLEFT"
            elseif growDir == "DOWN" then
                desiredAnchor = "TOPLEFT"
            else
                desiredAnchor = "CENTER"
            end

            local point, _, relPoint, x, y = self:GetPoint()
            local frameWidth, frameHeight = self:GetSize()

            local newX, newY = x, y

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

            newX = QUICore:PixelRound(newX)
            newY = QUICore:PixelRound(newY)
            self:ClearAllPoints()
            self:SetPoint(desiredAnchor, UIParent, relPoint, newX, newY)
            settings.position = { point = desiredAnchor, relPoint = relPoint, x = newX, y = newY }
        end
    end)

    mainFrame.iconContainer = CreateFrame("Frame", nil, mainFrame)
    mainFrame.iconContainer:SetPoint("TOP", mainFrame, "TOP", 0, 0)
    mainFrame.iconContainer:SetSize(200, ICON_SIZE)

    mainFrame.labelBar = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    mainFrame.labelBar:SetPoint("TOP", mainFrame.iconContainer, "BOTTOM", 0, -2)
    mainFrame.labelBar:SetSize(100, 18)
    local lblBgR, lblBgG, lblBgB = 0.05, 0.05, 0.05
    if Helpers and Helpers.GetSkinBgColor then lblBgR, lblBgG, lblBgB = Helpers.GetSkinBgColor() end
    ns.SkinBase.ApplyPixelBackdrop(mainFrame.labelBar, 1, true, true, nil, { lblBgR, lblBgG, lblBgB, 0.95 }, nil, nil, 1)

    mainFrame.labelBar.text = mainFrame.labelBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mainFrame.labelBar.text:SetPoint("CENTER", 0, 0)
    CJKFont(mainFrame.labelBar.text, Helpers.GetGeneralFont(), 10, Helpers.GetGeneralFontOutline())
    mainFrame.labelBar.text:SetText(ns.L["Raid Buffs"])

    for i = 1, #RAID_BUFFS do
        buffIcons[i] = CreateBuffIcon(mainFrame.iconContainer, i)
        buffIcons[i]:Hide()
    end

    mainFrame:Hide()

    return mainFrame
end

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

    if mainFrame.labelBar then
        mainFrame.labelBar:SetBackdropColor(bgr, bgg, bgb, bga)
        mainFrame.labelBar:SetBackdropBorderColor(sr, sg, sb, sa)
        if mainFrame.labelBar.text then
            local settings = GetSettings()
            local textColor = settings.labelTextColor
            if textColor then
                mainFrame.labelBar.text:SetTextColor(textColor[1], textColor[2], textColor[3], 1)
            else
                mainFrame.labelBar.text:SetTextColor(1, 1, 1, 1)
            end
        end
    end

    ApplyIconBorderSettings()

    mainFrame.quiSkinColor = { sr, sg, sb, sa }
    mainFrame.quiBgColor = { bgr, bgg, bgb, bga }
end

function QUI_RaidBuffs:RefreshColors()
    ApplySkin()
end

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

UpdateDisplay = function()
    local settings = GetSettings()
    local inCombat = InCombatLockdown()
    if not settings.enabled then
        lastLayoutKey = nil
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
        lastLayoutKey = nil
        if inCombat then mainFrame:SetAlpha(0) else mainFrame:Hide() end
        return
    end

    local iconSize = settings.iconSize or ICON_SIZE
    local iconSpacing = settings.iconSpacing or ICON_SPACING
    local growDir = settings.growDirection or "RIGHT"
    local isVertical = (growDir == "UP" or growDir == "DOWN" or growDir == "CENTER_V")
    local totalSize = (#missing * iconSize) + ((#missing - 1) * iconSpacing)
    local position = settings.position
    local layoutChanged = false
    local layoutKey
    if not inCombat then
        local positionKey = position and table.concat({
            position.point or "", position.relPoint or "", position.x or 0, position.y or 0,
        }, ":") or ""
        layoutKey = table.concat({
            #missing, iconSize, iconSpacing, growDir, settings.hideLabelBar and 1 or 0,
            settings.labelFontSize or 12, positionKey,
        }, "|")
        layoutChanged = layoutKey ~= lastLayoutKey
    end

    if #buffIcons < #missing then
        for i = #buffIcons + 1, #missing do
            buffIcons[i] = CreateBuffIcon(mainFrame.iconContainer, i)
            buffIcons[i]:Hide()
        end
        ApplyIconBorderSettings()
    end

    for i, icon in ipairs(buffIcons) do
        if i <= #missing then
            local buff = missing[i]

            if not inCombat and layoutChanged then
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
            end

            if buff.selfBuff then
                icon.icon:SetTexture(GetSelfBuffIcon(buff))
            else
                icon.icon:SetTexture(GetBuffIcon(buff.spellId))
            end
            icon.buffData = buff

            local canCast = buff.selfBuff and buff._resolvedSpellName or (not buff.selfBuff and PlayerCanCastBuff(buff))
            local hasBuff = buff._hasBuff

            if hasBuff then
                icon.icon:SetDesaturated(false)
                icon.icon:SetVertexColor(1, 1, 1, 1)
                if LCG then LCG.AutoCastGlow_Stop(icon) end
            elseif canCast then
                icon.icon:SetDesaturated(true)
                icon.icon:SetVertexColor(1, 1, 1, 1)
                if LCG then LCG.AutoCastGlow_Start(icon, { 0.2, 1, 0.2, 1 }, 8, 0.25) end
            else
                icon.icon:SetDesaturated(true)
                icon.icon:SetVertexColor(0.6, 0.6, 0.6, 1)
                if LCG then LCG.AutoCastGlow_Stop(icon) end
            end

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

            local countSettings = settings.buffCount or { show = false }
            if not buff.selfBuff and countSettings.show and icon.countText then
                local buffed, total = CountBuffedMembers(buff.spellId, buff.name, buff.buffIDs)
                icon.buffCount = buffed
                icon.buffTotal = total
                icon.countText:SetFormattedText("%d/%d", buffed, total)

                local countFontSize = countSettings.fontSize or 10
                local countFontName = countSettings.font or "Quazii"
                local countFontPath = STANDARD_TEXT_FONT
                if LSM then
                    countFontPath = LSM:Fetch("font", countFontName) or STANDARD_TEXT_FONT
                end
                CJKFont(icon.countText, countFontPath, countFontSize, "OUTLINE")

                local countColor = countSettings.color or { 1, 1, 1, 1 }
                icon.countText:SetTextColor(countColor[1] or 1, countColor[2] or 1, countColor[3] or 1, countColor[4] or 1)

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
            if not inCombat and icon.clickButton then
                icon.clickButton:SetAttribute("type", nil)
                icon.clickButton:SetAttribute("spell", nil)
                icon.isCastable = false
            end
        end
    end

    if not inCombat then
        local fontSize = settings.labelFontSize or 12
        local labelBarHeight = fontSize + 8
        local labelBarGap = 2

        CJKFont(mainFrame.labelBar.text, Helpers.GetGeneralFont(), fontSize, Helpers.GetGeneralFontOutline())
        mainFrame.labelBar.text:SetText(ns.L["Raid Buffs"])

        if layoutChanged then
            local hideLabelBar = settings.hideLabelBar
            local minIconsSize = (3 * iconSize) + (2 * iconSpacing)
            local minTextWidth = fontSize * 8 + 10

            mainFrame.iconContainer:ClearAllPoints()
            mainFrame.labelBar:ClearAllPoints()

            if isVertical then
                local containerHeight = totalSize
                local containerWidth = iconSize
                mainFrame.iconContainer:SetSize(containerWidth, containerHeight)

                if hideLabelBar then
                    mainFrame.labelBar:Hide()
                    if growDir == "UP" then
                        mainFrame.iconContainer:SetPoint("BOTTOM", mainFrame, "BOTTOM", 0, 0)
                    elseif growDir == "DOWN" then
                        mainFrame.iconContainer:SetPoint("TOP", mainFrame, "TOP", 0, 0)
                    else
                        mainFrame.iconContainer:SetPoint("CENTER", mainFrame, "CENTER", 0, 0)
                    end
                    mainFrame:SetSize(containerWidth, containerHeight)
                else
                    local frameWidth = math.max(containerWidth, minTextWidth)
                    mainFrame.labelBar:SetSize(frameWidth, labelBarHeight)
                    mainFrame.labelBar:Show()
                    mainFrame.iconContainer:SetPoint("TOP", mainFrame, "TOP", 0, 0)
                    mainFrame.labelBar:SetPoint("TOP", mainFrame.iconContainer, "BOTTOM", 0, -labelBarGap)
                    mainFrame:SetSize(frameWidth, containerHeight + labelBarGap + labelBarHeight)
                end
            else
                local frameWidth = math.max(totalSize, hideLabelBar and 0 or math.max(minIconsSize, minTextWidth))
                mainFrame.iconContainer:SetSize(totalSize, iconSize)

                if hideLabelBar then
                    mainFrame.labelBar:Hide()
                    if growDir == "LEFT" then
                        mainFrame.iconContainer:SetPoint("RIGHT", mainFrame, "RIGHT", 0, 0)
                    elseif growDir == "RIGHT" then
                        mainFrame.iconContainer:SetPoint("LEFT", mainFrame, "LEFT", 0, 0)
                    else
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

            if settings.position and not (_G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("missingRaidBuffs")) then
                mainFrame:ClearAllPoints()
                mainFrame:SetPoint(settings.position.point, UIParent, settings.position.relPoint, settings.position.x, settings.position.y)
            end
        end
        lastLayoutKey = layoutKey
    end

    if inCombat then mainFrame:SetAlpha(1) else mainFrame:Show() end
end

local function ThrottledUpdate()
    local pf = ns.QUI_PerfFlags
    if pf and pf.disabled and pf.disabled.raidbuffs then return end
    local now = GetTime()
    if now - lastUpdate < UPDATE_THROTTLE then return end
    lastUpdate = now
    UpdateDisplay()
end

local eventFrame = CreateFrame("Frame")

local StartRangeCheck, StopRangeCheck
local StartWeaponEnchantPolling

local function OnEvent(self, event, ...)
    local settings = GetSettings()

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
        StartWeaponEnchantPolling()
        C_Timer.After(2, UpdateDisplay)
    elseif event == "GROUP_ROSTER_UPDATE" then
        ThrottledUpdate()
    elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        UpdateDisplay()
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        C_Timer.After(1, UpdateDisplay)
    elseif event == "PLAYER_DEAD" or event == "PLAYER_UNGHOST" then
        ThrottledUpdate()
    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        UpdateDisplay()
    end
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("PLAYER_DEAD")
eventFrame:RegisterEvent("PLAYER_UNGHOST")
eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
eventFrame:SetScript("OnEvent", OnEvent)

local function SetupDebugInstrumentation()
    ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
    ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "RaidBuffs", frame = eventFrame }
end
if ns.DebugRegister then
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation()
end

local trackedSpellIDs = {}
for _, buff in ipairs(RAID_BUFFS) do
    if buff.buffIDs then
        for _, id in ipairs(buff.buffIDs) do trackedSpellIDs[id] = true end
    elseif buff.spellId then
        trackedSpellIDs[buff.spellId] = true
    end
end
for _, selfBuff in ipairs(SELF_BUFFS) do
    if selfBuff.anyBuffIDs then
        for id in pairs(selfBuff.anyBuffIDs) do trackedSpellIDs[id] = true end
    end
end
for _, allyBuff in ipairs(ALLY_BUFFS) do
    for _, id in ipairs(allyBuff.ids) do trackedSpellIDs[id] = true end
end

---@type fun(...): ...
local AuraDeltaIsRelevant
if MissingRaidBuffs and MissingRaidBuffs.MakeDeltaRelevanceTracker then
    AuraDeltaIsRelevant = MissingRaidBuffs.MakeDeltaRelevanceTracker(function()
        return trackedSpellIDs
    end, false)
else
    AuraDeltaIsRelevant = function() return true end
end

if ns.AuraEvents then
    ns.AuraEvents:Subscribe("roster", function(unit, updateInfo)
        local settings = GetSettings()
        if not settings or not settings.enabled then return end
        if not AuraDeltaIsRelevant(unit, updateInfo) then return end
        ThrottledUpdate()
    end)
end

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

local lastMHEnchantID, lastOHEnchantID
local weaponEnchantTicker

local function PlayerNeedsWeaponEnchantPolling()
    local playerClass = GetPlayerClass()
    if not playerClass then return false end
    for _, entry in ipairs(SELF_BUFFS) do
        if entry.providerClass == playerClass and entry.checkType == "weaponEnchant" then
            return true
        end
    end
    return false
end

StartWeaponEnchantPolling = function()
    if weaponEnchantTicker then return end
    if not PlayerNeedsWeaponEnchantPolling() then return end
    local hasMH, _, _, mhID, hasOH, _, _, ohID = GetWeaponEnchantInfo()
    lastMHEnchantID = hasMH and mhID or nil
    lastOHEnchantID = hasOH and ohID or nil
    weaponEnchantTicker = C_Timer.NewTicker(0.5, function()
        local settings = GetSettings()
        if not settings or not settings.enabled then return end
        local hMH, _, _, mID, hOH, _, _, oID = GetWeaponEnchantInfo()
        local curMH = hMH and mID or nil
        local curOH = hOH and oID or nil
        if curMH ~= lastMHEnchantID or curOH ~= lastOHEnchantID then
            lastMHEnchantID = curMH
            lastOHEnchantID = curOH
            ThrottledUpdate()
        end
    end)
end

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

    ScanGroupClasses()
    local classes = {}
    for class, _ in pairs(groupClasses) do
        table_insert(classes, class)
    end
    table_insert(lines, "Group Classes: " .. (#classes > 0 and table.concat(classes, ", ") or "NONE"))

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
            local name = UnitName(unit)
            if IsSecretValue(name) then name = "SECRET" end
            if name == nil then name = "?" end
            local uClass = SafeUnitClass(unit)

            local uirRange, uirChecked = "?", "?"
            local ok1, r1, r2 = pcall(UnitInRange, unit)
            if ok1 then
                if IsSecretValue(r1) then uirRange = "SECRET" else uirRange = tostring(r1) end
                if IsSecretValue(r2) then uirChecked = "SECRET" else uirChecked = tostring(r2) end
            end
            local cidResult = "?"
            local ok2, cid = pcall(CheckInteractDistance, unit, 1)
            if ok2 then
                if IsSecretValue(cid) then cidResult = "SECRET" else cidResult = tostring(cid) end
            end
            local udsResult = "N/A"
            if UnitDistanceSquared then
                local ok3, distSq = pcall(UnitDistanceSquared, unit)
                if ok3 then
                    if IsSecretValue(distSq) then udsResult = "SECRET" else udsResult = tostring(distSq) end
                end
            end
            local rangeInfo = " UnitInRange:" .. uirRange .. "/" .. uirChecked .. " CheckInteract:" .. cidResult .. " DistSq:" .. udsResult

            table_insert(lines, "  " .. unit .. ": " .. name .. " (" .. (uClass or "?") .. ") exists:" .. tostring(exists) .. " connected:" .. tostring(connected) .. " dead:" .. tostring(dead) .. " available:" .. tostring(available))
            table_insert(lines, "    Range APIs:" .. rangeInfo)
        end
    end

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
        if playerHas == nil then
            status = hasProvider and "UNKNOWN" or "No provider"
        elseif hasProvider and not playerHas then
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

        if canProvide and IsInGroup() and not IsInRaid() then
            for i = 1, numMembers - 1 do
                local unit = "party" .. i
                if IsUnitAvailable(unit, buffRange) then
                    local has = UnitHasBuff(unit, buff.spellId, buff.name, buff.buffIDs)
                    local hasText
                    if IsSecretValue(has) then
                        hasText = "SECRET"
                    elseif has == nil then
                        hasText = "UNKNOWN"
                    elseif has then
                        hasText = "HAS"
                    else
                        hasText = "MISSING"
                    end
                    local name = UnitName(unit)
                    if IsSecretValue(name) then name = "SECRET" end
                    if name == nil then name = "?" end
                    table_insert(lines, "    -> " .. unit .. " (" .. name .. "): " .. hasText)
                end
            end
        end
    end

    error(table.concat(lines, "\n"), 0)
end

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

    ns.Registry:Register("raidbuffsSkin", {
        refresh = function()
            if _G.QUI_RefreshRaidBuffs then _G.QUI_RefreshRaidBuffs() end
        end,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end
