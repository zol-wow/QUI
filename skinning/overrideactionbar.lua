local addonName, ns = ...

---------------------------------------------------------------------------
-- OVERRIDE ACTION BAR SKINNING (Compact style)
---------------------------------------------------------------------------

local FONT_FLAGS = "OUTLINE"
local BUTTON_SIZE = 40  -- Compact but usable button size
local BUTTON_SPACING = 3  -- Tight but readable spacing
local LEAVE_BUTTON_SIZE = 28  -- Visible leave button
local RESOURCE_BAR_WIDTH = 12  -- Slim vertical bar
local RESOURCE_BAR_HEIGHT = 40  -- Match button height

-- Get skinning colors
local function GetColors()
    local QUI = _G.QUI
    local sr, sg, sb, sa = 0.2, 1.0, 0.6, 1
    local bgr, bgg, bgb, bga = 0.05, 0.05, 0.05, 0.95

    if QUI and QUI.GetSkinColor then
        sr, sg, sb, sa = QUI:GetSkinColor()
    end
    if QUI and QUI.GetSkinBgColor then
        bgr, bgg, bgb, bga = QUI:GetSkinBgColor()
    end

    return sr, sg, sb, sa, bgr, bgg, bgb, bga
end

-- Style action button with QUI theme
local function StyleActionButton(button, index, sr, sg, sb, sa, bgr, bgg, bgb, bga)
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
    if not button.quiBackdrop then
        button.quiBackdrop = CreateFrame("Frame", nil, button, "BackdropTemplate")
        button.quiBackdrop:SetPoint("TOPLEFT", -1, 1)
        button.quiBackdrop:SetPoint("BOTTOMRIGHT", 1, -1)
        button.quiBackdrop:SetFrameLevel(button:GetFrameLevel())
        button.quiBackdrop:EnableMouse(false)
    end

    button.quiBackdrop:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    button.quiBackdrop:SetBackdropColor(bgr, bgg, bgb, 0.8)
    button.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)

    -- Hide default border/normal texture
    local normalTexture = button:GetNormalTexture()
    if normalTexture then normalTexture:SetAlpha(0) end

    -- Scale the icon to fit
    local icon = button.icon or button.Icon
    if icon then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- Trim edges
    end

    button.quiSkinColor = { sr, sg, sb, sa }
    button.quiStyled = true
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

    -- Hide entire pitch frame
    if bar.pitchFrame then
        bar.pitchFrame:Hide()
        bar.pitchFrame:SetAlpha(0)
    end

    -- Hide entire leave frame (we'll restyle the button)
    if bar.leaveFrame then
        bar.leaveFrame:SetAlpha(0)
        -- But keep LeaveButton visible
        if bar.LeaveButton then
            bar.LeaveButton:SetParent(bar)
            bar.LeaveButton:Show()
        end
    end

    -- Keep health bar and power bar but hide their Blizzard decorations
    -- (we'll restyle them as compact vertical bars)

    -- Hide XP bar
    if bar.xpBar then
        bar.xpBar:Hide()
        bar.xpBar:SetAlpha(0)
    end
end

-- Main skinning function
local function SkinOverrideActionBar()
    local QUICore = _G.QUI and _G.QUI.QUICore
    local settings = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general
    if not settings or not settings.skinOverrideActionBar then return end

    local bar = _G.OverrideActionBar
    if not bar or bar.quiSkinned then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetColors()

    -- Hide all Blizzard decorations
    HideBlizzardElements(bar)

    -- Calculate new compact size
    -- health bar + 6 buttons + spacing + leave button + power bar + padding
    local totalWidth = RESOURCE_BAR_WIDTH + BUTTON_SPACING + (BUTTON_SIZE * 6) + (BUTTON_SPACING * 5) + BUTTON_SPACING + LEAVE_BUTTON_SIZE + BUTTON_SPACING + RESOURCE_BAR_WIDTH + 16
    local totalHeight = BUTTON_SIZE + 8  -- padding

    -- Resize the bar
    bar:SetSize(totalWidth, totalHeight)

    -- Create main backdrop
    if not bar.quiBackdrop then
        bar.quiBackdrop = CreateFrame("Frame", nil, bar, "BackdropTemplate")
        bar.quiBackdrop:SetAllPoints()
        bar.quiBackdrop:SetFrameLevel(math.max(bar:GetFrameLevel() - 1, 0))
        bar.quiBackdrop:EnableMouse(false)
    end

    bar.quiBackdrop:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    bar.quiBackdrop:SetBackdropColor(bgr, bgg, bgb, bga)
    bar.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)

    -- Style and reposition spell buttons
    for i = 1, 6 do
        local button = bar["SpellButton" .. i]
        if button then
            StyleActionButton(button, i, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end

    -- Style leave button (compact, at the end)
    if bar.LeaveButton then
        local leaveBtn = bar.LeaveButton
        leaveBtn:SetSize(LEAVE_BUTTON_SIZE, LEAVE_BUTTON_SIZE)
        leaveBtn:ClearAllPoints()
        leaveBtn:SetPoint("LEFT", bar.SpellButton6, "RIGHT", BUTTON_SPACING + 4, 0)

        if not leaveBtn.quiBackdrop then
            leaveBtn.quiBackdrop = CreateFrame("Frame", nil, leaveBtn, "BackdropTemplate")
            leaveBtn.quiBackdrop:SetPoint("TOPLEFT", -1, 1)
            leaveBtn.quiBackdrop:SetPoint("BOTTOMRIGHT", 1, -1)
            leaveBtn.quiBackdrop:SetFrameLevel(leaveBtn:GetFrameLevel())
            leaveBtn.quiBackdrop:EnableMouse(false)
        end

        leaveBtn.quiBackdrop:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        leaveBtn.quiBackdrop:SetBackdropColor(0.6, 0.1, 0.1, 0.9)  -- Reddish for exit
        leaveBtn.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
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
        if not healthBar.quiBackdrop then
            healthBar.quiBackdrop = CreateFrame("Frame", nil, healthBar, "BackdropTemplate")
            healthBar.quiBackdrop:SetPoint("TOPLEFT", -1, 1)
            healthBar.quiBackdrop:SetPoint("BOTTOMRIGHT", 1, -1)
            healthBar.quiBackdrop:SetFrameLevel(healthBar:GetFrameLevel())
            healthBar.quiBackdrop:EnableMouse(false)
        end

        healthBar.quiBackdrop:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        healthBar.quiBackdrop:SetBackdropColor(bgr, bgg, bgb, 0.8)
        healthBar.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
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
        if not powerBar.quiBackdrop then
            powerBar.quiBackdrop = CreateFrame("Frame", nil, powerBar, "BackdropTemplate")
            powerBar.quiBackdrop:SetPoint("TOPLEFT", -1, 1)
            powerBar.quiBackdrop:SetPoint("BOTTOMRIGHT", 1, -1)
            powerBar.quiBackdrop:SetFrameLevel(powerBar:GetFrameLevel())
            powerBar.quiBackdrop:EnableMouse(false)
        end

        powerBar.quiBackdrop:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        powerBar.quiBackdrop:SetBackdropColor(bgr, bgg, bgb, 0.8)
        powerBar.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
    end

    bar.quiSkinned = true

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

-- Refresh colors
local function RefreshOverrideActionBarColors()
    local bar = _G.OverrideActionBar
    if not bar or not bar.quiSkinned then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetColors()

    -- Update main backdrop
    if bar.quiBackdrop then
        bar.quiBackdrop:SetBackdropColor(bgr, bgg, bgb, bga)
        bar.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
    end

    -- Update spell buttons
    for i = 1, 6 do
        local button = bar["SpellButton" .. i]
        if button and button.quiBackdrop then
            button.quiBackdrop:SetBackdropColor(bgr, bgg, bgb, 0.8)
            button.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
            button.quiSkinColor = { sr, sg, sb, sa }
        end
    end

    -- Update leave button
    if bar.LeaveButton and bar.LeaveButton.quiBackdrop then
        bar.LeaveButton.quiBackdrop:SetBackdropColor(0.6, 0.1, 0.1, 0.9)
        bar.LeaveButton.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
    end

    -- Update health bar
    if bar.healthBar and bar.healthBar.quiBackdrop then
        bar.healthBar.quiBackdrop:SetBackdropColor(bgr, bgg, bgb, 0.8)
        bar.healthBar.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
    end

    -- Update power bar
    if bar.powerBar and bar.powerBar.quiBackdrop then
        bar.powerBar.quiBackdrop:SetBackdropColor(bgr, bgg, bgb, 0.8)
        bar.powerBar.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
    end
end

-- Expose refresh function globally
_G.QUI_RefreshOverrideActionBarColors = RefreshOverrideActionBarColors

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------

local function SetupOverrideBarHooks()
    local bar = _G.OverrideActionBar
    if not bar or bar.quiHooked then return end

    -- Hook OnShow with delay to let Blizzard finish setup
    bar:HookScript("OnShow", function()
        C_Timer.After(0.15, SkinOverrideActionBar)
    end)

    -- If already visible, skin now
    if bar:IsShown() then
        C_Timer.After(0.15, SkinOverrideActionBar)
    end

    -- BUG-005: Hook UpdateMicroButtons to reset MicroMenu position persistently
    -- Blizzard calls this in OnShow and UpdateSkin, which can re-position MicroMenu
    -- after QUI's initial skinning. This hook ensures MicroMenu stays in normal position.
    -- Use C_Timer.After(0) to break taint chain from secure Blizzard code
    if bar.UpdateMicroButtons then
        hooksecurefunc(bar, "UpdateMicroButtons", function()
            if bar.quiSkinned and MicroMenu and MicroMenu.ResetMicroMenuPosition then
                C_Timer.After(0, function()
                    if not InCombatLockdown() then
                        MicroMenu:ResetMicroMenuPosition()
                    end
                end)
            end
        end)
    end

    bar.quiHooked = true
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" and addon == "Blizzard_OverrideActionBar" then
        SetupOverrideBarHooks()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Fallback: addon may already be loaded
        if _G.OverrideActionBar then
            SetupOverrideBarHooks()
        end
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
end)
