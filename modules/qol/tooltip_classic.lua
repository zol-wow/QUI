--[[
    QUI Tooltip Classic Engine
    Hook-based tooltip system (original implementation).
    Registers with TooltipProvider as the "classic" engine.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local Provider  -- resolved after provider loads
local TooltipInspect

-- Locals for performance
local GameTooltip = GameTooltip
local UIParent = UIParent
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime
local floor = math.floor

---------------------------------------------------------------------------
-- CLASSIC ENGINE TABLE
---------------------------------------------------------------------------
local ClassicEngine = {}

---------------------------------------------------------------------------
-- Cursor Follow State (engine-local)
---------------------------------------------------------------------------
local cursorFollowActive = setmetatable({}, {__mode = "k"})
local cursorFollowHooked = setmetatable({}, {__mode = "k"})

-- TAINT SAFETY: For GameTooltip, cursor follow uses a SEPARATE watcher
-- frame instead of HookScript. HookScript on GameTooltip permanently taints
-- its dispatch tables, causing ADDON_ACTION_BLOCKED when the world map's
-- secure context (secureexecuterange) uses GameTooltip for map pins.
local gtCursorWatcher

local function EnsureCursorFollowHooks(tooltip)
    if not tooltip or cursorFollowHooked[tooltip] then return end
    cursorFollowHooked[tooltip] = true

    if tooltip == GameTooltip then
        -- Use a separate watcher frame for GameTooltip to avoid taint
        if not gtCursorWatcher then
            gtCursorWatcher = CreateFrame("Frame")
            gtCursorWatcher:SetScript("OnUpdate", function()
                if not cursorFollowActive[GameTooltip] then return end
                if not GameTooltip:IsShown() then
                    cursorFollowActive[GameTooltip] = nil
                    return
                end
                local settings = Provider:GetSettings()
                if not settings or not settings.enabled or not settings.anchorToCursor then
                    cursorFollowActive[GameTooltip] = nil
                    return
                end
                Provider:PositionTooltipAtCursor(GameTooltip, settings)
            end)
        end
        return
    end

    -- Non-GameTooltip frames can safely use HookScript
    tooltip:HookScript("OnUpdate", function(self)
        if not cursorFollowActive[self] then return end
        local settings = Provider:GetSettings()
        if not settings or not settings.enabled or not settings.anchorToCursor then
            cursorFollowActive[self] = nil
            return
        end
        -- PositionTooltipAtCursor uses cached UIParent scale (updated on
        -- UI_SCALE_CHANGED) so arithmetic is safe during combat.
        -- GetCursorPosition returns screen coordinates, not combat-restricted data.
        Provider:PositionTooltipAtCursor(self, settings)
    end)

    tooltip:HookScript("OnHide", function(self)
        cursorFollowActive[self] = nil
    end)
end

local function AnchorTooltipToCursor(tooltip, parent, settings)
    if not tooltip then return false end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return false end
    EnsureCursorFollowHooks(tooltip)
    tooltip:SetOwner(parent or UIParent, "ANCHOR_NONE")
    cursorFollowActive[tooltip] = true
    Provider:PositionTooltipAtCursor(tooltip, settings or Provider:GetSettings())
    return true
end

---------------------------------------------------------------------------
-- DEBOUNCE STATE
---------------------------------------------------------------------------
local pendingSetUnitToken = 0
local tooltipPlayerItemLevelGUID = setmetatable({}, {__mode = "k"})
local tooltipUnitInfoState = setmetatable({}, {__mode = "k"})
local mountNameCache = {}
local MOUNT_NAME_CACHE_TTL = 0.75
local DEFAULT_PLAYER_ILVL_BRACKETS = {
    white = 245,
    green = 255,
    blue = 265,
    purple = 275,
    orange = 285,
}

local function RefreshTooltipLayout(tooltip)
    if not tooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if type(tooltip.UpdateTooltipSize) == "function" then
        pcall(tooltip.UpdateTooltipSize, tooltip)
    end
    -- Re-showing GameTooltip can re-enter widget setup (GameTooltip_AddWidgetSet).
    -- If another addon tainted the widget container, that path can hard-error on
    -- secret metric values. Keep our extra lines, but skip only when taint is
    -- detected and let normal widget tooltips continue to refresh as usual.
    if tooltip == GameTooltip then
        if Helpers.HasTaintedWidgetContainer and Helpers.HasTaintedWidgetContainer(tooltip) then
            return
        end
    end
    pcall(tooltip.Show, tooltip)
end

local function InvalidatePendingSetUnit()
    pendingSetUnitToken = pendingSetUnitToken + 1
end

local function ShouldHideOwnedTooltip(tooltip)
    local owner = tooltip and tooltip.GetOwner and tooltip:GetOwner() or nil
    if not owner then
        return false
    end
    if Provider:IsTransientTooltipOwner(owner) then
        return false
    end
    if Provider:IsOwnerFadedOut(owner) then
        return true
    end
    if not InCombatLockdown() then
        local context = Provider:GetTooltipContext(owner)
        if context and not Provider:ShouldShowTooltip(context) then
            return true
        end
    end
    return false
end

local function ResolveTooltipUnit(tooltip)
    if not tooltip then return nil end

    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    if not ok or not unit then return nil end

    if Helpers.IsSecretValue(unit) then
        unit = UnitExists("mouseover") and "mouseover" or nil
    end

    return unit
end

local function AreUnitsEquivalent(unitA, unitB)
    if not unitA or not unitB then return false end
    if Helpers.IsSecretValue(unitA) or Helpers.IsSecretValue(unitB) then return false end

    -- Keep UnitIsUnit evaluation and boolean coercion inside pcall to avoid
    -- leaking secret booleans into unprotected boolean tests.
    local okUnitIsUnit, isSameUnit = pcall(function()
        return UnitIsUnit(unitA, unitB) == true
    end)
    if okUnitIsUnit and isSameUnit then
        return true
    end

    return Helpers.SafeCompare(unitA, unitB) == true
end

local function GetPlayerItemLevelColor(itemLevel)
    if Helpers.IsSecretValue(itemLevel) then
        return 1, 1, 1
    end

    itemLevel = tonumber(itemLevel)
    if not itemLevel then
        return 1, 1, 1
    end

    local settings = Provider and Provider:GetSettings()
    if not settings or settings.colorPlayerItemLevel == false then
        return 1, 1, 1
    end

    local brackets = settings.itemLevelBrackets or DEFAULT_PLAYER_ILVL_BRACKETS
    local white = tonumber(brackets.white) or DEFAULT_PLAYER_ILVL_BRACKETS.white
    local green = tonumber(brackets.green) or DEFAULT_PLAYER_ILVL_BRACKETS.green
    local blue = tonumber(brackets.blue) or DEFAULT_PLAYER_ILVL_BRACKETS.blue
    local purple = tonumber(brackets.purple) or DEFAULT_PLAYER_ILVL_BRACKETS.purple
    local orange = tonumber(brackets.orange) or DEFAULT_PLAYER_ILVL_BRACKETS.orange

    if itemLevel >= orange then
        return 1, 0.5, 0
    elseif itemLevel >= purple then
        return 0.64, 0.21, 0.93
    elseif itemLevel >= blue then
        return 0, 0.44, 0.87
    elseif itemLevel >= green then
        return 0, 1, 0
    elseif itemLevel >= white then
        return 1, 1, 1
    end

    return 0.62, 0.62, 0.62
end

local function GetPlayerClassColor(classToken)
    if not classToken then
        return 1, 1, 1
    end

    local classColor
    if InCombatLockdown() then
        if C_ClassColor and C_ClassColor.GetClassColor then
            local ok, color = pcall(C_ClassColor.GetClassColor, classToken)
            if ok and color then
                classColor = color
            end
        end
    else
        classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    end

    if classColor then
        return classColor.r, classColor.g, classColor.b
    end

    return 1, 1, 1
end

local function GetPlayerItemLevelLabel(playerData)
    if not playerData then
        return "Player"
    end

    if playerData.specName and playerData.specName ~= "" and playerData.className and playerData.className ~= "" then
        return string.format("%s %s", playerData.specName, playerData.className)
    end

    if playerData.className and playerData.className ~= "" then
        return playerData.className
    end

    return "Player"
end

local function IsSettingEnabled(settings, key, defaultValue)
    if not settings then
        return defaultValue == true
    end

    local value = settings[key]
    if value == nil then
        return defaultValue == true
    end

    return value == true
end

local function EnsureTooltipUnitInfoState(tooltip, guid)
    if not tooltip or not guid then
        return nil
    end

    local state = tooltipUnitInfoState[tooltip]
    if not state or state.guid ~= guid then
        state = {
            guid = guid,
            spacerAdded = false,
            targetAdded = false,
            guildRankAdded = false,
            guildLineText = "",
            mountAdded = false,
            mountResolved = false,
            mountName = "",
            mountNameDisplayed = "",
            ratingAdded = false,
        }
        tooltipUnitInfoState[tooltip] = state
    end

    return state
end

local function EnsureTooltipInfoSpacer(tooltip, state)
    if not tooltip or not state or state.spacerAdded then return end
    tooltip:AddLine(" ")
    state.spacerAdded = true
end

local function ResolveTooltipTargetInfo(unit)
    if not unit or Helpers.IsSecretValue(unit) then
        return nil
    end

    local targetUnit = unit .. "target"
    local okExists, targetExists = pcall(UnitExists, targetUnit)
    if not okExists or not targetExists then
        return nil
    end

    local okName, targetName = pcall(UnitName, targetUnit)
    if not okName or not targetName or Helpers.IsSecretValue(targetName) or targetName == "" then
        return nil
    end

    local displayName = targetName
    if type(Ambiguate) == "function" then
        local okAmbiguate, shortName = pcall(Ambiguate, targetName, "none")
        if okAmbiguate and shortName and not Helpers.IsSecretValue(shortName) and shortName ~= "" then
            displayName = shortName
        end
    end

    local valueR, valueG, valueB = 1, 1, 1
    local okPlayer, isPlayer = pcall(UnitIsPlayer, targetUnit)
    if okPlayer and isPlayer then
        local okClass, _, targetClassToken = pcall(UnitClass, targetUnit)
        if okClass and targetClassToken then
            valueR, valueG, valueB = GetPlayerClassColor(targetClassToken)
        end
    end

    return {
        name = displayName,
        valueR = valueR,
        valueG = valueG,
        valueB = valueB,
    }
end

local function AddTooltipTargetInfo(tooltip, unit, state)
    if not tooltip or not unit or not state then return false end

    local targetInfo = ResolveTooltipTargetInfo(unit)
    local rightLine = nil
    if state.targetLineIndex and tooltip.GetRightLine then
        rightLine = tooltip:GetRightLine(state.targetLineIndex)
    end

    if not targetInfo then
        if rightLine and state.targetName ~= "" then
            pcall(rightLine.SetText, rightLine, "")
            state.targetName = ""
            return true
        end
        return false
    end

    if rightLine then
        if state.targetName ~= targetInfo.name then
            pcall(rightLine.SetText, rightLine, targetInfo.name)
            pcall(rightLine.SetTextColor, rightLine, targetInfo.valueR, targetInfo.valueG, targetInfo.valueB)
            state.targetName = targetInfo.name
            return true
        end
        return false
    end

    EnsureTooltipInfoSpacer(tooltip, state)
    tooltip:AddDoubleLine("Target:", targetInfo.name, 0.7, 0.82, 1, targetInfo.valueR, targetInfo.valueG, targetInfo.valueB)
    if tooltip.NumLines then
        local okNumLines, count = pcall(tooltip.NumLines, tooltip)
        state.targetLineIndex = (okNumLines and type(count) == "number") and count or nil
    else
        state.targetLineIndex = nil
    end
    state.targetName = targetInfo.name
    state.targetAdded = true
    return true
end

local function GetMountNameFromSpellID(spellID)
    if not spellID or Helpers.IsSecretValue(spellID) then return nil end
    if not C_MountJournal or not C_MountJournal.GetMountFromSpell then return nil end

    local okMount, mountID = pcall(C_MountJournal.GetMountFromSpell, spellID)
    if not okMount or not mountID or mountID == 0 or Helpers.IsSecretValue(mountID) then
        return nil
    end

    if not C_MountJournal.GetMountInfoByID then
        return nil
    end

    local okInfo, mountName = pcall(C_MountJournal.GetMountInfoByID, mountID)
    if not okInfo or not mountName or Helpers.IsSecretValue(mountName) or mountName == "" then
        return nil
    end

    return mountName
end

local function GetCachedMountName(guid)
    if not guid then
        return nil
    end

    local entry = mountNameCache[guid]
    if not entry then
        return nil
    end

    if (entry.expiresAt or 0) < GetTime() then
        mountNameCache[guid] = nil
        return nil
    end

    if entry.value == false then
        return false
    end

    return entry.value
end

local function SetCachedMountName(guid, mountName)
    if not guid then
        return
    end

    mountNameCache[guid] = {
        value = mountName or false,
        expiresAt = GetTime() + MOUNT_NAME_CACHE_TTL,
    }
end

local function InvalidateCachedMountName(guid)
    if not guid then return end
    mountNameCache[guid] = nil
end

local function GetMountedPlayerMountName(unit)
    if InCombatLockdown() then return nil end
    if not unit or Helpers.IsSecretValue(unit) then return nil end
    if not UnitExists(unit) then return nil end
    local guid = UnitGUID(unit)
    if Helpers.IsSecretValue(guid) then
        guid = nil
    end

    local cachedValue = GetCachedMountName(guid)
    if cachedValue ~= nil then
        return cachedValue or nil
    end

    local function ResolveMountNameFromAuraData(auraData)
        if not auraData then return nil end

        local spellID = auraData.spellId or auraData.spellID
        local mountName = GetMountNameFromSpellID(spellID)
        if mountName then
            return mountName
        end

        return nil
    end

    local mountName = nil
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for index = 1, 80 do
            local okAura, auraData = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, "HELPFUL")
            if not okAura then break end
            if not auraData then break end
            mountName = ResolveMountNameFromAuraData(auraData)
            if mountName then break end
        end
    elseif C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
        for index = 1, 80 do
            local okAura, auraData = pcall(C_UnitAuras.GetBuffDataByIndex, unit, index, "HELPFUL")
            if not okAura then break end
            if not auraData then break end
            mountName = ResolveMountNameFromAuraData(auraData)
            if mountName then break end
        end
    elseif UnitAura then
        for index = 1, 80 do
            local auraName, _, _, _, _, _, _, _, _, spellID = UnitAura(unit, index, "HELPFUL")
            if not auraName then break end

            mountName = GetMountNameFromSpellID(spellID)
            if mountName then
                break
            end
        end
    end

    if not mountName then
        local okTaxi, onTaxi = pcall(UnitOnTaxi, unit)
        if okTaxi and onTaxi then
            mountName = "Taxi"
        end
    end

    SetCachedMountName(guid, mountName)
    return mountName
end

local function AddTooltipMountInfo(tooltip, unit, state)
    if not tooltip or not unit or not state then return false end
    if InCombatLockdown() then return false end

    local mountName = nil
    if state.mountResolved then
        if state.mountName and state.mountName ~= "" then
            mountName = state.mountName
        end
    else
        mountName = GetMountedPlayerMountName(unit)
        state.mountResolved = true
        state.mountName = mountName or ""
    end

    local rightLine = nil
    if state.mountLineIndex and tooltip.GetRightLine then
        rightLine = tooltip:GetRightLine(state.mountLineIndex)
    end

    if rightLine then
        local displayName = mountName or ""
        if state.mountNameDisplayed ~= displayName then
            pcall(rightLine.SetText, rightLine, displayName)
            state.mountNameDisplayed = displayName
            state.mountAdded = displayName ~= ""
            return true
        end
        return false
    end

    if not mountName then
        return false
    end

    EnsureTooltipInfoSpacer(tooltip, state)
    tooltip:AddDoubleLine("Mount:", mountName, 0.65, 1, 0.65, 1, 1, 1)
    if tooltip.NumLines then
        local okNumLines, count = pcall(tooltip.NumLines, tooltip)
        state.mountLineIndex = (okNumLines and type(count) == "number") and count or nil
    else
        state.mountLineIndex = nil
    end
    state.mountNameDisplayed = mountName
    state.mountAdded = true
    return true
end

local function GetPlayerMythicRating(unit)
    if InCombatLockdown() then return nil end
    if not unit then return nil end

    if RaiderIO and RaiderIO.GetProfile then
        local okProfile, profile = pcall(RaiderIO.GetProfile, unit)
        if okProfile and profile and profile.mythicKeystoneProfile and profile.mythicKeystoneProfile.currentScore then
            local score = Helpers.SafeToNumber(profile.mythicKeystoneProfile.currentScore, 0)
            if score > 0 then
                local rating = floor(score)
                local color = {r = 1, g = 1, b = 1}

                if RaiderIO.GetScoreColor then
                    local okColor, r, g, b = pcall(RaiderIO.GetScoreColor, rating)
                    if okColor and r and g and b then
                        color.r, color.g, color.b = r, g, b
                    end
                end

                return rating, color
            end
        end
    end

    if not C_PlayerInfo or not C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
        return nil
    end

    local okSummary, ratingInfo = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, unit)
    if not okSummary or not ratingInfo then
        return nil
    end

    local score = Helpers.SafeToNumber(ratingInfo.currentSeasonScore, 0)
    if score <= 0 then
        return nil
    end

    local rating = floor(score)
    local color = {r = 1, g = 1, b = 1}
    if C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor then
        local okColor, rarityColor = pcall(C_ChallengeMode.GetDungeonScoreRarityColor, rating)
        if okColor and rarityColor then
            color.r = Helpers.SafeToNumber(rarityColor.r, 1)
            color.g = Helpers.SafeToNumber(rarityColor.g, 1)
            color.b = Helpers.SafeToNumber(rarityColor.b, 1)
        end
    end

    return rating, color
end

local function StripColorCodes(text)
    if not text or Helpers.IsSecretValue(text) then
        return nil
    end

    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    return text
end

local function TrimText(text)
    if not text then return nil end
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return text
end

local function EscapePattern(text)
    if not text then return nil end
    return text:gsub("([^%w])", "%%%1")
end

local function StripRealmSuffix(name, realm)
    if not name or not realm or realm == "" then
        return name
    end

    local realmPattern = EscapePattern("-" .. realm)
    if not realmPattern then
        return name
    end

    local stripped = name:gsub(realmPattern .. "$", "")
    if stripped and stripped ~= "" then
        return stripped
    end

    return name
end

local function AddGuildRankToExistingGuildLine(tooltip, unit, state)
    if not tooltip or not unit or not state then return false end

    local okGuildInfo, guildNameRaw, ret2, ret3, ret4 = pcall(GetGuildInfo, unit)
    if not okGuildInfo then return false end

    local guildName = guildNameRaw
    if not guildName or Helpers.IsSecretValue(guildName) or guildName == "" then
        return false
    end

    local unitRealm = nil
    local okUnitName, _, realm = pcall(UnitName, unit)
    if okUnitName and realm and not Helpers.IsSecretValue(realm) and realm ~= "" then
        unitRealm = realm
    end

    local guildRealm = nil
    if type(ret4) == "string" and not Helpers.IsSecretValue(ret4) and ret4 ~= "" then
        guildRealm = ret4
    end

    local function IsRealmString(value)
        if not value then return false end
        if guildRealm and value == guildRealm then return true end
        if unitRealm and value == unitRealm then return true end
        return false
    end

    local guildRank = nil
    local function TryRankCandidate(value)
        if guildRank then return end
        if type(value) ~= "string" then return end
        if Helpers.IsSecretValue(value) or value == "" then return end
        if value == guildName then return end
        if IsRealmString(value) then return end
        guildRank = value
    end

    TryRankCandidate(ret2)
    TryRankCandidate(ret3)
    TryRankCandidate(ret4)
    if not guildRank then return false end

    local displayGuildName = StripRealmSuffix(guildName, guildRealm)
    displayGuildName = StripRealmSuffix(displayGuildName, unitRealm)
    local expectedText = string.format("%s - %s", displayGuildName, guildRank)
    if state.guildLineText == expectedText then
        return false
    end

    local lineCount = 0
    if tooltip.NumLines then
        local okNumLines, count = pcall(tooltip.NumLines, tooltip)
        if okNumLines and type(count) == "number" then
            lineCount = count
        end
    end

    local guildLine = nil
    local possibleGuildLines = {
        guildName,
        displayGuildName,
        guildRealm and (displayGuildName .. "-" .. guildRealm) or nil,
        unitRealm and (displayGuildName .. "-" .. unitRealm) or nil,
    }
    local possibleExtendedGuildLines = {
        expectedText,
        string.format("%s - %s", guildName, guildRank),
        guildRealm and string.format("%s-%s - %s", displayGuildName, guildRealm, guildRank) or nil,
        unitRealm and string.format("%s-%s - %s", displayGuildName, unitRealm, guildRank) or nil,
    }

    local function IsGuildLineMatch(plainText)
        if not plainText then return false end
        for _, candidate in ipairs(possibleGuildLines) do
            if candidate and (plainText == candidate or plainText == string.format("<%s>", candidate)) then
                return true
            end
        end
        for _, candidate in ipairs(possibleExtendedGuildLines) do
            if candidate and (plainText == candidate or plainText == string.format("<%s>", candidate)) then
                return true
            end
        end
        return false
    end

    for i = 2, math.min(lineCount, 8) do
        local line = tooltip.GetLeftLine and tooltip:GetLeftLine(i) or _G["GameTooltipTextLeft" .. i]
        if line then
            local okText, text = pcall(line.GetText, line)
            if okText and text and not Helpers.IsSecretValue(text) then
                local plain = TrimText(StripColorCodes(text))
                if IsGuildLineMatch(plain) then
                    guildLine = line
                    break
                end
            end
        end
    end

    if not guildLine then
        return false
    end

    local okR, r, g, b, a = pcall(guildLine.GetTextColor, guildLine)
    pcall(guildLine.SetText, guildLine, expectedText)
    if okR then
        pcall(guildLine.SetTextColor, guildLine, r, g, b, a)
    end

    state.guildLineText = expectedText
    state.guildRankAdded = true
    return true
end

local function AddUnitTooltipInfoToTooltip(tooltip, unit, settings)
    if not tooltip or not unit then return false end

    local guid = UnitGUID(unit)
    if not guid or Helpers.IsSecretValue(guid) then
        return false
    end

    local state = EnsureTooltipUnitInfoState(tooltip, guid)
    if not state then
        return false
    end

    local added = false
    if IsSettingEnabled(settings, "showTooltipTarget", true) then
        if AddTooltipTargetInfo(tooltip, unit, state) then
            added = true
        end
    end

    local okPlayer, isPlayer = pcall(UnitIsPlayer, unit)
    if not okPlayer or not isPlayer then
        return added
    end

    if AddGuildRankToExistingGuildLine(tooltip, unit, state) then
        added = true
    end

    if InCombatLockdown() then
        return added
    end

    if IsSettingEnabled(settings, "showPlayerMount", true) then
        if AddTooltipMountInfo(tooltip, unit, state) then
            added = true
        end
    end

    if IsSettingEnabled(settings, "showPlayerMythicRating", true) and not state.ratingAdded then
        local rating, color = GetPlayerMythicRating(unit)
        if rating and color then
            EnsureTooltipInfoSpacer(tooltip, state)
            tooltip:AddDoubleLine("M+ Rating:", tostring(rating), 0.8, 0.85, 1, color.r or 1, color.g or 1, color.b or 1)
            state.ratingAdded = true
            added = true
        end
    end

    return added
end

local function AddPlayerItemLevelToTooltip(tooltip, unit, skipShow)
    if not TooltipInspect or not unit or not tooltip then return false end
    if InCombatLockdown() then return false end

    local playerData = TooltipInspect:GetCachedPlayerData(unit)
    if not playerData or not playerData.itemLevel then
        if not InCombatLockdown() then
            TooltipInspect:QueueInspect(unit)
        end
        return false
    end

    local guid = UnitGUID(unit)
    if tooltipPlayerItemLevelGUID[tooltip] == guid then
        return false
    end

    if Helpers.IsSecretValue(playerData.itemLevel) then
        return false
    end

    local itemLevel = tonumber(playerData.itemLevel)
    if not itemLevel or itemLevel <= 0 then
        return false
    end

    local label = GetPlayerItemLevelLabel(playerData)
    local labelR, labelG, labelB = GetPlayerClassColor(playerData.classToken)
    local valueR, valueG, valueB = GetPlayerItemLevelColor(itemLevel)

    tooltip:AddLine(" ")
    tooltip:AddDoubleLine(label, string.format("%.1f", itemLevel), labelR, labelG, labelB, valueR, valueG, valueB)
    tooltipPlayerItemLevelGUID[tooltip] = guid

    if not skipShow then
        RefreshTooltipLayout(tooltip)
    end

    return true
end

local function AddUnitTooltipAugmentations(tooltip, unit, settings, skipShow)
    if not tooltip or not unit or not settings then
        return false
    end

    local added = false
    if AddUnitTooltipInfoToTooltip(tooltip, unit, settings) then
        added = true
    end

    local okPlayer, isPlayer = pcall(UnitIsPlayer, unit)
    if okPlayer and isPlayer and settings.showPlayerItemLevel then
        if AddPlayerItemLevelToTooltip(tooltip, unit, true) then
            added = true
        end
    end

    if added and not skipShow then
        RefreshTooltipLayout(tooltip)
    end

    return added
end

---------------------------------------------------------------------------
-- SETUP HOOKS
---------------------------------------------------------------------------
local function SetupTooltipHook()
    ns.QUI_AnchorTooltipToCursor = AnchorTooltipToCursor

    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
        if tooltip.IsForbidden and tooltip:IsForbidden() then return end
        if parent and parent.IsForbidden and parent:IsForbidden() then return end

        local settings = Provider:GetSettings()
        if not settings or not settings.enabled then return end

        InvalidatePendingSetUnit()

        -- Visibility/context checks call methods on Blizzard frames (GetName,
        -- GetAttribute, GetActionInfo) which can taint the execution context
        -- during combat. Skip them — combat hiding is handled by the SetUnit
        -- hook and OnCombatStateChanged instead.
        if not InCombatLockdown() then
            local context = Provider:GetTooltipContext(parent)
            if context and not Provider:ShouldShowTooltip(context) then
                tooltip:Hide()
                tooltip:SetOwner(UIParent, "ANCHOR_NONE")
                tooltip:ClearLines()
                return
            end
        end

        -- Cursor positioning uses cached UIParent scale and
        -- GetCursorPosition (screen coords, not restricted) — safe in combat.
        if settings.anchorToCursor then
            -- Don't call AnchorTooltipToCursor here — it calls SetOwner()
            -- which re-taints the tooltip from addon context, breaking
            -- widget-set layout (secret value arithmetic on child frames).
            -- Blizzard already called SetOwner(parent, "ANCHOR_NONE") inside
            -- GameTooltip_SetDefaultAnchor before this hook fires.
            EnsureCursorFollowHooks(tooltip)
            cursorFollowActive[tooltip] = true
            Provider:PositionTooltipAtCursor(tooltip, settings)
        else
            cursorFollowActive[tooltip] = nil
        end
    end)

    -- TAINT SAFETY: Use TooltipDataProcessor instead of hooksecurefunc(GameTooltip, "SetUnit")
    -- to avoid tainting GameTooltip's dispatch tables.
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        if tooltip ~= GameTooltip then return end
        if tooltip.IsForbidden and tooltip:IsForbidden() then return end
        local settings = Provider:GetSettings()
        if not settings or not settings.enabled then return end

        if settings.hideInCombat and InCombatLockdown() then
            if not settings.combatKey or settings.combatKey == "NONE" or not Provider:IsModifierActive(settings.combatKey) then
                tooltip:Hide()
                return
            end
        end

        local owner = tooltip:GetOwner()
        local token = pendingSetUnitToken + 1
        pendingSetUnitToken = token
        C_Timer.After(0.1, function()
            if token ~= pendingSetUnitToken then return end
            if tooltip.IsForbidden and tooltip:IsForbidden() then return end
            if not tooltip:IsShown() then return end
            if tooltip:GetOwner() ~= owner then return end
            if owner ~= UIParent then return end
            local unit = ResolveTooltipUnit(tooltip)
            if unit and UnitExists(unit) then return end
            if UnitExists("mouseover") then return end
            if Provider:IsFrameBlockingMouse() then
                tooltip:Hide()
            end
        end)
    end)

    -- Class color player names
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        if tooltip ~= GameTooltip then return end
        local settings = Provider:GetSettings()
        if not settings or not settings.enabled or not settings.classColorName then return end

        local unit = ResolveTooltipUnit(tooltip)
        if not unit then return end

        local okPlayer, isPlayer = pcall(UnitIsPlayer, unit)
        if not okPlayer or not isPlayer then return end
        local okClass, _, class = pcall(UnitClass, unit)
        if not okClass or not class then return end

        local classColor
        if InCombatLockdown() then
            if C_ClassColor and C_ClassColor.GetClassColor then
                local okColor, color = pcall(C_ClassColor.GetClassColor, class)
                if okColor and color then classColor = color end
            end
        else
            classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        end

        if classColor then
            local nameLine = tooltip.GetLeftLine and tooltip:GetLeftLine(1) or GameTooltipTextLeft1
            if nameLine then
                local okText, text = pcall(nameLine.GetText, nameLine)
                if okText and text and not Helpers.IsSecretValue(text) then
                    pcall(nameLine.SetTextColor, nameLine, classColor.r, classColor.g, classColor.b)
                end
            end
        end
    end)

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        if tooltip ~= GameTooltip then return end
        local settings = Provider:GetSettings()
        if not settings or not settings.enabled then return end

        local unit = ResolveTooltipUnit(tooltip)
        if not unit then return end

        tooltipPlayerItemLevelGUID[tooltip] = nil
        tooltipUnitInfoState[tooltip] = nil
        AddUnitTooltipAugmentations(tooltip, unit, settings, true)
    end)

    -- Hide health bar
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        if tooltip ~= GameTooltip then return end
        if InCombatLockdown() then return end
        local settings = Provider:GetSettings()
        if not settings or not settings.enabled then return end

        if settings.hideHealthBar then
            if GameTooltipStatusBar and not (GameTooltipStatusBar.IsForbidden and GameTooltipStatusBar:IsForbidden()) then
                pcall(GameTooltipStatusBar.SetShown, GameTooltipStatusBar, false)
                pcall(GameTooltipStatusBar.SetAlpha, GameTooltipStatusBar, 0)
            end
        end
    end)

    -- Spell ID tracking (per-tooltip dedupe signature)
    local tooltipSpellIDAdded = setmetatable({}, {__mode = "k"})

    -- TAINT SAFETY: Use a separate watcher frame to detect GameTooltip
    -- hide/clear instead of HookScript("OnHide"/"OnTooltipCleared").
    -- HookScript on GameTooltip permanently taints its dispatch tables.
    local gtSpellIDWatcher = CreateFrame("Frame")
    local gtSpellIDWasShown = false
    gtSpellIDWatcher:SetScript("OnUpdate", function()
        local shown = GameTooltip:IsShown()
        if gtSpellIDWasShown and not shown then
            InvalidatePendingSetUnit()
            tooltipSpellIDAdded[GameTooltip] = nil
            tooltipPlayerItemLevelGUID[GameTooltip] = nil
            tooltipUnitInfoState[GameTooltip] = nil
        end
        gtSpellIDWasShown = shown
    end)

    local function ResolveSpellIDFromTooltipData(tooltip, data)
        if data then
            local fromID = data.id
            if type(fromID) == "number" then
                if not (type(issecretvalue) == "function" and issecretvalue(fromID)) then
                    return fromID
                end
            end

            local fromSpellID = data.spellID
            if type(fromSpellID) == "number" then
                if not (type(issecretvalue) == "function" and issecretvalue(fromSpellID)) then
                    return fromSpellID
                end
            end
        end

        if tooltip and tooltip.GetSpell then
            local ok, a, b, c, d = pcall(tooltip.GetSpell, tooltip)
            if ok then
                if type(d) == "number" then return d end
                if type(c) == "number" then return c end
                if type(b) == "number" then return b end
                if type(a) == "number" then return a end
            end
        end

        return nil
    end

    local function BuildSpellIDDedupeKey(data, spellID)
        if not data or type(data.dataInstanceID) ~= "number" then
            return "spell:" .. tostring(spellID)
        end
        return tostring(data.dataInstanceID) .. ":" .. tostring(spellID)
    end

    local function ResolveItemIDFromTooltipData(tooltip, data)
        if data then
            local fromID = data.id
            if type(fromID) == "number" then
                if not (type(issecretvalue) == "function" and issecretvalue(fromID)) then
                    return fromID
                end
            end

            local fromItemID = data.itemID
            if type(fromItemID) == "number" then
                if not (type(issecretvalue) == "function" and issecretvalue(fromItemID)) then
                    return fromItemID
                end
            end
        end

        if tooltip and tooltip.GetItem then
            local ok, _, itemLink = pcall(tooltip.GetItem, tooltip)
            if ok and type(itemLink) == "string" then
                local itemID = tonumber(string.match(itemLink, "item:(%d+)"))
                if itemID then
                    return itemID
                end
            end
        end

        return nil
    end

    local function BuildItemIDDedupeKey(data, itemID)
        if not data or type(data.dataInstanceID) ~= "number" then
            return "item:" .. tostring(itemID)
        end
        return tostring(data.dataInstanceID) .. ":item:" .. tostring(itemID)
    end

    local function AddSpellIDToTooltip(tooltip, spellID, data, skipShow)
        if not spellID then return end
        local settings = Provider:GetSettings()
        if not settings or not settings.enabled or not settings.showSpellIDs then return end
        if type(spellID) ~= "number" then return end
        if type(issecretvalue) == "function" and issecretvalue(spellID) then return end
        local dedupeKey = BuildSpellIDDedupeKey(data, spellID)
        if tooltipSpellIDAdded[tooltip] == dedupeKey then return end
        tooltipSpellIDAdded[tooltip] = dedupeKey

        local iconID = nil
        if C_Spell and C_Spell.GetSpellTexture then
            local iconOk, result = pcall(C_Spell.GetSpellTexture, spellID)
            if iconOk and result and type(result) == "number" then
                iconID = result
            end
        end

        tooltip:AddLine(" ")
        tooltip:AddDoubleLine("Spell ID:", tostring(spellID), 0.5, 0.8, 1, 1, 1, 1)
        if iconID then
            tooltip:AddDoubleLine("Icon ID:", tostring(iconID), 0.5, 0.8, 1, 1, 1, 1)
        end

        if not skipShow then
            RefreshTooltipLayout(tooltip)
        end
    end

    local function AddItemIDToTooltip(tooltip, itemID, data, skipShow)
        if not itemID then return end
        local settings = Provider:GetSettings()
        if not settings or not settings.enabled or not settings.showSpellIDs then return end
        if type(itemID) ~= "number" then return end
        if type(issecretvalue) == "function" and issecretvalue(itemID) then return end
        local dedupeKey = BuildItemIDDedupeKey(data, itemID)
        if tooltipSpellIDAdded[tooltip] == dedupeKey then return end
        tooltipSpellIDAdded[tooltip] = dedupeKey

        tooltip:AddLine(" ")
        tooltip:AddDoubleLine("Item ID:", tostring(itemID), 0.5, 0.8, 1, 1, 1, 1)

        if not skipShow then
            RefreshTooltipLayout(tooltip)
        end
    end

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip, data)
        if InCombatLockdown() then return end
        pcall(function()
            local spellID = ResolveSpellIDFromTooltipData(tooltip, data)
            if spellID then
                AddSpellIDToTooltip(tooltip, spellID, data)
            end
        end)
    end)

    local auraTooltipType = Enum.TooltipDataType.UnitAura or Enum.TooltipDataType.Aura
    if auraTooltipType then
        TooltipDataProcessor.AddTooltipPostCall(auraTooltipType, function(tooltip, data)
            if InCombatLockdown() then return end
            pcall(function()
                local spellID = ResolveSpellIDFromTooltipData(tooltip, data)
                if spellID then
                    AddSpellIDToTooltip(tooltip, spellID, data, false)
                end
            end)
        end)
    end

    -- TAINT SAFETY: Aura spell ID display now uses TooltipDataProcessor
    -- instead of hooksecurefunc(GameTooltip, auraMethod). The Aura
    -- TooltipDataProcessor callback above already handles spell IDs for
    -- aura tooltips. The per-method hooks were redundant and tainted
    -- GameTooltip's dispatch tables.

    -- TAINT SAFETY: Suppress tooltips that bypass GameTooltip_SetDefaultAnchor.
    -- Uses TooltipDataProcessor instead of hooksecurefunc(GameTooltip, "SetSpellByID"/"SetItemByID")
    -- to avoid tainting GameTooltip's dispatch tables.
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip)
        if tooltip ~= GameTooltip then return end
        if tooltip.IsForbidden and tooltip:IsForbidden() then return end
        local settings = Provider:GetSettings()
        if not settings or not settings.enabled then return end
        InvalidatePendingSetUnit()
        if ShouldHideOwnedTooltip(tooltip) then
            tooltip:Hide()
        end
    end)

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if not InCombatLockdown() then
            pcall(function()
                local itemID = ResolveItemIDFromTooltipData(tooltip, data)
                if itemID then
                    AddItemIDToTooltip(tooltip, itemID, data)
                end
            end)
        end

        if tooltip ~= GameTooltip then return end
        if tooltip.IsForbidden and tooltip:IsForbidden() then return end
        local settings = Provider:GetSettings()
        if not settings or not settings.enabled then return end
        InvalidatePendingSetUnit()
        if ShouldHideOwnedTooltip(tooltip) then
            tooltip:Hide()
        end
    end)

    if TooltipInspect and TooltipInspect.RegisterRefreshCallback then
        TooltipInspect:RegisterRefreshCallback(function(guid)
            if not GameTooltip or not GameTooltip:IsShown() then return end
            if InCombatLockdown() then return end

            local settings = Provider:GetSettings()
            if not settings or not settings.enabled or not settings.showPlayerItemLevel then return end

            local unit = ResolveTooltipUnit(GameTooltip)
            if not unit or UnitGUID(unit) ~= guid then return end

            AddUnitTooltipAugmentations(GameTooltip, unit, settings, false)
        end)
    end

end

---------------------------------------------------------------------------
-- Modifier / Combat Event Handlers
---------------------------------------------------------------------------
local function OnModifierStateChanged()
    if not GameTooltip:IsShown() then return end
    local settings = Provider:GetSettings()
    if not settings or not settings.enabled then return end
    local owner = GameTooltip:GetOwner()
    local context = Provider:GetTooltipContext(owner)
    if context and not Provider:ShouldShowTooltip(context) then
        GameTooltip:Hide()
    end
end

local function OnUnitTargetChanged(changedUnit)
    if not changedUnit or not GameTooltip or not GameTooltip:IsShown() then return end

    local settings = Provider:GetSettings()
    if not settings or not settings.enabled then return end
    if not IsSettingEnabled(settings, "showTooltipTarget", true) then return end

    local unit = ResolveTooltipUnit(GameTooltip)
    if not unit then return end

    local isSameUnit = AreUnitsEquivalent(unit, changedUnit)

    if not isSameUnit then return end

    local guid = UnitGUID(unit)
    if not guid or Helpers.IsSecretValue(guid) then return end

    local state = EnsureTooltipUnitInfoState(GameTooltip, guid)
    if not state then return end

    if AddTooltipTargetInfo(GameTooltip, unit, state) then
        RefreshTooltipLayout(GameTooltip)
    end
end

local function OnUnitAuraChanged(changedUnit)
    if not changedUnit or not GameTooltip or not GameTooltip:IsShown() then return end
    if InCombatLockdown() then return end

    local settings = Provider:GetSettings()
    if not settings or not settings.enabled then return end
    if not IsSettingEnabled(settings, "showPlayerMount", true) then return end

    local unit = ResolveTooltipUnit(GameTooltip)
    if not unit then return end

    local isSameUnit = AreUnitsEquivalent(unit, changedUnit)

    if not isSameUnit then return end

    local okPlayer, isPlayer = pcall(UnitIsPlayer, unit)
    if not okPlayer or not isPlayer then return end

    local guid = UnitGUID(unit)
    if not guid or Helpers.IsSecretValue(guid) then return end

    local state = EnsureTooltipUnitInfoState(GameTooltip, guid)
    if not state then return end

    InvalidateCachedMountName(guid)
    state.mountResolved = false
    if AddTooltipMountInfo(GameTooltip, unit, state) then
        RefreshTooltipLayout(GameTooltip)
    end
end

local function OnCombatStateChanged(inCombat)
    local settings = Provider:GetSettings()
    if not settings or not settings.enabled or not settings.hideInCombat then return end
    if inCombat then
        if not settings.combatKey or settings.combatKey == "NONE" or not Provider:IsModifierActive(settings.combatKey) then
            GameTooltip:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- ENGINE CONTRACT
---------------------------------------------------------------------------

function ClassicEngine:Initialize()
    Provider = ns.TooltipProvider
    TooltipInspect = ns.TooltipInspect

    SetupTooltipHook()

    -- Event handlers
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
    eventFrame:RegisterEvent("UNIT_TARGET")
    eventFrame:RegisterEvent("UNIT_AURA")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:SetScript("OnEvent", function(self, event, arg1)
        if event == "MODIFIER_STATE_CHANGED" then
            OnModifierStateChanged()
        elseif event == "UNIT_TARGET" then
            OnUnitTargetChanged(arg1)
        elseif event == "UNIT_AURA" then
            OnUnitAuraChanged(arg1)
        elseif event == "PLAYER_REGEN_DISABLED" then
            OnCombatStateChanged(true)
        elseif event == "PLAYER_REGEN_ENABLED" then
            OnCombatStateChanged(false)
        end
    end)
end

function ClassicEngine:Refresh()
    -- Settings apply on next tooltip show
end

function ClassicEngine:SetEnabled(enabled)
    -- Classic engine hooks are permanent once installed
end

---------------------------------------------------------------------------
-- REGISTER WITH PROVIDER
---------------------------------------------------------------------------
ns.TooltipProvider:RegisterEngine("classic", ClassicEngine)
