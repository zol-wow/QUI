local ADDON_NAME, ns = ...

local Chrome = ns.QUI_GroupFrameChrome or {}
ns.QUI_GroupFrameChrome = Chrome

local DEFAULT_COLORS = Chrome.DEFAULT_COLORS or {
    darkHealth      = { 0.15, 0.15, 0.15, 1 },
    powerBar        = { 0.2, 0.4, 0.8, 1 },
    healAbsorb      = { 0.5, 0.1, 0.1, 1 },
    threat          = { 1, 0, 0, 0.8 },
    targetHighlight = { 1, 1, 1, 0.6 },
    dispelFallback  = { 0.2, 0.6, 1.0, 1 },
    darkModeBg      = { 0.25, 0.25, 0.25, 1 },
    frameBg         = { 0.1, 0.1, 0.1, 0.9 },
    healPrediction  = { 0.2, 1, 0.2, 1 },
}
Chrome.DEFAULT_COLORS = DEFAULT_COLORS

local LEVELS = Chrome.LEVELS or {
    THREAT       = 6,
    TARGET       = 7,
    DISPEL       = 8,
    TEXT         = 9,
    DISPEL_ICON  = 10,
    CLEANSE      = 11,
    AURA_HOST    = 12,
    AURA_BAR     = 13,
    TARGETED     = 14,
}
Chrome.LEVELS = LEVELS

local _fontPathCache, _texturePathCache = {}, {}

local function FontPath(general)
    local name = (general and general.font) or "Quazii"
    local cached = _fontPathCache[name]
    if cached then return cached end
    local LSM = ns.LSM
    local path = (LSM and LSM:Fetch("font", name)) or "Fonts\\FRIZQT__.TTF"
    _fontPathCache[name] = path
    return path
end

local function FontOutline(general)
    return (general and general.fontOutline) or "OUTLINE"
end

local function TexturePath(textureName, general)
    local name = textureName or (general and general.texture) or "Quazii v5"
    local cached = _texturePathCache[name]
    if cached then return cached end
    local LSM = ns.LSM
    local path = LSM and LSM:Fetch("statusbar", name, true)
    if not path and name:find("[/\\]") then
        path = name
    end
    path = path or "Interface\\Buttons\\WHITE8X8"
    _texturePathCache[name] = path
    return path
end

function Chrome.InvalidateAssetCache()
    for k in pairs(_fontPathCache) do _fontPathCache[k] = nil end
    for k in pairs(_texturePathCache) do _texturePathCache[k] = nil end
end

local _backdropCache = {}
local function GetCachedBackdrop(bgFile, edgeFile, edgeSize)
    local key = (bgFile or "") .. "|" .. (edgeFile or "") .. "|" .. (edgeSize or 0)
    local bd = _backdropCache[key]
    if not bd then
        bd = {
            bgFile = bgFile,
            edgeFile = edgeFile or nil,
            edgeSize = edgeSize and edgeSize > 0 and edgeSize or nil,
        }
        _backdropCache[key] = bd
    end
    return bd
end

local function EnsureBackdrop(frame, bd)
    if frame._quiBackdrop == bd then return end
    frame._quiBackdrop = bd
    frame:SetBackdrop(bd)
end

local function SetBackdropFillColor(frame, r, g, b, a)
    local center = frame and frame.Center
    if center then
        center:SetVertexColor(r, g, b, a)
    end
end

local function ApplyStatusBarTexture(statusBar, textureName, general)
    if not statusBar then return end

    statusBar:SetStatusBarTexture(TexturePath(textureName, general))

    local tex = statusBar:GetStatusBarTexture()
    if tex then
        tex:SetTexCoord(0, 1, 0, 1)
        if tex.SetHorizTile then tex:SetHorizTile(false) end
        if tex.SetVertTile then tex:SetVertTile(false) end
    end
end

-- >>> QUI_TEST_EXTRACT ApplyOverlayBar (sentinel used by
local function ApplyOverlayBar(bar, settings, healthBar, isVertical, opts)
    if not bar or not healthBar then return end
    settings = settings or {}
    opts = opts or {}

    ApplyStatusBarTexture(bar, settings.texture, opts.general)

    local order = tonumber(settings.drawOrder) or opts.drawOrderDefault or 1
    if order < 1 then order = 1 elseif order > 3 then order = 3 end
    bar:SetFrameLevel(healthBar:GetFrameLevel() + order + 1)
    bar:SetFrameStrata(healthBar:GetFrameStrata())

    local reverse = false
    local resolvedVertical = isVertical
    bar:ClearAllPoints()
    if settings.mode == "detached" then
        local frame = opts.frame or healthBar:GetParent()
        local w = settings.width or 60
        local h = settings.height or 8
        resolvedVertical = h > w
        bar:SetSize(w, h)
        local anchor = settings.anchor or "BOTTOM"
        bar:SetPoint(anchor, frame, anchor, settings.offsetX or 0, settings.offsetY or 0)
        if opts.fillOrigin then
            reverse = (settings.fillFrom or "reverse") ~= "default"
        else
            reverse = true
        end
        bar:SetReverseFill(reverse)
        bar:SetOrientation(resolvedVertical and "VERTICAL" or "HORIZONTAL")
    elseif opts.anchorToHealth then
        local healthTex = healthBar:GetStatusBarTexture()
        if isVertical then
            bar:SetPoint("BOTTOMLEFT", healthTex, "TOPLEFT", 0, 0)
            bar:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
            bar:SetOrientation("VERTICAL")
        else
            bar:SetPoint("TOPLEFT", healthTex, "TOPRIGHT", 0, 0)
            bar:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
            bar:SetOrientation("HORIZONTAL")
        end
    else
        bar:SetAllPoints(healthBar)
        if opts.fillOrigin then
            reverse = (settings.fillFrom or "reverse") ~= "default"
        else
            reverse = true
        end
        bar:SetReverseFill(reverse)
        bar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
    end

    if settings.spark then
        local spark = bar._quiSpark
        if not spark then
            spark = bar:CreateTexture(nil, "OVERLAY")
            spark:SetColorTexture(1, 1, 1, 1)
            bar._quiSpark = spark
        end
        local sc = settings.sparkColor
        spark:SetVertexColor(sc and sc[1] or 1, sc and sc[2] or 1, sc and sc[3] or 1, 1)
        local fillTex = bar:GetStatusBarTexture()
        spark:ClearAllPoints()
        if resolvedVertical then
            spark:SetPoint("LEFT", fillTex, "LEFT", 0, 0)
            spark:SetPoint("RIGHT", fillTex, "RIGHT", 0, 0)
            spark:SetHeight(1)
            local edge = reverse and "BOTTOM" or "TOP"
            spark:SetPoint(edge, fillTex, edge, 0, 0)
        else
            spark:SetPoint("TOP", fillTex, "TOP", 0, 0)
            spark:SetPoint("BOTTOM", fillTex, "BOTTOM", 0, 0)
            spark:SetWidth(1)
            local edge = reverse and "LEFT" or "RIGHT"
            spark:SetPoint(edge, fillTex, edge, 0, 0)
        end
        spark:Show()
    elseif bar._quiSpark then
        bar._quiSpark:Hide()
    end

    if settings.outline then
        local o = bar._quiOutline
        if not o then
            o = {
                top    = bar:CreateTexture(nil, "OVERLAY"),
                bottom = bar:CreateTexture(nil, "OVERLAY"),
                left   = bar:CreateTexture(nil, "OVERLAY"),
                right  = bar:CreateTexture(nil, "OVERLAY"),
            }
            bar._quiOutline = o
        end
        local oc = settings.outlineColor or { 0, 0, 0, 1 }
        local r, g, b, a = oc[1] or 0, oc[2] or 0, oc[3] or 0, oc[4] or 1
        o.top:ClearAllPoints(); o.top:SetColorTexture(r, g, b, a)
        o.top:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
        o.top:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0); o.top:SetHeight(1)
        o.bottom:ClearAllPoints(); o.bottom:SetColorTexture(r, g, b, a)
        o.bottom:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
        o.bottom:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0); o.bottom:SetHeight(1)
        o.left:ClearAllPoints(); o.left:SetColorTexture(r, g, b, a)
        o.left:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
        o.left:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0); o.left:SetWidth(1)
        o.right:ClearAllPoints(); o.right:SetColorTexture(r, g, b, a)
        o.right:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
        o.right:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0); o.right:SetWidth(1)
        o.top:Show(); o.bottom:Show(); o.left:Show(); o.right:Show()
    elseif bar._quiOutline then
        local o = bar._quiOutline
        o.top:Hide(); o.bottom:Hide(); o.left:Hide(); o.right:Hide()
    end
end
-- <<< QUI_TEST_EXTRACT ApplyOverlayBar

local ANCHOR_MAP = {
    LEFT       = { point = "LEFT",       leftPoint = "LEFT",       rightPoint = "CENTER",       justify = "LEFT",   justifyV = "MIDDLE" },
    RIGHT      = { point = "RIGHT",       leftPoint = "CENTER",     rightPoint = "RIGHT",        justify = "RIGHT",  justifyV = "MIDDLE" },
    CENTER     = { point = "CENTER",     leftPoint = "LEFT",       rightPoint = "RIGHT",        justify = "CENTER", justifyV = "MIDDLE" },
    TOPLEFT    = { point = "TOPLEFT",    leftPoint = "TOPLEFT",    rightPoint = "TOP",          justify = "LEFT",   justifyV = "TOP" },
    TOPRIGHT   = { point = "TOPRIGHT",   leftPoint = "TOP",        rightPoint = "TOPRIGHT",     justify = "RIGHT",  justifyV = "TOP" },
    TOP        = { point = "TOP",        leftPoint = "TOPLEFT",    rightPoint = "TOPRIGHT",     justify = "CENTER", justifyV = "TOP" },
    BOTTOMLEFT = { point = "BOTTOMLEFT", leftPoint = "BOTTOMLEFT", rightPoint = "BOTTOM",       justify = "LEFT",   justifyV = "BOTTOM" },
    BOTTOMRIGHT= { point = "BOTTOMRIGHT", leftPoint = "BOTTOM",     rightPoint = "BOTTOMRIGHT",  justify = "RIGHT",  justifyV = "BOTTOM" },
    BOTTOM     = { point = "BOTTOM",     leftPoint = "BOTTOMLEFT", rightPoint = "BOTTOMRIGHT",  justify = "CENTER", justifyV = "BOTTOM" },
}

ns.QUI_GroupFrameTextAnchorMap = ANCHOR_MAP

local function GetTextAnchorInfo(anchorName)
    return ANCHOR_MAP[anchorName] or ANCHOR_MAP.LEFT
end

local DIMENSION_DEFAULTS = {
    party  = { 200, 40, "partyWidth",      "partyHeight" },
    small  = { 180, 36, "smallRaidWidth",  "smallRaidHeight" },
    medium = { 160, 30, "mediumRaidWidth", "mediumRaidHeight" },
    large  = { 140, 24, "largeRaidWidth",  "largeRaidHeight" },
}

function Chrome.DimensionMode(count, contextMode)
    if contextMode == "party" then return "party" end
    count = tonumber(count) or 0
    if contextMode ~= "raid" and count <= 5 then return "party" end
    if count <= 15 then return "small" end
    if count <= 25 then return "medium" end
    return "large"
end

function Chrome.FrameDimensions(vdb, mode)
    local spec = DIMENSION_DEFAULTS[mode] or DIMENSION_DEFAULTS.party
    local dims = vdb and vdb.dimensions
    if not dims then return spec[1], spec[2] end
    return tonumber(dims[spec[3]]) or spec[1], tonumber(dims[spec[4]]) or spec[2]
end

local INDICATOR_ANCHORS = {
    { key = "roleIcon",       anchor = "roleIconAnchor",     x = "roleIconOffsetX",     y = "roleIconOffsetY",
      defAnchor = "TOPLEFT",    defX = 2,  defY = -2 },
    { key = "readyCheckIcon", anchor = "readyCheckAnchor",   x = "readyCheckOffsetX",   y = "readyCheckOffsetY",
      defAnchor = "CENTER",     defX = 0,  defY = 0 },
    { key = "resIcon",        anchor = "resurrectionAnchor", x = "resurrectionOffsetX", y = "resurrectionOffsetY",
      defAnchor = "CENTER",     defX = 0,  defY = 0 },
    { key = "summonIcon",     anchor = "summonAnchor",       x = "summonOffsetX",       y = "summonOffsetY",
      defAnchor = "CENTER",     defX = 16, defY = 0 },
    { key = "leaderIcon",     anchor = "leaderAnchor",       x = "leaderOffsetX",       y = "leaderOffsetY",
      defAnchor = "TOP",        defX = 0,  defY = 6 },
    { key = "targetMarker",   anchor = "targetMarkerAnchor", x = "targetMarkerOffsetX", y = "targetMarkerOffsetY",
      defAnchor = "TOPRIGHT",   defX = -2, defY = -2 },
    { key = "phaseIcon",      anchor = "phaseAnchor",        x = "phaseOffsetX",        y = "phaseOffsetY",
      defAnchor = "BOTTOMLEFT", defX = 2,  defY = 2 },
}

local function AnchorText(frame, region, anchorName, offX, offY, bottomPad)
    if not region or not region.ClearAllPoints or not region.SetPoint then return end
    local a = GetTextAnchorInfo(anchorName)
    local pad = a.point:find("BOTTOM") and bottomPad or 0
    local padX = math.abs(offX)
    region:ClearAllPoints()
    region:SetPoint(a.leftPoint, frame, a.leftPoint, padX, offY + pad)
    region:SetPoint(a.rightPoint, frame, a.rightPoint, -padX, offY + pad)
end

local function SetTextJustification(region, horizontal, vertical)
    if not region or not region.SetJustifyH or not region.SetJustifyV then return end
    local changed = region.GetJustifyH and region:GetJustifyH() ~= horizontal
    region:SetJustifyH(horizontal)
    region:SetJustifyV(vertical)
    if changed and region.GetText and region.SetText then
        local text = region:GetText()
        region:SetText("")
        region:SetText(text)
    end
end

local function AnchorBottomPadded(frame, vdb, bottomPad)
    if not frame then return end
    vdb = vdb or {}
    bottomPad = bottomPad or frame._bottomPad or 0

    local nameSettings = vdb.name
    local nameAnchor = GetTextAnchorInfo(nameSettings and nameSettings.nameAnchor or "LEFT")
    AnchorText(frame, frame.nameText, nameAnchor.point,
        nameSettings and nameSettings.nameOffsetX or 4,
        nameSettings and nameSettings.nameOffsetY or 0, bottomPad)
    SetTextJustification(frame.nameText,
        nameSettings and nameSettings.nameJustify or nameAnchor.justify, nameAnchor.justifyV)

    local levelAnchor = GetTextAnchorInfo(nameSettings and nameSettings.levelAnchor or "RIGHT")
    AnchorText(frame, frame.levelText, levelAnchor.point,
        nameSettings and nameSettings.levelOffsetX or -4,
        nameSettings and nameSettings.levelOffsetY or 0, bottomPad)
    SetTextJustification(frame.levelText,
        nameSettings and nameSettings.levelJustify or levelAnchor.justify, levelAnchor.justifyV)

    local healthSettings = vdb.health
    local healthAnchor = GetTextAnchorInfo(healthSettings and healthSettings.healthAnchor or "RIGHT")
    AnchorText(frame, frame.healthText, healthAnchor.point,
        healthSettings and healthSettings.healthOffsetX or -4,
        healthSettings and healthSettings.healthOffsetY or 0, bottomPad)
    SetTextJustification(frame.healthText,
        healthSettings and healthSettings.healthJustify or healthAnchor.justify, healthAnchor.justifyV)

    local indDB = vdb.indicators or {}
    for _, spec in ipairs(INDICATOR_ANCHORS) do
        local tex = frame[spec.key]
        if tex and tex.ClearAllPoints and tex.SetPoint then
            local anchor = indDB[spec.anchor] or spec.defAnchor
            local offX = indDB[spec.x] or spec.defX
            local offY = indDB[spec.y] or spec.defY
            if anchor:find("BOTTOM") then offY = offY + bottomPad end
            tex:ClearAllPoints()
            tex:SetPoint(anchor, frame, anchor, offX, offY)
        end
    end
end
Chrome.AnchorBottomPadded = AnchorBottomPadded

local DISPEL_ICON_TYPES = Chrome.DISPEL_ICON_TYPES or {
    "Magic", "Curse", "Disease", "Poison", "Bleed",
}
local DISPEL_ICON_ATLASES = Chrome.DISPEL_ICON_ATLASES or {
    Magic   = "RaidFrame-Icon-DebuffMagic",
    Curse   = "RaidFrame-Icon-DebuffCurse",
    Disease = "RaidFrame-Icon-DebuffDisease",
    Poison  = "RaidFrame-Icon-DebuffPoison",
    Bleed   = "RaidFrame-Icon-DebuffBleed",
}
Chrome.DISPEL_ICON_TYPES = DISPEL_ICON_TYPES
Chrome.DISPEL_ICON_ATLASES = DISPEL_ICON_ATLASES

function Chrome.HideDispelTypeIcons(frame)
    local icons = frame and frame.dispelTypeIcons
    if not icons then return end
    for _, typeName in ipairs(DISPEL_ICON_TYPES) do
        local icon = icons[typeName]
        if icon then icon:Hide() end
    end
end

function Chrome.ShowDispelTypeIcon(frame, typeName)
    local icons = frame and frame.dispelTypeIcons
    if not icons then return false end
    local selected = icons[typeName]
    for _, name in ipairs(DISPEL_ICON_TYPES) do
        local icon = icons[name]
        if icon then icon:Hide() end
    end
    if not selected then return false end
    local texture = selected:GetStatusBarTexture()
    if texture then texture:SetVertexColor(1, 1, 1, 1) end
    selected:Show()
    return true
end

function Chrome.ApplyDispelIconLayout(frame, settings)
    if not frame then return end
    if not settings or settings.showIcon ~= true then
        Chrome.HideDispelTypeIcons(frame)
        return
    end

    local icons = frame.dispelTypeIcons or {}
    frame.dispelTypeIcons = icons
    local size = tonumber(settings.iconSize) or 20
    local alpha = tonumber(settings.iconOpacity) or 1
    local anchor = settings.iconAnchor or "TOPRIGHT"
    local offsetX = tonumber(settings.iconOffsetX) or 0
    local offsetY = tonumber(settings.iconOffsetY) or 0

    for _, typeName in ipairs(DISPEL_ICON_TYPES) do
        local icon = icons[typeName]
        if not icon then
            icon = CreateFrame("StatusBar", nil, frame)
            icon:SetMinMaxValues(0, 1)
            icon:SetValue(1)
            icons[typeName] = icon
        end
        icon:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        local texture = icon:GetStatusBarTexture()
        if texture then
            texture:SetAtlas(DISPEL_ICON_ATLASES[typeName])
            texture:SetVertexColor(1, 1, 1, 1)
        end
        icon:ClearAllPoints()
        icon:SetPoint(anchor, frame, anchor, offsetX, offsetY)
        icon:SetSize(size, size)
        icon:SetAlpha(alpha)
        icon:SetFrameLevel(frame:GetFrameLevel() + LEVELS.DISPEL_ICON)
        icon:Hide()
    end
end

function Chrome.Apply(frame, vdb, state)
    if not frame then return end
    vdb = vdb or {}
    local general = vdb.general
    local QUICore = ns.Addon
    local Helpers = ns.Helpers
    local LSM = ns.LSM

        local borderPx = general and general.borderSize or 1
        local borderSize = borderPx > 0 and (QUICore.Pixels and QUICore:Pixels(borderPx, frame) or borderPx) or 0
        local px = QUICore.GetPixelSize and QUICore:GetPixelSize(frame) or 1

        EnsureBackdrop(frame, GetCachedBackdrop(
            "Interface\\Buttons\\WHITE8x8",
            borderSize > 0 and "Interface\\Buttons\\WHITE8x8" or nil,
            borderSize > 0 and borderSize or nil
        ))

        local bgColor, healthOpacity, bgOpacity
        if general and general.darkMode then
            bgColor = general.darkModeBgColor or DEFAULT_COLORS.darkModeBg
            healthOpacity = general.darkModeHealthOpacity or 1.0
            bgOpacity = general.darkModeBgOpacity or 1.0
        else
            bgColor = general and general.defaultBgColor or DEFAULT_COLORS.frameBg
            healthOpacity = general and general.defaultHealthOpacity or 1.0
            bgOpacity = general and general.defaultBgOpacity or 1.0
        end
        local bgAlpha = (bgColor[4] or 1) * bgOpacity
        frame._lastBackdropColorR = bgColor[1]
        frame._lastBackdropColorG = bgColor[2]
        frame._lastBackdropColorB = bgColor[3]
        frame._lastBackdropColorA = bgAlpha
        frame._lastBackdropReapplyTime = GetTime()
        SetBackdropFillColor(frame, bgColor[1], bgColor[2], bgColor[3], bgAlpha)
        if borderSize > 0 then
            local bdr, bdg, bdb, bda = 0, 0, 0, 1
            if Helpers and Helpers.GetSkinBorderColor then bdr, bdg, bdb, bda = Helpers.GetSkinBorderColor() end
            frame:SetBackdropBorderColor(bdr, bdg, bdb, bda)
        end

        local powerSettings = vdb.power
        local showPower = powerSettings and powerSettings.showPowerBar ~= false
        local powerHeight = showPower and (QUICore.PixelRound and QUICore:PixelRound(powerSettings.powerBarHeight or 4, frame) or 4) or 0
        local separatorHeight = showPower and px or 0

        local healthBar = frame.healthBar or CreateFrame("StatusBar", nil, frame)
        healthBar:ClearAllPoints()
        healthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", borderSize, -borderSize)
        healthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize + powerHeight + separatorHeight)
        ApplyStatusBarTexture(healthBar, nil, general)
        healthBar:SetMinMaxValues(0, 100)
        healthBar:SetValue(100)
        healthBar:EnableMouse(false)
        healthBar:SetAlpha(healthOpacity)
        local isVertical = (((vdb.health and vdb.health.healthFillDirection) or "HORIZONTAL") == "VERTICAL")
        healthBar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
        frame._isVerticalFill = isVertical
        frame.healthBar = healthBar

        if frame.healthBg then
            frame.healthBg:Hide()
            frame.healthBg = nil
        end

        local healPredictionBar = frame.healPredictionBar or CreateFrame("StatusBar", nil, healthBar)
        frame.healPredictionBar = healPredictionBar
        healPredictionBar:SetMinMaxValues(0, 1)
        healPredictionBar:SetValue(0)
        ApplyOverlayBar(healPredictionBar, vdb and vdb.healPrediction, healthBar, isVertical,
            { drawOrderDefault = 1, anchorToHealth = true, frame = frame, general = general })
        healPredictionBar:Hide()

        local absorbBar = frame.absorbBar or CreateFrame("StatusBar", nil, healthBar)
        frame.absorbBar = absorbBar
        absorbBar:SetMinMaxValues(0, 1)
        absorbBar:SetValue(0)
        ApplyOverlayBar(absorbBar, vdb and vdb.absorbs, healthBar, isVertical,
            { drawOrderDefault = 2, fillOrigin = true, frame = frame, general = general })
        absorbBar:Hide()

        local healAbsorbBar = frame.healAbsorbBar or CreateFrame("StatusBar", nil, healthBar)
        frame.healAbsorbBar = healAbsorbBar
        healAbsorbBar:SetMinMaxValues(0, 1)
        healAbsorbBar:SetValue(0)
        ApplyOverlayBar(healAbsorbBar, vdb and vdb.healAbsorbs, healthBar, isVertical,
            { drawOrderDefault = 3, fillOrigin = true, frame = frame, general = general })
        healAbsorbBar:Hide()

        if showPower then
            local powerBar = frame.powerBar or CreateFrame("StatusBar", nil, frame)
            powerBar:ClearAllPoints()
            powerBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", borderSize, borderSize)
            powerBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize)
            powerBar:SetHeight(powerHeight)
            ApplyStatusBarTexture(powerBar, nil, general)
            powerBar:SetMinMaxValues(0, 100)
            powerBar:SetValue(100)
            powerBar:EnableMouse(false)
            frame.powerBar = powerBar

            if not frame._powerBg then
                local powerBg = powerBar:CreateTexture(nil, "BACKGROUND")
                powerBg:SetAllPoints()
                powerBg:SetTexture("Interface\\Buttons\\WHITE8x8")
                powerBg:SetVertexColor(0.05, 0.05, 0.05, 0.9)
                frame._powerBg = powerBg
            end

            if not frame._powerSeparator then
                local separator = powerBar:CreateTexture(nil, "OVERLAY")
                separator:SetHeight(px)
                separator:SetPoint("BOTTOMLEFT", powerBar, "TOPLEFT", 0, 0)
                separator:SetPoint("BOTTOMRIGHT", powerBar, "TOPRIGHT", 0, 0)
                separator:SetTexture("Interface\\Buttons\\WHITE8x8")
                separator:SetVertexColor(0, 0, 0, 1)
                frame._powerSeparator = separator
            end
        end

        local textFrame = frame._textFrame or CreateFrame("Frame", nil, frame)
        textFrame:SetAllPoints()
        textFrame:SetFrameLevel(frame:GetFrameLevel() + LEVELS.TEXT)
        frame._textFrame = textFrame

        local statusText = frame.statusText or textFrame:CreateFontString(nil, "OVERLAY")
        statusText:ClearAllPoints()
        if Helpers and Helpers.ApplyFontWithFallback then
            Helpers.ApplyFontWithFallback(statusText, FontPath(general), 14, "OUTLINE")
        else
            statusText:SetFont(FontPath(general), 14, "OUTLINE")
        end
        statusText:SetPoint("CENTER", frame, "CENTER", 0, 0)
        statusText:SetJustifyH("CENTER")
        statusText:SetJustifyV("MIDDLE")
        statusText:SetTextColor(0.9, 0.9, 0.9, 1)
        statusText:Hide()
        frame.statusText = statusText

        local bottomPad = powerHeight + separatorHeight + borderSize
        frame._bottomPad = bottomPad

        local fontPath = FontPath(general)
        local fontOutline = FontOutline(general)
        local nameSettings = vdb.name
        local nameFontSize = nameSettings and nameSettings.nameFontSize or 12
        local nameText = frame.nameText or textFrame:CreateFontString(nil, "OVERLAY")
        Helpers.ApplyFontWithFallback(nameText, fontPath, nameFontSize, fontOutline)
        nameText:SetTextColor(1, 1, 1, 1)
        nameText:SetWordWrap(false)
        frame.nameText = nameText

        local levelText = frame.levelText or textFrame:CreateFontString(nil, "OVERLAY")
        local levelFontPath = fontPath
        if nameSettings and type(nameSettings.levelFont) == "string" and nameSettings.levelFont ~= "" then
            levelFontPath = LSM:Fetch("font", nameSettings.levelFont, true) or fontPath
        end
        Helpers.ApplyFontWithFallback(levelText, levelFontPath, nameSettings and nameSettings.levelFontSize or nameFontSize, fontOutline)
        levelText:SetTextColor(1, 1, 1, 1)
        levelText:SetWordWrap(false)
        if nameSettings and nameSettings.showLevel == true then
            levelText:Show()
        else
            levelText:Hide()
        end
        frame.levelText = levelText

        local healthSettings = vdb.health
        local healthFontSize = healthSettings and healthSettings.healthFontSize or 12

        local healthText = frame.healthText or textFrame:CreateFontString(nil, "OVERLAY")
        if Helpers and Helpers.ApplyFontWithFallback then
            Helpers.ApplyFontWithFallback(healthText, fontPath, healthFontSize, fontOutline)
        else
            healthText:SetFont(fontPath, healthFontSize, fontOutline)
        end
        healthText:SetTextColor(1, 1, 1, 1)
        healthText:SetWordWrap(false)
        frame.healthText = healthText

        local indDB = vdb.indicators or {}

        local roleIconSize = indDB.roleIconSize or 12
        local roleAnchor = indDB.roleIconAnchor or "TOPLEFT"
        local roleOffX = indDB.roleIconOffsetX or 2
        local roleOffY = indDB.roleIconOffsetY or -2

        local roleIcon = frame.roleIcon or textFrame:CreateTexture(nil, "OVERLAY")
        roleIcon:ClearAllPoints()
        roleIcon:SetSize(roleIconSize, roleIconSize)
        roleIcon:Hide()
        frame.roleIcon = roleIcon

        local readyCheckIcon = frame.readyCheckIcon or textFrame:CreateTexture(nil, "OVERLAY")
        readyCheckIcon:ClearAllPoints()
        local rcSize = indDB.readyCheckSize or 16
        readyCheckIcon:SetSize(rcSize, rcSize)
        local rcAnchor = indDB.readyCheckAnchor or "CENTER"
        readyCheckIcon:Hide()
        frame.readyCheckIcon = readyCheckIcon

        local resIcon = frame.resIcon or textFrame:CreateTexture(nil, "OVERLAY")
        resIcon:ClearAllPoints()
        local resSize = indDB.resurrectionSize or 16
        resIcon:SetSize(resSize, resSize)
        local resAnchor = indDB.resurrectionAnchor or "CENTER"
        resIcon:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")
        resIcon:Hide()
        frame.resIcon = resIcon

        local summonIcon = frame.summonIcon or textFrame:CreateTexture(nil, "OVERLAY")
        summonIcon:ClearAllPoints()
        local sumSize = indDB.summonSize or 20
        summonIcon:SetSize(sumSize, sumSize)
        local sumAnchor = indDB.summonAnchor or "CENTER"
        summonIcon:SetAtlas("RaidFrame-Icon-SummonPending")
        summonIcon:Hide()
        frame.summonIcon = summonIcon

        local leaderIcon = frame.leaderIcon or textFrame:CreateTexture(nil, "OVERLAY")
        leaderIcon:ClearAllPoints()
        local ldrSize = indDB.leaderSize or 12
        leaderIcon:SetSize(ldrSize, ldrSize)
        local ldrAnchor = indDB.leaderAnchor or "TOP"
        leaderIcon:Hide()
        frame.leaderIcon = leaderIcon

        local targetMarker = frame.targetMarker or textFrame:CreateTexture(nil, "OVERLAY")
        targetMarker:ClearAllPoints()
        local tmSize = indDB.targetMarkerSize or 14
        targetMarker:SetSize(tmSize, tmSize)
        local tmAnchor = indDB.targetMarkerAnchor or "TOPRIGHT"
        targetMarker:Hide()
        frame.targetMarker = targetMarker

        local phaseIcon = frame.phaseIcon or textFrame:CreateTexture(nil, "OVERLAY")
        phaseIcon:ClearAllPoints()
        local phSize = indDB.phaseSize or 16
        phaseIcon:SetSize(phSize, phSize)
        local phAnchor = indDB.phaseAnchor or "BOTTOMLEFT"
        phaseIcon:SetTexture("Interface\\TargetingFrame\\UI-PhasingIcon")
        phaseIcon:Hide()
        frame.phaseIcon = phaseIcon

        indDB = vdb.indicators or {}
        local threatBorderPx = px * (indDB.threatBorderSize or 3)
        local threatBorder = frame.threatBorder or CreateFrame("Frame", nil, frame, "BackdropTemplate")
        threatBorder:ClearAllPoints()
        threatBorder:SetPoint("TOPLEFT", -px, px)
        threatBorder:SetPoint("BOTTOMRIGHT", px, -px)
        threatBorder:SetFrameLevel(frame:GetFrameLevel() + LEVELS.THREAT)
        EnsureBackdrop(threatBorder, GetCachedBackdrop(
            "Interface\\Buttons\\WHITE8x8",
            "Interface\\Buttons\\WHITE8x8",
            threatBorderPx
        ))
        threatBorder._fillOpacity = tonumber(indDB.threatFillOpacity) or 0.15
        threatBorder:Hide()
        frame.threatBorder = threatBorder

        local healerDB = vdb.healer
        local targetSettings = healerDB and healerDB.targetHighlight
        local targetHighlight = frame.targetHighlight or CreateFrame("Frame", nil, frame, "BackdropTemplate")
        targetHighlight:ClearAllPoints()
        targetHighlight:SetPoint("TOPLEFT", -px, px)
        targetHighlight:SetPoint("BOTTOMRIGHT", px, -px)
        targetHighlight:SetFrameLevel(frame:GetFrameLevel() + LEVELS.TARGET)
        EnsureBackdrop(targetHighlight, GetCachedBackdrop(
            "Interface\\Buttons\\WHITE8x8",
            "Interface\\Buttons\\WHITE8x8",
            px * 2
        ))
        targetHighlight._fillOpacity = tonumber(targetSettings and targetSettings.fillOpacity) or 0.12
        targetHighlight:Hide()
        frame.targetHighlight = targetHighlight

        local dispelOverlay = frame.dispelOverlay or CreateFrame("Frame", nil, frame)
        dispelOverlay:ClearAllPoints()
        dispelOverlay:SetAllPoints(frame)
        dispelOverlay:SetFrameLevel(frame:GetFrameLevel() + LEVELS.DISPEL)

        local dispelSettings = healerDB and healerDB.dispelOverlay
        local dispelBorderSize = px * (dispelSettings and dispelSettings.borderSize or 3)
        local function MakeDispelBorder(parent)
            local sb = CreateFrame("StatusBar", nil, parent)
            sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
            sb:SetMinMaxValues(0, 1)
            sb:SetValue(1)
            return sb
        end

        local bTop = dispelOverlay.borderTop or MakeDispelBorder(dispelOverlay)
        bTop:ClearAllPoints()
        bTop:SetPoint("TOPLEFT", dispelOverlay, "TOPLEFT", 0, 0)
        bTop:SetPoint("TOPRIGHT", dispelOverlay, "TOPRIGHT", 0, 0)
        bTop:SetHeight(dispelBorderSize)
        dispelOverlay.borderTop = bTop

        local bBottom = dispelOverlay.borderBottom or MakeDispelBorder(dispelOverlay)
        bBottom:ClearAllPoints()
        bBottom:SetPoint("BOTTOMLEFT", dispelOverlay, "BOTTOMLEFT", 0, 0)
        bBottom:SetPoint("BOTTOMRIGHT", dispelOverlay, "BOTTOMRIGHT", 0, 0)
        bBottom:SetHeight(dispelBorderSize)
        dispelOverlay.borderBottom = bBottom

        local bLeft = dispelOverlay.borderLeft or MakeDispelBorder(dispelOverlay)
        bLeft:ClearAllPoints()
        bLeft:SetPoint("TOPLEFT", dispelOverlay, "TOPLEFT", 0, 0)
        bLeft:SetPoint("BOTTOMLEFT", dispelOverlay, "BOTTOMLEFT", 0, 0)
        bLeft:SetWidth(dispelBorderSize)
        dispelOverlay.borderLeft = bLeft

        local bRight = dispelOverlay.borderRight or MakeDispelBorder(dispelOverlay)
        bRight:ClearAllPoints()
        bRight:SetPoint("TOPRIGHT", dispelOverlay, "TOPRIGHT", 0, 0)
        bRight:SetPoint("BOTTOMRIGHT", dispelOverlay, "BOTTOMRIGHT", 0, 0)
        bRight:SetWidth(dispelBorderSize)
        dispelOverlay.borderRight = bRight

        local dispelFill = dispelOverlay.fill
        if not dispelFill then
            dispelFill = dispelOverlay:CreateTexture(nil, "BACKGROUND")
            dispelOverlay.fill = dispelFill
        end
        dispelFill:SetAllPoints(dispelOverlay)
        dispelFill:SetColorTexture(1, 1, 1, 1)
        dispelFill:SetVertexColor(0, 0, 0, 0)
        dispelOverlay._fillOpacity = dispelSettings and dispelSettings.fillOpacity or 0

        -- Awareness gradient for the BY_ME_PLUS_TYPED scope (above the flat
        -- fill, below the border bars). Both endpoints ride the asset's alpha
        -- via LayoutDispelGradient; consumers tint, lay out, and show it.
        local dispelGradient = dispelOverlay.gradient
        if not dispelGradient then
            dispelGradient = dispelOverlay:CreateTexture(nil, "BACKGROUND", nil, 1)
            dispelGradient:SetTexture(Chrome.DISPEL_GRADIENT_TEXTURE)
            dispelOverlay.gradient = dispelGradient
        end
        dispelGradient:SetAllPoints(dispelOverlay)
        dispelGradient:Hide()

        dispelOverlay:Hide()
        frame.dispelOverlay = dispelOverlay

        Chrome.ApplyDispelIconLayout(frame, dispelSettings)

        local cleanseGlow = frame.cleanseGlow or CreateFrame("Frame", nil, frame)
        cleanseGlow:ClearAllPoints()
        cleanseGlow:SetPoint("TOPLEFT", frame, "TOPLEFT", -4, 4)
        cleanseGlow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 4, -4)
        cleanseGlow:SetFrameLevel(frame:GetFrameLevel() + LEVELS.CLEANSE)
        local glowTex = cleanseGlow.tex
        if not glowTex then
            glowTex = cleanseGlow:CreateTexture(nil, "OVERLAY")
            glowTex:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
            glowTex:SetBlendMode("ADD")
            cleanseGlow.tex = glowTex
        end
        glowTex:SetAllPoints(cleanseGlow)
        cleanseGlow:Hide()
        frame.cleanseGlow = cleanseGlow

        local portraitSettings = vdb.portrait
        if portraitSettings and portraitSettings.showPortrait then
            local portraitSizePx = portraitSettings.portraitSize or 30
            local portraitSizeRound = QUICore.PixelRound and QUICore:PixelRound(portraitSizePx, frame) or portraitSizePx
            local portraitBorderPx = QUICore.Pixels and QUICore:Pixels(1, frame) or px

            local portrait = frame.portrait or CreateFrame("Frame", nil, frame, "BackdropTemplate")
            portrait:SetSize(portraitSizeRound, portraitSizeRound)
            portrait:ClearAllPoints()

            local side = portraitSettings.portraitSide or "LEFT"
            if side == "LEFT" then
                portrait:SetPoint("RIGHT", frame, "LEFT", 0, 0)
            else
                portrait:SetPoint("LEFT", frame, "RIGHT", 0, 0)
            end

            EnsureBackdrop(portrait, GetCachedBackdrop(nil, "Interface\\Buttons\\WHITE8x8", portraitBorderPx))
            local pbdr, pbdg, pbdb, pbda = 0, 0, 0, 1
            if Helpers and Helpers.GetSkinBorderColor then pbdr, pbdg, pbdb, pbda = Helpers.GetSkinBorderColor() end
            portrait:SetBackdropBorderColor(pbdr, pbdg, pbdb, pbda)
            portrait:SetFrameLevel(frame:GetFrameLevel() + 1)

            local portraitTex = frame.portraitTexture or portrait:CreateTexture(nil, "ARTWORK")
            portraitTex:ClearAllPoints()
            portraitTex:SetPoint("TOPLEFT", portraitBorderPx, -portraitBorderPx)
            portraitTex:SetPoint("BOTTOMRIGHT", -portraitBorderPx, portraitBorderPx)
            frame.portraitTexture = portraitTex
            frame.portrait = portrait
            portrait:Show()
        elseif frame.portrait then
            frame.portrait:Hide()
        end
    AnchorBottomPadded(frame, vdb, bottomPad)

    if state then
        state.healthPowerShow = showPower
        state.healthPowerBorder = borderSize
        state.healthPowerBottom = bottomPad
    end

    return {
        borderSize      = borderSize,
        px              = px,
        powerHeight     = powerHeight,
        separatorHeight = separatorHeight,
        bottomPad       = bottomPad,
        showPower       = showPower,
        isVertical      = isVertical,
    }
end

function Chrome.ResizeHealthForPower(frame, vdb, showPowerForUnit, state)
    if not frame or not frame.healthBar then return end
    vdb = vdb or {}
    state = state or {}
    local QUICore = ns.Addon
    local general = vdb.general
    local borderPx = general and general.borderSize or 1
    local borderSize = borderPx > 0 and (QUICore and QUICore.Pixels and QUICore:Pixels(borderPx, frame) or borderPx) or 0
    local px = (QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(frame)) or 1

    local bottomPad = borderSize
    if showPowerForUnit then
        local powerSettings = vdb.power
        local rawPowerHeight = (powerSettings and powerSettings.powerBarHeight) or 4
        local powerHeight = (QUICore and QUICore.PixelRound and QUICore:PixelRound(rawPowerHeight, frame)) or rawPowerHeight
        bottomPad = borderSize + powerHeight + px
    end

    if state.healthPowerShow == showPowerForUnit
        and state.healthPowerBorder == borderSize
        and state.healthPowerBottom == bottomPad
    then
        return bottomPad
    end
    state.healthPowerShow = showPowerForUnit
    state.healthPowerBorder = borderSize
    state.healthPowerBottom = bottomPad
    frame._bottomPad = bottomPad

    frame.healthBar:ClearAllPoints()
    frame.healthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", borderSize, -borderSize)
    frame.healthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, bottomPad)
    AnchorBottomPadded(frame, vdb, bottomPad)
    return bottomPad
end

function Chrome.SetBackdropOverlayColor(overlay, r, g, b, a)
    if not overlay then return end
    overlay:SetBackdropBorderColor(r, g, b, a)
    SetBackdropFillColor(overlay, r, g, b, overlay._fillOpacity or 0)
end

local DISPEL_BORDER_KEYS = { "borderTop", "borderBottom", "borderLeft", "borderRight" }
Chrome.DISPEL_BORDER_KEYS = DISPEL_BORDER_KEYS

-- White alpha ramp (opaque bottom -> transparent top) tinted per dispel type
-- for the BY_ME_PLUS_TYPED awareness gradient.
Chrome.DISPEL_GRADIENT_TEXTURE = ((ns.Helpers and ns.Helpers.AssetPath)
    or "Interface\\AddOns\\QUI\\assets\\") .. "dispel_gradient.tga"

-- Geometry + alpha for the awareness gradient. Opacity rides the ASSET's
-- per-pixel alpha via a texcoord sub-range: the ramp asset's alpha equals its
-- v coordinate, so sampling v across [endOpacity, startOpacity] renders a fade
-- between exactly those two opacities. That matters because the aura engine
-- owns registered dispel-type textures -- it rewrites SetAlpha when it shows
-- them and overwrites vertex color from an RGB-only color map on every aura
-- update -- so asset alpha is the only carrier that survives. Endpoints may be
-- inverted (end > start); WoW samples a flipped texcoord range natively, and
-- equal endpoints degenerate to a flat fill at that opacity. Color is applied
-- by the caller (engine tint, color curve, or plain rgb).
function Chrome.LayoutDispelGradient(tex, startOpacity, endOpacity, verticalFill)
    if not tex then return end
    local s = tonumber(startOpacity) or 1
    local e = tonumber(endOpacity) or 0
    if s < 0 then s = 0 elseif s > 1 then s = 1 end
    if e < 0 then e = 0 elseif e > 1 then e = 1 end
    if verticalFill then
        -- Fill origin is the bottom edge.
        tex:SetTexCoord(0, 1, e, s)
    else
        -- Rotate 90 degrees: fill origin is the left edge.
        tex:SetTexCoord(0, s, 1, s, 0, e, 1, e)
    end
end

-- Border/fill visibility toggle so the gradient can show alone when only a
-- non-actionable typed debuff is present (BY_ME_PLUS_TYPED scope).
function Chrome.SetDispelBordersShown(overlay, shown)
    if not overlay then return end
    for _, key in ipairs(DISPEL_BORDER_KEYS) do
        local border = overlay[key]
        if border then border:SetShown(shown) end
    end
    if overlay.fill then overlay.fill:SetShown(shown) end
end

function Chrome.SetDispelBorderColor(overlay, r, g, b, a)
    if not overlay then return end
    for _, key in ipairs(DISPEL_BORDER_KEYS) do
        local border = overlay[key]
        if border then
            border:GetStatusBarTexture():SetVertexColor(r, g, b, a)
        end
    end
    if overlay.fill then
        local fillA = overlay._fillOpacity or 0
        overlay.fill:SetVertexColor(r, g, b, fillA)
    end
end

Chrome.FontPath              = FontPath
Chrome.FontOutline           = FontOutline
Chrome.TexturePath           = TexturePath
Chrome.ApplyStatusBarTexture = ApplyStatusBarTexture
Chrome.TextAnchorInfo        = GetTextAnchorInfo
Chrome.GetCachedBackdrop     = GetCachedBackdrop
Chrome.EnsureBackdrop        = EnsureBackdrop
Chrome.SetBackdropFillColor  = SetBackdropFillColor
Chrome.ApplyOverlayBar       = ApplyOverlayBar
Chrome.BackdropCache         = _backdropCache
Chrome.FontPathCache         = _fontPathCache
ns.QUI_GroupFrameApplyOverlayBar = ApplyOverlayBar

return Chrome
