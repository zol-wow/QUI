-- cooldowneffects.lua
-- Hides intrusive Blizzard cooldown effects and glows
-- Features:
-- 1. Hides Blizzard Red/Flash Effects (Pandemic, ProcStartFlipbook, Finish)
-- 2. Hides ALL Overlay Glows (golden proc glows, spell activation alerts, etc.)

local _, ns = ...
local Helpers = ns.Helpers

-- Default settings
local DEFAULTS = { hideEssential = true, hideUtility = true }

-- Get settings from AceDB via shared helper
local function GetSettings()
    return Helpers.GetModuleSettings("cooldownEffects", DEFAULTS)
end

-- ======================================================
-- Feature 1: Hide Blizzard red/flash cooldown overlays
-- ======================================================
local function HideCooldownEffects(child)
    if not child then return end
    
    local effectFrames = {"PandemicIcon", "ProcStartFlipbook", "Finish"}
    
    for _, frameName in ipairs(effectFrames) do
        local frame = child[frameName]
        if frame then
            frame:Hide()
            frame:SetAlpha(0)
            
            -- Hook to keep it hidden
            if not frame._QUI_NoShow then
                frame._QUI_NoShow = true
                
                -- Hook Show to prevent it from showing
                if frame.Show then
                    hooksecurefunc(frame, "Show", function(self)
                        self:Hide()
                        self:SetAlpha(0)
                    end)
                end
                
                -- Also hook parent OnShow
                if child.HookScript then
                    child:HookScript("OnShow", function(self)
                        local f = self[frameName]
                        if f then
                            f:Hide()
                            f:SetAlpha(0)
                        end
                    end)
                end
            end
        end
    end
end

-- ======================================================
-- Feature 2: Hide Blizzard Overlay Glows on Cooldown Viewers
-- (Always hide Blizzard's glow - our LibCustomGlow is separate)
-- ======================================================
local function HideBlizzardGlows(button)
    if not button then return end
    
    -- ALWAYS hide Blizzard's glows - our custom glow uses LibCustomGlow which is separate
    -- Don't call ActionButton_HideOverlayGlow as it may interfere with proc detection
    
    -- Hide the SpellActivationAlert overlay (the golden swirl glow frame)
    if button.SpellActivationAlert then
        button.SpellActivationAlert:Hide()
        button.SpellActivationAlert:SetAlpha(0)
    end
    
    -- Hide OverlayGlow frame if it exists (Blizzard's default)
    if button.OverlayGlow then
        button.OverlayGlow:Hide()
        button.OverlayGlow:SetAlpha(0)
    end
    
    -- Hide _ButtonGlow (Blizzard's button glow frame, NOT our LibCustomGlow frames)
    if button._ButtonGlow then
        button._ButtonGlow:Hide()
    end
end

-- Alias for backwards compatibility
local HideAllGlows = HideBlizzardGlows

-- ======================================================
-- Apply to Cooldown Viewers - ONLY Essential and Utility
-- ======================================================
local viewers = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer"
    -- BuffIconCooldownViewer is NOT included - we want glows/effects on buff icons
}

local function ProcessViewer(viewerName)
    local viewer = _G[viewerName]
    if not viewer then return end
    
    -- Check if we should hide effects for this viewer
    local settings = GetSettings()
    local shouldHide = false
    if viewerName == "EssentialCooldownViewer" then
        shouldHide = settings.hideEssential
    elseif viewerName == "UtilityCooldownViewer" then
        shouldHide = settings.hideUtility
    end
    
    if not shouldHide then return end -- Don't process if effects should be shown
    
    local function ProcessIcons()
        local children = {viewer:GetChildren()}
        for _, child in ipairs(children) do
            if child:IsShown() then
                -- Hide red/flash effects
                HideCooldownEffects(child)
                
                -- Hide ALL glows (not just Epidemic)
                pcall(HideAllGlows, child)
                
                -- Mark as processed (no OnUpdate hook needed - we handle glows via hooksecurefunc)
                    child._QUI_EffectsHidden = true
            end
        end
    end
    
    -- Process immediately
    ProcessIcons()
    
    -- Hook Layout to reprocess when viewer updates
    if viewer.Layout and not viewer._QUI_EffectsHooked then
        viewer._QUI_EffectsHooked = true
        hooksecurefunc(viewer, "Layout", function()
            C_Timer.After(0.15, ProcessIcons)  -- 150ms debounce for CPU efficiency
        end)
    end
    
    -- Hook OnShow
    if not viewer._QUI_EffectsShowHooked then
        viewer._QUI_EffectsShowHooked = true
        viewer:HookScript("OnShow", function()
            C_Timer.After(0.15, ProcessIcons)  -- 150ms debounce for CPU efficiency
        end)
    end
end

local function ApplyToAllViewers()
    for _, viewerName in ipairs(viewers) do
        ProcessViewer(viewerName)
    end
end

-- ======================================================
-- Hook Blizzard Glows globally on Cooldown Viewers - ONLY Essential/Utility
-- (Custom QUI glows are handled separately in customglows.lua using LibCustomGlow)
-- ======================================================
-- Hide any existing Blizzard glows on all viewer icons
local function HideExistingBlizzardGlows()
    local viewerNames = {"EssentialCooldownViewer", "UtilityCooldownViewer"}
    for _, viewerName in ipairs(viewerNames) do
        local viewer = _G[viewerName]
        if viewer then
            local children = {viewer:GetChildren()}
            for _, child in ipairs(children) do
                pcall(HideBlizzardGlows, child)
            end
        end
    end
end

local function HookAllGlows()
    -- Hook the standard ActionButton_ShowOverlayGlow
    -- When Blizzard tries to show a glow, we ALWAYS hide Blizzard's glow
    -- Our custom glow (via LibCustomGlow) is completely separate and won't be affected
    if type(ActionButton_ShowOverlayGlow) == "function" then
        hooksecurefunc("ActionButton_ShowOverlayGlow", function(button)
            -- Only hide glows on Essential/Utility cooldown viewers, NOT BuffIcon
            if button and button:GetParent() then
                local parent = button:GetParent()
                local parentName = parent:GetName()
                if parentName and (
                    parentName:find("EssentialCooldown") or 
                    parentName:find("UtilityCooldown")
                    -- BuffIconCooldown is NOT included - we want glows on buff icons
                ) then
                    -- Hide Blizzard's glow immediately
                    -- customglows.lua runs first (load order) and applies LibCustomGlow
                    -- which is NOT affected by HideBlizzardGlows
                    C_Timer.After(0.01, function()
                        if button then
                            pcall(HideBlizzardGlows, button)
                        end
                    end)
                end
            end
        end)
    end
    
    -- Also hide any glows that might already be showing
    HideExistingBlizzardGlows()
end

-- ======================================================
-- Monitor removed - we don't process BuffIconCooldownViewer anymore
-- ======================================================
local function StartMonitoring()
    -- No longer needed - BuffIconCooldownViewer is not processed
end

-- ======================================================
-- Initialize
-- ======================================================
local glowHooksSetup = false

local function EnsureGlowHooks()
    if glowHooksSetup then return end
    glowHooksSetup = true
    HookAllGlows()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event, arg)
    if event == "ADDON_LOADED" and arg == "Blizzard_CooldownManager" then
        EnsureGlowHooks()
        -- Consolidated timer: apply settings and hide glows together
        C_Timer.After(0.5, function()
            ApplyToAllViewers()
            HideExistingBlizzardGlows()
        end)
        C_Timer.After(1, HideExistingBlizzardGlows) -- Final cleanup for late procs
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0.5, function()
            ApplyToAllViewers()
            HideExistingBlizzardGlows()
        end)
    elseif event == "PLAYER_LOGIN" then
        EnsureGlowHooks()
        C_Timer.After(0.5, HideExistingBlizzardGlows)
    end
end)

-- ======================================================
-- Export to QUI namespace
-- ======================================================
QUI.CooldownEffects = {
    HideCooldownEffects = HideCooldownEffects,
    HideAllGlows = HideAllGlows,
    ApplyToAllViewers = ApplyToAllViewers,
}

-- Global function for config panel to call
_G.QUI_RefreshCooldownEffects = function()
    ApplyToAllViewers()
end

