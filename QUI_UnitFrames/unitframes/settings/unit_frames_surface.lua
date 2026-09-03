local _, ns = ...
local QUI = QUI
local GUI = QUI.GUI

local function CJKFont(fs, p, s, f)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fs, p, s, f)
    else
        fs:SetFont(p, s, f)
    end
end
local Settings = ns.Settings
local FullSurface = Settings and Settings.FullSurface
local ClearFrame = FullSurface and FullSurface.ClearFrame

local function TruncateName(name, maxLength)
    local UF = ns.QUI_UnitFrames
    if UF and UF.TruncateName then return UF.TruncateName(name, maxLength) end
    return name
end

local AURA_ANCHOR_FRAMEPOINT = {
    TOPLEFT     = { "BOTTOMLEFT",  "TOPLEFT",     1 },
    TOPRIGHT    = { "BOTTOMRIGHT", "TOPRIGHT",   -1 },
    BOTTOMLEFT  = { "TOPLEFT",     "BOTTOMLEFT",  1 },
    BOTTOMRIGHT = { "TOPRIGHT",    "BOTTOMRIGHT", -1 },
}

local function ResolveModel(feature)
    local model = feature and feature.model or nil
    if type(model) == "function" then
        model = model()
    end
    if type(model) == "table" then
        return model
    end
    return ns.QUI_UnitFramesSettingsModel
end

local function NormalizeUnitKey(unitKey)
    local model = ResolveModel()
    local normalize = model and model.NormalizeUnitKey
    if type(normalize) == "function" then
        return normalize(unitKey)
    end
    return unitKey
end

local State = {
    selectedUnit = "player",
    activeTab    = "general",
    activeBody   = nil,
    repaintTabs  = nil,
}

local TabModel
local EnsureTabModel

local function IsPerUnitTab(tabKey)
    local model = ResolveModel()
    local isPerUnitTab = model and model.IsPerUnitTab
    return type(isPerUnitTab) == "function" and isPerUnitTab(tabKey) == true
end

local function ResolveTabVariant(tabKey)
    if not IsPerUnitTab(tabKey) then return nil end
    return State.selectedUnit
end

local UnitSelection = FullSurface and FullSurface.CreateSelectionController
    and FullSurface.CreateSelectionController(State, {
        stateKey = "selectedUnit",
        normalize = NormalizeUnitKey,
        afterSet = function()
            if ns.QUI_UnitFramesBodyPreview
                and ns.QUI_UnitFramesBodyPreview.SetSelectedUnit then
                ns.QUI_UnitFramesBodyPreview.SetSelectedUnit(State.selectedUnit)
            end

            if _G.QUI_RefreshUnitFramePreview then
                _G.QUI_RefreshUnitFramePreview()
            end

            if IsPerUnitTab(EnsureTabModel():GetActiveKey()) and State.repaintTabs then
                State.repaintTabs(false)
            end
        end,
    })

local function SetSelectedUnit(key)
    UnitSelection:Set(key)
end

local function GetSelectedUnit()
    return State.selectedUnit
end

local function SetActiveTab(tabKey)
    if type(tabKey) ~= "string" or tabKey == "" then
        return false
    end

    local tabModel = EnsureTabModel()
    if not tabModel or type(tabModel.SetActiveKey) ~= "function" then
        return false
    end

    if type(tabModel.GetTabs) == "function" then
        local found = false
        for _, tab in ipairs(tabModel:GetTabs() or {}) do
            if type(tab) == "table" and tab.key == tabKey then
                found = true
                break
            end
        end
        if not found then
            return false
        end
    end

    local activeKey = type(tabModel.GetActiveKey) == "function" and tabModel:GetActiveKey() or nil
    if activeKey == tabKey then
        return true
    end

    tabModel:SetActiveKey(tabKey)
    if State.repaintTabs then
        State.repaintTabs()
    end
    return true
end

local function NavigateSearchEntry(entry)
    if type(entry) ~= "table" then
        return false
    end

    local handled = false
    if type(entry.surfaceUnitKey) == "string" and entry.surfaceUnitKey ~= "" then
        SetSelectedUnit(entry.surfaceUnitKey)
        handled = true
    end
    if SetActiveTab(entry.surfaceTabKey) then
        handled = true
    end

    return handled
end

local function GetSearchRoot()
    return State.activeBody
end

local MOCK_NAMES = {
    player       = ns.L["Player"],
    target       = ns.L["Boss Target"],
    focus        = ns.L["Raid Focus"],
    targettarget = ns.L["Focus Target"],
    pet          = ns.L["Voidwalker"],
    boss         = ns.L["Boss 1"],
}

local function GetLSM()
    return (ns and ns.LSM) or (LibStub and LibStub("LibSharedMedia-3.0", true)) or nil
end

local function ResolveUnitFrameFont()
    local H = ns and ns.Helpers
    local path    = (H and H.GetGeneralFont and H.GetGeneralFont()) or "Fonts\\FRIZQT__.TTF"
    local outline = (H and H.GetGeneralFontOutline and H.GetGeneralFontOutline()) or ""
    return path, outline
end

local function ResolveElementFont(fontName, fallbackPath)
    local LSM = GetLSM()
    if LSM and LSM.Fetch and type(fontName) == "string" and fontName ~= "" then
        local path = LSM:Fetch("font", fontName, true)
        if path then return path end
    end
    return fallbackPath
end

local function ResolveStatusBarTexture(name)
    local LSM = GetLSM()
    if LSM and LSM.Fetch and name then
        local path = LSM:Fetch("statusbar", name, true)
        if path then return path end
    end
    return "Interface\\Buttons\\WHITE8x8"
end

local GetPlayerClassColorOr

local function GetPlayerClassColor()
    local r, g, b = GetPlayerClassColorOr(0.2, 0.8, 0.2)
    return r, g, b
end

local function ResolveHealthColor(unitKey, unitDB, general)
    if general and general.darkMode then
        local c = general.darkModeHealthColor or { 0.1, 0.1, 0.1 }
        return c[1], c[2], c[3], (general.darkModeHealthOpacity or 1)
    end
    local opacity = (general and general.defaultHealthOpacity) or 1
    if unitDB.useClassColor then
        if unitKey == "player" or unitKey == "pet" then
            local r, g, b = GetPlayerClassColor()
            return r, g, b, opacity
        end
    end
    if unitDB.useHostilityColor and general and general.hostilityColorHostile then
        local c = general.hostilityColorHostile
        return c[1], c[2], c[3], opacity
    end
    local custom = unitDB.customHealthColor or (general and general.defaultHealthColor) or { 0.2, 0.8, 0.2 }
    return custom[1], custom[2], custom[3], opacity
end

local function ResolveBgColor(general)
    if general and general.darkMode then
        local c = general.darkModeBgColor or { 0.05, 0.05, 0.05 }
        return c[1], c[2], c[3], (general.darkModeBgOpacity or 0.9)
    end
    local c = (general and general.defaultBgColor) or { 0, 0, 0 }
    return c[1], c[2], c[3], (general and general.defaultBgOpacity) or 0.75
end

local function ResolveTextColor(unitKey, masterOn, custom)
    if masterOn then
        if unitKey == "player" or unitKey == "pet" then
            local r, g, b = GetPlayerClassColor()
            return r, g, b, 1
        end
        return 0.9, 0.3, 0.3, 1
    end
    if custom and custom[1] then
        return custom[1], custom[2], custom[3], custom[4] or 1
    end
    return 1, 1, 1, 1
end

local ANCHOR_MAP = {
    TOPLEFT     = "TOPLEFT",      TOP         = "TOP",         TOPRIGHT    = "TOPRIGHT",
    LEFT        = "LEFT",         CENTER      = "CENTER",      RIGHT       = "RIGHT",
    BOTTOMLEFT  = "BOTTOMLEFT",   BOTTOM      = "BOTTOM",      BOTTOMRIGHT = "BOTTOMRIGHT",
}

local function ApplyTextAnchor(fs, target, anchorKey, offsetX, offsetY, pad)
    local anchor = ANCHOR_MAP[anchorKey] or "LEFT"
    fs:ClearAllPoints()
    local edgeX = (anchor:find("LEFT") and pad) or (anchor:find("RIGHT") and -pad) or 0
    local edgeY = (anchor:find("TOP") and -pad) or (anchor:find("BOTTOM") and pad) or 0
    fs:SetPoint(anchor, target, anchor, (offsetX or 0) + edgeX, (offsetY or 0) + edgeY)
    if anchor:find("RIGHT") then fs:SetJustifyH("RIGHT")
    elseif anchor:find("LEFT") then fs:SetJustifyH("LEFT")
    else fs:SetJustifyH("CENTER") end
end

function GetPlayerClassColorOr(dr, dg, db, da)
    local _, class = UnitClass("player")
    local cc = ns.Helpers and ns.Helpers.GetClassColorTable(class)
    if cc then return cc.r, cc.g, cc.b, da end
    return dr, dg, db, da
end

local function ApplyHairlineBorder(textures, frame, size)
    size = math.max(0, size or 0)
    if size == 0 then
        for i = 1, 4 do textures[i]:Hide() end
        return
    end
    for i = 1, 4 do textures[i]:Show() end
    local b = textures
    b[1]:ClearAllPoints(); b[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0); b[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0); b[1]:SetHeight(size)
    b[2]:ClearAllPoints(); b[2]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0); b[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0); b[2]:SetHeight(size)
    b[3]:ClearAllPoints(); b[3]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0); b[3]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0); b[3]:SetWidth(size)
    b[4]:ClearAllPoints(); b[4]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0); b[4]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0); b[4]:SetWidth(size)
end

local function CreateHairlineBorder(frame, color)
    local b = {}
    for i = 1, 4 do
        local t = frame:CreateTexture(nil, "OVERLAY")
        if color then t:SetColorTexture(color[1], color[2], color[3], color[4]) end
        b[i] = t
    end
    return b
end

ns.QUI_UnitFramesPreviewShared = ns.QUI_UnitFramesPreviewShared or {}
ns.QUI_UnitFramesPreviewShared.ANCHOR_MAP = ANCHOR_MAP
ns.QUI_UnitFramesPreviewShared.GetLSM = GetLSM
ns.QUI_UnitFramesPreviewShared.ResolveStatusBarTexture = ResolveStatusBarTexture
ns.QUI_UnitFramesPreviewShared.ResolveUnitFrameFont = ResolveUnitFrameFont
ns.QUI_UnitFramesPreviewShared.ApplyTextAnchor = ApplyTextAnchor
ns.QUI_UnitFramesPreviewShared.GetPlayerClassColorOr = GetPlayerClassColorOr
ns.QUI_UnitFramesPreviewShared.ApplyHairlineBorder = ApplyHairlineBorder
ns.QUI_UnitFramesPreviewShared.CreateHairlineBorder = CreateHairlineBorder

local function BuildMockFrame(host)
    local mock = CreateFrame("Frame", nil, host)
    mock:SetPoint("CENTER", host, "CENTER", 0, 0)

    local portrait = CreateFrame("Frame", nil, host)
    portrait._bg = portrait:CreateTexture(nil, "BACKGROUND")
    portrait._bg:SetAllPoints(portrait)
    portrait._art = portrait:CreateTexture(nil, "ARTWORK")
    portrait._border = CreateHairlineBorder(portrait)
    portrait:Hide()
    mock._portrait = portrait

    mock._bg = mock:CreateTexture(nil, "BACKGROUND", nil, -2)
    mock._bg:SetAllPoints(mock)

    mock._border = CreateHairlineBorder(mock, { 0, 0, 0, 1 })

    mock._healthBar = mock:CreateTexture(nil, "ARTWORK")

    mock._powerBar = mock:CreateTexture(nil, "ARTWORK")
    mock._powerBg  = mock:CreateTexture(nil, "BACKGROUND", nil, -1)

    mock._nameText = mock:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mock._nameText:SetJustifyH("LEFT")

    mock._levelText = mock:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mock._levelText:SetJustifyH("RIGHT")

    mock._healthText = mock:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mock._healthText:SetJustifyH("RIGHT")

    mock._powerText = mock:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mock._powerText:SetJustifyH("RIGHT")

    mock._targetMarker = mock:CreateTexture(nil, "OVERLAY")
    mock._targetMarker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
    mock._targetMarker:Hide()

    mock._stanceText = mock:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mock._stanceIcon = mock:CreateTexture(nil, "OVERLAY")
    mock._stanceIcon:SetTexture("Interface\\Icons\\Ability_Druid_CatForm")
    mock._stanceIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    mock._stanceText:Hide()
    mock._stanceIcon:Hide()

    mock._restedIcon = mock:CreateTexture(nil, "OVERLAY")
    mock._restedIcon:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
    mock._restedIcon:SetTexCoord(0, 0.5, 0, 0.421875)
    mock._restedIcon:Hide()

    mock._combatIcon = mock:CreateTexture(nil, "OVERLAY")
    mock._combatIcon:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
    mock._combatIcon:SetTexCoord(0.5, 1.0, 0, 0.484375)
    mock._combatIcon:Hide()

    mock._leaderIcon = mock:CreateTexture(nil, "OVERLAY")
    mock._leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
    mock._leaderIcon:Hide()

    mock._classIcon = mock:CreateTexture(nil, "OVERLAY")
    mock._classIcon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Elite")
    mock._classIcon:Hide()

    mock._healPred = mock:CreateTexture(nil, "ARTWORK", nil, 1)
    mock._healPred:Hide()

    mock._absorb = mock:CreateTexture(nil, "ARTWORK", nil, 2)
    mock._absorb:Hide()

    local function CreateAuraIcon(iconTexPath)
        local icon = CreateFrame("Frame", nil, mock)
        icon:SetFrameLevel(mock:GetFrameLevel() + 10)
        icon._art = icon:CreateTexture(nil, "ARTWORK")
        icon._art:SetTexture(iconTexPath)
        icon._art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon._border = CreateHairlineBorder(icon)
        icon._stack = icon:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        icon._dur   = icon:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        icon:Hide()
        return icon
    end

    mock._debuffIcons = {}
    mock._buffIcons   = {}
    local DEBUFF_TEX = {
        "Interface\\Icons\\Spell_Fire_FireBolt02",
        "Interface\\Icons\\Spell_Shadow_ShadowBolt",
        "Interface\\Icons\\Ability_Creature_Disease_02",
        "Interface\\Icons\\Ability_Rogue_DeadlyBrew",
        "Interface\\Icons\\Spell_Nature_Web",
        "Interface\\Icons\\Spell_Shadow_GatherShadows",
    }
    local BUFF_TEX = {
        "Interface\\Icons\\Spell_Holy_PowerWordShield",
        "Interface\\Icons\\Spell_Holy_GreaterBlessingofKings",
        "Interface\\Icons\\Spell_Holy_PrayerofSpirit",
        "Interface\\Icons\\Spell_Nature_Regenerate",
        "Interface\\Icons\\Spell_Arcane_MindMastery",
        "Interface\\Icons\\Spell_Magic_MageArmor",
    }
    for i = 1, 6 do
        mock._debuffIcons[i] = CreateAuraIcon(DEBUFF_TEX[i])
        mock._buffIcons[i]   = CreateAuraIcon(BUFF_TEX[i])
    end

    if ns.QUI_UnitFramesCastbarPreview and ns.QUI_UnitFramesCastbarPreview.Build then
        mock._castbarMock = ns.QUI_UnitFramesCastbarPreview.Build(host)
    end

    if ns.QUI_UnitFramesBodyPreview and ns.QUI_UnitFramesBodyPreview.Build then
        ns.QUI_UnitFramesBodyPreview.Build(mock)
    end

    return mock
end

local function ApplyBorder(mock, size)
    ApplyHairlineBorder(mock._border, mock, size)
end

local function IncludePreviewBounds(object, bounds)
    if not object or (object.IsShown and not object:IsShown()) then return end

    local top = object.GetTop and object:GetTop()
    local bottom = object.GetBottom and object:GetBottom()
    if top and bottom then
        bounds.top = bounds.top and math.max(bounds.top, top) or top
        bounds.bottom = bounds.bottom and math.min(bounds.bottom, bottom) or bottom
    end
end

local function IncludeFrameTreeBounds(frame, bounds)
    if not frame or (frame.IsShown and not frame:IsShown()) then return end

    IncludePreviewBounds(frame, bounds)

    if frame.GetRegions then
        local regions = { frame:GetRegions() }
        for i = 1, #regions do
            IncludePreviewBounds(regions[i], bounds)
        end
    end

    if frame.GetChildren then
        local children = { frame:GetChildren() }
        for i = 1, #children do
            IncludeFrameTreeBounds(children[i], bounds)
        end
    end
end

local function MeasurePreviewContentHeight(mock)
    local bounds = {}
    IncludeFrameTreeBounds(mock, bounds)
    IncludeFrameTreeBounds(mock and mock._portrait, bounds)
    if mock and not mock._previewBodyOnly then
        IncludeFrameTreeBounds(mock._castbarMock, bounds)
    end
    if not bounds.top or not bounds.bottom then return nil, nil end
    return math.max(0, bounds.top - bounds.bottom), bounds
end

local function ResizePreviewToContent(mock)
    local outer = mock and mock._previewOuter
    local host = mock and mock:GetParent()
    if not outer or not host then return end

    local contentHeight, bounds = MeasurePreviewContentHeight(mock)
    if not contentHeight or contentHeight <= 0 then return end

    local hostTop = host.GetTop and host:GetTop()
    local hostBottom = host.GetBottom and host:GetBottom()
    if hostTop and hostBottom then
        local hostCenter = (hostTop + hostBottom) * 0.5
        local contentCenter = (bounds.top + bounds.bottom) * 0.5
        local centerDelta = hostCenter - contentCenter
        if math.abs(centerDelta) >= 0.5 then
            mock._previewYOffset = (mock._previewYOffset or 0) + centerDelta
            mock:ClearAllPoints()
            mock:SetPoint(
                "CENTER",
                host,
                "CENTER",
                mock._previewXOffset or 0,
                mock._previewYOffset
            )
        end
    end

    local desiredHeight = math.floor(contentHeight + (mock._previewChromeHeight or 20) + 0.5)
    desiredHeight = math.max(mock._previewMinHeight or 60, desiredHeight)
    if mock._previewMaxHeight then
        desiredHeight = math.min(mock._previewMaxHeight, desiredHeight)
    end

    local currentHeight = outer.GetHeight and outer:GetHeight() or 0
    if math.abs(currentHeight - desiredHeight) >= 1 then
        mock._previewAutoHeightApplying = true
        outer:SetHeight(desiredHeight)
        mock._previewAutoHeightApplying = nil
    end
end

local function RequestPreviewAutoHeight(mock)
    if not mock or not mock._previewAutoHeight or mock._previewAutoHeightPending then return end
    mock._previewAutoHeightPending = true

    local function Apply()
        mock._previewAutoHeightPending = nil
        if State.previewMock ~= mock then return end
        ResizePreviewToContent(mock)
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0, Apply)
    else
        Apply()
    end
end

local function RefreshMock()
    if _G.QUI_SEARCH_HARVEST then return end
    if not State.previewMock or not State.previewHost then return end
    local mock, host = State.previewMock, State.previewHost

    local db = QUI and QUI.db and QUI.db.profile
    local ufdb = db and db.quiUnitFrames
    local unitDB = ufdb and ufdb[State.selectedUnit]
    local general = db and db.general
    if not unitDB then mock:Hide(); return end
    mock:Show()

    local borderSize = math.max(0, unitDB.borderSize or 1)

    local dbW, dbH = unitDB.width or 200, unitDB.height or 40
    local portraitOn = unitDB.showPortrait
        and (State.selectedUnit == "player" or State.selectedUnit == "target" or State.selectedUnit == "focus")
    local portraitSize = portraitOn and (unitDB.portraitSize or 40) or 0
    local portraitGap  = portraitOn and (unitDB.portraitGap or 0) or 0
    local effectiveW = dbW + portraitSize + portraitGap
    local effectiveH = math.max(dbH, portraitSize)
    local hostW = math.max(host:GetWidth() - 40, 80)
    local bodyOnly = mock._previewBodyOnly == true
    local scaleBudgetHeight = mock._previewScaleBudgetHeight or (bodyOnly and 140 or 180)
    local chromeHeight = mock._previewChromeHeight or (bodyOnly and 20 or 56)
    local hostH = math.max(scaleBudgetHeight - chromeHeight, 40)
    local scale = math.min(1, math.min(hostW / effectiveW, hostH / effectiveH))
    local w = math.floor(dbW * scale + 0.5)
    local h = math.floor(dbH * scale + 0.5)
    mock:SetSize(w, h)

    local shift = 0
    if portraitOn then
        local pEdge = (portraitSize + portraitGap) * scale * 0.5
        shift = (unitDB.portraitSide == "LEFT") and pEdge or -pEdge
    end
    mock:ClearAllPoints()
    mock._previewXOffset = shift
    if mock._previewYOffset == nil then
        mock._previewYOffset = bodyOnly and 0 or 22
    end
    mock:SetPoint("CENTER", host, "CENTER", shift, mock._previewYOffset)

    local bgR, bgG, bgB, bgA = ResolveBgColor(general)
    mock._bg:SetColorTexture(bgR, bgG, bgB, bgA)
    ApplyBorder(mock, borderSize)

    local inner = borderSize
    local powerShown = unitDB.showPowerBar
    local powerH = powerShown and math.max(2, math.floor((unitDB.powerBarHeight or 4) * scale + 0.5)) or 0
    local healthH = h - (inner * 2) - (powerShown and (powerH + 1) or 0)
    if healthH < 4 then healthH = 4 end
    local healthTop = -inner
    mock._healthBar:ClearAllPoints()
    mock._healthBar:SetPoint("TOPLEFT", mock, "TOPLEFT", inner, healthTop)
    mock._healthBar:SetHeight(healthH)
    local texPath = ResolveStatusBarTexture(unitDB.texture)
    mock._healthBar:SetTexture(texPath)
    local hR, hG, hB, hA = ResolveHealthColor(State.selectedUnit, unitDB, general)
    mock._healthBar:SetVertexColor(hR, hG, hB, 1)
    mock._healthBar:SetAlpha(hA or 1)

    if unitDB.healPrediction and unitDB.healPrediction.enabled then
        local c = unitDB.healPrediction.color or { 0.2, 1, 0.2 }
        mock._healPred:SetTexture(texPath)
        mock._healPred:SetVertexColor(c[1], c[2], c[3], 1)
        mock._healPred:SetAlpha(unitDB.healPrediction.opacity or 0.5)
        mock._healPred:ClearAllPoints()
        mock._healPred:SetPoint("TOPLEFT", mock._healthBar, "TOPRIGHT", 0, 0)
        mock._healPred:SetPoint("BOTTOMLEFT", mock._healthBar, "BOTTOMRIGHT", 0, 0)
    else
        mock._healPred:Hide()
    end

    if unitDB.absorbs and unitDB.absorbs.enabled then
        local absTex = ResolveStatusBarTexture(unitDB.absorbs.texture or unitDB.texture)
        local c = unitDB.absorbs.color or { 0.2, 0.8, 0.8 }
        mock._absorb:SetTexture(absTex)
        mock._absorb:SetVertexColor(c[1], c[2], c[3], 1)
        mock._absorb:SetAlpha(unitDB.absorbs.opacity or 0.7)
        mock._absorb:ClearAllPoints()
        mock._absorb:SetPoint("TOPRIGHT", mock._healthBar, "TOPRIGHT", 0, 0)
        mock._absorb:SetPoint("BOTTOMRIGHT", mock._healthBar, "BOTTOMRIGHT", 0, 0)
    else
        mock._absorb:Hide()
    end

    if unitDB.targetMarker and unitDB.targetMarker.enabled then
        mock._targetMarker:Show()
        local tmSize = math.floor((unitDB.targetMarker.size or 20) * scale + 0.5)
        mock._targetMarker:SetSize(tmSize, tmSize)
        local anchor = ANCHOR_MAP[unitDB.targetMarker.anchor or "TOP"] or "TOP"
        mock._targetMarker:ClearAllPoints()
        mock._targetMarker:SetPoint(anchor, mock, anchor,
            (unitDB.targetMarker.xOffset or 0) * scale,
            (unitDB.targetMarker.yOffset or 0) * scale)
    else
        mock._targetMarker:Hide()
    end

    if powerShown then
        mock._powerBg:Show()
        mock._powerBar:Show()
        local pColor = unitDB.powerBarColor or { 0.2, 0.4, 0.9 }
        local ptex = ResolveStatusBarTexture(unitDB.texture)
        mock._powerBg:ClearAllPoints()
        mock._powerBg:SetPoint("BOTTOMLEFT", mock, "BOTTOMLEFT", inner, inner)
        mock._powerBg:SetPoint("BOTTOMRIGHT", mock, "BOTTOMRIGHT", -inner, inner)
        mock._powerBg:SetHeight(powerH)
        mock._powerBg:SetColorTexture(bgR * 0.8, bgG * 0.8, bgB * 0.8, bgA)
        mock._powerBar:ClearAllPoints()
        mock._powerBar:SetPoint("BOTTOMLEFT", mock, "BOTTOMLEFT", inner, inner)
        mock._powerBar:SetHeight(powerH)
        mock._powerBar:SetTexture(ptex)
        mock._powerBar:SetVertexColor(pColor[1], pColor[2], pColor[3], 1)
    else
        mock._powerBg:Hide()
        mock._powerBar:Hide()
    end

    local fontPath, fontOutline = ResolveUnitFrameFont()

    if unitDB.showName ~= false then
        mock._nameText:Show()
        local nameFont = math.max(8, math.min(24, math.floor((unitDB.nameFontSize or 11) * scale + 0.5)))
        CJKFont(mock._nameText, fontPath, nameFont, fontOutline)

        local rawName
        if State.selectedUnit == "player" then
            rawName = ns.Helpers.SafeValue(UnitName("player")) or ns.L["Player"]
        else
            rawName = MOCK_NAMES[State.selectedUnit] or State.selectedUnit
        end
        local maxLen = unitDB.maxNameLength or 0
        if maxLen > 0 then
            rawName = TruncateName(rawName, maxLen)
        end

        if (State.selectedUnit == "target" or State.selectedUnit == "boss") and unitDB.showInlineToT then
            local sep = unitDB.totSeparator or " >> "
            local totName = ns.L["TargetOfTarget"]
            local totMax = unitDB.totNameCharLimit or 0
            if totMax > 0 then
                totName = TruncateName(totName, totMax)
            end
            rawName = rawName .. sep .. totName
        end
        mock._nameText:SetText(rawName)

        local masterOn = general and general.masterColorNameText
        local nr, ng, nb, na = ResolveTextColor(State.selectedUnit, masterOn, unitDB.nameTextColor)
        mock._nameText:SetTextColor(nr, ng, nb, na)

        ApplyTextAnchor(
            mock._nameText, mock,
            unitDB.nameAnchor or "TOPLEFT",
            (unitDB.nameOffsetX or 0) * scale,
            (unitDB.nameOffsetY or 0) * scale,
            inner + 4
        )
    else
        mock._nameText:Hide()
    end

    if unitDB.showLevel == true then
        mock._levelText:Show()
        local levelFont = math.max(8, math.min(24, math.floor((unitDB.levelFontSize or unitDB.nameFontSize or 11) * scale + 0.5)))
        CJKFont(mock._levelText, ResolveElementFont(unitDB.levelFont, fontPath), levelFont, fontOutline)

        local levels = {
            player = "80",
            target = "82",
            focus = "81",
            targettarget = "80",
            pet = "80",
            boss = "??",
        }
        mock._levelText:SetText(levels[State.selectedUnit] or "80")

        local lr, lg, lb, la = ResolveTextColor(State.selectedUnit, false, unitDB.levelTextColor)
        mock._levelText:SetTextColor(lr, lg, lb, la)
        ApplyTextAnchor(
            mock._levelText, mock,
            unitDB.levelAnchor or "RIGHT",
            (unitDB.levelOffsetX or -4) * scale,
            (unitDB.levelOffsetY or 0) * scale,
            inner + 4
        )
    else
        mock._levelText:Hide()
    end

    if unitDB.showHealth ~= false then
        mock._healthText:Show()
        local hFont = math.max(8, math.min(24, math.floor((unitDB.healthFontSize or 11) * scale + 0.5)))
        CJKFont(mock._healthText, fontPath, hFont, fontOutline)

        local masterOn = general and general.masterColorHealthText
        local hr, hg, hb, ha = ResolveTextColor(State.selectedUnit, masterOn, unitDB.healthTextColor)
        mock._healthText:SetTextColor(hr, hg, hb, ha)

        ApplyTextAnchor(
            mock._healthText, mock,
            unitDB.healthAnchor or "TOPRIGHT",
            (unitDB.healthOffsetX or 0) * scale,
            (unitDB.healthOffsetY or 0) * scale,
            inner + 4
        )
    else
        mock._healthText:Hide()
    end

    local portrait = mock._portrait
    if portraitOn then
        portrait:Show()
        local pSize     = math.floor(portraitSize * scale + 0.5)
        local pBorder   = math.max(0, unitDB.portraitBorderSize or 1)
        portrait:SetSize(pSize, pSize)
        portrait:ClearAllPoints()
        local pgap = portraitGap * scale
        local poxScaled = (unitDB.portraitOffsetX or 0) * scale
        local poyScaled = (unitDB.portraitOffsetY or 0) * scale
        if unitDB.portraitSide == "LEFT" then
            portrait:SetPoint("TOPRIGHT", mock, "TOPLEFT", -pgap + poxScaled, poyScaled)
        else
            portrait:SetPoint("TOPLEFT", mock, "TOPRIGHT", pgap + poxScaled, poyScaled)
        end

        portrait._bg:SetColorTexture(bgR * 0.6, bgG * 0.6, bgB * 0.6, bgA)

        portrait._art:ClearAllPoints()
        portrait._art:SetPoint("TOPLEFT", portrait, "TOPLEFT", pBorder, -pBorder)
        portrait._art:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", -pBorder, pBorder)
        if SetPortraitTexture then
            SetPortraitTexture(portrait._art, "player")
        end

        local pbR, pbG, pbB = 0, 0, 0
        if unitDB.portraitBorderUseClassColor then
            pbR, pbG, pbB = GetPlayerClassColor()
        elseif unitDB.portraitBorderColor then
            local c = unitDB.portraitBorderColor
            pbR, pbG, pbB = c[1], c[2], c[3]
        end
        local pb = portrait._border
        if pBorder ~= 0 then
            for i = 1, 4 do pb[i]:SetColorTexture(pbR, pbG, pbB, 1) end
        end
        ApplyHairlineBorder(pb, portrait, pBorder)
    else
        portrait:Hide()
    end

    local auraDB = unitDB.auras or {}
    local function FirstEnabledFilterStrip(auras, auraType)
        local elements = type(auras) == "table" and type(auras.elements) == "table" and auras.elements["*"]
        if type(elements) ~= "table" then return nil end
        for _, e in ipairs(elements) do
            if type(e) == "table" and e.mode == "filterStrip" and e.enabled ~= false and e.auraType == auraType then
                return e
            end
        end
        return nil
    end
    local function LayoutAuraKind(pool, enabled, anchorKey, growKey, iconSize, maxIcons, offXRaw, offYRaw, showStack, stackSize, stackColor, stackAnchor, stackOffX, stackOffY, showDur, durSize, durColor, durAnchor, durOffX, durOffY, spacing)
        if not enabled then
            for _, icon in ipairs(pool) do icon:Hide() end
            return
        end
        local count = math.min(maxIcons or 6, 6)
        local sz = math.max(8, math.floor((iconSize or 22) * scale + 0.5))
        local sp = math.floor((spacing or 2) * scale + 0.5)
        local step = sz + sp
        local anchor = anchorKey or "TOPLEFT"
        local grow = growKey or "RIGHT"
        local ox = (offXRaw or 0) * scale
        local oy = (offYRaw or 0) * scale

        local dx, dy
        if grow == "LEFT" then dx, dy = -step, 0
        elseif grow == "UP" then dx, dy = 0, step
        elseif grow == "DOWN" then dx, dy = 0, -step
        else dx, dy = step, 0 end

        local map = AURA_ANCHOR_FRAMEPOINT[anchor] or AURA_ANCHOR_FRAMEPOINT.TOPLEFT
        local iconPoint, framePoint, bx = map[1], map[2], map[3]

        for i = 1, 6 do
            local icon = pool[i]
            if i <= count then
                icon:Show()
                icon:SetSize(sz, sz)
                icon:ClearAllPoints()
                icon:SetPoint(iconPoint, mock, framePoint, ox + bx + dx * (i - 1), oy + dy * (i - 1))
                icon._art:ClearAllPoints()
                icon._art:SetPoint("TOPLEFT", 1, -1)
                icon._art:SetPoint("BOTTOMRIGHT", -1, 1)
                for bi = 1, 4 do icon._border[bi]:SetColorTexture(0, 0, 0, 1) end
                ApplyHairlineBorder(icon._border, icon, 1)

                if showStack then
                    icon._stack:Show()
                    CJKFont(icon._stack, fontPath, math.max(8, math.floor((stackSize or 10) * scale + 0.5)), fontOutline)
                    local sc = stackColor or { 1, 1, 1, 1 }
                    icon._stack:SetTextColor(sc[1], sc[2], sc[3], sc[4] or 1)
                    icon._stack:ClearAllPoints()
                    icon._stack:SetPoint(ANCHOR_MAP[stackAnchor or "BOTTOMRIGHT"] or "BOTTOMRIGHT", icon, ANCHOR_MAP[stackAnchor or "BOTTOMRIGHT"] or "BOTTOMRIGHT", (stackOffX or -1) * scale, (stackOffY or 1) * scale)
                else
                    icon._stack:Hide()
                end

                if showDur then
                    icon._dur:Show()
                    CJKFont(icon._dur, fontPath, math.max(8, math.floor((durSize or 12) * scale + 0.5)), fontOutline)
                    local dc = durColor or { 1, 1, 1, 1 }
                    icon._dur:SetTextColor(dc[1], dc[2], dc[3], dc[4] or 1)
                    icon._dur:ClearAllPoints()
                    icon._dur:SetPoint(ANCHOR_MAP[durAnchor or "CENTER"] or "CENTER", icon, ANCHOR_MAP[durAnchor or "CENTER"] or "CENTER", (durOffX or 0) * scale, (durOffY or 0) * scale)
                else
                    icon._dur:Hide()
                end
            else
                icon:Hide()
            end
        end
    end

    local debuffStrip = FirstEnabledFilterStrip(auraDB, "HARMFUL")
    LayoutAuraKind(
        mock._debuffIcons, debuffStrip ~= nil,
        debuffStrip and debuffStrip.anchor, debuffStrip and debuffStrip.growDirection,
        debuffStrip and debuffStrip.iconSize, debuffStrip and debuffStrip.maxIcons,
        debuffStrip and debuffStrip.offsetX, debuffStrip and debuffStrip.offsetY,
        debuffStrip and debuffStrip.stack.show, debuffStrip and debuffStrip.stack.fontSize, debuffStrip and debuffStrip.stack.color,
        debuffStrip and debuffStrip.stack.anchor, debuffStrip and debuffStrip.stack.offsetX, debuffStrip and debuffStrip.stack.offsetY,
        debuffStrip and debuffStrip.duration.show, debuffStrip and debuffStrip.duration.fontSize, debuffStrip and debuffStrip.duration.color,
        debuffStrip and debuffStrip.duration.anchor, debuffStrip and debuffStrip.duration.offsetX, debuffStrip and debuffStrip.duration.offsetY,
        debuffStrip and debuffStrip.spacing
    )
    local buffStrip = FirstEnabledFilterStrip(auraDB, "HELPFUL")
    LayoutAuraKind(
        mock._buffIcons, buffStrip ~= nil,
        buffStrip and buffStrip.anchor, buffStrip and buffStrip.growDirection,
        buffStrip and buffStrip.iconSize, buffStrip and buffStrip.maxIcons,
        buffStrip and buffStrip.offsetX, buffStrip and buffStrip.offsetY,
        buffStrip and buffStrip.stack.show, buffStrip and buffStrip.stack.fontSize, buffStrip and buffStrip.stack.color,
        buffStrip and buffStrip.stack.anchor, buffStrip and buffStrip.stack.offsetX, buffStrip and buffStrip.stack.offsetY,
        buffStrip and buffStrip.duration.show, buffStrip and buffStrip.duration.fontSize, buffStrip and buffStrip.duration.color,
        buffStrip and buffStrip.duration.anchor, buffStrip and buffStrip.duration.offsetX, buffStrip and buffStrip.duration.offsetY,
        buffStrip and buffStrip.spacing
    )

    if unitDB.showPowerText and powerShown then
        mock._powerText:Show()
        local ptFont = math.max(8, math.min(24, math.floor((unitDB.powerTextFontSize or 10) * scale + 0.5)))
        CJKFont(mock._powerText, fontPath, ptFont, fontOutline)

        local usePowerColor = unitDB.powerTextUsePowerColor
        local masterOn = general and general.masterColorPowerText
        local pr, pg, pb, pa
        if usePowerColor then
            pr, pg, pb, pa = 0.2, 0.4, 0.95, 1
        else
            pr, pg, pb, pa = ResolveTextColor(State.selectedUnit, masterOn, unitDB.powerTextColor)
        end
        mock._powerText:SetTextColor(pr, pg, pb, pa)

        ApplyTextAnchor(
            mock._powerText, mock,
            unitDB.powerTextAnchor or "BOTTOMRIGHT",
            (unitDB.powerTextOffsetX or 0) * scale,
            (unitDB.powerTextOffsetY or 0) * scale,
            inner + 4
        )
    else
        mock._powerText:Hide()
    end

    local function ApplyIndicator(tex, indicatorDB, defaultAnchor, xKey, yKey)
        if not (indicatorDB and indicatorDB.enabled) then tex:Hide(); return end
        tex:Show()
        local sz = math.max(6, math.floor((indicatorDB.size or 16) * scale + 0.5))
        tex:SetSize(sz, sz)
        local anchor = ANCHOR_MAP[indicatorDB.anchor or defaultAnchor] or defaultAnchor
        tex:ClearAllPoints()
        tex:SetPoint(anchor, mock, anchor,
            (indicatorDB[xKey] or 0) * scale,
            (indicatorDB[yKey] or 0) * scale)
    end

    local stanceDB = (State.selectedUnit == "player") and unitDB.indicators and unitDB.indicators.stance or nil
    if stanceDB and stanceDB.enabled then
        mock._stanceText:Show()
        local sFont = math.max(8, math.floor((stanceDB.fontSize or 12) * scale + 0.5))
        CJKFont(mock._stanceText, fontPath, sFont, fontOutline)
        mock._stanceText:SetText(ns.L["Bear Form"])
        if stanceDB.useClassColor then
            local r, g, b = GetPlayerClassColor()
            mock._stanceText:SetTextColor(r, g, b, 1)
        else
            local c = stanceDB.customColor or { 1, 1, 1, 1 }
            mock._stanceText:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        end
        local anc = ANCHOR_MAP[stanceDB.anchor or "BOTTOM"] or "BOTTOM"
        mock._stanceText:ClearAllPoints()
        mock._stanceText:SetPoint(anc, mock, anc,
            (stanceDB.offsetX or 0) * scale,
            (stanceDB.offsetY or -2) * scale)

        if stanceDB.showIcon then
            mock._stanceIcon:Show()
            local iconSz = math.max(6, math.floor((stanceDB.iconSize or 14) * scale + 0.5))
            mock._stanceIcon:SetSize(iconSz, iconSz)
            mock._stanceIcon:ClearAllPoints()
            mock._stanceIcon:SetPoint("RIGHT", mock._stanceText, "LEFT", (stanceDB.iconOffsetX or -2) * scale, 0)
        else
            mock._stanceIcon:Hide()
        end
    else
        mock._stanceText:Hide()
        mock._stanceIcon:Hide()
    end

    if State.selectedUnit == "player" then
        ApplyIndicator(mock._restedIcon, unitDB.indicators and unitDB.indicators.rested, "TOPLEFT", "offsetX", "offsetY")
        ApplyIndicator(mock._combatIcon, unitDB.indicators and unitDB.indicators.combat, "TOPLEFT", "offsetX", "offsetY")
    else
        mock._restedIcon:Hide()
        mock._combatIcon:Hide()
    end

    if State.selectedUnit == "player" or State.selectedUnit == "target" or State.selectedUnit == "focus" then
        ApplyIndicator(mock._leaderIcon, unitDB.leaderIcon, "TOPLEFT", "xOffset", "yOffset")
    else
        mock._leaderIcon:Hide()
    end

    if State.selectedUnit == "target" or State.selectedUnit == "focus" or State.selectedUnit == "boss" then
        ApplyIndicator(mock._classIcon, unitDB.classificationIcon, "LEFT", "xOffset", "yOffset")
    else
        mock._classIcon:Hide()
    end

    if bodyOnly and mock._castbarMock then
        mock._castbarMock:Hide()
    elseif mock._castbarMock and ns.QUI_UnitFramesCastbarPreview and ns.QUI_UnitFramesCastbarPreview.Refresh then
        ns.QUI_UnitFramesCastbarPreview.Refresh(mock._castbarMock, State.selectedUnit, unitDB, general)

        if unitDB.castbar and unitDB.castbar.enabled then
            mock._castbarMock:ClearAllPoints()
            mock._castbarMock:SetPoint("TOP", mock, "BOTTOM", 0, -8 * scale)
        end
    end

    if ns.QUI_UnitFramesBodyPreview and ns.QUI_UnitFramesBodyPreview.Refresh then
        ns.QUI_UnitFramesBodyPreview.Refresh(unitDB, general)
    end
    RequestPreviewAutoHeight(mock)
end

_G.QUI_RefreshUnitFramePreview = function()
    RefreshMock()
end

local function BuildPreviewBlock(pv, opts)
    local model = ResolveModel()
    local getUnitOptions = model and model.GetUnitOptions
    local bodyOnly = opts and opts.bodyOnly == true
    local showDropdown = not opts or opts.showDropdown ~= false
    local previewHostForBlock
    local previewMockForBlock

    State.selectedUnit = NormalizeUnitKey(State.selectedUnit)
    FullSurface.BuildDropdownPreviewBlock(pv, {
        gui = GUI,
        state = State,
        selectedValue = State.selectedUnit,
        dropdownStateKey = "_selectedUnit",
        dropdownLabel = ns.L["Unit"],
        dropdownOptions = type(getUnitOptions) == "function" and getUnitOptions() or {},
        dropdownMeta = {
            description = ns.L["Select which unit frame to configure. Settings in the tabs below apply to the chosen unit."],
        },
        showDropdown = showDropdown,
        onDropdownChanged = function(value)
            SetSelectedUnit(value)
        end,
        onBuildPreviewHost = function(previewHost)
            previewHostForBlock = previewHost
            State.previewHost = previewHost
            State.previewMock = BuildMockFrame(previewHost)
            previewMockForBlock = State.previewMock
            State.previewMock._previewOuter = pv
            State.previewMock._previewBodyOnly = bodyOnly
            State.previewMock._previewAutoHeight = not opts or opts.autoHeight ~= false
            State.previewMock._previewScaleBudgetHeight =
                (opts and opts.scaleBudgetHeight) or (bodyOnly and 140 or 180)
            State.previewMock._previewChromeHeight = showDropdown and 56 or 20
            State.previewMock._previewMinHeight =
                (opts and opts.minHeight) or (bodyOnly and 60 or 96)
            State.previewMock._previewMaxHeight = opts and opts.maxHeight

            previewHost:SetScript("OnSizeChanged", function()
                if State.previewMock == previewMockForBlock
                    and not previewMockForBlock._previewAutoHeightApplying then
                    RefreshMock()
                end
            end)
            RefreshMock()
        end,
    })

    if pv.HookScript then
        pv:HookScript("OnShow", function()
            if not previewHostForBlock or not previewMockForBlock then return end
            State.previewHost = previewHostForBlock
            State.previewMock = previewMockForBlock
            if ns.QUI_UnitFramesBodyPreview and ns.QUI_UnitFramesBodyPreview.Build then
                ns.QUI_UnitFramesBodyPreview.Build(previewMockForBlock)
            end
            RefreshMock()
        end)
    end
end

local function BuildTabStrip(parent)
    return FullSurface.CreateTabStrip(parent)
end

EnsureTabModel = function(feature)
    if TabModel then
        return TabModel
    end

    local model = ResolveModel(feature)
    local getTabDefinitions = model and model.GetTabDefinitions
    local tabDefinitions = type(getTabDefinitions) == "function" and getTabDefinitions() or {}

    TabModel = FullSurface and FullSurface.CreateTabModel
        and FullSurface.CreateTabModel(State, {
            stateKey = "activeTab",
            defaultKey = "general",
            tabs = tabDefinitions,
        })

    return TabModel
end

local function BuildTileBody(body, _, _, feature)
    local tabModel = EnsureTabModel(feature)
    return FullSurface.BuildScrollTabBody(body, {
        cacheTabBodies = true,
        state = State,
        clearFrame = ClearFrame,
        createTabStrip = BuildTabStrip,
        resolveVariantKey = ResolveTabVariant,
        initialize = function()
            State.activeTab = State.activeTab or "general"
        end,
        getTabs = function() return tabModel:GetTabs() end,
        getActiveTab = function() return tabModel:GetActiveKey() end,
        setActiveTab = function(tabKey)
            tabModel:SetActiveKey(tabKey)
        end,
        render = function(host, activeTab) return tabModel:RenderKey(host, activeTab) end,
    })
end

ns.QUI_UnitFramesSettingsSurface = {
    preview = {
        height = 180,
        build = BuildPreviewBlock,
    },
    GetSearchRoot = GetSearchRoot,
    NavigateSearchEntry = NavigateSearchEntry,
    SetActiveTab = SetActiveTab,
    SetSelectedUnit = SetSelectedUnit,
    GetSelectedUnit = GetSelectedUnit,
    RenderPage = BuildTileBody,
}
