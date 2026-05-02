--[[
    QUI HUD Visibility Controllers
    Manages fade-in/fade-out visibility for CDM viewers and unit frames.
    Independent of CDM engine — reads frames from ns.CDMProvider (or
    falls back to well-known Blizzard globals).
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local QUICore = ns.Addon

---------------------------------------------------------------------------
-- FORWARD DECLARATIONS
---------------------------------------------------------------------------
local UpdateCDMVisibility
local UpdateCustomTrackersVisibility
local UpdateUnitframesVisibility
local HookCustomTrackerFrameForMouseover

---------------------------------------------------------------------------
-- HEALTH STATE TRACKER (curve-driven alpha override)
-- UnitHealth / UnitHealthMax / UnitHealthPercent return secret values for
-- the player in 12.0+. Build a step NumberCurve mapping fraction→alpha
-- and pass UnitHealthPercent's secret return straight into frame:SetAlpha
-- — the value never re-enters Lua, so no taint comparisons happen.
--
--   fraction <  1.0 → alpha 1 (damaged: frame visible)
--   fraction == 1.0 → alpha 0 (full HP: frame hidden)
--
-- Drives unit frame visibility directly when the bool-rule path
-- (ShouldUnitframesBeVisible) returns false and the user has
-- "Show when health below 100%" enabled.
---------------------------------------------------------------------------
local _damagedAlphaCurve

local function GetDamagedAlphaCurve()
    if _damagedAlphaCurve then return _damagedAlphaCurve end
    if not C_CurveUtil or not C_CurveUtil.CreateCurve
       or not Enum or not Enum.LuaCurveType then
        return nil
    end
    local curve = C_CurveUtil.CreateCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    curve:AddPoint(0.0, 1)  -- below full health
    curve:AddPoint(1.0, 0)  -- exactly full health
    _damagedAlphaCurve = curve
    return curve
end

---------------------------------------------------------------------------
-- SHARED HELPERS
---------------------------------------------------------------------------

-- Check if player is in a group (party or raid)
local function IsPlayerInGroup()
    return IsInGroup() or IsInRaid()
end

-- Housing instance types - excluded from "Show in Instance" detection
local HOUSING_INSTANCE_TYPES = {
    ["neighborhood"] = true,  -- Founder's Point, Razorwind Shores
    ["interior"] = true,      -- Inside player houses
}

-- Check if player is in an instance (dungeon, raid, arena, pvp, scenario)
-- Excludes housing zones which are technically instances but shouldn't trigger "Show In Instance"
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
-- CDM FRAME CACHE
---------------------------------------------------------------------------
local _cdmFramesCache = {}
local _cdmFramesDirty = true

-- Invalidate cache so next GetCDMFrames() rebuilds
local function InvalidateCDMFrameCache()
    _cdmFramesDirty = true
end

-- Get CDM frames (viewers + power bars) — cached to avoid per-frame allocations
local function IsCustomCDMBarFrame(frame)
    if not frame then return false end
    local key = frame._quiCdmKey
    if not key and frame._spellEntry then
        key = frame._spellEntry.viewerType
    end
    if type(key) ~= "string" then return false end

    local profile = QUICore and QUICore.db and QUICore.db.profile
    local container = profile
        and profile.ncdm
        and profile.ncdm.containers
        and profile.ncdm.containers[key]
    return type(container) == "table" and container.containerType == "customBar"
end

local function GetCDMFrames()
    if not _cdmFramesDirty then
        return _cdmFramesCache
    end

    wipe(_cdmFramesCache)

    -- Use provider when available, fall back to well-known Blizzard globals
    if ns.CDMProvider and ns.CDMProvider.GetViewerFrames then
        local frames = ns.CDMProvider:GetViewerFrames()
        if frames then
            for i = 1, #frames do
                if not IsCustomCDMBarFrame(frames[i]) then
                    _cdmFramesCache[#_cdmFramesCache + 1] = frames[i]
                end
            end
        end
    else
        local frameNames = ns.CDMProvider and ns.CDMProvider.GetViewerFrameNames and ns.CDMProvider:GetViewerFrameNames()
        frameNames = frameNames or {
            essential = "EssentialCooldownViewer",
            utility   = "UtilityCooldownViewer",
            buffIcon  = "BuffIconCooldownViewer",
            buffBar   = "BuffBarCooldownViewer",
        }
        for _, blizzName in pairs(frameNames) do
            if _G[blizzName] then
                _cdmFramesCache[#_cdmFramesCache + 1] = _G[blizzName]
            end
        end
    end

    _cdmFramesDirty = false
    return _cdmFramesCache
end

local function GetCustomTrackerFrames()
    local frames = {}
    if ns.CDMProvider and ns.CDMProvider.GetViewerFrames then
        local allFrames = ns.CDMProvider:GetViewerFrames()
        if allFrames then
            for i = 1, #allFrames do
                local frame = allFrames[i]
                if IsCustomCDMBarFrame(frame) then
                    frames[#frames + 1] = frame
                end
            end
        end
    end
    return frames
end

---------------------------------------------------------------------------
-- CDM VISIBILITY SETTINGS CACHE
---------------------------------------------------------------------------
local function GetCDMVisibilitySettings()
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.cdmVisibility then
        return QUICore.db.profile.cdmVisibility
    end
    return nil
end

local function IsCDMMasterEnabled()
    local profile = QUICore and QUICore.db and QUICore.db.profile
    local ncdm = profile and profile.ncdm
    return not ncdm or ncdm.enabled ~= false
end

---------------------------------------------------------------------------
-- CDM VISIBILITY CONTROLLER
---------------------------------------------------------------------------
local CDMVisibility = {
    currentlyHidden = false,
    isFading = false,
    fadeStart = 0,
    fadeStartAlpha = 1,
    fadeTargetAlpha = 1,
    fadeTargets = nil,
    fadeFrame = nil,
    mouseOver = false,
    mouseoverDetector = nil,
    hoverCount = 0,
    leaveTimer = nil,
}

-- Determine if CDM should be visible (SHOW logic)
local function ShouldCDMBeVisible()
    if not IsCDMMasterEnabled() then return false end

    local vis = GetCDMVisibilitySettings()
    if not vis then return true end

    if vis.showAlways then
        local ignoreHideRules = vis.dontHideInDungeonsRaids and Helpers.IsPlayerInDungeonOrRaid and Helpers.IsPlayerInDungeonOrRaid()
        if not ignoreHideRules then
            if vis.hideWhenMounted and not vis.showWhenMounted and Helpers.IsPlayerMounted() then return false end
            if vis.hideWhenFlying and Helpers.IsPlayerFlying() then return false end
            if vis.hideWhenSkyriding and Helpers.IsPlayerSkyriding() then return false end
            if vis.hideWhenInVehicle and Helpers.IsPlayerInVehicle and Helpers.IsPlayerInVehicle() then return false end
        end
        return true
    end

    -- Active show conditions override hide rules
    if vis.showWhenTargetExists and UnitExists("target") then return true end
    if vis.showInCombat and UnitAffectingCombat("player") then return true end
    if vis.showInGroup and IsPlayerInGroup() then return true end
    if vis.showInInstance and IsPlayerInInstance() then return true end
    if vis.showOnMouseover and CDMVisibility.mouseOver then return true end
    if vis.showWhenMounted and Helpers.IsPlayerMounted() then return true end

    -- No active show condition — apply hide rules
    local ignoreHideRules = vis.dontHideInDungeonsRaids and Helpers.IsPlayerInDungeonOrRaid and Helpers.IsPlayerInDungeonOrRaid()
    if not ignoreHideRules then
        if vis.hideWhenMounted and not vis.showWhenMounted and Helpers.IsPlayerMounted() then return false end
        if vis.hideWhenFlying and Helpers.IsPlayerFlying() then return false end
        if vis.hideWhenSkyriding and Helpers.IsPlayerSkyriding() then return false end
        if vis.hideWhenInVehicle and Helpers.IsPlayerInVehicle and Helpers.IsPlayerInVehicle() then return false end
    end

    return false
end

-- OnUpdate handler for CDM fade animation
local function OnCDMFadeUpdate(self, elapsed)
    local targetAlpha = Helpers.SafeToNumber(CDMVisibility.fadeTargetAlpha, 1)
    local vis = GetCDMVisibilitySettings()
    local duration = (vis and vis.fadeDuration) or 0.2
    if duration <= 0 then duration = 0.01 end

    local now = GetTime()
    local elapsedTime = now - CDMVisibility.fadeStart
    local progress = math.min(elapsedTime / duration, 1)

    local startAlpha = Helpers.SafeToNumber(CDMVisibility.fadeStartAlpha, targetAlpha)
    local alpha = startAlpha + (targetAlpha - startAlpha) * progress

    local frames = CDMVisibility.fadeTargets or GetCDMFrames()
    for i = #frames, 1, -1 do
        local frame = frames[i]
        local ok = false
        if frame and frame.SetAlpha and (not frame.IsForbidden or not frame:IsForbidden()) then
            ok = pcall(frame.SetAlpha, frame, alpha)
        end
        if not ok then
            table.remove(frames, i)
        end
    end

    if progress >= 1 then
        CDMVisibility.isFading = false
        CDMVisibility.currentlyHidden = (targetAlpha < 1)
        CDMVisibility.fadeTargets = nil
        self:SetScript("OnUpdate", nil)
    end
end

-- Start CDM fade animation
local function StartCDMFade(targetAlpha)
    local frames = GetCDMFrames()
    if #frames == 0 then return end

    local rawAlpha = frames[1]:GetAlpha()
    if Helpers.IsSecretValue(rawAlpha) then
        for _, frame in ipairs(frames) do
            if frame and frame.SetAlpha and (not frame.IsForbidden or not frame:IsForbidden()) then
                pcall(frame.SetAlpha, frame, targetAlpha)
            end
        end
        if CDMVisibility.fadeFrame then
            CDMVisibility.fadeFrame:SetScript("OnUpdate", nil)
        end
        CDMVisibility.isFading = false
        CDMVisibility.currentlyHidden = (targetAlpha < 1)
        CDMVisibility.fadeStartAlpha = targetAlpha
        CDMVisibility.fadeTargetAlpha = targetAlpha
        CDMVisibility.fadeTargets = nil
        return
    end

    local currentAlpha = Helpers.SafeToNumber(rawAlpha, targetAlpha)

    if math.abs(currentAlpha - targetAlpha) < 0.01 then
        CDMVisibility.currentlyHidden = (targetAlpha < 1)
        CDMVisibility.fadeStartAlpha = targetAlpha
        CDMVisibility.fadeTargetAlpha = targetAlpha
        return
    end

    CDMVisibility.isFading = true
    CDMVisibility.fadeStart = GetTime()
    CDMVisibility.fadeStartAlpha = currentAlpha
    CDMVisibility.fadeTargetAlpha = targetAlpha
    CDMVisibility.fadeTargets = {}
    for i = 1, #frames do
        CDMVisibility.fadeTargets[i] = frames[i]
    end

    if not CDMVisibility.fadeFrame then
        CDMVisibility.fadeFrame = CreateFrame("Frame")
    end
    CDMVisibility.fadeFrame:SetScript("OnUpdate", OnCDMFadeUpdate)
end

-- Update CDM visibility
UpdateCDMVisibility = function()
    if not IsCDMMasterEnabled() then
        StartCDMFade(0)
        return
    end

    if Helpers.IsEditModeActive() or Helpers.IsLayoutModeActive() then
        StartCDMFade(1)
        return
    end

    local shouldShow = ShouldCDMBeVisible()
    local vis = GetCDMVisibilitySettings()

    if shouldShow then
        StartCDMFade(1)
    else
        StartCDMFade(vis and vis.fadeOutAlpha or 0)
    end

    -- Refresh resource bars so CDM visibility changes apply immediately
    if QUICore then
        if QUICore.UpdatePowerBar then
            QUICore:UpdatePowerBar()
        end
        if QUICore.UpdateSecondaryPowerBar then
            QUICore:UpdateSecondaryPowerBar()
        end
    end
end

---------------------------------------------------------------------------
-- CDM MOUSEOVER DETECTION
---------------------------------------------------------------------------
local _mouseoverHooked = Helpers.CreateStateTable()

local function IsAddonOwnedCDMMouseoverFrame(frame)
    return frame
        and (frame._isQUICDMIcon or frame._quiCdmKey or frame._quiCDMMouseoverTarget)
end

-- Hook a single frame for mouseover detection
-- Exported on ns so CDM engines can call it when skinning new icons
local function HookFrameForMouseover(frame)
    if not IsAddonOwnedCDMMouseoverFrame(frame) or _mouseoverHooked[frame] then return end
    if IsCustomCDMBarFrame(frame) then
        if HookCustomTrackerFrameForMouseover then
            HookCustomTrackerFrameForMouseover(frame)
        end
        return
    end

    _mouseoverHooked[frame] = true

    frame:HookScript("OnEnter", function()
        local vis = GetCDMVisibilitySettings()
        if not vis or vis.showAlways or not vis.showOnMouseover then return end

        if CDMVisibility.leaveTimer then
            CDMVisibility.leaveTimer:Cancel()
            CDMVisibility.leaveTimer = nil
        end

        CDMVisibility.hoverCount = CDMVisibility.hoverCount + 1
        if CDMVisibility.hoverCount == 1 then
            CDMVisibility.mouseOver = true
            UpdateCDMVisibility()
        end
    end)

    frame:HookScript("OnLeave", function()
        local vis = GetCDMVisibilitySettings()
        if not vis or vis.showAlways or not vis.showOnMouseover then return end

        CDMVisibility.hoverCount = math.max(0, CDMVisibility.hoverCount - 1)

        if CDMVisibility.hoverCount == 0 then
            if CDMVisibility.leaveTimer then
                CDMVisibility.leaveTimer:Cancel()
            end

            CDMVisibility.leaveTimer = C_Timer.NewTimer(0.5, function()
                CDMVisibility.leaveTimer = nil
                if CDMVisibility.hoverCount == 0 then
                    CDMVisibility.mouseOver = false
                    UpdateCDMVisibility()
                end
            end)
        end
    end)
end

-- Setup CDM mouseover detector
local function SetupCDMMouseoverDetector()
    local vis = GetCDMVisibilitySettings()

    -- Remove existing detector
    if CDMVisibility.mouseoverDetector then
        CDMVisibility.mouseoverDetector:SetScript("OnUpdate", nil)
        CDMVisibility.mouseoverDetector:Hide()
        CDMVisibility.mouseoverDetector = nil
    end

    if CDMVisibility.leaveTimer then
        CDMVisibility.leaveTimer:Cancel()
        CDMVisibility.leaveTimer = nil
    end

    CDMVisibility.mouseOver = false
    CDMVisibility.hoverCount = 0

    if not vis or vis.showAlways or not vis.showOnMouseover then
        return
    end

    -- Hook addon-owned container frames
    local cdmFrames = GetCDMFrames()
    for _, frame in ipairs(cdmFrames) do
        HookFrameForMouseover(frame)
    end

    -- Hook existing addon-owned icons from each viewer. Do not HookScript
    -- arbitrary Blizzard viewer children; CDM icon creation calls the same
    -- API for late-created addon-owned icons.
    local viewers
    if ns.CDMProvider and ns.CDMProvider.GetViewerFrames then
        viewers = ns.CDMProvider:GetViewerFrames()
    else
        viewers = {}
        local names = ns.CDMProvider and ns.CDMProvider.GetViewerFrameNames and ns.CDMProvider:GetViewerFrameNames()
        names = names or {
            essential = "EssentialCooldownViewer",
            utility   = "UtilityCooldownViewer",
            buffIcon  = "BuffIconCooldownViewer",
            buffBar   = "BuffBarCooldownViewer",
        }
        for _, name in pairs(names) do
            if _G[name] then
                viewers[#viewers + 1] = _G[name]
            end
        end
    end

    for _, viewer in ipairs(viewers) do
        if viewer and viewer.GetNumChildren then
            local numChildren = viewer:GetNumChildren()
            for i = 1, numChildren do
                local child = select(i, viewer:GetChildren())
                if child and IsAddonOwnedCDMMouseoverFrame(child) then
                    HookFrameForMouseover(child)
                end
            end
        end
    end

    -- Create minimal detector frame (just for cleanup tracking, no OnUpdate)
    local detector = CreateFrame("Frame", nil, UIParent)
    detector:EnableMouse(false)
    CDMVisibility.mouseoverDetector = detector
end

---------------------------------------------------------------------------
-- CUSTOM TRACKER / CUSTOM CDM BAR VISIBILITY CONTROLLER
---------------------------------------------------------------------------
local CustomTrackersVisibility = {
    currentlyHidden = false,
    isFading = false,
    fadeStart = 0,
    fadeStartAlpha = 1,
    fadeTargetAlpha = 1,
    fadeTargets = nil,
    fadeFrame = nil,
    mouseOver = false,
    mouseoverDetector = nil,
    hoverCount = 0,
    leaveTimer = nil,
}

local function GetCustomTrackersVisibilitySettings()
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.customTrackersVisibility then
        return QUICore.db.profile.customTrackersVisibility
    end
    return nil
end

local function ShouldCustomTrackersBeVisible()
    if not IsCDMMasterEnabled() then return false end

    local vis = GetCustomTrackersVisibilitySettings()
    if not vis then return true end

    if vis.showAlways then
        local ignoreHideRules = vis.dontHideInDungeonsRaids and Helpers.IsPlayerInDungeonOrRaid and Helpers.IsPlayerInDungeonOrRaid()
        if not ignoreHideRules then
            if vis.hideWhenMounted and not vis.showWhenMounted and Helpers.IsPlayerMounted() then return false end
            if vis.hideWhenFlying and Helpers.IsPlayerFlying() then return false end
            if vis.hideWhenSkyriding and Helpers.IsPlayerSkyriding() then return false end
            if vis.hideWhenInVehicle and Helpers.IsPlayerInVehicle and Helpers.IsPlayerInVehicle() then return false end
        end
        return true
    end

    if vis.showWhenTargetExists and UnitExists("target") then return true end
    if vis.showInCombat and UnitAffectingCombat("player") then return true end
    if vis.showInGroup and IsPlayerInGroup() then return true end
    if vis.showInInstance and IsPlayerInInstance() then return true end
    if vis.showOnMouseover and CustomTrackersVisibility.mouseOver then return true end
    if vis.showWhenMounted and Helpers.IsPlayerMounted() then return true end

    local ignoreHideRules = vis.dontHideInDungeonsRaids and Helpers.IsPlayerInDungeonOrRaid and Helpers.IsPlayerInDungeonOrRaid()
    if not ignoreHideRules then
        if vis.hideWhenMounted and not vis.showWhenMounted and Helpers.IsPlayerMounted() then return false end
        if vis.hideWhenFlying and Helpers.IsPlayerFlying() then return false end
        if vis.hideWhenSkyriding and Helpers.IsPlayerSkyriding() then return false end
        if vis.hideWhenInVehicle and Helpers.IsPlayerInVehicle and Helpers.IsPlayerInVehicle() then return false end
    end

    return false
end

local function OnCustomTrackersFadeUpdate(self, elapsed)
    local targetAlpha = Helpers.SafeToNumber(CustomTrackersVisibility.fadeTargetAlpha, 1)
    local vis = GetCustomTrackersVisibilitySettings()
    local duration = (vis and vis.fadeDuration) or 0.2
    if duration <= 0 then duration = 0.01 end

    local now = GetTime()
    local elapsedTime = now - CustomTrackersVisibility.fadeStart
    local progress = math.min(elapsedTime / duration, 1)
    local startAlpha = Helpers.SafeToNumber(CustomTrackersVisibility.fadeStartAlpha, targetAlpha)
    local alpha = startAlpha + (targetAlpha - startAlpha) * progress

    local frames = CustomTrackersVisibility.fadeTargets or GetCustomTrackerFrames()
    for i = #frames, 1, -1 do
        local frame = frames[i]
        local ok = false
        if frame and frame.SetAlpha and (not frame.IsForbidden or not frame:IsForbidden()) then
            ok = pcall(frame.SetAlpha, frame, alpha)
        end
        if not ok then
            table.remove(frames, i)
        end
    end

    if progress >= 1 then
        CustomTrackersVisibility.isFading = false
        CustomTrackersVisibility.currentlyHidden = (targetAlpha < 1)
        CustomTrackersVisibility.fadeTargets = nil
        self:SetScript("OnUpdate", nil)
    end
end

local function StartCustomTrackersFade(targetAlpha)
    local frames = GetCustomTrackerFrames()
    if #frames == 0 then return end

    local rawAlpha = frames[1]:GetAlpha()
    if Helpers.IsSecretValue(rawAlpha) then
        for _, frame in ipairs(frames) do
            if frame and frame.SetAlpha and (not frame.IsForbidden or not frame:IsForbidden()) then
                pcall(frame.SetAlpha, frame, targetAlpha)
            end
        end
        if CustomTrackersVisibility.fadeFrame then
            CustomTrackersVisibility.fadeFrame:SetScript("OnUpdate", nil)
        end
        CustomTrackersVisibility.isFading = false
        CustomTrackersVisibility.currentlyHidden = (targetAlpha < 1)
        CustomTrackersVisibility.fadeStartAlpha = targetAlpha
        CustomTrackersVisibility.fadeTargetAlpha = targetAlpha
        CustomTrackersVisibility.fadeTargets = nil
        return
    end

    local currentAlpha = Helpers.SafeToNumber(rawAlpha, targetAlpha)
    if math.abs(currentAlpha - targetAlpha) < 0.01 then
        CustomTrackersVisibility.currentlyHidden = (targetAlpha < 1)
        CustomTrackersVisibility.fadeStartAlpha = targetAlpha
        CustomTrackersVisibility.fadeTargetAlpha = targetAlpha
        return
    end

    CustomTrackersVisibility.isFading = true
    CustomTrackersVisibility.fadeStart = GetTime()
    CustomTrackersVisibility.fadeStartAlpha = currentAlpha
    CustomTrackersVisibility.fadeTargetAlpha = targetAlpha
    CustomTrackersVisibility.fadeTargets = {}
    for i = 1, #frames do
        CustomTrackersVisibility.fadeTargets[i] = frames[i]
    end

    if not CustomTrackersVisibility.fadeFrame then
        CustomTrackersVisibility.fadeFrame = CreateFrame("Frame")
    end
    CustomTrackersVisibility.fadeFrame:SetScript("OnUpdate", OnCustomTrackersFadeUpdate)
end

UpdateCustomTrackersVisibility = function()
    if not IsCDMMasterEnabled() then
        StartCustomTrackersFade(0)
        return
    end

    if Helpers.IsEditModeActive() or Helpers.IsLayoutModeActive() then
        StartCustomTrackersFade(1)
        return
    end

    local shouldShow = ShouldCustomTrackersBeVisible()
    local vis = GetCustomTrackersVisibilitySettings()
    if shouldShow then
        StartCustomTrackersFade(1)
    else
        StartCustomTrackersFade(vis and vis.fadeOutAlpha or 0)
    end
end

HookCustomTrackerFrameForMouseover = function(frame)
    if not IsAddonOwnedCDMMouseoverFrame(frame) or _mouseoverHooked[frame] then return end
    if not IsCustomCDMBarFrame(frame) then return end

    _mouseoverHooked[frame] = true

    frame:HookScript("OnEnter", function()
        local vis = GetCustomTrackersVisibilitySettings()
        if not vis or vis.showAlways or not vis.showOnMouseover then return end

        if CustomTrackersVisibility.leaveTimer then
            CustomTrackersVisibility.leaveTimer:Cancel()
            CustomTrackersVisibility.leaveTimer = nil
        end

        CustomTrackersVisibility.hoverCount = CustomTrackersVisibility.hoverCount + 1
        if CustomTrackersVisibility.hoverCount == 1 then
            CustomTrackersVisibility.mouseOver = true
            UpdateCustomTrackersVisibility()
        end
    end)

    frame:HookScript("OnLeave", function()
        local vis = GetCustomTrackersVisibilitySettings()
        if not vis or vis.showAlways or not vis.showOnMouseover then return end

        CustomTrackersVisibility.hoverCount = math.max(0, CustomTrackersVisibility.hoverCount - 1)
        if CustomTrackersVisibility.hoverCount == 0 then
            if CustomTrackersVisibility.leaveTimer then
                CustomTrackersVisibility.leaveTimer:Cancel()
            end

            CustomTrackersVisibility.leaveTimer = C_Timer.NewTimer(0.5, function()
                CustomTrackersVisibility.leaveTimer = nil
                if CustomTrackersVisibility.hoverCount == 0 then
                    CustomTrackersVisibility.mouseOver = false
                    UpdateCustomTrackersVisibility()
                end
            end)
        end
    end)
end

local function SetupCustomTrackersMouseoverDetector()
    local vis = GetCustomTrackersVisibilitySettings()

    if CustomTrackersVisibility.mouseoverDetector then
        CustomTrackersVisibility.mouseoverDetector:SetScript("OnUpdate", nil)
        CustomTrackersVisibility.mouseoverDetector:Hide()
        CustomTrackersVisibility.mouseoverDetector = nil
    end

    if CustomTrackersVisibility.leaveTimer then
        CustomTrackersVisibility.leaveTimer:Cancel()
        CustomTrackersVisibility.leaveTimer = nil
    end

    CustomTrackersVisibility.mouseOver = false
    CustomTrackersVisibility.hoverCount = 0

    if not vis or vis.showAlways or not vis.showOnMouseover then
        return
    end

    local frames = GetCustomTrackerFrames()
    for _, frame in ipairs(frames) do
        HookCustomTrackerFrameForMouseover(frame)
        if frame and frame.GetNumChildren then
            local numChildren = frame:GetNumChildren()
            for i = 1, numChildren do
                local child = select(i, frame:GetChildren())
                if child and IsAddonOwnedCDMMouseoverFrame(child) then
                    HookCustomTrackerFrameForMouseover(child)
                end
            end
        end
    end

    local detector = CreateFrame("Frame", nil, UIParent)
    detector:EnableMouse(false)
    CustomTrackersVisibility.mouseoverDetector = detector
end

---------------------------------------------------------------------------
-- UNITFRAMES VISIBILITY CONTROLLER
---------------------------------------------------------------------------
local UnitframesVisibility = {
    currentlyHidden = false,
    isFading = false,
    fadeStart = 0,
    fadeStartAlpha = 1,
    fadeTargetAlpha = 1,
    fadeTargets = nil,
    fadeFrame = nil,
    mouseOver = false,
    mouseoverDetector = nil,
    leaveTimer = nil,
}

local function IsUnitframesCombatLocked()
    if InCombatLockdown and InCombatLockdown() then return true end
    return UnitAffectingCombat and UnitAffectingCombat("player")
end

-- Get unitframesVisibility settings from profile
local function GetUnitframesVisibilitySettings()
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.unitframesVisibility then
        return QUICore.db.profile.unitframesVisibility
    end
    return nil
end

-- Get unit frames and castbars for visibility control
local function GetUnitframeFrames()
    local frames = {}

    if _G.QUI_UnitFrames then
        for unitKey, frame in pairs(_G.QUI_UnitFrames) do
            if frame then
                table.insert(frames, frame)
            end
        end
    end

    local vis = GetUnitframesVisibilitySettings()
    if not (vis and vis.alwaysShowCastbars) then
        if _G.QUI_Castbars then
            for unitKey, castbar in pairs(_G.QUI_Castbars) do
                if castbar then
                    table.insert(frames, castbar)
                end
            end
        end
    end

    return frames
end

-- Player-only subset for the curve-driven HP override. The "Show when
-- health below 100%" condition reads PLAYER hp, so it should only re-show
-- the player's own frame (and castbar) — target/focus/pet/etc. follow
-- their own rules.
local function GetPlayerUnitframes()
    local frames = {}
    if _G.QUI_UnitFrames and _G.QUI_UnitFrames.player then
        table.insert(frames, _G.QUI_UnitFrames.player)
    end
    local vis = GetUnitframesVisibilitySettings()
    if not (vis and vis.alwaysShowCastbars) then
        if _G.QUI_Castbars and _G.QUI_Castbars.player then
            table.insert(frames, _G.QUI_Castbars.player)
        end
    end
    return frames
end

local function GetUnitframeFramesExcludingPlayer()
    local frames = {}
    if _G.QUI_UnitFrames then
        for unitKey, frame in pairs(_G.QUI_UnitFrames) do
            if frame and unitKey ~= "player" then
                table.insert(frames, frame)
            end
        end
    end
    local vis = GetUnitframesVisibilitySettings()
    if not (vis and vis.alwaysShowCastbars) then
        if _G.QUI_Castbars then
            for unitKey, castbar in pairs(_G.QUI_Castbars) do
                if castbar and unitKey ~= "player" then
                    table.insert(frames, castbar)
                end
            end
        end
    end
    return frames
end

local function ApplyUnitframeVisibilityAlpha(frame, alpha)
    if not frame then return end

    if frame._quiCastbar then
        if frame._quiDesiredVisible then return end
        if frame._quiUseAlphaVisibility then
            frame:SetAlpha(0)
            return
        end
    end

    frame:SetAlpha(alpha)
end

-- Determine if Unitframes should be visible (SHOW logic)
local function ShouldUnitframesBeVisible()
    local vis = GetUnitframesVisibilitySettings()
    if not vis then return true end

    -- Combat visibility is a safety floor. Unit frames must not fade out while
    -- protected combat interactions and secret health values are active.
    if IsUnitframesCombatLocked() then
        return true
    end

    -- "Show when health below 100%" override is applied later as a
    -- curve-driven alpha in UpdateUnitframesVisibility — it can't live
    -- here because it'd require comparing a secret HP value in Lua.

    if vis.showAlways then
        local ignoreHideRules = vis.dontHideInDungeonsRaids and Helpers.IsPlayerInDungeonOrRaid and Helpers.IsPlayerInDungeonOrRaid()
        if not ignoreHideRules then
            if vis.hideWhenMounted and not vis.showWhenMounted and Helpers.IsPlayerMounted() then return false end
            if vis.hideWhenFlying and Helpers.IsPlayerFlying() then return false end
            if vis.hideWhenSkyriding and Helpers.IsPlayerSkyriding() then return false end
        end
        return true
    end

    -- Active show conditions override hide rules
    if vis.showWhenTargetExists and UnitExists("target") then return true end
    if vis.showInCombat and UnitAffectingCombat("player") then return true end
    if vis.showInGroup and IsPlayerInGroup() then return true end
    if vis.showInInstance and IsPlayerInInstance() then return true end
    if vis.showOnMouseover and UnitframesVisibility.mouseOver then return true end
    if vis.showWhenMounted and Helpers.IsPlayerMounted() then return true end

    -- No active show condition — apply hide rules
    local ignoreHideRules = vis.dontHideInDungeonsRaids and Helpers.IsPlayerInDungeonOrRaid and Helpers.IsPlayerInDungeonOrRaid()
    if not ignoreHideRules then
        if vis.hideWhenMounted and not vis.showWhenMounted and Helpers.IsPlayerMounted() then return false end
        if vis.hideWhenFlying and Helpers.IsPlayerFlying() then return false end
        if vis.hideWhenSkyriding and Helpers.IsPlayerSkyriding() then return false end
    end

    return false
end

-- OnUpdate handler for Unitframes fade animation
local function OnUnitframesFadeUpdate(self, elapsed)
    local targetAlpha = Helpers.SafeToNumber(UnitframesVisibility.fadeTargetAlpha, 1)
    if targetAlpha < 1 and IsUnitframesCombatLocked() then
        local frames = UnitframesVisibility.fadeTargets or GetUnitframeFrames()
        for _, frame in ipairs(frames) do
            ApplyUnitframeVisibilityAlpha(frame, 1)
        end
        UnitframesVisibility.isFading = false
        UnitframesVisibility.currentlyHidden = false
        UnitframesVisibility.fadeTargetAlpha = 1
        UnitframesVisibility.fadeTargets = nil
        self:SetScript("OnUpdate", nil)
        return
    end

    local vis = GetUnitframesVisibilitySettings()
    local duration = (vis and vis.fadeDuration) or 0.2
    if duration <= 0 then duration = 0.01 end

    local now = GetTime()
    local elapsedTime = now - UnitframesVisibility.fadeStart
    local progress = math.min(elapsedTime / duration, 1)

    local startAlpha = Helpers.SafeToNumber(UnitframesVisibility.fadeStartAlpha, targetAlpha)
    local alpha = startAlpha + (targetAlpha - startAlpha) * progress

    local frames = UnitframesVisibility.fadeTargets or GetUnitframeFrames()
    for _, frame in ipairs(frames) do
        ApplyUnitframeVisibilityAlpha(frame, alpha)
    end

    if progress >= 1 then
        UnitframesVisibility.isFading = false
        UnitframesVisibility.currentlyHidden = (targetAlpha < 1)
        UnitframesVisibility.fadeTargets = nil
        self:SetScript("OnUpdate", nil)
    end
end

-- Start Unitframes fade animation. `framesOverride` lets callers fade a
-- subset (e.g. non-player frames while the player frame is being driven
-- directly by the HP curve).
local function StartUnitframesFade(targetAlpha, framesOverride)
    local frames = framesOverride or GetUnitframeFrames()
    if #frames == 0 then return end

    local forceInstant = IsUnitframesCombatLocked()
    if targetAlpha < 1 and forceInstant then
        targetAlpha = 1
    end

    local rawAlpha = frames[1]:GetAlpha()
    if Helpers.IsSecretValue(rawAlpha) then
        for _, frame in ipairs(frames) do
            ApplyUnitframeVisibilityAlpha(frame, targetAlpha)
        end
        if UnitframesVisibility.fadeFrame then
            UnitframesVisibility.fadeFrame:SetScript("OnUpdate", nil)
        end
        UnitframesVisibility.isFading = false
        UnitframesVisibility.currentlyHidden = (targetAlpha < 1)
        UnitframesVisibility.fadeStartAlpha = targetAlpha
        UnitframesVisibility.fadeTargetAlpha = targetAlpha
        UnitframesVisibility.fadeTargets = nil
        return
    end

    local currentAlpha = Helpers.SafeToNumber(rawAlpha, targetAlpha)

    if forceInstant or math.abs(currentAlpha - targetAlpha) < 0.01 then
        for _, frame in ipairs(frames) do
            ApplyUnitframeVisibilityAlpha(frame, targetAlpha)
        end
        if UnitframesVisibility.fadeFrame then
            UnitframesVisibility.fadeFrame:SetScript("OnUpdate", nil)
        end
        UnitframesVisibility.isFading = false
        UnitframesVisibility.currentlyHidden = (targetAlpha < 1)
        UnitframesVisibility.fadeStartAlpha = targetAlpha
        UnitframesVisibility.fadeTargetAlpha = targetAlpha
        UnitframesVisibility.fadeTargets = nil
        return
    end

    UnitframesVisibility.isFading = true
    UnitframesVisibility.fadeStart = GetTime()
    UnitframesVisibility.fadeStartAlpha = currentAlpha
    UnitframesVisibility.fadeTargetAlpha = targetAlpha
    UnitframesVisibility.fadeTargets = frames

    if not UnitframesVisibility.fadeFrame then
        UnitframesVisibility.fadeFrame = CreateFrame("Frame")
    end
    UnitframesVisibility.fadeFrame:SetScript("OnUpdate", OnUnitframesFadeUpdate)
end

-- Update Unitframes visibility
UpdateUnitframesVisibility = function()
    if (_G.QUI_IsUnitFrameEditModeActive and _G.QUI_IsUnitFrameEditModeActive())
        or Helpers.IsLayoutModeActive() then
        StartUnitframesFade(1)
        return
    end

    local vis = GetUnitframesVisibilitySettings()
    local shouldShow = ShouldUnitframesBeVisible()

    -- Curve-driven "Show when health below 100%" override (PLAYER ONLY).
    -- When rules say hide and the option is enabled, route the secret HP
    -- fraction through the step curve and pipe its return straight into
    -- the player frame's SetAlpha. The value never enters Lua. Other
    -- frames (target/focus/pet/etc.) follow the normal fade rule because
    -- they don't track player HP.
    --   below full → alpha 1 (player frame visible)
    --   exactly 1.0 → alpha 0 (player frame hidden, hide rules win)
    local hpCurve = ((not shouldShow) and vis and vis.showWhenHealthBelow100
        and UnitHealthPercent) and GetDamagedAlphaCurve() or nil
    if hpCurve then
        local damagedAlpha = UnitHealthPercent("player", true, hpCurve)
        for _, frame in ipairs(GetPlayerUnitframes()) do
            ApplyUnitframeVisibilityAlpha(frame, damagedAlpha)
        end

        -- Non-player frames + castbars: fade per rule.
        local fadeAlpha = vis and vis.fadeOutAlpha or 0
        local nonPlayerFrames = GetUnitframeFramesExcludingPlayer()
        if #nonPlayerFrames > 0 then
            StartUnitframesFade(fadeAlpha, nonPlayerFrames)
        else
            -- Only player frame exists — stop any in-flight fade so it
            -- doesn't overwrite the curve-driven alpha.
            if UnitframesVisibility.fadeFrame then
                UnitframesVisibility.fadeFrame:SetScript("OnUpdate", nil)
            end
            UnitframesVisibility.isFading = false
            UnitframesVisibility.fadeTargets = nil
        end
        return
    end

    -- Sync castbar alpha based on "Always Show Castbars" setting
    if _G.QUI_Castbars then
        local targetAlpha = 1

        if vis and vis.alwaysShowCastbars then
            targetAlpha = 1
        else
            targetAlpha = shouldShow and 1 or (vis and vis.fadeOutAlpha or 0)
        end

        for unitKey, castbar in pairs(_G.QUI_Castbars) do
            if castbar then
                ApplyUnitframeVisibilityAlpha(castbar, targetAlpha)
            end
        end
    end

    if shouldShow then
        StartUnitframesFade(1)
    else
        StartUnitframesFade(vis and vis.fadeOutAlpha or 0)
    end
end

-- Setup Unitframes mouseover detector
local function SetupUnitframesMouseoverDetector()
    local vis = GetUnitframesVisibilitySettings()

    if UnitframesVisibility.mouseoverDetector then
        UnitframesVisibility.mouseoverDetector:SetScript("OnUpdate", nil)
        UnitframesVisibility.mouseoverDetector:Hide()
        UnitframesVisibility.mouseoverDetector = nil
    end

    if UnitframesVisibility.leaveTimer then
        UnitframesVisibility.leaveTimer:Cancel()
        UnitframesVisibility.leaveTimer = nil
    end
    UnitframesVisibility.mouseOver = false

    if not vis or vis.showAlways or not vis.showOnMouseover then
        return
    end

    local ufFrames = GetUnitframeFrames()
    local hoverCount = 0

    for _, frame in ipairs(ufFrames) do
        if frame and not _mouseoverHooked[frame] then
            _mouseoverHooked[frame] = true

            frame:HookScript("OnEnter", function()
                if UnitframesVisibility.leaveTimer then
                    UnitframesVisibility.leaveTimer:Cancel()
                    UnitframesVisibility.leaveTimer = nil
                end
                hoverCount = hoverCount + 1
                if hoverCount == 1 then
                    UnitframesVisibility.mouseOver = true
                    UpdateUnitframesVisibility()
                end
            end)

            frame:HookScript("OnLeave", function()
                hoverCount = math.max(0, hoverCount - 1)
                if hoverCount == 0 then
                    if UnitframesVisibility.leaveTimer then
                        UnitframesVisibility.leaveTimer:Cancel()
                    end
                    UnitframesVisibility.leaveTimer = C_Timer.NewTimer(0.5, function()
                        UnitframesVisibility.leaveTimer = nil
                        if hoverCount == 0 then
                            UnitframesVisibility.mouseOver = false
                            UpdateUnitframesVisibility()
                        end
                    end)
                end
            end)
        end
    end

    local detector = CreateFrame("Frame", nil, UIParent)
    detector:EnableMouse(false)
    UnitframesVisibility.mouseoverDetector = detector
end

---------------------------------------------------------------------------
-- ACTION BARS VISIBILITY CONTROLLER
---------------------------------------------------------------------------
local ActionBarsVisibility = {
    currentlyHidden = false,
    isFading = false,
    fadeStart = 0,
    fadeStartAlpha = 1,
    fadeTargetAlpha = 1,
    fadeTargets = nil,
    fadeFrame = nil,
    mouseOver = false,
    mouseoverDetector = nil,
    leaveTimer = nil,
}

local function GetActionBarsVisibilitySettings()
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.actionBarsVisibility then
        return QUICore.db.profile.actionBarsVisibility
    end
    return nil
end

local function GetActionBarFrames()
    local frames = {}
    -- Action bar containers from the owned action bar system
    if ns.ActionBarsOwned and ns.ActionBarsOwned.containers then
        for barKey, container in pairs(ns.ActionBarsOwned.containers) do
            if container then
                frames[#frames + 1] = { barKey = barKey, container = container }
            end
        end
    end
    return frames
end

local function ShouldActionBarsBeVisible()
    local vis = GetActionBarsVisibilitySettings()
    if not vis then return true end

    if vis.showAlways then
        -- "Always show" still respects hide rules (mounted/flying/etc.)
        local ignoreHideRules = vis.dontHideInDungeonsRaids and Helpers.IsPlayerInDungeonOrRaid and Helpers.IsPlayerInDungeonOrRaid()
        if not ignoreHideRules then
            if vis.hideWhenMounted and not vis.showWhenMounted and Helpers.IsPlayerMounted() then return false end
            if vis.hideWhenInVehicle and Helpers.IsPlayerInVehicle and Helpers.IsPlayerInVehicle() then return false end
            if vis.hideWhenFlying and Helpers.IsPlayerFlying() then return false end
            if vis.hideWhenSkyriding and Helpers.IsPlayerSkyriding() then return false end
        end
        return true
    end

    -- Active show conditions (target, combat, etc.) override hide rules
    if vis.showWhenTargetExists and UnitExists("target") then return true end
    if vis.showInCombat and UnitAffectingCombat("player") then return true end
    if vis.showInGroup and IsPlayerInGroup() then return true end
    if vis.showInInstance and IsPlayerInInstance() then return true end
    if vis.showOnMouseover and ActionBarsVisibility.mouseOver then return true end
    if vis.showWhenMounted and Helpers.IsPlayerMounted() then return true end

    -- No active show condition matched — apply hide rules
    local ignoreHideRules = vis.dontHideInDungeonsRaids and Helpers.IsPlayerInDungeonOrRaid and Helpers.IsPlayerInDungeonOrRaid()
    if not ignoreHideRules then
        if vis.hideWhenMounted and not vis.showWhenMounted and Helpers.IsPlayerMounted() then return false end
        if vis.hideWhenInVehicle and Helpers.IsPlayerInVehicle and Helpers.IsPlayerInVehicle() then return false end
        if vis.hideWhenFlying and Helpers.IsPlayerFlying() then return false end
        if vis.hideWhenSkyriding and Helpers.IsPlayerSkyriding() then return false end
    end

    return false
end

local function OnActionBarsFadeUpdate(self, elapsed)
    local targetAlpha = Helpers.SafeToNumber(ActionBarsVisibility.fadeTargetAlpha, 1)
    local vis = GetActionBarsVisibilitySettings()
    local duration = (vis and vis.fadeDuration) or 0.2
    if duration <= 0 then duration = 0.01 end

    local now = GetTime()
    local elapsedTime = now - ActionBarsVisibility.fadeStart
    local progress = math.min(elapsedTime / duration, 1)

    local startAlpha = Helpers.SafeToNumber(ActionBarsVisibility.fadeStartAlpha, targetAlpha)
    local alpha = startAlpha + (targetAlpha - startAlpha) * progress

    local frames = ActionBarsVisibility.fadeTargets or GetActionBarFrames()
    local setBarAlpha = ns.ActionBarsOwned and ns.ActionBarsOwned.SetBarAlpha
    for _, entry in ipairs(frames) do
        if setBarAlpha then
            pcall(setBarAlpha, entry.barKey, alpha)
        elseif entry.container and entry.container.SetAlpha then
            pcall(entry.container.SetAlpha, entry.container, alpha)
        end
    end

    if progress >= 1 then
        ActionBarsVisibility.isFading = false
        ActionBarsVisibility.currentlyHidden = (targetAlpha < 1)
        ActionBarsVisibility.fadeTargets = nil
        self:SetScript("OnUpdate", nil)
    end
end

local function StartActionBarsFade(targetAlpha)
    local frames = GetActionBarFrames()
    if #frames == 0 then return end

    local rawAlpha = frames[1].container:GetAlpha()
    if Helpers.IsSecretValue(rawAlpha) then
        local setBarAlpha = ns.ActionBarsOwned and ns.ActionBarsOwned.SetBarAlpha
        for _, entry in ipairs(frames) do
            if setBarAlpha then
                pcall(setBarAlpha, entry.barKey, targetAlpha)
            elseif entry.container and entry.container.SetAlpha then
                pcall(entry.container.SetAlpha, entry.container, targetAlpha)
            end
        end
        if ActionBarsVisibility.fadeFrame then
            ActionBarsVisibility.fadeFrame:SetScript("OnUpdate", nil)
        end
        ActionBarsVisibility.isFading = false
        ActionBarsVisibility.currentlyHidden = (targetAlpha < 1)
        ActionBarsVisibility.fadeStartAlpha = targetAlpha
        ActionBarsVisibility.fadeTargetAlpha = targetAlpha
        ActionBarsVisibility.fadeTargets = nil
        return
    end

    local currentAlpha = Helpers.SafeToNumber(rawAlpha, targetAlpha)

    if math.abs(currentAlpha - targetAlpha) < 0.01 then
        ActionBarsVisibility.currentlyHidden = (targetAlpha < 1)
        ActionBarsVisibility.fadeStartAlpha = targetAlpha
        ActionBarsVisibility.fadeTargetAlpha = targetAlpha
        return
    end

    ActionBarsVisibility.isFading = true
    ActionBarsVisibility.fadeStart = GetTime()
    ActionBarsVisibility.fadeStartAlpha = currentAlpha
    ActionBarsVisibility.fadeTargetAlpha = targetAlpha
    ActionBarsVisibility.fadeTargets = frames

    if not ActionBarsVisibility.fadeFrame then
        ActionBarsVisibility.fadeFrame = CreateFrame("Frame")
    end
    ActionBarsVisibility.fadeFrame:SetScript("OnUpdate", OnActionBarsFadeUpdate)
end

local function StopActionBarsFade()
    ActionBarsVisibility.isFading = false
    ActionBarsVisibility.fadeTargets = nil
    if ActionBarsVisibility.fadeFrame then
        ActionBarsVisibility.fadeFrame:SetScript("OnUpdate", nil)
    end
end

local function IsActionBarMouseoverFadeEnabled()
    if not (QUICore and QUICore.db and QUICore.db.profile) then return false end

    local actionBars = QUICore.db.profile.actionBars
    if type(actionBars) ~= "table" then return false end

    local fade = actionBars.fade
    local globalFadeEnabled = type(fade) == "table" and fade.enabled == true
    local bars = actionBars.bars
    local containers = ns.ActionBarsOwned and ns.ActionBarsOwned.containers

    if type(containers) == "table" and next(containers) ~= nil then
        for barKey in pairs(containers) do
            local barSettings = type(bars) == "table" and bars[barKey]
            local fadeEnabled = type(barSettings) == "table" and barSettings.fadeEnabled
            if fadeEnabled == nil then
                fadeEnabled = globalFadeEnabled
            end
            if fadeEnabled then
                return true
            end
        end
        return false
    end

    return globalFadeEnabled
end

local function UpdateActionBarsVisibility()
    if Helpers.IsEditModeActive() or Helpers.IsLayoutModeActive() then
        StartActionBarsFade(1)
        return
    end

    local shouldShow = ShouldActionBarsBeVisible()
    local vis = GetActionBarsVisibilitySettings()

    if shouldShow then
        if IsActionBarMouseoverFadeEnabled() then
            StopActionBarsFade()
            ActionBarsVisibility.currentlyHidden = false
            if type(_G.QUI_RefreshActionBarFade) == "function" then
                _G.QUI_RefreshActionBarFade()
            end
        else
            StartActionBarsFade(1)
        end
    else
        StartActionBarsFade(vis and vis.fadeOutAlpha or 0)
    end
end

local function SetupActionBarsMouseoverDetector()
    local vis = GetActionBarsVisibilitySettings()

    if ActionBarsVisibility.mouseoverDetector then
        ActionBarsVisibility.mouseoverDetector:SetScript("OnUpdate", nil)
        ActionBarsVisibility.mouseoverDetector:Hide()
        ActionBarsVisibility.mouseoverDetector = nil
    end

    if ActionBarsVisibility.leaveTimer then
        ActionBarsVisibility.leaveTimer:Cancel()
        ActionBarsVisibility.leaveTimer = nil
    end
    ActionBarsVisibility.mouseOver = false

    if not vis or vis.showAlways or not vis.showOnMouseover then
        return
    end

    local abFrames = GetActionBarFrames()
    local hoverCount = 0

    for _, entry in ipairs(abFrames) do
        local frame = entry.container
        if frame and not _mouseoverHooked[frame] then
            _mouseoverHooked[frame] = true

            frame:HookScript("OnEnter", function()
                if ActionBarsVisibility.leaveTimer then
                    ActionBarsVisibility.leaveTimer:Cancel()
                    ActionBarsVisibility.leaveTimer = nil
                end
                hoverCount = hoverCount + 1
                if hoverCount == 1 then
                    ActionBarsVisibility.mouseOver = true
                    UpdateActionBarsVisibility()
                end
            end)

            frame:HookScript("OnLeave", function()
                hoverCount = math.max(0, hoverCount - 1)
                if hoverCount == 0 then
                    if ActionBarsVisibility.leaveTimer then
                        ActionBarsVisibility.leaveTimer:Cancel()
                    end
                    ActionBarsVisibility.leaveTimer = C_Timer.NewTimer(0.3, function()
                        ActionBarsVisibility.leaveTimer = nil
                        if hoverCount == 0 then
                            ActionBarsVisibility.mouseOver = false
                            UpdateActionBarsVisibility()
                        end
                    end)
                end
            end)
        end
    end

    -- Polling detector: catches mouseover when bars are fully faded out
    -- and OnEnter may not fire reliably on transparent containers
    local detector = CreateFrame("Frame", nil, UIParent)
    detector:EnableMouse(false)
    local pollInterval = 0
    detector:SetScript("OnUpdate", function(self, elapsed)
        pollInterval = pollInterval + elapsed
        if pollInterval < 0.1 then return end
        pollInterval = 0

        if ActionBarsVisibility.mouseOver then return end
        if not ActionBarsVisibility.currentlyHidden
            and not (ActionBarsVisibility.isFading and ActionBarsVisibility.fadeTargetAlpha < 1) then
            return
        end

        local frames = GetActionBarFrames()
        for _, entry in ipairs(frames) do
            local container = entry.container
            local alpha = container and container.GetAlpha and Helpers.SafeToNumber(container:GetAlpha(), 1) or 1
            if container and alpha < 0.99 and container:IsMouseOver() then
                if ActionBarsVisibility.leaveTimer then
                    ActionBarsVisibility.leaveTimer:Cancel()
                    ActionBarsVisibility.leaveTimer = nil
                end
                hoverCount = 1
                ActionBarsVisibility.mouseOver = true
                UpdateActionBarsVisibility()
                return
            end
        end
    end)
    ActionBarsVisibility.mouseoverDetector = detector
end

---------------------------------------------------------------------------
-- CHAT FRAMES VISIBILITY CONTROLLER
---------------------------------------------------------------------------
local ChatVisibility = {
    currentlyHidden = false,
    isFading = false,
    fadeStart = 0,
    fadeStartAlpha = 1,
    fadeTargetAlpha = 1,
    fadeTargets = nil,
    fadeFrame = nil,
    mouseOver = false,
    mouseoverDetector = nil,
    leaveTimer = nil,
}

local function GetChatVisibilitySettings()
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.chatVisibility then
        return QUICore.db.profile.chatVisibility
    end
    return nil
end

local function GetChatFrames()
    local frames = {}
    for i = 1, NUM_CHAT_WINDOWS do
        local chatFrame = _G["ChatFrame" .. i]
        if chatFrame and chatFrame:IsShown() then
            -- Include the chat frame and its dock/tab
            frames[#frames + 1] = chatFrame
        end
    end
    -- Include GeneralDockManager (the tab bar)
    if _G.GeneralDockManager then
        frames[#frames + 1] = _G.GeneralDockManager
    end
    return frames
end

local function ShouldChatBeVisible()
    local vis = GetChatVisibilitySettings()
    if not vis then return true end

    if vis.showAlways then
        local ignoreHideRules = vis.dontHideInDungeonsRaids and Helpers.IsPlayerInDungeonOrRaid and Helpers.IsPlayerInDungeonOrRaid()
        if not ignoreHideRules then
            if vis.hideWhenMounted and not vis.showWhenMounted and Helpers.IsPlayerMounted() then return false end
            if vis.hideWhenInVehicle and Helpers.IsPlayerInVehicle and Helpers.IsPlayerInVehicle() then return false end
            if vis.hideWhenFlying and Helpers.IsPlayerFlying() then return false end
            if vis.hideWhenSkyriding and Helpers.IsPlayerSkyriding() then return false end
        end
        return true
    end

    -- Active show conditions override hide rules
    if vis.showWhenTargetExists and UnitExists("target") then return true end
    if vis.showInCombat and UnitAffectingCombat("player") then return true end
    if vis.showInGroup and IsPlayerInGroup() then return true end
    if vis.showInInstance and IsPlayerInInstance() then return true end
    if vis.showOnMouseover and ChatVisibility.mouseOver then return true end
    if vis.showWhenMounted and Helpers.IsPlayerMounted() then return true end

    -- No active show condition — apply hide rules
    local ignoreHideRules = vis.dontHideInDungeonsRaids and Helpers.IsPlayerInDungeonOrRaid and Helpers.IsPlayerInDungeonOrRaid()
    if not ignoreHideRules then
        if vis.hideWhenMounted and not vis.showWhenMounted and Helpers.IsPlayerMounted() then return false end
        if vis.hideWhenInVehicle and Helpers.IsPlayerInVehicle and Helpers.IsPlayerInVehicle() then return false end
        if vis.hideWhenFlying and Helpers.IsPlayerFlying() then return false end
        if vis.hideWhenSkyriding and Helpers.IsPlayerSkyriding() then return false end
    end

    return false
end

local function OnChatFadeUpdate(self, elapsed)
    local targetAlpha = Helpers.SafeToNumber(ChatVisibility.fadeTargetAlpha, 1)
    local vis = GetChatVisibilitySettings()
    local duration = (vis and vis.fadeDuration) or 0.2
    if duration <= 0 then duration = 0.01 end

    local now = GetTime()
    local elapsedTime = now - ChatVisibility.fadeStart
    local progress = math.min(elapsedTime / duration, 1)

    local startAlpha = Helpers.SafeToNumber(ChatVisibility.fadeStartAlpha, targetAlpha)
    local alpha = startAlpha + (targetAlpha - startAlpha) * progress

    local frames = ChatVisibility.fadeTargets or GetChatFrames()
    for _, frame in ipairs(frames) do
        if frame and frame.SetAlpha then
            pcall(frame.SetAlpha, frame, alpha)
        end
    end

    if progress >= 1 then
        ChatVisibility.isFading = false
        ChatVisibility.currentlyHidden = (targetAlpha < 1)
        ChatVisibility.fadeTargets = nil
        self:SetScript("OnUpdate", nil)
    end
end

local function StartChatFade(targetAlpha)
    local frames = GetChatFrames()
    if #frames == 0 then return end

    local rawAlpha = frames[1]:GetAlpha()
    if Helpers.IsSecretValue(rawAlpha) then
        for _, frame in ipairs(frames) do
            if frame and frame.SetAlpha then
                pcall(frame.SetAlpha, frame, targetAlpha)
            end
        end
        if ChatVisibility.fadeFrame then
            ChatVisibility.fadeFrame:SetScript("OnUpdate", nil)
        end
        ChatVisibility.isFading = false
        ChatVisibility.currentlyHidden = (targetAlpha < 1)
        ChatVisibility.fadeStartAlpha = targetAlpha
        ChatVisibility.fadeTargetAlpha = targetAlpha
        ChatVisibility.fadeTargets = nil
        return
    end

    local currentAlpha = Helpers.SafeToNumber(rawAlpha, targetAlpha)

    if math.abs(currentAlpha - targetAlpha) < 0.01 then
        ChatVisibility.currentlyHidden = (targetAlpha < 1)
        ChatVisibility.fadeStartAlpha = targetAlpha
        ChatVisibility.fadeTargetAlpha = targetAlpha
        return
    end

    ChatVisibility.isFading = true
    ChatVisibility.fadeStart = GetTime()
    ChatVisibility.fadeStartAlpha = currentAlpha
    ChatVisibility.fadeTargetAlpha = targetAlpha
    ChatVisibility.fadeTargets = frames

    if not ChatVisibility.fadeFrame then
        ChatVisibility.fadeFrame = CreateFrame("Frame")
    end
    ChatVisibility.fadeFrame:SetScript("OnUpdate", OnChatFadeUpdate)
end

local function UpdateChatVisibility()
    if Helpers.IsEditModeActive() or Helpers.IsLayoutModeActive() then
        StartChatFade(1)
        return
    end

    local shouldShow = ShouldChatBeVisible()
    local vis = GetChatVisibilitySettings()

    if shouldShow then
        StartChatFade(1)
    else
        StartChatFade(vis and vis.fadeOutAlpha or 0)
    end
end

local function SetupChatMouseoverDetector()
    local vis = GetChatVisibilitySettings()

    if ChatVisibility.mouseoverDetector then
        ChatVisibility.mouseoverDetector:SetScript("OnUpdate", nil)
        ChatVisibility.mouseoverDetector:Hide()
        ChatVisibility.mouseoverDetector = nil
    end

    if ChatVisibility.leaveTimer then
        ChatVisibility.leaveTimer:Cancel()
        ChatVisibility.leaveTimer = nil
    end
    ChatVisibility.mouseOver = false

    if not vis or vis.showAlways or not vis.showOnMouseover then
        return
    end

    local chatFrames = GetChatFrames()
    local hoverCount = 0

    for _, frame in ipairs(chatFrames) do
        if frame and not _mouseoverHooked[frame] then
            _mouseoverHooked[frame] = true

            frame:HookScript("OnEnter", function()
                if ChatVisibility.leaveTimer then
                    ChatVisibility.leaveTimer:Cancel()
                    ChatVisibility.leaveTimer = nil
                end
                hoverCount = hoverCount + 1
                if hoverCount == 1 then
                    ChatVisibility.mouseOver = true
                    UpdateChatVisibility()
                end
            end)

            frame:HookScript("OnLeave", function()
                hoverCount = math.max(0, hoverCount - 1)
                if hoverCount == 0 then
                    if ChatVisibility.leaveTimer then
                        ChatVisibility.leaveTimer:Cancel()
                    end
                    ChatVisibility.leaveTimer = C_Timer.NewTimer(0.5, function()
                        ChatVisibility.leaveTimer = nil
                        if hoverCount == 0 then
                            ChatVisibility.mouseOver = false
                            UpdateChatVisibility()
                        end
                    end)
                end
            end)
        end
    end

    local detector = CreateFrame("Frame", nil, UIParent)
    detector:EnableMouse(false)
    ChatVisibility.mouseoverDetector = detector
end

---------------------------------------------------------------------------
-- SHARED EVENT HANDLING
---------------------------------------------------------------------------
local visibilityEventFrame = CreateFrame("Frame")
visibilityEventFrame:RegisterEvent("ADDON_LOADED")
visibilityEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
visibilityEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
visibilityEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
visibilityEventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
visibilityEventFrame:RegisterEvent("GROUP_JOINED")
visibilityEventFrame:RegisterEvent("GROUP_LEFT")
visibilityEventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
visibilityEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
visibilityEventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
visibilityEventFrame:RegisterEvent("UNIT_ENTERED_VEHICLE")
visibilityEventFrame:RegisterEvent("UNIT_EXITED_VEHICLE")
visibilityEventFrame:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR")
visibilityEventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
visibilityEventFrame:RegisterEvent("PLAYER_FLAGS_CHANGED")
visibilityEventFrame:RegisterEvent("PLAYER_IS_GLIDING_CHANGED")
visibilityEventFrame:RegisterUnitEvent("UNIT_HEALTH", "player")
visibilityEventFrame:RegisterUnitEvent("UNIT_MAXHEALTH", "player")

local _pendingSetupTimer = nil

-- Frame-based event coalescing: burst-prone events (GROUP_ROSTER_UPDATE,
-- ZONE_CHANGED_NEW_AREA, etc.) fire multiple times in the same frame.
-- Instead of running 4 visibility updates per event, coalesce into one
-- update on the next frame.  Show/Hide pattern auto-deduplicates.
local visCoalesceFrame = CreateFrame("Frame")
visCoalesceFrame:Hide()
visCoalesceFrame:SetScript("OnUpdate", function(self)
    self:Hide()
    UpdateCDMVisibility()
    UpdateCustomTrackersVisibility()
    UpdateUnitframesVisibility()
    UpdateActionBarsVisibility()
    UpdateChatVisibility()
end)

visibilityEventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_FLAGS_CHANGED" then
        local unit = ...
        if unit ~= "player" then return end
    end
    if event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" then
        local unit = ...
        if unit ~= "player" then return end
    end

    -- Health events — re-run unit-frame visibility so the curve-driven
    -- alpha override picks up the new HP fraction.
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        if UpdateUnitframesVisibility then UpdateUnitframesVisibility() end
    end

    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName ~= ADDON_NAME then return end
        self:UnregisterEvent("ADDON_LOADED")
    end

    if event == "ADDON_LOADED" or event == "PLAYER_ENTERING_WORLD" then
        -- Schedule delayed setup so CDM/UF frames have time to render.
        -- Also runs on PLAYER_ENTERING_WORLD to cover zone transitions.
        if _pendingSetupTimer then
            _pendingSetupTimer:Cancel()
        end
        _pendingSetupTimer = C_Timer.NewTimer(2.0, function()
            _pendingSetupTimer = nil
            SetupCDMMouseoverDetector()
                SetupCustomTrackersMouseoverDetector()
            SetupUnitframesMouseoverDetector()
            SetupActionBarsMouseoverDetector()
            SetupChatMouseoverDetector()
            -- CDM and custom bars run here — UF/AB/Chat visibility is driven by
            -- events (dismount, combat, target, etc.).  Running a full
            -- re-eval here flashes frames because IsMounted() and
            -- IsPlayerInDungeonOrRaid() can still return stale values
            -- 2+ seconds after a zone transition. UNIT_HEALTH events keep
            -- the curve-driven HP override current independently.
            UpdateCDMVisibility()
            UpdateCustomTrackersVisibility()
        end)
    end

    -- On zone-transition events, skip the coalesced visibility update for
    -- controllers that are currently hidden. IsMounted()/IsFlying() return
    -- stale values right after a load screen, which makes ShouldBeVisible
    -- erroneously return true and flash frames.  The 2-second setup timer
    -- runs the authoritative re-evaluation once API state has settled.
    -- All other events (dismount, combat, target change) trigger normally.
    if (event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA")
        and (UnitframesVisibility.currentlyHidden
            or CustomTrackersVisibility.currentlyHidden
            or ActionBarsVisibility.currentlyHidden
            or ChatVisibility.currentlyHidden) then
        -- Run CDM only — it doesn't have mount-based hide rules
        UpdateCDMVisibility()
        return
    end

    -- Coalesce visibility updates: if multiple events fire in the same
    -- frame (e.g. GROUP_ROSTER_UPDATE bursts), only one update runs.
    visCoalesceFrame:Show()
end)

---------------------------------------------------------------------------
-- GLOBAL EXPORTS
---------------------------------------------------------------------------
_G.QUI_RefreshCDMVisibility = function()
    _cdmFramesDirty = true
    UpdateCDMVisibility()
end
_G.QUI_RefreshCustomTrackersVisibility = UpdateCustomTrackersVisibility
_G.QUI_RefreshUnitframesVisibility = UpdateUnitframesVisibility
_G.QUI_RefreshCDMMouseover = SetupCDMMouseoverDetector
_G.QUI_RefreshCustomTrackersMouseover = SetupCustomTrackersMouseoverDetector
_G.QUI_RefreshUnitframesMouseover = SetupUnitframesMouseoverDetector
_G.QUI_ShouldCDMBeVisible = ShouldCDMBeVisible
_G.QUI_ShouldCustomTrackersBeVisible = ShouldCustomTrackersBeVisible
_G.QUI_ShouldUnitframesBeVisible = ShouldUnitframesBeVisible
_G.QUI_RefreshActionBarsVisibility = UpdateActionBarsVisibility
_G.QUI_RefreshActionBarsMouseover = SetupActionBarsMouseoverDetector
_G.QUI_RefreshChatVisibility = UpdateChatVisibility
_G.QUI_RefreshChatMouseover = SetupChatMouseoverDetector

if ns.Registry then
    ns.Registry:Register("cdmVisibility", {
        refresh = _G.QUI_RefreshCDMVisibility,
        priority = 10,
        group = "cooldowns",
        importCategories = { "cdm" },
    })
    ns.Registry:Register("customTrackersVisibility", {
        refresh = _G.QUI_RefreshCustomTrackersVisibility,
        priority = 10,
        group = "cooldowns",
        importCategories = { "customTrackers" },
    })
end

---------------------------------------------------------------------------
-- NAMESPACE EXPORTS
---------------------------------------------------------------------------
-- Expose HookFrameForMouseover so CDM engines can hook new icons during skinning
ns.HookFrameForMouseover = function(frame)
    HookFrameForMouseover(frame)
    if HookCustomTrackerFrameForMouseover then
        HookCustomTrackerFrameForMouseover(frame)
    end
end
-- Expose cache invalidation so engines can mark frames dirty after init
ns.InvalidateCDMFrameCache = InvalidateCDMFrameCache
ns.GetCDMFrameCacheStats = function()
    return {
        dirty = _cdmFramesDirty and true or false,
        size  = #_cdmFramesCache,
    }
end

---------------------------------------------------------------------------
-- LAYOUT MODE: force all frames visible on enter, restore on exit
---------------------------------------------------------------------------
local function RefreshAllVisibility()
    UpdateCDMVisibility()
    UpdateCustomTrackersVisibility()
    UpdateUnitframesVisibility()
    UpdateActionBarsVisibility()
    UpdateChatVisibility()
end

C_Timer.After(2, function()
    local core = ns.Helpers and ns.Helpers.GetCore and ns.Helpers.GetCore()
    if not core then return end
    if core.RegisterLayoutModeEnter then
        core:RegisterLayoutModeEnter(RefreshAllVisibility)
    end
    if core.RegisterLayoutModeExit then
        core:RegisterLayoutModeExit(RefreshAllVisibility)
    end
end)
