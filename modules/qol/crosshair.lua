local ADDON_NAME, ns = ...
local QUI = ns.QUI or {}
ns.QUI = QUI
local Helpers = ns.Helpers

local crosshairFrame, horizLine, vertLine, horizBorder, vertBorder


local isOutOfRange = false
local isOutOfMidRange = false
local RANGE_CHECK_INTERVAL = 0.1
local eventFrame = CreateFrame("Frame")
local eventRegistrationState = {}
local UpdateEventRegistrations

local GetSettings = Helpers.CreateDBGetter("crosshair")

local IsOutOfMeleeRange = function() return ns.RangeUtils.IsOutOfMeleeRange() end
local IsOutOfMidRange = function() return ns.RangeUtils.IsOutOfMidRange() end

local function ApplyCrosshairColor(settings, outOfMelee, outOfMid)
    if not horizLine or not vertLine then return end

    local r, g, b, a

    if settings.changeColorOnRange then
        local meleeCheck = settings.enableMeleeRangeCheck ~= false
        local midCheck = settings.enableMidRangeCheck == true

        if meleeCheck and midCheck then
            if outOfMid then
                local oorColor = settings.outOfRangeColor or { 1, 0.2, 0.2, 1 }
                r, g, b, a = oorColor[1] or 1, oorColor[2] or 0.2, oorColor[3] or 0.2, oorColor[4] or 1
            elseif outOfMelee then
                local midColor = settings.midRangeColor or { 1, 0.6, 0.2, 1 }
                r, g, b, a = midColor[1] or 1, midColor[2] or 0.6, midColor[3] or 0.2, midColor[4] or 1
            else
                r, g, b, a = settings.r or 1, settings.g or 0.949, settings.b or 0, settings.a or 1
            end
        elseif meleeCheck then
            if outOfMelee then
                local oorColor = settings.outOfRangeColor or { 1, 0.2, 0.2, 1 }
                r, g, b, a = oorColor[1] or 1, oorColor[2] or 0.2, oorColor[3] or 0.2, oorColor[4] or 1
            else
                r, g, b, a = settings.r or 1, settings.g or 0.949, settings.b or 0, settings.a or 1
            end
        elseif midCheck then
            if outOfMid then
                local oorColor = settings.outOfRangeColor or { 1, 0.2, 0.2, 1 }
                r, g, b, a = oorColor[1] or 1, oorColor[2] or 0.2, oorColor[3] or 0.2, oorColor[4] or 1
            else
                r, g, b, a = settings.r or 1, settings.g or 0.949, settings.b or 0, settings.a or 1
            end
        else
            r, g, b, a = settings.r or 1, settings.g or 0.949, settings.b or 0, settings.a or 1
        end
    else
        r, g, b, a = settings.r or 1, settings.g or 0.949, settings.b or 0, settings.a or 1
    end

    horizLine:SetColorTexture(r, g, b, a)
    vertLine:SetColorTexture(r, g, b, a)
end

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
        StopRangeCheckTicker()
        return
    end

    local inCombat = InCombatLockdown()

    if settings.rangeColorInCombatOnly and not inCombat then
        if isOutOfRange or isOutOfMidRange then
            isOutOfRange = false
            isOutOfMidRange = false
            ApplyCrosshairColor(settings, false, false)
        end
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

    if settings.hideUntilOutOfRange and crosshairFrame then
        local shouldShow = inCombat and ((meleeCheck and isOutOfRange) or (midCheck and not meleeCheck and isOutOfMidRange))
        if shouldShow then
            crosshairFrame:Show()
        else
            crosshairFrame:Hide()
        end
    end
end

local function UpdateRangeChecking()
    if not crosshairFrame then return end

    local settings = GetSettings()
    if settings and settings.enabled and settings.changeColorOnRange then
        StopRangeCheckTicker()
        rangeCheckTicker = C_Timer.NewTicker(RANGE_CHECK_INTERVAL, PerformRangeUpdate)

        local inCombat = InCombatLockdown()

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

        if settings.hideUntilOutOfRange then
            local shouldShow = inCombat and ((meleeCheck and isOutOfRange) or (midCheck and not meleeCheck and isOutOfMidRange))
            if shouldShow then
                crosshairFrame:Show()
            else
                crosshairFrame:Hide()
            end
        end
    else
        StopRangeCheckTicker()
        isOutOfRange = false
        isOutOfMidRange = false
    end
end

local function CreateCrosshair()
    if crosshairFrame then return end

    crosshairFrame = CreateFrame("Frame", "QUI_Crosshair", UIParent)
    crosshairFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    crosshairFrame:SetSize(1, 1)
    crosshairFrame:SetFrameStrata("HIGH")

    horizBorder = crosshairFrame:CreateTexture(nil, "BACKGROUND")
    horizBorder:SetPoint("CENTER", crosshairFrame)
    horizBorder:SetColorTexture(0, 0, 0, 1)

    vertBorder = crosshairFrame:CreateTexture(nil, "BACKGROUND")
    vertBorder:SetPoint("CENTER", crosshairFrame)
    vertBorder:SetColorTexture(0, 0, 0, 1)

    horizLine = crosshairFrame:CreateTexture(nil, "ARTWORK")
    horizLine:SetPoint("CENTER", crosshairFrame)
    horizLine:SetColorTexture(1, 0.949, 0, 1)

    vertLine = crosshairFrame:CreateTexture(nil, "ARTWORK")
    vertLine:SetPoint("CENTER", crosshairFrame)
    vertLine:SetColorTexture(1, 0.949, 0, 1)

    crosshairFrame:Hide()
end

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

    local enabled = settings.enabled
    local size = settings.size or 12
    local thickness = settings.thickness or 3
    local borderSize = settings.borderSize or 2
    local offsetX = settings.offsetX or 0
    local offsetY = settings.offsetY or 0
    local borderR, borderG, borderB, borderA = Helpers.GetSkinBorderColor(settings, "")
    local strata = settings.strata or "HIGH"
    local onlyInCombat = settings.onlyInCombat

    crosshairFrame:SetFrameStrata(strata)
    if not (_G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("crosshair")) then
        crosshairFrame:ClearAllPoints()
        crosshairFrame:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
    end

    horizBorder:SetSize((size * 2) + borderSize * 2, thickness + borderSize * 2)
    vertBorder:SetSize(thickness + borderSize * 2, (size * 2) + borderSize * 2)
    horizBorder:SetColorTexture(borderR, borderG, borderB, borderA)
    vertBorder:SetColorTexture(borderR, borderG, borderB, borderA)

    horizLine:SetSize(size * 2, thickness)
    vertLine:SetSize(thickness, size * 2)

    if settings.changeColorOnRange then
        local meleeCheck = settings.enableMeleeRangeCheck ~= false
        local midCheck = settings.enableMidRangeCheck == true
        isOutOfRange = meleeCheck and IsOutOfMeleeRange() or false
        isOutOfMidRange = midCheck and IsOutOfMidRange() or false
        ApplyCrosshairColor(settings, isOutOfRange, isOutOfMidRange)
    else
        local r = settings.r or 1
        local g = settings.g or 0.949
        local b = settings.b or 0
        local a = settings.a or 1
        horizLine:SetColorTexture(r, g, b, a)
        vertLine:SetColorTexture(r, g, b, a)
    end

    if not enabled then
        crosshairFrame:Hide()
        crosshairFrame:SetScript("OnUpdate", nil)
    elseif onlyInCombat then
        crosshairFrame:SetShown(InCombatLockdown())
    else
        crosshairFrame:Show()
    end

    UpdateRangeChecking()
    UpdateEventRegistrations(settings)
end

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

local function OnTargetChanged()
    local settings = GetSettings()
    if settings and settings.enabled and settings.changeColorOnRange then
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

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        OnCombatStart()
    elseif event == "PLAYER_REGEN_ENABLED" then
        OnCombatEnd()
    elseif event == "PLAYER_TARGET_CHANGED" then
        OnTargetChanged()
    end
end)

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(function()
        CreateCrosshair()
        UpdateCrosshair()
        UpdateEventRegistrations()
    end)
end

_G.QUI_RefreshCrosshair = UpdateCrosshair

if ns.Registry then
    ns.Registry:Register("crosshair", {
        refresh = _G.QUI_RefreshCrosshair,
        priority = 30,
        group = "qol",
        importCategories = { "castBars" },
    })
end

QUI.Crosshair = {
    Update = UpdateCrosshair,
    Create = CreateCrosshair,
}

if Helpers and Helpers.BorderRegistry then
    Helpers.BorderRegistry.Register({
        key = "crosshair", label = "Crosshair", category = "HUD", prefix = "",
        db = function(p) return p.crosshair end,
        refresh = function() if _G.QUI_RefreshCrosshair then _G.QUI_RefreshCrosshair() end end,
        legacy = { table = "borderColorTable", scalars = true },
    })
end
