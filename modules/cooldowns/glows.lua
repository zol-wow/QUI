-- customglows.lua
-- Custom glow effects for Essential and Utility cooldown viewers
-- Uses LibCustomGlow for custom glow styles (Pixel Glow, Autocast Shine, Button Glow)
-- Replaces Blizzard's SpellActivationAlert with the configured custom glow

local _, ns = ...
local Helpers = ns.Helpers

-- Get LibCustomGlow for custom glow styles
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

-- Get IsSpellOverlayed API for glow state detection (fallback)
local IsSpellOverlayed = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed

-- Track which icons currently have active glows
local activeGlowIcons = {}  -- [icon] = true

-- Track active glow spell names from SPELL_ACTIVATION_OVERLAY_GLOW events.
-- Used for name-based matching since CDM cooldownIDs != actual spell IDs.
local activeGlowSpellNames = {}  -- [spellName] = true

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

    local ok, parent = pcall(icon.GetParent, icon)
    if not ok or not parent then return nil end

    local nameOk, parentName = pcall(parent.GetName, parent)
    if not nameOk or not parentName then return nil end

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
-- Suppress Blizzard's glow on an icon
-- Hides SpellActivationAlert/OverlayGlow and hooks Show
-- to prevent them from reappearing.
-- ======================================================
local function SuppressBlizzardGlow(icon)
    if not icon then return end

    pcall(function()
        local alert = icon.SpellActivationAlert
        if alert then
            alert:Hide()
            alert:SetAlpha(0)
            -- Persistent hook: keep it hidden even if Blizzard re-shows it
            if not alert._QUI_NoShow then
                alert._QUI_NoShow = true
                hooksecurefunc(alert, "Show", function(self)
                    self:Hide()
                    self:SetAlpha(0)
                end)
            end
        end
    end)

    pcall(function()
        if icon.OverlayGlow then
            icon.OverlayGlow:Hide()
            icon.OverlayGlow:SetAlpha(0)
            if not icon.OverlayGlow._QUI_NoShow then
                icon.OverlayGlow._QUI_NoShow = true
                hooksecurefunc(icon.OverlayGlow, "Show", function(self)
                    self:Hide()
                    self:SetAlpha(0)
                end)
            end
        end
    end)
end

-- ======================================================
-- Check if Blizzard's glow is visually active on an icon
-- (before we suppress it)
-- ======================================================
local function HasBlizzardGlow(icon)
    if not icon then return false end

    local found = false
    pcall(function()
        if icon.SpellActivationAlert and icon.SpellActivationAlert:IsShown() then
            found = true
        end
    end)
    if found then return true end

    pcall(function()
        if icon.OverlayGlow and icon.OverlayGlow:IsShown() then
            found = true
        end
    end)
    return found
end

-- ======================================================
-- LibCustomGlow application (supports 3 glow types)
-- ======================================================

-- Forward declaration (StopGlow is defined after ApplyLibCustomGlow)
local StopGlow

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

    -- Suppress Blizzard's glow on this icon
    SuppressBlizzardGlow(icon)

    -- Set the flag FIRST so cooldowneffects.lua doesn't interfere
    icon._QUICustomGlowActive = true
    activeGlowIcons[icon] = true

    ApplyLibCustomGlow(icon, viewerSettings)
end

-- Stop all glow effects on an icon
StopGlow = function(icon)
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
-- Checks all viewer icons and applies/removes glows.
-- Uses multiple detection methods:
--   1. Visual: is Blizzard's SpellActivationAlert showing?
--   2. API: does IsSpellOverlayed return true for the icon's spell?
-- Runs OUTSIDE Blizzard's CDM update cycle (via C_Timer.After(0)) so that
-- LCG frame tree modifications never happen during internal CDM updates.
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

-- Get the ACTUAL spell ID from a CDM icon for use with IsSpellOverlayed.
-- IMPORTANT: icon.cooldownID is a CDM tracking ID (e.g. 18459), NOT a WoW spell ID.
-- We need the real spell ID from cooldownInfo for overlay detection.
local function GetIconSpellID(icon)
    local spellID
    pcall(function()
        -- Priority 1: cooldownInfo.overrideSpellID (morphed/current form)
        if icon.cooldownInfo then
            if icon.cooldownInfo.overrideSpellID then
                local id = icon.cooldownInfo.overrideSpellID
                if not (type(issecretvalue) == "function" and issecretvalue(id)) then
                    spellID = id
                end
            end
            -- Priority 2: cooldownInfo.spellID (base spell ID)
            if not spellID and icon.cooldownInfo.spellID then
                local id = icon.cooldownInfo.spellID
                if not (type(issecretvalue) == "function" and issecretvalue(id)) then
                    spellID = id
                end
            end
        end
        -- Priority 3: GetSpellID method (some icons may have this)
        if not spellID and icon.GetSpellID then
            local id = icon:GetSpellID()
            if id and not (type(issecretvalue) == "function" and issecretvalue(id)) then
                spellID = id
            end
        end
        -- NOTE: Do NOT use icon.cooldownID or icon.spellID here — in WoW 12.0
        -- these are CDM tracking IDs, not actual WoW spell IDs.
    end)
    return spellID
end

-- Get the spell name from a CDM icon for name-based glow matching.
local function GetIconSpellName(icon)
    local name
    pcall(function()
        if icon.cooldownInfo and icon.cooldownInfo.name then
            local n = icon.cooldownInfo.name
            -- Verify it's a real string (not secret)
            if type(n) == "string" then
                name = n
            else
                local ok, _ = pcall(function() return n:len() end)
                if ok then name = n end
            end
        end
    end)
    return name
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

                    -- Method 1: Check if Blizzard's glow is visually showing
                    if HasBlizzardGlow(icon) then
                        shouldGlow = true
                        canDetermine = true
                    end

                    -- Method 2: Check via IsSpellOverlayed API (using actual spell ID from cooldownInfo)
                    if not canDetermine then
                        local spellID = GetIconSpellID(icon)
                        if spellID then
                            -- When we have a targetSpellID from an event, skip unrelated icons
                            if targetSpellID then
                                local matchOk, matches = pcall(function() return spellID == targetSpellID end)
                                if not matchOk or not matches then
                                    spellID = nil  -- Skip this icon
                                end
                            end
                            if spellID then
                                canDetermine = true
                                if IsSpellOverlayed and IsSpellOverlayed(spellID) then
                                    shouldGlow = true
                                end
                            end
                        end
                    end

                    -- Method 3: Name-based matching against tracked glow events
                    -- Catches cases where spell IDs don't match (CDM uses different IDs)
                    if not canDetermine or (canDetermine and not shouldGlow) then
                        local spellName = GetIconSpellName(icon)
                        if spellName and activeGlowSpellNames[spellName] then
                            shouldGlow = true
                            canDetermine = true
                        elseif spellName and not canDetermine then
                            -- We have a name but it's not glowing — that's a valid determination
                            canDetermine = true
                        end
                    end

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

-- NOTE: ActionButton_ShowOverlayGlow / ActionButton_HideOverlayGlow
-- do NOT exist in WoW 12.0. Glow detection is handled entirely via
-- SPELL_ACTIVATION_OVERLAY_GLOW events + name-based matching.

local viewerScanState = {}

-- Poll cooldown viewer state without HookScript() to avoid tainting Blizzard
-- secret-value refresh paths (e.g. totem data in CooldownViewerItemData).
local function PollViewerChangesForScan()
    local changed = false

    for _, viewerName in ipairs(VIEWER_NAMES) do
        local viewer = _G[viewerName]
        if viewer then
            local state = viewerScanState[viewerName]
            if not state then
                state = { shown = false, childCount = 0, width = 0, height = 0 }
                viewerScanState[viewerName] = state
            end

            local shown = viewer:IsShown()
            local childCount = shown and (viewer:GetNumChildren() or 0) or 0
            local width = shown and (viewer:GetWidth() or 0) or 0
            local height = shown and (viewer:GetHeight() or 0) or 0

            if shown ~= state.shown
                or childCount ~= state.childCount
                or math.abs(width - state.width) > 0.5
                or math.abs(height - state.height) > 0.5 then
                state.shown = shown
                state.childCount = childCount
                state.width = width
                state.height = height
                changed = true
            end
        end
    end

    if changed then
        ScheduleGlowScan()
    end
end

-- ======================================================
-- Event-Driven Glow Detection (fallback for cases where
-- ActionButton hooks don't fire)
-- ======================================================

local function SetupGlowDetection()
    -- Poll viewer state changes instead of HookScript() to avoid taint.
    C_Timer.NewTicker(0.25, function()
        PollViewerChangesForScan()
    end)

    -- Listen for glow events and state changes
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:SetScript("OnEvent", function(_, event, spellID)
        if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
            -- Track this spell name as glowing (for name-based matching)
            pcall(function()
                local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
                if name then
                    activeGlowSpellNames[name] = true
                end
            end)
            ScheduleGlowScan(spellID)
        elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
            -- Remove this spell name from glowing set
            pcall(function()
                local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
                if name then
                    activeGlowSpellNames[name] = nil
                end
            end)
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

