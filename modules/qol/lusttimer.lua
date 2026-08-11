local ADDON_NAME, ns = ...
local QUI = ns.QUI or {}
ns.QUI = QUI
local QUICore = ns.Addon
local Helpers = ns.Helpers
local UIKit = ns.UIKit

local function CJKFont(fs, p, s, f)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fs, p, s, f)
    else
        fs:SetFont(p, s, f)
    end
end

local C_UnitAuras = C_UnitAuras
local issecretvalue = issecretvalue

local LUST_SPELLS = {
    [2825]   = true,
    [32182]  = true,
    [80353]  = true,
    [264667] = true,
    [390386] = true,
    [466904] = true,
}
local SATED_SPELLS = {
    [57723]  = true,
    [57724]  = true,
    [80354]  = true,
    [264689] = true,
    [390435] = true,
}

local STATUS_BAR_INTERPOLATION_IMMEDIATE = 0
local STATUS_BAR_TIMER_REMAINING = 1

local State = {
    frame = nil,
    isPreviewMode = false,
    activeInstanceID = nil,
}

local GetSettings = Helpers.CreateDBGetter("lustTimer")

-- entirely C-side (SetTimerDuration / SetCooldownFromDurationObject), so no
local function BindDuration(bar, count, instanceID)
    if not bar or not instanceID then return false end
    if not (C_UnitAuras and C_UnitAuras.GetAuraDuration) then return false end
    local ok, durObj = pcall(C_UnitAuras.GetAuraDuration, "player", instanceID)
    if not ok or not durObj then return false end

    local appliedBar = ns.SafeCallMethod("sink-forward", bar, "SetTimerDuration", durObj,
        STATUS_BAR_INTERPOLATION_IMMEDIATE, STATUS_BAR_TIMER_REMAINING)
    ns.SafeCallMethodIfPresent("sink-forward", count, "SetCooldownFromDurationObject", durObj)
    return appliedBar and true or false
end

local function CreateTimerFrame()
    if State.frame then return end

    local frame = CreateFrame("Frame", "QUI_LustTimer", UIParent, "BackdropTemplate")
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
    frame:SetSize(160, 22)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(50)

    frame:SetBackdrop(UIKit.GetBackdropInfo(nil, nil, frame))
    local bgr, bgg, bgb = 0, 0, 0
    if Helpers and Helpers.GetSkinBgColor then bgr, bgg, bgb = Helpers.GetSkinBgColor() end
    frame:SetBackdropColor(bgr, bgg, bgb, 0.6)
    UIKit.CreateBorderLines(frame)
    UIKit.UpdateBorderLines(frame, 1, 0, 0, 0, 1)

    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    bar:SetStatusBarColor(0.6, 0.2, 0.2, 1)
    frame.bar = bar

    local count = CreateFrame("Cooldown", nil, bar, "CooldownFrameTemplate")
    count:SetAllPoints(bar)
    count:SetDrawSwipe(false)
    count:SetDrawEdge(false)
    count:SetHideCountdownNumbers(false)
    frame.count = count

    local label = bar:CreateFontString(nil, "OVERLAY")
    label:SetPoint("LEFT", bar, "LEFT", 4, 0)
    CJKFont(label, (Helpers and Helpers.GetGeneralFont and Helpers.GetGeneralFont()) or "Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    label:SetTextColor(1, 1, 1, 1)
    label:SetText(ns.L and ns.L["Lust"] or "Lust")
    frame.label = label

    frame:Hide()
    State.frame = frame
end

local function UpdateAppearance()
    if not State.frame then CreateTimerFrame() end
    local settings = GetSettings()
    if not settings then return end
    local frame = State.frame

    local width = settings.width or 160
    local height = settings.height or 22
    frame:SetSize(width, height)

    local xOffset = settings.xOffset or 0
    local yOffset = settings.yOffset or -120
    if not (_G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("lustTimer")) then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", xOffset, yOffset)
    end

    local texturePath = (ns.LSM and ns.LSM.Fetch and ns.LSM:Fetch("statusbar", settings.barTexture or "Solid"))
        or "Interface\\Buttons\\WHITE8x8"
    frame.bar:SetStatusBarTexture(texturePath)
    local bc = settings.barColor or { 0.6, 0.2, 0.2, 1 }
    frame.bar:SetStatusBarColor(bc[1], bc[2], bc[3], bc[4] or 1)

    local fontSize = settings.fontSize or 13
    local fontName = settings.useCustomFont and settings.font or (QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general and QUICore.db.profile.general.font) or "Quazii"
    local fontPath = UIKit.ResolveFontPath(fontName)
    CJKFont(frame.label, fontPath, fontSize, "OUTLINE")
    local tc = settings.textColor or { 1, 1, 1, 1 }
    frame.label:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
    if settings.showLabel == false then frame.label:Hide() else frame.label:Show() end

    local borderSize = settings.borderSize or 1
    local bR, bG, bB, bA = Helpers.GetSkinBorderColor(settings, "")
    local bgColor = settings.backdropColor or { 0, 0, 0, 0.6 }
    frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.6)
    UIKit.CreateBorderLines(frame)
    UIKit.UpdateBorderLines(frame, borderSize, bR, bG, bB, bA, settings.hideBorder)
end

local function ShowFor(instanceID)
    local settings = GetSettings()
    if not settings or not settings.enabled then return end
    if State.isPreviewMode then return end
    CreateTimerFrame()
    UpdateAppearance()
    State.activeInstanceID = instanceID
    if not BindDuration(State.frame.bar, State.frame.count, instanceID) then
        if State.frame.count then State.frame.count:Clear() end
        State.frame.bar:SetMinMaxValues(0, 1)
        State.frame.bar:SetValue(1)
    end
    State.frame:Show()
end

local function HideTimer()
    State.activeInstanceID = nil
    if State.frame and not State.isPreviewMode then
        if State.frame.count then State.frame.count:Clear() end
        State.frame:Hide()
    end
end

local function ScanForLust()
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return end
    for spellID in pairs(LUST_SPELLS) do
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        aura = Helpers.SafeValue(aura)
        if ok and aura and aura.auraInstanceID then
            ShowFor(aura.auraInstanceID)
            return
        end
    end

    if State.activeInstanceID then
        local restricted = C_Secrets and C_Secrets.ShouldAurasBeSecret
            and C_Secrets.ShouldAurasBeSecret()
        if not restricted then
            HideTimer()
        end
    end
end

local function OnPlayerAura(_, info)
    local settings = GetSettings()
    if not settings or not settings.enabled then return end

    if info == nil then
        ScanForLust()
        return
    end

    if info.removedAuraInstanceIDs and State.activeInstanceID then
        for _, instID in ipairs(info.removedAuraInstanceIDs) do
            if instID == State.activeInstanceID then
                HideTimer()
                break
            end
        end
    end

    if info.addedAuras then
        for _, data in ipairs(info.addedAuras) do
            local sid = data and data.spellId
            local secret = issecretvalue and issecretvalue(sid)
            if sid and not secret and LUST_SPELLS[sid] and not SATED_SPELLS[sid] then
                ShowFor(data.auraInstanceID)
                break
            end
        end
    end
end

local function RefreshLustTimer()
    local settings = GetSettings()
    if (not settings or not settings.enabled) and not State.isPreviewMode then
        HideTimer()
        return
    end
    UpdateAppearance()
    if settings and settings.enabled and not State.isPreviewMode then
        ScanForLust()
    end
end

local function TogglePreview(enable)
    CreateTimerFrame()
    if not State.frame then return end
    State.isPreviewMode = enable
    if enable then
        UpdateAppearance()
        State.frame.bar:SetMinMaxValues(0, 1)
        State.frame.bar:SetValue(0.66)
        if State.frame.count then State.frame.count:Clear() end
        State.frame:Show()
    else
        local settings = GetSettings()
        if not (settings and settings.enabled and State.activeInstanceID) then
            State.frame:Hide()
        end
    end
end

local function IsPreviewMode()
    return State.isPreviewMode
end

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(function()
        CreateTimerFrame()
        if ns.AuraEvents and ns.AuraEvents.Subscribe then
            ns.AuraEvents:Subscribe("player", OnPlayerAura)
        end
        RefreshLustTimer()
    end)
end

local regenFrame = CreateFrame("Frame")
regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
regenFrame:SetScript("OnEvent", function()
    if State.activeInstanceID and not State.isPreviewMode then
        ScanForLust()
    end
end)

_G.QUI_RefreshLustTimer = RefreshLustTimer
_G.QUI_ToggleLustTimerPreview = TogglePreview

QUI.LustTimer = {
    Refresh = RefreshLustTimer,
    TogglePreview = TogglePreview,
    IsPreviewMode = IsPreviewMode,
}

if ns.Registry then
    ns.Registry:Register("lustTimer", {
        refresh = _G.QUI_RefreshLustTimer,
        priority = 40,
        group = "trackers",
        importCategories = { "trackersTimers" },
    })
    ns.Registry:Register("lustTimerSkin", {
        refresh = _G.QUI_RefreshLustTimer,
        priority = 40,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

if Helpers and Helpers.BorderRegistry then
    Helpers.BorderRegistry.Register({
        key = "lustTimer", label = "Lust Timer", category = "Trackers", prefix = "",
        db = function(p) return p.lustTimer end,
        refresh = function() if _G.QUI_RefreshLustTimer then _G.QUI_RefreshLustTimer() end end,
        legacy = { useClass = "useClassColorBorder", accent = "useAccentColorBorder" },
    })
end
