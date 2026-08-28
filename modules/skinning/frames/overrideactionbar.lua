local addonName, ns = ...

if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
local QUICore = ns.Addon
local SkinBase = ns.SkinBase
local Helpers = ns.Helpers

local BUTTON_SIZE = 40
local BUTTON_SPACING = 3
local LEAVE_BUTTON_SIZE = 28
local RESOURCE_BAR_WIDTH = 12
local RESOURCE_BAR_HEIGHT = 40
local pendingOverrideSkin = false
local pendingOverridePostUpdate = false
local overrideActionBarLifecycleHooked = false

local function StyleActionButton(button, index, sr, sg, sb, sa, bgr, bgg, bgb)
    if not button then return end

    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)

    button:ClearAllPoints()
    if index == 1 then
        button:SetPoint("LEFT", button:GetParent(), "LEFT", RESOURCE_BAR_WIDTH + BUTTON_SPACING + 4, 0)
    else
        local prevButton = button:GetParent()["SpellButton" .. (index - 1)]
        if prevButton then
            button:SetPoint("LEFT", prevButton, "RIGHT", BUTTON_SPACING, 0)
        end
    end

    local btnBd = SkinBase.GetFrameData(button, "backdrop")
    if not btnBd then
        btnBd = CreateFrame("Frame", nil, button, "BackdropTemplate")
        SkinBase.SetExpandedPixelPoints(btnBd, button, 1)
        btnBd:SetFrameLevel(button:GetFrameLevel())
        btnBd:EnableMouse(false)
        SkinBase.SetFrameData(button, "backdrop", btnBd)
    end

    SkinBase.ApplyPixelBackdrop(btnBd, 1, true, true)
    Helpers.SetFrameBackdropColor(btnBd, bgr, bgg, bgb, 0.8)
    Helpers.SetFrameBackdropBorderColor(btnBd, sr, sg, sb, sa)

    local normalTexture = button:GetNormalTexture()
    if normalTexture then normalTexture:SetAlpha(0) end
    if button.SlotArt then button.SlotArt:SetAlpha(0) end
    if button.SlotBackground then button.SlotBackground:SetAlpha(0) end

    if button.UpdateButtonArt and not SkinBase.GetFrameData(button, "qArtHooked") then
        hooksecurefunc(button, "UpdateButtonArt", function(self)
            if self.SlotArt then self.SlotArt:SetAlpha(0) end
            if self.SlotBackground then self.SlotBackground:SetAlpha(0) end
            local nt = self.GetNormalTexture and self:GetNormalTexture()
            if nt then nt:SetAlpha(0) end
        end)
        SkinBase.SetFrameData(button, "qArtHooked", true)
    end

    local icon = button.icon or button.Icon
    if icon then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    SkinBase.SetFrameData(button, "skinColor", { sr, sg, sb, sa })
    SkinBase.MarkStyled(button)
end

local function HideBlizzardElements(bar)
    local texturesToHide = {
        "_BG", "EndCapL", "EndCapR", "_Border",
        "Divider1", "Divider2", "Divider3",
        "ExitBG", "MicroBGL", "MicroBGR", "_MicroBGMid",
        "ButtonBGL", "ButtonBGR", "_ButtonBGMid",
        "PitchOverlay", "PitchButtonBG", "PitchBG", "PitchMarker",
        "HealthBarBG", "HealthBarOverlay",
        "PowerBarBG", "PowerBarOverlay",
    }

    for _, texName in ipairs(texturesToHide) do
        local tex = bar[texName]
        if tex and tex.SetAlpha then
            tex:SetAlpha(0)
        end
    end

    if bar.pitchFrame then
        bar.pitchFrame:SetAlpha(0)
    end

    if bar.xpBar then
        bar.xpBar:SetAlpha(0)
    end
end

local function SkinOverrideActionBar()
    if not QUICore or type(QUICore.GetPixelSize) ~= "function" then return end
    local settings = QUICore.db and QUICore.db.profile and QUICore.db.profile.general
    if not settings or not settings.skinOverrideActionBar then return end

    local bar = _G.OverrideActionBar
    if not bar then return end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        pendingOverrideSkin = true
        return
    end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors(settings, "overrideActionBar")

    HideBlizzardElements(bar)

    local totalWidth = RESOURCE_BAR_WIDTH + BUTTON_SPACING + (BUTTON_SIZE * 6) + (BUTTON_SPACING * 5) + BUTTON_SPACING + LEAVE_BUTTON_SIZE + BUTTON_SPACING + RESOURCE_BAR_WIDTH + 16
    local totalHeight = BUTTON_SIZE + 8

    bar:SetSize(totalWidth, totalHeight)

    local barBd = SkinBase.GetFrameData(bar, "backdrop")
    if not barBd then
        barBd = CreateFrame("Frame", nil, bar, "BackdropTemplate")
        barBd:SetAllPoints()
        barBd:SetFrameLevel(math.max(bar:GetFrameLevel() - 1, 0))
        barBd:EnableMouse(false)
        SkinBase.SetFrameData(bar, "backdrop", barBd)
    end

    SkinBase.ApplyPixelBackdrop(barBd, 1, true, true)
    Helpers.SetFrameBackdropColor(barBd, bgr, bgg, bgb, bga)
    Helpers.SetFrameBackdropBorderColor(barBd, sr, sg, sb, sa)

    for i = 1, 6 do
        local button = bar["SpellButton" .. i]
        if button then
            StyleActionButton(button, i, sr, sg, sb, sa, bgr, bgg, bgb)
        end
    end

    if bar.LeaveButton then
        local leaveBtn = bar.LeaveButton
        leaveBtn:SetSize(LEAVE_BUTTON_SIZE, LEAVE_BUTTON_SIZE)
        leaveBtn:ClearAllPoints()
        leaveBtn:SetPoint("LEFT", bar.SpellButton6, "RIGHT", BUTTON_SPACING + 4, 0)

        local leaveBd = SkinBase.GetFrameData(leaveBtn, "backdrop")
        if not leaveBd then
            leaveBd = CreateFrame("Frame", nil, leaveBtn, "BackdropTemplate")
            SkinBase.SetExpandedPixelPoints(leaveBd, leaveBtn, 1)
            leaveBd:SetFrameLevel(leaveBtn:GetFrameLevel())
            leaveBd:EnableMouse(false)
            SkinBase.SetFrameData(leaveBtn, "backdrop", leaveBd)
        end

        SkinBase.ApplyPixelBackdrop(leaveBd, 1, true, true)
        Helpers.SetFrameBackdropColor(leaveBd, 0.6, 0.1, 0.1, 0.9)
        Helpers.SetFrameBackdropBorderColor(leaveBd, sr, sg, sb, sa)
    end

    if bar.healthBar then
        local healthBar = bar.healthBar
        healthBar:Show()
        healthBar:SetAlpha(1)
        healthBar:SetOrientation("VERTICAL")
        healthBar:SetRotatesTexture(true)
        healthBar:SetSize(RESOURCE_BAR_WIDTH, RESOURCE_BAR_HEIGHT)
        healthBar:ClearAllPoints()
        healthBar:SetPoint("LEFT", bar, "LEFT", 4, 0)
        healthBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")

        local hbBd = SkinBase.GetFrameData(healthBar, "backdrop")
        if not hbBd then
            hbBd = CreateFrame("Frame", nil, healthBar, "BackdropTemplate")
            SkinBase.SetExpandedPixelPoints(hbBd, healthBar, 1)
            hbBd:SetFrameLevel(healthBar:GetFrameLevel())
            hbBd:EnableMouse(false)
            SkinBase.SetFrameData(healthBar, "backdrop", hbBd)
        end

        SkinBase.ApplyPixelBackdrop(hbBd, 1, true, true)
        Helpers.SetFrameBackdropColor(hbBd, bgr, bgg, bgb, 0.8)
        Helpers.SetFrameBackdropBorderColor(hbBd, sr, sg, sb, sa)
    end

    if bar.powerBar then
        local powerBar = bar.powerBar
        powerBar:Show()
        powerBar:SetAlpha(1)
        powerBar:SetOrientation("VERTICAL")
        powerBar:SetRotatesTexture(true)
        powerBar:SetSize(RESOURCE_BAR_WIDTH, RESOURCE_BAR_HEIGHT)
        powerBar:ClearAllPoints()
        powerBar:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
        powerBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")

        local pbBd = SkinBase.GetFrameData(powerBar, "backdrop")
        if not pbBd then
            pbBd = CreateFrame("Frame", nil, powerBar, "BackdropTemplate")
            SkinBase.SetExpandedPixelPoints(pbBd, powerBar, 1)
            pbBd:SetFrameLevel(powerBar:GetFrameLevel())
            pbBd:EnableMouse(false)
            SkinBase.SetFrameData(powerBar, "backdrop", pbBd)
        end

        SkinBase.ApplyPixelBackdrop(pbBd, 1, true, true)
        Helpers.SetFrameBackdropColor(pbBd, bgr, bgg, bgb, 0.8)
        Helpers.SetFrameBackdropBorderColor(pbBd, sr, sg, sb, sa)
    end

    SkinBase.MarkSkinned(bar)
end

local function RunOverrideActionBarPostUpdate()
    pendingOverridePostUpdate = false
    SkinOverrideActionBar()
end

local function DeferOverrideActionBarPostUpdate()
    if pendingOverridePostUpdate then return end
    pendingOverridePostUpdate = true
    -- FrameXML OverrideActionBarMixin:UpdateSkin resets skin, size, actionpage, buttons, and status bars.
    C_Timer.After(0, RunOverrideActionBarPostUpdate)
end

local function EnsureOverrideActionBarLifecycleHook(bar)
    if not bar or overrideActionBarLifecycleHooked or not bar.UpdateSkin then return end
    hooksecurefunc(bar, "UpdateSkin", function()
        DeferOverrideActionBarPostUpdate()
    end)
    overrideActionBarLifecycleHooked = true
end

local function RefreshOverrideActionBarColors()
    local bar = _G.OverrideActionBar
    if not bar or not SkinBase.IsSkinned(bar) then return end

    local settings = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors(settings, "overrideActionBar")

    local mainBd = SkinBase.GetFrameData(bar, "backdrop")
    if mainBd then
        Helpers.SetFrameBackdropColor(mainBd, bgr, bgg, bgb, bga)
        Helpers.SetFrameBackdropBorderColor(mainBd, sr, sg, sb, sa)
    end

    for i = 1, 6 do
        local button = bar["SpellButton" .. i]
        local spellBd = button and SkinBase.GetFrameData(button, "backdrop")
        if spellBd then
            Helpers.SetFrameBackdropColor(spellBd, bgr, bgg, bgb, 0.8)
            Helpers.SetFrameBackdropBorderColor(spellBd, sr, sg, sb, sa)
            SkinBase.SetFrameData(button, "skinColor", { sr, sg, sb, sa })
        end
    end

    local leaveBd = bar.LeaveButton and SkinBase.GetFrameData(bar.LeaveButton, "backdrop")
    if leaveBd then
        Helpers.SetFrameBackdropColor(leaveBd, 0.6, 0.1, 0.1, 0.9)
        Helpers.SetFrameBackdropBorderColor(leaveBd, sr, sg, sb, sa)
    end

    local healthBd = bar.healthBar and SkinBase.GetFrameData(bar.healthBar, "backdrop")
    if healthBd then
        Helpers.SetFrameBackdropColor(healthBd, bgr, bgg, bgb, 0.8)
        Helpers.SetFrameBackdropBorderColor(healthBd, sr, sg, sb, sa)
    end

    local powerBd = bar.powerBar and SkinBase.GetFrameData(bar.powerBar, "backdrop")
    if powerBd then
        Helpers.SetFrameBackdropColor(powerBd, bgr, bgg, bgb, 0.8)
        Helpers.SetFrameBackdropBorderColor(powerBd, sr, sg, sb, sa)
    end
end

_G.QUI_RefreshOverrideActionBarColors = RefreshOverrideActionBarColors

if ns.Registry then
    ns.Registry:Register("skinOverrideActionBar", {
        refresh = _G.QUI_RefreshOverrideActionBarColors,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

local function HandleBarStateChange()
    local bar = _G.OverrideActionBar
    if not bar then return end

    local settings = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general
    if not settings or not settings.skinOverrideActionBar then return end
    EnsureOverrideActionBarLifecycleHook(bar)

    if not bar:IsShown() then return end

    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        pendingOverrideSkin = true
        return
    end

    DeferOverrideActionBarPostUpdate()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")
frame:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR")
frame:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" then
        if addon == "Blizzard_OverrideActionBar" then
            HandleBarStateChange()
        end
    elseif event == "PLAYER_ENTERING_WORLD"
        or event == "UPDATE_VEHICLE_ACTIONBAR"
        or event == "UPDATE_OVERRIDE_ACTIONBAR" then
        HandleBarStateChange()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingOverrideSkin then
            pendingOverrideSkin = false
            HandleBarStateChange()
        end
    end
end)

if ns.WhenLoggedIn then ns.WhenLoggedIn(HandleBarStateChange) end
