--[[
    QUI Tooltip Engine
    Hook-based tooltip system.
    Registers with TooltipProvider as the "default" engine.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local Provider  -- resolved after provider loads
local TooltipInspect

-- Locals for performance
local GameTooltip = GameTooltip
local UIParent = UIParent
local WorldFrame = WorldFrame
local InCombatLockdown = InCombatLockdown

---------------------------------------------------------------------------
-- ENGINE TABLE
---------------------------------------------------------------------------
local TooltipEngine = {}

---------------------------------------------------------------------------
-- Cursor Follow State (engine-local)
---------------------------------------------------------------------------
local cursorFollowActive = Helpers.CreateStateTable()
local cursorFollowHooked = Helpers.CreateStateTable()

-- TAINT SAFETY: For GameTooltip, cursor follow uses a SEPARATE watcher
-- frame instead of HookScript. HookScript on GameTooltip permanently taints
-- its dispatch tables, causing ADDON_ACTION_BLOCKED when the world map's
-- secure context (secureexecuterange) uses GameTooltip for map pins.
local gtCursorWatcher

-- World quest / map tooltips can register a widget container on GameTooltip.
-- Re-anchoring or re-showing the tooltip from addon code while that container
-- is active can re-enter Blizzard's secure widget layout and trigger
-- LayoutFrame secret-value comparison errors.
local function HasActiveWidgetContainer(tooltip)
    if not tooltip or not tooltip.GetChildren then return false end

    local ok, result = pcall(function()
        for i = 1, select("#", tooltip:GetChildren()) do
            local child = select(i, tooltip:GetChildren())
            if child and (child.RegisterForWidgetSet or child.shownWidgetCount ~= nil or child.widgetSetID ~= nil) then
                local widgetSetID = child.widgetSetID
                if widgetSetID ~= nil then
                    return true
                end

                local shownWidgetCount = child.shownWidgetCount
                if shownWidgetCount ~= nil then
                    if Helpers.IsSecretValue(shownWidgetCount) then
                        return true
                    end
                    shownWidgetCount = tonumber(shownWidgetCount)
                    if shownWidgetCount and shownWidgetCount > 0 then
                        return true
                    end
                end

                local numWidgetsShowing = child.numWidgetsShowing
                if numWidgetsShowing ~= nil then
                    if Helpers.IsSecretValue(numWidgetsShowing) then
                        return true
                    end
                    numWidgetsShowing = tonumber(numWidgetsShowing)
                    if numWidgetsShowing and numWidgetsShowing > 0 then
                        return true
                    end
                end

                if child.IsShown and child:IsShown() then
                    return true
                end
            end
        end
        return false
    end)

    return ok and result == true
end

-- Quest/world map reward tooltips can also attach Blizzard MoneyFrame children
-- to GameTooltip. Re-anchoring or forcing a re-show while those are active can
-- taint Blizzard's money width math and explode in MoneyFrame_Update.
local function HasActiveMoneyFrame(tooltip)
    if not tooltip or not tooltip.GetChildren then return false end

    local ok, result = pcall(function()
        for i = 1, select("#", tooltip:GetChildren()) do
            local child = select(i, tooltip:GetChildren())
            if child then
                local childName = child.GetName and child:GetName() or nil
                if child.moneyType ~= nil or child.staticMoney ~= nil or child.lastArgMoney ~= nil or
                    (type(childName) == "string" and childName:find("MoneyFrame")) then
                    if child.IsShown then
                        local okShown, shown = pcall(child.IsShown, child)
                        if not okShown or shown then
                            return true
                        end
                    else
                        return true
                    end
                end
            end
        end
        return false
    end)

    return ok and result == true
end

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
                if HasActiveMoneyFrame(GameTooltip) then
                    cursorFollowActive[GameTooltip] = nil
                    return
                end
                if HasActiveWidgetContainer(GameTooltip) then
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
    if tooltip == GameTooltip and HasActiveMoneyFrame(tooltip) then return false end
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
local DEFAULT_PLAYER_ILVL_BRACKETS = {
    white = 245,
    green = 255,
    blue = 265,
    purple = 275,
    orange = 285,
}

-- Tooltip Unit Info State (target, mount, M+ rating)
local tooltipUnitInfoState = setmetatable({}, {__mode = "k"})

-- Mount Name Cache (GUID → {name, timestamp})
local mountNameCache = {}
local MOUNT_CACHE_TTL = 0.75

local function RefreshTooltipLayout(tooltip)
    if not tooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end

    -- Re-layout of GameTooltip is unsafe while Blizzard widget containers are
    -- active. World quest/map tooltips use this path, and forcing a refresh from
    -- addon code can trip LayoutFrame secret-value comparisons on clear/hide.
    if tooltip == GameTooltip then
        if HasActiveMoneyFrame(tooltip) then
            return
        end
        if HasActiveWidgetContainer(tooltip) then
            return
        end
        if Helpers.HasTaintedWidgetContainer and Helpers.HasTaintedWidgetContainer(tooltip) then
            return
        end
    end

    if type(tooltip.UpdateTooltipSize) == "function" then
        pcall(tooltip.UpdateTooltipSize, tooltip)
    end
    -- Only call Show() on hidden tooltips.  On already-visible tooltips
    -- UpdateTooltipSize handles relayout.  Show() triggers Blizzard's
    -- internal NineSlice restyle which the skinning watcher can only
    -- catch one frame later, causing a visible flicker.
    local alreadyShown = tooltip.IsShown and tooltip:IsShown()
    if not alreadyShown then
        pcall(tooltip.Show, tooltip)
    end
end

local function InvalidatePendingSetUnit()
    pendingSetUnitToken = pendingSetUnitToken + 1
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

local function ResolveTooltipVisibilityContext(tooltip, fallbackContext)
    if not tooltip or not Provider then
        return fallbackContext
    end

    local owner = tooltip.GetOwner and tooltip:GetOwner() or nil
    if owner then
        local context = Provider:GetTooltipContext(owner)
        if context then
            return context
        end
    end

    local unit = ResolveTooltipUnit(tooltip)
    if unit and UnitExists(unit) then
        if owner and not Provider:IsTransientTooltipOwner(owner) then
            return "frames"
        end
        return "npcs"
    end

    return fallbackContext
end

local function ShouldHideOwnedTooltip(tooltip, fallbackContext)
    if not tooltip or not Provider then
        return false
    end

    local owner = tooltip.GetOwner and tooltip:GetOwner() or nil
    if owner and not Provider:IsTransientTooltipOwner(owner) and Provider:IsOwnerFadedOut(owner) then
        return true
    end

    if InCombatLockdown() then
        return false
    end

    local context = ResolveTooltipVisibilityContext(tooltip, fallbackContext)
    if context and not Provider:ShouldShowTooltip(context) then
        return true
    end

    return false
end

local tooltipHideFadeState = {
    active = false,
    duration = 0,
    elapsed = 0,
    startAlpha = 1,
}

local function ResetTooltipHideFade()
    tooltipHideFadeState.active = false
    tooltipHideFadeState.duration = 0
    tooltipHideFadeState.elapsed = 0
    tooltipHideFadeState.startAlpha = 1
    if GameTooltip and GameTooltip.IsShown and GameTooltip:IsShown() then
        pcall(GameTooltip.SetAlpha, GameTooltip, 1)
    end
end

local function StartTooltipHideFade(duration)
    duration = tonumber(duration) or 0
    if not GameTooltip or not (GameTooltip.IsShown and GameTooltip:IsShown()) then
        ResetTooltipHideFade()
        return
    end

    if duration <= 0 then
        ResetTooltipHideFade()
        GameTooltip:Hide()
        return
    end

    local okAlpha, currentAlpha = pcall(GameTooltip.GetAlpha, GameTooltip)
    tooltipHideFadeState.active = true
    tooltipHideFadeState.duration = duration
    tooltipHideFadeState.elapsed = 0
    tooltipHideFadeState.startAlpha = (okAlpha and type(currentAlpha) == "number" and currentAlpha) or 1
end

local function IsChildOfFrame(frame, ancestor)
    if not frame or not ancestor then
        return false
    end

    local depth = 0
    while frame and depth < 12 do
        if frame == ancestor then
            return true
        end
        if frame == UIParent then
            break
        end
        if not frame.GetParent then
            break
        end
        local ok, parent = pcall(frame.GetParent, frame)
        if not ok or not parent then
            break
        end
        frame = parent
        depth = depth + 1
    end

    return false
end

local function IsTooltipOwnerHovered(owner)
    if not owner or not Provider then
        return false
    end

    local focus = Provider.GetTopMouseFrame and Provider:GetTopMouseFrame()
    if focus and IsChildOfFrame(focus, owner) then
        return true
    end

    if owner.IsMouseOver then
        local ok, isOver = pcall(owner.IsMouseOver, owner)
        if ok and isOver then
            return true
        end
    end

    return false
end

local function ShouldKeepTooltipVisible(tooltip)
    if not tooltip or not Provider then
        return false
    end

    local owner = tooltip.GetOwner and tooltip:GetOwner() or nil
    if owner and not Provider:IsTransientTooltipOwner(owner) then
        return IsTooltipOwnerHovered(owner)
    end

    local unit = ResolveTooltipUnit(tooltip)
    if unit and UnitExists(unit) then
        return true
    end

    if UnitExists("mouseover") then
        return true
    end

    if Provider.IsFrameBlockingMouse and Provider:IsFrameBlockingMouse() then
        return true
    end

    -- World object tooltips (mining/herb nodes, summon stones, fishing schools,
    -- ground loot) have a transient owner, no unit, and mouse focus on WorldFrame.
    -- Trust Blizzard's native OnLeave to hide them; otherwise hideDelay=0 hides
    -- them on the first frame and the user never sees the tooltip.
    local focus = Provider.GetTopMouseFrame and Provider:GetTopMouseFrame()
    if focus == WorldFrame then
        return true
    end

    return false
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

---------------------------------------------------------------------------
-- Tooltip Unit Info Helper Functions (Target, Mount, M+ Rating)
---------------------------------------------------------------------------

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
            targetAdded = false,
            targetName = nil,
            mountResolved = false,
            mountName = nil,
            mountAdded = false,
            ratingAdded = false,
        }
        tooltipUnitInfoState[tooltip] = state
    end
    return state
end

local function EnsureTooltipInfoSpacer(tooltip, state)
    if not tooltip or not state then return end
    if state.spacerAdded then return end
    tooltip:AddLine(" ")
    state.spacerAdded = true
end

local function ResolveTooltipTargetInfo(unit)
    if not unit then
        return nil
    end
    local targetUnit = unit .. "target"
    local ok, exists = pcall(UnitExists, targetUnit)
    if not ok or not exists then
        return {
            name = "Unknown",
            valueR = 1,
            valueG = 1,
            valueB = 1,
        }
    end

    local okName, targetName = pcall(UnitName, targetUnit)
    if not okName or not targetName then
        targetName = "Unknown"
    end

    -- Get target's class for color
    local okClass, _, classToken = pcall(UnitClass, targetUnit)
    local valueR, valueG, valueB = 1, 1, 1
    if okClass and classToken then
        valueR, valueG, valueB = GetPlayerClassColor(classToken)
    end

    return {
        name = targetName,
        valueR = valueR,
        valueG = valueG,
        valueB = valueB,
    }
end

local function AddTooltipTargetInfo(tooltip, unit, state)
    if not tooltip or not unit or not state then return false end
    if state.targetAdded then return false end

    local targetInfo = ResolveTooltipTargetInfo(unit)
    if not targetInfo then return false end

    EnsureTooltipInfoSpacer(tooltip, state)
    tooltip:AddDoubleLine("Target:", targetInfo.name, 0.7, 0.82, 1, targetInfo.valueR, targetInfo.valueG, targetInfo.valueB)
    state.targetAdded = true
    return true
end

local function GetMountNameFromSpellID(spellID)
    if not spellID then return nil end
    if Helpers.IsSecretValue(spellID) then return nil end
    if spellID == 0 then return nil end

    if not C_MountJournal or not C_MountJournal.GetMountFromSpell then return nil end

    local ok, mountID = pcall(C_MountJournal.GetMountFromSpell, spellID)
    if not ok or not mountID or mountID == 0 or Helpers.IsSecretValue(mountID) then
        return nil
    end

    if not C_MountJournal.GetMountInfoByID then return nil end

    local okInfo, mountName = pcall(C_MountJournal.GetMountInfoByID, mountID)
    if not okInfo or not mountName then
        return nil
    end

    return mountName
end

local function GetCachedMountName(guid)
    if not guid then return nil end
    local entry = mountNameCache[guid]
    if not entry then return nil end

    local age = GetTime() - (entry.timestamp or 0)
    if age > MOUNT_CACHE_TTL then
        mountNameCache[guid] = nil
        return nil
    end

    return entry.name
end

local function SetCachedMountName(guid, mountName)
    if not guid then return end
    if not mountName then
        mountNameCache[guid] = nil
        return
    end
    mountNameCache[guid] = {
        name = mountName,
        timestamp = GetTime(),
    }
end

local function GetMountedPlayerMountName(unit)
    if not unit or not UnitExists(unit) then return nil end
    if InCombatLockdown() then
        -- During combat, can't iterate auras, skip mount detection
        return nil
    end

    -- Try C_UnitAuras (modern API, WoW 10.0+)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 80 do
            local ok, auraData = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
            if not ok or not auraData then break end

            if auraData.spellId then
                local mountName = GetMountNameFromSpellID(auraData.spellId)
                if mountName then
                    SetCachedMountName(UnitGUID(unit), mountName)
                    return mountName
                end
            end
        end
    else
        -- Fallback to legacy UnitAura API
        for i = 1, 80 do
            local ok, name, _, _, _, _, _, _, _, spellID = pcall(UnitAura, unit, i, "HELPFUL")
            if not ok or not name then break end

            if spellID then
                local mountName = GetMountNameFromSpellID(spellID)
                if mountName then
                    SetCachedMountName(UnitGUID(unit), mountName)
                    return mountName
                end
            end
        end
    end

    -- Check if mounted via taxi/flying mount
    local guid = UnitGUID(unit)
    local cachedName = GetCachedMountName(guid)
    if cachedName then return cachedName end

    return nil
end

local function AddTooltipMountInfo(tooltip, unit, state)
    if not tooltip or not unit or not state then return false end
    if state.mountAdded then return false end

    local mountName = GetMountedPlayerMountName(unit)
    if not mountName then return false end

    EnsureTooltipInfoSpacer(tooltip, state)
    tooltip:AddDoubleLine("Mount:", mountName, 0.65, 1, 0.65, 1, 1, 1)
    state.mountAdded = true
    return true
end

local function GetPlayerMythicRating(unit)
    if not unit then return nil end

    -- Try RaiderIO addon first
    if _G.RaiderIO and _G.RaiderIO.GetProfile then
        local ok, profile = pcall(_G.RaiderIO.GetProfile, unit)
        if ok and profile and profile.mythicKeystoneProfile and profile.mythicKeystoneProfile.currentScore then
            local score = Helpers.SafeToNumber(profile.mythicKeystoneProfile.currentScore, 0)
            if score and score > 0 then
                local color = _G.RaiderIO.GetScoreColor and _G.RaiderIO.GetScoreColor(score)
                if type(color) == "table" and color.r then
                    return math.floor(score), color.r, color.g, color.b
                end
                return math.floor(score), 1, 1, 1
            end
        end
    end

    -- Fall back to native C_PlayerInfo
    if C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
        local ok, ratingInfo = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, unit)
        if ok and ratingInfo and ratingInfo.currentSeasonScore then
            local score = Helpers.SafeToNumber(ratingInfo.currentSeasonScore, 0)
            if score and score > 0 then
                local color = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor and C_ChallengeMode.GetDungeonScoreRarityColor(score)
                if color then
                    return math.floor(score), color.r, color.g, color.b
                end
                return math.floor(score), 1, 0.82, 0
            end
        end
    end

    return nil
end

local function AddUnitTooltipInfoToTooltip(tooltip, unit, settings)
    if not tooltip or not unit or not settings then return end
    if InCombatLockdown() then return end

    local guid = UnitGUID(unit)
    if not guid or Helpers.IsSecretValue(guid) then return end

    local state = EnsureTooltipUnitInfoState(tooltip, guid)
    if not state then return end

    -- Add target info
    if IsSettingEnabled(settings, "showTooltipTarget", true) then
        AddTooltipTargetInfo(tooltip, unit, state)
    end

    -- Add mount info
    if IsSettingEnabled(settings, "showPlayerMount", true) then
        AddTooltipMountInfo(tooltip, unit, state)
    end

    -- Add M+ rating
    if IsSettingEnabled(settings, "showPlayerMythicRating", true) then
        local rating, r, g, b = GetPlayerMythicRating(unit)
        if rating then
            EnsureTooltipInfoSpacer(tooltip, state)
            tooltip:AddDoubleLine("M+ Rating:", string.format("%.1f", rating), 0.7, 0.82, 1, r or 1, g or 1, b or 1)
            state.ratingAdded = true
        end
    end
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

        -- Reposition immediately — ClearAllPoints/SetPoint are C-side and
        -- handle combat safely. Do NOT call SetOwner here; Blizzard already
        -- set it and re-calling mid-build disrupts the tooltip chain.
        if settings.anchorToCursor then
            EnsureCursorFollowHooks(tooltip)
            cursorFollowActive[tooltip] = true
            Provider:PositionTooltipAtCursor(tooltip, settings)
        else
            cursorFollowActive[tooltip] = nil
            Provider:PositionTooltipAtAnchor(tooltip, settings)
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

        if ShouldHideOwnedTooltip(tooltip) then
            tooltip:Hide()
            return
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

    -- Strip server name / player title
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        if tooltip ~= GameTooltip then return end
        local settings = Provider:GetSettings()
        if not settings or not settings.enabled then return end

        local hideServer = settings.hideServerName
        local hideTitle = settings.hidePlayerTitle
        if not hideServer and not hideTitle then return end

        local unit = ResolveTooltipUnit(tooltip)
        if not unit then return end

        local okPlayer, isPlayer = pcall(UnitIsPlayer, unit)
        if not okPlayer or not isPlayer then return end

        -- Strip title from name line (line 1)
        if hideTitle then
            local nameLine = tooltip.GetLeftLine and tooltip:GetLeftLine(1) or GameTooltipTextLeft1
            if nameLine then
                local okText, lineText = pcall(nameLine.GetText, nameLine)
                if okText and lineText and not Helpers.IsSecretValue(lineText) then
                    local okName, bareName = pcall(UnitName, unit)
                    if okName and bareName and not Helpers.IsSecretValue(bareName) and lineText ~= bareName then
                        pcall(nameLine.SetText, nameLine, bareName)
                    end
                end
            end
        end

        -- Hide server/realm line
        if hideServer then
            local _, unitRealm = UnitName(unit)
            if unitRealm and unitRealm ~= "" and not Helpers.IsSecretValue(unitRealm) then
                -- Scan lines 2-5 for the realm name line
                for i = 2, 5 do
                    local line = tooltip.GetLeftLine and tooltip:GetLeftLine(i)
                        or _G["GameTooltipTextLeft" .. i]
                    if line then
                        local okLT, lt = pcall(line.GetText, line)
                        if okLT and lt and not Helpers.IsSecretValue(lt) then
                            if lt == unitRealm then
                                pcall(line.SetText, line, "")
                                pcall(line.Hide, line)
                                break
                            end
                        end
                    end
                end
            end
        end
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

        local okPlayer, isPlayer = pcall(UnitIsPlayer, unit)
        if not okPlayer or not isPlayer then return end

        -- Add target/mount/M+ info (combat-aware)
        AddUnitTooltipInfoToTooltip(tooltip, unit, settings)

        -- Add player item level (out of combat only)
        if not InCombatLockdown() then
            tooltipPlayerItemLevelGUID[tooltip] = nil
            AddPlayerItemLevelToTooltip(tooltip, unit, true)
        end
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
    gtSpellIDWatcher:SetScript("OnUpdate", function(_, elapsed)
        local shown = GameTooltip:IsShown()
        if shown and not gtSpellIDWasShown then
            ResetTooltipHideFade()
        end
        if gtSpellIDWasShown and not shown then
            ResetTooltipHideFade()
            InvalidatePendingSetUnit()
            tooltipSpellIDAdded[GameTooltip] = nil
            tooltipPlayerItemLevelGUID[GameTooltip] = nil
            tooltipUnitInfoState[GameTooltip] = nil
        elseif shown then
            local settings = Provider:GetSettings()
            if not settings or not settings.enabled then
                ResetTooltipHideFade()
            elseif ShouldHideOwnedTooltip(GameTooltip) then
                ResetTooltipHideFade()
                GameTooltip:Hide()
            elseif ShouldKeepTooltipVisible(GameTooltip) then
                if tooltipHideFadeState.active then
                    ResetTooltipHideFade()
                end
            else
                if not tooltipHideFadeState.active then
                    StartTooltipHideFade(settings.hideDelay)
                end
            end

            if tooltipHideFadeState.active then
                tooltipHideFadeState.elapsed = tooltipHideFadeState.elapsed + (elapsed or 0)
                local duration = tooltipHideFadeState.duration
                local progress = (duration > 0) and (tooltipHideFadeState.elapsed / duration) or 1
                if progress >= 1 then
                    ResetTooltipHideFade()
                    GameTooltip:Hide()
                else
                    local nextAlpha = math.max(0, tooltipHideFadeState.startAlpha * (1 - progress))
                    pcall(GameTooltip.SetAlpha, GameTooltip, nextAlpha)
                end
            end
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
        if ShouldHideOwnedTooltip(tooltip, "abilities") then
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
        if ShouldHideOwnedTooltip(tooltip, "items") then
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
            if not unit then return end

            local unitGUID = UnitGUID(unit)
            if not unitGUID or Helpers.IsSecretValue(unitGUID) or Helpers.IsSecretValue(guid) then
                return
            end
            if Helpers.SafeCompare(unitGUID, guid) ~= true then return end

            AddPlayerItemLevelToTooltip(GameTooltip, unit, false)
        end)
    end

end

---------------------------------------------------------------------------
-- Modifier / Combat Event Handlers
---------------------------------------------------------------------------
local function OnUnitTargetChanged(changedUnit)
    if not GameTooltip:IsShown() then return end
    local unit = ResolveTooltipUnit(GameTooltip)
    if not unit or unit ~= changedUnit then return end

    -- Tooltip is showing this unit and their target changed
    local settings = Provider:GetSettings()
    if not settings or not settings.enabled or not IsSettingEnabled(settings, "showTooltipTarget", true) then return end

    local state = tooltipUnitInfoState[GameTooltip]
    if not state then return end

    -- Mark target as needing refresh
    state.targetAdded = false
    RefreshTooltipLayout(GameTooltip)
end

local function OnUnitAuraChanged(changedUnit)
    if not GameTooltip:IsShown() then return end
    local unit = ResolveTooltipUnit(GameTooltip)
    if not unit or unit ~= changedUnit then return end

    -- Tooltip is showing this unit and their auras changed (mount status)
    local settings = Provider:GetSettings()
    if not settings or not settings.enabled or not IsSettingEnabled(settings, "showPlayerMount", true) then return end

    local state = tooltipUnitInfoState[GameTooltip]
    if not state then return end

    -- Mark mount as needing refresh
    state.mountAdded = false
    RefreshTooltipLayout(GameTooltip)
end

local function OnModifierStateChanged()
    if not GameTooltip:IsShown() then return end
    local settings = Provider:GetSettings()
    if not settings or not settings.enabled then return end
    local context = ResolveTooltipVisibilityContext(GameTooltip)
    if context and not Provider:ShouldShowTooltip(context) then
        GameTooltip:Hide()
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

function TooltipEngine:Initialize()
    Provider = ns.TooltipProvider
    TooltipInspect = ns.TooltipInspect

    SetupTooltipHook()

    -- Event handlers (UNIT_AURA handled by centralized dispatcher)
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("UNIT_TARGET")
    eventFrame:SetScript("OnEvent", function(self, event, arg1)
        if event == "MODIFIER_STATE_CHANGED" then
            OnModifierStateChanged()
        elseif event == "PLAYER_REGEN_DISABLED" then
            OnCombatStateChanged(true)
        elseif event == "PLAYER_REGEN_ENABLED" then
            OnCombatStateChanged(false)
        elseif event == "UNIT_TARGET" then
            OnUnitTargetChanged(arg1)
        end
    end)

    -- Subscribe to centralized aura dispatcher (all units — tooltip needs any unit)
    if ns.AuraEvents then
        ns.AuraEvents:Subscribe("all", function(unit, updateInfo)
            OnUnitAuraChanged(unit)
        end)
    end
end

function TooltipEngine:Refresh()
    -- Settings apply on next tooltip show
end

function TooltipEngine:SetEnabled(enabled)
    -- Hooks are permanent once installed
end

---------------------------------------------------------------------------
-- REGISTER WITH PROVIDER
---------------------------------------------------------------------------
ns.TooltipProvider:RegisterEngine("default", TooltipEngine)
