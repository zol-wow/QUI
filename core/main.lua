local ADDON_NAME, ns = ...
local QUI = QUI

local type = type
local pairs = pairs
local ipairs = ipairs
local pcall = pcall
local tostring = tostring
local tonumber = tonumber
local select = select
local wipe = wipe
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local hooksecurefunc = hooksecurefunc

local function RunAfterFirstFrame(callback, delay)
    if ns and ns.RunAfterFirstFrame then
        return ns.RunAfterFirstFrame(callback, delay)
    end
    if C_Timer and C_Timer.After then
        return C_Timer.After(delay or 0, callback)
    end
    if type(callback) == "function" then
        return callback()
    end
    return nil
end

local QUICore = QUI:NewModule("QUICore", "AceConsole-3.0", "AceEvent-3.0")
QUI.QUICore = QUICore

ns.Addon = QUICore

QUICore.__pendingReload = false
QUICore.__reloadEventFrame = nil

local function EnsureReloadEventFrame(self)
    if self.__reloadEventFrame then
        return self.__reloadEventFrame
    end

    self.__reloadEventFrame = CreateFrame("Frame")
    self.__reloadEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.__reloadEventFrame:SetScript("OnEvent", function(frame, event)
        if event == "PLAYER_REGEN_ENABLED" and QUICore.__pendingReload then
            QUICore.__pendingReload = false
            QUICore:ShowReloadPopup()
        end
    end)

    return self.__reloadEventFrame
end

function QUICore:SafeReload()
    if InCombatLockdown() and not (QUI.db and QUI.db.profile and QUI.db.profile.general and QUI.db.profile.general.allowReloadInCombat) then
        if not self.__pendingReload then
            self.__pendingReload = true
            print("|cFF30D1FFQUI:|r " .. ns.L["Reload queued - will execute when combat ends."])
            EnsureReloadEventFrame(self)
        end
    else
        ReloadUI()
    end
end

function QUICore:ShowReloadPopup()
    if QUI and QUI.GUI and QUI.GUI.ShowConfirmation then
        QUI.GUI:ShowConfirmation({
            title = ns.L["Reload Ready"],
            message = ns.L["Combat ended. Click to reload the UI."],
            acceptText = ns.L["Reload Now"],
            cancelText = ns.L["Later"],
            onAccept = function() ReloadUI() end,
        })
    else
        print("|cFF30D1FFQUI:|r " .. ns.L["Combat ended. Type /reload to reload."])
    end
end

function QUI:SafeReload()
    if self.QUICore then
        self.QUICore:SafeReload()
    else
        if InCombatLockdown() and not (self.db and self.db.profile and self.db.profile.general and self.db.profile.general.allowReloadInCombat) then
            print("|cFF30D1FFQUI:|r " .. ns.L["Cannot reload during combat."])
        else
            ReloadUI()
        end
    end
end

local function ResolveSmartDefaultScale()
    local _, screenHeight = GetPhysicalScreenSize()
    if screenHeight >= 2160 then
        return 0.53
    elseif screenHeight >= 1440 then
        return 0.64
    end
    return 1.0
end

local function RepositionFramesAfterScale()
    local ApplyAnchors = _G.QUI_ApplyAllFrameAnchors
    if ApplyAnchors then ns.SafeCall("bulkhead", ApplyAnchors, true) end
    local RefreshUnitFrames = _G.QUI_RefreshUnitFrames
    if RefreshUnitFrames then ns.SafeCall("bulkhead", RefreshUnitFrames) end
    local RefreshGroupFrames = _G.QUI_RefreshGroupFrames
    if RefreshGroupFrames then ns.SafeCall("bulkhead", RefreshGroupFrames) end
end

local LSM = ns.LSM
local LCG = LibStub("LibCustomGlow-1.0", true)

local LibDualSpec   = LibStub("LibDualSpec-1.0", true)

function QUICore:GetHUDFrameLevel(priority)
    return 100 + (priority or 5) * 20
end

local defaults = ns.defaults

function QUICore:SeedNewProfile(event, db, profileKey)
    if ns.ApplyNewProfileSeed then
        ns.ApplyNewProfileSeed(db.profile)
    end
end

function QUICore:OnInitialize()
    ns._freshInstall = rawget(_G, "QUIDB") == nil

    self.db = LibStub("AceDB-3.0"):New("QUIDB", defaults, true)
    QUI.db = self.db

    self.db.RegisterCallback(self, "OnNewProfile", "SeedNewProfile")

    if ns.Compatibility and ns.Compatibility.RunShippedDefaultsMaintenance then
        ns.Compatibility.RunShippedDefaultsMaintenance(self.db)
    end

    if ns.Migrations and ns.Migrations.Run then
        ns.Migrations.Run(self.db)
    end

    ns._startupTierPassDone = true

    if ns.Migrations and ns.Migrations.RunLate then
        self:RegisterEvent("PLAYER_LOGIN", function(event)
            ns.Migrations.RunLate(self.db)
            self:UnregisterEvent("PLAYER_LOGIN")
        end)
    end

    local profile = self.db.profile

    self._preservedUIScale = nil

    self._lastKnownProfile = self.db:GetCurrentProfile()

    self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileCopied",  "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileReset",   "OnProfileChanged")

    if LibDualSpec then
        LibDualSpec:EnhanceDatabase(self.db, ADDON_NAME)
    end

    RunAfterFirstFrame(function()
        self:CreateMinimapButton()
    end, 0.1)

    local GUI = QUI.GUI
    if GUI and GUI.ApplyAccentColor and GUI.ResolveThemePreset then
        local general = profile and profile.general
        local preset = general and general.themePreset
        if preset then
            local r, g, b = GUI:ResolveThemePreset(preset)
            GUI:ApplyAccentColor(r, g, b)
        elseif general and general.addonAccentColor then
            local ac = general.addonAccentColor
            if ac[1] and ac[2] and ac[3] then
                GUI:ApplyAccentColor(ac[1], ac[2], ac[3])
            end
        end
    end

	self._didInitialize = true
	for _, callback in ipairs(self._postInitializeCallbacks or {}) do
		ns.SafeCall("bulkhead", callback, self)
	end

end

local function IsInChallengeModeContext()
    if not C_ChallengeMode then return false end
    if C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() then
        return true
    end
    return (C_ChallengeMode.GetActiveChallengeMapID and C_ChallengeMode.GetActiveChallengeMapID() ~= nil) or false
end

function QUICore:_ParkProfileChangeDuringChallenge(event, profileKey)
    local alreadyParked = self._parkedProfileChange ~= nil
    self._parkedProfileChange = { event = event, profileKey = profileKey }

    if not self._challengeParkWatcher then
        local watcher = CreateFrame("Frame")
        self._challengeParkWatcher = watcher
        watcher:SetScript("OnEvent", function()
            local parked = QUICore._parkedProfileChange
            if not parked then
                watcher:UnregisterAllEvents()
                return
            end
            if IsInChallengeModeContext() or InCombatLockdown() then return end
            QUICore._parkedProfileChange = nil
            watcher:UnregisterAllEvents()
            QUICore:OnProfileChanged(parked.event, QUICore.db, parked.profileKey)
        end)
    end
    local watcher = self._challengeParkWatcher
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    watcher:RegisterEvent("CHALLENGE_MODE_RESET")
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")

    if not alreadyParked then
        print("|cFF34D399QUI:|r Profile change deferred — it will be applied when you leave the Mythic+ dungeon.")
    end
end

function QUICore:OnProfileChanged(event, db, profileKey)

    if IsInChallengeModeContext() then
        self:_ParkProfileChangeDuringChallenge(event, profileKey)
        return
    end

    local currentProfile = self.db:GetCurrentProfile()
    local effectiveProfileKey = profileKey
    local isCopyOrReset = event == "OnProfileCopied" or event == "OnProfileReset"
    if isCopyOrReset then
        effectiveProfileKey = currentProfile
    end
    if type(effectiveProfileKey) ~= "string" or effectiveProfileKey == "" then
        effectiveProfileKey = currentProfile
    end

    if not isCopyOrReset
        and effectiveProfileKey == self._lastKnownProfile and effectiveProfileKey == currentProfile then
        return
    end
    self._lastKnownProfile = effectiveProfileKey

    if ns.CDMResolvers and ns.CDMResolvers._RebuildCatalog then
        ns.CDMResolvers._RebuildCatalog()
    end

    local pins = ns.Settings and ns.Settings.Pins
    if pins and type(pins.HandleProfileEvent) == "function" then
        pins:HandleProfileEvent(event, self.db, effectiveProfileKey)
    end

    local addon = _G.QUI
    if addon and addon.BackwardsCompat then
        addon:BackwardsCompat()
    end

    if ns.Migrations and ns.Migrations.RunLate then
        ns.Migrations.RunLate(self.db)
    end

    if self.CleanupFontRegistry then
        self:CleanupFontRegistry()
    end

    local profileScaleChanged = false
    local function FinalizeProfileScale(scale)
        self.uiscale = scale or UIParent:GetScale()
        self.screenWidth, self.screenHeight = GetScreenWidth(), GetScreenHeight()
        if self.RefreshAllFonts then
            self:RefreshAllFonts()
        end
        if ns.UIKit and ns.UIKit.RefreshScaleBoundWidgets then
            ns.UIKit.RefreshScaleBoundWidgets()
        end
    end
    local function DeferUIScale(scale)
        QUICore._pendingUIScale = scale
        if not QUICore._scaleRegenFrame then
            QUICore._scaleRegenFrame = CreateFrame("Frame")
            QUICore._scaleRegenFrame:SetScript("OnEvent", function(self)
                if QUICore._pendingUIScale and not InCombatLockdown() then
                    local ok = ns.SafeCallMethod("defer-ooc", UIParent, "SetScale", QUICore._pendingUIScale)
                    if ok then
                        FinalizeProfileScale(QUICore._pendingUIScale)
                        QUICore._pendingUIScale = nil
                        self:UnregisterAllEvents()
                    end
                end
            end)
        end
        QUICore._scaleRegenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        QUICore._scaleRegenFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    end
    local function ApplyUIScale(scale)
        if InCombatLockdown() then
            DeferUIScale(scale)
        else
            local ok = ns.SafeCallMethod("defer-ooc", UIParent, "SetScale", scale)
            if not ok then
                DeferUIScale(scale)
            else
                FinalizeProfileScale(scale)
            end
        end
    end

    if self.db.profile.general then
        local newProfileScale = self.db.profile.general.uiScale

        if not newProfileScale or newProfileScale == 0 then
            local scaleToUse = self._preservedUIScale

            if not scaleToUse then
                if self.GetSmartDefaultScale then
                    scaleToUse = self:GetSmartDefaultScale()
                else
                    scaleToUse = ResolveSmartDefaultScale()
                end
            end

            self.db.profile.general.uiScale = scaleToUse
            ApplyUIScale(scaleToUse)
        else
            local currentScale = UIParent:GetScale()
            if currentScale and math.abs(newProfileScale - currentScale) > 0.001 then
                profileScaleChanged = true
            end

            ApplyUIScale(newProfileScale)
            self._preservedUIScale = newProfileScale
        end
    end

    if self._preservedPanelScale then
        self.db.profile.configPanelScale = self._preservedPanelScale
    end
    if self._preservedPanelAlpha then
        self.db.profile.configPanelAlpha = self._preservedPanelAlpha
    end

    if QUI.GUI and QUI.GUI.MainFrame then
        if type(QUI.GUI.TeardownFrameTree) == "function" then
            ns.SafeCallMethod("bulkhead", QUI.GUI, "TeardownFrameTree", QUI.GUI.MainFrame, { includeRoot = true })
        else
            ns.SafeCallMethod("bulkhead", QUI.GUI.MainFrame, "Hide")
            ns.SafeCallMethod("bulkhead", QUI.GUI.MainFrame, "SetParent", nil)
        end
        QUI.GUI.MainFrame = nil
        QUI.GUI.SettingsRegistry = {}
        QUI.GUI.SettingsRegistryKeys = {}
    end

    if self.RefreshAll then
        ns.SafeCallMethod("bulkhead", self, "RefreshAll")
    end

    if QUICore.Minimap then
        C_Timer.After(0.1, function()
            if QUICore.Minimap.Refresh then
                QUICore.Minimap:Refresh()
            end
        end)
    end

    if ns.Migrations and ns.Migrations.ResetCastbarPreviewModes then
        ns.Migrations.ResetCastbarPreviewModes(self.db.profile)
    end

    if _G.QUI_RefreshSpecProfilesTab then
        _G.QUI_RefreshSpecProfilesTab()
    end

    local refreshGroups = { "cooldowns", "frames", "castbars", "qol", "combat", "trackers", "data", "chat", "character", "utility", "ui", "anchoring", "bags" }
    C_Timer.After(0.2, function()
        if ns.Registry then
            for _, group in ipairs(refreshGroups) do
                ns.Registry:RefreshAll(group)
            end
        end
        self:ShowProfileChangeNotification()
    end)

    C_Timer.After(0.5, function()
        if ns.Registry then
            ns.Registry:RefreshAll("skinning")
        end
        if _G.QUI_RefreshStatusTrackingBarSkin then
            _G.QUI_RefreshStatusTrackingBarSkin()
        end
    end)

    C_Timer.After(1.0, function()
        if not InCombatLockdown() then
            RepositionFramesAfterScale()
        end
    end)

    if profileScaleChanged then
        C_Timer.After(1.8, function()
            if InCombatLockdown() then
                return
            end

            if ns.Registry then
                for _, group in ipairs(refreshGroups) do
                    ns.Registry:RefreshAll(group)
                end
            end

            RepositionFramesAfterScale()
        end)
    end

    if ns.AddonLoader then
        ns.AddonLoader:LoadEnabledLODModules()
    end
end

function QUICore:ShowProfileChangeNotification()
    local profileName = self.db and self.db:GetCurrentProfile() or "Unknown"
    print(ns.L["|cff60A5FAQUI:|r Profile switched to |cFFFFD700%s|r. Use |cFFFFD700/editmode|r to adjust frame positions."]:format(profileName))
end

QUICore._editModeEnterCallbacks = {}
QUICore._editModeExitCallbacks = {}
QUICore._postInitializeCallbacks = QUICore._postInitializeCallbacks or {}
QUICore._postEnableCallbacks = QUICore._postEnableCallbacks or {}

function QUICore:RegisterEditModeEnter(callback)
    local um = ns.QUI_LayoutMode
    if um then
        um:RegisterEnterCallback(callback)
    else
        table.insert(self._editModeEnterCallbacks, callback)
    end
end

function QUICore:RegisterEditModeExit(callback)
    local um = ns.QUI_LayoutMode
    if um then
        um:RegisterExitCallback(callback)
    else
        table.insert(self._editModeExitCallbacks, callback)
    end
end

function QUICore:RegisterPostInitialize(callback)
    if type(callback) ~= "function" then
        return
    end
    if self._didInitialize then
        ns.SafeCall("bulkhead", callback, self)
        return
    end
    table.insert(self._postInitializeCallbacks, callback)
end

function QUICore:RegisterLayoutModeEnter(callback)
    return self:RegisterEditModeEnter(callback)
end

function QUICore:RegisterLayoutModeExit(callback)
    return self:RegisterEditModeExit(callback)
end

function QUICore:RegisterPostEnable(callback)
    if type(callback) ~= "function" then
        return
    end
    if self._didEnable then
        ns.SafeCall("bulkhead", callback, self)
        return
    end
    table.insert(self._postEnableCallbacks, callback)
end

function QUICore:OnEnable()
    SlashCmdList["RELOAD"] = function()
        QUI:SafeReload()
    end

    if self.InitializePixelPerfect then
        self:InitializePixelPerfect()
    end

    ns._inInitSafeWindow = true

    if self.ApplyUIScale then
        self:ApplyUIScale()
    elseif self.db.profile.general then
        local savedScale = self.db.profile.general.uiScale
        local scaleToApply
        if savedScale and savedScale > 0 then
            scaleToApply = savedScale
        else
            scaleToApply = ResolveSmartDefaultScale()
            self.db.profile.general.uiScale = scaleToApply
        end
        UIParent:SetScale(scaleToApply)
    end

    self._preservedUIScale = UIParent:GetScale()
    self._preservedPanelScale = self.db.profile.configPanelScale
    self._preservedPanelAlpha = self.db.profile.configPanelAlpha

    local function ApplyFrameOverrides()
        if ns.QUI_Anchoring then
            ns.QUI_Anchoring:ApplyAllFrameAnchors()
        end
    end

    if QUI.BuffBorders and QUI.BuffBorders.Init then
        QUI.BuffBorders.Init()
    end

    if ns.AddonLoader and ns.AddonLoader.LoadEnabledLODModulesEager then
        ns.AddonLoader:LoadEnabledLODModulesEager()
    end

    ApplyFrameOverrides()

    ns._inInitSafeWindow = false

    RunAfterFirstFrame(function()
        self:HookEditMode()
    end, 0.1)

    RunAfterFirstFrame(function()
        if self.Alerts and self.db.profile.general then
            self.Alerts:Initialize()
        end
        if self.ApplyGlobalFont then
            self:ApplyGlobalFont()
        end
        if self.ApplyGlobalDefaultFont then
            self:ApplyGlobalDefaultFont()
        end
        ApplyFrameOverrides()
    end, 0.2)

    RunAfterFirstFrame(function()
        local RefreshUIHider = _G.QUI_RefreshUIHider
        local RefreshBuffBorders = _G.QUI_RefreshBuffBorders
        if RefreshUIHider then
            RefreshUIHider()
        end
        if RefreshBuffBorders then
            RefreshBuffBorders()
        end
        ApplyFrameOverrides()
    end, 0.35)

    RunAfterFirstFrame(function()
        ApplyFrameOverrides()
    end, 0.8)

    RunAfterFirstFrame(function()
        if ns.QUI_Anchoring then
            ns.QUI_Anchoring:RegisterAllFrameTargets()
        end
        ApplyFrameOverrides()
    end, 1.0)

    self:SetupEncounterWarningsSecretValuePatch()
end

function QUICore:OpenConfig()
    if QUI and QUI.OpenOptions then
        QUI:OpenOptions()
    end
end

function QUICore:CreateMinimapButton()
    local LDB = LibStub("LibDataBroker-1.1", true)
    local LibDBIcon = LibStub("LibDBIcon-1.0", true)

    if not LDB or not LibDBIcon then
        return
    end

    if not self.db.profile.minimapButton then
        self.db.profile.minimapButton = {
            hide = false,
        }
    end

    local dataObj = LDB:NewDataObject(ADDON_NAME, {
        type = "launcher",
        icon = ns.Helpers.AssetPath .. "QUI.tga",
        label = "QUI",
        OnClick = function(clickedframe, button)
            if button == "LeftButton" then
                self:OpenConfig()
            elseif button == "RightButton" then
                if _G.QUI_ToggleLayoutMode then
                    _G.QUI_ToggleLayoutMode()
                end
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:SetText("|cFF30D1FFQUI|r")
            tooltip:AddLine(ns.L["Left-click to open configuration"], 1, 1, 1)
            tooltip:AddLine(ns.L["Right-click to toggle Edit Mode"], 1, 1, 1)
        end,
    })

    LibDBIcon:Register(ADDON_NAME, dataObj, self.db.profile.minimapButton)
end

function QUICore:HookEditMode()
    if self.__editModeHooked then return end
    self.__editModeHooked = true

    if EditModeManagerFrame then
        local _bossContainerScaledSidesHooked = false

        local _editModeSuppressedFrames = {}
        local _editModeSuppressedFrameNames = {
            "PlayerFrame", "PartyFrame",
            "BossTargetFrameContainer",
            "BuffFrame", "DebuffFrame",
            "MainMenuBar", "MainActionBar",
            "MultiBarBottomLeft", "MultiBarBottomRight",
            "MultiBarRight", "MultiBarLeft",
            "MultiBar5", "MultiBar6", "MultiBar7",
            "StanceBar", "MicroMenuContainer", "BagsBar",
            "PetActionBar", "ExtraAbilityContainer",
            "ExtraActionBarFrame", "ZoneAbilityFrame",
            "OverrideActionBar", "MainMenuBarVehicleLeaveButton",
            "ObjectiveTrackerFrame",
            "DurabilityFrame",
            "PlayerCastingBarFrame",
            "GameTooltipDefaultContainer",
        }

        local function ShouldSuppressEditModeFrame(name)
            if name == "PartyFrame" then
                local gfDB = QUI.db and QUI.db.profile and QUI.db.profile.quiGroupFrames
                return gfDB and gfDB.enabled ~= false
            end
            return true
        end

        local function SuppressEditModeSelection(frame)
            if not frame then return end
            ns.SafeCallMethodIfPresent("best-effort-style", frame, "ClearHighlight")
            local selection = frame.Selection
            ns.SafeCallMethodIfPresent("best-effort-style", selection, "Hide")
            ns.SafeCallMethodIfPresent("best-effort-style", EditModeMagnetismManager, "UnregisterFrame", frame)
        end

        local function InstallEditModeSuppression()
            for _, name in ipairs(_editModeSuppressedFrameNames) do
                if ShouldSuppressEditModeFrame(name) then
                    local frame = _G[name]
                    if frame and not _editModeSuppressedFrames[frame] then
                        _editModeSuppressedFrames[frame] = true
                        if frame.HighlightSystem then
                            hooksecurefunc(frame, "HighlightSystem", function(f)
                                SuppressEditModeSelection(f)
                            end)
                        end
                        if frame.SelectSystem then
                            hooksecurefunc(frame, "SelectSystem", function(f)
                                SuppressEditModeSelection(f)
                            end)
                        end
                        SuppressEditModeSelection(frame)
                    end
                end
            end
        end

        local suppressFrame = CreateFrame("Frame")
        suppressFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        suppressFrame:SetScript("OnEvent", function(f)
            f:UnregisterAllEvents()
            InstallEditModeSuppression()
        end)

        hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
            InstallEditModeSuppression()
            C_Timer.After(0, function()
                for _, name in ipairs(_editModeSuppressedFrameNames) do
                    if ShouldSuppressEditModeFrame(name) then
                        local frame = _G[name]
                        SuppressEditModeSelection(frame)
                    end
                end
            end)

            if not InCombatLockdown() and BossTargetFrameContainer and not _bossContainerScaledSidesHooked then
                if BossTargetFrameContainer.GetScaledSelectionSides then
                    local original = BossTargetFrameContainer.GetScaledSelectionSides
                    BossTargetFrameContainer.GetScaledSelectionSides = function(frame)
                        local left = frame:GetLeft()
                        if left == nil then
                            return -10000, -9999, 10000, 10001
                        end
                        return original(frame)
                    end
                    _bossContainerScaledSidesHooked = true
                end
            end
        end)

        hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
            C_Timer.After(0.15, function()
                for _, barName in ipairs({"QUIPowerBar", "QUISecondaryPowerBar"}) do
                    local bar = _G[barName]
                    if bar and bar.editOverlay and bar.editOverlay:IsShown() then
                        bar.editOverlay:Hide()
                    end
                end
            end)
        end)
    end

    local combatEndFrame = CreateFrame("Frame")
    combatEndFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    combatEndFrame:SetScript("OnEvent", function(frame, event)
        if event == "PLAYER_REGEN_ENABLED" then
            C_Timer.After(0.3, function()
                local ApplyAllFrameAnchors = _G.QUI_ApplyAllFrameAnchors
                if ApplyAllFrameAnchors then
                    ApplyAllFrameAnchors()
                end
            end)
        end
    end)
end

function QUICore:SetupEncounterWarningsSecretValuePatch()
    if self.__encounterWarningsPatchSetup then return end
    self.__encounterWarningsPatchSetup = true

    local function TryPatch()
        if self.__encounterWarningsPatched then return true end
        if not EncounterWarningsTextElementMixin
            or type(EncounterWarningsTextElementMixin.Init) ~= "function"
            or not EncounterWarningsViewElementMixin
            or not EncounterWarningsUtil then
            return false
        end

        local originalInit = EncounterWarningsTextElementMixin.Init
        EncounterWarningsTextElementMixin.Init = function(textElement, encounterWarningInfo, parentView)
            local ok, err = pcall(originalInit, textElement, encounterWarningInfo, parentView)
            if ok then
                return
            end

            if type(err) == "string" and err:find("secret value") then
                pcall(EncounterWarningsViewElementMixin.Init, textElement, encounterWarningInfo, parentView)

                local maximumTextSize = EncounterWarningsUtil.GetMaximumTextSizeForSeverity(encounterWarningInfo.severity)
                if type(maximumTextSize) ~= "table" then
                    maximumTextSize = { width = 0, height = 0 }
                end
                local textFontObject = EncounterWarningsUtil.GetFontObjectForSeverity(encounterWarningInfo.severity)
                local textColor = EncounterWarningsUtil.GetTextColorForSeverity(encounterWarningInfo.severity)

                if textFontObject then
                    textElement:SetFontObject(textFontObject)
                end
                if textColor and textColor.GetRGB then
                    textElement:SetTextColor(textColor:GetRGB())
                end
                textElement:SetTextScale(1)

                local setOk = pcall(textElement.SetTextToFit, textElement, encounterWarningInfo.text)
                if not setOk then
                    pcall(textElement.SetText, textElement, "")
                end

                local maxHeight = maximumTextSize.height or 0
                local maxWidth = maximumTextSize.width or 0
                textElement:SetHeight(maxHeight)

                local widthOk, tooWide = pcall(function()
                    return textElement:GetStringWidth() > maxWidth
                end)
                if widthOk and tooWide then
                    textElement:SetWidth(maxWidth)
                    pcall(textElement.ScaleTextToFit, textElement)
                end
                return
            end

            error(err, 0)
        end

        self.__encounterWarningsPatched = true
        return true
    end

    local patched = TryPatch()

    self._didEnable = true
    for _, callback in ipairs(self._postEnableCallbacks or {}) do
        ns.SafeCall("bulkhead", callback, self)
    end

    if patched then
        return
    end

    local patchFrame = CreateFrame("Frame")
    patchFrame:RegisterEvent("ADDON_LOADED")
    patchFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    patchFrame:SetScript("OnEvent", function(_, event, addonName)
        if event == "ADDON_LOADED" and addonName == "Blizzard_EncounterWarnings" then
            if TryPatch() then
                patchFrame:UnregisterAllEvents()
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            patchFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
            if not self.__encounterWarningsPatched then
                TryPatch()
            end
            if self.__encounterWarningsPatched then
                patchFrame:UnregisterAllEvents()
            end
        end
    end)

    self.__encounterWarningsPatchFrame = patchFrame
end

function QUI:GetAddonAccentColor()
    local db = QUI.db and QUI.db.profile
    if not db then
        return 0.376, 0.647, 0.980, 1
    end
    local preset = db.general and db.general.themePreset
    if preset and QUI.GUI and QUI.GUI.ResolveThemePreset then
        local r, g, b = QUI.GUI:ResolveThemePreset(preset)
        return r, g, b, 1
    end
    local c = (db.general and db.general.addonAccentColor)
        or db.addonAccentColor
        or {0.376, 0.647, 0.980, 1}
    return c[1], c[2], c[3], c[4] or 1
end

function QUI:GetSkinColor()
    local db = QUI.db and QUI.db.profile
    if not db then
        return 0.376, 0.647, 0.980, 1
    end

    local preset = db.general and db.general.themePreset
    if preset and QUI.GUI and QUI.GUI.ResolveThemePreset then
        local r, g, b = QUI.GUI:ResolveThemePreset(preset)
        return r, g, b, 1
    end

    if db.general and db.general.skinUseClassColor then
        local _, class = UnitClass("player")
        local color = ns.Helpers and ns.Helpers.GetClassColorTable(class)
        if color then
            return color.r, color.g, color.b, 1
        end
    end

    local c = (db.general and db.general.addonAccentColor)
        or db.addonAccentColor
        or {0.376, 0.647, 0.980, 1}
    return c[1], c[2], c[3], c[4] or 1
end

function QUI:GetSkinBgColor()
    local db = QUI.db and QUI.db.profile
    if not db or not db.general then
        return 0.05, 0.05, 0.05, 0.95
    end

    local c = db.general.skinBgColor or { 0.05, 0.05, 0.05, 0.95 }
    return c[1], c[2], c[3], c[4] or 0.95
end

function QUICore:RefreshAll()
    self:UpdatePowerBar()
    self:UpdateSecondaryPowerBar()
    if self.ApplyGlobalFont then
        self:ApplyGlobalFont()
    end
    if self.ApplyGlobalDefaultFont then
        self:ApplyGlobalDefaultFont()
    end
    local RefreshSkyriding = _G.QUI_RefreshSkyriding
    if RefreshSkyriding then
        RefreshSkyriding()
    end
end
