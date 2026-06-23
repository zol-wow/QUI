local addonName, ns = ...
local QUICore = ns.Addon
local SkinBase = ns.SkinBase
local Helpers = ns.Helpers

---------------------------------------------------------------------------
-- OVERRIDE ACTION BAR SKINNING (Compact style)
---------------------------------------------------------------------------

local BUTTON_SIZE = 40  -- Compact but usable button size
local BUTTON_SPACING = 3  -- Tight but readable spacing
local LEAVE_BUTTON_SIZE = 28  -- Visible leave button
local RESOURCE_BAR_WIDTH = 12  -- Slim vertical bar
local RESOURCE_BAR_HEIGHT = 40  -- Match button height
local pendingOverrideSkin = false
local pendingOverridePostUpdate = false
local overrideActionBarLifecycleHooked = false

-- Style action button with QUI theme
local function StyleActionButton(button, index, sr, sg, sb, sa, bgr, bgg, bgb)
    if not button then return end

    -- Resize button
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)

    -- Clear existing anchors and reposition (after resource bar)
    button:ClearAllPoints()
    if index == 1 then
        button:SetPoint("LEFT", button:GetParent(), "LEFT", RESOURCE_BAR_WIDTH + BUTTON_SPACING + 4, 0)
    else
        local prevButton = button:GetParent()["SpellButton" .. (index - 1)]
        if prevButton then
            button:SetPoint("LEFT", prevButton, "RIGHT", BUTTON_SPACING, 0)
        end
    end

    -- Create backdrop
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

    -- Hide default border/normal texture + Mainline icon-frame slot art
    local normalTexture = button:GetNormalTexture()
    if normalTexture then normalTexture:SetAlpha(0) end
    if button.SlotArt then button.SlotArt:SetAlpha(0) end
    if button.SlotBackground then button.SlotBackground:SetAlpha(0) end

    -- BaseActionButtonMixin:UpdateButtonArt re-shows SlotArt/SlotBackground and
    -- re-SetNormalAtlas's (resetting alpha) on every state Update. Re-suppress after
    -- it, per-button (scoped — never hook the shared mixin), once-guarded.
    if button.UpdateButtonArt and not SkinBase.GetFrameData(button, "qArtHooked") then
        hooksecurefunc(button, "UpdateButtonArt", function(self)
            if self.SlotArt then self.SlotArt:SetAlpha(0) end
            if self.SlotBackground then self.SlotBackground:SetAlpha(0) end
            local nt = self.GetNormalTexture and self:GetNormalTexture()
            if nt then nt:SetAlpha(0) end
        end)
        SkinBase.SetFrameData(button, "qArtHooked", true)
    end

    -- Scale the icon to fit
    local icon = button.icon or button.Icon
    if icon then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- Trim edges
    end

    SkinBase.SetFrameData(button, "skinColor", { sr, sg, sb, sa })
    SkinBase.MarkStyled(button)
end

-- Hide ALL Blizzard decorative elements
local function HideBlizzardElements(bar)
    -- Main decorative textures
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

    -- Hide entire pitch frame (SetAlpha only — Hide() taints the protected bar hierarchy)
    if bar.pitchFrame then
        bar.pitchFrame:SetAlpha(0)
    end

    -- Hide entire leave frame (we'll restyle the button)
    if bar.leaveFrame then
        bar.leaveFrame:SetAlpha(0)
        -- But keep LeaveButton visible without reparenting protected hierarchy
        if bar.LeaveButton then
            bar.LeaveButton:Show()
        end
    end

    -- Keep health bar and power bar but hide their Blizzard decorations
    -- (we'll restyle them as compact vertical bars)

    -- Hide XP bar (SetAlpha only — Hide() taints the protected bar hierarchy)
    if bar.xpBar then
        bar.xpBar:SetAlpha(0)
    end
end

-- Main skinning function
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

    -- Hide all Blizzard decorations
    HideBlizzardElements(bar)

    -- Calculate new compact size
    -- health bar + 6 buttons + spacing + leave button + power bar + padding
    local totalWidth = RESOURCE_BAR_WIDTH + BUTTON_SPACING + (BUTTON_SIZE * 6) + (BUTTON_SPACING * 5) + BUTTON_SPACING + LEAVE_BUTTON_SIZE + BUTTON_SPACING + RESOURCE_BAR_WIDTH + 16
    local totalHeight = BUTTON_SIZE + 8  -- padding

    -- Resize the bar
    bar:SetSize(totalWidth, totalHeight)

    -- Create main backdrop
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

    -- Style and reposition spell buttons
    for i = 1, 6 do
        local button = bar["SpellButton" .. i]
        if button then
            StyleActionButton(button, i, sr, sg, sb, sa, bgr, bgg, bgb)
        end
    end

    -- Style leave button (compact, at the end)
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
        Helpers.SetFrameBackdropColor(leaveBd, 0.6, 0.1, 0.1, 0.9)  -- Reddish for exit
        Helpers.SetFrameBackdropBorderColor(leaveBd, sr, sg, sb, sa)
    end

    -- Style and reposition health bar (vertical, on the left)
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

        -- Create backdrop for health bar
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

    -- Style and reposition power bar (vertical, on the right)
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

        -- Create backdrop for power bar
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

    -- BUG-005: Reset MicroMenu to normal position after skinning
    -- Blizzard's UpdateMicroButtons() positions MicroMenu using hardcoded offsets (x=648+)
    -- based on the default bar size. After QUI resizes the bar to ~332px, those offsets
    -- place MicroMenu outside the visible bar area. Reset it to its normal container.
    -- Use C_Timer.After(0) to avoid taint from secure code execution
    if MicroMenu and MicroMenu.ResetMicroMenuPosition then
        C_Timer.After(0, function()
            if not InCombatLockdown() then
                MicroMenu:ResetMicroMenuPosition()
            end
        end)
    end
end

local function RunOverrideActionBarPostUpdate()
    pendingOverridePostUpdate = false
    SkinOverrideActionBar()
    -- BUG-005: Blizzard's UpdateMicroButtons (called from OnShow/UpdateSkin)
    -- re-positions MicroMenu using hardcoded offsets that no longer match
    -- our compact bar size. Reset position here on every bar-state event.
    if MicroMenu and MicroMenu.ResetMicroMenuPosition and not InCombatLockdown() then
        MicroMenu:ResetMicroMenuPosition()
    end
end

local function DeferOverrideActionBarPostUpdate()
    if pendingOverridePostUpdate then return end
    pendingOverridePostUpdate = true
    -- FrameXML OverrideActionBarMixin:UpdateSkin resets skin, size, actionpage, buttons, and status bars.
    -- One frame exits the protected controller/update stack without HookScript
    -- or animation-group hooks on the protected bar.
    C_Timer.After(0, RunOverrideActionBarPostUpdate)
end

local function EnsureOverrideActionBarLifecycleHook(bar)
    if not bar or overrideActionBarLifecycleHooked or not bar.UpdateSkin then return end
    hooksecurefunc(bar, "UpdateSkin", function()
        DeferOverrideActionBarPostUpdate()
    end)
    overrideActionBarLifecycleHooked = true
end

-- Refresh colors
local function RefreshOverrideActionBarColors()
    local bar = _G.OverrideActionBar
    if not bar or not SkinBase.IsSkinned(bar) then return end

    local settings = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors(settings, "overrideActionBar")

    -- Update main backdrop
    local mainBd = SkinBase.GetFrameData(bar, "backdrop")
    if mainBd then
        Helpers.SetFrameBackdropColor(mainBd, bgr, bgg, bgb, bga)
        Helpers.SetFrameBackdropBorderColor(mainBd, sr, sg, sb, sa)
    end

    -- Update spell buttons
    for i = 1, 6 do
        local button = bar["SpellButton" .. i]
        local spellBd = button and SkinBase.GetFrameData(button, "backdrop")
        if spellBd then
            Helpers.SetFrameBackdropColor(spellBd, bgr, bgg, bgb, 0.8)
            Helpers.SetFrameBackdropBorderColor(spellBd, sr, sg, sb, sa)
            SkinBase.SetFrameData(button, "skinColor", { sr, sg, sb, sa })
        end
    end

    -- Update leave button
    local leaveBd = bar.LeaveButton and SkinBase.GetFrameData(bar.LeaveButton, "backdrop")
    if leaveBd then
        Helpers.SetFrameBackdropColor(leaveBd, 0.6, 0.1, 0.1, 0.9)
        Helpers.SetFrameBackdropBorderColor(leaveBd, sr, sg, sb, sa)
    end

    -- Update health bar
    local healthBd = bar.healthBar and SkinBase.GetFrameData(bar.healthBar, "backdrop")
    if healthBd then
        Helpers.SetFrameBackdropColor(healthBd, bgr, bgg, bgb, 0.8)
        Helpers.SetFrameBackdropBorderColor(healthBd, sr, sg, sb, sa)
    end

    -- Update power bar
    local powerBd = bar.powerBar and SkinBase.GetFrameData(bar.powerBar, "backdrop")
    if powerBd then
        Helpers.SetFrameBackdropColor(powerBd, bgr, bgg, bgb, 0.8)
        Helpers.SetFrameBackdropBorderColor(powerBd, sr, sg, sb, sa)
    end
end

-- Expose refresh function globally
_G.QUI_RefreshOverrideActionBarColors = RefreshOverrideActionBarColors

if ns.Registry then
    ns.Registry:Register("skinOverrideActionBar", {
        refresh = _G.QUI_RefreshOverrideActionBarColors,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

---------------------------------------------------------------------------
-- INITIALIZATION
--
-- TAINT SAFETY: We deliberately do NOT install HookScript("OnShow") or
-- HookScript on animation groups on OverrideActionBar — those taint the
-- protected bar and cause ADDON_ACTION_BLOCKED inside Blizzard's
-- BeginActionBarTransition → Show() during combat. Same pattern as the
-- Send/Open Mail mover fix: a separate watcher frame listens for state
-- events and triggers skinning, so the bar itself stays untainted.
---------------------------------------------------------------------------

local function HandleBarStateChange()
    local bar = _G.OverrideActionBar
    if not bar then return end
    EnsureOverrideActionBarLifecycleHook(bar)

    local settings = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general
    if not settings or not settings.skinOverrideActionBar then return end

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

-- LOD catch-up: first PEW already fired before this module loads. Also covers
-- Blizzard_OverrideActionBar having loaded before us (same code path).
-- ns.WhenLoggedIn is nil only in the headless test harness.
if ns.WhenLoggedIn then ns.WhenLoggedIn(HandleBarStateChange) end
