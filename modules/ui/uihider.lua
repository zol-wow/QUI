local _, ns = ...
local Helpers = ns.Helpers

local DEFAULTS = {
    hideObjectiveTrackerAlways = false,
    keepTrackerInDelvesScenarios = false,
    hideObjectiveTrackerInstanceTypes = {
        mythicPlus = false,
        mythicDungeon = false,
        normalDungeon = false,
        heroicDungeon = false,
        followerDungeon = false,
        raid = false,
        pvp = false,
        arena = false,
    },
    hideMinimapBorder = false,
    hideTimeManager = false,
    hideGameTime = false,
    hideRaidFrameManager = false,
    hideMinimapZoneText = false,
    hideBuffCollapseButton = false,
    hideFriendlyPlayerNameplates = false,
    hideFriendlyNPCNameplates = false,
    hideTalkingHead = true,
    hideExperienceBar = false,
    hideReputationBar = false,
    hideErrorMessages = false,
    hideInfoMessages = false,
    hideWorldMapBlackout = false,
    hidePlayerFrameInParty = false,
}

local pendingObjectiveTrackerHide = false
local pendingApplyHideSettings = false

local _crfHidden = false
local _crfOrigParent = nil
local _crfHideParent = nil

local hookedSecureFrames = Helpers.CreateStateTable()

local IsInEditMode = Helpers.IsEditModeShown

local function GetSettings()
    local uiHider = Helpers.GetModuleSettings("uiHider", DEFAULTS)
    if not uiHider then return nil end

    if uiHider.hideObjectiveTracker ~= nil then
        if uiHider.hideObjectiveTrackerAlways == nil then
            uiHider.hideObjectiveTrackerAlways = uiHider.hideObjectiveTracker
        end
        uiHider.hideObjectiveTracker = nil
    end

    if uiHider.hideObjectiveTrackerInInstances ~= nil then
        if not uiHider.hideObjectiveTrackerInstanceTypes then
            if uiHider.hideObjectiveTrackerInInstances then
                uiHider.hideObjectiveTrackerInstanceTypes = {
                    mythicPlus = true,
                    mythicDungeon = true,
                    normalDungeon = true,
                    heroicDungeon = true,
                    followerDungeon = true,
                    raid = true,
                    pvp = true,
                    arena = true,
                }
            else
                uiHider.hideObjectiveTrackerInstanceTypes = {
                    mythicPlus = false,
                    mythicDungeon = false,
                    normalDungeon = false,
                    heroicDungeon = false,
                    followerDungeon = false,
                    raid = true,
                    pvp = false,
                    arena = false,
                }
            end
        end
        uiHider.hideObjectiveTrackerInInstances = nil
    elseif not uiHider.hideObjectiveTrackerInstanceTypes then
        uiHider.hideObjectiveTrackerInstanceTypes = {
            mythicPlus = false,
            mythicDungeon = false,
            normalDungeon = false,
            heroicDungeon = false,
            followerDungeon = false,
            raid = false,
            pvp = false,
            arena = false,
        }
    end

    return uiHider
end

local function IsInMythicPlus()
    local _, instanceType, difficulty = GetInstanceInfo()
    return instanceType == "party" and difficulty == 8
end

local function IsInNormalDungeon()
    local _, instanceType, difficulty = GetInstanceInfo()
    return instanceType == "party" and difficulty == 1
end

local function IsInHeroicDungeon()
    local _, instanceType, difficulty = GetInstanceInfo()
    return instanceType == "party" and difficulty == 2
end

local function IsInMythicDungeon()
    local _, instanceType, difficulty = GetInstanceInfo()
    return instanceType == "party" and difficulty == 23
end

local function IsInFollowerDungeon()
    local inInstance, instanceType = IsInInstance()
    if not inInstance or instanceType ~= "party" then
        return false
    end
    local _, _, difficulty = GetInstanceInfo()
    return difficulty == 205
end

local function ShouldHideInCurrentInstance(instanceTypes)
    if not instanceTypes then return false end

    local inInstance, instanceType = IsInInstance()
    if not inInstance or not instanceType then return false end

    if instanceType == "party" then
        if IsInFollowerDungeon() and instanceTypes.followerDungeon then
            return true
        elseif IsInMythicPlus() and instanceTypes.mythicPlus then
            return true
        elseif IsInMythicDungeon() and instanceTypes.mythicDungeon then
            return true
        elseif IsInNormalDungeon() and instanceTypes.normalDungeon then
            return true
        elseif IsInHeroicDungeon() and instanceTypes.heroicDungeon then
            return true
        end
    elseif instanceTypes[instanceType] then
        return true
    end

    return false
end

local function IsInDelveOrScenario()
    local delves = _G.C_DelvesUI
    if delves then
        if delves.HasActiveDelve then
            local ok, active = ns.SafeCall("report", delves.HasActiveDelve)
            if ok and active then return true end
        end
        if delves.GetTieredEntranceType then
            local ok, entranceType = ns.SafeCall("report", delves.GetTieredEntranceType)
            if ok and entranceType == 1 then return true end
        end
    end

    if C_ScenarioInfo and C_ScenarioInfo.GetScenarioInfo then
        local ok, info = ns.SafeCall("report", C_ScenarioInfo.GetScenarioInfo)
        if ok and info then return true end
    end

    return false
end

local function ShouldHideObjectiveTracker(s)
    local wouldHide = s.hideObjectiveTrackerAlways
        or ShouldHideInCurrentInstance(s.hideObjectiveTrackerInstanceTypes)

    if wouldHide and s.keepTrackerInDelvesScenarios and IsInDelveOrScenario() then
        return false
    end

    return wouldHide
end

local function ApplyHideSettings()
    local settings = GetSettings()
    if not settings then
        return
    end

    if IsInEditMode() then
        return
    end

    if InCombatLockdown() then
        pendingApplyHideSettings = true
        return
    end
    pendingApplyHideSettings = false

    if ObjectiveTrackerFrame then
        local shouldHide = ShouldHideObjectiveTracker(settings)

        if shouldHide then
            if InCombatLockdown() then
                pendingObjectiveTrackerHide = true
            else
                ObjectiveTrackerFrame:Hide()
                ObjectiveTrackerFrame:EnableMouse(false)
                pendingObjectiveTrackerHide = false
            end

            local otState = hookedSecureFrames[ObjectiveTrackerFrame]
            if not otState then otState = {}; hookedSecureFrames[ObjectiveTrackerFrame] = otState end
            if not otState.showHooked then
                otState.showHooked = true
                hooksecurefunc(ObjectiveTrackerFrame, "Show", function(self)
                    if IsInEditMode() then return end
                    local s = GetSettings()
                    if s then
                        if ShouldHideObjectiveTracker(s) then
                            self:SetAlpha(0)
                        end
                    end

                    C_Timer.After(0, function()
                        if IsInEditMode() then return end
                        local s2 = GetSettings()
                        if s2 then
                            if ShouldHideObjectiveTracker(s2) then
                                if InCombatLockdown() then
                                    pendingObjectiveTrackerHide = true
                                    return
                                end

                                self:Hide()
                                self:EnableMouse(false)
                                pendingObjectiveTrackerHide = false
                            end
                        end
                    end)
                end)
            end
        else
            pendingObjectiveTrackerHide = false
            if not InCombatLockdown() then
                ObjectiveTrackerFrame:SetAlpha(1)
                ObjectiveTrackerFrame:Show()
                ObjectiveTrackerFrame:EnableMouse(true)
            end
        end
    end

    if MinimapCluster and MinimapCluster.BorderTop then
        if settings.hideMinimapBorder then
        MinimapCluster.BorderTop:Hide()
        else
            MinimapCluster.BorderTop:Show()
        end
    end

    if TimeManagerClockButton then
        if settings.hideTimeManager then
        TimeManagerClockButton:Hide()
        else
            TimeManagerClockButton:Show()
        end
    end

    if GameTimeFrame then
        if settings.hideGameTime then
            GameTimeFrame:Hide()
        else
            GameTimeFrame:Show()
        end
        local gtState = hookedSecureFrames[GameTimeFrame]
        if not gtState then gtState = {}; hookedSecureFrames[GameTimeFrame] = gtState end
        if not gtState.showHooked then
            gtState.showHooked = true
            hooksecurefunc(GameTimeFrame, "Show", function(self)
                C_Timer.After(0, function()
                    if IsInEditMode() then return end
                    local s = GetSettings()
                    if s and s.hideGameTime then
                        self:Hide()
                    end
                end)
            end)
        end
    end

    if CompactRaidFrameManager then
        if InCombatLockdown() then
        elseif settings.hideRaidFrameManager then
            if not _crfHidden then
                if not _crfHideParent then
                    _crfHideParent = CreateFrame("Frame")
                    _crfHideParent:Hide()
                end
                _crfOrigParent = CompactRaidFrameManager:GetParent()
                CompactRaidFrameManager:SetParent(_crfHideParent)
                _crfHidden = true
            end
        else
            if _crfHidden then
                CompactRaidFrameManager:SetParent(_crfOrigParent or UIParent)
                _crfHidden = false
            end
        end
    end

    if MinimapZoneText then
        if settings.hideMinimapZoneText then
            MinimapZoneText:Hide()
        else
            MinimapZoneText:Show()
        end
    end

    if BuffFrame and BuffFrame.CollapseAndExpandButton then
        local btn = BuffFrame.CollapseAndExpandButton
        if settings.hideBuffCollapseButton then
            if btn.NormalTexture then btn.NormalTexture:SetAlpha(0) end
            if btn.PushedTexture then btn.PushedTexture:SetAlpha(0) end
            if btn.HighlightTexture then btn.HighlightTexture:SetAlpha(0) end
            btn:EnableMouse(false)

            local btnState = hookedSecureFrames[btn]
            if not btnState then btnState = {}; hookedSecureFrames[btn] = btnState end
            if not btnState.alphaHooked then
                btnState.alphaHooked = true
                local function BlockAlpha(texture)
                    C_Timer.After(0, function()
                        if not texture then return end
                        if IsInEditMode() then return end
                        local s = GetSettings()
                        if s and s.hideBuffCollapseButton and texture.GetAlpha and texture:GetAlpha() > 0 then
                            texture:SetAlpha(0)
                        end
                    end)
                end
                if btn.NormalTexture then hooksecurefunc(btn.NormalTexture, "SetAlpha", BlockAlpha) end
                if btn.PushedTexture then hooksecurefunc(btn.PushedTexture, "SetAlpha", BlockAlpha) end
                if btn.HighlightTexture then hooksecurefunc(btn.HighlightTexture, "SetAlpha", BlockAlpha) end
            end
        else
            if btn.NormalTexture then btn.NormalTexture:SetAlpha(1) end
            if btn.PushedTexture then btn.PushedTexture:SetAlpha(1) end
            if btn.HighlightTexture then btn.HighlightTexture:SetAlpha(1) end
            btn:EnableMouse(true)
        end
    end

    do
        local hidePlayers = settings.hideFriendlyPlayerNameplates
        local hideNPCs = settings.hideFriendlyNPCNameplates
        C_Timer.After(0, function()
            local npCVars = ns.QUI_NameplatesCVars
            if npCVars and npCVars.IsActive and npCVars:IsActive() then
                npCVars:RequestFriendlyVisibility(not hidePlayers, not hideNPCs)
                return
            end
            SetCVar("nameplateShowFriendlyPlayers", hidePlayers and "0" or "1")
            SetCVar("nameplateShowFriendlyNPCs", hideNPCs and "0" or "1")
        end)
    end

    if TalkingHeadFrame then
        local thState = hookedSecureFrames[TalkingHeadFrame]
        if not thState then thState = {}; hookedSecureFrames[TalkingHeadFrame] = thState end

        local talkingHeadChildren = {
            "MainFrame",
            "PortraitFrame",
            "BackgroundFrame",
            "TextFrame",
            "NameFrame",
        }
        local function SetTalkingHeadMouse(enable)
            TalkingHeadFrame:EnableMouse(enable)
            for _, childName in ipairs(talkingHeadChildren) do
                local child = TalkingHeadFrame[childName]
                if child and child.EnableMouse then
                    child:EnableMouse(enable)
                end
            end
        end

        local function DisableTalkingHeadMouse()
            SetTalkingHeadMouse(false)
        end

        local function EnableTalkingHeadMouse()
            SetTalkingHeadMouse(true)
        end

        if settings.hideTalkingHead then
            TalkingHeadFrame:Hide()
            DisableTalkingHeadMouse()

            if not thState.showHooked then
                thState.showHooked = true
                hooksecurefunc(TalkingHeadFrame, "Show", function(self)
                    C_Timer.After(0, function()
                        if IsInEditMode() then return end
                        local s = GetSettings()
                        if s and s.hideTalkingHead then
                            self:Hide()
                            DisableTalkingHeadMouse()
                        end
                    end)
                end)
            end
        else
            if not thState.mouseManaged then
                thState.mouseManaged = true

                DisableTalkingHeadMouse()

                hooksecurefunc(TalkingHeadFrame, "PlayCurrent", function()
                    C_Timer.After(0, function()
                        EnableTalkingHeadMouse()
                    end)
                end)

                TalkingHeadFrame:HookScript("OnHide", function()
                    C_Timer.After(0, function()
                        DisableTalkingHeadMouse()
                    end)
                end)
            end
        end

        if not thState.muteHooked then
            thState.muteHooked = true
            hooksecurefunc(TalkingHeadFrame, "PlayCurrent", function()
                C_Timer.After(0, function()
                    local s = GetSettings()
                    if s and s.muteTalkingHead and TalkingHeadFrame.voHandle then
                        StopSound(TalkingHeadFrame.voHandle, 0)
                        TalkingHeadFrame.voHandle = nil
                    end
                end)
            end)
        end
    end

    if StatusTrackingBarManager then
        local hideXP = settings.hideExperienceBar
        local hideRep = settings.hideReputationBar

        local BarsEnum = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
        local BARS_ENUM_EXPERIENCE = BarsEnum and BarsEnum.Experience or 4
        local BARS_ENUM_REPUTATION = BarsEnum and BarsEnum.Reputation or 1

        local function HideStatusBars()
            if IsInEditMode() then return end
            local s = GetSettings()
            if not s then return end

            local doHideXP = s.hideExperienceBar
            local doHideRep = s.hideReputationBar

            if doHideXP and doHideRep then
                StatusTrackingBarManager:Hide()
                return
            end

            StatusTrackingBarManager:Show()

            if StatusTrackingBarManager.barContainers then
                for _, container in ipairs(StatusTrackingBarManager.barContainers) do
                    local shownBarIndex = container.shownBarIndex

                    if shownBarIndex == BARS_ENUM_EXPERIENCE and doHideXP then
                        container:SetAlpha(0)
                        container:EnableMouse(false)
                    elseif shownBarIndex == BARS_ENUM_REPUTATION and doHideRep then
                        container:SetAlpha(0)
                        container:EnableMouse(false)
                    else
                        container:SetAlpha(1)
                        container:EnableMouse(true)
                    end
                end
            end
        end

        local stbState = hookedSecureFrames[StatusTrackingBarManager]
        if not stbState then stbState = {}; hookedSecureFrames[StatusTrackingBarManager] = stbState end

        if hideXP and hideRep then
            StatusTrackingBarManager:Hide()

            if not stbState.showHooked then
                stbState.showHooked = true
                hooksecurefunc(StatusTrackingBarManager, "Show", function(self)
                    C_Timer.After(0, function()
                        if IsInEditMode() then return end
                        local s = GetSettings()
                        if s and s.hideExperienceBar and s.hideReputationBar then
                            self:Hide()
                        end
                    end)
                end)
            end
        elseif hideXP or hideRep then
            StatusTrackingBarManager:Show()
            if StatusTrackingBarManager.barContainers then
                HideStatusBars()
            end

            if not stbState.barsHooked then
                stbState.barsHooked = true
                hooksecurefunc(StatusTrackingBarManager, "UpdateBarsShown", function()
                    C_Timer.After(0.01, HideStatusBars)
                end)
            end
        end
    end

    if UIErrorsFrame then
        local hideErrors = settings.hideErrorMessages
        local hideInfo = settings.hideInfoMessages

        if hideErrors and hideInfo then
            UIErrorsFrame:Hide()
            UIErrorsFrame:EnableMouse(false)
            UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
            UIErrorsFrame:UnregisterEvent("UI_INFO_MESSAGE")
        else
            UIErrorsFrame:Show()
            UIErrorsFrame:EnableMouse(false)

            if hideErrors then
                UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
            else
                UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE")
            end

            if hideInfo then
                UIErrorsFrame:UnregisterEvent("UI_INFO_MESSAGE")
            else
                UIErrorsFrame:RegisterEvent("UI_INFO_MESSAGE")
            end
        end
    end

    if WorldMapFrame and WorldMapFrame.BlackoutFrame and not InCombatLockdown() then
        local boState = hookedSecureFrames[WorldMapFrame.BlackoutFrame]
        if not boState then boState = {}; hookedSecureFrames[WorldMapFrame.BlackoutFrame] = boState end
        if settings.hideWorldMapBlackout then
            if not boState.blackoutHidden then
                RegisterStateDriver(WorldMapFrame.BlackoutFrame, "visibility", "hide")
                boState.blackoutHidden = true
            end
        elseif boState.blackoutHidden then
            UnregisterStateDriver(WorldMapFrame.BlackoutFrame, "visibility")
            WorldMapFrame.BlackoutFrame:Show()
            boState.blackoutHidden = false
        end
    end

    local QUI_UF = ns and ns.QUI_UnitFrames
    local playerFrame = (QUI_UF and QUI_UF.frames and QUI_UF.frames.player) or PlayerFrame
    if playerFrame and not InCombatLockdown() then
        local pfState = hookedSecureFrames[playerFrame]
        if not pfState then pfState = {}; hookedSecureFrames[playerFrame] = pfState end
        if settings.hidePlayerFrameInParty then
            RegisterStateDriver(playerFrame, "visibility", "[group] hide; show")
        elseif pfState.partyHideActive then
            UnregisterStateDriver(playerFrame, "visibility")
            playerFrame:Show()
        end
        pfState.partyHideActive = settings.hidePlayerFrameInParty
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("CHALLENGE_MODE_START")
eventFrame:RegisterEvent("CHALLENGE_MODE_RESET")
eventFrame:RegisterEvent("SCENARIO_UPDATE")
eventFrame:RegisterEvent("SCENARIO_COMPLETED")
eventFrame:RegisterEvent("ACTIVE_DELVE_DATA_UPDATE")
eventFrame:RegisterEvent("UNIT_ENTERED_VEHICLE")
eventFrame:RegisterEvent("UNIT_EXITED_VEHICLE")
if C_PetBattles then
    eventFrame:RegisterEvent("PET_BATTLE_OPENING_START")
    eventFrame:RegisterEvent("PET_BATTLE_CLOSE")
end
eventFrame:SetScript("OnEvent", function(self, event, addon)
    local settings = GetSettings()

    if event == "ADDON_LOADED" and addon == "Blizzard_TalkingHeadUI" then
        if settings then
            _G.QUI_RefreshUIHider()
        end
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        local needsApply = pendingApplyHideSettings or pendingObjectiveTrackerHide
        pendingObjectiveTrackerHide = false
        if settings and needsApply then
            ApplyHideSettings()
        end
        return
    end

    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" then
        if settings and settings.hidePlayerFrameInParty then
            C_Timer.After(0, function()
                if IsInEditMode() then return end
                if InCombatLockdown() then return end
                ApplyHideSettings()
            end)
        end
        return
    end

    if event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" then
        local unit = addon
        if unit ~= "player" then return end
        if settings and settings.hideDataBarsInVehicle and StatusTrackingBarManager then
            C_Timer.After(0, function()
                if UnitInVehicle("player") then
                    StatusTrackingBarManager:Hide()
                else
                    StatusTrackingBarManager:Show()
                    ApplyHideSettings()
                end
            end)
        end
        return
    end

    if event == "PET_BATTLE_OPENING_START" then
        if settings and settings.hideDataBarsInPetBattle and StatusTrackingBarManager then
            StatusTrackingBarManager:Hide()
        end
        return
    end

    if event == "PET_BATTLE_CLOSE" then
        if settings and settings.hideDataBarsInPetBattle and StatusTrackingBarManager then
            C_Timer.After(0.1, function()
                StatusTrackingBarManager:Show()
                ApplyHideSettings()
            end)
        end
        return
    end

    if settings then
        ApplyHideSettings()
    end
end)

QUI.UIHider = {
    ApplySettings = ApplyHideSettings,
}

_G.QUI_RefreshUIHider = function()
    ApplyHideSettings()
end

if ns.Registry then
    ns.Registry:Register("uiHider", {
        refresh = _G.QUI_RefreshUIHider,
        priority = 60,
        group = "ui",
        importCategories = { "qol" },
    })
end

local function ShowAllHiddenForEditMode()
    if InCombatLockdown() then return end
    local settings = GetSettings()
    if not settings then return end

    if ObjectiveTrackerFrame then
        local wasHidden = ShouldHideObjectiveTracker(settings)
        if wasHidden then
            ObjectiveTrackerFrame:SetAlpha(1)
            ObjectiveTrackerFrame:Show()
            ObjectiveTrackerFrame:EnableMouse(true)
        end
    end

    if settings.hidePlayerFrameInParty then
        local QUI_UF = ns and ns.QUI_UnitFrames
        local playerFrame = (QUI_UF and QUI_UF.frames and QUI_UF.frames.player) or PlayerFrame
        if playerFrame then
            UnregisterStateDriver(playerFrame, "visibility")
            playerFrame:Show()
        end
    end

    if MinimapCluster and MinimapCluster.BorderTop and settings.hideMinimapBorder then
        MinimapCluster.BorderTop:Show()
    end

    if TimeManagerClockButton and settings.hideTimeManager then
        TimeManagerClockButton:Show()
    end

    if GameTimeFrame and settings.hideGameTime then
        GameTimeFrame:Show()
    end

    if CompactRaidFrameManager and settings.hideRaidFrameManager and _crfHidden then
        CompactRaidFrameManager:SetParent(_crfOrigParent or UIParent)
        _crfHidden = false
    end

    if MinimapZoneText and settings.hideMinimapZoneText then
        MinimapZoneText:Show()
    end

    if BuffFrame and BuffFrame.CollapseAndExpandButton and settings.hideBuffCollapseButton then
        local btn = BuffFrame.CollapseAndExpandButton
        if btn.NormalTexture then btn.NormalTexture:SetAlpha(1) end
        if btn.PushedTexture then btn.PushedTexture:SetAlpha(1) end
        if btn.HighlightTexture then btn.HighlightTexture:SetAlpha(1) end
        btn:EnableMouse(true)
    end

    if TalkingHeadFrame and settings.hideTalkingHead then
        local sel = TalkingHeadFrame.Selection
        if sel and sel:IsShown() then
            TalkingHeadFrame:Show()
        end
    end

    if StatusTrackingBarManager then
        if settings.hideExperienceBar and settings.hideReputationBar then
            StatusTrackingBarManager:Show()
        end
        if StatusTrackingBarManager.barContainers then
            for _, container in ipairs(StatusTrackingBarManager.barContainers) do
                container:SetAlpha(1)
                container:EnableMouse(true)
            end
        end
    end

    if WorldMapFrame and WorldMapFrame.BlackoutFrame and not InCombatLockdown() then
        local boState = hookedSecureFrames[WorldMapFrame.BlackoutFrame]
        if boState and boState.blackoutHidden then
            UnregisterStateDriver(WorldMapFrame.BlackoutFrame, "visibility")
            WorldMapFrame.BlackoutFrame:Show()
            boState.blackoutHidden = false
        end
    end

    if UIErrorsFrame then
        if settings.hideErrorMessages and settings.hideInfoMessages then
            UIErrorsFrame:Show()
        end
        if settings.hideErrorMessages then
            UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE")
        end
        if settings.hideInfoMessages then
            UIErrorsFrame:RegisterEvent("UI_INFO_MESSAGE")
        end
    end
end

C_Timer.After(1.5, function()
    local core = Helpers.GetCore and Helpers.GetCore()
    if not core or not core.RegisterEditModeEnter then return end

    core:RegisterEditModeEnter(function()
        if InCombatLockdown() then return end
        ShowAllHiddenForEditMode()
    end)

    core:RegisterEditModeExit(function()
        if InCombatLockdown() then return end
        ApplyHideSettings()
    end)
end)
