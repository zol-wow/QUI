local ADDON_NAME, ns = ...
local NP = ns.QUI_Nameplates
if not NP then return end

local UIKit = ns.UIKit
local QUICore = ns.Addon

local type = type
local pcall = pcall
local wipe = wipe
local CreateFrame = CreateFrame
local UnitThreatSituation = UnitThreatSituation
local IsInInstance = IsInInstance
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local UnitExists = UnitExists
local UnitIsUnit = UnitIsUnit
local GetRaidTargetIndex = GetRaidTargetIndex
local UnitHealthPercent = UnitHealthPercent

local NPExtras = {}
NP.Extras = NPExtras

local RAID_MARKER_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local ASSET_ROOT = (ns.Helpers and ns.Helpers.AssetPath) or "Interface\\AddOns\\QUI\\assets\\"

local context = {
    role = "DAMAGER",
    inInstance = false,
    instanceKind = "world",
}
NPExtras.context = context

function NPExtras.GetContext()
    return context
end

local function RefreshContext()
    local ok, inInstance, instanceType = pcall(IsInInstance)
    inInstance = ok and NP.Plain(inInstance, "boolean") or false
    instanceType = ok and NP.Plain(instanceType, "string") or nil
    if inInstance then
        if instanceType == "raid" then
            context.inInstance = true
            context.instanceKind = "raid"
        elseif instanceType == "party" or instanceType == "scenario" then
            context.inInstance = true
            context.instanceKind = "dungeon"
        else
            context.inInstance = false
            context.instanceKind = "world"
        end
    else
        context.inInstance = false
        context.instanceKind = "world"
    end

    local role
    if UnitGroupRolesAssigned then
        local okRole, r = pcall(UnitGroupRolesAssigned, "player")
        r = okRole and NP.Plain(r, "string") or nil
        if r and r ~= "NONE" then role = r end
    end
    if not role and GetSpecialization and GetSpecializationRole then
        local okSpec, spec = pcall(GetSpecialization)
        spec = okSpec and NP.Plain(spec, "number") or nil
        if spec then
            local okR, r = pcall(GetSpecializationRole, spec)
            role = okR and NP.Plain(r, "string") or nil
        end
    end
    context.role = role or "DAMAGER"
end
NPExtras.RefreshContext = RefreshContext

local groupTanks = {}

function NPExtras.GetGroupTanks()
    return groupTanks
end

local function RefreshGroupTanks()
    wipe(groupTanks)
    local prefix, count
    local okRaid, inRaid = pcall(IsInRaid)
    if okRaid and NP.Plain(inRaid, "boolean") == true then
        prefix, count = "raid", 40
    else
        local okGroup, inGroup = pcall(IsInGroup)
        if not (okGroup and NP.Plain(inGroup, "boolean") == true) then return end
        prefix, count = "party", 4
    end
    for i = 1, count do
        local token = prefix .. i
        local okExists, exists = pcall(UnitExists, token)
        if okExists and NP.Plain(exists, "boolean") == true then
            local okSelf, isSelf = pcall(UnitIsUnit, token, "player")
            if not (okSelf and NP.Plain(isSelf, "boolean") == true) then
                local okRole, role = pcall(UnitGroupRolesAssigned, token)
                if okRole and NP.Plain(role, "string") == "TANK" then
                    groupTanks[#groupTanks + 1] = token
                end
            end
        end
    end
end
NPExtras.RefreshGroupTanks = RefreshGroupTanks

function NPExtras.MapThreatSituation(situation, offTankHasAggro)
    if situation == nil then return nil end
    if situation >= 2 then return "high" end
    if offTankHasAggro == true then return "offtank" end
    if situation == 1 then return "near" end
    return "low"
end

local function OffTankHasAggro(unit)
    for i = 1, #groupTanks do
        local ok, situation = pcall(UnitThreatSituation, groupTanks[i], unit)
        situation = ok and NP.Plain(situation, "number") or nil
        if situation and situation >= 2 then
            return true
        end
    end
    return false
end

function NPExtras.UpdateThreat(plate)
    local unit = plate.unit
    if not unit then return end
    local ok, situation = pcall(UnitThreatSituation, "player", unit)
    situation = ok and NP.Plain(situation, "number") or nil
    local offTank = false
    if situation ~= nil and situation < 2 and context.role == "TANK" and #groupTanks > 0 then
        offTank = OffTankHasAggro(unit)
    end
    plate.npThreat = NPExtras.MapThreatSituation(situation, offTank)
end

local questCache = {}
local questCacheDirty = false

local function ScanQuestLines(unit)
    if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return false end
    local okData, data = pcall(C_TooltipInfo.GetUnit, unit)
    if not okData or type(data) ~= "table" or type(data.lines) ~= "table" then
        return false
    end
    local playerName = UnitName and NP.Plain(UnitName("player"), "string") or nil
    for i = 1, #data.lines do
        local line = data.lines[i]
        if type(line) == "table" then
            local lineType = NP.Plain(line.type, "number")
            if lineType == 8 or lineType == 17 then
                return true
            end
            local okText, isQuest = pcall(function()
                local text = line.leftText
                if type(text) ~= "string" then return false end
                if playerName and text == playerName then return false end
                return text:find("%d+/%d+") ~= nil or text:find("%d+%%") ~= nil
            end)
            if okText and isQuest == true then
                return true
            end
        end
    end
    return false
end

function NPExtras.IsQuestUnit(unit)
    if not unit then return false end
    local cached = questCache[unit]
    if cached ~= nil then return cached end
    local isQuest = ScanQuestLines(unit) == true
    questCache[unit] = isQuest
    return isQuest
end

function NPExtras.InvalidateQuestCache(unit)
    if unit then
        questCache[unit] = nil
    else
        wipe(questCache)
    end
end

local titleCache = {}

function NPExtras.InvalidateTitleCache()
    wipe(titleCache)
end

function NPExtras.GetNpcTitle(unit)
    if not unit or context.inInstance == true then return nil end
    local cached = titleCache[unit]
    if cached ~= nil then return cached or nil end
    local title = false
    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        local okData, data = pcall(C_TooltipInfo.GetUnit, unit)
        if okData and type(data) == "table" and type(data.lines) == "table" then
            local line = data.lines[2]
            local okText, text = pcall(function()
                local t = line and line.leftText
                if type(t) ~= "string" then return nil end
                if t == "" or t:find("%d") then return nil end
                return t
            end)
            if okText and type(text) == "string" then title = text end
        end
    end
    titleCache[unit] = title
    return title or nil
end

local EXECUTE_SPELLS = {
    [5331]   = 20,
    [163201] = 20,
    [5308]   = 20,
    [281001] = 35,
    [206315] = 35,
    [322109] = 15,
    [32379]  = 20,
    [392507] = 35,
    [343294] = 35,
    [328085] = 35,
    [388667] = 20,
    [17877]  = 20,
    [234876] = 35,
    [2948]   = 30,
}

function NPExtras.GetExecuteSpellThresholds()
    return EXECUTE_SPELLS
end

local executeKnownProbe = nil
local autoThreshold, autoResolved = nil, false

function NPExtras.InvalidateExecuteThreshold()
    autoResolved = false
    autoThreshold = nil
end

function NPExtras._SetExecuteKnownProbe(fn)
    executeKnownProbe = fn
    NPExtras.InvalidateExecuteThreshold()
end

local function IsExecuteSpellKnown(spellId)
    if executeKnownProbe then
        return executeKnownProbe(spellId) == true
    end
    if type(IsPlayerSpell) ~= "function" then return false end
    local ok, isKnown = pcall(IsPlayerSpell, spellId)
    return ok and NP.Plain(isKnown, "boolean") == true
end

local function ResolveAutoThreshold()
    autoResolved = true
    autoThreshold = nil
    for spellId, pct in pairs(EXECUTE_SPELLS) do
        if IsExecuteSpellKnown(spellId) then
            if not autoThreshold or pct > autoThreshold then
                autoThreshold = pct
            end
        end
    end
end

function NPExtras.ResolveExecuteThreshold(manualPct, autoEnabled)
    if autoEnabled == false then return manualPct end
    if not autoResolved then ResolveAutoThreshold() end
    return autoThreshold or manualPct
end

local executeCurve, executeCurveThreshold

local function GetExecuteCurve(thresholdPct)
    if executeCurve and executeCurveThreshold == thresholdPct then
        return executeCurve
    end
    if not (C_CurveUtil and C_CurveUtil.CreateCurve and Enum and Enum.LuaCurveType) then
        return nil
    end
    local curve = C_CurveUtil.CreateCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    curve:AddPoint(0.0, 1)
    curve:AddPoint((thresholdPct or 35) / 100, 0)
    executeCurve, executeCurveThreshold = curve, thresholdPct
    return curve
end

function NPExtras.UpdateExecute(plate)
    local overlay = plate.npExecuteOverlay
    if not overlay then return end
    local unit = plate.unit
    local settings = NP.GetTypeSettings(plate) or {}
    local colors = settings.colors or {}
    if not unit or colors.executeEnabled ~= true or type(UnitHealthPercent) ~= "function" then
        overlay:SetAlpha(0)
        return
    end
    local curve = GetExecuteCurve(NPExtras.ResolveExecuteThreshold(
        colors.executeThreshold or 35, colors.executeAuto ~= false))
    if not curve then
        overlay:SetAlpha(0)
        return
    end
    local ok, alpha = pcall(UnitHealthPercent, unit, nil, curve)
    if ok and issecretvalue and issecretvalue(alpha) then
        pcall(overlay.SetAlpha, overlay, alpha) -- @secret-safe: secret alpha rides the C-side SetAlpha sink
    elseif ok and alpha ~= nil then -- @secret-safe: issecretvalue branch above proves alpha plain here
        pcall(overlay.SetAlpha, overlay, alpha)
    else
        overlay:SetAlpha(0)
    end
end

function NPExtras.BuildPlate(plate)
    local marker = plate:CreateTexture(nil, "OVERLAY", nil, 5)
    marker:SetTexture(RAID_MARKER_TEXTURE)
    marker:Hide()
    plate.npRaidMarker = marker

    local glow = plate:CreateTexture(nil, "BACKGROUND", nil, -7)
    glow:SetTexture("Interface\\Buttons\\WHITE8x8")
    glow:SetBlendMode("ADD")
    glow:Hide()
    plate.npTargetGlow = glow

    local arrowL = plate:CreateTexture(nil, "OVERLAY", nil, 6)
    arrowL:SetTexture(ASSET_ROOT .. "nameplate_arrow")
    arrowL:SetTexCoord(1, 0, 0, 1)
    arrowL:Hide()
    plate.npTargetArrowL = arrowL

    local arrowR = plate:CreateTexture(nil, "OVERLAY", nil, 6)
    arrowR:SetTexture(ASSET_ROOT .. "nameplate_arrow")
    arrowR:Hide()
    plate.npTargetArrowR = arrowR

    local brackets = plate:CreateTexture(nil, "OVERLAY", nil, 6)
    brackets:SetTexture(ASSET_ROOT .. "nameplate_brackets")
    brackets:Hide()
    plate.npTargetBrackets = brackets

    local glowline = plate:CreateTexture(nil, "OVERLAY", nil, 6)
    glowline:SetTexture(ASSET_ROOT .. "nameplate_glowline")
    glowline:Hide()
    plate.npTargetGlowline = glowline

    local focusGlow = plate:CreateTexture(nil, "BACKGROUND", nil, -7)
    focusGlow:SetTexture("Interface\\Buttons\\WHITE8x8")
    focusGlow:SetBlendMode("ADD")
    focusGlow:Hide()
    plate.npFocusGlow = focusGlow

    local hover = plate.healthBar:CreateTexture(nil, "ARTWORK", nil, 3)
    hover:SetAllPoints(plate.healthBar)
    hover:SetColorTexture(1, 1, 1, 1)
    hover:SetAlpha(0)
    plate.npHoverHighlight = hover

    local execute = plate.healthBar:CreateTexture(nil, "ARTWORK", nil, 2)
    execute:SetAllPoints(plate.healthBar)
    execute:SetAlpha(0)
    plate.npExecuteOverlay = execute

    local hitbox = plate:CreateTexture(nil, "BACKGROUND", nil, -8)
    hitbox:SetColorTexture(0, 0.8, 1, 0.25)
    hitbox:Hide()
    plate.npHitboxVis = hitbox

    local pvp = plate:CreateTexture(nil, "OVERLAY", nil, 6)
    pvp:Hide()
    plate.npPvpIcon = pvp

    local quest = plate:CreateTexture(nil, "OVERLAY", nil, 5)
    quest:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
    quest:Hide()
    plate.npQuestIcon = quest
end

local PVP_CLASS_ATLAS

local function GetPvpAtlasMap()
    if PVP_CLASS_ATLAS ~= nil then return PVP_CLASS_ATLAS or nil end
    local e = Enum and Enum.PvPUnitClassification
    if not e then
        PVP_CLASS_ATLAS = false
        return nil
    end
    PVP_CLASS_ATLAS = {
        [e.FlagCarrierHorde]    = "nameplates-icon-flag-horde",
        [e.FlagCarrierAlliance] = "nameplates-icon-flag-alliance",
        [e.FlagCarrierNeutral]  = "nameplates-icon-flag-neutral",
        [e.CartRunnerHorde]     = "nameplates-icon-cart-horde",
        [e.CartRunnerAlliance]  = "nameplates-icon-cart-alliance",
        [e.AssassinHorde]       = "nameplates-icon-bounty-horde",
        [e.AssassinAlliance]    = "nameplates-icon-bounty-alliance",
        [e.OrbCarrierBlue]      = "nameplates-icon-orb-blue",
        [e.OrbCarrierGreen]     = "nameplates-icon-orb-green",
        [e.OrbCarrierOrange]    = "nameplates-icon-orb-orange",
        [e.OrbCarrierPurple]    = "nameplates-icon-orb-purple",
    }
    return PVP_CLASS_ATLAS
end

function NPExtras.UpdatePvpIcon(plate)
    local icon = plate.npPvpIcon
    if not icon then return end
    local unit = plate.unit
    if not unit or not plate.npPvpIconEnabled or type(UnitPvpClassification) ~= "function" then
        icon:Hide()
        return
    end
    local map = GetPvpAtlasMap()
    if not map then
        icon:Hide()
        return
    end
    local ok, classification = pcall(UnitPvpClassification, unit)
    local plainClass = ok and NP.Plain(classification, "number") or nil
    local atlas = plainClass and map[plainClass] or nil
    if not atlas then
        icon:Hide()
        return
    end
    local okAtlas = pcall(icon.SetAtlas, icon, atlas, false)
    if okAtlas then icon:Show() else icon:Hide() end
end

function NPExtras.UpdateQuestIcon(plate)
    local icon = plate.npQuestIcon
    if not icon then return end
    if plate.npQuestIconEnabled and plate.npIsQuest == true then
        icon:Show()
    else
        icon:Hide()
    end
end

function NPExtras.ApplyAppearance(plate, settings)
    local highlight = settings.highlight or {}
    local markerS = settings.raidMarker or {}
    local colors = settings.colors or {}

    local size = markerS.size or 24
    QUICore:SetPixelPerfectSize(plate.npRaidMarker, size, size)
    plate.npRaidMarker:ClearAllPoints()
    local pos = markerS.position or "TOPRIGHT"
    if pos == "TOP" then
        plate.npRaidMarker:SetPoint("BOTTOM", plate.nameText, "TOP", 0, QUICore:Pixels(2, plate))
    elseif pos == "LEFT" then
        plate.npRaidMarker:SetPoint("RIGHT", plate.healthBar, "LEFT", -QUICore:Pixels(4, plate), 0)
    elseif pos == "RIGHT" then
        plate.npRaidMarker:SetPoint("LEFT", plate.healthBar, "RIGHT", QUICore:Pixels(4, plate), 0)
    else
        plate.npRaidMarker:SetPoint("BOTTOMLEFT", plate.healthBar, "TOPRIGHT", QUICore:Pixels(2, plate), QUICore:Pixels(2, plate))
    end
    plate.npRaidMarkerEnabled = markerS.enabled ~= false

    local questS = settings.questIcon or {}
    local questSize = questS.size or 18
    QUICore:SetPixelPerfectSize(plate.npQuestIcon, questSize, questSize)
    plate.npQuestIcon:ClearAllPoints()
    local questPos = questS.position or "LEFT"
    if questPos == "RIGHT" then
        plate.npQuestIcon:SetPoint("LEFT", plate.healthBar, "RIGHT", QUICore:Pixels(4, plate), 0)
    elseif questPos == "TOP" then
        plate.npQuestIcon:SetPoint("BOTTOM", plate.nameText, "TOP", 0, QUICore:Pixels(2, plate))
    else
        plate.npQuestIcon:SetPoint("RIGHT", plate.healthBar, "LEFT", -QUICore:Pixels(4, plate), 0)
    end
    plate.npQuestIconEnabled = questS.enabled == true
    NPExtras.UpdateQuestIcon(plate)

    local pvpS = settings.pvpIcon or {}
    local pvpSize = pvpS.size or 20
    QUICore:SetPixelPerfectSize(plate.npPvpIcon, pvpSize, pvpSize)
    plate.npPvpIcon:ClearAllPoints()
    plate.npPvpIcon:SetPoint("RIGHT", plate.healthBar, "LEFT", -QUICore:Pixels(4, plate), 0)
    plate.npPvpIconEnabled = pvpS.enabled ~= false
    NPExtras.UpdatePvpIcon(plate)

    local gc = highlight.targetGlowColor or { 0.412, 0.667, 1.0 }
    plate.npTargetGlow:SetVertexColor(gc[1], gc[2], gc[3], highlight.targetGlowAlpha or 1)
    plate.npTargetGlow:ClearAllPoints()
    plate.npTargetGlow:SetPoint("TOPLEFT", plate.healthBar, "TOPLEFT", -QUICore:Pixels(6, plate), QUICore:Pixels(6, plate))
    plate.npTargetGlow:SetPoint("BOTTOMRIGHT", plate.healthBar, "BOTTOMRIGHT", QUICore:Pixels(6, plate), -QUICore:Pixels(6, plate))
    plate.npTargetGlowEnabled = highlight.targetGlow ~= false

    local style = highlight.targetStyle or "wash"
    plate.npTargetStyle = style
    local ga = highlight.targetGlowAlpha or 1
    local barH = (settings.health and settings.health.height) or 24
    local barW = (settings.health and settings.health.width) or 210

    if style == "arrows" then
        local sz = barH + 8
        QUICore:SetPixelPerfectSize(plate.npTargetArrowL, sz, sz)
        QUICore:SetPixelPerfectSize(plate.npTargetArrowR, sz, sz)
        plate.npTargetArrowL:ClearAllPoints()
        plate.npTargetArrowL:SetPoint("RIGHT", plate.healthBar, "LEFT", -QUICore:Pixels(2, plate), 0)
        plate.npTargetArrowR:ClearAllPoints()
        plate.npTargetArrowR:SetPoint("LEFT", plate.healthBar, "RIGHT", QUICore:Pixels(2, plate), 0)
        plate.npTargetArrowL:SetVertexColor(gc[1], gc[2], gc[3], ga)
        plate.npTargetArrowR:SetVertexColor(gc[1], gc[2], gc[3], ga)
    elseif style == "brackets" then
        QUICore:SetPixelPerfectSize(plate.npTargetBrackets, barW + 16, barH + 8)
        plate.npTargetBrackets:ClearAllPoints()
        plate.npTargetBrackets:SetPoint("CENTER", plate.healthBar, "CENTER", 0, 0)
        plate.npTargetBrackets:SetVertexColor(gc[1], gc[2], gc[3], ga)
    elseif style == "glowline" then
        QUICore:SetPixelPerfectSize(plate.npTargetGlowline, barW, 8)
        plate.npTargetGlowline:ClearAllPoints()
        plate.npTargetGlowline:SetPoint("TOP", plate.healthBar, "BOTTOM", 0, -QUICore:Pixels(1, plate))
        plate.npTargetGlowline:SetVertexColor(gc[1], gc[2], gc[3], ga)
    end

    local fc = highlight.focusGlowColor or { 0.051, 0.820, 0.620 }
    plate.npFocusGlow:SetVertexColor(fc[1], fc[2], fc[3], highlight.focusGlowAlpha or 1)
    plate.npFocusGlow:ClearAllPoints()
    plate.npFocusGlow:SetPoint("TOPLEFT", plate.healthBar, "TOPLEFT", -QUICore:Pixels(6, plate), QUICore:Pixels(6, plate))
    plate.npFocusGlow:SetPoint("BOTTOMRIGHT", plate.healthBar, "BOTTOMRIGHT", QUICore:Pixels(6, plate), -QUICore:Pixels(6, plate))
    plate.npFocusGlowEnabled = highlight.focusGlow == true

    local mc = highlight.mouseoverColor or { 1, 1, 1 }
    plate.npHoverHighlight:SetColorTexture(mc[1] or 1, mc[2] or 1, mc[3] or 1, 1)
    plate.npHoverAlpha = highlight.mouseoverAlpha or 0.3
    plate.npHoverEnabled = highlight.mouseover ~= false

    local ec = colors.execute or { 1, 0.1, 0.1 }
    plate.npExecuteOverlay:SetColorTexture(ec[1], ec[2], ec[3], 0.55)

    NPExtras.ApplyHitboxVisual(plate)
end

function NPExtras.UpdateRaidMarker(plate)
    local marker = plate.npRaidMarker
    if not marker then return end
    local unit = plate.unit
    if not unit or not plate.npRaidMarkerEnabled then
        marker:Hide()
        return
    end
    local ok, index = pcall(GetRaidTargetIndex, unit)
    index = ok and NP.Plain(index, "number") or nil
    if index and index >= 1 and index <= 8 then
        if SetRaidTargetIconTexture then
            pcall(SetRaidTargetIconTexture, marker, index)
        end
        marker:Show()
    else
        marker:Hide()
    end
end

local currentTargetPlate, currentFocusPlate

local function RefreshPlateColor(plate)
    NP.Health.UpdateColor(plate, NP.GetTypeSettings(plate), context)
end

local function HideTargetStyleTextures(plate)
    if plate.npTargetGlow then plate.npTargetGlow:Hide() end
    if plate.npTargetArrowL then plate.npTargetArrowL:Hide() end
    if plate.npTargetArrowR then plate.npTargetArrowR:Hide() end
    if plate.npTargetBrackets then plate.npTargetBrackets:Hide() end
    if plate.npTargetGlowline then plate.npTargetGlowline:Hide() end
end

local function ApplyTargetVisual(plate)
    HideTargetStyleTextures(plate)
    if not (plate.npIsTarget == true and plate.npTargetGlowEnabled) then return end
    local style = plate.npTargetStyle or "wash"
    if style == "arrows" then
        plate.npTargetArrowL:Show()
        plate.npTargetArrowR:Show()
    elseif style == "brackets" then
        plate.npTargetBrackets:Show()
    elseif style == "glowline" then
        plate.npTargetGlowline:Show()
    else
        plate.npTargetGlow:Show()
    end
end

local playerHasTarget = false

function NPExtras.ApplyPlateAlpha(plate)
    local fading = NP.GetSettings().fading or {}
    local dim = fading.nonTargetAlpha or 1.0
    if dim >= 1 or not playerHasTarget or plate.npIsTarget == true then
        plate:SetAlpha(1)
    else
        plate:SetAlpha(dim)
    end
end

local function ApplyFocusVisual(plate)
    if not plate.npFocusGlow then return end
    if plate.npIsFocus == true and plate.npFocusGlowEnabled then
        plate.npFocusGlow:Show()
    else
        plate.npFocusGlow:Hide()
    end
end

local ResolvePlateFor
ResolvePlateFor = function(token)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
    local ok, base = pcall(C_NamePlate.GetNamePlateForUnit, token)
    if not ok or not base then return nil end
    return NP.platesByBase[base]
end
NPExtras.ResolvePlateFor = ResolvePlateFor

local function OnTargetChanged()
    local okExists, hasTarget = pcall(UnitExists, "target")
    playerHasTarget = okExists and NP.Plain(hasTarget, "boolean") == true

    local old = currentTargetPlate
    currentTargetPlate = nil
    if old and old.unit then
        old.npIsTarget = false
        ApplyTargetVisual(old)
        RefreshPlateColor(old)
        if NP.Driver and NP.Driver.PinPlateScale then NP.Driver.PinPlateScale(old) end
    end
    local plate = ResolvePlateFor("target")
    if plate and plate.unit then
        plate.npIsTarget = true
        currentTargetPlate = plate
        ApplyTargetVisual(plate)
        RefreshPlateColor(plate)
        if NP.Driver and NP.Driver.PinPlateScale then NP.Driver.PinPlateScale(plate) end
    end

    if NP.Power and NP.Power.AttachToTarget then NP.Power.AttachToTarget() end

    local dim = (NP.GetSettings().fading or {}).nonTargetAlpha or 1.0
    if dim < 1 then
        for _, p in pairs(NP.plates) do
            NPExtras.ApplyPlateAlpha(p)
        end
    else
        if old then NPExtras.ApplyPlateAlpha(old) end
        if plate then NPExtras.ApplyPlateAlpha(plate) end
    end
end

local function OnFocusChanged()
    local old = currentFocusPlate
    currentFocusPlate = nil
    if old and old.unit then
        old.npIsFocus = false
        ApplyFocusVisual(old)
        RefreshPlateColor(old)
    end
    local plate = ResolvePlateFor("focus")
    if plate and plate.unit then
        plate.npIsFocus = true
        currentFocusPlate = plate
        ApplyFocusVisual(plate)
        RefreshPlateColor(plate)
    end
end

local hoverPlate, hoverTicker

local function StopHover()
    if hoverPlate then
        hoverPlate.npHoverHighlight:SetAlpha(0)
        hoverPlate = nil
    end
    if hoverTicker then
        hoverTicker:Cancel()
        hoverTicker = nil
    end
end

local function HoverTick()
    local plate = hoverPlate
    if not plate or not plate.unit then
        StopHover()
        return
    end
    local ok, stillHovered = pcall(UnitIsUnit, "mouseover", plate.unit)
    if not (ok and NP.Plain(stillHovered, "boolean") == true) then
        StopHover()
    end
end

local function OnMouseoverChanged()
    local plate = ResolvePlateFor("mouseover")
    if plate == hoverPlate then return end
    StopHover()
    if not plate or not plate.npHoverEnabled or not plate.unit then return end
    hoverPlate = plate
    plate.npHoverHighlight:SetAlpha(plate.npHoverAlpha or 0.3)
    if C_Timer and C_Timer.NewTicker then
        hoverTicker = C_Timer.NewTicker(0.1, HoverTick)
    end
end

function NPExtras.ApplyHitboxVisual(plate)
    local hitbox = plate.npHitboxVis
    if not hitbox then return end
    local settings = NP.GetSettings()
    local cv = settings and settings.cvars
    if cv and cv.hitboxVisualizer == true and plate.npBase then
        hitbox:ClearAllPoints()
        hitbox:SetAllPoints(plate.npBase)
        hitbox:Show()
    else
        hitbox:Hide()
    end
end

function NPExtras.OnPlateShown(plate)
    NPExtras.UpdateRaidMarker(plate)
    if plate.npIsTarget == true then
        currentTargetPlate = plate
    end
    if plate.npIsFocus == true then
        currentFocusPlate = plate
    end
    ApplyTargetVisual(plate)
    ApplyFocusVisual(plate)
    NPExtras.ApplyPlateAlpha(plate)
    NPExtras.UpdateQuestIcon(plate)
    NPExtras.UpdatePvpIcon(plate)
    NPExtras.UpdateExecute(plate)

    NPExtras.ApplyHitboxVisual(plate)
end

function NPExtras.ClearPlate(plate)
    if currentTargetPlate == plate then currentTargetPlate = nil end
    if currentFocusPlate == plate then currentFocusPlate = nil end
    if hoverPlate == plate then StopHover() end
    if plate.npRaidMarker then plate.npRaidMarker:Hide() end
    HideTargetStyleTextures(plate)
    if plate.npFocusGlow then plate.npFocusGlow:Hide() end
    if plate.npQuestIcon then plate.npQuestIcon:Hide() end
    if plate.npPvpIcon then plate.npPvpIcon:Hide() end
    if plate.npHoverHighlight then plate.npHoverHighlight:SetAlpha(0) end
    if plate.npExecuteOverlay then plate.npExecuteOverlay:SetAlpha(0) end
    if plate.npHitboxVis then plate.npHitboxVis:Hide() end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("SPELLS_CHANGED")
eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
eventFrame:RegisterEvent("RAID_TARGET_UPDATE")
eventFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
eventFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_REMOVED" then
        local token = NP.Plain(unit, "string")
        if token then
            questCache[token] = nil
            titleCache[token] = nil
        end
        return
    end
    if event == "PLAYER_TARGET_CHANGED" then
        if NP.IsEnabled() then OnTargetChanged() end
        return
    end
    if event == "UPDATE_MOUSEOVER_UNIT" then
        if NP.IsEnabled() then OnMouseoverChanged() end
        return
    end
    if event == "PLAYER_FOCUS_CHANGED" then
        if NP.IsEnabled() then OnFocusChanged() end
        return
    end
    if event == "RAID_TARGET_UPDATE" then
        if NP.IsEnabled() then
            for _, plate in pairs(NP.plates) do
                NPExtras.UpdateRaidMarker(plate)
            end
        end
        return
    end
    if event == "QUEST_LOG_UPDATE" then
        if not questCacheDirty then
            questCacheDirty = true
            C_Timer.After(0, function()
                questCacheDirty = false
                wipe(questCache)
                wipe(titleCache)
                for _, plate in pairs(NP.plates) do
                    if plate.unit then
                        plate.npIsQuest = NPExtras.IsQuestUnit(plate.unit) == true
                        NPExtras.UpdateQuestIcon(plate)
                        NP.Health.UpdateColor(plate, NP.GetTypeSettings(plate), context)
                    end
                end
            end)
        end
        return
    end
    if event == "GROUP_ROSTER_UPDATE" then
        RefreshGroupTanks()
        return
    end
    if event == "SPELLS_CHANGED" then
        NPExtras.InvalidateExecuteThreshold()
        return
    end
    NPExtras.InvalidateExecuteThreshold()
    wipe(titleCache)
    RefreshContext()
    RefreshGroupTanks()
end)
