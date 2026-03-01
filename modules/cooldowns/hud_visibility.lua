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
    if Helpers.IsEditModeActive() then
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
    if _G.QUI_IsUnitFrameEditModeActive and _G.QUI_IsUnitFrameEditModeActive() then
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
-- SHARED EVENT HANDLING
---------------------------------------------------------------------------
local visibilityEventFrame = CreateFrame("Frame")
visibilityEventFrame:RegisterEvent("PLAYER_LOGIN")
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

    if event == "PLAYER_LOGIN" then
        C_Timer.After(1.5, function()
            SetupCDMMouseoverDetector()
            SetupUnitframesMouseoverDetector()
            UpdateCDMVisibility()
            UpdateUnitframesVisibility()
        end)
    else
        UpdateCDMVisibility()
        UpdateUnitframesVisibility()
    end
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

---------------------------------------------------------------------------
-- NAMESPACE EXPORTS
---------------------------------------------------------------------------
-- Expose HookFrameForMouseover so CDM engines can hook new icons during skinning
ns.HookFrameForMouseover = HookFrameForMouseover
-- Expose cache invalidation so engines can mark frames dirty after init
ns.InvalidateCDMFrameCache = InvalidateCDMFrameCache
