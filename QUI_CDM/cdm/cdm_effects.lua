local _, ns = ...
local Helpers = ns.Helpers
local Sources = ns.CDMSources
local Shared = ns.CDMShared
local Resolvers = ns.CDMResolvers

local _issecretvalue = issecretvalue or function() return false end

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

local _pandemicCurve

local function GetPandemicCurve()
    if _pandemicCurve then return _pandemicCurve end
    if not C_CurveUtil or not C_CurveUtil.CreateCurve
       or not Enum or not Enum.LuaCurveType then
        return nil
    end
    local curve = C_CurveUtil.CreateCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    curve:AddPoint(-1.0, 0)
    curve:AddPoint(0.0, 1)
    curve:AddPoint(0.3, 0)
    _pandemicCurve = curve
    return curve
end

local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

local FLASH_TEXTURE = (Helpers and Helpers.AssetPath or [[Interface\AddOns\QUI\assets\]]) .. [[iconskin\Flash]]
local HAMMER_TEXTURE = (Helpers and Helpers.AssetPath or [[Interface\AddOns\QUI\assets\]]) .. [[quazii_hammer]]

local IsSpellOverlayed = (C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed)
    or _G.IsSpellOverlayed

local overlayedSpells = {}
local overlayedSpellCounts = {}
local overlayedSourceMap = {}

local overlayGlowSpell = {}
local overlayGlowBase  = {}

local _iconRawSeen = {}
local _iconCandidateSeen = {}
local _iconSpellIDScratch = {}
local _iconSpellIDScratchN = 0

local function GetIconRuntimeState(icon)
    if not icon then return nil end
    local store = ns.CDMRuntimeStore
    if store and store.GetFrameState then
        return store.GetFrameState(icon)
    end
    return icon._cdmRuntimeState
end

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

local function GatherIconSpellIDs(icon)
    _iconSpellIDScratchN = 0
    if not icon or not icon._spellEntry then return 0 end
    wipe(_iconRawSeen)
    wipe(_iconCandidateSeen)

    local entry = icon._spellEntry
    VisitRawSpellID(entry.spellID)
    VisitRawSpellID(entry.overrideSpellID)
    VisitRawSpellID(entry.id)

    VisitRawSpellID(icon._runtimeSpellID)

    local runtimeState = GetIconRuntimeState(icon)
    if runtimeState then
        VisitRawSpellID(runtimeState.spellID)
        local state = runtimeState.state
        if state then
            VisitRawSpellID(state.overrideTooltipSpellID)
            VisitRawSpellID(state.overrideSpellID)
            VisitRawSpellID(state.spellID)
            local linkedSpellIDs = state.linkedSpellIDs
            if type(linkedSpellIDs) == "table" then
                for _, linkedSpellID in ipairs(linkedSpellIDs) do
                    VisitRawSpellID(linkedSpellID)
                end
            end
        end
    end

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

local function MarkOverlayCandidate(mapped, candidateID)
    if not candidateID or mapped[candidateID] then return end
    mapped[candidateID] = true
    overlayedSpellCounts[candidateID] = (overlayedSpellCounts[candidateID] or 0) + 1
    overlayedSpells[candidateID] = true
end

local function MarkOverlaySource(sourceSpellID)
    if not sourceSpellID then return end
    ClearOverlaySource(sourceSpellID)
    local mapped = {}
    MarkOverlayCandidate(mapped, sourceSpellID)
    local overrideID = Sources and Sources.QueryOverrideSpell
        and Sources.QueryOverrideSpell(sourceSpellID)
    MarkOverlayCandidate(mapped, overrideID)
    local baseID = Sources and Sources.QueryBaseSpell
        and Sources.QueryBaseSpell(sourceSpellID)
    if baseID and baseID ~= sourceSpellID then
        MarkOverlayCandidate(mapped, baseID)
        local baseOverrideID = Sources and Sources.QueryOverrideSpell
            and Sources.QueryOverrideSpell(baseID)
        MarkOverlayCandidate(mapped, baseOverrideID)
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

local IsOverlayed

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

local function GetSpellGlowOverrideForID(viewerType, spellID)
    local CDMSpellData = ns.CDMSpellData
    if not CDMSpellData or not viewerType or not spellID then return nil end
    return CDMSpellData:GetSpellOverride(viewerType, spellID)
end

local function GetSpellGlowOverride(icon)
    if not icon or not icon._spellEntry then return nil end

    local entry = icon._spellEntry
    local lookupID = entry.spellID or entry.id
    return GetSpellGlowOverrideForID(entry.viewerType, lookupID)
end

local function IsGlowOverrideDisabled(override)
    return override and override.glowEnabled == false
end

local function IsOverlayCandidateAllowed(viewerType, candidateID)
    local candidateOvr = GetSpellGlowOverrideForID(viewerType, candidateID)
    if not IsGlowOverrideDisabled(candidateOvr) then
        return true, candidateOvr
    end

    for sourceID, mapped in pairs(overlayedSourceMap) do
        if mapped[candidateID] then
            local sourceOvr = GetSpellGlowOverrideForID(viewerType, sourceID)
            if not IsGlowOverrideDisabled(sourceOvr) then
                return true, sourceOvr
            end
        end
    end

    return false, candidateOvr
end

local function FindAllowedOverlayGlow(icon, viewerType)
    local n = GatherIconSpellIDs(icon)
    for i = 1, n do
        local candidateID = _iconSpellIDScratch[i]
        if IsOverlayed(candidateID) then
            local allowed, candidateOvr = IsOverlayCandidateAllowed(viewerType, candidateID)
            if allowed then
                return true, candidateOvr, candidateID
            end
        end
    end
    return false, nil, nil
end

local GetSettings = Helpers.CreateDBGetter("customGlow")

local _pandemicDebuffKeys = {}
local _pandemicBuffKeys = {}

local function IsPandemicMirroringEnabled(icon)
    if not icon or not icon._spellEntry then return false end

    local settings = GetSettings()
    if not settings then return true end

    local viewerType = icon._spellEntry.viewerType
    if not viewerType then return false end

    local debuffKey = _pandemicDebuffKeys[viewerType]
    local buffKey   = _pandemicBuffKeys[viewerType]
    if not debuffKey then
        debuffKey = viewerType .. "PandemicDebuffEnabled"
        buffKey   = viewerType .. "PandemicBuffEnabled"
        _pandemicDebuffKeys[viewerType] = debuffKey
        _pandemicBuffKeys[viewerType]   = buffKey
    end
    local debuffOn = settings[debuffKey] ~= false
    local buffOn   = settings[buffKey]   ~= false

    local isHarmful = icon._auraIsHarmful
    if isHarmful == true  then return debuffOn end
    if isHarmful == false then return buffOn   end
    return debuffOn or buffOn
end

local ClearPandemicState
local SyncGlowForIcon
local UpdatePandemicGlow
local HasProcOnUsableOverride

local activeGlowIcons = {}
local buttonGlowOwners = {}

local spellIdToGlowIcons = {}
local procOnUsableGlowIcons = {}
local procOnUsableGlowMapReady = false

local function AddGlowMapID(spellID, icon)
    if _issecretvalue(spellID) then return end
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
    local runtimeState = GetIconRuntimeState(icon)
    if runtimeState then
        AddGlowMapID(runtimeState.spellID, icon)
        local state = runtimeState.state
        if state then
            AddGlowMapID(state.overrideTooltipSpellID, icon)
            AddGlowMapID(state.overrideSpellID, icon)
            AddGlowMapID(state.spellID, icon)
            local linkedSpellIDs = state.linkedSpellIDs
            if type(linkedSpellIDs) == "table" then
                for _, linkedSpellID in ipairs(linkedSpellIDs) do
                    AddGlowMapID(linkedSpellID, icon)
                end
            end
        end
    end
    if HasProcOnUsableOverride and HasProcOnUsableOverride(icon) then
        procOnUsableGlowIcons[#procOnUsableGlowIcons + 1] = icon
    end
end

local _rebuildGlowSpellMapInFlight = false
local function RebuildGlowSpellMap()
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

local function GetViewerType(icon)
    if not icon or not icon._spellEntry then return nil end
    local vt = icon._spellEntry.viewerType
    if vt == "essential" then return "Essential"
    elseif vt == "utility" then return "Utility"
    elseif vt then return vt
    end
    return nil
end

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

    ---@diagnostic disable-next-line: unreachable-code
    return nil
end

local function EnsureGlowBelowSwipe(icon, glowFrame)
    if not glowFrame or not icon or not icon.Cooldown then return end
    if not (glowFrame.SetFrameLevel and glowFrame.GetFrameLevel) then return end

    local cdLevel = icon.Cooldown:GetFrameLevel()
    local targetLevel = cdLevel - 1
    if targetLevel < 0 then targetLevel = 0 end
    if glowFrame:GetFrameLevel() ~= targetLevel then
        glowFrame:SetFrameLevel(targetLevel)
    end
end
ns._CDM_EnsureGlowBelowSwipe = EnsureGlowBelowSwipe

local function StartTextureGlow(icon, key, texturePath, color)
    local frame = icon[key]
    if not frame then
        local template = icon._quiLayoutRestricted and "DisableUntrustedLayoutScriptsTemplate" or nil
        frame = CreateFrame("Frame", nil, icon, template)
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

local DEFAULT_GLOW_KEY = "_QUICustomGlow"

local function ApplyLibCustomGlow(icon, viewerSettings, glowKey, skipTracking)
    if not LCG or not icon then return false end

    glowKey = glowKey or DEFAULT_GLOW_KEY
    local flashKey  = "_QUIFlash" .. glowKey
    local hammerKey = "_QUIHammer" .. glowKey

    local glowType = viewerSettings.glowType
    local color = viewerSettings.color
    local lines = viewerSettings.lines
    local frequency = viewerSettings.frequency
    local thickness = viewerSettings.thickness
    local scale = viewerSettings.scale or 1
    local xOffset = viewerSettings.xOffset or 0
    local yOffset = viewerSettings.yOffset or 0

    StopGlow(icon, glowKey)

    if glowType == "Pixel Glow" then
        LCG.PixelGlow_Start(icon, color, lines, frequency, nil, thickness, 0, 0, true, glowKey)
        local glowFrame = icon["_PixelGlow" .. glowKey]
        if glowFrame then
            glowFrame:ClearAllPoints()
            glowFrame:SetPoint("TOPLEFT", icon, "TOPLEFT", -xOffset, yOffset)
            glowFrame:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", xOffset, -yOffset)
            EnsureGlowBelowSwipe(icon, glowFrame)
        end

    elseif glowType == "Autocast Shine" then
        LCG.AutoCastGlow_Start(icon, color, lines, frequency, scale, 0, 0, glowKey)
        local glowFrame = icon["_AutoCastGlow" .. glowKey]
        if glowFrame then
            glowFrame:ClearAllPoints()
            glowFrame:SetPoint("TOPLEFT", icon, "TOPLEFT", -xOffset, yOffset)
            glowFrame:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", xOffset, -yOffset)
            EnsureGlowBelowSwipe(icon, glowFrame)
        end

    elseif glowType == "Button Glow" then
        LCG.ButtonGlow_Start(icon, color, frequency)
        buttonGlowOwners[icon] = glowKey
        EnsureGlowBelowSwipe(icon, icon["_ButtonGlow"])

    elseif glowType == "Flash" then
        local frame = StartTextureGlow(icon, flashKey, FLASH_TEXTURE, color)
        EnsureGlowBelowSwipe(icon, frame)

    elseif glowType == "Hammer" then
        local frame = StartTextureGlow(icon, hammerKey, HAMMER_TEXTURE, color)
        EnsureGlowBelowSwipe(icon, frame)

    elseif glowType == "Proc Glow" then
        LCG.ProcGlow_Start(icon, {
            key = glowKey,
            color = color,
            startAnim = true,
            xOffset = xOffset,
            yOffset = viewerSettings.yOffset or 0,
        })
        local glowFrame = icon["_ProcGlow" .. glowKey]
        if glowFrame then
            EnsureGlowBelowSwipe(icon, glowFrame)
        end
    end

    if not skipTracking then
        activeGlowIcons[icon] = true
    end
    return true
end

local function ApplyGlowColorOverride(viewerSettings, spellOvr)
    if not spellOvr or not spellOvr.glowColor then return viewerSettings end
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

    viewerSettings = ApplyGlowColorOverride(viewerSettings, spellOvr)

    ApplyLibCustomGlow(icon, viewerSettings)
end

StopGlow = function(icon, glowKey)
    if not icon then return end
    glowKey = glowKey or DEFAULT_GLOW_KEY
    if LCG then
        LCG.PixelGlow_Stop(icon, glowKey)
        LCG.AutoCastGlow_Stop(icon, glowKey)
        local buttonGlowOwner = buttonGlowOwners[icon]
        if buttonGlowOwner == glowKey
            or (not buttonGlowOwner and glowKey == DEFAULT_GLOW_KEY) then
            LCG.ButtonGlow_Stop(icon)
            buttonGlowOwners[icon] = nil
        end
        LCG.ProcGlow_Stop(icon, glowKey)
    end
    StopTextureGlow(icon, "_QUIFlash" .. glowKey)
    StopTextureGlow(icon, "_QUIHammer" .. glowKey)
    if glowKey == DEFAULT_GLOW_KEY then
        activeGlowIcons[icon] = nil
    end
end

local PANDEMIC_TEXTURE = FLASH_TEXTURE

local function EnsurePandemicGlowFrame(icon)
    if not icon then return nil end
    local frame = icon.PandemicGlow
    if frame then return frame end

    local template = icon._quiLayoutRestricted and "DisableUntrustedLayoutScriptsTemplate" or nil
    frame = CreateFrame("Frame", nil, icon, template)
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
    EnsureGlowBelowSwipe(icon, frame)
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

    if frame.texture
       and durObj.IsZero
       and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
        local isZero = durObj.IsZero(durObj)
        local gate = C_CurveUtil.EvaluateColorValueFromBoolean(isZero, 0, 1)
        frame.texture.SetAlpha(frame.texture, gate)
    end

    frame:SetAlpha(durObj:EvaluateRemainingPercent(curve))
end

ClearPandemicState = function(icon)
    if not icon then return end
    if icon.PandemicGlow then
        icon.PandemicGlow:SetAlpha(0)
    end
end

local _pandemicEntryProbe = {}

local function IsPandemicEnabledForEntry(entry)
    if not entry then return false end
    _pandemicEntryProbe._spellEntry = entry
    local enabled = IsPandemicMirroringEnabled(_pandemicEntryProbe)
    _pandemicEntryProbe._spellEntry = nil
    return enabled
end

local function ApplyPandemicToOverlay(overlay)
    if not overlay then return end
    local tex = overlay._quiPandemicTex
    if not tex and overlay.CreateTexture then
        tex = overlay:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(PANDEMIC_TEXTURE)
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetBlendMode("ADD")
        tex:SetAllPoints(overlay)
        tex:SetVertexColor(1, 0.85, 0.2, 1)
        overlay._quiPandemicTex = tex
    end
    if tex then tex:Show() end
end

local function ClearPandemicFromOverlay(overlay)
    local tex = overlay and overlay._quiPandemicTex
    if tex then tex:Hide() end
end

local GROW_POP_PEAK     = 1.25
local GROW_POP_UP_SEC   = 0.10
local GROW_POP_DOWN_SEC = 0.15

local function EnsureGrowPop(tex)
    if not tex or not tex.CreateAnimationGroup then return nil end
    local ag = tex._quiGrowPop
    if ag then return ag end

    ag = tex:CreateAnimationGroup()

    local up = ag:CreateAnimation("Scale")
    up:SetOrder(1)
    up:SetDuration(GROW_POP_UP_SEC)
    up:SetScaleFrom(1, 1)
    up:SetScaleTo(GROW_POP_PEAK, GROW_POP_PEAK)
    up:SetOrigin("CENTER", 0, 0)
    up:SetSmoothing("OUT")

    local down = ag:CreateAnimation("Scale")
    down:SetOrder(2)
    down:SetDuration(GROW_POP_DOWN_SEC)
    down:SetScaleFrom(GROW_POP_PEAK, GROW_POP_PEAK)
    down:SetScaleTo(1, 1)
    down:SetOrigin("CENTER", 0, 0)
    down:SetSmoothing("IN")

    tex._quiGrowPop = ag
    return ag
end

local function PlayGrowPop(icon)
    if not icon then return end
    local tex = icon.Icon
    if not tex then return end

    local db = Shared and Shared.GetContainerDB and Shared.GetContainerDB("buff")
    if not db or not db.growOnApply then return end

    local ag = EnsureGrowPop(tex)
    if not ag then return end
    if ag:IsPlaying() then ag:Stop() end
    ag:Play()
end

local function StopGrowPop(icon)
    local tex = icon and icon.Icon
    local ag = tex and tex._quiGrowPop
    if ag then
        if ag:IsPlaying() then ag:Stop() end
        tex:SetScale(1)
    end
end

local function IsOverlayQueryActive(spellID)
    if _issecretvalue(spellID) then return false end -- @secret-policy: reject-secret-ids
    if not spellID or not IsSpellOverlayed then return false end
    return IsSpellOverlayed(spellID) and true or false
end

IsOverlayed = function(spellID)
    if _issecretvalue(spellID) then return false end -- @secret-policy: reject-secret-ids
    if not spellID then return false end
    if overlayedSpells[spellID] then return true end
    if IsSpellOverlayed then
        return IsOverlayQueryActive(spellID)
    end
    return false
end

local function EvaluateGlowForIcon(icon)
    if not icon or not icon:IsShown() or not icon._spellEntry then
        return false, nil
    end

    do
        local profile = ns.Helpers and ns.Helpers.GetProfile and ns.Helpers.GetProfile()
        local source = profile and profile.ncdm and profile.ncdm.glowSource or "QUI"
        if source == "Off" then
            StopGlow(icon)
            return false, nil
        elseif source == "Skin" then
            local b = ns.ExternalSkinBridge
            if b and b.IsAvailable() and b.SkinProvidesGlow() then
                StopGlow(icon)
                return false, nil
            end
        end
    end

    local entry = icon._spellEntry
    local viewerType = entry.viewerType

    local spellOvr = GetSpellGlowOverride(icon)
    local overlayGlow, overlayOvr, overlaySpellID = FindAllowedOverlayGlow(icon, viewerType)

    local shouldGlow
    if overlayGlow then
        shouldGlow = true
    elseif spellOvr and spellOvr.glowEnabled == false then
        shouldGlow = false
    elseif spellOvr and spellOvr.glowEnabled == true then
        shouldGlow = true
    end

    if not shouldGlow and spellOvr and spellOvr.procOnUsable == true then
        shouldGlow = IsSpellCastable(icon)
    end

    local entryID = entry.spellID or entry.id
    if overlayGlow then
        overlayGlowSpell[icon] = overlaySpellID
        overlayGlowBase[icon] = entryID
    elseif not shouldGlow then
        local latched = overlayGlowSpell[icon]
        if latched and overlayGlowBase[icon] == entryID and IsOverlayed(latched) then
            shouldGlow = true
        else
            overlayGlowSpell[icon] = nil
            overlayGlowBase[icon] = nil
        end
    end

    return shouldGlow and true or false, overlayOvr or spellOvr
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

local function _SyncGlowIfVisible(icon)
    if not icon:IsShown() then return end
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

local _scanGlowVisited = {}

local function _ProcessGlowIconsForCandidate(spellID, visited)
    if _issecretvalue(spellID) then return false end -- @secret-policy: reject-secret-ids
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
    local baseID = Sources and Sources.QueryBaseSpell
        and Sources.QueryBaseSpell(spellID)
    if baseID and baseID ~= spellID then
        if _ProcessGlowIconsForCandidate(baseID, visited) then
            matched = true
        end
        local baseOverrideID = Sources and Sources.QueryOverrideSpell
            and Sources.QueryOverrideSpell(baseID)
        if baseOverrideID and baseOverrideID ~= baseID then
            if _ProcessGlowIconsForCandidate(baseOverrideID, visited) then
                matched = true
            end
        end
    end

    if not matched then
        ScanAllGlows()
    end

    wipe(visited)
end

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
    wipe(overlayGlowSpell)
    wipe(overlayGlowBase)
end

local function RefreshAllGlows()
    StopAllTrackedGlows()

    if not IsCDMRuntimeEnabled() then
        return
    end

    RebuildGlowSpellMap()
    ScanAllGlows()
end

local function ResyncAllGlows()
    if not IsCDMRuntimeEnabled() then
        StopAllTrackedGlows()
        return
    end
    RebuildGlowSpellMap()
    ScanAllGlows()
end

local function InvalidateOverrideCacheForProc()
    local rq = ns.CDMRuntimeQueries
    if rq and rq.ClearStableCaches then
        rq.ClearStableCaches()
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_SHOW")
eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_HIDE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
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
        InvalidateOverrideCacheForProc()
        MarkOverlaySource(spellID)
        ScanGlowsForSpell(spellID)
        return
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE"
        or event == "SPELL_ACTIVATION_OVERLAY_HIDE" then
        InvalidateOverrideCacheForProc()
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
if ns.DebugRegister then
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation()
end

local function DisableRuntime()
    eventFrame:UnregisterAllEvents()
    eventFrame:SetScript("OnEvent", nil)
    StopAllTrackedGlows()
end

local _pandemicVisited = {}

local function HandleUnitAuraChanged(_unit, _updateInfo)
    if not IsCDMRuntimeEnabled() then return end

    wipe(_pandemicVisited)
    for _, icons in pairs(spellIdToGlowIcons) do
        for i = 1, #icons do
            local icon = icons[i]
            if icon and not _pandemicVisited[icon] then
                _pandemicVisited[icon] = true
                if icon:IsShown() and icon._spellEntry then
                    UpdatePandemicGlow(icon)
                end
            end
        end
    end
end

local function ResolveGlowForEntry(entry)
    if not entry then return nil end
    local fakeIcon = { _spellEntry = entry }
    local viewerType = GetViewerType(fakeIcon)
    if not viewerType then return nil end
    local viewerSettings = GetViewerSettings(viewerType)
    if not viewerSettings then return nil end
    local spellOvr = GetSpellGlowOverride(fakeIcon)
    if spellOvr and spellOvr.glowEnabled == false then return nil end
    return ApplyGlowColorOverride(viewerSettings, spellOvr)
end

ns._OwnedGlows = {
    StartGlow = StartGlow,
    StopGlow = StopGlow,
    ResolveGlowForEntry = ResolveGlowForEntry,
    RefreshAllGlows = RefreshAllGlows,
    ResyncAllGlows = ResyncAllGlows,
    RebuildGlowSpellMap = RebuildGlowSpellMap,
    GetViewerType = GetViewerType,
    GetViewerSettings = GetViewerSettings,
    ApplyGlowWithKey = function(icon, viewerSettings, glowKey)
        return ApplyLibCustomGlow(icon, viewerSettings, glowKey, true)
    end,
    StopGlowWithKey = function(icon, glowKey)
        return StopGlow(icon, glowKey)
    end,
    activeGlowIcons = activeGlowIcons,
    ScheduleGlowScan = ScanAllGlows,
    IsSpellCastable = IsSpellCastable,
    UpdatePandemicGlow = UpdatePandemicGlow,
    ClearPandemicState = ClearPandemicState,
    IsPandemicEnabledForEntry = IsPandemicEnabledForEntry,
    ApplyPandemicToOverlay = ApplyPandemicToOverlay,
    ClearPandemicFromOverlay = ClearPandemicFromOverlay,
    PlayGrowPop = PlayGrowPop,
    StopGrowPop = StopGrowPop,
    HandleUnitAuraChanged = HandleUnitAuraChanged,
    DisableRuntime = DisableRuntime,
    GetGlowState = function(icon)
        return activeGlowIcons[icon] and { active = true } or nil
    end,
}

local _, ns = ...
local Helpers = ns.Helpers
local Sources = ns.CDMSources
local Shared = ns.CDMShared

local function IsCDMRuntimeEnabled()
    return not Shared or Shared.IsRuntimeEnabled()
end

local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

local FLASH_TEXTURE = (Helpers and Helpers.AssetPath or [[Interface\AddOns\QUI\assets\]]) .. [[iconskin\Flash]]
local HAMMER_TEXTURE = (Helpers and Helpers.AssetPath or [[Interface\AddOns\QUI\assets\]]) .. [[quazii_hammer]]

local GetSettings = Helpers.CreateDBGetter("cooldownHighlighter")

local activeHighlights = {}
local GLOW_KEY = "_QUIHighlighter"

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

local function StopAllGlows(icon)
    if not icon or not LCG then return end
    LCG.PixelGlow_Stop(icon, GLOW_KEY)
    LCG.AutoCastGlow_Stop(icon, GLOW_KEY)
    if icon[GLOW_KEY] then
        icon[GLOW_KEY] = nil
        LCG.ButtonGlow_Stop(icon)
        if activeGlowIcons[icon] then
            activeGlowIcons[icon] = nil
            SyncGlowForIcon(icon)
        end
    end
    LCG.ProcGlow_Stop(icon, GLOW_KEY)
    StopTextureGlow(icon, "_QUIFlashHL")
    StopTextureGlow(icon, "_QUIHammerHL")
end

local function RemoveHighlight(icon)
    if not icon then return end
    StopAllGlows(icon)
    activeHighlights[icon] = nil
end

local EnsureGlowBelowSwipe = ns._CDM_EnsureGlowBelowSwipe

local function ApplyHighlight(icon)
    if not icon or not LCG then return end

    local settings = GetSettings()
    if not settings or not settings.enabled then return end

    do
        local profile = ns.Helpers and ns.Helpers.GetProfile and ns.Helpers.GetProfile()
        local source = profile and profile.ncdm and profile.ncdm.glowSource or "QUI"
        if source == "Off" then
            return
        elseif source == "Skin" then
            local b = ns.ExternalSkinBridge
            if b and b.IsAvailable() and b.SkinProvidesGlow() then
                return
            end
        end
    end

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
        EnsureGlowBelowSwipe(icon, icon["_PixelGlow" .. GLOW_KEY])
    elseif glowType == "Autocast Shine" then
        LCG.AutoCastGlow_Start(icon, color, lines, frequency, scale, 0, 0, GLOW_KEY)
        EnsureGlowBelowSwipe(icon, icon["_AutoCastGlow" .. GLOW_KEY])
    elseif glowType == "Button Glow" then
        if not icon["_ButtonGlow"] then
            LCG.ButtonGlow_Start(icon, color, frequency)
            icon[GLOW_KEY] = true
            EnsureGlowBelowSwipe(icon, icon["_ButtonGlow"])
        end

    elseif glowType == "Flash" then
        EnsureGlowBelowSwipe(icon, StartTextureGlow(icon, "_QUIFlashHL", FLASH_TEXTURE, color))

    elseif glowType == "Hammer" then
        EnsureGlowBelowSwipe(icon, StartTextureGlow(icon, "_QUIHammerHL", HAMMER_TEXTURE, color))

    elseif glowType == "Proc Glow" then
        LCG.ProcGlow_Start(icon, {
            key = GLOW_KEY,
            color = color,
            startAnim = true,
        })
        EnsureGlowBelowSwipe(icon, icon["_ProcGlow" .. GLOW_KEY])
    end

    activeHighlights[icon] = C_Timer.NewTimer(duration, function()
        RemoveHighlight(icon)
    end)
end

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

_G.QUI_RefreshCooldownHighlighter = function()
    if not IsCDMRuntimeEnabled() then
        ClearHighlights()
        return
    end

    local settings = GetSettings()
    if not settings or not settings.enabled then
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

local _, ns = ...
local Helpers = ns.Helpers
local Shared = ns.CDMShared
local _issecretvalue = issecretvalue or function() return false end

local DEFAULTS = {
    showBuffSwipe = true,
    showCooldownIconAuraPhase = true,
    showBuffIconSwipe = true,
    showGCDSwipe = true,
    showCooldownSwipe = true,
    overlayColorMode = "default",
    overlayColor = {1, 1, 1, 1},
    swipeColorMode = "default",
    swipeColor = {1, 1, 1, 1},
}

local function GetSettings()
    return Helpers.GetModuleSettings("cooldownSwipe", DEFAULTS)
end

local EFFECTS_DEFAULTS = {
    hideEssential = false,
    hideUtility = false,
}

local function GetEffectsSettings()
    return Helpers.GetModuleSettings("cooldownEffects", EFFECTS_DEFAULTS)
end

local function ContainerHideKey(viewerType)
    if viewerType == "essential" then return "hideEssential" end
    if viewerType == "utility" then return "hideUtility" end
    if viewerType == nil then return nil end
    return "hide_" .. viewerType
end

local function IsContainerEffectsHidden(viewerType)
    local key = ContainerHideKey(viewerType)
    if not key then return false end
    local effects = GetEffectsSettings()
    return (effects and effects[key] == true) or false
end

local function GetClassColor()
    local _, class = UnitClass("player")
    local classColor
    if C_ClassColor and C_ClassColor.GetClassColor and type(class) ~= "nil" then
        classColor = C_ClassColor.GetClassColor(class)
    elseif not _issecretvalue(class) and type(class) == "string" then
        classColor = Helpers.GetClassColorTable(class)
    end
    if type(classColor) ~= "nil" then
        if type(classColor.GetRGBA) == "function" then
            local r, g, b = classColor:GetRGBA()
            return r, g, b, 0.8
        end
        return classColor.r, classColor.g, classColor.b, 0.8
    end
    return 1, 1, 1, 0.8
end

local function ResolveColor(mode, colorTable)
    if mode == "class" then
        return GetClassColor()
    elseif mode == "accent" then
        local QUI = _G.QUI
        if QUI and QUI.GetSkinColor then
            local r, g, b = QUI:GetSkinColor()
            return r, g, b, 0.8
        end
        return 0.376, 0.647, 0.980, 0.8
    elseif mode == "custom" then
        local c = colorTable or {}
        return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
    end
    return nil
end

local CDM_DEFAULT_R, CDM_DEFAULT_G, CDM_DEFAULT_B, CDM_DEFAULT_A = 0, 0, 0, 0.8
local BLIZZ_BUFF_R, BLIZZ_BUFF_G, BLIZZ_BUFF_B, BLIZZ_BUFF_A = 0.93, 0.77, 0.0, 0.45
local FULL_FRAME_SWIPE_TEXTURE = "Interface\\Buttons\\WHITE8X8"

local function SettingEnabled(value, fallback)
    if Shared and Shared.SettingEnabled then
        return Shared.SettingEnabled(value, fallback)
    end
    return value == nil and fallback == true or value == true
end

function ns._CDM_ResolvePreviewSwipe(settings, mode)
    settings = settings or {}
    local showSwipe
    if mode == "aura" then
        showSwipe = SettingEnabled(settings.showBuffSwipe, true)
    else
        showSwipe = SettingEnabled(settings.showCooldownSwipe, true)
    end
    if not showSwipe then
        return false, 0, 0, 0, 0
    end

    local r, g, b, a
    if mode == "aura" then
        r, g, b, a = ResolveColor(settings.overlayColorMode or "default", settings.overlayColor)
        if not r then r, g, b, a = BLIZZ_BUFF_R, BLIZZ_BUFF_G, BLIZZ_BUFF_B, BLIZZ_BUFF_A end
    else
        r, g, b, a = ResolveColor(settings.swipeColorMode or "default", settings.swipeColor)
        if not r then r, g, b, a = CDM_DEFAULT_R, CDM_DEFAULT_G, CDM_DEFAULT_B, CDM_DEFAULT_A end
    end
    return true, r, g, b, a or 1
end

function ns._CDM_ResolveModeColor(settings, mode)
    settings = settings or {}
    local r, g, b, a
    if mode == "aura" then
        r, g, b, a = ResolveColor(settings.overlayColorMode or "default", settings.overlayColor)
        if not r then r, g, b, a = BLIZZ_BUFF_R, BLIZZ_BUFF_G, BLIZZ_BUFF_B, BLIZZ_BUFF_A end
    else
        r, g, b, a = ResolveColor(settings.swipeColorMode or "default", settings.swipeColor)
        if not r then r, g, b, a = CDM_DEFAULT_R, CDM_DEFAULT_G, CDM_DEFAULT_B, CDM_DEFAULT_A end
    end
    return r, g, b, a or 1
end

local function ApplySwipeToIcon(icon, settings)
    if not icon or not icon.Cooldown or not icon._spellEntry then return end
    settings = settings or GetSettings()

    local entry = icon._spellEntry
    local isBuffIcon = (entry.viewerType == "buff")
    local isAuraEntry
    local CDMSpellData = ns.CDMSpellData
    if CDMSpellData and CDMSpellData.IsAuraEntry then
        isAuraEntry = CDMSpellData.IsAuraEntry(entry, entry.viewerType)
    else
        isAuraEntry = (entry.kind == "aura")
            or IsBuiltinAuraContainerKey(entry.viewerType)
    end

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

    local showEdge = showSwipe and ((mode == "aura" and SettingEnabled(settings.showBuffEdge, true))
        or (mode == "cooldown" and settings.showRechargeEdge))

    if IsContainerEffectsHidden(entry.viewerType) then
        showSwipe = false
        showEdge = false
    end

    local function applyToCooldown(cd)
        if not cd then return end
        cd._quiIntendedDrawSwipe = showSwipe and true or false
        cd._quiIntendedDrawEdge  = showEdge and true or false
        cd._quiIntendedSwipeTexture = FULL_FRAME_SWIPE_TEXTURE
        cd.SetSwipeTexture(cd, FULL_FRAME_SWIPE_TEXTURE)
        cd.SetDrawSwipe(cd, showSwipe and true or false)
        cd.SetDrawEdge(cd, showEdge and true or false)

        -- SetCooldownFromDurationObject + SetReverse (aura path) can
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

local function ApplySwipeToBuffChild(icon, settings)
    if not icon or not icon.Cooldown then return end
    settings = settings or GetSettings()

    local showSwipe = SettingEnabled(settings.showBuffIconSwipe, true)
    local showEdge = showSwipe and SettingEnabled(settings.showBuffEdge, true)

    icon.Cooldown:SetDrawSwipe(showSwipe)
    icon.Cooldown:SetDrawEdge(showEdge)

    if not showSwipe then
        icon.Cooldown:SetSwipeColor(0, 0, 0, 0)
    else
        local oR, oG, oB, oA = ResolveColor(settings.overlayColorMode or "default", settings.overlayColor)
        if not oR then oR, oG, oB, oA = BLIZZ_BUFF_R, BLIZZ_BUFF_G, BLIZZ_BUFF_B, BLIZZ_BUFF_A end

        icon.Cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
        icon.Cooldown:SetSwipeColor(oR, oG, oB, oA)
    end
end

local function RefreshAllSwipes()
    local CDMIcons = ns.CDMIcons
    if not CDMIcons then return end

    local settings = GetSettings()

    if CDMIcons.UpdateAllCooldowns then
        CDMIcons:UpdateAllCooldowns()
    end

    local IconFactory = ns.CDMIconFactory
    if not IconFactory then return end
    for _, viewerType in ipairs(GetBuiltinIconContainerKeys()) do
        local pool = IconFactory:GetIconPool(viewerType)
        for _, icon in ipairs(pool) do
            ApplySwipeToIcon(icon, settings)
        end
    end

    local ncdm = Shared and Shared.GetNcdmDB and Shared.GetNcdmDB()
    local customList = ncdm and ncdm.containers
    if customList then
        for containerKey, cfg in pairs(customList) do
            if cfg and not cfg.builtIn then
                local pool = IconFactory:GetIconPool(containerKey)
                for _, icon in ipairs(pool) do
                    ApplySwipeToIcon(icon, settings)
                end
            end
        end
    end
end

ns._OwnedSwipe = {
    Apply = RefreshAllSwipes,
    ApplyToIcon = ApplySwipeToIcon,
    ApplyToBuffChild = ApplySwipeToBuffChild,
    GetSettings = GetSettings,
    IsContainerEffectsHidden = IsContainerEffectsHidden,
    _TestContainerHideKey = ContainerHideKey,
}
