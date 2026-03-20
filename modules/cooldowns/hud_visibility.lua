--[[
    QUI HUD Visibility Controllers
    Manages fade-in/fade-out visibility for CDM viewers and unit frames.
    Independent of CDM engine — reads frames from ns.CDMProvider (or
    falls back to well-known Blizzard globals).
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

---------------------------------------------------------------------------
-- FORWARD DECLARATIONS
---------------------------------------------------------------------------
local UpdateCDMVisibility
local UpdateUnitframesVisibility

---------------------------------------------------------------------------
-- HEALTH STATE TRACKER
-- UnitHealth() always returns secret values from addon code in WoW 12.0+
-- and COMBAT_LOG_EVENT_UNFILTERED is restricted. Use RegisterStateDriver
-- with a health macro conditional — evaluated in Blizzard's secure code,
-- completely bypassing addon taint.
---------------------------------------------------------------------------
-- HEALTH STATE DETECTION
-- ALL health APIs return secret values from addon code in WoW 12.0+.
-- Secret values can't be compared, even inside pcall.
--
-- Solution: UNIT_HEALTH fires when health changes. When health is at 100%
-- and stable, UNIT_HEALTH stops firing. So:
-- 1. Every UNIT_HEALTH event → set _healthBelowMax = true (health changing)
-- 2. Start/reset a short timer on each event
-- 3. When timer expires (no more events) → health stabilized → assume 100%
--    (natural regen brings health back to max, then UNIT_HEALTH stops)
---------------------------------------------------------------------------
local _healthBelowMax = false
local _healthStableTimer = nil
local HEALTH_STABLE_DURATION = 3.0  -- seconds after last health event to assume full

local function UpdateHealthState()
    -- UNIT_HEALTH fired — health is changing, assume below max
    local wasBelowMax = _healthBelowMax
    _healthBelowMax = true

    if not wasBelowMax and UpdateUnitframesVisibility then
        UpdateUnitframesVisibility()
    end

    -- Reset the stable timer — when health stops changing, assume full
    if _healthStableTimer then
        _healthStableTimer:Cancel()
    end
    _healthStableTimer = C_Timer.NewTimer(HEALTH_STABLE_DURATION, function()
        _healthStableTimer = nil
        _healthBelowMax = false
        if UpdateUnitframesVisibility then
            UpdateUnitframesVisibility()
        end
    end)
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
                _cdmFramesCache[#_cdmFramesCache + 1] = frames[i]
            end
        end
    else
        -- Fallback: hardcoded Blizzard viewer names
        if _G.EssentialCooldownViewer then
            _cdmFramesCache[#_cdmFramesCache + 1] = _G.EssentialCooldownViewer
        end
        if _G.UtilityCooldownViewer then
            _cdmFramesCache[#_cdmFramesCache + 1] = _G.UtilityCooldownViewer
        end
        if _G.BuffIconCooldownViewer then
            _cdmFramesCache[#_cdmFramesCache + 1] = _G.BuffIconCooldownViewer
        end
        if _G.BuffBarCooldownViewer then
            _cdmFramesCache[#_cdmFramesCache + 1] = _G.BuffBarCooldownViewer
        end
    end

    _cdmFramesDirty = false
    return _cdmFramesCache
end

---------------------------------------------------------------------------
-- CDM VISIBILITY SETTINGS CACHE
---------------------------------------------------------------------------
local _visSettingsCache = nil
local QUICore = ns.Addon

local function GetCDMVisibilitySettings()
    if _visSettingsCache then return _visSettingsCache end
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.cdmVisibility then
        _visSettingsCache = QUICore.db.profile.cdmVisibility
        return _visSettingsCache
    end
    return nil
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
    fadeFrame = nil,
    mouseOver = false,
    mouseoverDetector = nil,
    hoverCount = 0,
    leaveTimer = nil,
}

-- Determine if CDM should be visible (SHOW logic)
local function ShouldCDMBeVisible()
    local vis = GetCDMVisibilitySettings()
    if not vis then return true end

    local ignoreHideRules = vis.dontHideInDungeonsRaids and Helpers.IsPlayerInDungeonOrRaid and Helpers.IsPlayerInDungeonOrRaid()
    if not ignoreHideRules then
        if vis.hideWhenMounted and Helpers.IsPlayerMounted() then return false end
        if vis.hideWhenFlying and Helpers.IsPlayerFlying() then return false end
        if vis.hideWhenSkyriding and Helpers.IsPlayerSkyriding() then return false end
        if vis.hideWhenInVehicle and Helpers.IsPlayerInVehicle and Helpers.IsPlayerInVehicle() then return false end
    end

    if vis.showAlways then return true end

    if vis.showWhenTargetExists and UnitExists("target") then return true end
    if vis.showInCombat and UnitAffectingCombat("player") then return true end
    if vis.showInGroup and IsPlayerInGroup() then return true end
    if vis.showInInstance and IsPlayerInInstance() then return true end
    if vis.showOnMouseover and CDMVisibility.mouseOver then return true end

    return false
end

-- OnUpdate handler for CDM fade animation
local function OnCDMFadeUpdate(self, elapsed)
    local vis = GetCDMVisibilitySettings()
    local duration = (vis and vis.fadeDuration) or 0.2
    if duration <= 0 then duration = 0.01 end

    local now = GetTime()
    local elapsedTime = now - CDMVisibility.fadeStart
    local progress = math.min(elapsedTime / duration, 1)

    local alpha = CDMVisibility.fadeStartAlpha +
        (CDMVisibility.fadeTargetAlpha - CDMVisibility.fadeStartAlpha) * progress

    local frames = GetCDMFrames()
    for i = #frames, 1, -1 do
        local frame = frames[i]
        local ok = false
        if frame and frame.SetAlpha and (not frame.IsForbidden or not frame:IsForbidden()) then
            ok = pcall(frame.SetAlpha, frame, alpha)
        end
        if not ok then
            table.remove(frames, i)
            _cdmFramesDirty = true
        end
    end

    if progress >= 1 then
        CDMVisibility.isFading = false
        CDMVisibility.currentlyHidden = (CDMVisibility.fadeTargetAlpha < 1)
        self:SetScript("OnUpdate", nil)
    end
end

-- Start CDM fade animation
local function StartCDMFade(targetAlpha)
    local frames = GetCDMFrames()
    if #frames == 0 then return end

    local currentAlpha = frames[1]:GetAlpha()

    if math.abs(currentAlpha - targetAlpha) < 0.01 then
        CDMVisibility.currentlyHidden = (targetAlpha < 1)
        return
    end

    CDMVisibility.isFading = true
    CDMVisibility.fadeStart = GetTime()
    CDMVisibility.fadeStartAlpha = currentAlpha
    CDMVisibility.fadeTargetAlpha = targetAlpha

    if not CDMVisibility.fadeFrame then
        CDMVisibility.fadeFrame = CreateFrame("Frame")
    end
    CDMVisibility.fadeFrame:SetScript("OnUpdate", OnCDMFadeUpdate)
end

-- Update CDM visibility
UpdateCDMVisibility = function()
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

-- Hook a single frame for mouseover detection
-- Exported on ns so CDM engines can call it when skinning new icons
local function HookFrameForMouseover(frame)
    if not frame or _mouseoverHooked[frame] then return end

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

    -- Hook container frames
    local cdmFrames = GetCDMFrames()
    for _, frame in ipairs(cdmFrames) do
        HookFrameForMouseover(frame)
    end

    -- Hook existing icons from each viewer
    -- Use provider for viewer enumeration when available
    local viewers
    if ns.CDMProvider and ns.CDMProvider.GetViewerFrames then
        viewers = ns.CDMProvider:GetViewerFrames()
    else
        viewers = {}
        local names = {"EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer"}
        for _, name in ipairs(names) do
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
                if child and child.IsShown and child:IsShown() then
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
-- UNITFRAMES VISIBILITY CONTROLLER
---------------------------------------------------------------------------
local UnitframesVisibility = {
    currentlyHidden = false,
    isFading = false,
    fadeStart = 0,
    fadeStartAlpha = 1,
    fadeTargetAlpha = 1,
    fadeFrame = nil,
    mouseOver = false,
    mouseoverDetector = nil,
    leaveTimer = nil,
}

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

    -- Health < 100% overrides hide rules (uses UNIT_HEALTH event timing)
    if vis.showWhenHealthBelow100 and _healthBelowMax then
        return true
    end

    local ignoreHideRules = vis.dontHideInDungeonsRaids and Helpers.IsPlayerInDungeonOrRaid and Helpers.IsPlayerInDungeonOrRaid()
    if not ignoreHideRules then
        if vis.hideWhenMounted and Helpers.IsPlayerMounted() then return false end
        if vis.hideWhenFlying and Helpers.IsPlayerFlying() then return false end
        if vis.hideWhenSkyriding and Helpers.IsPlayerSkyriding() then return false end
    end

    if vis.showAlways then return true end

    if vis.showWhenTargetExists and UnitExists("target") then return true end
    if vis.showInCombat and UnitAffectingCombat("player") then return true end
    if vis.showInGroup and IsPlayerInGroup() then return true end
    if vis.showInInstance and IsPlayerInInstance() then return true end
    if vis.showOnMouseover and UnitframesVisibility.mouseOver then return true end

    return false
end

-- OnUpdate handler for Unitframes fade animation
local function OnUnitframesFadeUpdate(self, elapsed)
    local vis = GetUnitframesVisibilitySettings()
    local duration = (vis and vis.fadeDuration) or 0.2
    if duration <= 0 then duration = 0.01 end

    local now = GetTime()
    local elapsedTime = now - UnitframesVisibility.fadeStart
    local progress = math.min(elapsedTime / duration, 1)

    local alpha = UnitframesVisibility.fadeStartAlpha +
        (UnitframesVisibility.fadeTargetAlpha - UnitframesVisibility.fadeStartAlpha) * progress

    local frames = GetUnitframeFrames()
    for _, frame in ipairs(frames) do
        ApplyUnitframeVisibilityAlpha(frame, alpha)
    end

    if progress >= 1 then
        UnitframesVisibility.isFading = false
        UnitframesVisibility.currentlyHidden = (UnitframesVisibility.fadeTargetAlpha < 1)
        self:SetScript("OnUpdate", nil)
    end
end

-- Start Unitframes fade animation
local function StartUnitframesFade(targetAlpha)
    local frames = GetUnitframeFrames()
    if #frames == 0 then return end

    local currentAlpha = frames[1]:GetAlpha()

    if math.abs(currentAlpha - targetAlpha) < 0.01 then
        UnitframesVisibility.currentlyHidden = (targetAlpha < 1)
        return
    end

    UnitframesVisibility.isFading = true
    UnitframesVisibility.fadeStart = GetTime()
    UnitframesVisibility.fadeStartAlpha = currentAlpha
    UnitframesVisibility.fadeTargetAlpha = targetAlpha

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

    -- Sync castbar alpha based on "Always Show Castbars" setting
    if _G.QUI_Castbars then
        local targetAlpha = 1

        if vis and vis.alwaysShowCastbars then
            targetAlpha = 1
        else
            if _G.QUI_UnitFrames then
                for _, frame in pairs(_G.QUI_UnitFrames) do
                    if frame then
                        targetAlpha = frame:GetAlpha()
                        break
                    end
                end
            end
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
    if ns.QUI_ActionBars and ns.QUI_ActionBars.containers then
        for _, container in pairs(ns.QUI_ActionBars.containers) do
            if container then
                frames[#frames + 1] = container
            end
        end
    end
    return frames
end

local function ShouldActionBarsBeVisible()
    local vis = GetActionBarsVisibilitySettings()
    if not vis then return true end

    local ignoreHideRules = vis.dontHideInDungeonsRaids and Helpers.IsPlayerInDungeonOrRaid and Helpers.IsPlayerInDungeonOrRaid()
    if not ignoreHideRules then
        if vis.hideWhenMounted and Helpers.IsPlayerMounted() then return false end
        if vis.hideWhenInVehicle and Helpers.IsPlayerInVehicle and Helpers.IsPlayerInVehicle() then return false end
        if vis.hideWhenFlying and Helpers.IsPlayerFlying() then return false end
        if vis.hideWhenSkyriding and Helpers.IsPlayerSkyriding() then return false end
    end

    if vis.showAlways then return true end

    if vis.showWhenTargetExists and UnitExists("target") then return true end
    if vis.showInCombat and UnitAffectingCombat("player") then return true end
    if vis.showInGroup and IsPlayerInGroup() then return true end
    if vis.showInInstance and IsPlayerInInstance() then return true end
    if vis.showOnMouseover and ActionBarsVisibility.mouseOver then return true end

    return false
end

local function OnActionBarsFadeUpdate(self, elapsed)
    local vis = GetActionBarsVisibilitySettings()
    local duration = (vis and vis.fadeDuration) or 0.2
    if duration <= 0 then duration = 0.01 end

    local now = GetTime()
    local elapsedTime = now - ActionBarsVisibility.fadeStart
    local progress = math.min(elapsedTime / duration, 1)

    local alpha = ActionBarsVisibility.fadeStartAlpha +
        (ActionBarsVisibility.fadeTargetAlpha - ActionBarsVisibility.fadeStartAlpha) * progress

    local frames = GetActionBarFrames()
    for _, frame in ipairs(frames) do
        if frame and frame.SetAlpha then
            pcall(frame.SetAlpha, frame, alpha)
        end
    end

    if progress >= 1 then
        ActionBarsVisibility.isFading = false
        ActionBarsVisibility.currentlyHidden = (ActionBarsVisibility.fadeTargetAlpha < 1)
        self:SetScript("OnUpdate", nil)
    end
end

local function StartActionBarsFade(targetAlpha)
    local frames = GetActionBarFrames()
    if #frames == 0 then return end

    local currentAlpha = frames[1]:GetAlpha()

    if math.abs(currentAlpha - targetAlpha) < 0.01 then
        ActionBarsVisibility.currentlyHidden = (targetAlpha < 1)
        return
    end

    ActionBarsVisibility.isFading = true
    ActionBarsVisibility.fadeStart = GetTime()
    ActionBarsVisibility.fadeStartAlpha = currentAlpha
    ActionBarsVisibility.fadeTargetAlpha = targetAlpha

    if not ActionBarsVisibility.fadeFrame then
        ActionBarsVisibility.fadeFrame = CreateFrame("Frame")
    end
    ActionBarsVisibility.fadeFrame:SetScript("OnUpdate", OnActionBarsFadeUpdate)
end

local function UpdateActionBarsVisibility()
    if Helpers.IsEditModeActive() or Helpers.IsLayoutModeActive() then
        StartActionBarsFade(1)
        return
    end

    local shouldShow = ShouldActionBarsBeVisible()
    local vis = GetActionBarsVisibilitySettings()

    if shouldShow then
        StartActionBarsFade(1)
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

    for _, frame in ipairs(abFrames) do
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
                    ActionBarsVisibility.leaveTimer = C_Timer.NewTimer(0.5, function()
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

    local detector = CreateFrame("Frame", nil, UIParent)
    detector:EnableMouse(false)
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

    local ignoreHideRules = vis.dontHideInDungeonsRaids and Helpers.IsPlayerInDungeonOrRaid and Helpers.IsPlayerInDungeonOrRaid()
    if not ignoreHideRules then
        if vis.hideWhenMounted and Helpers.IsPlayerMounted() then return false end
        if vis.hideWhenInVehicle and Helpers.IsPlayerInVehicle and Helpers.IsPlayerInVehicle() then return false end
        if vis.hideWhenFlying and Helpers.IsPlayerFlying() then return false end
        if vis.hideWhenSkyriding and Helpers.IsPlayerSkyriding() then return false end
    end

    if vis.showAlways then return true end

    if vis.showWhenTargetExists and UnitExists("target") then return true end
    if vis.showInCombat and UnitAffectingCombat("player") then return true end
    if vis.showInGroup and IsPlayerInGroup() then return true end
    if vis.showInInstance and IsPlayerInInstance() then return true end
    if vis.showOnMouseover and ChatVisibility.mouseOver then return true end

    return false
end

local function OnChatFadeUpdate(self, elapsed)
    local vis = GetChatVisibilitySettings()
    local duration = (vis and vis.fadeDuration) or 0.2
    if duration <= 0 then duration = 0.01 end

    local now = GetTime()
    local elapsedTime = now - ChatVisibility.fadeStart
    local progress = math.min(elapsedTime / duration, 1)

    local alpha = ChatVisibility.fadeStartAlpha +
        (ChatVisibility.fadeTargetAlpha - ChatVisibility.fadeStartAlpha) * progress

    local frames = GetChatFrames()
    for _, frame in ipairs(frames) do
        if frame and frame.SetAlpha then
            pcall(frame.SetAlpha, frame, alpha)
        end
    end

    if progress >= 1 then
        ChatVisibility.isFading = false
        ChatVisibility.currentlyHidden = (ChatVisibility.fadeTargetAlpha < 1)
        self:SetScript("OnUpdate", nil)
    end
end

local function StartChatFade(targetAlpha)
    local frames = GetChatFrames()
    if #frames == 0 then return end

    local currentAlpha = frames[1]:GetAlpha()

    if math.abs(currentAlpha - targetAlpha) < 0.01 then
        ChatVisibility.currentlyHidden = (targetAlpha < 1)
        return
    end

    ChatVisibility.isFading = true
    ChatVisibility.fadeStart = GetTime()
    ChatVisibility.fadeStartAlpha = currentAlpha
    ChatVisibility.fadeTargetAlpha = targetAlpha

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

visibilityEventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_FLAGS_CHANGED" then
        local unit = ...
        if unit ~= "player" then return end
    end
    if event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" then
        local unit = ...
        if unit ~= "player" then return end
    end

    -- Health events — update health state before visibility check
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        UpdateHealthState()
    end

    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName ~= ADDON_NAME then return end
        self:UnregisterEvent("ADDON_LOADED")
    end

    if event == "ADDON_LOADED" or event == "PLAYER_ENTERING_WORLD" then
        UpdateHealthState()
        -- Schedule delayed setup so CDM/UF frames have time to render.
        -- Also runs on PLAYER_ENTERING_WORLD to cover zone transitions.
        if _pendingSetupTimer then
            _pendingSetupTimer:Cancel()
        end
        _pendingSetupTimer = C_Timer.NewTimer(2.0, function()
            _pendingSetupTimer = nil
            UpdateHealthState()  -- Player healthBar should exist by now
            SetupCDMMouseoverDetector()
            SetupUnitframesMouseoverDetector()
            SetupActionBarsMouseoverDetector()
            SetupChatMouseoverDetector()
            UpdateCDMVisibility()
            UpdateUnitframesVisibility()
            UpdateActionBarsVisibility()
            UpdateChatVisibility()
        end)
    end

    -- Always try an immediate update too (works for events where frames
    -- already exist, e.g. target changes, combat, zone transitions).
    UpdateCDMVisibility()
    UpdateUnitframesVisibility()
    UpdateActionBarsVisibility()
    UpdateChatVisibility()
end)

---------------------------------------------------------------------------
-- GLOBAL EXPORTS
---------------------------------------------------------------------------
_G.QUI_RefreshCDMVisibility = function()
    _visSettingsCache = nil
    _cdmFramesDirty = true
    UpdateCDMVisibility()
end
_G.QUI_RefreshUnitframesVisibility = UpdateUnitframesVisibility
_G.QUI_RefreshCDMMouseover = SetupCDMMouseoverDetector
_G.QUI_RefreshUnitframesMouseover = SetupUnitframesMouseoverDetector
_G.QUI_ShouldCDMBeVisible = ShouldCDMBeVisible
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
end

---------------------------------------------------------------------------
-- NAMESPACE EXPORTS
---------------------------------------------------------------------------
-- Expose HookFrameForMouseover so CDM engines can hook new icons during skinning
ns.HookFrameForMouseover = HookFrameForMouseover
-- Expose cache invalidation so engines can mark frames dirty after init
ns.InvalidateCDMFrameCache = InvalidateCDMFrameCache

---------------------------------------------------------------------------
-- LAYOUT MODE: force all frames visible on enter, restore on exit
---------------------------------------------------------------------------
local function RefreshAllVisibility()
    UpdateCDMVisibility()
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
