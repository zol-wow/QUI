--[[
    QUI Options V2 — Unit Frames tile
    Shared surface wrapper for the schema-owned Unit Frames settings page:
      - preview block (unit dropdown + live preview) persists across inner tabs
      - inner tab strip switches schema-backed tab content without disturbing
        the preview
      - the General tab is cross-unit; all other tabs follow the selected unit
]]

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

---------------------------------------------------------------------------
-- Shared state — read/written from preview block callbacks and tab
-- strip callbacks on the same tile body.
---------------------------------------------------------------------------
local State = {
    selectedUnit = "player",
    activeTab    = "general",
    activeBody   = nil,
    repaintTabs  = nil,
}

local TabModel
local EnsureTabModel

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local UnitSelection = FullSurface and FullSurface.CreateSelectionController
    and FullSurface.CreateSelectionController(State, {
        stateKey = "selectedUnit",
        normalize = NormalizeUnitKey,
        afterSet = function()
            -- Reset the body preview cycle BEFORE refreshing the mock so
            -- the first frame after the unit change shows segment-1 of
            -- the new cycle, not the prior unit's mid-cycle state.
            if ns.QUI_UnitFramesBodyPreview
                and ns.QUI_UnitFramesBodyPreview.SetSelectedUnit then
                ns.QUI_UnitFramesBodyPreview.SetSelectedUnit(State.selectedUnit)
            end

            if _G.QUI_RefreshUnitFramePreview then
                _G.QUI_RefreshUnitFramePreview()
            end

            if State.invalidateTabBodies then
                State.invalidateTabBodies()
            end

            local activeTab = EnsureTabModel():GetActiveKey()
            local model = ResolveModel()
            local isPerUnitTab = model and model.IsPerUnitTab
            if type(isPerUnitTab) == "function"
                and isPerUnitTab(activeTab)
                and State.repaintTabs then
                State.repaintTabs()
            end
        end,
    })

local function SetSelectedUnit(key)
    UnitSelection:Set(key)
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

---------------------------------------------------------------------------
-- PREVIEW BLOCK — dropdown + preview area. Called via tile.config.preview.
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Live mock unit frame — scaled preview with health bar, power bar, and
-- text. Driven entirely from the selected
-- unit's DB settings; updates on SetSelectedUnit and on every settings
-- widget callback (RefreshNewUF_Module in unitframes.lua chains into
-- QUI_RefreshUnitFramePreview).
---------------------------------------------------------------------------
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

-- Same font + outline the runtime unit frames use — drives the preview's
-- name/health/power text so they match what the player will see in-game.
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

-- Resolve a text color given the master class-color override + custom fallback.
-- `masterOn` is the cross-unit "Color ALL X Text" toggle from General tab;
-- when true, text inherits class/react color for the previewed unit.
local function ResolveTextColor(unitKey, masterOn, custom)
    if masterOn then
        if unitKey == "player" or unitKey == "pet" then
            local r, g, b = GetPlayerClassColor()
            return r, g, b, 1
        end
        -- Non-player preview uses a hostile-red stand-in for class/react.
        return 0.9, 0.3, 0.3, 1
    end
    if custom and custom[1] then
        return custom[1], custom[2], custom[3], custom[4] or 1
    end
    return 1, 1, 1, 1
end

-- Map a 9-point anchor + offset to an (anchorPoint, offsetX, offsetY) relative
-- to a target frame. Used to position text inside the health-bar region.
local ANCHOR_MAP = {
    TOPLEFT     = "TOPLEFT",      TOP         = "TOP",         TOPRIGHT    = "TOPRIGHT",
    LEFT        = "LEFT",         CENTER      = "CENTER",      RIGHT       = "RIGHT",
    BOTTOMLEFT  = "BOTTOMLEFT",   BOTTOM      = "BOTTOM",      BOTTOMRIGHT = "BOTTOMRIGHT",
}

local function ApplyTextAnchor(fs, target, anchorKey, offsetX, offsetY, pad)
    local anchor = ANCHOR_MAP[anchorKey] or "LEFT"
    fs:ClearAllPoints()
    -- Inset from the frame edge by `pad` so corner-anchored text doesn't
    -- visually collide with the border.
    local edgeX = (anchor:find("LEFT") and pad) or (anchor:find("RIGHT") and -pad) or 0
    local edgeY = (anchor:find("TOP") and -pad) or (anchor:find("BOTTOM") and pad) or 0
    fs:SetPoint(anchor, target, anchor, (offsetX or 0) + edgeX, (offsetY or 0) + edgeY)
    if anchor:find("RIGHT") then fs:SetJustifyH("RIGHT")
    elseif anchor:find("LEFT") then fs:SetJustifyH("LEFT")
    else fs:SetJustifyH("CENTER") end
end

-- Resolve the player's class color with a caller-supplied fallback tuple.
-- Returns r, g, b (and any extra fallback components the caller passed).
-- (Assigns the forward-declared upvalue so GetPlayerClassColor can delegate.)
function GetPlayerClassColorOr(dr, dg, db, da)
    local _, class = UnitClass("player")
    local cc = ns.Helpers and ns.Helpers.GetClassColorTable(class)
    if cc then return cc.r, cc.g, cc.b, da end
    return dr, dg, db, da
end

-- Lay out 4 hairline strip textures (top/bottom/left/right) flush to a frame's
-- edges. `textures` is { top, bottom, left, right }. size == 0 hides them all.
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

-- Create the 4 hairline edge textures for a frame's border, returned as
-- { top, bottom, left, right } for ApplyHairlineBorder to lay out. Pass `color`
-- ({r,g,b,a}) to tint them at creation (the bar mocks use solid black); omit it
-- for borders recolored later (the portrait + aura icons).
local function CreateHairlineBorder(frame, color)
    local b = {}
    for i = 1, 4 do
        local t = frame:CreateTexture(nil, "OVERLAY")
        if color then t:SetColorTexture(color[1], color[2], color[3], color[4]) end
        b[i] = t
    end
    return b
end

-- Publish the preview helper set so sibling preview files (castbar preview,
-- which loads after this file in QUI_Options.toc) reuse one implementation
-- instead of maintaining byte-identical copies.
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

    -- Portrait frame (sibling — anchors to mock's LEFT or RIGHT edge).
    local portrait = CreateFrame("Frame", nil, host)
    portrait._bg = portrait:CreateTexture(nil, "BACKGROUND")
    portrait._bg:SetAllPoints(portrait)
    portrait._art = portrait:CreateTexture(nil, "ARTWORK")
    -- Stand-in for the unit's 3D portrait: use the player's portrait so the
    -- preview shows real art, not a placeholder. Set at refresh time so it
    -- stays current if the player changes zones / transforms.
    portrait._border = CreateHairlineBorder(portrait)
    portrait:Hide()
    mock._portrait = portrait

    -- Frame background (for the unfilled portion of the health bar + bg ring)
    mock._bg = mock:CreateTexture(nil, "BACKGROUND", nil, -2)
    mock._bg:SetAllPoints(mock)

    -- Border — 4 hairline textures (cheaper than SetBackdrop, no Blizzard recursion)
    mock._border = CreateHairlineBorder(mock, { 0, 0, 0, 1 })

    -- Health bar
    mock._healthBar = mock:CreateTexture(nil, "ARTWORK")

    -- Power bar (hidden when showPowerBar = false)
    mock._powerBar = mock:CreateTexture(nil, "ARTWORK")
    mock._powerBg  = mock:CreateTexture(nil, "BACKGROUND", nil, -1)

    -- Name text (top-left of the health bar)
    mock._nameText = mock:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mock._nameText:SetJustifyH("LEFT")

    -- Level text (independent position/font controls)
    mock._levelText = mock:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mock._levelText:SetJustifyH("RIGHT")

    -- Health text (right side of health bar)
    mock._healthText = mock:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mock._healthText:SetJustifyH("RIGHT")

    -- Power text (positioned per unitDB.powerTextAnchor)
    mock._powerText = mock:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mock._powerText:SetJustifyH("RIGHT")

    -- Target marker (skull icon by default — visible indicator of the setting)
    mock._targetMarker = mock:CreateTexture(nil, "OVERLAY")
    mock._targetMarker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
    mock._targetMarker:Hide()

    -- Stance / Form text (player only) with optional icon
    mock._stanceText = mock:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mock._stanceIcon = mock:CreateTexture(nil, "OVERLAY")
    mock._stanceIcon:SetTexture("Interface\\Icons\\Ability_Druid_CatForm")
    mock._stanceIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    mock._stanceText:Hide()
    mock._stanceIcon:Hide()

    -- Status indicators (rested + combat icons; player only)
    mock._restedIcon = mock:CreateTexture(nil, "OVERLAY")
    mock._restedIcon:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
    mock._restedIcon:SetTexCoord(0, 0.5, 0, 0.421875)
    mock._restedIcon:Hide()

    mock._combatIcon = mock:CreateTexture(nil, "OVERLAY")
    mock._combatIcon:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
    mock._combatIcon:SetTexCoord(0.5, 1.0, 0, 0.484375)
    mock._combatIcon:Hide()

    -- Leader / Assistant + Classification icons
    mock._leaderIcon = mock:CreateTexture(nil, "OVERLAY")
    mock._leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
    mock._leaderIcon:Hide()

    mock._classIcon = mock:CreateTexture(nil, "OVERLAY")
    mock._classIcon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Elite")
    mock._classIcon:Hide()

    -- Heal prediction overlay (green extension past the health fill)
    mock._healPred = mock:CreateTexture(nil, "ARTWORK", nil, 1)
    mock._healPred:Hide()

    -- Absorb overlay (teal stripe on top of the health bar)
    mock._absorb = mock:CreateTexture(nil, "ARTWORK", nil, 2)
    mock._absorb:Hide()

    -- Aura icon pools (debuff + buff, max 6 each for the mock). Each
    -- icon is a small frame with a bg + art texture. Pooled so RefreshMock
    -- just re-positions rather than re-creating on every setting tweak.
    local function CreateAuraIcon(iconTexPath)
        local icon = CreateFrame("Frame", nil, host)
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

    -- Castbar mock — sits in the bottom-region of the host, populated
    -- per the selected unit's castbar settings by RefreshMock.
    if ns.QUI_UnitFramesCastbarPreview and ns.QUI_UnitFramesCastbarPreview.Build then
        mock._castbarMock = ns.QUI_UnitFramesCastbarPreview.Build(host)
    end

    -- Body preview driver — owns the cycle ticker + pct-dependent writes
    -- (health/power bar widths, health/power text, heal-pred width,
    -- absorb width, aura stack + duration text).
    if ns.QUI_UnitFramesBodyPreview and ns.QUI_UnitFramesBodyPreview.Build then
        ns.QUI_UnitFramesBodyPreview.Build(mock)
    end

    return mock
end

local function ApplyBorder(mock, size)
    ApplyHairlineBorder(mock._border, mock, size)
end

local function RefreshMock()
    if not State.previewMock or not State.previewHost then return end
    local mock, host = State.previewMock, State.previewHost

    local db = QUI and QUI.db and QUI.db.profile
    local ufdb = db and db.quiUnitFrames
    local unitDB = ufdb and ufdb[State.selectedUnit]
    local general = db and db.general
    if not unitDB then mock:Hide(); return end
    mock:Show()

    local borderSize = math.max(0, unitDB.borderSize or 1)

    -- Scale to fit inside preview host (~20px horizontal margin; ~60px reserved
    -- at the bottom for the castbar mock). Portrait, when shown, adds to the
    -- effective width so the combined frame+portrait fits.
    local dbW, dbH = unitDB.width or 200, unitDB.height or 40
    local portraitOn = unitDB.showPortrait
        and (State.selectedUnit == "player" or State.selectedUnit == "target" or State.selectedUnit == "focus")
    local portraitSize = portraitOn and (unitDB.portraitSize or 40) or 0
    local portraitGap  = portraitOn and (unitDB.portraitGap or 0) or 0
    -- Portrait hugs the frame's top; frame total height uses the taller of
    -- the two. portraitSize is already a pixel value so it scales the same.
    local effectiveW = dbW + portraitSize + portraitGap
    local effectiveH = math.max(dbH, portraitSize)
    local hostW = math.max(host:GetWidth() - 40, 80)
    -- Cap effective height at host:GetHeight() - 100; that leaves the
    -- bottom region of the host (~60px on a 220px pane) reserved for
    -- the castbar mock.
    local hostH = math.max(host:GetHeight() - 100, 40)
    local scale = math.min(1, math.min(hostW / effectiveW, hostH / effectiveH))
    local w = math.floor(dbW * scale + 0.5)
    local h = math.floor(dbH * scale + 0.5)
    mock:SetSize(w, h)

    -- Recenter mock so the combined frame+portrait is visually centered.
    local shift = 0
    if portraitOn then
        local pEdge = (portraitSize + portraitGap) * scale * 0.5
        shift = (unitDB.portraitSide == "LEFT") and pEdge or -pEdge
    end
    mock:ClearAllPoints()
    mock:SetPoint("CENTER", host, "CENTER", shift, 30)

    -- Background + border
    local bgR, bgG, bgB, bgA = ResolveBgColor(general)
    mock._bg:SetColorTexture(bgR, bgG, bgB, bgA)
    ApplyBorder(mock, borderSize)

    -- Health bar sits inside the border
    local inner = borderSize
    local powerShown = unitDB.showPowerBar
    local powerH = powerShown and math.max(2, math.floor((unitDB.powerBarHeight or 4) * scale + 0.5)) or 0
    local healthH = h - (inner * 2) - (powerShown and (powerH + 1) or 0)
    if healthH < 4 then healthH = 4 end
    local healthTop = -inner
    mock._healthBar:ClearAllPoints()
    mock._healthBar:SetPoint("TOPLEFT", mock, "TOPLEFT", inner, healthTop)
    mock._healthBar:SetHeight(healthH)
    -- Width is set per-tick by the body preview driver (ApplyDynamics).
    local texPath = ResolveStatusBarTexture(unitDB.texture)
    mock._healthBar:SetTexture(texPath)
    local hR, hG, hB, hA = ResolveHealthColor(State.selectedUnit, unitDB, general)
    mock._healthBar:SetVertexColor(hR, hG, hB, 1)
    mock._healthBar:SetAlpha(hA or 1)

    -- Heal prediction: settings-driven color/texture/opacity + anchor setup.
    -- Width / Show / Hide are driven per-tick by the body preview driver.
    if unitDB.healPrediction and unitDB.healPrediction.enabled then
        local c = unitDB.healPrediction.color or { 0.2, 1, 0.2 }
        mock._healPred:SetTexture(texPath)
        mock._healPred:SetVertexColor(c[1], c[2], c[3], 1)
        mock._healPred:SetAlpha(unitDB.healPrediction.opacity or 0.5)
        mock._healPred:ClearAllPoints()
        mock._healPred:SetPoint("TOPLEFT", mock._healthBar, "TOPRIGHT", 0, 0)
        mock._healPred:SetPoint("BOTTOMLEFT", mock._healthBar, "BOTTOMRIGHT", 0, 0)
        -- Width and Show/Hide are set per-tick by the driver.
    else
        mock._healPred:Hide()
    end

    -- Absorb: settings-driven color/texture/opacity + anchor setup.
    -- Width / Show / Hide are driven per-tick by the body preview driver.
    if unitDB.absorbs and unitDB.absorbs.enabled then
        local absTex = ResolveStatusBarTexture(unitDB.absorbs.texture or unitDB.texture)
        local c = unitDB.absorbs.color or { 0.2, 0.8, 0.8 }
        mock._absorb:SetTexture(absTex)
        mock._absorb:SetVertexColor(c[1], c[2], c[3], 1)
        mock._absorb:SetAlpha(unitDB.absorbs.opacity or 0.7)
        mock._absorb:ClearAllPoints()
        mock._absorb:SetPoint("TOPRIGHT", mock._healthBar, "TOPRIGHT", 0, 0)
        mock._absorb:SetPoint("BOTTOMRIGHT", mock._healthBar, "BOTTOMRIGHT", 0, 0)
        -- Width and Show/Hide are set per-tick by the driver.
    else
        mock._absorb:Hide()
    end

    -- Target Marker. Respects: enabled, size, anchor (9-point), xOffset,
    -- yOffset. Mocks a skull icon so the user sees position/size feedback.
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

    -- Power bar (bottom)
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
        -- Width is set per-tick by the body preview driver (ApplyDynamics).
        mock._powerBar:SetTexture(ptex)
        mock._powerBar:SetVertexColor(pColor[1], pColor[2], pColor[3], 1)
    else
        mock._powerBg:Hide()
        mock._powerBar:Hide()
    end

    local fontPath, fontOutline = ResolveUnitFrameFont()

    -- Name text. Respects: showName, nameFontSize, nameTextColor,
    -- nameAnchor, nameOffsetX/Y, maxNameLength, and the cross-unit
    -- masterColorNameText override (General tab).
    if unitDB.showName ~= false then
        mock._nameText:Show()
        local nameFont = math.max(8, math.min(24, math.floor((unitDB.nameFontSize or 11) * scale + 0.5)))
        CJKFont(mock._nameText, fontPath, nameFont, fontOutline)

        local rawName
        if State.selectedUnit == "player" then
            rawName = UnitName("player") or ns.L["Player"]
        else
            rawName = MOCK_NAMES[State.selectedUnit] or State.selectedUnit
        end
        local maxLen = unitDB.maxNameLength or 0
        if maxLen > 0 and #rawName > maxLen then
            rawName = rawName:sub(1, maxLen)
        end

        -- Target-only inline ToT suffix (class-colored divider when toggled).
        if State.selectedUnit == "target" and unitDB.showInlineToT then
            local sep = unitDB.totSeparator or " >> "
            local totName = ns.L["TargetOfTarget"]
            local totMax = unitDB.totNameCharLimit or 0
            if totMax > 0 and #totName > totMax then
                totName = totName:sub(1, totMax)
            end
            rawName = rawName .. sep .. totName
        end
        mock._nameText:SetText(rawName)

        local masterOn = general and general.masterColorNameText
        local nr, ng, nb, na = ResolveTextColor(State.selectedUnit, masterOn, unitDB.nameTextColor)
        mock._nameText:SetTextColor(nr, ng, nb, na)

        -- Scale offsets with the mock so a -10 offset on a 400px real frame
        -- doesn't push the text off a 200px preview mock.
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

    -- Level text. Mirrors the runtime's opt-in level string without touching
    -- name truncation or inline target-of-target text.
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

    -- Health text. Respects: showHealth, healthDisplayStyle,
    -- hideHealthPercentSymbol, healthDivider, healthTextColor,
    -- healthFontSize, healthAnchor, healthOffsetX/Y, and the cross-unit
    -- masterColorHealthText override.
    if unitDB.showHealth ~= false then
        mock._healthText:Show()
        local hFont = math.max(8, math.min(24, math.floor((unitDB.healthFontSize or 11) * scale + 0.5)))
        CJKFont(mock._healthText, fontPath, hFont, fontOutline)
        -- Health text content is set per-tick by the body preview driver.

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

    -- Portrait. Respects: showPortrait, portraitSide, portraitSize,
    -- portraitBorderSize, portraitGap, portraitOffsetX/Y,
    -- portraitBorderUseClassColor, portraitBorderColor. Only applies to
    -- player/target/focus (per the settings builder's own gate).
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

        -- BG matches the frame's background for visual consistency.
        portrait._bg:SetColorTexture(bgR * 0.6, bgG * 0.6, bgB * 0.6, bgA)

        -- Art fills most of the portrait; border textures outline it.
        portrait._art:ClearAllPoints()
        portrait._art:SetPoint("TOPLEFT", portrait, "TOPLEFT", pBorder, -pBorder)
        portrait._art:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", -pBorder, pBorder)
        if SetPortraitTexture then
            SetPortraitTexture(portrait._art, "player")
        end

        -- Border color
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

    -- Auras (debuffs + buffs). Respects: showDebuffs, showBuffs, icon sizes,
    -- anchor (4-corner), grow (L/R/U/D), max icons, X/Y offsets, stack +
    -- duration text + color per kind. Max 6 icons shown in the mock.
    local auraDB = unitDB.auras or {}
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

        for i = 1, 6 do
            local icon = pool[i]
            if i <= count then
                icon:Show()
                icon:SetSize(sz, sz)
                icon:ClearAllPoints()
                icon:SetPoint(anchor, mock, anchor, ox + dx * (i - 1), oy + dy * (i - 1))
                icon._art:ClearAllPoints()
                icon._art:SetPoint("TOPLEFT", 1, -1)
                icon._art:SetPoint("BOTTOMRIGHT", -1, 1)
                -- 1px border around each icon
                for bi = 1, 4 do icon._border[bi]:SetColorTexture(0, 0, 0, 1) end
                ApplyHairlineBorder(icon._border, icon, 1)

                -- Stack text
                if showStack then
                    icon._stack:Show()
                    CJKFont(icon._stack, fontPath, math.max(8, math.floor((stackSize or 10) * scale + 0.5)), fontOutline)
                    -- Stack text content is set per-tick by the body preview driver.
                    local sc = stackColor or { 1, 1, 1, 1 }
                    icon._stack:SetTextColor(sc[1], sc[2], sc[3], sc[4] or 1)
                    icon._stack:ClearAllPoints()
                    icon._stack:SetPoint(ANCHOR_MAP[stackAnchor or "BOTTOMRIGHT"] or "BOTTOMRIGHT", icon, ANCHOR_MAP[stackAnchor or "BOTTOMRIGHT"] or "BOTTOMRIGHT", (stackOffX or -1) * scale, (stackOffY or 1) * scale)
                else
                    icon._stack:Hide()
                end

                -- Duration text
                if showDur then
                    icon._dur:Show()
                    CJKFont(icon._dur, fontPath, math.max(8, math.floor((durSize or 12) * scale + 0.5)), fontOutline)
                    -- Duration text content is set per-tick by the body preview driver.
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

    LayoutAuraKind(
        mock._debuffIcons, auraDB.showDebuffs,
        auraDB.debuffAnchor, auraDB.debuffGrow,
        auraDB.iconSize, auraDB.debuffMaxIcons,
        auraDB.debuffOffsetX, auraDB.debuffOffsetY,
        auraDB.debuffShowStack, auraDB.debuffStackSize, auraDB.debuffStackColor,
        auraDB.debuffStackAnchor, auraDB.debuffStackOffsetX, auraDB.debuffStackOffsetY,
        auraDB.debuffShowDuration, auraDB.debuffDurationSize, auraDB.debuffDurationColor,
        auraDB.debuffDurationAnchor, auraDB.debuffDurationOffsetX, auraDB.debuffDurationOffsetY,
        auraDB.debuffSpacing
    )
    LayoutAuraKind(
        mock._buffIcons, auraDB.showBuffs,
        auraDB.buffAnchor, auraDB.buffGrow,
        auraDB.buffIconSize, auraDB.buffMaxIcons,
        auraDB.buffOffsetX, auraDB.buffOffsetY,
        auraDB.buffShowStack, auraDB.buffStackSize, auraDB.buffStackColor,
        auraDB.buffStackAnchor, auraDB.buffStackOffsetX, auraDB.buffStackOffsetY,
        auraDB.buffShowDuration, auraDB.buffDurationSize, auraDB.buffDurationColor,
        auraDB.buffDurationAnchor, auraDB.buffDurationOffsetX, auraDB.buffDurationOffsetY,
        auraDB.buffSpacing
    )

    -- Power text. Respects: showPowerText, powerTextFormat,
    -- hidePowerPercentSymbol, powerTextUsePowerColor, powerTextColor,
    -- powerTextFontSize, powerTextAnchor, powerTextOffsetX/Y, and the
    -- masterColorPowerText override.
    if unitDB.showPowerText and powerShown then
        mock._powerText:Show()
        local ptFont = math.max(8, math.min(24, math.floor((unitDB.powerTextFontSize or 10) * scale + 0.5)))
        CJKFont(mock._powerText, fontPath, ptFont, fontOutline)
        -- Power text content is set per-tick by the body preview driver.

        local usePowerColor = unitDB.powerTextUsePowerColor
        local masterOn = general and general.masterColorPowerText
        local pr, pg, pb, pa
        if usePowerColor then
            -- Power-type color (stand-in: blue for mana, overridden below
            -- for power-having units once preview adds power type awareness)
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

    -- Indicator-shaped icon helper: enabled/size/anchor/offset.
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

    -- Stance / Form text (player only) — both text and optional icon.
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

    -- Status indicators (player only).
    if State.selectedUnit == "player" then
        ApplyIndicator(mock._restedIcon, unitDB.indicators and unitDB.indicators.rested, "TOPLEFT", "offsetX", "offsetY")
        ApplyIndicator(mock._combatIcon, unitDB.indicators and unitDB.indicators.combat, "TOPLEFT", "offsetX", "offsetY")
    else
        mock._restedIcon:Hide()
        mock._combatIcon:Hide()
    end

    -- Leader / Assistant (player/target/focus).
    if State.selectedUnit == "player" or State.selectedUnit == "target" or State.selectedUnit == "focus" then
        ApplyIndicator(mock._leaderIcon, unitDB.leaderIcon, "TOPLEFT", "xOffset", "yOffset")
    else
        mock._leaderIcon:Hide()
    end

    -- Classification (target/focus/boss).
    if State.selectedUnit == "target" or State.selectedUnit == "focus" or State.selectedUnit == "boss" then
        ApplyIndicator(mock._classIcon, unitDB.classificationIcon, "LEFT", "xOffset", "yOffset")
    else
        mock._classIcon:Hide()
    end

    -- Castbar mock — re-applies all castbar settings to the bottom-region mock.
    if mock._castbarMock and ns.QUI_UnitFramesCastbarPreview and ns.QUI_UnitFramesCastbarPreview.Refresh then
        ns.QUI_UnitFramesCastbarPreview.Refresh(mock._castbarMock, State.selectedUnit, unitDB, general)

        -- Anchor the castbar mock below the body mock at the same width, so
        -- the preview shows the in-game spatial relationship. Overrides
        -- the castbar driver's host-bottom anchor and host-derived width.
        if unitDB.castbar and unitDB.castbar.enabled then
            mock._castbarMock:ClearAllPoints()
            mock._castbarMock:SetPoint("TOP", mock, "BOTTOM", 0, -8 * scale)
            mock._castbarMock:SetWidth(w)
            mock._castbarMock._barInnerW = w
        end
    end

    -- Body preview driver — caches unitDB / general, syncs per-aura
    -- state for the now-visible icon set, and paints the first frame
    -- with the current cycle pcts so the bars don't snap to a stale
    -- value between RefreshMock and the next OnUpdate tick.
    if ns.QUI_UnitFramesBodyPreview and ns.QUI_UnitFramesBodyPreview.Refresh then
        ns.QUI_UnitFramesBodyPreview.Refresh(unitDB, general)
    end
end

-- Expose globally so settings widget callbacks in options/tabs/frames/
-- unitframes.lua can trigger a refresh without a direct module reference.
_G.QUI_RefreshUnitFramePreview = function()
    RefreshMock()
end

local function BuildPreviewBlock(pv)
    local model = ResolveModel()
    local getUnitOptions = model and model.GetUnitOptions

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
        onDropdownChanged = function(value)
            SetSelectedUnit(value)
        end,
        onBuildPreviewHost = function(previewHost)
            State.previewHost = previewHost
            State.previewMock = BuildMockFrame(previewHost)

            -- Re-render when the host changes size (panel resize) so the scale math re-runs.
            previewHost:SetScript("OnSizeChanged", function() RefreshMock() end)
            RefreshMock()
        end,
    })
end

---------------------------------------------------------------------------
-- TAB STRIP — style matches cooldown_manager.lua (11pt labels, 2px
-- accent underline on active tab, 1px divider below the whole strip).
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- TILE BODY — inner tab strip + scroll-wrapped content host.
---------------------------------------------------------------------------
local function BuildTileBody(body, _, _, feature)
    local tabModel = EnsureTabModel(feature)
    return FullSurface.BuildScrollTabBody(body, {
        cacheTabBodies = true,
        state = State,
        clearFrame = ClearFrame,
        createTabStrip = BuildTabStrip,
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
        height = 220,
        build = BuildPreviewBlock,
    },
    GetSearchRoot = GetSearchRoot,
    NavigateSearchEntry = NavigateSearchEntry,
    SetActiveTab = SetActiveTab,
    SetSelectedUnit = SetSelectedUnit,
    RenderPage = BuildTileBody,
}
