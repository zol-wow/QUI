local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local SkinBase = ns.SkinBase

local eventFrame = CreateFrame("Frame")
local combatEventsRegistered = false

local GetSettings = Helpers.CreateDBGetter("general")

local function GetConfig()
    local settings = GetSettings()
    if not settings then return nil end
    return settings.noTargetWarning
end

local WarningFrame = CreateFrame("Frame", "QUI_NoTargetWarningFrame", UIParent, "BackdropTemplate")
WarningFrame:SetSize(220, 44)
WarningFrame:SetFrameStrata("HIGH")
WarningFrame:Hide()

do
    local bgr, bgg, bgb = 0.1, 0.1, 0.1
    if Helpers and Helpers.GetSkinBgColor then
        bgr, bgg, bgb = Helpers.GetSkinBgColor()
    end
    local sr, sg, sb = 1, 0.3, 0.3
    if SkinBase and SkinBase.CreateBackdrop then
        SkinBase.CreateBackdrop(WarningFrame, sr, sg, sb, 1, bgr, bgg, bgb, 0.9)
    elseif SkinBase and SkinBase.ApplyPixelBackdrop then
        SkinBase.ApplyPixelBackdrop(WarningFrame, 2, true, false, { sr, sg, sb, 1 }, { bgr, bgg, bgb, 0.9 })
    end
end

WarningFrame.text = WarningFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
WarningFrame.text:SetPoint("CENTER")
WarningFrame.text:SetTextColor(1, 0.3, 0.3, 1)
WarningFrame.text:SetText(ns.L["No Target"])

local pulse = WarningFrame:CreateAnimationGroup()
pulse:SetLooping("BOUNCE")
local fade = pulse:CreateAnimation("Alpha")
fade:SetFromAlpha(1)
fade:SetToAlpha(0.25)
fade:SetDuration(0.5)
fade:SetSmoothing("IN_OUT")

local function ApplyFontSize()
    local cfg = GetConfig()
    local size = (cfg and cfg.fontSize) or 20
    local fontPath = select(1, WarningFrame.text:GetFont())
    if fontPath and size and size > 0 then
        if Helpers and Helpers.ApplyFontWithFallback then
            Helpers.ApplyFontWithFallback(WarningFrame.text, fontPath, size, "OUTLINE")
        else
            WarningFrame.text:SetFont(fontPath, size, "OUTLINE")
        end
    end
end

local function PositionWarningFrame()
    if _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("noTargetWarning") then return end

    local cfg = GetConfig()
    local xOffset = (cfg and cfg.offsetX) or 0
    local yOffset = (cfg and cfg.offsetY) or -160

    WarningFrame:ClearAllPoints()
    WarningFrame:SetPoint("CENTER", UIParent, "CENTER", xOffset, yOffset)
end

PositionWarningFrame()

local warningTicker = nil
local shown = false

local function ShowWarning()
    if shown then return end
    shown = true
    PositionWarningFrame()
    ApplyFontSize()
    WarningFrame:Show()
    if not pulse:IsPlaying() then pulse:Play() end
end

local function HideWarning()
    if not shown and not WarningFrame:IsShown() then return end
    shown = false
    if pulse:IsPlaying() then pulse:Stop() end
    WarningFrame:SetAlpha(1)
    WarningFrame:Hide()
end

local function HasNoAttackableTarget()
    if not UnitExists("target") then return true end
    if UnitIsDead("target") then return true end
    if not UnitCanAttack("player", "target") then return true end
    return false
end

local function UpdateWarningState()
    local cfg = GetConfig()
    if not cfg or not cfg.enabled then
        HideWarning()
        return
    end
    if not InCombatLockdown() then
        HideWarning()
        return
    end
    if HasNoAttackableTarget() then
        ShowWarning()
    else
        HideWarning()
    end
end

local function StartPolling()
    if warningTicker then
        warningTicker:Cancel()
        warningTicker = nil
    end
    UpdateWarningState()
    warningTicker = C_Timer.NewTicker(0.25, UpdateWarningState)
end

local function StopPolling()
    if warningTicker then
        warningTicker:Cancel()
        warningTicker = nil
    end
    HideWarning()
end

local function SetCombatEventsRegistered(shouldRegister)
    if shouldRegister and not combatEventsRegistered then
        eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
        combatEventsRegistered = true
    elseif not shouldRegister and combatEventsRegistered then
        eventFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
        eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        eventFrame:UnregisterEvent("PLAYER_TARGET_CHANGED")
        combatEventsRegistered = false
    end
end

local function UpdateEventRegistration()
    local cfg = GetConfig()
    local enabled = cfg and cfg.enabled == true
    SetCombatEventsRegistered(enabled)
    if not enabled then
        StopPolling()
    end
end

eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        StartPolling()
    elseif event == "PLAYER_REGEN_ENABLED" then
        StopPolling()
    elseif event == "PLAYER_TARGET_CHANGED" then
        if InCombatLockdown() then UpdateWarningState() end
    end
end)

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(function()
        UpdateEventRegistration()
        if InCombatLockdown() and combatEventsRegistered then
            StartPolling()
        end
    end)
end

local function RefreshNoTargetWarning()
    PositionWarningFrame()
    ApplyFontSize()
    UpdateEventRegistration()
    local bgr, bgg, bgb = 0.1, 0.1, 0.1
    if Helpers and Helpers.GetSkinBgColor then
        bgr, bgg, bgb = Helpers.GetSkinBgColor()
    end
    local sr, sg, sb = 1, 0.3, 0.3
    if SkinBase and SkinBase.CreateBackdrop then
        SkinBase.CreateBackdrop(WarningFrame, sr, sg, sb, 1, bgr, bgg, bgb, 0.9)
    elseif WarningFrame.SetBackdropColor then
        WarningFrame:SetBackdropColor(bgr, bgg, bgb, 0.9)
    end
    if InCombatLockdown() and combatEventsRegistered then
        StartPolling()
    else
        StopPolling()
    end
end
ns.RefreshNoTargetWarning = RefreshNoTargetWarning

local function ToggleNoTargetWarningPreview(show)
    if show then
        PositionWarningFrame()
        ApplyFontSize()
        WarningFrame.text:SetText(ns.L["No Target"])
        WarningFrame:SetAlpha(1)
        WarningFrame:Show()
        if not pulse:IsPlaying() then pulse:Play() end
    else
        if pulse:IsPlaying() then pulse:Stop() end
        WarningFrame:SetAlpha(1)
        WarningFrame:Hide()
    end
end
ns.ToggleNoTargetWarningPreview = ToggleNoTargetWarningPreview

if ns.Registry then
    ns.Registry:Register("noTargetWarning", {
        refresh = RefreshNoTargetWarning,
        priority = 30,
        group = "qol",
        importCategories = { "qol" },
    })
    ns.Registry:Register("noTargetWarningSkin", {
        refresh = RefreshNoTargetWarning,
        priority = 30,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end
