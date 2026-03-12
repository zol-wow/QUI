---------------------------------------------------------------------------
-- QUI Crosshair Module
-- A simple screen center crosshair overlay
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local QUI = ns.QUI or {}
ns.QUI = QUI
local Helpers = ns.Helpers
local CreateOnUpdateThrottle = Helpers and Helpers.CreateOnUpdateThrottle

local crosshairFrame, horizLine, vertLine, horizBorder, vertBorder

-- Separate frame for range checking (always visible so OnUpdate runs even when crosshair is hidden)
local rangeCheckFrame

-- Range tracking state
local isOutOfRange = false
local isOutOfMidRange = false  -- For 25-yard check
local RANGE_CHECK_INTERVAL = 0.1  -- Check range 10 times per second
local eventFrame = CreateFrame("Frame")
local eventRegistrationState = {}
local UpdateEventRegistrations


---------------------------------------------------------------------------
-- Get settings from database
---------------------------------------------------------------------------
local function GetSettings()
    return Helpers.GetModuleDB("crosshair")
end

---------------------------------------------------------------------------
-- Range checking via shared RangeUtils (cached action bar scan)
---------------------------------------------------------------------------
local IsOutOfMeleeRange = function() return ns.RangeUtils.IsOutOfMeleeRange() end
local IsOutOfMidRange = function() return ns.RangeUtils.IsOutOfMidRange() end

---------------------------------------------------------------------------
-- Apply crosshair color based on range state
-- Supports independent melee (5yd) and mid-range (25yd) checks
---------------------------------------------------------------------------
local function ApplyCrosshairColor(settings, outOfMelee, outOfMid)
    if not horizLine or not vertLine then return end

    local r, g, b, a

    if settings.changeColorOnRange then
        local meleeCheck = settings.enableMeleeRangeCheck ~= false  -- default true
        local midCheck = settings.enableMidRangeCheck == true

        if meleeCheck and midCheck then
            -- Both checks enabled: melee → mid-range → out-of-range
            if outOfMid then
                -- Out of 25-yard range - use out-of-range color
                local oorColor = settings.outOfRangeColor or { 1, 0.2, 0.2, 1 }
                r, g, b, a = oorColor[1] or 1, oorColor[2] or 0.2, oorColor[3] or 0.2, oorColor[4] or 1
            elseif outOfMelee then
                -- Out of melee but in 25-yard range - use mid-range color
                local midColor = settings.midRangeColor or { 1, 0.6, 0.2, 1 }
                r, g, b, a = midColor[1] or 1, midColor[2] or 0.6, midColor[3] or 0.2, midColor[4] or 1
            else
                -- In melee range - use normal color
                r, g, b, a = settings.r or 1, settings.g or 0.949, settings.b or 0, settings.a or 1
            end
        elseif meleeCheck then
            -- Only melee check: in melee → out-of-range
            if outOfMelee then
                local oorColor = settings.outOfRangeColor or { 1, 0.2, 0.2, 1 }
                r, g, b, a = oorColor[1] or 1, oorColor[2] or 0.2, oorColor[3] or 0.2, oorColor[4] or 1
            else
                r, g, b, a = settings.r or 1, settings.g or 0.949, settings.b or 0, settings.a or 1
            end
        elseif midCheck then
            -- Only mid-range check: in 25yd → out-of-range
            if outOfMid then
                local oorColor = settings.outOfRangeColor or { 1, 0.2, 0.2, 1 }
                r, g, b, a = oorColor[1] or 1, oorColor[2] or 0.2, oorColor[3] or 0.2, oorColor[4] or 1
            else
                r, g, b, a = settings.r or 1, settings.g or 0.949, settings.b or 0, settings.a or 1
            end
        else
            -- No checks enabled (shouldn't happen, but fallback to normal)
            r, g, b, a = settings.r or 1, settings.g or 0.949, settings.b or 0, settings.a or 1
        end
    else
        -- Range checking disabled - use normal color
        r, g, b, a = settings.r or 1, settings.g or 0.949, settings.b or 0, settings.a or 1
    end

    horizLine:SetColorTexture(r, g, b, a)
    vertLine:SetColorTexture(r, g, b, a)
end

---------------------------------------------------------------------------
-- Range check OnUpdate handler
---------------------------------------------------------------------------
local rangeCheckTicker

local function StopRangeCheckTicker()
    if rangeCheckTicker then
        rangeCheckTicker:Cancel()
        rangeCheckTicker = nil
    end
end

local function PerformRangeUpdate()
    local settings = GetSettings()
    if not settings or not settings.enabled or not settings.changeColorOnRange then
        -- Feature disabled, stop checking
        StopRangeCheckTicker()
        return
    end

    local inCombat = InCombatLockdown()

    -- Check if we should only track range in combat
    if settings.rangeColorInCombatOnly and not inCombat then
        -- Not in combat and combat-only is enabled, use normal color
        if isOutOfRange or isOutOfMidRange then
            isOutOfRange = false
            isOutOfMidRange = false
            ApplyCrosshairColor(settings, false, false)
        end
        -- If hideUntilOutOfRange, hide the crosshair when not in combat
        if settings.hideUntilOutOfRange and crosshairFrame then
            crosshairFrame:Hide()
        end
        return
    end

    local meleeCheck = settings.enableMeleeRangeCheck ~= false
    local midCheck = settings.enableMidRangeCheck == true

    local newOutOfRange = meleeCheck and IsOutOfMeleeRange() or false
    local newOutOfMidRange = midCheck and IsOutOfMidRange() or false

    if newOutOfRange ~= isOutOfRange or newOutOfMidRange ~= isOutOfMidRange then
        isOutOfRange = newOutOfRange
        isOutOfMidRange = newOutOfMidRange
        ApplyCrosshairColor(settings, isOutOfRange, isOutOfMidRange)
    end

    -- Handle hideUntilOutOfRange visibility (trigger on whichever range check is active)
    if settings.hideUntilOutOfRange and crosshairFrame then
        local shouldShow = inCombat and ((meleeCheck and isOutOfRange) or (midCheck and not meleeCheck and isOutOfMidRange))
        if shouldShow then
            crosshairFrame:Show()
        else
            crosshairFrame:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Start or stop range checking based on settings
---------------------------------------------------------------------------
local function UpdateRangeChecking()
    if not crosshairFrame then return end

    -- Create the range check frame if needed (used as a named anchor for the crosshair system)
    if not rangeCheckFrame then
        rangeCheckFrame = CreateFrame("Frame", "QUI_CrosshairRangeCheck", UIParent)
        rangeCheckFrame:SetSize(1, 1)
        rangeCheckFrame:SetPoint("CENTER")
        rangeCheckFrame:Show()
    end

    local settings = GetSettings()
    if settings and settings.enabled and settings.changeColorOnRange then
        -- Replace any existing ticker with a fresh one
        StopRangeCheckTicker()
        rangeCheckTicker = C_Timer.NewTicker(RANGE_CHECK_INTERVAL, PerformRangeUpdate)

        local inCombat = InCombatLockdown()

        -- Immediately check range (respecting combat-only setting)
        local meleeCheck = settings.enableMeleeRangeCheck ~= false
        local midCheck = settings.enableMidRangeCheck == true

        if settings.rangeColorInCombatOnly and not inCombat then
            isOutOfRange = false
            isOutOfMidRange = false
            ApplyCrosshairColor(settings, false, false)
        else
            isOutOfRange = meleeCheck and IsOutOfMeleeRange() or false
            isOutOfMidRange = midCheck and IsOutOfMidRange() or false
            ApplyCrosshairColor(settings, isOutOfRange, isOutOfMidRange)
        end

        -- Handle hideUntilOutOfRange initial visibility
        if settings.hideUntilOutOfRange then
            if inCombat and isOutOfRange then
                crosshairFrame:Show()
            else
                crosshairFrame:Hide()
            end
        end
    else
        -- Disable range checking
        StopRangeCheckTicker()
        if rangeCheckFrame then
            rangeCheckFrame:SetScript("OnUpdate", nil)
        end
        isOutOfRange = false
    end
end

---------------------------------------------------------------------------
-- Create the crosshair frame and textures
---------------------------------------------------------------------------
local function CreateCrosshair()
    if crosshairFrame then return end
    
    crosshairFrame = CreateFrame("Frame", "QUI_Crosshair", UIParent)
    crosshairFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    crosshairFrame:SetSize(1, 1)
    crosshairFrame:SetFrameStrata("HIGH")
    
    -- Border textures (drawn behind main lines)
    horizBorder = crosshairFrame:CreateTexture(nil, "BACKGROUND")
    horizBorder:SetPoint("CENTER", crosshairFrame)
    horizBorder:SetColorTexture(0, 0, 0, 1)
    
    vertBorder = crosshairFrame:CreateTexture(nil, "BACKGROUND")
    vertBorder:SetPoint("CENTER", crosshairFrame)
    vertBorder:SetColorTexture(0, 0, 0, 1)
    
    -- Main crosshair lines (drawn above borders)
    horizLine = crosshairFrame:CreateTexture(nil, "ARTWORK")
    horizLine:SetPoint("CENTER", crosshairFrame)
    horizLine:SetColorTexture(1, 0.949, 0, 1)  -- Default yellow
    
    vertLine = crosshairFrame:CreateTexture(nil, "ARTWORK")
    vertLine:SetPoint("CENTER", crosshairFrame)
    vertLine:SetColorTexture(1, 0.949, 0, 1)  -- Default yellow
    
    crosshairFrame:Hide()
end

---------------------------------------------------------------------------
-- Update crosshair appearance from settings
---------------------------------------------------------------------------
local function UpdateCrosshair()
    if not crosshairFrame then
        CreateCrosshair()
    end
    
    local settings = GetSettings()
    if not settings then
        crosshairFrame:Hide()
        UpdateRangeChecking()
        UpdateEventRegistrations(nil)
        return
    end
    
    -- Get settings with defaults
    local enabled = settings.enabled
    local size = settings.size or 12
    local thickness = settings.thickness or 3
    local borderSize = settings.borderSize or 2
    local offsetX = settings.offsetX or 0
    local offsetY = settings.offsetY or 0
    local borderR = settings.borderR or 0
    local borderG = settings.borderG or 0
    local borderB = settings.borderB or 0
    local borderA = settings.borderA or 1
    local strata = settings.strata or "HIGH"
    local onlyInCombat = settings.onlyInCombat
    
    -- Apply strata and position
    crosshairFrame:SetFrameStrata(strata)
    crosshairFrame:ClearAllPoints()
    crosshairFrame:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
    
    -- Size the border textures (slightly larger than main lines)
    horizBorder:SetSize((size * 2) + borderSize * 2, thickness + borderSize * 2)
    vertBorder:SetSize(thickness + borderSize * 2, (size * 2) + borderSize * 2)
    horizBorder:SetColorTexture(borderR, borderG, borderB, borderA)
    vertBorder:SetColorTexture(borderR, borderG, borderB, borderA)
    
    -- Size the main crosshair lines
    horizLine:SetSize(size * 2, thickness)
    vertLine:SetSize(thickness, size * 2)
    
    -- Apply color based on range state (if feature enabled)
    if settings.changeColorOnRange then
        local meleeCheck = settings.enableMeleeRangeCheck ~= false
        local midCheck = settings.enableMidRangeCheck == true
        isOutOfRange = meleeCheck and IsOutOfMeleeRange() or false
        isOutOfMidRange = midCheck and IsOutOfMidRange() or false
        ApplyCrosshairColor(settings, isOutOfRange, isOutOfMidRange)
    else
        -- Use normal color
        local r = settings.r or 1
        local g = settings.g or 0.949
        local b = settings.b or 0
        local a = settings.a or 1
        horizLine:SetColorTexture(r, g, b, a)
        vertLine:SetColorTexture(r, g, b, a)
    end
    
    -- Show/hide based on settings
    if not enabled then
        crosshairFrame:Hide()
        crosshairFrame:SetScript("OnUpdate", nil)
    elseif onlyInCombat then
        crosshairFrame:SetShown(InCombatLockdown())
    else
        crosshairFrame:Show()
    end
    
    -- Update range checking state
    UpdateRangeChecking()
    UpdateEventRegistrations(settings)
end

---------------------------------------------------------------------------
-- Combat visibility handling
---------------------------------------------------------------------------
local function OnCombatStart()
    local settings = GetSettings()
    if settings and settings.enabled and settings.onlyInCombat then
        if crosshairFrame then
            crosshairFrame:Show()
            UpdateRangeChecking()
        end
    end
end

local function OnCombatEnd()
    local settings = GetSettings()
    if settings and settings.onlyInCombat then
        if crosshairFrame then
            crosshairFrame:Hide()
            crosshairFrame:SetScript("OnUpdate", nil)
        end
    end
end

---------------------------------------------------------------------------
-- Target changed handler
---------------------------------------------------------------------------
local function OnTargetChanged()
    local settings = GetSettings()
    if settings and settings.enabled and settings.changeColorOnRange then
        -- Immediately update color when target changes
        local meleeCheck = settings.enableMeleeRangeCheck ~= false
        local midCheck = settings.enableMidRangeCheck == true
        isOutOfRange = meleeCheck and IsOutOfMeleeRange() or false
        isOutOfMidRange = midCheck and IsOutOfMidRange() or false
        ApplyCrosshairColor(settings, isOutOfRange, isOutOfMidRange)
    end
end

local function SetEventRegistration(eventName, shouldRegister)
    local isRegistered = eventRegistrationState[eventName] == true
    if shouldRegister and not isRegistered then
        eventFrame:RegisterEvent(eventName)
        eventRegistrationState[eventName] = true
    elseif not shouldRegister and isRegistered then
        eventFrame:UnregisterEvent(eventName)
        eventRegistrationState[eventName] = false
    end
end

UpdateEventRegistrations = function(settings)
    settings = settings or GetSettings()
    local enabled = settings and settings.enabled
    local needsCombatEvents = enabled and (settings.onlyInCombat or settings.rangeColorInCombatOnly or settings.hideUntilOutOfRange)
    local needsTargetEvent = enabled and settings.changeColorOnRange

    SetEventRegistration("PLAYER_REGEN_DISABLED", needsCombatEvents)
    SetEventRegistration("PLAYER_REGEN_ENABLED", needsCombatEvents)
    SetEventRegistration("PLAYER_TARGET_CHANGED", needsTargetEvent)
end

---------------------------------------------------------------------------
-- Initialize
---------------------------------------------------------------------------
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName ~= ADDON_NAME then return end
        self:UnregisterEvent("ADDON_LOADED")
        CreateCrosshair()
        UpdateCrosshair()
        UpdateEventRegistrations()
    elseif event == "PLAYER_REGEN_DISABLED" then
        OnCombatStart()
    elseif event == "PLAYER_REGEN_ENABLED" then
        OnCombatEnd()
    elseif event == "PLAYER_TARGET_CHANGED" then
        OnTargetChanged()
    end
end)

---------------------------------------------------------------------------
-- Global refresh function for GUI
---------------------------------------------------------------------------
_G.QUI_RefreshCrosshair = UpdateCrosshair

QUI.Crosshair = {
    Update = UpdateCrosshair,
    Create = CreateCrosshair,
}

