-- customglows.lua
-- Custom glow effects for Essential and Utility CDM icons.
-- Simplified: applies LibCustomGlow directly to addon-owned icon frames.
-- No overlay frame indirection, no Blizzard glow suppression needed.

local _, ns = ...
local Helpers = ns.Helpers

-- Get LibCustomGlow for custom glow styles
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

-- Get IsSpellOverlayed API: try C_ namespace (12.0+), fall back to deprecated global
local IsSpellOverlayed = (C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed)
    or _G.IsSpellOverlayed

-- Event-based overlay tracking: ultimate fallback when neither query API exists,
-- and also used to check override spell IDs that the API might miss.
local overlayedSpells = {}  -- [spellID] = true

-- Track which icons currently have active glows
local activeGlowIcons = {}  -- [icon] = true

---------------------------------------------------------------------------
-- SETTINGS ACCESS
---------------------------------------------------------------------------
local function GetSettings()
    return Helpers.GetModuleDB("customGlow")
end

---------------------------------------------------------------------------
-- DETERMINE VIEWER TYPE FROM ICON
-- Uses icon._spellEntry.viewerType instead of checking parent frame.
---------------------------------------------------------------------------
local function GetViewerType(icon)
    if not icon or not icon._spellEntry then return nil end
    local vt = icon._spellEntry.viewerType
    if vt == "essential" then return "Essential"
    elseif vt == "utility" then return "Utility"
    end
    return nil
end

---------------------------------------------------------------------------
-- GET SETTINGS FOR VIEWER TYPE
---------------------------------------------------------------------------
local function GetViewerSettings(viewerType)
    local settings = GetSettings()
    if not settings then return nil end

    if viewerType == "Essential" then
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

---------------------------------------------------------------------------
-- GLOW APPLICATION (supports 3 glow types via LibCustomGlow)
-- Applied directly to owned icons — no overlay frame needed.
---------------------------------------------------------------------------
local StopGlow

local function ApplyLibCustomGlow(icon, viewerSettings)
    if not LCG or not icon then return false end

    local glowType = viewerSettings.glowType
    local color = viewerSettings.color
    local lines = viewerSettings.lines
    local frequency = viewerSettings.frequency
    local thickness = viewerSettings.thickness
    local scale = viewerSettings.scale or 1
    local xOffset = viewerSettings.xOffset or 0

    -- Stop any existing glow first
    StopGlow(icon)

    if glowType == "Pixel Glow" then
        LCG.PixelGlow_Start(icon, color, lines, frequency, nil, thickness, 0, 0, true, "_QUICustomGlow")
        local glowFrame = icon["_PixelGlow_QUICustomGlow"]
        if glowFrame then
            glowFrame:ClearAllPoints()
            glowFrame:SetPoint("TOPLEFT", icon, "TOPLEFT", -xOffset, xOffset)
            glowFrame:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", xOffset, -xOffset)
        end

    elseif glowType == "Autocast Shine" then
        LCG.AutoCastGlow_Start(icon, color, lines, frequency, scale, 0, 0, "_QUICustomGlow")
        local glowFrame = icon["_AutoCastGlow_QUICustomGlow"]
        if glowFrame then
            glowFrame:ClearAllPoints()
            glowFrame:SetPoint("TOPLEFT", icon, "TOPLEFT", -xOffset, xOffset)
            glowFrame:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", xOffset, -xOffset)
        end

    elseif glowType == "Button Glow" then
        LCG.ButtonGlow_Start(icon, color, frequency)
    end

    activeGlowIcons[icon] = true
    return true
end

---------------------------------------------------------------------------
-- START / STOP GLOW
---------------------------------------------------------------------------
local function StartGlow(icon)
    if not icon then return end
    if activeGlowIcons[icon] then return end

    local viewerType = GetViewerType(icon)
    if not viewerType then return end

    local viewerSettings = GetViewerSettings(viewerType)
    if not viewerSettings then return end

    ApplyLibCustomGlow(icon, viewerSettings)
end

StopGlow = function(icon)
    if not icon then return end
    if LCG then
        pcall(LCG.PixelGlow_Stop, icon, "_QUICustomGlow")
        pcall(LCG.AutoCastGlow_Stop, icon, "_QUICustomGlow")
        pcall(LCG.ButtonGlow_Stop, icon)
    end
    activeGlowIcons[icon] = nil
end

---------------------------------------------------------------------------
-- CHECK OVERLAY STATE: query API + event-based tracking
---------------------------------------------------------------------------
local function IsOverlayed(spellID)
    if not spellID then return false end
    -- Query API (works for base spell IDs)
    if IsSpellOverlayed then
        local ok, result = pcall(IsSpellOverlayed, spellID)
        if ok and result then return true end
    end
    -- Event-based tracking (catches override IDs and API gaps)
    return overlayedSpells[spellID] or false
end

---------------------------------------------------------------------------
-- SCAN ALL ICONS AND SYNC GLOW STATE
---------------------------------------------------------------------------
local function ScanAllGlows()
    local CDMIcons = ns.CDMIcons
    if not CDMIcons then return end

    for _, viewerType in ipairs({"essential", "utility"}) do
        local pool = CDMIcons:GetIconPool(viewerType)
        for _, icon in ipairs(pool) do
            if icon._spellEntry then
                local baseID = icon._spellEntry.spellID
                local overrideID = icon._spellEntry.overrideSpellID
                local shouldGlow = IsOverlayed(baseID)
                    or (overrideID and overrideID ~= baseID and IsOverlayed(overrideID))

                -- Check current runtime override: the spell may be temporarily
                -- replaced (e.g., Judgment → Hammer of Wrath via Wake of Ashes).
                -- The glow event fires for the override's spell ID, which differs
                -- from both baseID and the static scan-time overrideSpellID.
                if not shouldGlow and C_Spell and C_Spell.GetOverrideSpell then
                    local currentOverride = C_Spell.GetOverrideSpell(baseID)
                    if currentOverride and currentOverride ~= baseID
                        and currentOverride ~= overrideID then
                        shouldGlow = IsOverlayed(currentOverride)
                    end
                end

                if shouldGlow and not activeGlowIcons[icon] then
                    StartGlow(icon)
                elseif not shouldGlow and activeGlowIcons[icon] then
                    StopGlow(icon)
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- REFRESH ALL GLOWS (called when settings change)
---------------------------------------------------------------------------
local function RefreshAllGlows()
    -- Stop all current glows
    local toStop = {}
    for icon in pairs(activeGlowIcons) do
        toStop[#toStop + 1] = icon
    end
    for _, icon in ipairs(toStop) do
        StopGlow(icon)
    end
    wipe(activeGlowIcons)

    -- Re-scan to apply with current settings
    ScanAllGlows()
end

---------------------------------------------------------------------------
-- EVENT HANDLING
-- SPELL_ACTIVATION_OVERLAY_GLOW events drive proc glow updates.
-- Track overlay state in overlayedSpells table for API-free fallback.
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(_, event, spellID)
    -- Only run when owned CDM engine is active
    if ns.CDMProvider and ns.CDMProvider:GetActiveEngineName() and ns.CDMProvider:GetActiveEngineName() ~= "owned" then return end

    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" and spellID then
        overlayedSpells[spellID] = true
        -- Also track override spell so icon lookup hits
        if C_Spell and C_Spell.GetOverrideSpell then
            local overrideID = C_Spell.GetOverrideSpell(spellID)
            if overrideID and overrideID ~= spellID then
                overlayedSpells[overrideID] = true
            end
        end
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" and spellID then
        overlayedSpells[spellID] = nil
        if C_Spell and C_Spell.GetOverrideSpell then
            local overrideID = C_Spell.GetOverrideSpell(spellID)
            if overrideID and overrideID ~= spellID then
                overlayedSpells[overrideID] = nil
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        wipe(overlayedSpells)
    end
    ScanAllGlows()
end)

-- Low-frequency fallback scan to catch edge cases (e.g. icon replaced
-- with an already-active proc, no SHOW event fires for it)
C_Timer.NewTicker(3, function()
    if ns.CDMProvider and ns.CDMProvider:GetActiveEngineName() == "owned" then
        ScanAllGlows()
    end
end)

---------------------------------------------------------------------------
-- EXPORTS (deferred — only overwrite classic engine's exports when owned is active)
---------------------------------------------------------------------------
-- Store on ns for engine init to wire
ns._OwnedGlows = {
    StartGlow = StartGlow,
    StopGlow = StopGlow,
    RefreshAllGlows = RefreshAllGlows,
    GetViewerType = GetViewerType,
    activeGlowIcons = activeGlowIcons,
    ScheduleGlowScan = ScanAllGlows,
    GetGlowState = function(icon)
        return activeGlowIcons[icon] and { active = true } or nil
    end,
}


