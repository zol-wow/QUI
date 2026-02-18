-- uihider.lua
-- Provides checkboxes to hide various Blizzard UI elements
-- Settings persist across sessions and apply on reload/login

local _, ns = ...
local Helpers = ns.Helpers

-- Default settings
local DEFAULTS = {
    hideObjectiveTrackerAlways = false,
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
}

local pendingObjectiveTrackerHide = false

-- TAINT SAFETY: Track hook state in a local weak-keyed table, NOT on Blizzard
-- frames. Writing _QUI_* properties to secure frames taints them in Midnight's
-- taint model, causing ADDON_ACTION_FORBIDDEN and secret-value errors.
local hookedSecureFrames = setmetatable({}, { __mode = "k" })

-- Get settings from AceDB via shared helper
local function GetSettings()
    local uiHider = Helpers.GetModuleSettings("uiHider", DEFAULTS)
    if not uiHider then return nil end

    -- Backwards compatibility: migrate old hideObjectiveTracker to hideObjectiveTrackerAlways
    if uiHider.hideObjectiveTracker ~= nil then
        if uiHider.hideObjectiveTrackerAlways == nil then
            uiHider.hideObjectiveTrackerAlways = uiHider.hideObjectiveTracker
        end
        uiHider.hideObjectiveTracker = nil  -- Remove old key
    end

    -- Migrate old hideObjectiveTrackerInInstances to new per-type system
    if uiHider.hideObjectiveTrackerInInstances ~= nil then
        if not uiHider.hideObjectiveTrackerInstanceTypes then
            if uiHider.hideObjectiveTrackerInInstances then
                -- User had it enabled: enable all instance types
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
                -- User had it disabled: only enable raids by default
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
        uiHider.hideObjectiveTrackerInInstances = nil  -- Remove old key
    elseif not uiHider.hideObjectiveTrackerInstanceTypes then
        -- Fresh install: all instance types disabled by default
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

-- Helper: Check if player is in a Mythic+ dungeon (difficulty 8)
local function IsInMythicPlus()
    local _, instanceType, difficulty = GetInstanceInfo()
    return instanceType == "party" and difficulty == 8
end

-- Helper: Check if player is in a Normal dungeon (difficulty 1)
local function IsInNormalDungeon()
    local _, instanceType, difficulty = GetInstanceInfo()
    return instanceType == "party" and difficulty == 1
end

-- Helper: Check if player is in a Heroic dungeon (difficulty 2)
local function IsInHeroicDungeon()
    local _, instanceType, difficulty = GetInstanceInfo()
    return instanceType == "party" and difficulty == 2
end

-- Helper: Check if player is in a Mythic dungeon (difficulty 23, not M+)
local function IsInMythicDungeon()
    local _, instanceType, difficulty = GetInstanceInfo()
    return instanceType == "party" and difficulty == 23
end

-- Helper: Check if player is in a Follower dungeon (difficulty 205)
local function IsInFollowerDungeon()
    local inInstance, instanceType = IsInInstance()
    if not inInstance or instanceType ~= "party" then
        return false
    end
    local _, _, difficulty = GetInstanceInfo()
    return difficulty == 205
end

-- Helper: Check if should hide objective tracker based on current instance
local function ShouldHideInCurrentInstance(instanceTypes)
    if not instanceTypes then return false end

    local inInstance, instanceType = IsInInstance()
    if not inInstance or not instanceType then return false end

    -- Special handling for "party" type: check specific dungeon difficulties
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
    -- For other instance types, use the checkbox setting directly
    elseif instanceTypes[instanceType] then
        return true
    end

    return false
end

-- Apply hide/show commands based on saved settings
local function ApplyHideSettings()
    local settings = GetSettings()
    if not settings then
        return
    end
    
    -- Objective Tracker (Quest Tracker)
    if ObjectiveTrackerFrame then
        local shouldHide = false

        -- Check if should hide always
        if settings.hideObjectiveTrackerAlways then
            shouldHide = true
        -- Check if should hide in specific instance types
        elseif ShouldHideInCurrentInstance(settings.hideObjectiveTrackerInstanceTypes) then
            shouldHide = true
        end

        if shouldHide then
            if InCombatLockdown() then
                pendingObjectiveTrackerHide = true
            else
                ObjectiveTrackerFrame:Hide()
                ObjectiveTrackerFrame:EnableMouse(false)  -- Prevent hidden frame from blocking clicks
                pendingObjectiveTrackerHide = false
            end

            -- Hook Show() to prevent Blizzard from showing it again (quest updates, boss fights, etc.)
            local otState = hookedSecureFrames[ObjectiveTrackerFrame]
            if not otState then otState = {}; hookedSecureFrames[ObjectiveTrackerFrame] = otState end
            if not otState.showHooked then
                otState.showHooked = true
                hooksecurefunc(ObjectiveTrackerFrame, "Show", function(self)
                    -- Break secure call chains before enforcing hidden state
                    C_Timer.After(0, function()
                        local s = GetSettings()
                        if s then
                            local shouldHideNow = false
                            if s.hideObjectiveTrackerAlways then
                                shouldHideNow = true
                            elseif ShouldHideInCurrentInstance(s.hideObjectiveTrackerInstanceTypes) then
                                shouldHideNow = true
                            end

                            if shouldHideNow then
                                if type(InCombatLockdown) == "function" and InCombatLockdown() then
                                    pendingObjectiveTrackerHide = true
                                    return
                                end

                                self:Hide()
                                self:EnableMouse(false)  -- Prevent hidden frame from blocking clicks
                                pendingObjectiveTrackerHide = false
                            end
                        end
                    end)
                end)
            end
        else
            pendingObjectiveTrackerHide = false
            if not (type(InCombatLockdown) == "function" and InCombatLockdown()) then
                ObjectiveTrackerFrame:Show()
                ObjectiveTrackerFrame:EnableMouse(true)  -- Restore mouse when shown
            end
        end
    end
    
    -- Minimap Border (Top)
    if MinimapCluster and MinimapCluster.BorderTop then
        if settings.hideMinimapBorder then
        MinimapCluster.BorderTop:Hide()
        else
            MinimapCluster.BorderTop:Show()
        end
    end
    
    -- Time Manager Clock Button
    if TimeManagerClockButton then
        if settings.hideTimeManager then
        TimeManagerClockButton:Hide()
        else
            TimeManagerClockButton:Show()
        end
    end
    
    -- Game Time Frame (Calendar Button)
    if GameTimeFrame then
        if settings.hideGameTime then
            GameTimeFrame:Hide()
        else
            GameTimeFrame:Show()
        end
        -- Hook Show() to prevent Blizzard from re-showing when hidden
        local gtState = hookedSecureFrames[GameTimeFrame]
        if not gtState then gtState = {}; hookedSecureFrames[GameTimeFrame] = gtState end
        if not gtState.showHooked then
            gtState.showHooked = true
            -- TAINT SAFETY: Defer to break taint chain from secure context.
            hooksecurefunc(GameTimeFrame, "Show", function(self)
                C_Timer.After(0, function()
                    local s = GetSettings()
                    if s and s.hideGameTime then
                        self:Hide()
                    end
                end)
            end)
        end
    end

    -- Compact Raid Frame Manager
    if CompactRaidFrameManager then
        local crfState = hookedSecureFrames[CompactRaidFrameManager]
        if not crfState then crfState = {}; hookedSecureFrames[CompactRaidFrameManager] = crfState end

        if InCombatLockdown() then
            -- Skip protected operations during combat
        elseif settings.hideRaidFrameManager then
            -- Defer Hide/EnableMouse to break taint chain from secure context
            C_Timer.After(0, function()
                if InCombatLockdown() then return end
                CompactRaidFrameManager:Hide()
                CompactRaidFrameManager:EnableMouse(false)
            end)
            -- Hook Show() to prevent it from reappearing when joining groups, etc.
            if not crfState.showHooked then
                crfState.showHooked = true
                hooksecurefunc(CompactRaidFrameManager, "Show", function(self)
                    C_Timer.After(0, function()
                        if InCombatLockdown() then return end
                        local s = GetSettings()
                        if s and s.hideRaidFrameManager then
                            self:Hide()
                            self:EnableMouse(false)
                        end
                    end)
                end)
            end
            -- Hook SetShown() to catch permission-change visibility updates
            if not crfState.setShownHooked then
                crfState.setShownHooked = true
                hooksecurefunc(CompactRaidFrameManager, "SetShown", function(self, shown)
                    C_Timer.After(0, function()
                        if InCombatLockdown() then return end
                        local s = GetSettings()
                        if s and s.hideRaidFrameManager and shown then
                            self:Hide()
                            self:EnableMouse(false)
                        end
                    end)
                end)
            end
        else
            CompactRaidFrameManager:Show()
            CompactRaidFrameManager:EnableMouse(true)
        end
    end
    
    -- Minimap Zone Text
    if MinimapZoneText then
        if settings.hideMinimapZoneText then
        MinimapZoneText:Hide()
        else
            MinimapZoneText:Show()
    end
end

    -- Mail Icon is now controlled by Minimap module (showMail setting)
    
    -- Buff Frame Collapse Button (uses alpha approach for persistence)
    if BuffFrame and BuffFrame.CollapseAndExpandButton then
        local btn = BuffFrame.CollapseAndExpandButton
        if settings.hideBuffCollapseButton then
            -- Set alpha to 0 on all textures
            if btn.NormalTexture then btn.NormalTexture:SetAlpha(0) end
            if btn.PushedTexture then btn.PushedTexture:SetAlpha(0) end
            if btn.HighlightTexture then btn.HighlightTexture:SetAlpha(0) end
            -- Disable mouse interaction
            btn:EnableMouse(false)

            -- Hook SetAlpha on textures to prevent Blizzard from resetting
            local btnState = hookedSecureFrames[btn]
            if not btnState then btnState = {}; hookedSecureFrames[btn] = btnState end
            if not btnState.alphaHooked then
                btnState.alphaHooked = true
                -- TAINT SAFETY: Defer to break taint chain from secure context.
                local function BlockAlpha(texture)
                    C_Timer.After(0, function()
                        if not texture then return end
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
            -- Restore visibility
            if btn.NormalTexture then btn.NormalTexture:SetAlpha(1) end
            if btn.PushedTexture then btn.PushedTexture:SetAlpha(1) end
            if btn.HighlightTexture then btn.HighlightTexture:SetAlpha(1) end
            btn:EnableMouse(true)
        end
    end

    -- Friendly Player/NPC Nameplates
    -- TAINT SAFETY: Defer SetCVar calls via C_Timer.After(0) to break taint
    -- chain. Synchronous SetCVar triggers OnNamePlateAdded in the current
    -- (possibly tainted) execution context, causing SetNamePlateHitTestFrame
    -- and CompactUnitFrame_UpdateHealPrediction errors.
    do
        local hidePlayers = settings.hideFriendlyPlayerNameplates
        local hideNPCs = settings.hideFriendlyNPCNameplates
        C_Timer.After(0, function()
            SetCVar("nameplateShowFriendlyPlayers", hidePlayers and "0" or "1")
            SetCVar("nameplateShowFriendlyNPCs", hideNPCs and "0" or "1")
        end)
    end

    -- Talking Head Frame
    -- Fix: TalkingHeadFrame captures mouse even when not showing content,
    -- blocking clicks on panels that open near its position.
    -- We disable mouse on the frame and its children when idle.
    if TalkingHeadFrame then
        local thState = hookedSecureFrames[TalkingHeadFrame]
        if not thState then thState = {}; hookedSecureFrames[TalkingHeadFrame] = thState end

        -- Helper to disable mouse on TalkingHeadFrame and children
        local function DisableTalkingHeadMouse()
            TalkingHeadFrame:EnableMouse(false)
            local childrenToDisable = {
                "MainFrame",
                "PortraitFrame",
                "BackgroundFrame",
                "TextFrame",
                "NameFrame",
            }
            for _, childName in ipairs(childrenToDisable) do
                local child = TalkingHeadFrame[childName]
                if child and child.EnableMouse then
                    child:EnableMouse(false)
                end
            end
        end

        -- Helper to re-enable mouse when showing content
        local function EnableTalkingHeadMouse()
            TalkingHeadFrame:EnableMouse(true)
            local childrenToEnable = {
                "MainFrame",
                "PortraitFrame",
                "BackgroundFrame",
                "TextFrame",
                "NameFrame",
            }
            for _, childName in ipairs(childrenToEnable) do
                local child = TalkingHeadFrame[childName]
                if child and child.EnableMouse then
                    child:EnableMouse(true)
                end
            end
        end

        if settings.hideTalkingHead then
            TalkingHeadFrame:Hide()
            DisableTalkingHeadMouse()

            -- Hook Show() to keep it hidden
            if not thState.showHooked then
                thState.showHooked = true
                -- TAINT SAFETY: Defer to break taint chain from secure context.
                hooksecurefunc(TalkingHeadFrame, "Show", function(self)
                    C_Timer.After(0, function()
                        local s = GetSettings()
                        if s and s.hideTalkingHead then
                            self:Hide()
                            DisableTalkingHeadMouse()
                        end
                    end)
                end)
            end
        else
            -- Not hiding, but still manage mouse to prevent blocking
            -- Disable mouse when idle, re-enable when content plays
            if not thState.mouseManaged then
                thState.mouseManaged = true

                -- Initially disable mouse (no content showing)
                DisableTalkingHeadMouse()

                -- Re-enable mouse when a talking head starts playing
                -- TAINT SAFETY: Defer to break taint chain from secure context.
                hooksecurefunc(TalkingHeadFrame, "PlayCurrent", function()
                    C_Timer.After(0, function()
                        EnableTalkingHeadMouse()
                    end)
                end)

                -- Disable mouse when the talking head finishes/hides
                -- TAINT SAFETY: Defer to break taint chain from secure context.
                TalkingHeadFrame:HookScript("OnHide", function()
                    C_Timer.After(0, function()
                        DisableTalkingHeadMouse()
                    end)
                end)
            end
        end

        -- Talking Head Mute (hook PlayCurrent once)
        if not thState.muteHooked then
            thState.muteHooked = true
            -- TAINT SAFETY: Defer to break taint chain from secure context.
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

    -- Experience Bar and Reputation Bar (handled separately via individual bar hiding)
    if StatusTrackingBarManager then
        local hideXP = settings.hideExperienceBar
        local hideRep = settings.hideReputationBar

        -- Use Blizzard's BarsEnum if available, fallback to known values
        local BarsEnum = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
        local BARS_ENUM_EXPERIENCE = BarsEnum and BarsEnum.Experience or 4
        local BARS_ENUM_REPUTATION = BarsEnum and BarsEnum.Reputation or 1

        -- Helper function to hide individual bars based on type
        local function HideStatusBars()
            local s = GetSettings()
            if not s then return end

            local doHideXP = s.hideExperienceBar
            local doHideRep = s.hideReputationBar

            -- If both are hidden, hide the entire manager
            if doHideXP and doHideRep then
                StatusTrackingBarManager:Hide()
                return
            end

            -- Show the manager if it was hidden
            StatusTrackingBarManager:Show()

            -- Blizzard uses barContainers (visual slots) that display bars based on shownBarIndex
            -- Each container can show one bar type at a time, determined by priority
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

        -- If both are hidden, just hide the entire manager
        if hideXP and hideRep then
            StatusTrackingBarManager:Hide()

            if not stbState.showHooked then
                stbState.showHooked = true
                -- TAINT SAFETY: Defer to break taint chain from secure context.
                hooksecurefunc(StatusTrackingBarManager, "Show", function(self)
                    C_Timer.After(0, function()
                        local s = GetSettings()
                        if s and s.hideExperienceBar and s.hideReputationBar then
                            self:Hide()
                        end
                    end)
                end)
            end
        elseif hideXP or hideRep then
            -- Show the manager but hide individual bars
            StatusTrackingBarManager:Show()
            if StatusTrackingBarManager.barContainers then
                HideStatusBars()
            end

            -- Hook UpdateBarsShown to re-hide bars after Blizzard updates
            if not stbState.barsHooked then
                stbState.barsHooked = true
                hooksecurefunc(StatusTrackingBarManager, "UpdateBarsShown", function()
                    C_Timer.After(0.01, HideStatusBars)
                end)
            end
        end
        -- else: Do nothing - let other addons/Blizzard manage the bar when QUI isn't hiding
    end

    -- UIErrorsFrame (error and info messages)
    if UIErrorsFrame then
        local hideErrors = settings.hideErrorMessages
        local hideInfo = settings.hideInfoMessages

        if hideErrors and hideInfo then
            UIErrorsFrame:Hide()
            UIErrorsFrame:EnableMouse(false)
            UIErrorsFrame:UnregisterAllEvents()
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

    -- World Map Blackout (dark overlay behind fullscreen map)
    if WorldMapFrame and WorldMapFrame.BlackoutFrame then
        if settings.hideWorldMapBlackout then
            WorldMapFrame.BlackoutFrame:SetAlpha(0)
            WorldMapFrame.BlackoutFrame:EnableMouse(false)

            -- Hook the BlackoutFrame to keep it hidden if Blizzard tries to show it
            -- IMPORTANT: Skip during combat to avoid taint propagation to SetPassThroughButtons
            local boState = hookedSecureFrames[WorldMapFrame.BlackoutFrame]
            if not boState then boState = {}; hookedSecureFrames[WorldMapFrame.BlackoutFrame] = boState end
            if not boState.blackoutHooked then
                boState.blackoutHooked = true
                -- TAINT SAFETY: Defer to break taint chain from secure context.
                hooksecurefunc(WorldMapFrame.BlackoutFrame, "Show", function(self)
                    C_Timer.After(0, function()
                        if InCombatLockdown() then return end  -- Avoid taint during combat
                        local s = GetSettings()
                        if s and s.hideWorldMapBlackout then
                            self:SetAlpha(0)
                            self:EnableMouse(false)
                        end
                    end)
                end)

                -- Also hook SetAlpha to prevent alpha changes
                -- TAINT SAFETY: Defer to break taint chain from secure context.
                hooksecurefunc(WorldMapFrame.BlackoutFrame, "SetAlpha", function(self)
                    C_Timer.After(0, function()
                        if InCombatLockdown() then return end  -- Avoid taint during combat
                        local s = GetSettings()
                        if s and s.hideWorldMapBlackout and self.GetAlpha and self:GetAlpha() > 0 then
                            self:SetAlpha(0)
                            self:EnableMouse(false)
                        end
                    end)
                end)
            end
        else
            WorldMapFrame.BlackoutFrame:SetAlpha(1)
            WorldMapFrame.BlackoutFrame:EnableMouse(true)
        end
    end
end

-- Initialize
-- Note: ApplyHideSettings is called from core/main.lua OnEnable()
-- This ensures AceDB is initialized before we try to read settings

-- Event frame for instance detection, raid permission changes, and addon loading
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("CHALLENGE_MODE_START")
eventFrame:RegisterEvent("CHALLENGE_MODE_RESET")
eventFrame:SetScript("OnEvent", function(self, event, addon)
    local settings = GetSettings()

    -- Handle Blizzard_TalkingHeadUI loading (it's load-on-demand)
    -- Apply TalkingHeadFrame mouse fix when it loads
    if event == "ADDON_LOADED" and addon == "Blizzard_TalkingHeadUI" then
        -- Re-apply settings now that TalkingHeadFrame exists
        if settings then
            _G.QUI_RefreshUIHider()
        end
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if pendingObjectiveTrackerHide then
            pendingObjectiveTrackerHide = false
        end
        if settings then
            ApplyHideSettings()
        end
        return
    end

    -- Handle raid permission/role changes - re-hide CompactRaidFrameManager
    -- BUG-008: Wrap in C_Timer.After(0) to break taint chain from secure event context
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" then
        if settings and settings.hideRaidFrameManager and CompactRaidFrameManager then
            C_Timer.After(0, function()
                if not InCombatLockdown() then
                    CompactRaidFrameManager:Hide()
                    CompactRaidFrameManager:EnableMouse(false)
                end
            end)
        end
        return
    end

    -- Refresh all hide settings when entering new zones/instances
    -- This ensures hooks are properly set up for ObjectiveTrackerFrame and other elements
    if settings then
        ApplyHideSettings()
    end
end)

-- Export to QUI namespace
QUI.UIHider = {
    ApplySettings = ApplyHideSettings,
}

-- Global function for config panel to call
_G.QUI_RefreshUIHider = function()
    ApplyHideSettings()
end

