-- customglows.lua
-- Custom glow effects for Essential and Utility CDM icons.
-- Simplified: applies LibCustomGlow directly to addon-owned icon frames.
-- No overlay frame indirection, no Blizzard glow suppression needed.

local _, ns = ...
local Helpers = ns.Helpers

-- Get LibCustomGlow for custom glow styles
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

-- Texture assets for overlay glow types
local FLASH_TEXTURE = [[Interface\AddOns\QUI\assets\iconskin\Flash]]
local HAMMER_TEXTURE = [[Interface\AddOns\QUI\assets\quazii_hammer]]

-- Get IsSpellOverlayed API: try C_ namespace (12.0+), fall back to deprecated global
local IsSpellOverlayed = (C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed)
    or _G.IsSpellOverlayed

-- Event-based overlay tracking: ultimate fallback when neither query API exists,
-- and also used to check override spell IDs that the API might miss.
local overlayedSpells = {}  -- [spellID] = true

-- Track which icons currently have active glows
local activeGlowIcons = {}  -- [icon] = true

-- Reverse lookup: spellID → list of icons that track it.
-- Allows O(1) dispatch on SHOW/HIDE events instead of scanning all icons.
local spellIdToGlowIcons = {}  -- [spellID] = {icon, ...}

local function RebuildGlowSpellMap()
    wipe(spellIdToGlowIcons)
    local CDMIcons = ns.CDMIcons
    if not CDMIcons then return end
    for _, viewerType in ipairs({"essential", "utility"}) do
        local pool = CDMIcons:GetIconPool(viewerType)
        for _, icon in ipairs(pool) do
            if icon._spellEntry then
                local ids = {}
                if icon._spellEntry.spellID then ids[#ids + 1] = icon._spellEntry.spellID end
                if icon._spellEntry.overrideSpellID and icon._spellEntry.overrideSpellID ~= icon._spellEntry.spellID then
                    ids[#ids + 1] = icon._spellEntry.overrideSpellID
                end
                for _, id in ipairs(ids) do
                    local list = spellIdToGlowIcons[id]
                    if not list then
                        list = {}
                        spellIdToGlowIcons[id] = list
                    end
                    list[#list + 1] = icon
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- SETTINGS ACCESS
---------------------------------------------------------------------------
local GetSettings = Helpers.CreateDBGetter("customGlow")

local function IsOwnedEngineSelected()
    if ns.CDMProvider and ns.CDMProvider.GetActiveEngineName then
        local active = ns.CDMProvider:GetActiveEngineName()
        if active ~= nil then
            return active == "owned"
        end
    end

    local core = ns.Addon
    local db = core and core.db and core.db.profile
    local configured = db and db.ncdm and db.ncdm.engine
    if configured ~= nil then
        return configured == "owned"
    end

    return false
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
        return {
            enabled = true,
            glowType = settings.essentialGlowType or "Pixel Glow",
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
        return {
            enabled = true,
            glowType = settings.utilityGlowType or "Pixel Glow",
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

-- Ensure glow frame renders above the Cooldown swipe.
-- LibCustomGlow sets glow at icon:GetFrameLevel() + 8, but HUD layering
-- can push CooldownFrameTemplate above that. Reference the Cooldown frame
-- directly (same pattern as TextOverlay in cdm_icons.lua:659).
-- Layer order: Cooldown swipe (cdLevel) → Glow (+1) → Text (+1) → ClickButton (+2)
local function EnsureGlowAboveCooldown(icon, glowFrame)
    if not glowFrame or not icon or not icon.Cooldown then return end

    local cdLevel = icon.Cooldown:GetFrameLevel()
    local glowLevel = glowFrame:GetFrameLevel()
    if glowLevel <= cdLevel then
        glowLevel = cdLevel + 1
        glowFrame:SetFrameLevel(glowLevel)
    end

    -- Keep stack/proc text above glow and click button above text.
    local CDMIcons = ns.CDMIcons
    if CDMIcons and CDMIcons.EnsureTextOverlayLevel then
        CDMIcons:EnsureTextOverlayLevel(icon, glowLevel + 1)
    end
end

-- Shared helper: create or reuse a pulsing texture overlay on an icon.
-- key: unique frame key on icon (e.g. "_QUIFlashGlow")
-- texturePath: texture file path
local function StartTextureGlow(icon, key, texturePath, color)
    local frame = icon[key]
    if not frame then
        frame = CreateFrame("Frame", nil, icon)
        frame:SetAllPoints(icon)
        icon[key] = frame

        local tex = frame:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(texturePath)
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetBlendMode("ADD")
        tex:SetAllPoints(frame)
        frame.texture = tex

        local ag = frame:CreateAnimationGroup()
        ag:SetLooping("REPEAT")

        local fadeIn = ag:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0.3)
        fadeIn:SetToAlpha(1)
        fadeIn:SetDuration(0.4)
        fadeIn:SetOrder(1)

        local fadeOut = ag:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1)
        fadeOut:SetToAlpha(0.3)
        fadeOut:SetDuration(0.4)
        fadeOut:SetOrder(2)

        frame.animGroup = ag
    end

    local r, g, b, a = 1, 1, 1, 1
    if color then r, g, b, a = color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1 end
    frame.texture:SetVertexColor(r, g, b, a)
    frame:Show()
    frame.animGroup:Play()
    return frame
end

local function StopTextureGlow(icon, key)
    local frame = icon[key]
    if frame then
        frame.animGroup:Stop()
        frame:Hide()
    end
end

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
            EnsureGlowAboveCooldown(icon, glowFrame)
        end

    elseif glowType == "Autocast Shine" then
        LCG.AutoCastGlow_Start(icon, color, lines, frequency, scale, 0, 0, "_QUICustomGlow")
        local glowFrame = icon["_AutoCastGlow_QUICustomGlow"]
        if glowFrame then
            glowFrame:ClearAllPoints()
            glowFrame:SetPoint("TOPLEFT", icon, "TOPLEFT", -xOffset, xOffset)
            glowFrame:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", xOffset, -xOffset)
            EnsureGlowAboveCooldown(icon, glowFrame)
        end

    elseif glowType == "Button Glow" then
        LCG.ButtonGlow_Start(icon, color, frequency)
        EnsureGlowAboveCooldown(icon, icon["_ButtonGlow"])

    elseif glowType == "Flash" then
        local frame = StartTextureGlow(icon, "_QUIFlashGlow", FLASH_TEXTURE, color)
        EnsureGlowAboveCooldown(icon, frame)

    elseif glowType == "Hammer" then
        local frame = StartTextureGlow(icon, "_QUIHammerGlow", HAMMER_TEXTURE, color)
        EnsureGlowAboveCooldown(icon, frame)

    elseif glowType == "Proc Glow" then
        LCG.ProcGlow_Start(icon, {
            key = "_QUICustomGlow",
            color = color,
            startAnim = true,
            xOffset = xOffset,
            yOffset = viewerSettings.yOffset or 0,
        })
        local glowFrame = icon["_ProcGlow_QUICustomGlow"]
        if glowFrame then
            EnsureGlowAboveCooldown(icon, glowFrame)
        end
    end

    activeGlowIcons[icon] = true
    return true
end

---------------------------------------------------------------------------
-- START / STOP GLOW
---------------------------------------------------------------------------
-- Per-spell glow color override helper: returns a copy of viewerSettings
-- with the color replaced if a per-spell glowColor override exists.
local function ApplyGlowColorOverride(viewerSettings, spellOvr)
    if not spellOvr or not spellOvr.glowColor then return viewerSettings end
    -- Shallow copy so we don't mutate the cached settings table
    local copy = {}
    for k, v in pairs(viewerSettings) do copy[k] = v end
    copy.color = spellOvr.glowColor
    return copy
end

local function StartGlow(icon, spellOvr)
    if not icon then return end
    if activeGlowIcons[icon] then return end

    local viewerType = GetViewerType(icon)
    if not viewerType then return end

    local viewerSettings = GetViewerSettings(viewerType)
    if not viewerSettings then return end

    -- Apply per-spell glow color override
    viewerSettings = ApplyGlowColorOverride(viewerSettings, spellOvr)

    ApplyLibCustomGlow(icon, viewerSettings)
end

StopGlow = function(icon)
    if not icon then return end
    if LCG then
        pcall(LCG.PixelGlow_Stop, icon, "_QUICustomGlow")
        pcall(LCG.AutoCastGlow_Stop, icon, "_QUICustomGlow")
        pcall(LCG.ButtonGlow_Stop, icon)
        pcall(LCG.ProcGlow_Stop, icon, "_QUICustomGlow")
    end
    StopTextureGlow(icon, "_QUIFlashGlow")
    StopTextureGlow(icon, "_QUIHammerGlow")
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

    local CDMSpellData = ns.CDMSpellData

    for _, viewerType in ipairs({"essential", "utility"}) do
        local pool = CDMIcons:GetIconPool(viewerType)
        for _, icon in ipairs(pool) do
            if not icon:IsShown() then -- skip hidden icons (glow re-applied on layout refresh)
                -- noop: skip
            elseif icon._spellEntry then
                local baseID = icon._spellEntry.spellID
                local overrideID = icon._spellEntry.overrideSpellID

                -- Per-spell glow override lookup
                local spellOvr = nil
                if CDMSpellData then
                    local lookupID = icon._spellEntry.spellID or icon._spellEntry.id
                    if lookupID then
                        spellOvr = CDMSpellData:GetSpellOverride(viewerType, lookupID)
                    end
                end

                -- Per-spell glowEnabled override: false suppresses, true forces
                local shouldGlow
                if spellOvr and spellOvr.glowEnabled == false then
                    shouldGlow = false
                elseif spellOvr and spellOvr.glowEnabled == true then
                    shouldGlow = true
                else
                    -- Default: check proc overlay state
                    shouldGlow = IsOverlayed(baseID)
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
                end

                if shouldGlow and not activeGlowIcons[icon] then
                    StartGlow(icon, spellOvr)
                elseif not shouldGlow and activeGlowIcons[icon] then
                    StopGlow(icon)
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- TARGETED GLOW UPDATE FOR A SINGLE SPELL ID
-- O(1) lookup via reverse map instead of scanning all icons.
---------------------------------------------------------------------------
local function ScanGlowsForSpell(spellID)
    if not spellID then ScanAllGlows(); return end

    local CDMIcons = ns.CDMIcons
    if not CDMIcons then return end
    local CDMSpellData = ns.CDMSpellData

    -- Collect all candidate spellIDs to look up
    local candidates = { spellID }
    if C_Spell and C_Spell.GetOverrideSpell then
        local ov = C_Spell.GetOverrideSpell(spellID)
        if ov and ov ~= spellID then candidates[#candidates + 1] = ov end
    end

    -- Deduplicate icons across candidates
    local visited = {}
    for _, id in ipairs(candidates) do
        local icons = spellIdToGlowIcons[id]
        if icons then
            for _, icon in ipairs(icons) do
                if not visited[icon] then
                    visited[icon] = true
                    if icon:IsShown() and icon._spellEntry then
                        local viewerType = icon._spellEntry.viewerType
                        local baseID = icon._spellEntry.spellID
                        local overrideID = icon._spellEntry.overrideSpellID

                        local spellOvr = nil
                        if CDMSpellData and viewerType then
                            local lookupID = baseID or icon._spellEntry.id
                            if lookupID then
                                spellOvr = CDMSpellData:GetSpellOverride(viewerType, lookupID)
                            end
                        end

                        local shouldGlow
                        if spellOvr and spellOvr.glowEnabled == false then
                            shouldGlow = false
                        elseif spellOvr and spellOvr.glowEnabled == true then
                            shouldGlow = true
                        else
                            shouldGlow = IsOverlayed(baseID)
                                or (overrideID and overrideID ~= baseID and IsOverlayed(overrideID))
                            if not shouldGlow and C_Spell and C_Spell.GetOverrideSpell then
                                local currentOverride = C_Spell.GetOverrideSpell(baseID)
                                if currentOverride and currentOverride ~= baseID
                                    and currentOverride ~= overrideID then
                                    shouldGlow = IsOverlayed(currentOverride)
                                end
                            end
                        end

                        if shouldGlow and not activeGlowIcons[icon] then
                            StartGlow(icon, spellOvr)
                        elseif not shouldGlow and activeGlowIcons[icon] then
                            StopGlow(icon)
                        end
                    end
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

    -- Rebuild reverse lookup and re-scan with current settings
    RebuildGlowSpellMap()
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
    if not IsOwnedEngineSelected() then return end

    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" and spellID then
        overlayedSpells[spellID] = true
        if C_Spell and C_Spell.GetOverrideSpell then
            local overrideID = C_Spell.GetOverrideSpell(spellID)
            if overrideID and overrideID ~= spellID then
                overlayedSpells[overrideID] = true
            end
        end
        ScanGlowsForSpell(spellID)
        return
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" and spellID then
        overlayedSpells[spellID] = nil
        if C_Spell and C_Spell.GetOverrideSpell then
            local overrideID = C_Spell.GetOverrideSpell(spellID)
            if overrideID and overrideID ~= spellID then
                overlayedSpells[overrideID] = nil
            end
        end
        ScanGlowsForSpell(spellID)
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        wipe(overlayedSpells)
    end
    ScanAllGlows()
end)

-- Low-frequency fallback scan to catch edge cases (e.g. icon replaced
-- with an already-active proc, no SHOW event fires for it)
C_Timer.NewTicker(5, function()
    if IsOwnedEngineSelected() then
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
    RebuildGlowSpellMap = RebuildGlowSpellMap,
    GetViewerType = GetViewerType,
    activeGlowIcons = activeGlowIcons,
    ScheduleGlowScan = ScanAllGlows,
    GetGlowState = function(icon)
        return activeGlowIcons[icon] and { active = true } or nil
    end,
}


