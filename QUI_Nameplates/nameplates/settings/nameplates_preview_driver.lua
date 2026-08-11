local ADDON_NAME, ns = ...

local Helpers = ns.Helpers

local PREVIEW_HP = 65
local PREVIEW_ABSORB = 12
local PREVIEW_HEAL = 22
local PREVIEW_POWER = 55
local PREVIEW_ABS_TEXT = "1.4M"
local PREVIEW_ABSORB_TEXT = "+240K"
local PREVIEW_EXECUTE_ALPHA = 0.75
local CAST_PROGRESS = 0.62

local PREVIEW_BASE_OFFSET_X = 0
local PREVIEW_BASE_OFFSET_Y = 0
local PREVIEW_MEASURE_ATTEMPTS = 4

local PREVIEW_DEFAULT_STATE = {
    reaction = "hostile",
    isTarget = true,
    inCombat = true,
    casting = true,
}

local state = {
    host = nil,
    plate = nil,
    offsetX = PREVIEW_BASE_OFFSET_X,
    offsetY = PREVIEW_BASE_OFFSET_Y,
    extentW = nil,
    extentH = nil,
    observer = nil,
    preview = nil,
    byHost = setmetatable({}, { __mode = "k" }),
}

local PreviewDriver = {}

local FAKE_STATE = {
    petMinion    = { isMinion = true,  reaction = 2, classification = "normal",    isPlayer = false, name = "Voidwalker" },
    friendly     = { isMinion = false, reaction = 5, classification = "normal",    isPlayer = true,  name = "Ally" },
    bossElite    = { isMinion = false, reaction = 2, classification = "worldboss", isPlayer = false, name = "Boss" },
    minorTrivial = { isMinion = false, reaction = 2, classification = "minus",     isPlayer = false, name = "Critter" },
    enemyPlayer  = { isMinion = false, reaction = 2, classification = "normal",    isPlayer = true,  name = "Rival" },
    enemyNPC     = { isMinion = false, reaction = 2, classification = "normal",    isPlayer = false, name = "Target Dummy" },
}
PreviewDriver.FAKE_STATE = FAKE_STATE

local selectedType = nil

local function NP()
    return ns.QUI_Nameplates
end

local function SelectedType()
    if selectedType then return selectedType end
    local np = NP()
    local plateType = np and np.PlateType
    return (plateType and plateType.DEFAULT_KEY)
        or (plateType and plateType.ORDER and plateType.ORDER[1])
        or "enemyNPC"
end

local function PreviewState()
    return state.preview or PREVIEW_DEFAULT_STATE
end

local function PlayerClassToken()
    if type(UnitClass) ~= "function" then return nil end
    local ok, _, token = pcall(UnitClass, "player")
    if ok and type(token) == "string" then return token end
    return nil
end

local function GetSettings()
    local profile = Helpers and Helpers.GetProfile and Helpers.GetProfile()
    return profile and profile.nameplates or nil
end

local function GetTypeSettings(plate)
    local np = NP()
    if not (np and np.GetTypeSettings) then return nil end
    return np.GetTypeSettings(plate)
end

local function FriendlyIsOff(settings)
    local friendlySettings = settings and settings.friendly
    return type(friendlySettings) == "table" and friendlySettings.enabled == false
end

local function ReactionNameFor(value)
    if type(value) ~= "number" then return "hostile" end
    if value >= 5 then return "friendly" end
    if value == 4 then return "neutral" end
    return "hostile"
end

local function StampPreviewType(plate, settings)
    local key = SelectedType()
    local fake = FAKE_STATE[key] or {}
    plate.npType = key
    local np = NP()
    local typeSettings = GetTypeSettings(plate)
    local mode = (np and np.ResolveRenderMode and np.ResolveRenderMode(typeSettings)) or "bars"
    if key == "friendly" and FriendlyIsOff(settings) then mode = "off" end
    plate.npRenderMode = mode
    plate.npReaction = ReactionNameFor(fake.reaction)
    plate.npIsPlayer = fake.isPlayer == true
    plate.npClassToken = plate.npIsPlayer and PlayerClassToken() or nil
end

local function ResolvePreviewElements(settings)
    local NPAuras = ns.QUI_Nameplates and ns.QUI_Nameplates.Auras
    return (NPAuras and NPAuras.ResolveElements and NPAuras.ResolveElements(settings, true)) or {}
end

local function MakeAuraPin(plate)
    local QUICore = ns.Addon
    return function(element)
        local AuraGlue = ns.AuraGlue or (_G.QUI and _G.QUI.AuraGlue)
        if not (AuraGlue and AuraGlue.ElementProfile) then return nil end
        return AuraGlue.ElementProfile(element), element.anchor or "TOP",
            QUICore:Pixels(element.offsetX or 0, plate),
            QUICore:Pixels(element.offsetY or 0, plate)
    end
end

local function PaintFakeAuras(plate, settings)
    local Preview = ns.AuraPreview or (_G.QUI and _G.QUI.AuraPreview)
    if not Preview then return end
    local np = NP()
    if np and np.IsLightweightMode and np.IsLightweightMode(plate.npRenderMode) then
        Preview.Show(plate, {}, {
            anchorTo = plate.healthBar,
            resolve = MakeAuraPin(plate),
        })
        return
    end
    Preview.Show(plate, ResolvePreviewElements(settings), {
        anchorTo = plate.healthBar,
        resolve = MakeAuraPin(plate),
    })
end

local function PaintFakeData(plate, settings)
    local np = NP()
    local QUICore = ns.Addon

    local ps = PreviewState()
    local colors = settings.colors or {}

    local hp = PREVIEW_HP
    if ps.execute == true then
        local threshold = tonumber(colors.executeThreshold) or 35
        hp = math.max(5, threshold - 10)
    end

    plate.healthBar:SetMinMaxValues(0, 100)
    plate.healthBar:SetValue(hp)
    local reaction = ps.reaction
    if reaction == nil or reaction == PREVIEW_DEFAULT_STATE.reaction then
        reaction = plate.npReaction or PREVIEW_DEFAULT_STATE.reaction
    end
    local isPlayer = (ps.player == true) or (plate.npIsPlayer == true)
    local fakeState = {
        npReaction = (reaction == "tapped") and "hostile" or reaction,
        npInCombat = ps.inCombat ~= false,
        npIsPlayer = isPlayer,
        npTapDenied = reaction == "tapped",
        npIsQuest = ps.quest == true,
        npIsTarget = ps.isTarget == true,
        npIsFocus = ps.isFocus == true,
        npThreat = (ps.aggro == true) and "high" or nil,
        npClassToken = isPlayer and (plate.npClassToken or PlayerClassToken()) or nil,
    }
    if np.Colors then
        local r, g, b = np.Colors.Resolve(fakeState, settings,
            { role = "DAMAGER", inInstance = ps.aggro == true })
        plate.healthBar:SetStatusBarColor(r, g, b)
    end

    local absorbS = settings.absorbs or {}
    if plate.absorbBar then
        if absorbS.enabled ~= false then
            plate.absorbBar:SetMinMaxValues(0, 100)
            plate.absorbBar:SetValue(PREVIEW_ABSORB)
            plate.absorbBar:Show()
        else
            plate.absorbBar:Hide()
        end
    end
    if plate.npAbsorbText then
        if plate.npAbsorbTextEnabled and absorbS.enabled ~= false then
            plate.npAbsorbText:SetText(PREVIEW_ABSORB_TEXT)
            plate.npAbsorbText:Show()
        else
            plate.npAbsorbText:Hide()
        end
    end

    if plate.healPredictBar then
        if plate.npHealPredictEnabled then
            plate.healPredictBar:SetMinMaxValues(0, 100)
            plate.healPredictBar:SetValue(PREVIEW_HEAL)
            plate.healPredictBar:Show()
        else
            plate.healPredictBar:Hide()
        end
    end

    if plate.powerBar then
        if plate.npPowerBarEnabled then
            plate.powerBar:SetMinMaxValues(0, 100)
            plate.powerBar:SetValue(PREVIEW_POWER)
            local pc = _G.PowerBarColor and _G.PowerBarColor["MANA"]
            if pc then
                plate.powerBar:SetStatusBarColor(pc.r or 0.3, pc.g or 0.5, pc.b or 0.9)
            else
                plate.powerBar:SetStatusBarColor(0.3, 0.5, 0.9)
            end
            plate.powerBar:Show()
        else
            plate.powerBar:Hide()
        end
    end

    local nameS = settings.name or {}
    plate.nameText:SetText(ns.L["Cleave Training Dummy"])
    local nc = nameS.color or { 1, 1, 1 }
    if fakeState.npClassToken and nameS.classColorPlayers ~= false then
        local cc = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[fakeState.npClassToken]
        if cc then nc = { cc.r or 1, cc.g or 1, cc.b or 1 } end
    end
    plate.nameText:SetTextColor(nc[1] or 1, nc[2] or 1, nc[3] or 1)

    if plate.npTitleText then
        if plate.npTitleEnabled then
            plate.npTitleText:SetText(ns.L["Training Grounds"])
            plate.npTitleText:Show()
        else
            plate.npTitleText:Hide()
        end
    end

    local style = plate.npHealthTextStyle or "percent"
    if style == "none" then
        plate.healthText:SetText("")
    elseif style == "absolute" then
        plate.healthText:SetText(PREVIEW_ABS_TEXT)
    elseif style == "both" then
        plate.healthText:SetFormattedText(plate.npBothFmt or "%s | %d%%", PREVIEW_ABS_TEXT, hp)
    else
        plate.healthText:SetFormattedText(plate.npPctFmt or "%d%%", hp)
    end

    local cast = settings.castbar or {}
    local castBar = plate.castBar
    if castBar then
        if cast.enabled ~= false and ps.casting ~= false then
            castBar:SetMinMaxValues(0, 1)
            castBar:SetValue(CAST_PROGRESS)
            plate.npPlainNotInterruptible = ps.uninterruptible == true
            if np.Castbar and np.Castbar.ReapplyInterruptibleVisuals then
                np.Castbar.ReapplyInterruptibleVisuals(plate)
            else
                local c = colors.castInterruptible or { 0.70, 0.40, 0.90 }
                castBar:SetStatusBarColor(c[1], c[2], c[3])
            end
            if plate.castIcon then
                plate.castIcon:SetTexture(135808)
            end
            if plate.castSpellText then
                plate.castSpellText:SetText(ns.L["Pyroblast"])
            end
            if castBar.timeText then
                castBar.timeText:SetText("1.1")
            end
            if plate.castTargetText then
                if plate.npShowCastTarget then
                    plate.castTargetText:SetText(ns.L["Player"])
                    plate.castTargetText:Show()
                else
                    plate.castTargetText:Hide()
                end
            end
            castBar:Show()

            if plate.kickBar then
                if cast.kickTick ~= false then
                    local fillTex = castBar:GetStatusBarTexture()
                    if fillTex then
                        plate.kickBar:ClearAllPoints()
                        plate.kickBar:SetPoint("TOPLEFT", fillTex, "TOPRIGHT", 0, 0)
                        plate.kickBar:SetPoint("BOTTOMLEFT", fillTex, "BOTTOMRIGHT", 0, 0)
                    end
                    plate.kickBar:SetMinMaxValues(0, 1)
                    plate.kickBar:SetValue(0.18)
                    plate.kickBar:Show()
                else
                    plate.kickBar:Hide()
                end
            end
        else
            castBar:Hide()
            if plate.kickBar then plate.kickBar:Hide() end
            if plate.castTargetText then plate.castTargetText:Hide() end
        end
    end

    local pvpS = settings.pvpIcon or {}
    if plate.npPvpIcon then
        if pvpS.enabled ~= false then
            local okPvp = pcall(plate.npPvpIcon.SetAtlas, plate.npPvpIcon,
                "nameplates-icon-flag-horde", false)
            if okPvp then plate.npPvpIcon:Show() else plate.npPvpIcon:Hide() end
        else
            plate.npPvpIcon:Hide()
        end
    end

    local markerS = settings.raidMarker or {}
    if plate.npRaidMarker then
        if markerS.enabled ~= false and SetRaidTargetIconTexture then
            pcall(SetRaidTargetIconTexture, plate.npRaidMarker, 8)
            plate.npRaidMarker:Show()
        else
            plate.npRaidMarker:Hide()
        end
    end

    local questS = settings.questIcon or {}
    if plate.npQuestIcon then
        if questS.enabled == true then
            plate.npQuestIcon:Show()
        else
            plate.npQuestIcon:Hide()
        end
    end

    local levelS = settings.level or {}
    if plate.npLevelText then
        if levelS.enabled == true then
            plate.npLevelText:SetText("80")
            plate.npLevelText:SetTextColor(1, 0.82, 0)
            plate.npLevelText:Show()
        else
            plate.npLevelText:Hide()
        end
    end
    if plate.npClassIcon then
        local Classification = levelS.showClassification == true and ns.Classification or nil
        local atlas, cr, cg, cb
        if Classification then
            local fake = FAKE_STATE[SelectedType()]
            atlas, cr, cg, cb = Classification.Resolve(fake and fake.classification or "normal")
        end
        local okAtlas = atlas
            and pcall(plate.npClassIcon.SetAtlas, plate.npClassIcon, atlas, false)
        if okAtlas then
            plate.npClassIcon:SetVertexColor(cr, cg, cb)
            plate.npClassIcon:Show()
        else
            plate.npClassIcon:Hide()
        end
    end
    local highlight = settings.highlight or {}
    local previewStyle = highlight.targetStyle or "wash"
    local showTarget = ps.isTarget == true and highlight.targetGlow ~= false
    for _, key in ipairs({ "npTargetArrowL", "npTargetArrowR", "npTargetBrackets", "npTargetGlowline" }) do
        if plate[key] then plate[key]:Hide() end
    end
    if showTarget and previewStyle ~= "wash" then
        if previewStyle == "arrows" then
            if plate.npTargetArrowL then plate.npTargetArrowL:Show() end
            if plate.npTargetArrowR then plate.npTargetArrowR:Show() end
        elseif previewStyle == "brackets" then
            if plate.npTargetBrackets then plate.npTargetBrackets:Show() end
        elseif previewStyle == "glowline" then
            if plate.npTargetGlowline then plate.npTargetGlowline:Show() end
        end
    end
    if plate.npTargetGlow then
        if showTarget and previewStyle == "wash" then
            plate.npTargetGlow:Show()
        else
            plate.npTargetGlow:Hide()
        end
    end
    if plate.npFocusGlow then
        if ps.isFocus == true and plate.npFocusGlowEnabled == true then
            plate.npFocusGlow:Show()
        else
            plate.npFocusGlow:Hide()
        end
    end
    if plate.npHoverHighlight then
        if ps.mouseover == true and plate.npHoverEnabled then
            plate.npHoverHighlight:SetAlpha(plate.npHoverAlpha or 0.3)
        else
            plate.npHoverHighlight:SetAlpha(0)
        end
    end
    if plate.npExecuteOverlay then
        if ps.execute == true and colors.executeEnabled == true then
            plate.npExecuteOverlay:SetAlpha(PREVIEW_EXECUTE_ALPHA)
        else
            plate.npExecuteOverlay:SetAlpha(0)
        end
    end
    if plate.npHitboxVis then plate.npHitboxVis:Hide() end

    if np.Power and np.Power.RenderPreview then
        np.Power.RenderPreview(plate)
    end

    PaintFakeAuras(plate, settings)
end

local function EffScale(frame)
    local scale = frame and frame.GetEffectiveScale and frame:GetEffectiveScale()
    if type(scale) ~= "number" or scale <= 0 then return 1 end
    return scale
end

local function IncludeBounds(region, bounds)
    if not region or type(region.GetTop) ~= "function" then return end
    if region.IsShown and not region:IsShown() then return end
    if region.GetAlpha and (region:GetAlpha() or 1) <= 0.01 then return end
    local top, bottom = region:GetTop(), region:GetBottom()
    if not top or not bottom then return end
    local eff = EffScale(region)
    top, bottom = top * eff, bottom * eff
    bounds.top = bounds.top and math.max(bounds.top, top) or top
    bounds.bottom = bounds.bottom and math.min(bounds.bottom, bottom) or bottom

    local left = region.GetLeft and region:GetLeft()
    local right = region.GetRight and region:GetRight()
    if not left or not right then return end
    left, right = left * eff, right * eff
    bounds.left = bounds.left and math.min(bounds.left, left) or left
    bounds.right = bounds.right and math.max(bounds.right, right) or right
end

local function IncludeTreeBounds(frame, bounds)
    if not frame then return end
    if frame.IsShown and not frame:IsShown() then return end
    if frame.GetAlpha and (frame:GetAlpha() or 1) <= 0.01 then return end

    if frame.GetRegions then
        local regions = { frame:GetRegions() }
        for i = 1, #regions do
            IncludeBounds(regions[i], bounds)
        end
    end
    if frame.GetChildren then
        local children = { frame:GetChildren() }
        for i = 1, #children do
            IncludeTreeBounds(children[i], bounds)
        end
    end
end

local function MeasureAndPlace()
    local host, plate = state.host, state.plate
    if not host or not plate then return false end
    if type(host.GetTop) ~= "function" or type(host.GetLeft) ~= "function" then return false end

    local bounds = {}
    IncludeTreeBounds(plate, bounds)
    if not (bounds.top and bounds.bottom and bounds.left and bounds.right) then return false end

    local hostEff = EffScale(host)
    local plateEff = EffScale(plate)

    local contentW = (bounds.right - bounds.left) / hostEff
    local contentH = (bounds.top - bounds.bottom) / hostEff
    if contentW <= 0 or contentH <= 0 then return false end

    local hostLeft, hostTop = host:GetLeft(), host:GetTop()
    if hostLeft and hostTop then
        local dx = (hostLeft * hostEff - bounds.left) / plateEff
        local dy = (hostTop * hostEff - bounds.top) / plateEff
        if math.abs(dx) >= 0.5 or math.abs(dy) >= 0.5 then
            state.offsetX = (state.offsetX or PREVIEW_BASE_OFFSET_X) + dx
            state.offsetY = (state.offsetY or PREVIEW_BASE_OFFSET_Y) + dy
            local bound = state.byHost[host]
            if bound then
                bound.offsetX, bound.offsetY = state.offsetX, state.offsetY
            end
            plate:ClearAllPoints()
            plate:SetPoint("TOPLEFT", host, "TOPLEFT", state.offsetX, state.offsetY)
        end
    end

    state.extentW, state.extentH = contentW, contentH
    if state.observer then
        state.observer(contentW, contentH)
    end
    return true
end

local function RequestMeasure(attempt)
    local host = state.host
    if not host or host._npPreviewMeasurePending then return end
    host._npPreviewMeasurePending = true

    local function Apply()
        host._npPreviewMeasurePending = nil
        if state.host ~= host then return end
        if MeasureAndPlace() then return end
        local next = (attempt or 1) + 1
        if next <= PREVIEW_MEASURE_ATTEMPTS then
            RequestMeasure(next)
        end
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0, Apply)
    else
        Apply()
    end
end

local function BuildPreviewPlate(host)
    local np = NP()
    if not (np and np.Health and np.Castbar) then return nil end

    local plate = CreateFrame("Frame", nil, host)
    plate:SetSize(1, 1)
    plate:SetPoint("TOPLEFT", host, "TOPLEFT", PREVIEW_BASE_OFFSET_X, PREVIEW_BASE_OFFSET_Y)

    local core = ns.Addon
    local pushed = core and core.PushPixelReference and core.PopPixelReference
    if pushed then core:PushPixelReference(nil) end

    np.Health.Build(plate)
    np.Castbar.Build(plate)
    if np.Extras and np.Extras.BuildPlate then
        np.Extras.BuildPlate(plate)
    end

    if pushed then core:PopPixelReference() end
    return plate
end

local function PushLivePixelReference()
    local core = ns.Addon
    if core and core.PushPixelReference and core.PopPixelReference then
        core:PushPixelReference(nil)
        return core
    end
    return nil
end

local function PopLivePixelReference(core)
    if core then core:PopPixelReference() end
end

local function Refresh()
    local host = state.host
    local plate = state.plate
    if not host or not plate or not host:IsShown() then return end
    local settings = GetSettings()
    local np = NP()
    if not settings or not np then return end
    StampPreviewType(plate, settings)
    local typeSettings = GetTypeSettings(plate) or {}

    local core = PushLivePixelReference()

    np.Health.ApplyAppearance(plate, typeSettings)
    np.Castbar.ApplyAppearance(plate, typeSettings)
    if np.Extras and np.Extras.ApplyAppearance then
        np.Extras.ApplyAppearance(plate, typeSettings)
    end
    plate.npLiftOverlay = false
    if np.Castbar.ApplyLift then
        np.Castbar.ApplyLift(plate)
    end

    PaintFakeData(plate, typeSettings)

    if np.Driver and np.Driver.ApplyRenderMode then
        np.Driver.ApplyRenderMode(plate, plate.npRenderMode)
    end

    PopLivePixelReference(core)
    RequestMeasure()
end

function PreviewDriver.SetSelectedType(key)
    if type(key) ~= "string" or not FAKE_STATE[key] then return false end
    if selectedType == key then return false end
    selectedType = key
    Refresh()
    return true
end

ns.QUI_NameplatesPreviewDriver = PreviewDriver

function ns.QUI_BuildNameplatePreview(host)
    if not host then return end
    if state.host ~= host or not state.plate then
        local bound = state.byHost[host]
        if not bound then
            local plate = BuildPreviewPlate(host)
            if plate then
                bound = {
                    plate = plate,
                    offsetX = PREVIEW_BASE_OFFSET_X,
                    offsetY = PREVIEW_BASE_OFFSET_Y,
                }
                state.byHost[host] = bound
            end
        end
        state.host = host
        state.plate = bound and bound.plate or nil
        state.offsetX = bound and bound.offsetX or PREVIEW_BASE_OFFSET_X
        state.offsetY = bound and bound.offsetY or PREVIEW_BASE_OFFSET_Y
    end
    Refresh()
end

function ns.QUI_RefreshNameplatePreview()
    Refresh()
end

function ns.QUI_GetNameplatePreviewExtent()
    return state.extentW, state.extentH
end

function ns.QUI_SetNameplatePreviewObserver(fn)
    state.observer = type(fn) == "function" and fn or nil
end

function ns.QUI_SetNameplatePreviewState(previewState)
    state.preview = type(previewState) == "table" and previewState or nil
end

function ns.QUI_GetNameplatePreviewStateDefaults()
    local copy = {}
    for k, v in pairs(PREVIEW_DEFAULT_STATE) do copy[k] = v end
    return copy
end
