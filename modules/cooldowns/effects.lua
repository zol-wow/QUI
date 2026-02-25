-- cooldowneffects.lua
-- Hides intrusive Blizzard cooldown effects and glows
-- Features:
-- 1. Hides Blizzard Red/Flash Effects (Pandemic, ProcStartFlipbook, Finish)
-- 2. Hides ALL Overlay Glows (golden proc glows, spell activation alerts, etc.)

local _, ns = ...
local Helpers = ns.Helpers

-- TAINT SAFETY: Store per-frame state in local weak-keyed tables instead of
-- writing custom properties to Blizzard frames (CDM viewer icons/subframes).
local hookedFrames   = Helpers.CreateStateTable()  -- frame → true (Show hook applied)
local processedIcons = Helpers.CreateStateTable()  -- icon  → true (effects hidden)
local hookedViewers  = Helpers.CreateStateTable()  -- viewer → { layout, show }

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
            -- pcall to handle protected-state failures during combat
            pcall(frame.Hide, frame)
            pcall(frame.SetAlpha, frame, 0)

            -- Hook to keep it hidden
            if not hookedFrames[frame] then
                hookedFrames[frame] = true

                -- TAINT SAFETY: Defer to break taint chain from secure CDM context.
                Helpers.DeferredHideOnShow(frame, { clearAlpha = true })

                -- Also hook parent OnShow
                if child.HookScript then
                    child:HookScript("OnShow", function(self)
                        C_Timer.After(0, function()
                            if self and self[frameName] then
                                local f = self[frameName]
                                pcall(f.Hide, f)
                                pcall(f.SetAlpha, f, 0)
                            end
                        end)
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

    -- pcall to handle protected-state failures during combat

    -- Hide the SpellActivationAlert overlay (the golden swirl glow frame)
    if button.SpellActivationAlert then
        pcall(button.SpellActivationAlert.Hide, button.SpellActivationAlert)
        pcall(button.SpellActivationAlert.SetAlpha, button.SpellActivationAlert, 0)
    end

    -- Hide OverlayGlow frame if it exists (Blizzard's default)
    if button.OverlayGlow then
        pcall(button.OverlayGlow.Hide, button.OverlayGlow)
        pcall(button.OverlayGlow.SetAlpha, button.OverlayGlow, 0)
    end

    -- Hide _ButtonGlow only when it's Blizzard's frame, not LibCustomGlow's.
    -- LibCustomGlow's ButtonGlow_Start uses the same _ButtonGlow property,
    -- so skip hiding when our custom glow is active on this icon.
    -- NOTE: _QUICustomGlowActive is checked via the glows module's shared table
    local glowState = _G.QUI_GetGlowState and _G.QUI_GetGlowState(button)
    if button._ButtonGlow and not (glowState and glowState.active) then
        pcall(button._ButtonGlow.Hide, button._ButtonGlow)
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
                processedIcons[child] = true
            end
        end
    end
    
    -- Process immediately
    ProcessIcons()
    
    -- TAINT SAFETY: Defer to break taint chain from secure CDM context.
    -- Hook Layout to reprocess when viewer updates
    local hvState = hookedViewers[viewer]
    if not hvState then hvState = {}; hookedViewers[viewer] = hvState end
    if viewer.Layout and not hvState.layout then
        hvState.layout = true
        hooksecurefunc(viewer, "Layout", function()
            C_Timer.After(0.15, ProcessIcons)
        end)
    end

    -- Hook OnShow
    if not hvState.show then
        hvState.show = true
        viewer:HookScript("OnShow", function()
            C_Timer.After(0.15, ProcessIcons)
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
        -- TAINT SAFETY: Defer ALL addon logic to break taint chain from secure context.
        hooksecurefunc("ActionButton_ShowOverlayGlow", function(button)
            C_Timer.After(0, function()
                -- Only hide glows on Essential/Utility cooldown viewers, NOT BuffIcon
                if button and button.GetParent and button:GetParent() then
                    local parent = button:GetParent()
                    local parentName = parent.GetName and parent:GetName()
                    if parentName and (
                        parentName:find("EssentialCooldown") or
                        parentName:find("UtilityCooldown")
                        -- BuffIconCooldown is NOT included - we want glows on buff icons
                    ) then
                        pcall(HideBlizzardGlows, button)
                    end
                end
            end)
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

