local addonName, ns = ...
local QUICore = ns.Addon
local SkinBase = ns.SkinBase

---------------------------------------------------------------------------
-- OVERRIDE ACTION BAR SKINNING (Compact style)
---------------------------------------------------------------------------

local FONT_FLAGS = "OUTLINE"
local BUTTON_SIZE = 40  -- Compact but usable button size
local BUTTON_SPACING = 3  -- Tight but readable spacing
local LEAVE_BUTTON_SIZE = 28  -- Visible leave button
local RESOURCE_BAR_WIDTH = 12  -- Slim vertical bar
local RESOURCE_BAR_HEIGHT = 40  -- Match button height
local pendingOverrideSkin = false

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
    local btnBd = SkinBase.GetFrameData(button, "backdrop")
    if not btnBd then
        btnBd = CreateFrame("Frame", nil, button, "BackdropTemplate")
        btnBd:SetPoint("TOPLEFT", -1, 1)
        btnBd:SetPoint("BOTTOMRIGHT", 1, -1)
        btnBd:SetFrameLevel(button:GetFrameLevel())
        btnBd:EnableMouse(false)
        SkinBase.SetFrameData(button, "backdrop", btnBd)
    end

    local px = QUICore:GetPixelSize(btnBd)
    btnBd:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
        insets = { left = px, right = px, top = px, bottom = px }
    })
    btnBd:SetBackdropColor(bgr, bgg, bgb, 0.8)
    btnBd:SetBackdropBorderColor(sr, sg, sb, sa)

    -- Hide default border/normal texture
    local normalTexture = button:GetNormalTexture()
    if normalTexture then normalTexture:SetAlpha(0) end

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
    if not QUICore or type(QUICore.GetPixelSize) ~= "function" then return end
    local settings = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general
    if not settings or not settings.skinOverrideActionBar then return end

    local bar = _G.OverrideActionBar
    if not bar or SkinBase.IsSkinned(bar) then return end
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

    local barPx = QUICore:GetPixelSize(barBd)
    barBd:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = barPx,
        insets = { left = barPx, right = barPx, top = barPx, bottom = barPx }
    })
    barBd:SetBackdropColor(bgr, bgg, bgb, bga)
    barBd:SetBackdropBorderColor(sr, sg, sb, sa)

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

        local leaveBd = SkinBase.GetFrameData(leaveBtn, "backdrop")
        if not leaveBd then
            leaveBd = CreateFrame("Frame", nil, leaveBtn, "BackdropTemplate")
            leaveBd:SetPoint("TOPLEFT", -1, 1)
            leaveBd:SetPoint("BOTTOMRIGHT", 1, -1)
            leaveBd:SetFrameLevel(leaveBtn:GetFrameLevel())
            leaveBd:EnableMouse(false)
            SkinBase.SetFrameData(leaveBtn, "backdrop", leaveBd)
        end

        local lbPx = QUICore:GetPixelSize(leaveBd)
        leaveBd:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = lbPx,
            insets = { left = lbPx, right = lbPx, top = lbPx, bottom = lbPx }
        })
        leaveBd:SetBackdropColor(0.6, 0.1, 0.1, 0.9)  -- Reddish for exit
        leaveBd:SetBackdropBorderColor(sr, sg, sb, sa)
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
            hbBd:SetPoint("TOPLEFT", -1, 1)
            hbBd:SetPoint("BOTTOMRIGHT", 1, -1)
            hbBd:SetFrameLevel(healthBar:GetFrameLevel())
            hbBd:EnableMouse(false)
            SkinBase.SetFrameData(healthBar, "backdrop", hbBd)
        end

        local hbPx = QUICore:GetPixelSize(hbBd)
        hbBd:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = hbPx,
            insets = { left = hbPx, right = hbPx, top = hbPx, bottom = hbPx }
        })
        hbBd:SetBackdropColor(bgr, bgg, bgb, 0.8)
        hbBd:SetBackdropBorderColor(sr, sg, sb, sa)
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
            pbBd:SetPoint("TOPLEFT", -1, 1)
            pbBd:SetPoint("BOTTOMRIGHT", 1, -1)
            pbBd:SetFrameLevel(powerBar:GetFrameLevel())
            pbBd:EnableMouse(false)
            SkinBase.SetFrameData(powerBar, "backdrop", pbBd)
        end

        local pbPx = QUICore:GetPixelSize(pbBd)
        pbBd:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = pbPx,
            insets = { left = pbPx, right = pbPx, top = pbPx, bottom = pbPx }
        })
        pbBd:SetBackdropColor(bgr, bgg, bgb, 0.8)
        pbBd:SetBackdropBorderColor(sr, sg, sb, sa)
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

-- Refresh colors
local function RefreshOverrideActionBarColors()
    local bar = _G.OverrideActionBar
    if not bar or not SkinBase.IsSkinned(bar) then return end

    local settings = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors(settings, "overrideActionBar")

    -- Update main backdrop
    local mainBd = SkinBase.GetFrameData(bar, "backdrop")
    if mainBd then
        mainBd:SetBackdropColor(bgr, bgg, bgb, bga)
        mainBd:SetBackdropBorderColor(sr, sg, sb, sa)
    end

    -- Update spell buttons
    for i = 1, 6 do
        local button = bar["SpellButton" .. i]
        local spellBd = button and SkinBase.GetFrameData(button, "backdrop")
        if spellBd then
            spellBd:SetBackdropColor(bgr, bgg, bgb, 0.8)
            spellBd:SetBackdropBorderColor(sr, sg, sb, sa)
            SkinBase.SetFrameData(button, "skinColor", { sr, sg, sb, sa })
        end
    end

    -- Update leave button
    local leaveBd = bar.LeaveButton and SkinBase.GetFrameData(bar.LeaveButton, "backdrop")
    if leaveBd then
        leaveBd:SetBackdropColor(0.6, 0.1, 0.1, 0.9)
        leaveBd:SetBackdropBorderColor(sr, sg, sb, sa)
    end

    -- Update health bar
    local healthBd = bar.healthBar and SkinBase.GetFrameData(bar.healthBar, "backdrop")
    if healthBd then
        healthBd:SetBackdropColor(bgr, bgg, bgb, 0.8)
        healthBd:SetBackdropBorderColor(sr, sg, sb, sa)
    end

    -- Update power bar
    local powerBd = bar.powerBar and SkinBase.GetFrameData(bar.powerBar, "backdrop")
    if powerBd then
        powerBd:SetBackdropColor(bgr, bgg, bgb, 0.8)
        powerBd:SetBackdropBorderColor(sr, sg, sb, sa)
    end
end

-- Expose refresh function globally
_G.QUI_RefreshOverrideActionBarColors = RefreshOverrideActionBarColors

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------

local function SetupOverrideBarHooks()
    local bar = _G.OverrideActionBar
    if not bar or SkinBase.GetFrameData(bar, "hooked") then return end

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
    -- TAINT SAFETY: Defer ALL addon logic to break taint chain from secure context.
    if bar.UpdateMicroButtons then
        hooksecurefunc(bar, "UpdateMicroButtons", function()
            C_Timer.After(0, function()
                if SkinBase.IsSkinned(bar) and MicroMenu and MicroMenu.ResetMicroMenuPosition then
                    if not InCombatLockdown() then
                        MicroMenu:ResetMicroMenuPosition()
                    end
                end
            end)
        end)
    end

    SkinBase.SetFrameData(bar, "hooked", true)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" and addon == "Blizzard_OverrideActionBar" then
        SetupOverrideBarHooks()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Fallback: addon may already be loaded
        if _G.OverrideActionBar then
            SetupOverrideBarHooks()
        end
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingOverrideSkin then
            pendingOverrideSkin = false
            C_Timer.After(0, SkinOverrideActionBar)
        end
    end
end)
