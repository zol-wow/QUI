-- customglows.lua
-- Custom glow effects for Essential and Utility cooldown viewers
-- Uses Blizzard's SpellActivationAlert system for proper sizing
-- Falls back to LibCustomGlow for additional glow styles

local _, ns = ...
local Helpers = ns.Helpers

-- Get LibCustomGlow for fallback styles
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

-- Get IsSpellOverlayed API for reliable glow state detection
local IsSpellOverlayed = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed

-- Track which icons currently have active glows
local activeGlowIcons = {}  -- [icon] = true

-- Glow templates for proc effects
local GlowTemplates = {
    LoopGlow = {
        {
            name = "Default Blizzard Glow",
            atlas = "UI-HUD-ActionBar-Proc-Loop-Flipbook",
            rows = 6, columns = 5, frames = 30, duration = 1.0,
        },
        {
            name = "Blue Assist Glow",
            atlas = "RotationHelper-ProcLoopBlue-Flipbook",
            rows = 6, columns = 5, frames = 30, duration = 1.0,
        },
        {
            name = "Classic Ants",
            texture = "Interface\\SpellActivationOverlay\\IconAlertAnts",
            rows = 5, columns = 5, frames = 25, duration = 0.8,
        },
    },
}

-- ======================================================
-- Settings Access
-- ======================================================
local function GetSettings()
    return Helpers.GetModuleDB("customGlow")
end

local function GetEffectsSettings()
    return Helpers.GetModuleSettings("cooldownEffects", { hideEssential = true, hideUtility = true })
end

-- ======================================================
-- Determine viewer type from icon
-- ======================================================
local function GetViewerType(icon)
    if not icon then return nil end
    
    local parent = icon:GetParent()
    if not parent then return nil end
    
    local parentName = parent:GetName()
    if not parentName then return nil end
    
    if parentName:find("EssentialCooldown") then
        return "Essential"
    elseif parentName:find("UtilityCooldown") then
        return "Utility"
    end
    
    return nil
end

-- ======================================================
-- Get settings for viewer type
-- ======================================================
local function GetViewerSettings(viewerType)
    local settings = GetSettings()
    if not settings then return nil end

    local effectsSettings = GetEffectsSettings()

    if viewerType == "Essential" then
        if not effectsSettings.hideEssential then return nil end
        if not settings.essentialEnabled then return nil end
        local glowType = settings.essentialGlowType or "Pixel Glow"
        if glowType == "Proc Glow" then glowType = "Pixel Glow" end
        return {
            enabled = true,
            glowType = glowType,
            color = settings.essentialColor or {0.95, 0.95, 0.32, 1},
            lines = settings.essentialLines or 14,
            frequency = settings.essentialFrequency or 0.25,
            thickness = settings.essentialThickness or 2,
            scale = settings.essentialScale or 1,
            xOffset = settings.essentialXOffset or 0,
            yOffset = settings.essentialYOffset or 0,
        }
    elseif viewerType == "Utility" then
        if not effectsSettings.hideUtility then return nil end
        if not settings.utilityEnabled then return nil end
        local glowType = settings.utilityGlowType or "Pixel Glow"
        if glowType == "Proc Glow" then glowType = "Pixel Glow" end
        return {
            enabled = true,
            glowType = glowType,
            color = settings.utilityColor or {0.95, 0.95, 0.32, 1},
            lines = settings.utilityLines or 14,
            frequency = settings.utilityFrequency or 0.25,
            thickness = settings.utilityThickness or 2,
            scale = settings.utilityScale or 1,
            xOffset = settings.utilityXOffset or 0,
            yOffset = settings.utilityYOffset or 0,
        }
    end

    return nil
end

-- ======================================================
-- Customize Blizzard's SpellActivationAlert
-- ======================================================
local function CustomizeBlizzardGlow(button, viewerSettings)
    if not button then return false end
    
    local region = button.SpellActivationAlert
    if not region then return false end
    
    -- Get the loop flipbook texture
    local loopFlipbook = region.ProcLoopFlipbook
    if not loopFlipbook then return false end
    
    -- Apply custom color
    local color = viewerSettings.color or {0.95, 0.95, 0.32, 1}
    loopFlipbook:SetDesaturated(true)  -- Desaturate first so color applies properly
    loopFlipbook:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    
    -- Also color the start flipbook if it exists
    local startFlipbook = region.ProcStartFlipbook
    if startFlipbook then
        startFlipbook:SetDesaturated(true)
        startFlipbook:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    end
    
    -- Mark as customized
    button._QUICustomGlowActive = true
    activeGlowIcons[button] = true
    
    return true
end

-- ======================================================
-- LibCustomGlow application (supports 3 glow types)
-- ======================================================
local function ApplyLibCustomGlow(icon, viewerSettings)
    if not LCG then return false end
    if not icon then return false end

    local glowType = viewerSettings.glowType
    local color = viewerSettings.color
    local lines = viewerSettings.lines
    local frequency = viewerSettings.frequency
    local thickness = viewerSettings.thickness
    local scale = viewerSettings.scale or 1
    local xOffset = viewerSettings.xOffset or 0
    local yOffset = viewerSettings.yOffset or 0

    -- Stop any existing glow first
    StopGlow(icon)

    if glowType == "Pixel Glow" then
        -- Pixel Glow: animated lines around the border
        -- Parameters: frame, color, numLines, frequency, length, thickness, xOffset, yOffset, border, key
        LCG.PixelGlow_Start(icon, color, lines, frequency, nil, thickness, 0, 0, true, "_QUICustomGlow")
        local glowFrame = icon["_PixelGlow_QUICustomGlow"]
        if glowFrame then
            glowFrame:ClearAllPoints()
            -- Apply offset: negative expands outward, positive shrinks inward
            glowFrame:SetPoint("TOPLEFT", icon, "TOPLEFT", -xOffset, xOffset)
            glowFrame:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", xOffset, -xOffset)
        end

    elseif glowType == "Autocast Shine" then
        -- Autocast Shine: orbiting sparkle spots
        -- Parameters: frame, color, numSpots, frequency, scale, xOffset, yOffset, key
        LCG.AutoCastGlow_Start(icon, color, lines, frequency, scale, 0, 0, "_QUICustomGlow")
        local glowFrame = icon["_AutoCastGlow_QUICustomGlow"]
        if glowFrame then
            glowFrame:ClearAllPoints()
            glowFrame:SetPoint("TOPLEFT", icon, "TOPLEFT", -xOffset, xOffset)
            glowFrame:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", xOffset, -xOffset)
        end
    end

    -- Flag already set by StartGlow, just ensure it's there
    icon._QUICustomGlowActive = true
    activeGlowIcons[icon] = true

    return true
end

-- ======================================================
-- Main glow application function
-- ======================================================
local function StartGlow(icon)
    if not icon then return end
    
    -- Already has our glow? Skip
    if icon._QUICustomGlowActive then return end
    
    local viewerType = GetViewerType(icon)
    if not viewerType then return end
    
    local viewerSettings = GetViewerSettings(viewerType)
    if not viewerSettings then return end
    
    -- Always use LibCustomGlow since we hide Blizzard's SpellActivationAlert
    -- Set the flag FIRST so cooldowneffects.lua doesn't interfere
    icon._QUICustomGlowActive = true
    activeGlowIcons[icon] = true
    
    ApplyLibCustomGlow(icon, viewerSettings)
end

-- Stop all glow effects on an icon
function StopGlow(icon)
    if not icon then return end

    -- Stop LibCustomGlow effects
    if LCG then
        pcall(LCG.PixelGlow_Stop, icon, "_QUICustomGlow")
        pcall(LCG.AutoCastGlow_Stop, icon, "_QUICustomGlow")
    end

    icon._QUICustomGlowActive = nil
    activeGlowIcons[icon] = nil
end

-- ======================================================
-- CDM Icon Method Hooking (reliable glow detection)
-- Uses Blizzard's built-in CDM icon methods instead of
-- manual spellID matching which fails during combat
-- ======================================================

-- Hook individual CDM icon's glow methods
local function HookCDMIcon(icon)
    if not icon then return end
    if icon._QUIGlowHooked then return end

    local viewerType = GetViewerType(icon)
    if not viewerType then return end

    -- Hook the glow show event handler
    if icon.OnSpellActivationOverlayGlowShowEvent then
        hooksecurefunc(icon, "OnSpellActivationOverlayGlowShowEvent", function(self, spellID)
            -- Check if this icon should respond to this spellID (wrapped in pcall for safety)
            local shouldProcess = true
            if self.NeedSpellActivationUpdate then
                pcall(function()
                    if not self:NeedSpellActivationUpdate(spellID) then
                        shouldProcess = false
                    end
                end)
            end
            if not shouldProcess then return end

            local settings = GetViewerSettings(viewerType)
            if not settings then return end

            if self:IsShown() then
                StartGlow(self)
            end
        end)
    end

    -- Hook the glow hide event handler
    if icon.OnSpellActivationOverlayGlowHideEvent then
        hooksecurefunc(icon, "OnSpellActivationOverlayGlowHideEvent", function(self, spellID)
            -- Check if this icon should respond to this spellID (wrapped in pcall for safety)
            local shouldProcess = true
            if self.NeedSpellActivationUpdate then
                pcall(function()
                    if not self:NeedSpellActivationUpdate(spellID) then
                        shouldProcess = false
                    end
                end)
            end
            if not shouldProcess then return end

            StopGlow(self)
        end)
    end

    -- Hook RefreshOverlayGlow for initial state and refreshes
    if icon.RefreshOverlayGlow then
        hooksecurefunc(icon, "RefreshOverlayGlow", function(self)
            local settings = GetViewerSettings(viewerType)
            if not settings then return end

            local shouldGlow = false

            -- Method 1: Try IsSpellOverlayed API (wrapped in pcall for secret value protection)
            pcall(function()
                local spellID = self.GetSpellID and self:GetSpellID()
                if spellID and IsSpellOverlayed and IsSpellOverlayed(spellID) then
                    shouldGlow = true
                end
            end)

            -- Method 2: Fallback - check icon's overlay frames directly
            if not shouldGlow then
                pcall(function()
                    if self.overlay and self.overlay:IsShown() then
                        shouldGlow = true
                    elseif self.SpellActivationAlert and self.SpellActivationAlert:IsShown() then
                        shouldGlow = true
                    elseif self.OverlayGlow and self.OverlayGlow:IsShown() then
                        shouldGlow = true
                    end
                end)
            end

            if shouldGlow then
                StartGlow(self)
            else
                StopGlow(self)
            end
        end)
    end

    icon._QUIGlowHooked = true
end

-- Hook all icons in a viewer
local function HookViewerIcons(viewerName)
    local viewer = _G[viewerName]
    if not viewer then return end

    local children = {viewer:GetChildren()}
    for _, child in ipairs(children) do
        if child and child ~= viewer.Selection then
            HookCDMIcon(child)
        end
    end
end

-- Setup continuous hooking for new icons
local function SetupViewerHooking(viewerName, trackerKey)
    local viewer = _G[viewerName]
    if not viewer then return end

    -- Hook existing icons
    HookViewerIcons(viewerName)

    -- Watch for new icons via layout changes
    if not viewer._QUIGlowLayoutHooked then
        viewer:HookScript("OnSizeChanged", function()
            C_Timer.After(0.1, function()
                HookViewerIcons(viewerName)
            end)
        end)
        viewer._QUIGlowLayoutHooked = true
    end
end

-- ======================================================
-- Hook into Blizzard's glow system
-- ======================================================
local function SetupGlowHooks()
    -- Keep ActionButton hooks as backup for edge cases
    -- These still work for some scenarios where CDM icon methods aren't available
    if type(ActionButton_ShowOverlayGlow) == "function" then
        hooksecurefunc("ActionButton_ShowOverlayGlow", function(button)
            if not button then return end
            local viewerType = GetViewerType(button)
            if not viewerType then return end
            local viewerSettings = GetViewerSettings(viewerType)
            if not viewerSettings then return end
            if button:IsShown() then
                StartGlow(button)
            end
        end)
    end

    if type(ActionButton_HideOverlayGlow) == "function" then
        hooksecurefunc("ActionButton_HideOverlayGlow", function(button)
            if not button then return end
            local viewerType = GetViewerType(button)
            if viewerType then
                StopGlow(button)
            end
        end)
    end

    -- NEW: Setup CDM icon method hooks (more reliable than event-based spellID matching)
    -- These hook directly into Blizzard's CDM icon methods for glow show/hide
    C_Timer.After(0.5, function()
        SetupViewerHooking("EssentialCooldownViewer", "Essential")
        SetupViewerHooking("UtilityCooldownViewer", "Utility")
    end)

    -- Event frame for ensuring hooks are set up when icons change
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:SetScript("OnEvent", function(self, event)
        -- Ensure all icons are hooked (new icons may have been created)
        C_Timer.After(0.2, function()
            SetupViewerHooking("EssentialCooldownViewer", "Essential")
            SetupViewerHooking("UtilityCooldownViewer", "Utility")
        end)
    end)
end

-- ======================================================
-- Refresh all glows (called when settings change)
-- ======================================================
local function RefreshAllGlows()
    -- Store which icons had glows before refresh
    local iconsWithGlows = {}
    for icon, _ in pairs(activeGlowIcons) do
        if icon then
            iconsWithGlows[icon] = true
        end
    end
    
    -- Stop all existing custom glows
    for icon, _ in pairs(activeGlowIcons) do
        if icon then
            StopGlow(icon)
        end
    end
    wipe(activeGlowIcons)
    
    -- Re-apply glows to icons that had them before
    for icon, _ in pairs(iconsWithGlows) do
        if icon and icon:IsShown() then
            StartGlow(icon)
        end
    end
end

-- ======================================================
-- Initialize
-- ======================================================
local glowHooksSetup = false

local function EnsureGlowHooks()
    if glowHooksSetup then return end
    glowHooksSetup = true
    SetupGlowHooks()
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event, arg)
    if event == "ADDON_LOADED" and arg == "Blizzard_CooldownManager" then
        -- Set up hooks immediately - no delay!
        EnsureGlowHooks()
    elseif event == "PLAYER_LOGIN" then
        -- Backup: ensure hooks are set up by login
        EnsureGlowHooks()
    end
end)

-- ======================================================
-- Export to QUI namespace
-- ======================================================
QUI.CustomGlows = {
    StartGlow = StartGlow,
    StopGlow = StopGlow,
    RefreshAllGlows = RefreshAllGlows,
    GetViewerType = GetViewerType,
    activeGlowIcons = activeGlowIcons,
    -- CDM icon hooking (for external trigger if needed)
    HookCDMIcon = HookCDMIcon,
    HookViewerIcons = HookViewerIcons,
}

-- Global function for config panel to call
_G.QUI_RefreshCustomGlows = RefreshAllGlows

-- Debug functions
_G.QUI_TestCustomGlow = function(viewerType)
    viewerType = viewerType or "Essential"
    local viewer = _G[viewerType .. "CooldownViewer"]
    if viewer then
        local children = {viewer:GetChildren()}
        for i, child in ipairs(children) do
            if child:IsShown() then
                StartGlow(child)
                print("|cFF00FF00[QUI]|r Test glow applied to " .. viewerType .. " icon #" .. i)
                return
            end
        end
        print("|cFFFF0000[QUI]|r No visible icons in " .. viewerType .. " viewer")
    else
        print("|cFFFF0000[QUI]|r " .. viewerType .. "CooldownViewer not found")
    end
end

_G.QUI_StopAllCustomGlows = function()
    for icon, _ in pairs(activeGlowIcons) do
        if icon then
            StopGlow(icon)
        end
    end
    wipe(activeGlowIcons)
    print("|cFF00FF00[QUI]|r All custom glows stopped")
end
