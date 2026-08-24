local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local QUICore = ns.Addon

local UpdateCDMVisibility
local UpdateCustomTrackersVisibility
local UpdateUnitframesVisibility
local UpdateActionBarsVisibility
local UpdateChatVisibility
local HookCustomTrackerFrameForMouseover

local _damagedAlphaCurve

local function GetDamagedAlphaCurve()
    if _damagedAlphaCurve then return _damagedAlphaCurve end
    if not C_CurveUtil or not C_CurveUtil.CreateCurve
       or not Enum or not Enum.LuaCurveType then
        return nil
    end
    local curve = C_CurveUtil.CreateCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    curve:AddPoint(0.0, 1)
    curve:AddPoint(1.0, 0)
    _damagedAlphaCurve = curve
    return curve
end

local function ReadNumber(value, fallback)
    if issecretvalue and issecretvalue(value) then return fallback end
    local valueType = type(value)
    if valueType == "number" then return value end
    if valueType == "string" then return tonumber(value) or fallback end
    return fallback
end

local function IsPlayerInGroup()
    return IsInGroup() or IsInRaid()
end

local HOUSING_INSTANCE_TYPES = {
    ["neighborhood"] = true,
    ["interior"] = true,
}

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

local _cdmFramesCache = {}
local _cdmFramesDirty = true

local function InvalidateCDMFrameCache()
    _cdmFramesDirty = true
end

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

    if ns.CDMProvider and ns.CDMProvider.GetViewerFrames then
        local frames = ns.CDMProvider:GetViewerFrames()
        if frames then
            for i = 1, #frames do
                if not IsCustomCDMBarFrame(frames[i]) then
                    _cdmFramesCache[#_cdmFramesCache + 1] = frames[i]
                end
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

local _viewerAlphaProxy = CreateFrame and CreateFrame("Frame") or nil
local _rawViewerSetAlpha = _viewerAlphaProxy and _viewerAlphaProxy.SetAlpha or nil
local _securecall = securecallfunction or function(fn, ...) return fn(...) end
local REANCHOR_VIEWER_KEYS = { "essential", "utility", "buff", "trackedBar" }

local function ApplyReanchorViewerAlpha(alpha)
    if not _rawViewerSetAlpha then return end
    local boot = ns._cdmBoot
    local wiring = boot and boot.wiring
    if not (wiring and wiring.GetViewerForKey) then return end
    if not IsCDMMasterEnabled() then alpha = 1 end
    for i = 1, #REANCHOR_VIEWER_KEYS do
        local viewer = wiring:GetViewerForKey(REANCHOR_VIEWER_KEYS[i])
        if viewer and (not viewer.IsForbidden or not viewer:IsForbidden()) then
            _securecall(_rawViewerSetAlpha, viewer, alpha)
        end
    end
end

local function ShouldHideForLocationRules(vis, includeVehicle)
    local ignoreHideRules = vis.dontHideInDungeonsRaids and Helpers.IsPlayerInDungeonOrRaid and Helpers.IsPlayerInDungeonOrRaid()
    if ignoreHideRules then return false end
    if vis.hideWhenMounted and not vis.showWhenMounted and Helpers.IsPlayerMounted() then return true end
    if vis.hideWhenFlying and Helpers.IsPlayerFlying() then return true end
    if vis.hideWhenSkyriding and Helpers.IsPlayerSkyriding() then return true end
    if includeVehicle and vis.hideWhenInVehicle and Helpers.IsPlayerInVehicle and Helpers.IsPlayerInVehicle() then return true end
    return false
end

local _mouseoverHooked = Helpers.CreateStateTable()

local function ApplyFrameListAlpha(frames, alpha)
    for i = #frames, 1, -1 do
        local frame = frames[i]
        local ok = false
        if frame then
            ok = ns.SafeCallMethodIfPresent("best-effort-style", frame, "SetAlpha", alpha)
        end
        if not ok then
            table.remove(frames, i)
        end
    end
end

local function GetFrameAlpha(frame)
    return frame:GetAlpha()
end

local VisibilityController = {}
VisibilityController.__index = VisibilityController

local function CreateVisibilityController(config)
    config.currentlyHidden = false
    config.isFading = false
    config.fadeStart = 0
    config.fadeStartAlpha = 1
    config.fadeTargetAlpha = 1
    config.mouseOver = false
    config.hoverCount = 0
    config.leaveDelay = config.leaveDelay or 0.5
    config.getAlpha = config.getAlpha or GetFrameAlpha
    config.applyAlpha = config.applyAlpha or ApplyFrameListAlpha

    local controller = setmetatable(config, VisibilityController)
    controller.fadeTick = function(frame) controller:Tick(frame) end
    return controller
end

function VisibilityController:ShouldBeVisible()
    if self.masterGate and not self.masterGate() then return false end

    local vis = self.getSettings()
    if not vis then return true end

    if self.forceVisible and self.forceVisible() then return true end

    if vis.showAlways then
        if ShouldHideForLocationRules(vis, self.includeVehicle) then return false end
        return true
    end

    if vis.showWhenTargetExists and UnitExists("target") then return true end
    if vis.showInCombat and UnitAffectingCombat("player") then return true end
    if vis.showInGroup and IsPlayerInGroup() then return true end
    if vis.showInInstance and IsPlayerInInstance() then return true end
    if vis.showOnMouseover and self.mouseOver then return true end
    if vis.showWhenMounted and Helpers.IsPlayerMounted() then return true end

    if ShouldHideForLocationRules(vis, self.includeVehicle) then return false end

    return false
end

function VisibilityController:StopFade()
    self.isFading = false
    self.fadeTargets = nil
    if self.fadeFrame then
        self.fadeFrame:SetScript("OnUpdate", nil)
    end
end

function VisibilityController:Tick(frame)
    local targetAlpha = ReadNumber(self.fadeTargetAlpha, 1)

    if self.suppressed and self.suppressed() then
        self.isFading = false
        self.currentlyHidden = (targetAlpha < 1)
        self.fadeTargets = nil
        frame:SetScript("OnUpdate", nil)
        return
    end

    if targetAlpha < 1 and self.forceVisible and self.forceVisible() then
        self.applyAlpha(self.fadeTargets or self.getFrames(), 1)
        self.isFading = false
        self.currentlyHidden = false
        self.fadeTargetAlpha = 1
        self.fadeTargets = nil
        frame:SetScript("OnUpdate", nil)
        return
    end

    local vis = self.getSettings()
    local duration = (vis and vis.fadeDuration) or 0.2
    if duration <= 0 then duration = 0.01 end

    local progress = math.min((GetTime() - self.fadeStart) / duration, 1)
    local startAlpha = ReadNumber(self.fadeStartAlpha, targetAlpha)
    local alpha = startAlpha + (targetAlpha - startAlpha) * progress

    self.applyAlpha(self.fadeTargets or self.getFrames(), alpha)
    if self.onAlpha then self.onAlpha(alpha) end

    if progress >= 1 then
        self.isFading = false
        self.currentlyHidden = (targetAlpha < 1)
        self.fadeTargets = nil
        frame:SetScript("OnUpdate", nil)
    end
end

function VisibilityController:StartFade(targetAlpha, framesOverride)
    if self.suppressed and self.suppressed() then return end

    local frames = framesOverride or self.getFrames()
    if #frames == 0 then return end

    local forceInstant = (self.forceVisible and self.forceVisible()) and true or false
    if forceInstant and targetAlpha < 1 then
        targetAlpha = 1
    end

    local currentAlpha = ReadNumber(self.getAlpha(frames[1]), targetAlpha)

    if forceInstant or math.abs(currentAlpha - targetAlpha) < 0.01 then
        if self.instantApply then
            self.applyAlpha(frames, targetAlpha)
            self:StopFade()
        end
        self.currentlyHidden = (targetAlpha < 1)
        self.fadeStartAlpha = targetAlpha
        self.fadeTargetAlpha = targetAlpha
        if self.onAlpha then self.onAlpha(targetAlpha) end
        return
    end

    self.isFading = true
    self.fadeStart = GetTime()
    self.fadeStartAlpha = currentAlpha
    self.fadeTargetAlpha = targetAlpha

    local targets = {}
    for i = 1, #frames do
        targets[i] = frames[i]
    end
    self.fadeTargets = targets

    if not self.fadeFrame then
        self.fadeFrame = CreateFrame("Frame")
    end
    self.fadeFrame:SetScript("OnUpdate", self.fadeTick)
end

function VisibilityController:Snap()
    local target = ReadNumber(self.fadeTargetAlpha, 1)
    self.applyAlpha(self.fadeTargets or self.getFrames(), target)
    if self.onAlpha then self.onAlpha(target) end
    self.isFading = false
    self.currentlyHidden = (target < 1)
    self.fadeTargets = nil
    if self.fadeFrame then
        self.fadeFrame:SetScript("OnUpdate", nil)
    end
end

function VisibilityController:MouseoverEnabled()
    local vis = self.getSettings()
    return (vis and not vis.showAlways and vis.showOnMouseover) and true or false
end

function VisibilityController:HookFrame(frame)
    if not frame or _mouseoverHooked[frame] then return end
    _mouseoverHooked[frame] = true

    frame:HookScript("OnEnter", function()
        if self.guardHooks and not self:MouseoverEnabled() then return end

        if self.leaveTimer then
            self.leaveTimer:Cancel()
            self.leaveTimer = nil
        end

        self.hoverCount = self.hoverCount + 1
        if self.hoverCount == 1 then
            self.mouseOver = true
            self.update()
        end
    end)

    frame:HookScript("OnLeave", function()
        if self.guardHooks and not self:MouseoverEnabled() then return end

        self.hoverCount = math.max(0, self.hoverCount - 1)
        if self.hoverCount == 0 then
            if self.leaveTimer then
                self.leaveTimer:Cancel()
            end

            self.leaveTimer = C_Timer.NewTimer(self.leaveDelay, function()
                self.leaveTimer = nil
                if self.hoverCount == 0 then
                    self.mouseOver = false
                    self.update()
                end
            end)
        end
    end)
end

function VisibilityController:ResetMouseover()
    if self.mouseoverDetector then
        self.mouseoverDetector:SetScript("OnUpdate", nil)
        self.mouseoverDetector:Hide()
    end

    if self.leaveTimer then
        self.leaveTimer:Cancel()
        self.leaveTimer = nil
    end

    self.mouseOver = false
    self.hoverCount = 0
end

function VisibilityController:EnsureDetector()
    local detector = self.mouseoverDetector or CreateFrame("Frame", nil, UIParent)
    detector:EnableMouse(false)
    detector:Show()
    self.mouseoverDetector = detector
    return detector
end

local function IsAddonOwnedCDMMouseoverFrame(frame)
    return frame
        and (frame._isQUICDMIcon or frame._quiCdmKey or frame._quiCDMMouseoverTarget)
end

local CDMVisibility = CreateVisibilityController({
    getSettings = GetCDMVisibilitySettings,
    getFrames = GetCDMFrames,
    masterGate = IsCDMMasterEnabled,
    includeVehicle = true,
    guardHooks = true,
    onAlpha = function(alpha) ApplyReanchorViewerAlpha(alpha) end,
    update = function() UpdateCDMVisibility() end,
})

local function SnapCDMFadeToTarget()
    CDMVisibility:Snap()
end

UpdateCDMVisibility = function()
    if not IsCDMMasterEnabled() then
        CDMVisibility:StartFade(0)
        return
    end

    if Helpers.IsEditModeActive() or Helpers.IsLayoutModeActive() then
        CDMVisibility:StartFade(1)
        return
    end

    local shouldShow = CDMVisibility:ShouldBeVisible()
    local vis = GetCDMVisibilitySettings()

    local hpCurve = ((not shouldShow) and vis and vis.showWhenHealthBelow100
        and UnitHealthPercent) and GetDamagedAlphaCurve() or nil
    if hpCurve then
        local damagedAlpha = UnitHealthPercent("player", true, hpCurve)
        CDMVisibility:StopFade()
        local frames = GetCDMFrames()
        for i = #frames, 1, -1 do
            local frame = frames[i]
            if frame then
                ns.SafeCallMethodIfPresent("sink-forward", frame, "SetAlpha", damagedAlpha)
            end
        end
        ApplyReanchorViewerAlpha(damagedAlpha)
        if QUICore then
            if QUICore.UpdatePowerBar then QUICore:UpdatePowerBar() end
            if QUICore.UpdateSecondaryPowerBar then QUICore:UpdateSecondaryPowerBar() end
        end
        return
    end

    if shouldShow then
        CDMVisibility:StartFade(1)
    else
        CDMVisibility:StartFade(vis and vis.fadeOutAlpha or 0)
    end

    if QUICore then
        if QUICore.UpdatePowerBar then
            QUICore:UpdatePowerBar()
        end
        if QUICore.UpdateSecondaryPowerBar then
            QUICore:UpdateSecondaryPowerBar()
        end
    end
end

local function GetCustomTrackersVisibilitySettings()
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.customTrackersVisibility then
        return QUICore.db.profile.customTrackersVisibility
    end
    return nil
end

local CustomTrackersVisibility = CreateVisibilityController({
    getSettings = GetCustomTrackersVisibilitySettings,
    getFrames = GetCustomTrackerFrames,
    masterGate = IsCDMMasterEnabled,
    includeVehicle = true,
    guardHooks = true,
    update = function() UpdateCustomTrackersVisibility() end,
})

UpdateCustomTrackersVisibility = function()
    if not IsCDMMasterEnabled() then
        CustomTrackersVisibility:StartFade(0)
        return
    end

    if Helpers.IsEditModeActive() or Helpers.IsLayoutModeActive() then
        CustomTrackersVisibility:StartFade(1)
        return
    end

    local vis = GetCustomTrackersVisibilitySettings()
    if CustomTrackersVisibility:ShouldBeVisible() then
        CustomTrackersVisibility:StartFade(1)
    else
        CustomTrackersVisibility:StartFade(vis and vis.fadeOutAlpha or 0)
    end
end

local function HookFrameForMouseover(frame)
    if not IsAddonOwnedCDMMouseoverFrame(frame) or _mouseoverHooked[frame] then return end
    if IsCustomCDMBarFrame(frame) then
        if HookCustomTrackerFrameForMouseover then
            HookCustomTrackerFrameForMouseover(frame)
        end
        return
    end

    CDMVisibility:HookFrame(frame)
end

HookCustomTrackerFrameForMouseover = function(frame)
    if not IsAddonOwnedCDMMouseoverFrame(frame) or _mouseoverHooked[frame] then return end
    if not IsCustomCDMBarFrame(frame) then return end

    CustomTrackersVisibility:HookFrame(frame)
end

local function SetupCDMMouseoverDetector()
    CDMVisibility:ResetMouseover()
    if not CDMVisibility:MouseoverEnabled() then return end

    local cdmFrames = GetCDMFrames()
    for _, frame in ipairs(cdmFrames) do
        HookFrameForMouseover(frame)
    end

    local viewers
    if ns.CDMProvider and ns.CDMProvider.GetViewerFrames then
        viewers = ns.CDMProvider:GetViewerFrames()
    else
        viewers = {}
    end

    for _, viewer in ipairs(viewers) do
        if viewer and viewer.GetChildren then
            local children = { viewer:GetChildren() }
            for i = 1, #children do
                local child = children[i]
                if child and IsAddonOwnedCDMMouseoverFrame(child) then
                    HookFrameForMouseover(child)
                end
            end
        end
    end

    CDMVisibility:EnsureDetector()
end

local function SetupCustomTrackersMouseoverDetector()
    CustomTrackersVisibility:ResetMouseover()
    if not CustomTrackersVisibility:MouseoverEnabled() then return end

    local frames = GetCustomTrackerFrames()
    for _, frame in ipairs(frames) do
        HookCustomTrackerFrameForMouseover(frame)
        if frame and frame.GetChildren then
            local children = { frame:GetChildren() }
            for i = 1, #children do
                local child = children[i]
                if child and IsAddonOwnedCDMMouseoverFrame(child) then
                    HookCustomTrackerFrameForMouseover(child)
                end
            end
        end
    end

    CustomTrackersVisibility:EnsureDetector()
end

local function IsUnitframesCombatLocked()
    if InCombatLockdown and InCombatLockdown() then return true end
    return UnitAffectingCombat and UnitAffectingCombat("player")
end

local function GetUnitframesVisibilitySettings()
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.unitframesVisibility then
        return QUICore.db.profile.unitframesVisibility
    end
    return nil
end

local function GetUnitframeFrames()
    local frames = {}

    if _G.QUI_UnitFrames then
        for _, frame in pairs(_G.QUI_UnitFrames) do
            if frame then
                table.insert(frames, frame)
            end
        end
    end

    local vis = GetUnitframesVisibilitySettings()
    if not (vis and vis.alwaysShowCastbars) then
        if _G.QUI_Castbars then
            for _, castbar in pairs(_G.QUI_Castbars) do
                if castbar then
                    table.insert(frames, castbar)
                end
            end
        end
    end

    return frames
end

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
        return
    end

    frame:SetAlpha(alpha)
end

local function ApplyUnitframeListAlpha(frames, alpha)
    for _, frame in ipairs(frames) do
        ApplyUnitframeVisibilityAlpha(frame, alpha)
    end
end

local UnitframesVisibility = CreateVisibilityController({
    getSettings = GetUnitframesVisibilitySettings,
    getFrames = GetUnitframeFrames,
    applyAlpha = ApplyUnitframeListAlpha,
    forceVisible = IsUnitframesCombatLocked,
    includeVehicle = false,
    instantApply = true,
    update = function() UpdateUnitframesVisibility() end,
})

UpdateUnitframesVisibility = function()
    if (_G.QUI_IsUnitFrameEditModeActive and _G.QUI_IsUnitFrameEditModeActive())
        or Helpers.IsLayoutModeActive() then
        UnitframesVisibility:StartFade(1)
        return
    end

    local vis = GetUnitframesVisibilitySettings()
    local shouldShow = UnitframesVisibility:ShouldBeVisible()

    local hpCurve = ((not shouldShow) and vis and vis.showWhenHealthBelow100
        and UnitHealthPercent) and GetDamagedAlphaCurve() or nil
    if hpCurve then
        local damagedAlpha = UnitHealthPercent("player", true, hpCurve)
        ApplyUnitframeListAlpha(GetPlayerUnitframes(), damagedAlpha)

        local fadeAlpha = vis and vis.fadeOutAlpha or 0
        local nonPlayerFrames = GetUnitframeFramesExcludingPlayer()
        if #nonPlayerFrames > 0 then
            UnitframesVisibility:StartFade(fadeAlpha, nonPlayerFrames)
        else
            UnitframesVisibility:StopFade()
        end
        return
    end

    if _G.QUI_Castbars then
        local targetAlpha = 1

        if vis and vis.alwaysShowCastbars then
            targetAlpha = 1
        else
            targetAlpha = shouldShow and 1 or (vis and vis.fadeOutAlpha or 0)
        end

        for _, castbar in pairs(_G.QUI_Castbars) do
            if castbar then
                ApplyUnitframeVisibilityAlpha(castbar, targetAlpha)
            end
        end
    end

    if shouldShow then
        UnitframesVisibility:StartFade(1)
    else
        UnitframesVisibility:StartFade(vis and vis.fadeOutAlpha or 0)
    end
end

local function SetupUnitframesMouseoverDetector()
    UnitframesVisibility:ResetMouseover()
    if not UnitframesVisibility:MouseoverEnabled() then return end

    local ufFrames = GetUnitframeFrames()
    for _, frame in ipairs(ufFrames) do
        UnitframesVisibility:HookFrame(frame)
    end

    UnitframesVisibility:EnsureDetector()
end

local function GetActionBarsVisibilitySettings()
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.actionBarsVisibility then
        return QUICore.db.profile.actionBarsVisibility
    end
    return nil
end

local function GetActionBarFrames()
    local frames = {}
    if ns.ActionBarsOwned and ns.ActionBarsOwned.containers then
        for barKey, container in pairs(ns.ActionBarsOwned.containers) do
            if container then
                frames[#frames + 1] = { barKey = barKey, container = container }
            end
        end
    end
    return frames
end

local function ApplyActionBarListAlpha(frames, alpha)
    local setBarAlpha = ns.ActionBarsOwned and ns.ActionBarsOwned.SetBarAlpha
    for _, entry in ipairs(frames) do
        if setBarAlpha then
            ns.SafeCall("best-effort-style", setBarAlpha, entry.barKey, alpha)
        elseif entry.container then
            ns.SafeCallMethodIfPresent("best-effort-style", entry.container, "SetAlpha", alpha)
        end
    end
end

local function GetActionBarEntryAlpha(entry)
    return entry.container:GetAlpha()
end

local ActionBarsVisibility = CreateVisibilityController({
    getSettings = GetActionBarsVisibilitySettings,
    getFrames = GetActionBarFrames,
    applyAlpha = ApplyActionBarListAlpha,
    getAlpha = GetActionBarEntryAlpha,
    includeVehicle = true,
    leaveDelay = 0.3,
    update = function() UpdateActionBarsVisibility() end,
})

ns.ShouldHideActionBarsForVisibility = function()
    if Helpers.IsEditModeActive() or Helpers.IsLayoutModeActive() then
        return false
    end
    return not ActionBarsVisibility:ShouldBeVisible()
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

UpdateActionBarsVisibility = function()
    if Helpers.IsEditModeActive() or Helpers.IsLayoutModeActive() then
        ActionBarsVisibility:StartFade(1)
        return
    end

    local shouldShow = ActionBarsVisibility:ShouldBeVisible()
    local vis = GetActionBarsVisibilitySettings()

    if shouldShow then
        if IsActionBarMouseoverFadeEnabled() then
            ActionBarsVisibility:StopFade()
            ActionBarsVisibility.currentlyHidden = false
            if type(_G.QUI_RefreshActionBarFade) == "function" then
                _G.QUI_RefreshActionBarFade()
            end
        else
            ActionBarsVisibility:StartFade(1)
        end
    else
        ActionBarsVisibility:StartFade(vis and vis.fadeOutAlpha or 0)
    end
end

local function SetupActionBarsMouseoverDetector()
    ActionBarsVisibility:ResetMouseover()
    if not ActionBarsVisibility:MouseoverEnabled() then return end

    local abFrames = GetActionBarFrames()
    for _, entry in ipairs(abFrames) do
        ActionBarsVisibility:HookFrame(entry.container)
    end

    local detector = ActionBarsVisibility:EnsureDetector()
    local pollInterval = 0
    detector:SetScript("OnUpdate", function(_, elapsed)
        pollInterval = pollInterval + elapsed
        if pollInterval < 0.1 then return end
        pollInterval = 0

        if ActionBarsVisibility.mouseOver then return end
        if not ActionBarsVisibility.currentlyHidden
            and not (ActionBarsVisibility.isFading and ActionBarsVisibility.fadeTargetAlpha < 1) then
            return
        end

        local containers = ns.ActionBarsOwned and ns.ActionBarsOwned.containers
        if not containers then return end
        for _, container in pairs(containers) do
            local alpha = container and container.GetAlpha and ReadNumber(container:GetAlpha(), 1) or 1
            if container and alpha < 0.99 and container:IsMouseOver() then
                if ActionBarsVisibility.leaveTimer then
                    ActionBarsVisibility.leaveTimer:Cancel()
                    ActionBarsVisibility.leaveTimer = nil
                end
                ActionBarsVisibility.hoverCount = 1
                ActionBarsVisibility.mouseOver = true
                UpdateActionBarsVisibility()
                return
            end
        end
    end)
end

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
            frames[#frames + 1] = chatFrame
        end
    end
    if _G.GeneralDockManager then
        frames[#frames + 1] = _G.GeneralDockManager
    end
    return frames
end

local function IsChatSuppressed()
    local Suppress = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.BlizzardSuppress
    return (Suppress and Suppress.IsActive and Suppress.IsActive()) and true or false
end

local ChatVisibility = CreateVisibilityController({
    getSettings = GetChatVisibilitySettings,
    getFrames = GetChatFrames,
    suppressed = IsChatSuppressed,
    includeVehicle = true,
    update = function() UpdateChatVisibility() end,
})

UpdateChatVisibility = function()
    if Helpers.IsEditModeActive() or Helpers.IsLayoutModeActive() then
        ChatVisibility:StartFade(1)
        return
    end

    local vis = GetChatVisibilitySettings()
    if ChatVisibility:ShouldBeVisible() then
        ChatVisibility:StartFade(1)
    else
        ChatVisibility:StartFade(vis and vis.fadeOutAlpha or 0)
    end
end

local function SetupChatMouseoverDetector()
    ChatVisibility:ResetMouseover()
    if not ChatVisibility:MouseoverEnabled() then return end

    local chatFrames = GetChatFrames()
    for _, frame in ipairs(chatFrames) do
        ChatVisibility:HookFrame(frame)
    end

    ChatVisibility:EnsureDetector()
end

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
visibilityEventFrame:RegisterEvent("PLAYER_STARTED_MOVING")
visibilityEventFrame:RegisterEvent("PLAYER_STOPPED_MOVING")
visibilityEventFrame:RegisterEvent("PLAYER_IMPULSE_APPLIED")
visibilityEventFrame:RegisterEvent("UNIT_ENTERED_VEHICLE")
visibilityEventFrame:RegisterEvent("UNIT_EXITED_VEHICLE")
visibilityEventFrame:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR")
visibilityEventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
visibilityEventFrame:RegisterEvent("PLAYER_FLAGS_CHANGED")
visibilityEventFrame:RegisterEvent("PLAYER_IS_GLIDING_CHANGED")
visibilityEventFrame:RegisterUnitEvent("UNIT_HEALTH", "player")
visibilityEventFrame:RegisterUnitEvent("UNIT_MAXHEALTH", "player")

local _pendingSetupTimer = nil

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

    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        local cdmVis = GetCDMVisibilitySettings()
        if cdmVis and cdmVis.showWhenHealthBelow100 then
            UpdateCDMVisibility()
        end
        local ufVis = GetUnitframesVisibilitySettings()
        if ufVis and ufVis.showWhenHealthBelow100 then
            if UpdateUnitframesVisibility then UpdateUnitframesVisibility() end
        end
        return
    end

    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName ~= ADDON_NAME then return end
        self:UnregisterEvent("ADDON_LOADED")
    end

    if event == "ADDON_LOADED" or event == "PLAYER_ENTERING_WORLD" then
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
            UpdateCDMVisibility()
            UpdateCustomTrackersVisibility()
        end)
    end

    visCoalesceFrame:Show()
end)

_G.QUI_RefreshCDMVisibility = function()
    _cdmFramesDirty = true
    UpdateCDMVisibility()
end
ns.RefreshCDMVisibilityInstant = function()
    _cdmFramesDirty = true
    UpdateCDMVisibility()
    SnapCDMFadeToTarget()
end
_G.QUI_RefreshCustomTrackersVisibility = UpdateCustomTrackersVisibility
_G.QUI_RefreshUnitframesVisibility = UpdateUnitframesVisibility
_G.QUI_RefreshCDMMouseover = SetupCDMMouseoverDetector
_G.QUI_RefreshCustomTrackersMouseover = SetupCustomTrackersMouseoverDetector
_G.QUI_RefreshUnitframesMouseover = SetupUnitframesMouseoverDetector
_G.QUI_ShouldCDMBeVisible = function() return CDMVisibility:ShouldBeVisible() end
_G.QUI_ShouldCustomTrackersBeVisible = function() return CustomTrackersVisibility:ShouldBeVisible() end
_G.QUI_ShouldUnitframesBeVisible = function() return UnitframesVisibility:ShouldBeVisible() end
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

ns.HookFrameForMouseover = function(frame)
    HookFrameForMouseover(frame)
    if HookCustomTrackerFrameForMouseover then
        HookCustomTrackerFrameForMouseover(frame)
    end
end
ns.InvalidateCDMFrameCache = InvalidateCDMFrameCache
ns.GetCDMFrameCacheStats = function()
    return {
        dirty = _cdmFramesDirty and true or false,
        size  = #_cdmFramesCache,
    }
end

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
