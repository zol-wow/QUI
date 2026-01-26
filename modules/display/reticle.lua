---------------------------------------------------------------------------
-- QUI Reticle Module
-- GCD tracker ring that follows the mouse cursor with center reticle
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local QUI = ns.QUI or {}
ns.QUI = QUI
local Helpers = ns.Helpers

-- Locals
local UIParent = UIParent
local CreateFrame = CreateFrame
local GetScaledCursorPosition = GetScaledCursorPosition
local InCombatLockdown = InCombatLockdown
local UnitClass = UnitClass
local C_ClassColor = C_ClassColor
local C_Spell = C_Spell
local GetTime = GetTime
local pcall = pcall
local type = type

-- Frame references
local ringFrame, ringTexture, reticleTexture, gcdCooldown

-- State tracking
local lastCombatState = nil
local cachedSettings = nil
local cursorUpdateEnabled = false  -- Track OnUpdate state for performance

-- Cached values for OnUpdate performance (avoid per-frame table lookups)
local cachedOffsetX, cachedOffsetY = 0, 0
local lastCursorX, lastCursorY = 0, 0

-- Forward declarations for cursor update functions
local EnableCursorUpdate, DisableCursorUpdate

-- GCD spell ID (standard global cooldown reference)
local GCD_SPELL_ID = 61304

---------------------------------------------------------------------------
-- Ring texture paths
---------------------------------------------------------------------------
local RING_TEXTURES = {
    thin     = "Interface\\AddOns\\QUI\\assets\\cursor\\qui_ring_thin.png",
    standard = "Interface\\AddOns\\QUI\\assets\\cursor\\qui_ring_standard.png",
    thick    = "Interface\\AddOns\\QUI\\assets\\cursor\\qui_ring_thick.png",
    solid    = "Interface\\AddOns\\QUI\\assets\\cursor\\qui_ring_solid.png",
}

-- Reticle options (mix of custom texture and Blizzard Atlas)
local RETICLE_OPTIONS = {
    dot     = { path = "Interface\\AddOns\\QUI\\assets\\cursor\\qui_reticle_dot.tga", isAtlas = false },
    cross   = { path = "uitools-icon-plus", isAtlas = true },
    chevron = { path = "uitools-icon-chevron-down", isAtlas = true },
    diamond = { path = "UF-SoulShard-FX-FrameGlow", isAtlas = true },
}

---------------------------------------------------------------------------
-- Get settings from database (cached for performance)
---------------------------------------------------------------------------
local function GetSettings()
    if cachedSettings then return cachedSettings end
    cachedSettings = Helpers.GetModuleDB("reticle")
    return cachedSettings
end

-- Cache invalidation (called on profile change)
local function InvalidateCache()
    cachedSettings = nil
end

-- Cache offsets for OnUpdate performance (called on settings change)
local function CacheOffsets()
    local settings = GetSettings()
    cachedOffsetX = settings and settings.offsetX or 0
    cachedOffsetY = settings and settings.offsetY or 0
end

---------------------------------------------------------------------------
-- Get color based on settings (class color or custom)
---------------------------------------------------------------------------
local function GetRingColor()
    local settings = GetSettings()
    if not settings then return 1, 1, 1, 1 end

    if settings.useClassColor then
        local _, classFile = UnitClass("player")
        local color = C_ClassColor.GetClassColor(classFile)
        if color then
            return color.r, color.g, color.b, 1
        end
        return 1, 1, 1, 1
    else
        local c = settings.customColor or {0.204, 0.827, 0.6, 1}
        return c[1] or 0.204, c[2] or 0.827, c[3] or 0.6, c[4] or 1
    end
end

---------------------------------------------------------------------------
-- Get alpha based on combat state
---------------------------------------------------------------------------
local function GetCurrentAlpha()
    local settings = GetSettings()
    if not settings then return 1 end

    if InCombatLockdown() then
        return settings.inCombatAlpha or 0.8
    else
        return settings.outCombatAlpha or 0.3
    end
end

---------------------------------------------------------------------------
-- Secret value protection for Midnight 12.0+
-- Wrap numeric comparisons in pcall to handle protected cooldown values
---------------------------------------------------------------------------
local function IsCooldownActive(start, duration)
    if not start or not duration then return false end

    local ok, result = pcall(function()
        if duration == 0 or start == 0 then
            return false
        end
        return true
    end)

    if not ok then
        -- Comparison threw error = secret value = cooldown is active
        return true
    end

    return result and true or false
end

---------------------------------------------------------------------------
-- Read spell cooldown (handles both 11.x and 12.0+ API formats)
---------------------------------------------------------------------------
local function ReadSpellCooldown(spellID)
    if C_Spell and C_Spell.GetSpellCooldown then
        local a, b, c, d = C_Spell.GetSpellCooldown(spellID)
        if type(a) == "table" then
            -- Midnight 12.0+ returns table
            local t = a
            local start = t.startTime or t.start
            local duration = t.duration
            local modRate = t.modRate
            return start, duration, modRate
        else
            -- 11.x returns tuple: start, duration, enable, modRate
            return a, b, d
        end
    end
    -- Fallback for older API
    if GetSpellCooldown then
        local s, d = GetSpellCooldown(spellID)
        return s, d, nil
    end
    return nil, nil, nil
end

---------------------------------------------------------------------------
-- Create the cursor ring frame and elements
---------------------------------------------------------------------------
local function CreateReticle()
    if ringFrame then return end

    -- Main frame (follows cursor)
    ringFrame = CreateFrame("Frame", "QUI_Reticle", UIParent)
    ringFrame:SetFrameStrata("TOOLTIP")
    ringFrame:EnableMouse(false)  -- CRITICAL: Don't block mouse clicks
    ringFrame:SetSize(80, 80)

    -- Ring texture (background layer)
    ringTexture = ringFrame:CreateTexture(nil, "BACKGROUND")
    ringTexture:SetAllPoints()

    -- GCD Cooldown overlay (Blizzard template handles animation)
    gcdCooldown = CreateFrame("Cooldown", nil, ringFrame, "CooldownFrameTemplate")
    gcdCooldown:SetAllPoints()
    gcdCooldown:EnableMouse(false)
    gcdCooldown:SetDrawSwipe(true)
    gcdCooldown:SetDrawEdge(false)
    gcdCooldown:SetHideCountdownNumbers(true)
    if gcdCooldown.SetDrawBling then gcdCooldown:SetDrawBling(false) end
    if gcdCooldown.SetUseCircularEdge then gcdCooldown:SetUseCircularEdge(true) end
    gcdCooldown:SetFrameLevel(ringFrame:GetFrameLevel() + 2)

    -- Reticle texture (overlay layer - always on top)
    reticleTexture = ringFrame:CreateTexture(nil, "OVERLAY")
    reticleTexture:SetPoint("CENTER", ringFrame, "CENTER", 0, 0)

    ringFrame:Hide()
end

---------------------------------------------------------------------------
-- Update reticle appearance (center dot/crosshair)
---------------------------------------------------------------------------
local function UpdateReticleDot()
    if not reticleTexture then return end

    local settings = GetSettings()
    if not settings then return end

    local style = settings.reticleStyle or "dot"
    local size = settings.reticleSize or 10
    local r, g, b, a = GetRingColor()

    local reticleInfo = RETICLE_OPTIONS[style] or RETICLE_OPTIONS.dot

    if reticleInfo.isAtlas then
        reticleTexture:SetAtlas(reticleInfo.path)
    else
        reticleTexture:SetTexture(reticleInfo.path)
    end

    reticleTexture:SetSize(size, size)
    reticleTexture:SetVertexColor(r, g, b, a)
end

---------------------------------------------------------------------------
-- Update ring appearance
---------------------------------------------------------------------------
local function UpdateRingAppearance()
    if not ringFrame or not ringTexture then return end

    local settings = GetSettings()
    if not settings then return end

    local style = settings.ringStyle or "standard"
    local size = settings.ringSize or 40
    local r, g, b, a = GetRingColor()

    -- Set ring texture
    local texturePath = RING_TEXTURES[style] or RING_TEXTURES.standard
    ringTexture:SetTexture(texturePath)
    ringTexture:SetVertexColor(r, g, b, 1)

    -- Calculate ring alpha based on combat and GCD state
    local baseAlpha = GetCurrentAlpha()
    local ringAlpha = baseAlpha

    -- If GCD is active and enabled, fade the ring
    if gcdCooldown and gcdCooldown:IsShown() and settings.gcdEnabled then
        local fadeAmount = settings.gcdFadeRing or 0.35
        ringAlpha = baseAlpha * (1 - fadeAmount)
    end

    ringTexture:SetAlpha(ringAlpha)

    -- Update frame size
    ringFrame:SetSize(size, size)

    -- Update GCD swipe styling
    if gcdCooldown and settings.gcdEnabled then
        if gcdCooldown.SetSwipeTexture then
            gcdCooldown:SetSwipeTexture(texturePath)
        end
        gcdCooldown:SetSwipeColor(r, g, b, baseAlpha)
        if gcdCooldown.SetReverse then
            gcdCooldown:SetReverse(settings.gcdReverse or false)
        end
    end
end

---------------------------------------------------------------------------
-- Update GCD cooldown display
---------------------------------------------------------------------------
local function UpdateGCDCooldown()
    if not gcdCooldown then return end

    local settings = GetSettings()
    if not settings or not settings.gcdEnabled then
        gcdCooldown:Hide()
        UpdateRingAppearance()
        return
    end

    local start, duration, modRate = ReadSpellCooldown(GCD_SPELL_ID)

    if IsCooldownActive(start, duration) then
        gcdCooldown:Show()
        if modRate then
            gcdCooldown:SetCooldown(start, duration, modRate)
        else
            gcdCooldown:SetCooldown(start, duration)
        end
    else
        gcdCooldown:Hide()
    end

    UpdateRingAppearance()
end

---------------------------------------------------------------------------
-- Update visibility based on settings and combat state
-- forcedInCombat: optional boolean to override InCombatLockdown() check
-- (used by combat event handlers to avoid timing issues)
---------------------------------------------------------------------------
local function UpdateVisibility(forcedInCombat)
    if not ringFrame then return end

    local settings = GetSettings()
    if not settings or not settings.enabled then
        ringFrame:Hide()
        DisableCursorUpdate()  -- Stop OnUpdate when disabled
        return
    end

    -- Use forced state if provided, otherwise query InCombatLockdown
    local inCombat = (forcedInCombat ~= nil) and forcedInCombat or InCombatLockdown()

    -- Check hide out of combat setting
    if settings.hideOutOfCombat and not inCombat then
        ringFrame:Hide()
        DisableCursorUpdate()  -- Stop OnUpdate when hidden
        return
    end

    ringFrame:Show()
    EnableCursorUpdate()  -- Start OnUpdate when visible
end

---------------------------------------------------------------------------
-- Main update function (called on settings change)
---------------------------------------------------------------------------
local function UpdateReticle()
    if not ringFrame then
        CreateReticle()
    end

    CacheOffsets()  -- Cache offset values for OnUpdate performance
    UpdateVisibility()
    UpdateReticleDot()
    UpdateRingAppearance()
    UpdateGCDCooldown()
end

---------------------------------------------------------------------------
-- Combat state handlers
---------------------------------------------------------------------------
local function OnCombatStart()
    UpdateVisibility(true)  -- Force: we ARE in combat
    UpdateRingAppearance()
    UpdateGCDCooldown()     -- Ensure GCD tracking starts
end

local function OnCombatEnd()
    UpdateVisibility(false)  -- Force: we are NOT in combat
    UpdateRingAppearance()
end

---------------------------------------------------------------------------
-- Right-click hide functionality
---------------------------------------------------------------------------
local function SetupRightClickHide()
    WorldFrame:HookScript("OnMouseDown", function(_, button)
        if button == "RightButton" then
            local settings = GetSettings()
            if settings and settings.hideOnRightClick and ringFrame then
                ringFrame:Hide()
            end
        end
    end)

    WorldFrame:HookScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            local settings = GetSettings()
            if settings and settings.enabled and settings.hideOnRightClick and ringFrame then
                -- Only show if settings allow
                if not settings.hideOutOfCombat or InCombatLockdown() then
                    ringFrame:Show()
                end
            end
        end
    end)
end

---------------------------------------------------------------------------
-- OnUpdate handler for cursor following
-- OPTIMIZED: No DB lookups, no ClearAllPoints, cursor delta check
-- Enable/disable is handled by UpdateVisibility(), not here
---------------------------------------------------------------------------
local function CursorOnUpdate(self, elapsed)
    local x, y = GetScaledCursorPosition()

    -- Skip if cursor hasn't moved (0.5 pixel threshold)
    local dx, dy = x - lastCursorX, y - lastCursorY
    if dx > -0.5 and dx < 0.5 and dy > -0.5 and dy < 0.5 then
        return
    end
    lastCursorX, lastCursorY = x, y

    -- Direct SetPoint (no ClearAllPoints - frame uses single anchor)
    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x + cachedOffsetX, y + cachedOffsetY)
end

EnableCursorUpdate = function()
    if cursorUpdateEnabled or not ringFrame then return end
    cursorUpdateEnabled = true
    ringFrame:SetScript("OnUpdate", CursorOnUpdate)
end

DisableCursorUpdate = function()
    if not cursorUpdateEnabled or not ringFrame then return end
    cursorUpdateEnabled = false
    ringFrame:SetScript("OnUpdate", nil)
end

local function SetupCursorFollowing()
    -- Initial setup - enable if reticle should be visible
    local settings = GetSettings()
    if settings and settings.enabled then
        EnableCursorUpdate()
    end
end

---------------------------------------------------------------------------
-- Initialize
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

eventFrame:SetScript("OnEvent", function(self, event, unit, _, spellID)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(1, function()
            CreateReticle()
            UpdateReticle()
            SetupCursorFollowing()
            SetupRightClickHide()
            lastCombatState = InCombatLockdown()
        end)

    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateReticle()

    elseif event == "PLAYER_REGEN_DISABLED" then
        OnCombatStart()

    elseif event == "PLAYER_REGEN_ENABLED" then
        OnCombatEnd()

    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "ACTIONBAR_UPDATE_COOLDOWN" then
        UpdateGCDCooldown()

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" and unit == "player" then
        local settings = GetSettings()
        if not settings or not settings.gcdEnabled then
            if gcdCooldown then gcdCooldown:Hide() end
            return
        end

        -- Check cooldown of cast spell, fall back to GCD spell
        if spellID then
            local start, duration, modRate = ReadSpellCooldown(spellID)
            if IsCooldownActive(start, duration) then
                if gcdCooldown then
                    gcdCooldown:Show()
                    if modRate then
                        gcdCooldown:SetCooldown(start, duration, modRate)
                    else
                        gcdCooldown:SetCooldown(start, duration)
                    end
                    UpdateRingAppearance()
                end
            else
                UpdateGCDCooldown()
            end
        else
            UpdateGCDCooldown()
        end
    end
end)

---------------------------------------------------------------------------
-- Global refresh function for GUI
---------------------------------------------------------------------------
_G.QUI_RefreshReticle = function()
    InvalidateCache()
    UpdateReticle()
end

---------------------------------------------------------------------------
-- Module API
---------------------------------------------------------------------------
QUI.Reticle = {
    Update = UpdateReticle,
    Create = CreateReticle,
    Refresh = UpdateReticle,
    InvalidateCache = InvalidateCache,
}
