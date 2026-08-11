local ADDON_NAME, ns = ...
local NP = ns.QUI_Nameplates
if not NP then return end

local Helpers = ns.Helpers
local NPHealth = NP.Health
local NPColors = NP.Colors
local NPCVars = NP.CVars
local NPExtras = NP.Extras

local type = type
local pcall = pcall
local CreateFrame = CreateFrame
local UnitExists = UnitExists
local UnitIsUnit = UnitIsUnit
local hooksecurefunc = hooksecurefunc

local NPDriver = {}
NP.Driver = NPDriver

local plates = NP.plates

local hiddenParent = CreateFrame("Frame", nil, UIParent)
hiddenParent:Hide()

local suppression = setmetatable({}, { __mode = "k" })
local alphaLock = setmetatable({}, { __mode = "k" })

local SUPPRESS_CHILD_KEYS = {
    "HealthBarsContainer",
    "castBar",
    "CastBarsContainer",
    "RaidTargetFrame",
    "ClassificationFrame",
    "AurasFrame",
    "PlayerLevelDiffFrame",
    "SoftTargetFrame",
}

local CASTBAR_UNIT_EVENTS = {
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_EMPOWER_STOP",
    "UNIT_SPELLCAST_INTERRUPTIBLE",
    "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED",
}

local function PinAlphaZero(unitFrame)
    if alphaLock[unitFrame] then return end
    local record = suppression[unitFrame]
    if not (record and record.active) then return end
    alphaLock[unitFrame] = true
    pcall(unitFrame.SetAlpha, unitFrame, 0)
    alphaLock[unitFrame] = nil
end

local function SuppressBlizzardArt(base)
    local unitFrame = base and base.UnitFrame
    if not unitFrame then return end

    local record = suppression[unitFrame]
    if not record then
        record = { children = {} }
        suppression[unitFrame] = record
    end
    if record.active then return end
    record.active = true

    for i = 1, #SUPPRESS_CHILD_KEYS do
        local child = unitFrame[SUPPRESS_CHILD_KEYS[i]]
        if child and child.SetParent then
            local okParent, parent = pcall(child.GetParent, child)
            if okParent and parent and parent ~= hiddenParent then
                record.children[child] = parent
                pcall(child.SetParent, child, hiddenParent)
            end
        end
    end

    local castBar = unitFrame.castBar
        or (unitFrame.CastBarsContainer and unitFrame.CastBarsContainer.castBar)
    if castBar and castBar.UnregisterAllEvents then
        pcall(castBar.UnregisterAllEvents, castBar)
    end

    if not record.alphaHooked then
        record.alphaHooked = true
        hooksecurefunc(unitFrame, "SetAlpha", PinAlphaZero)
    end
    pcall(unitFrame.SetAlpha, unitFrame, 0)
end

local function RestoreBlizzardArt(base)
    local unitFrame = base and base.UnitFrame
    if not unitFrame then return end
    local record = suppression[unitFrame]
    if not (record and record.active) then return end
    record.active = false

    for child, originalParent in pairs(record.children) do
        pcall(child.SetParent, child, originalParent)
        record.children[child] = nil
    end

    local castBar = unitFrame.castBar
        or (unitFrame.CastBarsContainer and unitFrame.CastBarsContainer.castBar)
    if castBar and castBar.RegisterUnitEvent and castBar.unit then
        local unit = castBar.unit
        for i = 1, #CASTBAR_UNIT_EVENTS do
            castBar:RegisterUnitEvent(CASTBAR_UNIT_EVENTS[i], unit)
        end
        castBar:RegisterEvent("PLAYER_ENTERING_WORLD")
    end
    pcall(unitFrame.SetAlpha, unitFrame, 1)
end
NPDriver.RestoreBlizzardArt = RestoreBlizzardArt

function NPDriver.StampRenderMode(plate)
    local mode = NP.ResolveRenderMode(NP.GetTypeSettings(plate))
    if plate.npType == "friendly" or plate.npReaction == "friendly" then
        local settings = NP.GetSettings()
        local friendly = type(settings) == "table" and settings.friendly or nil
        if NP.Friendly.EffectiveMode() == "off" then
            mode = "off"
        elseif NP.Friendly.InstanceForcesNameOnly(friendly, NPExtras.GetContext()) then
            mode = "nameonly"
        end
    end
    plate.npRenderMode = mode
    return mode
end

local function ComputeUnitState(plate)
    local unit = plate.unit
    if not unit then return end
    local ok, v

    ok, v = pcall(UnitIsPlayer, unit)
    plate.npIsPlayer = (ok and NP.Plain(v, "boolean")) or false

    ok, v = pcall(UnitReaction, unit, "player")
    local reaction = ok and NP.Plain(v, "number") or nil
    if reaction then
        if reaction >= 5 then
            plate.npReaction = "friendly"
        elseif reaction == 4 then
            plate.npReaction = "neutral"
        else
            plate.npReaction = "hostile"
        end
    else
        plate.npReaction = "hostile"
    end

    local okClass, _, classToken = pcall(UnitClass, unit)
    plate.npClassToken = okClass and NP.Plain(classToken, "string") or nil

    ok, v = pcall(UnitIsTapDenied, unit)
    plate.npTapDenied = (ok and NP.Plain(v, "boolean")) or false

    plate.npType = NP.PlateType.Resolve(unit)

    ok, v = pcall(UnitAffectingCombat, unit)
    if ok then
        plate.npInCombat = NP.Plain(v, "boolean")
    else
        plate.npInCombat = nil
    end
end
NPDriver.ComputeUnitState = ComputeUnitState

function NPDriver.ApplySimplified(plate)
    if not NP.SIMPLIFIED_AVAILABLE then return end
    if not plate or not plate.unit then return end
    local flag = NP.ResolveRenderMode(NP.GetTypeSettings(plate)) == "simplified"
    pcall(C_NamePlateManager.SetNamePlateSimplified, plate.unit, flag)
end

function NPDriver.RefreshPlateType(plate)
    if not plate or not plate.unit then return false end
    local resolved = NP.PlateType.Resolve(plate.unit)
    if resolved == plate.npType then return false end
    plate.npType = resolved
    NPDriver.ApplySimplified(plate)
    return true
end

local function ComputeDeferredState(plate)
    local unit = plate.unit
    if not unit then return end

    plate.npIsQuest = NPExtras.IsQuestUnit(unit) == true

    local ok, v = pcall(UnitIsUnit, unit, "target")
    plate.npIsTarget = (ok and NP.Plain(v, "boolean")) or false
    ok, v = pcall(UnitIsUnit, unit, "focus")
    plate.npIsFocus = (ok and NP.Plain(v, "boolean")) or false
end

local PLATE_UNIT_EVENTS = {
    "UNIT_HEALTH",
    "UNIT_MAXHEALTH",
    "UNIT_ABSORB_AMOUNT_CHANGED",
    "UNIT_HEAL_PREDICTION",
    "UNIT_CLASSIFICATION_CHANGED",
    "UNIT_POWER_UPDATE",
    "UNIT_MAXPOWER",
    "UNIT_NAME_UPDATE",
    "UNIT_THREAT_LIST_UPDATE",
    "UNIT_FLAGS",
}

local ClearUnit, ReleasePlate, ApplyPlateAppearance

local function SyncPlateAppearanceType(plate)
    if plate.npAppearanceType == plate.npType then return false end
    ApplyPlateAppearance(plate, NP.GetSettings())
    return true
end
NPDriver.SyncPlateAppearanceType = SyncPlateAppearanceType

local function RebindPlate(plate, newUnit)
    local oldUnit = plate.unit
    if oldUnit and plates[oldUnit] == plate then
        plates[oldUnit] = nil
    end
    plate.unit = newUnit
    plates[newUnit] = plate
    for i = 1, #PLATE_UNIT_EVENTS do
        plate:RegisterUnitEvent(PLATE_UNIT_EVENTS[i], newUnit)
    end
    NP.Castbar.StopCast(plate)
    ComputeUnitState(plate)
    SyncPlateAppearanceType(plate)
    NPDriver.ApplySimplified(plate)
    ComputeDeferredState(plate)
    NPExtras.UpdateThreat(plate)
    NPHealth.UpdateHealth(plate)
    NPHealth.UpdateAbsorbs(plate)
    NPHealth.UpdateHealPrediction(plate)
    NPHealth.UpdateName(plate)
    NPHealth.UpdateLevel(plate)
    NPHealth.UpdateNpcTitle(plate)
    NPHealth.UpdateColor(plate, NP.GetTypeSettings(plate), NPExtras.GetContext())
    NP.Auras.ApplyAppearance(plate)
end

local function PlateOnEvent(plate, event, unit)
    if event == "UNIT_HEALTH" then
        local base = plate.npBase
        local token = NP.Plain(base and (base.unitToken or base.namePlateUnitToken), "string")
        if token and token ~= plate.unit then
            RebindPlate(plate, token)
            return
        end
        NPHealth.UpdateHealth(plate)
        if NPExtras.UpdateExecute then
            NPExtras.UpdateExecute(plate)
        end
        return
    end
    if event == "UNIT_MAXHEALTH" then
        NPHealth.UpdateHealth(plate)
        NPHealth.UpdateAbsorbs(plate)
        NPHealth.UpdateHealPrediction(plate)
        return
    end
    if event == "UNIT_ABSORB_AMOUNT_CHANGED" then
        NPHealth.UpdateAbsorbs(plate)
        return
    end
    if event == "UNIT_HEAL_PREDICTION" then
        NPHealth.UpdateHealPrediction(plate)
        return
    end
    if event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then
        NPHealth.UpdatePower(plate)
        return
    end
    if event == "UNIT_CLASSIFICATION_CHANGED" then
        NPExtras.UpdatePvpIcon(plate)
        NPHealth.UpdateLevel(plate)
        if NPDriver.RefreshPlateType(plate) then
            NP.RestyleActivePlates()
        end
        return
    end
    if event == "UNIT_NAME_UPDATE" then
        ComputeUnitState(plate)
        SyncPlateAppearanceType(plate)
        NPDriver.ApplySimplified(plate)
        NPHealth.UpdateName(plate)
        NPHealth.UpdateLevel(plate)
        NPHealth.UpdateNpcTitle(plate)
        NPHealth.UpdateColor(plate, NP.GetTypeSettings(plate), NPExtras.GetContext())
        return
    end
    if event == "UNIT_THREAT_LIST_UPDATE" then
        NPExtras.UpdateThreat(plate)
        local ok, v = pcall(UnitAffectingCombat, unit)
        plate.npInCombat = ok and NP.Plain(v, "boolean") or nil
        NPHealth.UpdateColor(plate, NP.GetTypeSettings(plate), NPExtras.GetContext())
        return
    end
    if event == "UNIT_FLAGS" then
        if NPDriver.RefreshPlateType(plate) then
            NP.RestyleActivePlates()
        end
        return
    end
end

local pool = {}
local poolSize = 0

local function PinPlateScale(plate)
    if not plate.SetIgnoreParentScale then return end
    local ok, es = pcall(UIParent.GetEffectiveScale, UIParent)
    es = ok and NP.Plain(es, "number") or nil
    if es and es > 0 then
        local settings = NP.GetSettings()
        local layout = settings.layout or {}
        local mult = (plate.npIsTarget == true) and (layout.targetScale or 1.0) or 1.0
        if plate.npRenderMode == "simplified" then
            mult = mult * NP.SimplifiedScale(settings)
        end
        plate:SetScale(es * mult)
    end
end
NPDriver.PinPlateScale = PinPlateScale

local function BuildPlate()
    local plate = CreateFrame("Frame", nil, hiddenParent)
    plate:Hide()
    plate:SetSize(1, 1)
    if plate.SetIgnoreParentScale then
        plate:SetIgnoreParentScale(true)
    end
    PinPlateScale(plate)
    plate:SetScript("OnEvent", PlateOnEvent)

    NPHealth.Build(plate)
    NP.Castbar.Build(plate)
    if NPExtras.BuildPlate then
        NPExtras.BuildPlate(plate)
    end

    local stackBounds = CreateFrame("Frame", nil, plate)
    local boundsTex = stackBounds:CreateTexture(nil, "BACKGROUND")
    boundsTex:SetAllPoints(stackBounds)
    boundsTex:SetColorTexture(1, 1, 1, 1)
    boundsTex:SetAlpha(0)
    plate.npStackBounds = stackBounds

    return plate
end

local function AcquirePlate()
    local plate
    if poolSize > 0 then
        plate = pool[poolSize]
        pool[poolSize] = nil
        poolSize = poolSize - 1
    else
        plate = BuildPlate()
    end
    return plate
end

function ClearUnit(plate)
    local unit = plate.unit
    plate:UnregisterAllEvents()
    NP.Castbar.StopCast(plate)
    NP.Auras.Clear(plate)
    if NPExtras.ClearPlate then
        NPExtras.ClearPlate(plate)
    end

    local base = plate.npBase
    if base and base.SetStackingBoundsFrame then
        pcall(base.SetStackingBoundsFrame, base, nil)
    end

    if unit and plates[unit] == plate then
        plates[unit] = nil
    end
    if base then
        NP.platesByBase[base] = nil
    end

    plate.unit = nil
    plate.npBase = nil
    plate.npDeferredPending = nil
    plate.npLastMaxHP = nil
    plate.npLastAbsorbMax = nil
    plate.npAbsorbHidden = nil
    if plate.healPredictBar then plate.healPredictBar:Hide() end
    if plate.powerBar then plate.powerBar:Hide() end
    plate.npLastR, plate.npLastG, plate.npLastB = nil, nil, nil
    plate.npReaction = nil
    plate.npType = nil
    plate.npRenderMode = nil
    plate.npIsPlayer = nil
    plate.npClassToken = nil
    plate.npTapDenied = nil
    plate.npInCombat = nil
    plate.npIsQuest = nil
    plate.npThreat = nil
    plate.npIsTarget = nil
    plate.npIsFocus = nil
    plate.npCastKind = nil
    plate.npCastImportant = nil
    plate.npPlainNotInterruptible = nil

    if NP.Power and NP.Power.Detach then NP.Power.Detach(plate) end
    plate:SetAlpha(1)
    plate:Hide()
    plate:ClearAllPoints()
    plate:SetParent(hiddenParent)
end
NPDriver.ClearUnit = ClearUnit

function ReleasePlate(plate)
    ClearUnit(plate)
    poolSize = poolSize + 1
    pool[poolSize] = plate
end

local deferredPlates = {}
local deferFrame = CreateFrame("Frame")
deferFrame:Hide()
deferFrame:SetScript("OnUpdate", function(self)
    self:Hide()
    for plate in pairs(deferredPlates) do
        deferredPlates[plate] = nil
        if plate.npDeferredPending and plate.unit then
            plate.npDeferredPending = nil
            ComputeDeferredState(plate)
            NPExtras.UpdateThreat(plate)
            NPHealth.UpdateName(plate)
            NPHealth.UpdateLevel(plate)
            NPHealth.UpdateNpcTitle(plate)
            NPHealth.UpdateAbsorbs(plate)
            NPHealth.UpdateHealPrediction(plate)
            NPHealth.UpdatePower(plate)
            NPHealth.UpdateColor(plate, NP.GetTypeSettings(plate), NPExtras.GetContext())
            NP.Auras.ApplyAppearance(plate)
            if NPExtras.OnPlateShown then
                NPExtras.OnPlateShown(plate)
            end
            if NP.Castbar.ProbeCast then
                NP.Castbar.ProbeCast(plate)
            end
        end
    end
end)

local LIGHTWEIGHT_HIDDEN_REGIONS = {
    "powerBar", "castBar", "healthText", "npTitleText",
    "absorbBar", "healPredictBar",
    "npAbsorbText", "npLevelText", "npClassIcon", "npRaidMarker",
    "npTargetGlow", "npTargetArrowL", "npTargetArrowR", "npTargetBrackets",
    "npTargetGlowline", "npFocusGlow", "npPvpIcon", "npQuestIcon",
}

local LIGHTWEIGHT_DISABLED_FLAGS = {
    "npAbsorbsEnabled", "npHealPredictEnabled", "npPowerBarEnabled",
    "npAbsorbTextEnabled", "npTitleEnabled", "npLevelEnabled",
    "npClassIconEnabled", "npCastEnabled", "npQuestIconEnabled",
    "npPvpIconEnabled", "npTargetGlowEnabled", "npFocusGlowEnabled",
    "npHoverEnabled", "npRaidMarkerEnabled",
}

local function ApplyRenderMode(plate, mode)
    if NP.IsLightweightMode(mode) then
        for i = 1, #LIGHTWEIGHT_DISABLED_FLAGS do
            plate[LIGHTWEIGHT_DISABLED_FLAGS[i]] = false
        end
        plate.npHealthTextStyle = "none"
        plate.npAbsorbHidden = true
        for i = 1, #LIGHTWEIGHT_HIDDEN_REGIONS do
            local region = plate[LIGHTWEIGHT_HIDDEN_REGIONS[i]]
            if region then region:Hide() end
        end
    end

    if mode == "nameonly" then
        plate.healthBar:Hide()

        local QUICore = ns.Addon
        local nameS = (NP.GetTypeSettings(plate) or {}).name or {}
        plate.nameText:ClearAllPoints()
        plate.nameText:SetPoint("CENTER", plate, "CENTER",
            QUICore:Pixels(nameS.offsetX or 0),
            QUICore:Pixels(nameS.offsetY or 0))
        plate.nameText:SetJustifyH(nameS.justify or "CENTER")
        if nameS.enabled == false then plate.nameText:Hide() else plate.nameText:Show() end
    else
        plate.healthBar:Show()
    end

    if mode == "off" then
        plate:Hide()
    else
        plate:Show()
    end
    return mode
end
NPDriver.ApplyRenderMode = ApplyRenderMode

local function ReapplyDynamicVisuals(plate)
    if not plate.unit then return end
    NPHealth.UpdateAbsorbs(plate)
    NPHealth.UpdateHealPrediction(plate)
    NPHealth.UpdatePower(plate)
    NPHealth.UpdateLevel(plate)
    NPHealth.UpdateNpcTitle(plate)
    if NPExtras.OnPlateShown then
        NPExtras.OnPlateShown(plate)
    end
end

local function ApplyResolvedRenderMode(plate)
    return ApplyRenderMode(plate, NPDriver.StampRenderMode(plate))
end
NPDriver.ApplyResolvedRenderMode = ApplyResolvedRenderMode

function ApplyPlateAppearance(plate, settings)
    local typeSettings = NP.GetTypeSettings(plate) or {}
    plate.npAppearanceType = plate.npType
    local mode = NPDriver.StampRenderMode(plate)

    local QUICore = ns.Addon
    local pinned = QUICore and QUICore.PushPixelReference and QUICore.PopPixelReference
    if pinned then QUICore:PushPixelReference(nil) end

    NPDriver.PinPlateScale(plate)
    NPHealth.ApplyAppearance(plate, typeSettings)
    NP.Castbar.ApplyAppearance(plate, typeSettings)
    NP.Auras.ApplyAppearance(plate)
    if NPExtras.ApplyAppearance then
        NPExtras.ApplyAppearance(plate, typeSettings)
    end

    local health = typeSettings.health or {}
    local cast = typeSettings.castbar or {}
    local nameS = typeSettings.name or {}
    local spacing = (settings.cvars and settings.cvars.stackingSpacing) or 1.0
    local w = (health.width or 210)
    local pb = typeSettings.powerBar or {}
    local powerH = (pb.enabled == true) and (pb.height or 6) or 0
    local h = ((health.height or 24) + (cast.height or 17) + powerH + ((nameS.size or 11) + math.abs(nameS.offsetY or 4)))
    if NP.IsLightweightMode(mode) then
        h = (health.height or 24) + ((nameS.size or 11) + math.abs(nameS.offsetY or 4))
    end
    plate.npStackBounds:ClearAllPoints()
    plate.npStackBounds:SetPoint("CENTER", plate, "CENTER", 0, 0)
    QUICore:SetPixelPerfectSize(plate.npStackBounds, w * spacing, h * spacing)

    ApplyRenderMode(plate, mode)
    ReapplyDynamicVisuals(plate)

    if pinned then QUICore:PopPixelReference() end
end

local function SetUnit(plate, unit, base)
    plate.unit = unit
    plate.npBase = base
    plates[unit] = plate
    NP.platesByBase[base] = plate

    plate:SetParent(base)
    plate:ClearAllPoints()

    local settings = NP.GetSettings()
    plate:SetPoint("CENTER", base, "CENTER", 0, (settings.layout and settings.layout.verticalOffset) or 0)
    plate:SetFrameLevel((base:GetFrameLevel() or 0) + 1)

    ComputeUnitState(plate)

    if plate.npAppearanceGen ~= NP.appearanceGen or plate.npAppearanceType ~= plate.npType then
        plate.npAppearanceGen = NP.appearanceGen
        ApplyPlateAppearance(plate, settings)
    end

    for i = 1, #PLATE_UNIT_EVENTS do
        plate:RegisterUnitEvent(PLATE_UNIT_EVENTS[i], unit)
    end

    if base.SetStackingBoundsFrame then
        pcall(base.SetStackingBoundsFrame, base, plate.npStackBounds)
    end

    NPHealth.UpdateHealth(plate)
    NPHealth.UpdateColor(plate, NP.GetTypeSettings(plate), NPExtras.GetContext())
    plate:Show()
    ApplyResolvedRenderMode(plate)

    plate.npDeferredPending = true
    deferredPlates[plate] = true
    deferFrame:Show()
end

local function GetBase(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
    local ok, base = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if ok then return base end
    return nil
end

local function BuildEnemyPlate(unit, base)
    base = base or GetBase(unit)
    if not base then return end
    SuppressBlizzardArt(base)
    local existing = plates[unit]
    if existing then
        ReleasePlate(existing)
    end
    local plate = AcquirePlate()
    SetUnit(plate, unit, base)
    NPDriver.ApplySimplified(plate)
    return plate
end
NPDriver.BuildEnemyPlate = BuildEnemyPlate

local function OnNamePlateAdded(unit)
    if not NP.IsEnabled() then return end
    local okSelf, isSelf = pcall(UnitIsUnit, unit, "player")
    if okSelf and NP.Plain(isSelf, "boolean") == true then return end

    local base = GetBase(unit)
    if not base then return end

    BuildEnemyPlate(unit, base)
end
NPDriver.RouteUnit = OnNamePlateAdded

local function OnNamePlateRemoved(unit)
    local plate = plates[unit]
    if not plate then return end
    local base = plate.npBase
    ReleasePlate(plate)
    if base then
        RestoreBlizzardArt(base)
    end
end

local hooksInstalled = false
local function InstallHooks()
    if hooksInstalled then return end
    local blizzDriver = _G.NamePlateDriverFrame
    if not blizzDriver then return end
    hooksInstalled = true

    hooksecurefunc(blizzDriver, "OnNamePlateAdded", function(_, unit)
        if not NP.IsEnabled() then return end
        local okSelf, isSelf = pcall(UnitIsUnit, unit, "player")
        if okSelf and NP.Plain(isSelf, "boolean") == true then return end
        local base = GetBase(unit)
        if base then
            SuppressBlizzardArt(base)
        end
    end)

    hooksecurefunc(blizzDriver, "UpdateNamePlateOptions", function()
        if not NP.IsEnabled() then return end
        NPCVars.ApplyPlateSize()
    end)
end

local prewarmDone = false
local function Prewarm()
    if prewarmDone or not NP.IsEnabled() then return end
    prewarmDone = true
    local created = 0
    local ticker
    ticker = C_Timer.NewTicker(0.1, function()
        created = created + 1
        ReleasePlate(BuildPlate())
        if created >= 20 and ticker then
            ticker:Cancel()
        end
    end, 20)
end

local function RestyleActivePlates()
    local settings = NP.GetSettings()
    local context = NPExtras.GetContext()
    local layout = settings.layout or {}
    for unit, plate in pairs(plates) do
        if plate.npAppearanceGen ~= NP.appearanceGen or plate.npAppearanceType ~= plate.npType then
            plate.npAppearanceGen = NP.appearanceGen
            ApplyPlateAppearance(plate, settings)
        end
        local base = plate.npBase
        if base then
            plate:ClearAllPoints()
            plate:SetPoint("CENTER", base, "CENTER", 0, layout.verticalOffset or 0)
        end
        PinPlateScale(plate)
        NPDriver.ApplySimplified(plate)
        NPExtras.ApplyPlateAlpha(plate)
        plate.npLastR = nil
        NPHealth.UpdateColor(plate, NP.GetTypeSettings(plate), context)
        NPHealth.UpdateHealth(plate)
    end
end
NP.RestyleActivePlates = RestyleActivePlates

local function TeardownAll()
    for unit, plate in pairs(plates) do
        local base = plate.npBase
        ReleasePlate(plate)
        if base then
            RestoreBlizzardArt(base)
        end
    end
end

function NPDriver.Refresh()
    if NP.IsEnabled() then
        NP.BumpAppearanceGeneration()
        NPCVars.ApplyAll()
        NP.Friendly.ApplyModeCVars()
        RestyleActivePlates()
        Prewarm()
    else
        TeardownAll()
    end
end

ns.QUI_RefreshNameplates = NPDriver.Refresh

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("UI_SCALE_CHANGED")
eventFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")

local function ReassertAppearance()
    if not NP.IsEnabled() then return end
    NP.BumpAppearanceGeneration()
    RestyleActivePlates()
end

eventFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        OnNamePlateAdded(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        OnNamePlateRemoved(unit)
    elseif event == "PLAYER_LOGIN" then
        InstallHooks()
        if NP.IsEnabled() then
            Prewarm()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        InstallHooks()
        if NP.IsEnabled() then
            NPExtras.RefreshContext()
            NPCVars.ApplyAll()
            ReassertAppearance()
            if C_Timer and C_Timer.After then
                C_Timer.After(1, ReassertAppearance)
            end
        end
    elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        ReassertAppearance()
    end
end)

InstallHooks()

local function SetupDebugInstrumentation()
    ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
    ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "NameplateDriver", frame = eventFrame }
    ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "NameplateDefer", frame = deferFrame, scriptType = "OnUpdate" }
end
if ns.DebugRegister then
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation()
end
