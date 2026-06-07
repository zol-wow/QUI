-- cdm_effects.lua
-- Visual effects for addon-owned CDM icons.


-- Proc and aura glow effects for addon-owned CDM icons.
-- Simplified: applies LibCustomGlow directly to addon-owned icon frames.
-- No overlay frame indirection, no Blizzard glow suppression needed.

local _, ns = ...
local Helpers = ns.Helpers
local Sources = ns.CDMSources
local Shared = ns.CDMShared
local Resolvers = ns.CDMResolvers

local function IsCDMRuntimeEnabled()
    return not Shared or Shared.IsRuntimeEnabled()
end

local function GetBuiltinCooldownContainerKeys()
    if Shared and Shared.GetBuiltinContainerKeysByEntryKind then
        return Shared.GetBuiltinContainerKeysByEntryKind("cooldown")
    end
    return {}
end

local function GetBuiltinIconContainerKeys()
    if Shared and Shared.GetBuiltinContainerKeysByShape then
        return Shared.GetBuiltinContainerKeysByShape("icon")
    end
    return {}
end

local function IsBuiltinAuraContainerKey(containerKey)
    if Shared and Shared.IsBuiltinAuraContainerKey then
        return Shared.IsBuiltinAuraContainerKey(containerKey)
    end
    return false
end

-- Pandemic step curve: lazily built, cached. The curve evaluates C-side and
-- yields a secret userdata (LuaCurveEvaluatedResult) that flows directly into
-- SetAlpha; never compared, arithmetic'd, or read into Lua. Mirrors the HP
-- alpha-curve pattern in hud_visibility.lua.
local _pandemicCurve

local function GetPandemicCurve()
    if _pandemicCurve then return _pandemicCurve end
    if not C_CurveUtil or not C_CurveUtil.CreateCurve
       or not Enum or not Enum.LuaCurveType then
        return nil
    end
    local curve = C_CurveUtil.CreateCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    -- Negative-side anchor: if the cached _lastAuraDurObj outlives the
    -- aura it represents (icon-side state didn't observe the removal in
    -- time, or the resolver returned r.durObj=nil while r.isActive=true
    -- and ApplyAuraStateToIcon kept the stale cached durObj), then
    -- EvaluateRemainingPercent on that durObj produces a NEGATIVE value
    -- once GetTime() is past startTime+duration. Without this anchor the
    -- step curve falls back to the lowest defined point's value (1) for
    -- any x below 0, leaving the glow stuck on permanently.
    curve:AddPoint(-1.0, 0) -- expired / negative percent: hide
    curve:AddPoint(0.0, 1)  -- 0..<30% remaining: glow visible
    curve:AddPoint(0.3, 0)  -- 30%+ remaining: glow hidden
    _pandemicCurve = curve
    return curve
end

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
local overlayedSpellCounts = {}  -- [spellID] = refcount
local overlayedSourceMap = {}  -- [sourceSpellID] = { [candidateID] = true }

-- Glow-spell-candidate gathering rewritten without per-call closures.
-- Previously `ForEachSpellCandidate` + `ForEachIconSpellID` took callbacks
-- and `EvaluateGlowForIcon` allocated 3 fresh closures per icon glow eval
-- (one outer, one VisitRaw, one inner candidate). With 100+ icons walked
-- many times per second during combat that dominated FR_CDM_Glows churn.
-- The new helpers fill module-level scratch tables; callers iterate them
-- directly with for-loops. No allocations in the hot path.

local _iconRawSeen = {}
local _iconCandidateSeen = {}
local _iconSpellIDScratch = {}
local _iconSpellIDScratchN = 0

-- Visit one raw spellID candidate. Resolves Blizzard's override spell once
-- and emits up to two deduplicated candidates into _iconSpellIDScratch.
-- Operates on module-level scratch; safe to call repeatedly until the next
-- GatherIconSpellIDs() reset.
local function VisitRawSpellID(id)
    if not id or _iconRawSeen[id] then return end
    _iconRawSeen[id] = true
    if not _iconCandidateSeen[id] then
        _iconCandidateSeen[id] = true
        local n = _iconSpellIDScratchN + 1
        _iconSpellIDScratchN = n
        _iconSpellIDScratch[n] = id
    end
    local overrideID = Sources and Sources.QueryOverrideSpell
        and Sources.QueryOverrideSpell(id)
    if overrideID and overrideID ~= id and not _iconCandidateSeen[overrideID] then
        _iconCandidateSeen[overrideID] = true
        local n = _iconSpellIDScratchN + 1
        _iconSpellIDScratchN = n
        _iconSpellIDScratch[n] = overrideID
    end
end

-- Fills _iconSpellIDScratch[1..N] with deduplicated candidate spellIDs for
-- the icon (seed IDs and their Blizzard overrides). Returns N. Callers
-- must consume the result before the next GatherIconSpellIDs() call.
local function GatherIconSpellIDs(icon)
    _iconSpellIDScratchN = 0
    if not icon or not icon._spellEntry then return 0 end
    wipe(_iconRawSeen)
    wipe(_iconCandidateSeen)

    local entry = icon._spellEntry
    -- entry.* come from our spell registration and are always non-secret.
    VisitRawSpellID(entry.spellID)
    VisitRawSpellID(entry.overrideSpellID)
    VisitRawSpellID(entry.id)

    -- Runtime override may be a secret value in combat; sanitize at the
    -- boundary. Combat misses here are covered by
    -- SPELL_ACTIVATION_OVERLAY_GLOW events, which deliver non-secret
    -- spellIDs directly to ScanGlowsForSpell.
    VisitRawSpellID(icon._runtimeSpellID)

    local CDMSpellData = ns.CDMSpellData
    if CDMSpellData and CDMSpellData.ResolveDisplaySpellID then
        VisitRawSpellID(CDMSpellData:ResolveDisplaySpellID(entry))
    end

    if entry.linkedSpellIDs then
        for _, linkedSpellID in ipairs(entry.linkedSpellIDs) do
            VisitRawSpellID(linkedSpellID)
        end
    end

    return _iconSpellIDScratchN
end

local function ClearOverlaySource(sourceSpellID)
    local mapped = sourceSpellID and overlayedSourceMap[sourceSpellID]
    if not mapped then return end
    for candidateID in pairs(mapped) do
        local count = (overlayedSpellCounts[candidateID] or 0) - 1
        if count > 0 then
            overlayedSpellCounts[candidateID] = count
            overlayedSpells[candidateID] = true
        else
            overlayedSpellCounts[candidateID] = nil
            overlayedSpells[candidateID] = nil
        end
    end
    overlayedSourceMap[sourceSpellID] = nil
end

local function MarkOverlaySource(sourceSpellID)
    if not sourceSpellID then return end
    ClearOverlaySource(sourceSpellID)
    -- mapped is stored persistently in overlayedSourceMap, so this
    -- allocation is intentional (one per MarkOverlaySource call).
    local mapped = {}
    mapped[sourceSpellID] = true
    overlayedSpellCounts[sourceSpellID] = (overlayedSpellCounts[sourceSpellID] or 0) + 1
    overlayedSpells[sourceSpellID] = true
    local overrideID = Sources and Sources.QueryOverrideSpell
        and Sources.QueryOverrideSpell(sourceSpellID)
    if overrideID and overrideID ~= sourceSpellID then
        mapped[overrideID] = true
        overlayedSpellCounts[overrideID] = (overlayedSpellCounts[overrideID] or 0) + 1
        overlayedSpells[overrideID] = true
    end
    overlayedSourceMap[sourceSpellID] = mapped
end

local function QueryReadableSpellUsable(spellID)
    if not spellID or not (Sources and Sources.QuerySpellUsable) then return true, false end
    local usable, noMana = Sources.QuerySpellUsable(spellID)
    usable = type(usable) == "boolean" and usable or nil
    noMana = type(noMana) == "boolean" and noMana or false
    return usable and true or false, noMana and true or false
end

-- Explicit per-spell override: glow when this ability becomes castable.
local function IsSpellCastable(icon)
    if not icon or not icon._spellEntry then return false end
    if icon._auraActive then return false end
    if icon._hasCooldownActive then return false end
    local spellID = icon._runtimeSpellID
        or icon._spellEntry.overrideSpellID
        or icon._spellEntry.spellID
    if not spellID then return false end
    return QueryReadableSpellUsable(spellID)
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
    if not viewerType then return false end

    -- Built-in viewers and custom containers all use the viewerType as
    -- the settings-key prefix.
    local debuffKey = viewerType .. "PandemicDebuffEnabled"
    local buffKey   = viewerType .. "PandemicBuffEnabled"
    local debuffOn = settings[debuffKey] ~= false
    local buffOn   = settings[buffKey]   ~= false

    -- Pick the relevant toggle from the cached aura type. When the type
    -- is unknown (aura first observed in combat without auraData), fall
    -- back to "show if either toggle is on" so combat-applied auras
    -- don't suddenly lose their pandemic glow.
    local isHarmful = icon._auraIsHarmful
    if isHarmful == true  then return debuffOn end
    if isHarmful == false then return buffOn   end
    return debuffOn or buffOn
end

-- Forward declarations.
local ClearPandemicState
local SyncGlowForIcon
local UpdatePandemicGlow
local HasProcOnUsableOverride

-- Track which icons currently have active glows
local activeGlowIcons = {}  -- [icon] = true

-- Reverse lookup: spellID -> list of icons that track it.
-- Allows O(1) dispatch on SHOW/HIDE events instead of scanning all icons.
local spellIdToGlowIcons = {}  -- [spellID] = {icon, ...}
local procOnUsableGlowIcons = {}
local procOnUsableGlowMapReady = false
-- SetupDebugInstrumentation is defined at the bottom of the file (it captures
-- eventFrame for QUI_PerfRegistry).

local function AddGlowMapID(spellID, icon)
    if not spellID then return end
    local list = spellIdToGlowIcons[spellID]
    if not list then
        list = {}
        spellIdToGlowIcons[spellID] = list
    end
    list[#list + 1] = icon
end

local function AddIconToGlowMaps(icon)
    if not icon or not icon._spellEntry then return end
    local spellID = icon._spellEntry.spellID
    local overrideID = icon._spellEntry.overrideSpellID
    AddGlowMapID(spellID, icon)
    if overrideID and overrideID ~= spellID then
        AddGlowMapID(overrideID, icon)
    end
    if HasProcOnUsableOverride and HasProcOnUsableOverride(icon) then
        procOnUsableGlowIcons[#procOnUsableGlowIcons + 1] = icon
    end
end

local _rebuildGlowSpellMapInFlight = false
local function RebuildGlowSpellMap()
    -- Reentry guard: a future change inside AddIconToGlowMaps that triggers
    -- Rebuild again would otherwise wipe the maps mid-population. AddIcon
    -- is currently a leaf, but the guard keeps the invariant cheap.
    if _rebuildGlowSpellMapInFlight then return end
    _rebuildGlowSpellMapInFlight = true
    wipe(spellIdToGlowIcons)
    wipe(procOnUsableGlowIcons)
    procOnUsableGlowMapReady = false
    local IconFactory = ns.CDMIconFactory
    if not IconFactory then
        _rebuildGlowSpellMapInFlight = false
        return
    end
    if IconFactory.ForEachIcon then
        IconFactory:ForEachIcon(function(icon)
            AddIconToGlowMaps(icon)
        end)
        procOnUsableGlowMapReady = true
        _rebuildGlowSpellMapInFlight = false
        return
    end
    for _, viewerType in ipairs(GetBuiltinCooldownContainerKeys()) do
        local pool = IconFactory:GetIconPool(viewerType)
        for _, icon in ipairs(pool) do
            AddIconToGlowMaps(icon)
        end
    end
    procOnUsableGlowMapReady = true
    _rebuildGlowSpellMapInFlight = false
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
-- Applied directly to owned icons; no overlay frame needed.
---------------------------------------------------------------------------

-- Ensure glow frame renders above the Cooldown swipe.
-- LibCustomGlow sets glow at icon:GetFrameLevel() + 8, but HUD layering
-- can push CooldownFrameTemplate above that. Reference the Cooldown frame
-- directly (same pattern as TextOverlay in cdm_icon_renderer.lua:659).
-- Layer order: Cooldown swipe (cdLevel) -> Glow (+1) -> Text (+1) -> ClickButton (+2)
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
-- Expose to subsequent file chunks so the highlighter and other consumers
-- share the same layer-coordination behavior (was previously a thinner
-- per-chunk duplicate that skipped the text-overlay anchoring).
ns._CDM_EnsureGlowAboveCooldown = EnsureGlowAboveCooldown

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
        LCG.PixelGlow_Stop(icon, "_QUICustomGlow")
        LCG.AutoCastGlow_Stop(icon, "_QUICustomGlow")
        LCG.ButtonGlow_Stop(icon)
        LCG.ProcGlow_Stop(icon, "_QUICustomGlow")
    end
    StopTextureGlow(icon, "_QUIFlashGlow")
    StopTextureGlow(icon, "_QUIHammerGlow")
    activeGlowIcons[icon] = nil
end

---------------------------------------------------------------------------
-- PANDEMIC GLOW: dedicated overlay frame whose alpha is driven by a
-- C_CurveUtil step curve evaluated against the icon's active aura
-- DurationObject. The curve evaluates C-side and the result is secret
-- userdata that flows directly into SetAlpha; no Lua-side compare or
-- arithmetic. Mirrors hud_visibility's UnitHealthPercent + curve pattern.
---------------------------------------------------------------------------
local PANDEMIC_TEXTURE = FLASH_TEXTURE  -- reuse the proc-glow flash sheet

local function EnsurePandemicGlowFrame(icon)
    if not icon then return nil end
    local frame = icon.PandemicGlow
    if frame then return frame end

    frame = CreateFrame("Frame", nil, icon)
    frame:SetAllPoints(icon)
    frame:SetAlpha(0)

    local tex = frame:CreateTexture(nil, "OVERLAY")
    tex:SetTexture(PANDEMIC_TEXTURE)
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetBlendMode("ADD")
    tex:SetAllPoints(frame)
    tex:SetVertexColor(1, 0.85, 0.2, 1)
    frame.texture = tex

    icon.PandemicGlow = frame
    EnsureGlowAboveCooldown(icon, frame)
    return frame
end

UpdatePandemicGlow = function(icon)
    if not icon or not icon._spellEntry then return end

    local frame = icon.PandemicGlow
    local enabled = IsPandemicMirroringEnabled(icon)
    if not enabled then
        if frame then frame:SetAlpha(0) end
        return
    end

    -- Pandemic glow is intentionally decoupled from the per-spell overlay/proc
    -- glow override: a spell's glowEnabled == false toggle suppresses only its
    -- overlay/proc glow, not its pandemic (aura-expiry) glow. They are distinct
    -- visual signals, so do not gate the pandemic glow on the overlay override.
    if not icon._auraActive or not icon._lastAuraDurObj then
        if frame then frame:SetAlpha(0) end
        return
    end

    local curve = GetPandemicCurve()
    if not curve then
        if frame then frame:SetAlpha(0) end
        return
    end

    frame = frame or EnsurePandemicGlowFrame(icon)
    if not frame then return end

    local durObj = icon._lastAuraDurObj

    -- Gate against permanent / no-duration auras. For an aura with no
    -- duration, EvaluateRemainingPercent lands at the start of the step
    -- curve (alpha 1) and the glow shows permanently. DurationObject:IsZero
    -- is a stable per-aura property (not derived from elapsed/remaining),
    -- and EvaluateColorValueFromBoolean keeps the (potentially-secret) bool
    -- C-side; pass the selected value directly to SetAlpha without reading
    -- or comparing it in Lua. Same pattern as the permanent-aura bar overlay.
    --   IsZero=true  (permanent): texture alpha 0, glow hidden
    --   IsZero=false (timed): texture alpha 1, curve drives frame alpha
    if frame.texture
       and durObj.IsZero
       and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
local okZ = true; local isZero = durObj.IsZero(durObj)
        if okZ then
local okA = true; local gate = C_CurveUtil.EvaluateColorValueFromBoolean(isZero, 0, 1)
            if okA then
                frame.texture.SetAlpha(frame.texture, gate)
            end
        end
    end

    -- Curve evaluates C-side; result is secret userdata; SetAlpha accepts it
    -- natively. Never read back into Lua.
    frame:SetAlpha(durObj:EvaluateRemainingPercent(curve))
end

ClearPandemicState = function(icon)
    if not icon then return end
    if icon.PandemicGlow then
        icon.PandemicGlow:SetAlpha(0)
    end
end

---------------------------------------------------------------------------
-- CHECK OVERLAY STATE: query API + event-based tracking
---------------------------------------------------------------------------
local function IsOverlayQueryActive(spellID)
    if not spellID or not IsSpellOverlayed then return false end
    return IsSpellOverlayed(spellID) and true or false
end

local function IsOverlayed(spellID)
    if not spellID then return false end
    -- Prefer the live query API whenever it exists. The event cache is a
    -- fallback for clients/API paths where the query function is unavailable;
    -- otherwise a missed HIDE event can leave a spell looking permanently procced.
    if IsSpellOverlayed then
        return IsOverlayQueryActive(spellID)
    end
    return overlayedSpells[spellID] or false
end

local function EvaluateGlowForIcon(icon)
    if not icon or not icon:IsShown() or not icon._spellEntry then
        return false, nil
    end

    local entry = icon._spellEntry
    local viewerType = entry.viewerType
    local baseID = entry.spellID
    local overrideID = entry.overrideSpellID

    local spellOvr = GetSpellGlowOverride(icon)

    local shouldGlow
    if spellOvr and spellOvr.glowEnabled == false then
        shouldGlow = false
    elseif spellOvr and spellOvr.glowEnabled == true then
        shouldGlow = true
    else
        local n = GatherIconSpellIDs(icon)
        for i = 1, n do
            if IsOverlayed(_iconSpellIDScratch[i]) then
                shouldGlow = true
                break
            end
        end
    end

    if not shouldGlow and spellOvr and spellOvr.procOnUsable == true then
        shouldGlow = IsSpellCastable(icon)
    end

    return shouldGlow and true or false, spellOvr
end

SyncGlowForIcon = function(icon)
    local shouldGlow, spellOvr = EvaluateGlowForIcon(icon)

    if shouldGlow and not activeGlowIcons[icon] then
        StartGlow(icon, spellOvr)
    elseif not shouldGlow and activeGlowIcons[icon] then
        StopGlow(icon)
    end

    UpdatePandemicGlow(icon)
end

HasProcOnUsableOverride = function(icon)
    local entry = icon and icon._spellEntry
    if not entry then return false end
    if entry.kind == "aura" or entry.kind == "auraBar" then return false end
    local CDMSpellData = ns.CDMSpellData
    if CDMSpellData and CDMSpellData.IsAuraEntry and CDMSpellData.IsAuraEntry(entry) then
        return false
    end
    local spellOvr = GetSpellGlowOverride(icon)
    return spellOvr and spellOvr.glowEnabled ~= false and spellOvr.procOnUsable == true
end

local function ScanProcOnUsableGlows()
    local IconFactory = ns.CDMIconFactory
    if not IconFactory then return end

    if not procOnUsableGlowMapReady then
        RebuildGlowSpellMap()
    end

    if procOnUsableGlowMapReady then
        for i = 1, #procOnUsableGlowIcons do
            local icon = procOnUsableGlowIcons[i]
            if icon and icon:IsShown() and icon._spellEntry and HasProcOnUsableOverride(icon) then
                SyncGlowForIcon(icon)
            end
        end
        return
    end

    for _, viewerType in ipairs(GetBuiltinCooldownContainerKeys()) do
        local pool = IconFactory:GetIconPool(viewerType)
        for _, icon in ipairs(pool) do
            if icon and icon:IsShown() and icon._spellEntry and HasProcOnUsableOverride(icon) then
                SyncGlowForIcon(icon)
            end
        end
    end
end

---------------------------------------------------------------------------
-- SCAN ALL ICONS AND SYNC GLOW STATE
---------------------------------------------------------------------------
-- Hoisted out of ScanAllGlows so IconFactory:ForEachIcon does not allocate
-- a fresh closure per call.
local function _SyncGlowIfVisible(icon)
    if not icon:IsShown() then return end -- skip hidden icons (glow re-applied on layout refresh)
    if icon._spellEntry then
        SyncGlowForIcon(icon)
    end
end

local function ScanAllGlows()
    local IconFactory = ns.CDMIconFactory
    if not IconFactory then return end

    if IconFactory.ForEachIcon then
        IconFactory:ForEachIcon(_SyncGlowIfVisible)
        return
    end

    for _, viewerType in ipairs(GetBuiltinCooldownContainerKeys()) do
        local pool = IconFactory:GetIconPool(viewerType)
        for _, icon in ipairs(pool) do
            _SyncGlowIfVisible(icon)
        end
    end
end

---------------------------------------------------------------------------
-- TARGETED GLOW UPDATE FOR A SINGLE SPELL ID
-- O(1) lookup via reverse map instead of scanning all icons.
---------------------------------------------------------------------------
local _scanGlowVisited = {}

-- Hoisted to avoid a per-call closure: previous ForEachSpellCandidate
-- callback captured `visited`, `matched`, and `spellIdToGlowIcons`. State
-- now lives on module locals; matched is signaled via the return value.
local function _ProcessGlowIconsForCandidate(spellID, visited)
    local icons = spellIdToGlowIcons[spellID]
    if not icons then return false end
    for i = 1, #icons do
        local icon = icons[i]
        if not visited[icon] then
            visited[icon] = true
            if icon:IsShown() and icon._spellEntry then
                SyncGlowForIcon(icon)
            end
        end
    end
    return true
end

local function ScanGlowsForSpell(spellID)
    if not spellID then ScanAllGlows(); return end

    local CDMIcons = ns.CDMIcons
    if not CDMIcons then return end

    -- Deduplicate icons across candidates. Reuse scratch table because
    -- overlay events can fire in bursts during combat.
    local visited = _scanGlowVisited
    wipe(visited)

    local matched = _ProcessGlowIconsForCandidate(spellID, visited)
    local overrideID = Sources and Sources.QueryOverrideSpell
        and Sources.QueryOverrideSpell(spellID)
    if overrideID and overrideID ~= spellID then
        if _ProcessGlowIconsForCandidate(overrideID, visited) then
            matched = true
        end
    end

    if not matched then
        -- Proc events are infrequent; if the fast reverse map misses because
        -- Blizzard reported a related spellID we do not currently index,
        -- rescan all visible icons immediately so short overlays are not lost.
        ScanAllGlows()
    end

    wipe(visited)
end

---------------------------------------------------------------------------
-- REFRESH ALL GLOWS (called when settings change)
---------------------------------------------------------------------------
local _refreshStopScratch = {}

local function StopAllTrackedGlows()
    local toStop = _refreshStopScratch
    wipe(toStop)
    for icon in pairs(activeGlowIcons) do
        toStop[#toStop + 1] = icon
    end
    for _, icon in ipairs(toStop) do
        StopGlow(icon)
        if icon.PandemicGlow then
            icon.PandemicGlow:SetAlpha(0)
        end
    end
    wipe(toStop)
    wipe(activeGlowIcons)
end

local function RefreshAllGlows()
    -- Stop all current glows
    StopAllTrackedGlows()

    if not IsCDMRuntimeEnabled() then
        return
    end

    -- Rebuild reverse lookup and re-scan with current settings
    RebuildGlowSpellMap()
    ScanAllGlows()
end

---------------------------------------------------------------------------
-- EVENT HANDLING
-- Spell activation overlay events drive proc glow updates.
-- Track overlay state in overlayedSpells table for API-free fallback.
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_SHOW")
eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_HIDE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("SPELL_UPDATE_USABLE")
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")

eventFrame:SetScript("OnEvent", function(_, event, spellID)
    if not IsCDMRuntimeEnabled() then
        StopAllTrackedGlows()
        return
    end

    if event == "SPELL_UPDATE_USABLE" or event == "SPELL_UPDATE_COOLDOWN" then
        ScanProcOnUsableGlows()
        return
    end
    if (event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW"
        or event == "SPELL_ACTIVATION_OVERLAY_SHOW") and spellID then
        MarkOverlaySource(spellID)
        ScanGlowsForSpell(spellID)
        return
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE"
        or event == "SPELL_ACTIVATION_OVERLAY_HIDE" then
        if spellID then
            ClearOverlaySource(spellID)
            ScanGlowsForSpell(spellID)
        else
            wipe(overlayedSpells)
            wipe(overlayedSpellCounts)
            wipe(overlayedSourceMap)
            ScanAllGlows()
        end
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        wipe(overlayedSpells)
        wipe(overlayedSpellCounts)
        wipe(overlayedSourceMap)
    end
    ScanAllGlows()
end)

local function SetupDebugInstrumentation()
    local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "CDM_overlayedSpells",       tbl = overlayedSpells }
    mp[#mp + 1] = { name = "CDM_glowSpellMap",          tbl = spellIdToGlowIcons }
    mp[#mp + 1] = { name = "CDM_procOnUsableGlowIcons", tbl = procOnUsableGlowIcons }
    mp[#mp + 1] = { name = "CDM_activeGlows",           tbl = activeGlowIcons }
    ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
    ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "CDM_Glows", frame = eventFrame }
end
if ns.DebugRegister then -- gate contract: core/debug_gate.lua
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation() -- standalone test harness: no gate, run eagerly
end

local function DisableRuntime()
    eventFrame:UnregisterAllEvents()
    eventFrame:SetScript("OnEvent", nil)
    StopAllTrackedGlows()
end

---------------------------------------------------------------------------
-- PANDEMIC AURA REFRESH
-- cdm_spelldata.lua owns UNIT_AURA and calls this after it captures the
-- batched payload. The icon's _lastAuraDurObj (cached by the resolver in
-- ApplyAuraStateToIcon) feeds the C-side curve evaluation; pandemic state
-- never enters Lua.
---------------------------------------------------------------------------
local function HandleUnitAuraChanged(_unit, _updateInfo)
    if not IsCDMRuntimeEnabled() then return end

    for _, icons in pairs(spellIdToGlowIcons) do
        for i = 1, #icons do
            local icon = icons[i]
            if icon and icon:IsShown() and icon._spellEntry then
                UpdatePandemicGlow(icon)
            end
        end
    end
end

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
    UpdatePandemicGlow = UpdatePandemicGlow,
    ClearPandemicState = ClearPandemicState,
    HandleUnitAuraChanged = HandleUnitAuraChanged,
    DisableRuntime = DisableRuntime,
    GetGlowState = function(icon)
        return activeGlowIcons[icon] and { active = true } or nil
    end,
}



---------------------------------------------------------------------------
-- Cooldown highlighter
---------------------------------------------------------------------------


-- Cooldown highlighter: briefly highlights the CDM icon matching a spell
-- the player just cast, giving visual feedback of what was pressed.

local _, ns = ...
local Helpers = ns.Helpers
local Sources = ns.CDMSources
local Shared = ns.CDMShared

local function IsCDMRuntimeEnabled()
    return not Shared or Shared.IsRuntimeEnabled()
end

local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

local FLASH_TEXTURE = [[Interface\AddOns\QUI\assets\iconskin\Flash]]
local HAMMER_TEXTURE = [[Interface\AddOns\QUI\assets\quazii_hammer]]

---------------------------------------------------------------------------
-- SETTINGS
---------------------------------------------------------------------------
local GetSettings = Helpers.CreateDBGetter("cooldownHighlighter")

---------------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------------
local activeHighlights = {}  -- [icon] = timerHandle
local GLOW_KEY = "_QUIHighlighter"

---------------------------------------------------------------------------
-- FIND CDM ICON BY SPELL ID
-- Searches all owned CDM icons for a matching spellID or overrideSpellID.
---------------------------------------------------------------------------
local VIEWER_TYPES = GetBuiltinIconContainerKeys()

local function FindIconBySpellID(castSpellID)
    if not castSpellID then return nil end

    local IconFactory = ns.CDMIconFactory
    if not IconFactory or not IconFactory.GetIconPool then return nil end

    for _, viewerType in ipairs(VIEWER_TYPES) do
        local pool = IconFactory:GetIconPool(viewerType)
        for _, icon in ipairs(pool) do
            if icon and icon._spellEntry and icon:IsShown() then
                local entry = icon._spellEntry
                local baseID = entry.spellID or entry.id
                if baseID == castSpellID then return icon end
                if entry.overrideSpellID and entry.overrideSpellID == castSpellID then return icon end
                if baseID and Sources and Sources.QueryOverrideSpell then
                    local overrideID = Sources.QueryOverrideSpell(baseID)
                    if overrideID and overrideID == castSpellID then return icon end
                end
            end
        end
    end

    return nil
end

---------------------------------------------------------------------------
-- TEXTURE OVERLAY GLOW HELPER
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- HIGHLIGHT APPLICATION
---------------------------------------------------------------------------
local function StopAllGlows(icon)
    if not icon or not LCG then return end
    LCG.PixelGlow_Stop(icon, GLOW_KEY)
    LCG.AutoCastGlow_Stop(icon, GLOW_KEY)
    LCG.ButtonGlow_Stop(icon)
    LCG.ProcGlow_Stop(icon, GLOW_KEY)
    StopTextureGlow(icon, "_QUIFlashHL")
    StopTextureGlow(icon, "_QUIHammerHL")
end

local function RemoveHighlight(icon)
    if not icon then return end
    StopAllGlows(icon)
    activeHighlights[icon] = nil
end

-- Use the canonical EnsureGlowAboveCooldown defined in the effects chunk
-- (exposed via ns._CDM_EnsureGlowAboveCooldown). This was a thinner local
-- duplicate that skipped the text-overlay re-anchoring; unifying ensures
-- the highlighter raises text above glow whenever it raises glow above
-- cooldown.
local EnsureGlowAboveCooldown = ns._CDM_EnsureGlowAboveCooldown

local function ApplyHighlight(icon)
    if not icon or not LCG then return end

    local settings = GetSettings()
    if not settings or not settings.enabled then return end

    -- Remove existing highlight if any
    if activeHighlights[icon] then
        activeHighlights[icon]:Cancel()
        RemoveHighlight(icon)
    end

    local glowType = settings.glowType or "Pixel Glow"
    local color = settings.color or {1, 1, 1, 0.8}
    local duration = settings.duration or 0.4
    local lines = settings.lines or 8
    local thickness = settings.thickness or 1
    local scale = settings.scale or 1
    local frequency = settings.frequency or 0.25

    if glowType == "Pixel Glow" then
        LCG.PixelGlow_Start(icon, color, lines, frequency, nil, thickness, 0, 0, true, GLOW_KEY)
        EnsureGlowAboveCooldown(icon, icon["_PixelGlow_" .. GLOW_KEY])
    elseif glowType == "Autocast Shine" then
        LCG.AutoCastGlow_Start(icon, color, lines, frequency, scale, 0, 0, GLOW_KEY)
        EnsureGlowAboveCooldown(icon, icon["_AutoCastGlow_" .. GLOW_KEY])
    elseif glowType == "Button Glow" then
        LCG.ButtonGlow_Start(icon, color, frequency)
        EnsureGlowAboveCooldown(icon, icon["_ButtonGlow"])

    elseif glowType == "Flash" then
        EnsureGlowAboveCooldown(icon, StartTextureGlow(icon, "_QUIFlashHL", FLASH_TEXTURE, color))

    elseif glowType == "Hammer" then
        EnsureGlowAboveCooldown(icon, StartTextureGlow(icon, "_QUIHammerHL", HAMMER_TEXTURE, color))

    elseif glowType == "Proc Glow" then
        LCG.ProcGlow_Start(icon, {
            key = GLOW_KEY,
            color = color,
            startAnim = true,
        })
        EnsureGlowAboveCooldown(icon, icon["_ProcGlow" .. GLOW_KEY])
    end

    -- Auto-remove after duration
    activeHighlights[icon] = C_Timer.NewTimer(duration, function()
        RemoveHighlight(icon)
    end)
end

---------------------------------------------------------------------------
-- DISPATCH
-- Called by cdm_icon_renderer.lua's central UNIT_SPELLCAST_SUCCEEDED handler. The
-- highlighter no longer registers the event itself; single registration on
-- cdEventFrame avoids the duplicate per-cast dispatch.
---------------------------------------------------------------------------
local function OnPlayerCastSucceeded(castSpellID)
    if not IsCDMRuntimeEnabled() then return end

    local settings = GetSettings()
    if not settings or not settings.enabled then return end
    if not castSpellID then return end

    local icon = FindIconBySpellID(castSpellID)
    if icon then
        ApplyHighlight(icon)
    end
end

local function ClearHighlights()
    for icon, timer in pairs(activeHighlights) do
        if timer and timer.Cancel then
            timer:Cancel()
        end
        RemoveHighlight(icon)
    end
end

local function DisableRuntime()
    ClearHighlights()
end

ns._OwnedHighlighter = {
    DisableRuntime = DisableRuntime,
    OnPlayerCastSucceeded = OnPlayerCastSucceeded,
}

---------------------------------------------------------------------------
-- GLOBAL REFRESH
---------------------------------------------------------------------------
_G.QUI_RefreshCooldownHighlighter = function()
    if not IsCDMRuntimeEnabled() then
        ClearHighlights()
        return
    end

    local settings = GetSettings()
    if not settings or not settings.enabled then
        -- Remove all active highlights
        ClearHighlights()
    end
end

if ns.Registry then
    ns.Registry:Register("cooldownHighlighter", {
        refresh = _G.QUI_RefreshCooldownHighlighter,
        priority = 10,
        group = "cooldowns",
        importCategories = { "cdm" },
    })
end


---------------------------------------------------------------------------
-- Cooldown swipe
---------------------------------------------------------------------------


-- Granular cooldown swipe control for addon-owned CDM icons.
-- Simplified: operates directly on QUI's owned icon frames.
-- No hooks, no pulse tickers, no deferred operations needed.

local _, ns = ...
local Helpers = ns.Helpers
local Shared = ns.CDMShared

-- Default settings
local DEFAULTS = {
    showBuffSwipe = true,
    showCooldownIconAuraPhase = true,
    showBuffIconSwipe = true,
    showGCDSwipe = true,
    showCooldownSwipe = true,
    -- Overlay color: shown when spell/buff is ACTIVE (aura duration)
    overlayColorMode = "default",  -- "default" | "class" | "accent" | "custom"
    overlayColor = {1, 1, 1, 1},
    -- Swipe color: shown when spell is ON COOLDOWN (radial darkening)
    swipeColorMode = "default",
    swipeColor = {1, 1, 1, 1},
}

-- Get settings from AceDB via shared helper
local function GetSettings()
    return Helpers.GetModuleSettings("cooldownSwipe", DEFAULTS)
end

---------------------------------------------------------------------------
-- COLOR RESOLUTION
---------------------------------------------------------------------------
local function GetClassColor()
    local _, class = UnitClass("player")
    local classColor = Helpers.GetClassColorTable(class)
    if classColor then
        return classColor.r, classColor.g, classColor.b, 0.8
    end
    return 1, 1, 1, 0.8
end

-- Resolve r,g,b,a for a given mode + stored color table; nil = leave default.
local function ResolveColor(mode, colorTable)
    if mode == "class" then
        return GetClassColor()
    elseif mode == "accent" then
        local QUI = _G.QUI
        if QUI and QUI.GetSkinColor then
            local r, g, b = QUI:GetSkinColor()
            return r, g, b, 0.8
        end
        return 0.376, 0.647, 0.980, 0.8  -- fallback sky blue
    elseif mode == "custom" then
        local c = colorTable or {}
        return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
    end
    return nil  -- "default": don't override
end

-- CDM default swipe color (dark overlay for cooldowns)
local CDM_DEFAULT_R, CDM_DEFAULT_G, CDM_DEFAULT_B, CDM_DEFAULT_A = 0, 0, 0, 0.8
-- Blizzard default buff/aura overlay color (yellow)
local BLIZZ_BUFF_R, BLIZZ_BUFF_G, BLIZZ_BUFF_B, BLIZZ_BUFF_A = 0.93, 0.77, 0.0, 0.45
local FULL_FRAME_SWIPE_TEXTURE = "Interface\\Buttons\\WHITE8X8"

local function SettingEnabled(value, fallback)
    if Shared and Shared.SettingEnabled then
        return Shared.SettingEnabled(value, fallback)
    end
    return value == nil and fallback == true or value == true
end

---------------------------------------------------------------------------
-- APPLY SWIPE TO A SINGLE ICON
-- Classification prefers the icon's active rendered swipe state:
-- aura phase, then explicit GCD render flag, then cooldown.
---------------------------------------------------------------------------
local function ApplySwipeToIcon(icon, settings)
    if not icon or not icon.Cooldown or not icon._spellEntry then return end
    settings = settings or GetSettings()

    local entry = icon._spellEntry
    local isBuffIcon = (entry.viewerType == "buff")
    -- Aura-kind classification is independent of container shape: an aura
    -- entry on a custom cooldown container or essential/utility (kind="aura")
    -- still gets aura-mode swipe styling. Falls back to viewerType when
    -- CDMSpellData is unavailable during early bootstrap.
    local isAuraEntry
    local CDMSpellData = ns.CDMSpellData
    if CDMSpellData and CDMSpellData.IsAuraEntry then
        isAuraEntry = CDMSpellData.IsAuraEntry(entry, entry.viewerType)
    else
        isAuraEntry = (entry.kind == "aura")
            or IsBuiltinAuraContainerKey(entry.viewerType)
    end

    -- Classify: aura, gcd, inactive, or cooldown. The resolver's active render mode is
    -- authoritative for cooldown-kind icons; fallback aura probing is only for
    -- early/unresolved styling. Otherwise a live aura lookup can recolor a
    -- CooldownFrame that is currently bound to a GCD DurationObject.
    local mode
    local resolvedMode = icon._resolvedCooldownMode
    if isAuraEntry or isBuffIcon then
        mode = "aura"
    elseif resolvedMode == "aura" then
        mode = "aura"
    elseif resolvedMode == "gcd-only" or icon._showingGCDSwipe then
        mode = "gcd"
    elseif resolvedMode == "cooldown" or resolvedMode == "item-cooldown" then
        if icon._hasCooldownActive == false and icon._showingGCDSwipe then
            mode = "gcd"
        elseif icon._hasCooldownActive == false then
            mode = "inactive"
        else
            mode = "cooldown"
        end
    elseif resolvedMode == "charge" then
        mode = "cooldown"
    elseif resolvedMode == "inactive" then
        mode = "inactive"
    elseif icon._auraActive then
        mode = "aura"
    elseif not isBuffIcon then
        if Resolvers and Resolvers.ResolveAuraActiveState then
            local active = Resolvers.ResolveAuraActiveState(entry)
            if active then mode = "aura" end
        end
        -- Buff-pool cross-reference (preserved here, not in the helper;
        -- it depends on the current state of OTHER icons, which is a
        -- visual concern, not a per-entry property).
        if not mode then
            local sid = entry.overrideSpellID or entry.spellID
            local IconFactory = ns.CDMIconFactory
            if sid and IconFactory then
                local buffPool = IconFactory:GetIconPool("buff")
                if buffPool then
                    for _, buffIcon in ipairs(buffPool) do
                        local be = buffIcon._spellEntry
                        if be and (be.overrideSpellID == sid or be.spellID == sid)
                           and buffIcon:IsShown() then
                            mode = "aura"
                            break
                        end
                    end
                end
            end
        end
    end
    if not mode then
        mode = "cooldown"
    end

    -- Swipe visibility
    local showSwipe
    if mode == "aura" then
        if isBuffIcon then
            showSwipe = SettingEnabled(settings.showBuffIconSwipe, true)
        else
            showSwipe = SettingEnabled(settings.showBuffSwipe, true)
        end
    elseif mode == "gcd" then
        showSwipe = SettingEnabled(settings.showGCDSwipe, true)
    elseif mode == "inactive" then
        showSwipe = false
    else
        showSwipe = SettingEnabled(settings.showCooldownSwipe, true)
    end

    -- Apply swipe styling to QUI's native icon.Cooldown.
    local showEdge = showSwipe and (mode == "aura" or (mode == "cooldown" and settings.showRechargeEdge))

    local function applyToCooldown(cd)
        if not cd then return end
        -- Stash intended state on the cooldown frame for later style reapplies.
        cd._quiIntendedDrawSwipe = showSwipe and true or false
        cd._quiIntendedDrawEdge  = showEdge and true or false
        cd._quiIntendedSwipeTexture = FULL_FRAME_SWIPE_TEXTURE
        cd.SetSwipeTexture(cd, FULL_FRAME_SWIPE_TEXTURE)
        cd.SetDrawSwipe(cd, showSwipe and true or false)
        cd.SetDrawEdge(cd, showEdge and true or false)

        -- Apply color and texture based on mode.
        -- When swipe is disabled, force alpha-0 color as a failsafe;
        -- SetCooldownFromDurationObject + SetReverse (aura path) can
        -- internally re-enable drawSwipe on the C-side animation system,
        -- so a transparent color ensures the swipe is invisible regardless.
        local cR, cG, cB, cA
        if not showSwipe then
            cR, cG, cB, cA = 0, 0, 0, 0
        elseif mode == "aura" then
            local oR, oG, oB, oA = ResolveColor(settings.overlayColorMode or "default", settings.overlayColor)
            if not oR then oR, oG, oB, oA = BLIZZ_BUFF_R, BLIZZ_BUFF_G, BLIZZ_BUFF_B, BLIZZ_BUFF_A end
            cR, cG, cB, cA = oR, oG, oB, oA
        else
            local sR, sG, sB, sA = ResolveColor(settings.swipeColorMode or "default", settings.swipeColor)
            if not sR then sR, sG, sB, sA = CDM_DEFAULT_R, CDM_DEFAULT_G, CDM_DEFAULT_B, CDM_DEFAULT_A end
            cR, cG, cB, cA = sR, sG, sB, sA
        end
        cd._quiIntendedSwipeColor = { cR, cG, cB, cA or 1 }
        cd.SetSwipeColor(cd, cR, cG, cB, cA)
    end

    applyToCooldown(icon.Cooldown)
end

---------------------------------------------------------------------------
-- APPLY SWIPE TO A BLIZZARD BUFF VIEWER CHILD
-- These children have .Icon and .Cooldown but no ._spellEntry.
-- Buff viewer children are always auras, so classification is fixed.
---------------------------------------------------------------------------
local function ApplySwipeToBuffChild(icon, settings)
    if not icon or not icon.Cooldown then return end
    settings = settings or GetSettings()

    -- Buff viewer children are always auras in the buff viewer
    local showSwipe = SettingEnabled(settings.showBuffIconSwipe, true)

    icon.Cooldown:SetDrawSwipe(showSwipe)
    icon.Cooldown:SetDrawEdge(showSwipe)

    if not showSwipe then
        icon.Cooldown:SetSwipeColor(0, 0, 0, 0)
    else
        -- Use overlay color (aura mode); default to Blizzard yellow
        local oR, oG, oB, oA = ResolveColor(settings.overlayColorMode or "default", settings.overlayColor)
        if not oR then oR, oG, oB, oA = BLIZZ_BUFF_R, BLIZZ_BUFF_G, BLIZZ_BUFF_B, BLIZZ_BUFF_A end

        icon.Cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
        icon.Cooldown:SetSwipeColor(oR, oG, oB, oA)
    end
end

---------------------------------------------------------------------------
-- REFRESH ALL ICONS
---------------------------------------------------------------------------
local function RefreshAllSwipes()
    local CDMIcons = ns.CDMIcons
    if not CDMIcons then return end

    local settings = GetSettings()

    if CDMIcons.UpdateAllCooldowns then
        CDMIcons:UpdateAllCooldowns()
    end

    -- Addon-owned built-in icon containers.
    local IconFactory = ns.CDMIconFactory
    if not IconFactory then return end
    for _, viewerType in ipairs(GetBuiltinIconContainerKeys()) do
        local pool = IconFactory:GetIconPool(viewerType)
        for _, icon in ipairs(pool) do
            ApplySwipeToIcon(icon, settings)
        end
    end
end

-- EXPORTS
---------------------------------------------------------------------------
ns._OwnedSwipe = {
    Apply = RefreshAllSwipes,
    ApplyToIcon = ApplySwipeToIcon,
    ApplyToBuffChild = ApplySwipeToBuffChild,
    GetSettings = GetSettings,
}
