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

local function ForEachSpellCandidate(spellID, callback)
    if not spellID or not callback then return end

    local seen = {}
    local function Visit(id)
        if id and not seen[id] then
            seen[id] = true
            callback(id)
        end
    end

    Visit(spellID)

    if C_Spell and C_Spell.GetOverrideSpell then
        local ok, overrideID = pcall(C_Spell.GetOverrideSpell, spellID)
        if ok and overrideID and overrideID ~= spellID then
            -- GetOverrideSpell can return secret values in combat; sanitize
            -- before using as a Lua table key downstream.
            Visit(Helpers.SafeValue(overrideID, nil))
        end
    end
end

local function GetChildSpellID(child)
    if not child or not child.GetSpellID then return nil end
    local ok, spellID = pcall(child.GetSpellID, child)
    if ok and spellID then
        return spellID
    end
    return nil
end

local function GetChildAuraSpellID(child)
    if not child or not child.GetAuraSpellID then return nil end
    local ok, spellID = pcall(child.GetAuraSpellID, child)
    if ok and spellID then
        return spellID
    end
    return nil
end

local function GetPreferredSpellID(icon)
    if not icon or not icon._spellEntry then return nil end

    local entry = icon._spellEntry
    local child = entry._blizzChild
    local childSpellID = GetChildSpellID(child)
    if childSpellID then
        return childSpellID
    end

    local childAuraSpellID = GetChildAuraSpellID(child)
    if childAuraSpellID then
        return childAuraSpellID
    end

    if icon._runtimeSpellID then
        return icon._runtimeSpellID
    end

    local CDMSpellData = ns.CDMSpellData
    if CDMSpellData and CDMSpellData.ResolveDisplaySpellID then
        local resolvedID = CDMSpellData:ResolveDisplaySpellID(entry)
        if resolvedID then
            return resolvedID
        end
    end

    return entry.overrideSpellID or entry.spellID or entry.id
end

local function ForEachIconSpellID(icon, callback)
    if not icon or not icon._spellEntry or not callback then return end

    local entry = icon._spellEntry
    local child = entry._blizzChild
    local rawSeen = {}
    local candidateSeen = {}

    local function VisitRaw(id)
        if not id or rawSeen[id] then return end
        rawSeen[id] = true
        ForEachSpellCandidate(id, function(candidateID)
            if candidateID and not candidateSeen[candidateID] then
                candidateSeen[candidateID] = true
                callback(candidateID)
            end
        end)
    end

    -- entry.* come from our spell registration and are always non-secret.
    VisitRaw(entry.spellID)
    VisitRaw(entry.overrideSpellID)
    VisitRaw(entry.id)

    -- Blizzard-sourced IDs (runtime override, child GetSpellID/GetAuraSpellID,
    -- cooldownInfo.*) can be secret values in combat. Sanitize at the boundary;
    -- downstream dedup/lookup tables are keyed by non-secret IDs from overlay
    -- event payloads and registered spell entries, so secret IDs couldn't match
    -- anyway. Combat misses here are covered by SPELL_ACTIVATION_OVERLAY_GLOW
    -- events, which deliver non-secret spellIDs directly to ScanGlowsForSpell.
    VisitRaw(Helpers.SafeValue(icon._runtimeSpellID, nil))
    VisitRaw(Helpers.SafeValue(GetChildSpellID(child), nil))
    VisitRaw(Helpers.SafeValue(GetChildAuraSpellID(child), nil))

    local CDMSpellData = ns.CDMSpellData
    if CDMSpellData and CDMSpellData.ResolveDisplaySpellID then
        -- ResolveDisplaySpellID returns child:GetSpellID() which can be a secret
        -- value in combat; sanitize before using as a Lua table key downstream.
        VisitRaw(Helpers.SafeValue(CDMSpellData:ResolveDisplaySpellID(entry), nil))
    end

    local info = child and child.cooldownInfo
    if info then
        VisitRaw(Helpers.SafeValue(info.spellID, nil))
        VisitRaw(Helpers.SafeValue(info.overrideSpellID, nil))
        VisitRaw(Helpers.SafeValue(info.overrideTooltipSpellID, nil))

        if info.linkedSpellIDs then
            for _, linkedSpellID in ipairs(info.linkedSpellIDs) do
                VisitRaw(Helpers.SafeValue(linkedSpellID, nil))
            end
        end
    end
end

-- Safe wrapper: C_Spell.IsSpellUsable can return secret values in Midnight.
local function SafeIsSpellUsable(spellID)
    if not spellID or not C_Spell or not C_Spell.IsSpellUsable then return true, false end
    local ok, usable, noMana = pcall(C_Spell.IsSpellUsable, spellID)
    if not ok then return true, false end
    return usable and true or false, noMana and true or false
end

-- Check if an icon's spell is fully castable: off cooldown, no active aura, has resources.
local function IsSpellCastable(icon)
    if not icon or not icon._spellEntry then return false end
    if icon._auraActive then return false end
    -- GCD-only cooldowns don't make a spell uncastable — skip the check
    -- so procOnUsable glow persists through the GCD swipe window.
    if icon._hasCooldownActive and not icon._isOnGCD then return false end
    local spellID = GetPreferredSpellID(icon)
    if not spellID then return false end
    return SafeIsSpellUsable(spellID)
end

local function GetSpellGlowOverride(icon)
    if not icon or not icon._spellEntry then return nil end

    local entry = icon._spellEntry
    local CDMSpellData = ns.CDMSpellData
    if not CDMSpellData or not entry.viewerType then return nil end

    local lookupID = entry.spellID or entry.id
    if not lookupID then return nil end

    return CDMSpellData:GetSpellOverride(entry.viewerType, lookupID)
end

local GetSettings = Helpers.CreateDBGetter("customGlow")

local function IsPandemicMirroringEnabled(icon)
    if not icon or not icon._spellEntry then return false end

    local settings = GetSettings()
    if not settings then return true end

    local viewerType = icon._spellEntry.viewerType
    if viewerType == "essential" then
        return settings.essentialPandemicEnabled ~= false
    elseif viewerType == "utility" then
        return settings.utilityPandemicEnabled ~= false
    elseif viewerType == "buff" then
        return settings.buffPandemicEnabled ~= false
    elseif viewerType then
        -- Custom container: uses viewerType as prefix
        return settings[viewerType .. "PandemicEnabled"] ~= false
    end

    return false
end

-- Forward declarations for hook-driven pandemic helpers.
local HookBlizzPandemic
local ClearPandemicState
local SyncGlowForIcon
local ResyncPandemicGlows

-- Track which icons currently have active glows
local activeGlowIcons = {}  -- [icon] = true

-- Reverse lookup: spellID → list of icons that track it.
-- Allows O(1) dispatch on SHOW/HIDE events instead of scanning all icons.
local spellIdToGlowIcons = {}  -- [spellID] = {icon, ...}
do local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "CDM_overlayedSpells", tbl = overlayedSpells }
    mp[#mp + 1] = { name = "CDM_glowSpellMap",    tbl = spellIdToGlowIcons }
    mp[#mp + 1] = { name = "CDM_activeGlows",     tbl = activeGlowIcons }
end

local function RebuildGlowSpellMap()
    wipe(spellIdToGlowIcons)
    local CDMIcons = ns.CDMIcons
    if not CDMIcons then return end
    for _, viewerType in ipairs({"essential", "utility"}) do
        local pool = CDMIcons:GetIconPool(viewerType)
        for _, icon in ipairs(pool) do
            if icon._spellEntry then
                local ids = {}
                local seen = {}
                local function AddID(id)
                    if id and not seen[id] then
                        seen[id] = true
                        ids[#ids + 1] = id
                    end
                end

                ForEachIconSpellID(icon, AddID)

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

-- SETTINGS ACCESS
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- DETERMINE VIEWER TYPE FROM ICON
-- Uses icon._spellEntry.viewerType instead of checking parent frame.
---------------------------------------------------------------------------
local function GetViewerType(icon)
    if not icon or not icon._spellEntry then return nil end
    local vt = icon._spellEntry.viewerType
    if vt == "essential" then return "Essential"
    elseif vt == "utility" then return "Utility"
    elseif vt then return vt  -- custom container key
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
    else
        -- Custom container: uses viewerType as prefix (e.g., "custom_1Enabled")
        local prefix = viewerType
        if not settings[prefix .. "Enabled"] then return nil end
        return {
            enabled = true,
            glowType = settings[prefix .. "GlowType"] or "Pixel Glow",
            color = settings[prefix .. "Color"] or {0.95, 0.95, 0.32, 1},
            lines = settings[prefix .. "Lines"] or 14,
            frequency = settings[prefix .. "Frequency"] or 0.25,
            thickness = settings[prefix .. "Thickness"] or 2,
            scale = settings[prefix .. "Scale"] or 1,
            xOffset = settings[prefix .. "XOffset"] or 0,
            yOffset = settings[prefix .. "YOffset"] or 0,
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
-- PANDEMIC GLOW: hook Blizzard CDM children's ShowPandemicStateFrame /
-- HidePandemicStateFrame. Blizzard calls these every OnUpdate tick.
-- Zero polling, zero API queries, zero secret value issues.
---------------------------------------------------------------------------
local PANDEMIC_LINGER = 0.1
local _pandemicState = setmetatable({}, { __mode = "k" })
local _pandemicGlowIcons = setmetatable({}, { __mode = "k" })  -- [icon] = true when glow is pandemic-driven

local function StartPandemicGlow(icon)
    if not icon or not icon._spellEntry or not icon:IsShown() then return end
    if not IsPandemicMirroringEnabled(icon) then return end

    local spellOvr = GetSpellGlowOverride(icon)
    if spellOvr and spellOvr.glowEnabled == false then return end

    _pandemicGlowIcons[icon] = true
    if not activeGlowIcons[icon] then
        StartGlow(icon, spellOvr)
    end
end

HookBlizzPandemic = function(icon, blizzChild)
    if not blizzChild or not blizzChild.ShowPandemicStateFrame then return end

    local state = _pandemicState[blizzChild]
    if not state then
        state = {}
        _pandemicState[blizzChild] = state
    end
    local wasActive = state.active
    if state.icon and state.icon ~= icon then
        local oldIcon = state.icon
        _pandemicGlowIcons[oldIcon] = nil
        if activeGlowIcons[oldIcon] then
            if oldIcon._spellEntry then
                SyncGlowForIcon(oldIcon)
            else
                StopGlow(oldIcon)
            end
        end
    end
    state.icon = icon

    if wasActive then
        if icon and icon._spellEntry and icon:IsShown() then
            StartPandemicGlow(icon)
        else
            state.active = nil
            state.lastFire = nil
        end
    end

    if state.hooked then return end
    state.hooked = true

    hooksecurefunc(blizzChild, "ShowPandemicStateFrame", function(self)
        local s = _pandemicState[self]
        if not s or not s.icon then return end
        s.lastFire = GetTime()
        if not s.active then
            s.active = true
            StartPandemicGlow(s.icon)
            if not _pandemicGlowIcons[s.icon]
                and (not s.icon._spellEntry or not s.icon:IsShown()) then
                s.active = nil
                s.lastFire = nil
            end
        end
    end)

    hooksecurefunc(blizzChild, "HidePandemicStateFrame", function(self)
        local s = _pandemicState[self]
        if not s or not s.active then return end
        local last = s.lastFire
        if last and (GetTime() - last) < PANDEMIC_LINGER then return end
        local icon = s.icon
        s.active = nil
        if icon then
            _pandemicGlowIcons[icon] = nil
            if icon._spellEntry then
                SyncGlowForIcon(icon)
            elseif activeGlowIcons[icon] then
                StopGlow(icon)
            end
        end
    end)
end

ClearPandemicState = function(icon)
    if not icon then return end

    _pandemicGlowIcons[icon] = nil

    for _, state in pairs(_pandemicState) do
        if state.icon == icon then
            state.icon = nil
            state.active = nil
            state.lastFire = nil
        end
    end

    if activeGlowIcons[icon] then
        StopGlow(icon)
    end
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

local function EvaluateGlowForIcon(icon, includeHidden)
    if not icon or not icon._spellEntry then
        return false, nil
    end
    if not includeHidden and not icon:IsShown() then
        return false, nil
    end

    local spellOvr = GetSpellGlowOverride(icon)

    local shouldGlow
    if spellOvr and spellOvr.glowEnabled == false then
        shouldGlow = false
    elseif spellOvr and spellOvr.glowEnabled == true then
        shouldGlow = true
    else
        shouldGlow = false
        ForEachIconSpellID(icon, function(spellID)
            if not shouldGlow and IsOverlayed(spellID) then
                shouldGlow = true
            end
        end)
    end

    if not shouldGlow and spellOvr and spellOvr.procOnUsable then
        shouldGlow = IsSpellCastable(icon)
    end

    return shouldGlow and true or false, spellOvr
end

SyncGlowForIcon = function(icon)
    local shouldGlow, spellOvr = EvaluateGlowForIcon(icon)

    if shouldGlow and not activeGlowIcons[icon] then
        StartGlow(icon, spellOvr)
    elseif not shouldGlow and activeGlowIcons[icon] and not _pandemicGlowIcons[icon] then
        StopGlow(icon)
    end
end

ResyncPandemicGlows = function()
    for _, state in pairs(_pandemicState) do
        local icon = state.icon
        if state.active and icon and icon._spellEntry and icon:IsShown() then
            StartPandemicGlow(icon)
        end
    end
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
            if not icon:IsShown() then -- skip hidden icons (glow re-applied on layout refresh)
                -- noop: skip
            elseif icon._spellEntry then
                SyncGlowForIcon(icon)
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

    -- Deduplicate icons across candidates
    local visited = {}
    local matched = false
    ForEachSpellCandidate(spellID, function(id)
        local icons = spellIdToGlowIcons[id]
        if icons then
            matched = true
            for _, icon in ipairs(icons) do
                if not visited[icon] then
                    visited[icon] = true
                    if icon:IsShown() and icon._spellEntry then
                        SyncGlowForIcon(icon)
                    end
                end
            end
        end
    end)

    if not matched then
        -- Proc events are infrequent; if the fast reverse map misses because
        -- Blizzard reported a related spellID we do not currently index,
        -- rescan all visible icons immediately so short overlays are not lost.
        ScanAllGlows()
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
    wipe(_pandemicGlowIcons)

    -- Rebuild reverse lookup and re-scan with current settings
    RebuildGlowSpellMap()
    ScanAllGlows()
    ResyncPandemicGlows()
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
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("SPELL_UPDATE_USABLE")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")

-- Coalesced usability glow scan: 100ms delay lets CDM's 50ms update finish first
-- so icon._hasCooldownActive is current when we check IsSpellCastable.
local _usabilityGlowPending = false
local function ScheduleUsabilityGlowScan()
    if _usabilityGlowPending then return end
    _usabilityGlowPending = true
    C_Timer.After(0.1, function()
        _usabilityGlowPending = false
        ScanAllGlows()
    end)
end

eventFrame:SetScript("OnEvent", function(_, event, spellID)
    if event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_USABLE" then
        ScheduleUsabilityGlowScan()
        return
    end
    if event == "PLAYER_TARGET_CHANGED" then
        ScheduleUsabilityGlowScan()
        return
    end
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

ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "CDM_Glows", frame = eventFrame }

-- Low-frequency fallback scan to catch edge cases (e.g. icon replaced
-- with an already-active proc, no SHOW event fires for it)
C_Timer.NewTicker(5, function()
    ScanAllGlows()
end)

---------------------------------------------------------------------------
-- EXPORTS
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
    IsSpellCastable = IsSpellCastable,
    ShouldIconGlow = function(icon)
        local shouldGlow = EvaluateGlowForIcon(icon, true)
        return shouldGlow and true or false
    end,
    SyncGlowForIcon = SyncGlowForIcon,
    HookBlizzPandemic = HookBlizzPandemic,
    ClearPandemicState = ClearPandemicState,
    GetGlowState = function(icon)
        return activeGlowIcons[icon] and { active = true } or nil
    end,
}


