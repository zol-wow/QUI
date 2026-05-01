--[[
    QUI AbilityTimeline Integration Module
    Anchors AbilityTimeline timeline and big icon frames to QUI elements.
]]

local ADDON_NAME, ns = ...
local QUICore = ns.Addon

---------------------------------------------------------------------------
-- MODULE TABLE
---------------------------------------------------------------------------
local QUI_AbilityTimeline = {}
ns.QUI_AbilityTimeline = QUI_AbilityTimeline

-- Deferred updates when frames are unavailable
local pendingUpdate = false
local retryTimer = nil

-- Hook install guard
local anchoredFramesHookInstalled = false
local TARGET_KEYS = {
    timeline = "abilityTimelineTimeline",
    bigIcon = "abilityTimelineBigIcon",
}

---------------------------------------------------------------------------
-- DATABASE ACCESS
---------------------------------------------------------------------------
local function GetDB()
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.abilityTimeline then
        return QUICore.db.profile.abilityTimeline
    end
    return nil
end

---------------------------------------------------------------------------
-- ADDON AVAILABILITY
---------------------------------------------------------------------------
local function IsAddonLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(name)
    end
    if type(IsAddOnLoaded) == "function" then
        return IsAddOnLoaded(name)
    end
    return false
end

function QUI_AbilityTimeline:IsAvailable()
    if _G.AbilityTimelineFrame or _G.AbilityTimelineBigIconFrame then
        return true
    end
    return IsAddonLoaded("AbilityTimeline")
end

---------------------------------------------------------------------------
-- FRAME RESOLUTION
---------------------------------------------------------------------------
function QUI_AbilityTimeline:GetAddonFrame(frameKey)
    if frameKey == "timeline" then
        return _G.AbilityTimelineFrame
    elseif frameKey == "bigIcon" then
        return _G.AbilityTimelineBigIconFrame
    end
    return nil
end

function QUI_AbilityTimeline:GetAnchorFrame(anchorName)
    if not anchorName or anchorName == "disabled" then
        return nil
    end

    -- Hardcoded QUI element map
    if anchorName == "essential" then
        return _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("essential")
    elseif anchorName == "utility" then
        return _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("utility")
    elseif anchorName == "primary" then
        return QUICore and QUICore.powerBar
    elseif anchorName == "secondary" then
        return QUICore and QUICore.secondaryPowerBar
    elseif anchorName == "playerCastbar" then
        return ns.QUI_Castbar and ns.QUI_Castbar.castbars and ns.QUI_Castbar.castbars["player"]
    elseif anchorName == "playerFrame" then
        return ns.QUI_UnitFrames and ns.QUI_UnitFrames.frames and ns.QUI_UnitFrames.frames.player
    elseif anchorName == "targetFrame" then
        return ns.QUI_UnitFrames and ns.QUI_UnitFrames.frames and ns.QUI_UnitFrames.frames.target
    end

    -- Registry fallback
    if ns.QUI_Anchoring and ns.QUI_Anchoring.GetAnchorTarget then
        return ns.QUI_Anchoring:GetAnchorTarget(anchorName)
    end

    return nil
end

---------------------------------------------------------------------------
-- POSITIONING
---------------------------------------------------------------------------
local function QueueRetry()
    if retryTimer then
        return
    end
    retryTimer = C_Timer.NewTimer(1.0, function()
        retryTimer = nil
        if ns.QUI_AbilityTimeline then
            ns.QUI_AbilityTimeline:ApplyAllPositions()
        end
    end)
end

local function TryInstallAnchoredFramesHook()
    if anchoredFramesHookInstalled then
        return true
    end

    local previousUpdateAnchoredFrames = _G.QUI_UpdateAnchoredFrames
    if not previousUpdateAnchoredFrames then
        return false
    end

    _G.QUI_UpdateAnchoredFrames = function(...)
        previousUpdateAnchoredFrames(...)
        QUI_AbilityTimeline:ApplyAllPositions()
    end
    anchoredFramesHookInstalled = true
    return true
end

local function RegisterAnchorTargets()
    if not (ns.QUI_Anchoring and ns.QUI_Anchoring.RegisterAnchorTarget) then
        return
    end

    local timelineFrame = _G.AbilityTimelineFrame
    if timelineFrame then
        ns.QUI_Anchoring:RegisterAnchorTarget(TARGET_KEYS.timeline, timelineFrame, {
            displayName = "AbilityTimeline Timeline",
            category = "External",
            categoryOrder = 1,
            order = 3,
        })
    end

    local bigIconFrame = _G.AbilityTimelineBigIconFrame
    if bigIconFrame then
        ns.QUI_Anchoring:RegisterAnchorTarget(TARGET_KEYS.bigIcon, bigIconFrame, {
            displayName = "AbilityTimeline Big Icon",
            category = "External",
            categoryOrder = 1,
            order = 4,
        })
    end
end

function QUI_AbilityTimeline:ApplyPosition(frameKey)
    local db = GetDB()
    if not db or not db[frameKey] then
        return
    end

    local cfg = db[frameKey]
    if not cfg.enabled or cfg.anchorTo == "disabled" then
        return
    end

    local addonFrame = self:GetAddonFrame(frameKey)
    if not addonFrame then
        pendingUpdate = true
        QueueRetry()
        return
    end

    local anchorFrame = self:GetAnchorFrame(cfg.anchorTo)
    if not anchorFrame then
        pendingUpdate = true
        QueueRetry()
        return
    end

    local ok = pcall(function()
        addonFrame:ClearAllPoints()
        addonFrame:SetPoint(
            cfg.sourcePoint or "TOP",
            anchorFrame,
            cfg.targetPoint or "BOTTOM",
            cfg.offsetX or 0,
            cfg.offsetY or -5
        )
    end)

    if not ok then
        pendingUpdate = true
        QueueRetry()
    end
end

function QUI_AbilityTimeline:ApplyAllPositions()
    TryInstallAnchoredFramesHook()
    RegisterAnchorTargets()
    self:ApplyPosition("timeline")
    self:ApplyPosition("bigIcon")
end

---------------------------------------------------------------------------
-- INITIALIZE
---------------------------------------------------------------------------
local initialized = false

function QUI_AbilityTimeline:Initialize()
    if not self:IsAvailable() then
        return
    end

    if not initialized then
        initialized = true
    end

    self:ApplyAllPositions()
end

---------------------------------------------------------------------------
-- EVENT HANDLING
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1.0, function()
            QUI_AbilityTimeline:Initialize()
        end)
    elseif event == "ADDON_LOADED" and arg1 == "AbilityTimeline" then
        C_Timer.After(1.0, function()
            QUI_AbilityTimeline:Initialize()
        end)
    elseif event == "PLAYER_REGEN_ENABLED" and pendingUpdate then
        pendingUpdate = false
        C_Timer.After(0.1, function()
            QUI_AbilityTimeline:ApplyAllPositions()
        end)
    end
end)

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
