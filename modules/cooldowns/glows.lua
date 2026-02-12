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

    elseif glowType == "Button Glow" then
        -- Button Glow: classic Blizzard-style action button glow
        -- Parameters: frame, color, frequency, frameLevel
        LCG.ButtonGlow_Start(icon, color, frequency)
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
local function StopGlow(icon)
    if not icon then return end

    -- Stop all LibCustomGlow effect types
    if LCG then
        pcall(LCG.PixelGlow_Stop, icon, "_QUICustomGlow")
        pcall(LCG.AutoCastGlow_Stop, icon, "_QUICustomGlow")
        pcall(LCG.ButtonGlow_Stop, icon)
    end

    icon._QUICustomGlowActive = nil
    activeGlowIcons[icon] = nil
end

-- ======================================================
-- Deferred Glow Scan
-- Checks all viewer icons via IsSpellOverlayed and applies/removes glows.
-- Runs OUTSIDE Blizzard's CDM update cycle (via C_Timer.After(0)) so that
-- LCG frame tree modifications never happen during internal CDM updates.
-- This prevents the icon disappearance bug on retail where frame changes
-- inside hooksecurefunc callbacks cascade into layout engine re-entries.
-- ======================================================

local VIEWER_NAMES = { "EssentialCooldownViewer", "UtilityCooldownViewer" }
local scanPending = false

-- Forward declaration
local ScheduleGlowScan

-- Lightweight icon frame check (mirrors cdm_viewer.lua's IsIconFrame)
local function IsIconFrame(frame)
    if not frame then return false end
    return (frame.Icon or frame.icon) and (frame.Cooldown or frame.cooldown)
end

-- Scan a single viewer's icons and sync glow state
local function ScanViewerGlows(viewerName, targetSpellID)
    local viewer = _G[viewerName]
    if not viewer then return end

    local children = { viewer:GetChildren() }
    for _, icon in ipairs(children) do
        -- Filter: must be a real shown CDM icon (not custom CDM, not Selection, not non-icon children)
        if icon and icon ~= viewer.Selection and not icon._isCustomCDMIcon
            and icon:IsShown() and IsIconFrame(icon) then
            local viewerType = GetViewerType(icon)
            if viewerType then
                local settings = GetViewerSettings(viewerType)
                if settings then
                    local shouldGlow = false
                    local canDetermine = false

                    pcall(function()
                        local spellID = icon.GetSpellID and icon:GetSpellID()
                        if spellID then
                            -- Secret spellID = spell is mid-morph, skip this icon
                            if type(issecretvalue) == "function" and issecretvalue(spellID) then
                                return
                            end
                            -- When we have a targetSpellID from an event, skip unrelated icons
                            if targetSpellID and spellID ~= targetSpellID then
                                return
                            end
                            canDetermine = true
                            if IsSpellOverlayed and IsSpellOverlayed(spellID) then
                                shouldGlow = true
                            end
                        end
                    end)

                    -- Only modify glow state when we could reliably determine it.
                    -- Icons with secret or nil spellIDs keep their current glow state.
                    if canDetermine then
                        if shouldGlow and not icon._QUICustomGlowActive then
                            StartGlow(icon)
                        elseif not shouldGlow and icon._QUICustomGlowActive then
                            StopGlow(icon)
                        end
                    end
                end
            end
        end
    end
end

-- Run a glow scan across all viewers (optionally targeting a single spellID)
local function RunGlowScan(targetSpellID)
    scanPending = false
    for _, viewerName in ipairs(VIEWER_NAMES) do
        pcall(ScanViewerGlows, viewerName, targetSpellID)
    end
end

-- Schedule a deferred glow scan for the next frame.
-- Multiple calls within the same frame are coalesced into one scan.
-- When targetSpellID is provided, only that spell's icon is updated (faster).
-- A pending full scan always wins over a targeted one.
local pendingTargetSpellID
ScheduleGlowScan = function(targetSpellID)
    if scanPending then
        -- Already have a pending scan; widen to full scan if mixing targets
        if pendingTargetSpellID and targetSpellID ~= pendingTargetSpellID then
            pendingTargetSpellID = nil
        end
        return
    end
    scanPending = true
    pendingTargetSpellID = targetSpellID  -- nil = full scan
    C_Timer.After(0, function()
        RunGlowScan(pendingTargetSpellID)
        pendingTargetSpellID = nil
    end)
end

-- ======================================================
-- Event-Driven Glow Detection
-- Listens for Blizzard's glow events and viewer changes,
-- then triggers deferred scans. No hooks on individual CDM
-- icon methods — all glow state changes happen outside
-- Blizzard's update cycle.
-- ======================================================

local function HookViewerForScan(viewerName)
    local viewer = _G[viewerName]
    if not viewer or viewer._QUIGlowScanHooked then return end
    viewer._QUIGlowScanHooked = true

    -- New icons appear when Blizzard resizes the viewer
    viewer:HookScript("OnSizeChanged", function()
        ScheduleGlowScan()
    end)

    -- Scan when viewer becomes visible
    viewer:HookScript("OnShow", function()
        ScheduleGlowScan()
    end)
end

local function SetupGlowDetection()
    -- Hook viewer containers for new icon detection
    for _, viewerName in ipairs(VIEWER_NAMES) do
        HookViewerForScan(viewerName)
    end

    -- Listen for glow events and state changes
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:SetScript("OnEvent", function(_, event, spellID)
        if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
            -- Targeted scan for the specific spell that changed
            ScheduleGlowScan(spellID)
        else
            -- Full scan for world entry, combat end, etc.
            ScheduleGlowScan()
        end
    end)

    -- Low-frequency fallback scan to catch edge cases where event-driven
    -- detection misses a glow state change (e.g. icon replaced with an
    -- already-active proc, no SHOW event fires for it)
    C_Timer.NewTicker(3, function()
        ScheduleGlowScan()
    end)

    -- Initial scan
    ScheduleGlowScan()
end

-- ======================================================
-- Refresh all glows (called when settings change)
-- ======================================================
local function RefreshAllGlows()
    -- Collect keys first to avoid modifying the table during iteration
    local toStop = {}
    for icon in pairs(activeGlowIcons) do
        toStop[#toStop + 1] = icon
    end
    for _, icon in ipairs(toStop) do
        StopGlow(icon)
    end
    wipe(activeGlowIcons)

    -- Re-scan to apply with current settings
    ScheduleGlowScan()
end

-- ======================================================
-- Initialize
-- ======================================================
local glowSetupDone = false

local function EnsureGlowSetup()
    if glowSetupDone then return end
    glowSetupDone = true
    SetupGlowDetection()
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event, arg)
    if event == "ADDON_LOADED" and arg == "Blizzard_CooldownManager" then
        EnsureGlowSetup()
    elseif event == "PLAYER_LOGIN" then
        -- Backup: ensure setup by login even if CDM loaded earlier
        EnsureGlowSetup()
    end
    -- Unregister once setup is done to stop receiving unnecessary events
    if glowSetupDone then
        self:UnregisterEvent("ADDON_LOADED")
        self:UnregisterEvent("PLAYER_LOGIN")
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
    ScheduleGlowScan = ScheduleGlowScan,
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
