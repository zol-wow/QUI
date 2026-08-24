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

local LUST_SPELLS = {
    [2825]   = true,
    [32182]  = true,
    [80353]  = true,
    [264667] = true,
    [390386] = true,
    [466904] = true,
}

local State = {
    frame = nil,
    container = nil,
    slot = nil,
    preview = nil,
    isPreviewMode = false,
}

local GetSettings = Helpers.CreateDBGetter("lustTimer")

local function BuildTimerSurface(frame, bindDuration)
    local border = frame:CreateTexture(nil, "BACKGROUND", nil, -2)
    border:SetAllPoints(frame)
    frame.border = border

    local backdrop = frame:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints(frame)
    frame.backdrop = backdrop

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

    if bindDuration then
        frame:SetDurationBar(bar, {
            direction = Enum.StatusBarTimerDirection.RemainingTime,
            interpolation = Enum.StatusBarInterpolation.Immediate,
        })
        frame:SetDurationCooldown(count)
    end
end

local function CreateTimerFrame()
    if State.frame then return end

    local frame = CreateFrame("Frame", "QUI_LustTimer", UIParent)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
    frame:SetSize(160, 22)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(50)

    local container = CreateFrame("AuraContainer", nil, frame, "CustomAuraContainerTemplate")
    container:SetAllPoints(frame)
    container:Hide()
    container:SetUnit("player")
    local slot = container:AddAuraSlot("lust", "HELPFUL", {
        candidateFilters = { includeSpellIDs = LUST_SPELLS },
        initializeFrame = function(button)
            button:SetAllPoints(button:GetParent())
            BuildTimerSurface(button, true)
        end,
    })

    local preview = CreateFrame("Frame", nil, frame)
    preview:SetAllPoints(frame)
    preview:SetFrameLevel(frame:GetFrameLevel() + 3)
    BuildTimerSurface(preview, false)
    preview.bar:SetValue(0.66)
    preview:Hide()

    frame:Hide()
    State.frame = frame
    State.container = container
    State.slot = slot
    State.preview = preview
end

local function UpdateSurfaceAppearance(frame, settings)
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
    local bgAlpha = settings.showBackdrop == false and 0 or (bgColor[4] or 0.6)
    local inset = settings.hideBorder and 0 or UIKit.Pixels(borderSize, frame)
    frame.border:SetColorTexture(bR, bG, bB, bA)
    frame.border:SetShown(inset > 0)
    frame.backdrop:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgAlpha)
    frame.backdrop:ClearAllPoints()
    frame.bar:ClearAllPoints()
    if inset > 0 then
        frame.backdrop:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
        frame.backdrop:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
        frame.bar:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
        frame.bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
    else
        frame.backdrop:SetAllPoints(frame)
        frame.bar:SetAllPoints(frame)
    end
end

local function RefreshLustTimer()
    CreateTimerFrame()
    local settings = GetSettings()
    if not settings then return end

    local frame = State.frame
    frame:SetSize(settings.width or 160, settings.height or 22)
    if not (_G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("lustTimer")) then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", settings.xOffset or 0, settings.yOffset or -120)
    end

    local restricted = C_Secrets and C_Secrets.ShouldAurasBeSecret
        and C_Secrets.ShouldAurasBeSecret()
    if restricted then
        if ns.AuraGlue and ns.AuraGlue.QueueRegenWork then
            ns.AuraGlue.QueueRegenWork(frame, RefreshLustTimer)
        end
    else
        UpdateSurfaceAppearance(State.slot, settings)
    end
    UpdateSurfaceAppearance(State.preview, settings)

    local live = settings.enabled == true and not State.isPreviewMode
    State.preview:SetShown(State.isPreviewMode)
    State.container:SetEnabled(live)
    State.container:SetShown(live)
    frame:SetShown(live or State.isPreviewMode)
end

local function TogglePreview(enable)
    CreateTimerFrame()
    State.isPreviewMode = enable == true
    RefreshLustTimer()
end

local function IsPreviewMode()
    return State.isPreviewMode
end

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(function()
        RefreshLustTimer()
    end)
end

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
