local ADDON_NAME, ns = ...
local function CJKFont(fs, p, s, f)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fs, p, s, f)
    else
        fs:SetFont(p, s, f)
    end
end
local Helpers = ns.Helpers
local QUICore = ns.Addon
local GetDB = Helpers.CreateDBGetter("quiGroupFrames")
local CHROME_LEVELS = (ns.QUI_GroupFrameChrome and ns.QUI_GroupFrameChrome.LEVELS)
    or {
        THREAT = 6, TARGET = 7, DISPEL = 8, TEXT = 9,
        DISPEL_ICON = 10, CLEANSE = 11, AURA_HOST = 12,
    }

local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local format = format
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local string_format = string.format
local table_insert = table.insert

local QUI_GFEM = {}
ns.QUI_GroupFrameEditMode = QUI_GFEM

local isEditMode = false
local isTestMode = false
local testFrames = {}
local testContainer = nil
local testContainers = {}
local testFramesByType = {}
local reuseContainers = {}
local groupMover = nil
local raidMover = nil
local spotlightHeader = nil
local spotlightContainer = nil
local partySelectionWatcher = nil
local raidSelectionWatcher = nil

local FAKE_CLASSES = { "WARRIOR", "PALADIN", "PRIEST", "DRUID", "SHAMAN", "MAGE", "ROGUE", "HUNTER", "WARLOCK", "DEATHKNIGHT", "MONK", "DEMONHUNTER", "EVOKER" }
local FAKE_NAMES = { "Tankthor", "Healena", "Pwnadin", "Natureza", "Shamwow", "Frostina", "Stabsworth", "Bowmaster", "Felcaster", "Lichking", "Mistpaw", "Demonbane", "Scalewing",
    "Ironwall", "Lightbeam", "Shadowmend", "Wildgrowth", "Totemist", "Arcanist", "Backstab", "Marksman", "Doomcall", "Runeblade", "Zenmaster", "Havocwing", "Breathfire",
    "Shieldwall", "Holylight", "Mindblast", "Starfall", "Lavaflow", "Pyrolust", "Ambusher", "Snipeshot", "Soulburn", "Froststorm", "Tigerpaw", "Vengewing", "Glimmora",
    "Bulwark", "Divinity" }
local FAKE_ROLES = { "TANK", "HEALER", "DAMAGER", "DAMAGER", "DAMAGER" }
local FAKE_RAID_ROLES = { "TANK", "TANK", "HEALER", "HEALER", "HEALER", "HEALER",
    "DAMAGER", "DAMAGER", "DAMAGER", "DAMAGER", "DAMAGER", "DAMAGER", "DAMAGER", "DAMAGER",
    "DAMAGER", "DAMAGER", "DAMAGER", "DAMAGER", "DAMAGER", "DAMAGER", "DAMAGER", "DAMAGER",
    "DAMAGER", "DAMAGER", "DAMAGER", "DAMAGER", "DAMAGER", "DAMAGER", "DAMAGER", "DAMAGER",
    "DAMAGER", "DAMAGER", "DAMAGER", "DAMAGER", "DAMAGER", "DAMAGER", "DAMAGER", "DAMAGER",
    "DAMAGER", "DAMAGER" }

local FAKE_BUFF_ICONS = {
    136034,
    135940,
    136081,
}
local FAKE_DEBUFF_ICONS = {
    136207,
    136130,
    136067,
}

local PREVIEW_INDICATORS = {
    [1] = { leader = true, targetHighlight = true, threatBorder = true, buffs = 1 },
    [2] = { readyCheck = true, raidMarker = 1, debuffs = 2, buffs = 1 },
    [3] = { phaseIcon = true, resurrection = true, debuffs = 1 },
    [4] = { dispelOverlay = true, summonPending = true, debuffs = 3 },
    [5] = { raidMarker = 8, buffs = 2 },
}

local function GetFakeHealthPct(index)
    local patterns = { 100, 85, 65, 45, 92, 78, 30, 95, 88, 55,
                       72, 100, 80, 60, 90, 75, 40, 98, 82, 68,
                       0, 100, 70, 50, 95, 85, 35, 100, 77, 62,
                       88, 42, 100, 73, 56, 91, 100, 83, 47, 100 }
    return patterns[((index - 1) % #patterns) + 1]
end

local PREVIEW_ELEMENT_BUFF_ICONS = { 136034, 135940, 136081, 135932, 136063 }
local PREVIEW_ELEMENT_DEBUFF_ICONS = { 136207, 136130, 136067, 135813, 136118 }

local function GetPreviewSpecID()
    local specIndex = GetSpecialization and GetSpecialization()
    if specIndex and GetSpecializationInfo then
        return (GetSpecializationInfo(specIndex))
    end
    return nil
end

local testShellPool = {}
local testShellCount = 0
local activeRecycle

local RECYCLE_KINDS = { "frames", "backdropFrames", "bars", "textures", "strings" }

local function RecycleStart(frame)
    local rc = frame._quiRecycle
    if not rc then
        rc = {}
        for _, kind in ipairs(RECYCLE_KINDS) do rc[kind] = {} end
        frame._quiRecycle = rc
    end
    rc.n = { frames = 0, backdropFrames = 0, bars = 0, textures = 0, strings = 0 }
    activeRecycle = rc
end

local function RecycleFinish()
    local rc = activeRecycle
    if not rc then return end
    for _, kind in ipairs(RECYCLE_KINDS) do
        local list = rc[kind]
        for i = rc.n[kind] + 1, #list do
            list[i]:Hide()
        end
    end
    activeRecycle = nil
end

local function RecycledFrame(parent, template)
    local rc = activeRecycle
    local key = template and "backdropFrames" or "frames"
    local n = rc.n[key] + 1
    rc.n[key] = n
    local f = rc[key][n]
    if not f then
        f = CreateFrame("Frame", nil, parent, template)
        rc[key][n] = f
    else
        f:SetParent(parent)
        f:ClearAllPoints()
        f:Show()
    end
    return f
end

local function RecycledBar(parent)
    local rc = activeRecycle
    local n = rc.n.bars + 1
    rc.n.bars = n
    local bar = rc.bars[n]
    if not bar then
        bar = CreateFrame("StatusBar", nil, parent)
        rc.bars[n] = bar
    else
        bar:SetParent(parent)
        bar:ClearAllPoints()
        bar:SetOrientation("HORIZONTAL")
        bar:SetAlpha(1)
        bar:Show()
    end
    bar:SetFrameLevel(parent:GetFrameLevel() + 1)
    return bar
end

local function RecycledTexture(parent, layer, sublevel)
    local rc = activeRecycle
    local n = rc.n.textures + 1
    rc.n.textures = n
    local tex = rc.textures[n]
    if not tex then
        tex = parent:CreateTexture(nil, layer, nil, sublevel)
        rc.textures[n] = tex
    else
        tex:SetParent(parent)
        tex:SetDrawLayer(layer, sublevel or 0)
        tex:ClearAllPoints()
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetVertexColor(1, 1, 1, 1)
        tex:Show()
    end
    return tex
end

local function RecycledFontString(parent, layer)
    local rc = activeRecycle
    local n = rc.n.strings + 1
    rc.n.strings = n
    local fs = rc.strings[n]
    if not fs then
        fs = parent:CreateFontString(nil, layer)
        rc.strings[n] = fs
    else
        fs:SetParent(parent)
        fs:ClearAllPoints()
        fs:SetText("")
        fs:Show()
    end
    return fs
end

local function AcquireTestShell(parent)
    local frame = table.remove(testShellPool)
    if frame then
        frame._quiPooled = nil
        frame:SetParent(parent)
        frame:ClearAllPoints()
        local Chrome = ns.QUI_GroupFrameChrome
        if Chrome and Chrome.HideDispelTypeIcons then
            Chrome.HideDispelTypeIcons(frame)
        end
    else
        testShellCount = testShellCount + 1
        frame = CreateFrame("Frame", "QUI_TestFrame" .. testShellCount, parent, "BackdropTemplate")
        frame._quiTestShell = true
    end
    return frame
end

local function ReleaseTestShell(frame)
    if frame._quiPooled then return end
    frame._quiPooled = true
    frame:Hide()
    testShellPool[#testShellPool + 1] = frame
end

local function RenderAuraElementsPreview(frame, auras, auraLevel, powerHeight, px, texturePath, frameType)
    local Model = ns.QUI_GroupFramesAuraModel
    if not Model or not Model.ActiveElementsForSpec then return end
    if Model.EnsureSeeded then Model.EnsureSeeded(auras, frameType) end
    local IconLayout = ns.QUI_GroupFrameIconLayout
    local elements = Model.ActiveElementsForSpec(auras, GetPreviewSpecID())
    if not elements or #elements == 0 then return end

    for _, element in ipairs(elements) do
        local mode = element.mode
        local displayType = element.displayType or "icon"

        if mode == "filterStrip" or mode == "missingRaidBuff" or (mode == "tracked" and displayType == "icon") then
            local harmful = (mode == "filterStrip") and element.auraType == "HARMFUL"
            local sampleIcons = harmful and PREVIEW_ELEMENT_DEBUFF_ICONS or PREVIEW_ELEMENT_BUFF_ICONS
            local borderR, borderG, borderB = (harmful and 0.8 or 0), (harmful and 0 or 0.6), 0
            local iconSize = element.iconSize or 14
            local growDir = element.growDirection or "RIGHT"
            local spacing = element.spacing or 2
            local anchor = element.anchor or "TOPLEFT"
            local offX = element.offsetX or 0
            local offY = element.offsetY or 0
            if anchor:find("BOTTOM") then offY = offY + powerHeight end
            local count
            if mode == "filterStrip" or mode == "missingRaidBuff" then
                count = element.maxIcons or 0
                if count <= 0 then count = #sampleIcons end
            else
                count = element.spells and #element.spells or 1
            end
            count = math.min(count, #sampleIcons)
            if count < 1 then count = 1 end

            local iconAnchor = (IconLayout and IconLayout.GetIconAnchorForGrow
                and IconLayout.GetIconAnchorForGrow(anchor, growDir)) or anchor
            local perRow = tonumber(element.iconsPerRow) or 0
            if perRow < 0 then perRow = 0 end
            local rowDir
            if growDir == "UP" or growDir == "DOWN" then
                rowDir = (type(anchor) == "string" and anchor:find("RIGHT")) and "LEFT" or "RIGHT"
            else
                rowDir = (type(anchor) == "string" and anchor:find("BOTTOM")) and "UP" or "DOWN"
            end
            for i = 1, count do
                local iconFrame = RecycledFrame(frame, "BackdropTemplate")
                iconFrame:SetSize(iconSize, iconSize)
                iconFrame:SetFrameLevel(auraLevel)
                local slotX, slotY = 0, 0
                if IconLayout and IconLayout.CalculateSlotOffset then
                    slotX, slotY = IconLayout.CalculateSlotOffset(i, iconSize, spacing, growDir, count, perRow, rowDir)
                else
                    slotX = (i - 1) * (iconSize + spacing)
                end
                iconFrame:ClearAllPoints()
                iconFrame:SetPoint(iconAnchor, frame, anchor, offX + slotX, offY + slotY)
                local iconPx = QUICore.GetPixelSize and QUICore:GetPixelSize(iconFrame) or px
                ns.SkinBase.ApplyPixelBackdrop(iconFrame, 1, true, false, { borderR, borderG, borderB, 1 }, { 0, 0, 0, 1 })
                local tex = RecycledTexture(iconFrame, "ARTWORK")
                tex:SetPoint("TOPLEFT", iconPx, -iconPx)
                tex:SetPoint("BOTTOMRIGHT", -iconPx, iconPx)
                tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                tex:SetTexture(sampleIcons[((i - 1) % #sampleIcons) + 1])
            end

        elseif mode == "tracked" and displayType == "square" then
            local size = element.iconSize or 8
            local anchor = element.anchor or "TOPLEFT"
            local offX = element.offsetX or 0
            local offY = element.offsetY or 0
            if anchor:find("BOTTOM") then offY = offY + powerHeight end
            local color = element.color or { 0.5, 0.5, 0.5, 1 }
            local sq = RecycledFrame(frame, "BackdropTemplate")
            sq:SetSize(size, size)
            sq:SetFrameLevel(auraLevel)
            sq:ClearAllPoints()
            sq:SetPoint(anchor, frame, anchor, offX, offY)
            ns.SkinBase.ApplyPixelBackdrop(sq, 1, false, false, { 0, 0, 0, 1 })
            local fill = RecycledTexture(sq, "ARTWORK")
            fill:SetAllPoints()
            fill:SetColorTexture(color[1] or 0.5, color[2] or 0.5, color[3] or 0.5, color[4] or 1)

        elseif mode == "tracked" and displayType == "bar" then
            local barCfg = element.bar or {}
            local orientation = barCfg.orientation == "VERTICAL" and "VERTICAL" or "HORIZONTAL"
            local thickness = math.max(1, barCfg.thickness or 4)
            local length = math.max(1, barCfg.length or 40)
            local width = orientation == "HORIZONTAL" and length or thickness
            local height = orientation == "VERTICAL" and length or thickness
            local anchor = barCfg.anchor or element.anchor or "BOTTOM"
            local offX = barCfg.offsetX or element.offsetX or 0
            local offY = barCfg.offsetY or element.offsetY or 0
            if anchor:find("BOTTOM") then offY = offY + powerHeight end
            local color = (barCfg.color) or element.color or { 0.2, 0.8, 0.2, 1 }
            local bar = RecycledBar(frame)
            bar:SetSize(width, height)
            bar:SetFrameLevel(auraLevel + 1)
            bar:ClearAllPoints()
            bar:SetPoint(anchor, frame, anchor, offX, offY)
            bar:SetOrientation(orientation)
            bar:SetStatusBarTexture(texturePath)
            bar:SetMinMaxValues(0, 1)
            bar:SetValue(0.66)
            bar:SetStatusBarColor(color[1] or 0.2, color[2] or 0.8, color[3] or 0.2, color[4] or 1)
            local bg = RecycledTexture(bar, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0, 0, 0, 0.28)

        elseif mode == "tracked" and displayType == "healthTint" then
            local hb = frame.healthBar
            if hb then
                local color = element.color or { 0.2, 0.8, 0.2, 1 }
                local tint = RecycledTexture(hb, "OVERLAY")
                tint:SetAllPoints(hb)
                tint:SetColorTexture(color[1] or 0.2, color[2] or 0.8, color[3] or 0.2, (color[4] or 1) * 0.4)
            end

        elseif mode == "tracked" and displayType == "border" then
            local anchorTo = frame.healthBar or frame
            local color = element.color or { 0.2, 0.8, 0.2, 1 }
            local size = math.max(1, (element.border and element.border.thickness) or 2)
            local outline = RecycledFrame(frame, "BackdropTemplate")
            outline:SetFrameLevel(auraLevel + 2)
            outline:ClearAllPoints()
            outline:SetPoint("TOPLEFT", anchorTo, "TOPLEFT", -size, size)
            outline:SetPoint("BOTTOMRIGHT", anchorTo, "BOTTOMRIGHT", size, -size)
            outline:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = size })
            outline:SetBackdropBorderColor(color[1] or 0.2, color[2] or 0.8, color[3] or 0.2, color[4] or 1)
        end
    end
end

local function CreateTestFrame(parent, index, totalCount, classToken, name, role, healthPct, contextMode)
    local db = GetDB()
    if not db then return nil end

    local GF = ns.QUI_GroupFrames
    if not GF then return nil end

    local isRaid = contextMode == "raid"
    local vdb = isRaid and (db.raid or db) or (db.party or db)

    local mode
    if totalCount <= 5 then mode = "party"
    elseif totalCount <= 15 then mode = "small"
    elseif totalCount <= 25 then mode = "medium"
    else mode = "large"
    end

    local dims = vdb and vdb.dimensions
    local w, h
    if mode == "party" then w, h = dims and dims.partyWidth or 200, dims and dims.partyHeight or 40
    elseif mode == "small" then w, h = dims and dims.smallRaidWidth or 180, dims and dims.smallRaidHeight or 36
    elseif mode == "medium" then w, h = dims and dims.mediumRaidWidth or 160, dims and dims.mediumRaidHeight or 30
    else w, h = dims and dims.largeRaidWidth or 140, dims and dims.largeRaidHeight or 24
    end

    local frame = AcquireTestShell(parent)
    RecycleStart(frame)
    frame:SetSize(w, h)

    local general = vdb.general
    local borderPx = general and general.borderSize or 1
    local borderSize = borderPx > 0 and (QUICore.Pixels and QUICore:Pixels(borderPx, frame) or borderPx) or 0
    local px = QUICore.GetPixelSize and QUICore:GetPixelSize(frame) or 1

    local bgColor, healthOpacity, bgOpacity
    if general and general.darkMode then
        bgColor = general.darkModeBgColor or { 0.25, 0.25, 0.25, 1 }
        healthOpacity = general.darkModeHealthOpacity or 1.0
        bgOpacity = general.darkModeBgOpacity or 1.0
    else
        bgColor = general and general.defaultBgColor or { 0.1, 0.1, 0.1, 0.9 }
        healthOpacity = general and general.defaultHealthOpacity or 1.0
        bgOpacity = general and general.defaultBgOpacity or 1.0
    end
    local bgAlpha = (bgColor[4] or 1) * bgOpacity
    local frameBorderColor
    if borderSize > 0 then
        local bdr, bdg, bdb, bda = 0.15, 0.15, 0.15, 1
        if Helpers and Helpers.GetSkinBorderColor then bdr, bdg, bdb, bda = Helpers.GetSkinBorderColor() end
        frameBorderColor = { bdr, bdg, bdb, bda }
    end
    ns.SkinBase.ApplyPixelBackdrop(frame, borderSize > 0 and borderPx or 0, true, false, frameBorderColor, { bgColor[1], bgColor[2], bgColor[3], bgAlpha })

    local powerSettings = vdb.power
    local showPower = powerSettings and powerSettings.showPowerBar ~= false
    local powerHeight = showPower and (powerSettings.powerBarHeight or 4) or 0
    local separatorHeight = showPower and px or 0

    local LSM = ns.LSM
    local textureName = general and general.texture or "Quazii v5"
    local texturePath = LSM:Fetch("statusbar", textureName) or "Interface\\TargetingFrame\\UI-StatusBar"

    local healthBar = RecycledBar(frame)
    healthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", borderSize, -borderSize)
    healthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize + powerHeight + separatorHeight)
    healthBar:SetStatusBarTexture(texturePath)
    healthBar:SetMinMaxValues(0, 100)
    healthBar:SetValue(healthPct)
    healthBar:SetAlpha(healthOpacity)

    if general and general.darkMode then
        local c = general.darkModeHealthColor or { 0.15, 0.15, 0.15, 1 }
        healthBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    elseif general and general.useClassColor ~= false then
        local cc = RAID_CLASS_COLORS[classToken]
        if cc then
            healthBar:SetStatusBarColor(cc.r, cc.g, cc.b, 1)
        else
            healthBar:SetStatusBarColor(0.2, 0.8, 0.2, 1)
        end
    else
        healthBar:SetStatusBarColor(0.2, 0.8, 0.2, 1)
    end

    if showPower then
        local powerBar = RecycledBar(frame)
        powerBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", borderSize, borderSize)
        powerBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize)
        powerBar:SetHeight(powerHeight)
        powerBar:SetStatusBarTexture(texturePath)
        powerBar:SetMinMaxValues(0, 100)
        powerBar:SetValue(100)
        if powerSettings.powerBarUsePowerColor then
            powerBar:SetStatusBarColor(0.2, 0.4, 0.8, 1)
        else
            local pc = powerSettings.powerBarColor or {0.2, 0.4, 0.8, 1}
            powerBar:SetStatusBarColor(pc[1], pc[2], pc[3], pc[4] or 1)
        end

        local powerBg = RecycledTexture(powerBar, "BACKGROUND")
        powerBg:SetAllPoints()
        powerBg:SetTexture("Interface\\Buttons\\WHITE8x8")
        powerBg:SetVertexColor(0.05, 0.05, 0.05, 0.9)

        local sep = RecycledTexture(powerBar, "OVERLAY")
        sep:SetHeight(px)
        sep:SetPoint("BOTTOMLEFT", powerBar, "TOPLEFT", 0, 0)
        sep:SetPoint("BOTTOMRIGHT", powerBar, "TOPRIGHT", 0, 0)
        sep:SetTexture("Interface\\Buttons\\WHITE8x8")
        sep:SetVertexColor(0, 0, 0, 1)
    end

    local textFrame = RecycledFrame(frame)
    textFrame:SetAllPoints()
    textFrame:SetFrameLevel(frame:GetFrameLevel() + CHROME_LEVELS.TEXT)

    local fontName = general and general.font or "Quazii"
    local fontPath = LSM:Fetch("font", fontName) or "Fonts\\FRIZQT__.TTF"
    local fontOutline = general and general.fontOutline or "OUTLINE"

    local ANCHOR_MAP = ns.QUI_GroupFrameTextAnchorMap

    local nameSettings = vdb.name
    if not nameSettings or nameSettings.showName ~= false then
        local nameAnchorInfo = ANCHOR_MAP[nameSettings and nameSettings.nameAnchor or "LEFT"] or ANCHOR_MAP.LEFT
        local nameOffsetX = nameSettings and nameSettings.nameOffsetX or 4
        local nameOffsetY = nameSettings and nameSettings.nameOffsetY or 0
        local namePadX = math.abs(nameOffsetX)
        local nameText = RecycledFontString(textFrame, "OVERLAY")
        Helpers.ApplyFontWithFallback(nameText, fontPath, nameSettings and nameSettings.nameFontSize or 12, fontOutline)
        nameText:SetPoint(nameAnchorInfo.leftPoint, frame, nameAnchorInfo.leftPoint, namePadX, nameOffsetY)
        nameText:SetPoint(nameAnchorInfo.rightPoint, frame, nameAnchorInfo.rightPoint, -namePadX, nameOffsetY)
        nameText:SetJustifyH(nameSettings and nameSettings.nameJustify or nameAnchorInfo.justify)
        nameText:SetJustifyV(nameAnchorInfo.justifyV)
        nameText:SetWordWrap(false)

        local displayName = name
        local maxLen = nameSettings and nameSettings.maxNameLength or 10
        if maxLen > 0 and #displayName > maxLen then
            displayName = displayName:sub(1, maxLen)
        end
        nameText:SetText("")
        nameText:SetText(displayName)

        if nameSettings and nameSettings.nameTextUseClassColor then
            local cc = RAID_CLASS_COLORS[classToken]
            if cc then
                nameText:SetTextColor(cc.r, cc.g, cc.b, 1)
            else
                nameText:SetTextColor(1, 1, 1, 1)
            end
        elseif nameSettings and nameSettings.nameTextColor then
            local tc = nameSettings.nameTextColor
            nameText:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
        else
            nameText:SetTextColor(1, 1, 1, 1)
        end
    end

    if nameSettings and nameSettings.showLevel == true then
        local levelAnchorInfo = ANCHOR_MAP[nameSettings.levelAnchor or "RIGHT"] or ANCHOR_MAP.RIGHT
        local levelOffsetX = nameSettings.levelOffsetX or -4
        local levelOffsetY = nameSettings.levelOffsetY or 0
        local levelPadX = math.abs(levelOffsetX)
        local levelText = RecycledFontString(textFrame, "OVERLAY")
        local levelFontPath = fontPath
        if type(nameSettings.levelFont) == "string" and nameSettings.levelFont ~= "" then
            levelFontPath = LSM:Fetch("font", nameSettings.levelFont, true) or fontPath
        end
        Helpers.ApplyFontWithFallback(levelText, levelFontPath, nameSettings.levelFontSize or 12, fontOutline)
        levelText:SetPoint(levelAnchorInfo.leftPoint, frame, levelAnchorInfo.leftPoint, levelPadX, levelOffsetY)
        levelText:SetPoint(levelAnchorInfo.rightPoint, frame, levelAnchorInfo.rightPoint, -levelPadX, levelOffsetY)
        levelText:SetJustifyH(nameSettings.levelJustify or levelAnchorInfo.justify)
        levelText:SetJustifyV(levelAnchorInfo.justifyV)
        levelText:SetWordWrap(false)
        levelText:SetText(tostring(80 - ((index - 1) % 6)))

        if nameSettings.levelTextColor then
            local tc = nameSettings.levelTextColor
            levelText:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
        else
            levelText:SetTextColor(1, 1, 1, 1)
        end
    end

    local healthSettings = vdb.health
    if not healthSettings or healthSettings.showHealthText ~= false then
        local healthAnchorInfo = ANCHOR_MAP[healthSettings and healthSettings.healthAnchor or "RIGHT"] or ANCHOR_MAP.RIGHT
        local healthOffsetX = healthSettings and healthSettings.healthOffsetX or -4
        local healthOffsetY = healthSettings and healthSettings.healthOffsetY or 0
        local healthPadX = math.abs(healthOffsetX)
        local healthText = RecycledFontString(textFrame, "OVERLAY")
        CJKFont(healthText, fontPath, healthSettings and healthSettings.healthFontSize or 12, fontOutline)
        healthText:SetPoint(healthAnchorInfo.leftPoint, frame, healthAnchorInfo.leftPoint, healthPadX, healthOffsetY)
        healthText:SetPoint(healthAnchorInfo.rightPoint, frame, healthAnchorInfo.rightPoint, -healthPadX, healthOffsetY)
        healthText:SetJustifyH(healthAnchorInfo.justify)
        healthText:SetJustifyV(healthAnchorInfo.justifyV)
        healthText:SetWordWrap(false)

        if healthPct == 0 then
            healthText:SetText(ns.L["Dead"])
            healthText:SetTextColor(0.5, 0.5, 0.5, 1)
            healthBar:SetStatusBarColor(0.5, 0.5, 0.5, 1)
        else
            local style = healthSettings and healthSettings.healthDisplayStyle or "percent"
            local fakeHP = healthPct * 1000
            local fakeMax = 100000
            if style == "percent" then
                healthText:SetText(healthPct .. "%")
            elseif style == "absolute" then
                healthText:SetText(string_format("%.0fK", fakeHP / 1000))
            elseif style == "both" then
                healthText:SetText(string_format("%.0fK", fakeHP / 1000) .. " | " .. healthPct .. "%")
            elseif style == "deficit" then
                local deficit = fakeMax - fakeHP
                if deficit > 0 then
                    healthText:SetText("-" .. string_format("%.0fK", deficit / 1000))
                else
                    healthText:SetText("")
                end
            else
                healthText:SetText(healthPct .. "%")
            end

            if healthSettings and healthSettings.healthTextColor then
                local tc = healthSettings.healthTextColor
                healthText:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
            else
                healthText:SetTextColor(1, 1, 1, 1)
            end
        end
    elseif healthPct == 0 then
        healthBar:SetStatusBarColor(0.5, 0.5, 0.5, 1)
    end

    local indSettings = vdb.indicators
    if indSettings and indSettings.showRoleIcon ~= false then
        local ROLE_TOGGLE_KEY = ns.QUI_GroupFrameRoleToggleKey
        local toggleKey = ROLE_TOGGLE_KEY[role]
        if not toggleKey or indSettings[toggleKey] ~= false then
            local roleIcon = RecycledTexture(textFrame, "OVERLAY")
            roleIcon:SetSize(indSettings.roleIconSize or 12, indSettings.roleIconSize or 12)
            local roleAnchor = indSettings.roleIconAnchor or "TOPLEFT"
            roleIcon:SetPoint(roleAnchor, frame, roleAnchor, indSettings.roleIconOffsetX or 2, indSettings.roleIconOffsetY or -2)
            local ROLE_ATLAS = ns.QUI_GroupFrameRoleAtlas
            local atlas = ROLE_ATLAS[role]
            if atlas then
                roleIcon:SetAtlas(atlas)
            else
                roleIcon:Hide()
            end
        end
    end

    local prev = PREVIEW_INDICATORS[((index - 1) % #PREVIEW_INDICATORS) + 1]
    local baseLevel = frame:GetFrameLevel()

    if prev and indSettings then
        local function IndPoint(tex, anchorKey, offXKey, offYKey, defAnchor, defX, defY)
            local a = indSettings[anchorKey] or defAnchor
            tex:SetPoint(a, frame, a, indSettings[offXKey] or defX, indSettings[offYKey] or defY)
        end

        if prev.readyCheck and indSettings.showReadyCheck ~= false then
            local rc = RecycledTexture(textFrame, "OVERLAY")
            local rcSize = indSettings.readyCheckSize or 16
            rc:SetSize(rcSize, rcSize)
            IndPoint(rc, "readyCheckAnchor", "readyCheckOffsetX", "readyCheckOffsetY", "CENTER", 0, 0)
            rc:SetTexture("INTERFACE\\RAIDFRAME\\ReadyCheck-Ready")
        end

        if prev.resurrection and indSettings.showResurrection ~= false then
            local ri = RecycledTexture(textFrame, "OVERLAY")
            local riSize = indSettings.resurrectionSize or 16
            ri:SetSize(riSize, riSize)
            IndPoint(ri, "resurrectionAnchor", "resurrectionOffsetX", "resurrectionOffsetY", "CENTER", 0, 0)
            ri:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")
        end

        if prev.summonPending and indSettings.showSummonPending ~= false then
            local si = RecycledTexture(textFrame, "OVERLAY")
            local siSize = indSettings.summonSize or 20
            si:SetSize(siSize, siSize)
            IndPoint(si, "summonAnchor", "summonOffsetX", "summonOffsetY", "CENTER", 16, 0)
            si:SetAtlas("RaidFrame-Icon-SummonPending")
        end

        if prev.leader and indSettings.showLeaderIcon ~= false then
            local li = RecycledTexture(textFrame, "OVERLAY")
            local liSize = indSettings.leaderSize or 12
            li:SetSize(liSize, liSize)
            IndPoint(li, "leaderAnchor", "leaderOffsetX", "leaderOffsetY", "TOP", 0, 6)
            li:SetAtlas("groupfinder-icon-leader")
        end

        if prev.raidMarker and indSettings.showTargetMarker ~= false then
            local rm = RecycledTexture(textFrame, "OVERLAY")
            local rmSize = indSettings.targetMarkerSize or 14
            rm:SetSize(rmSize, rmSize)
            IndPoint(rm, "targetMarkerAnchor", "targetMarkerOffsetX", "targetMarkerOffsetY", "TOPRIGHT", -2, -2)
            rm:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
            SetRaidTargetIconTexture(rm, prev.raidMarker)
        end

        if prev.phaseIcon and indSettings.showPhaseIcon ~= false then
            local pi = RecycledTexture(textFrame, "OVERLAY")
            local piSize = indSettings.phaseSize or 16
            pi:SetSize(piSize, piSize)
            IndPoint(pi, "phaseAnchor", "phaseOffsetX", "phaseOffsetY", "BOTTOMLEFT", 2, 2)
            pi:SetTexture("Interface\\TargetingFrame\\UI-PhasingIcon")
        end

        if prev.threatBorder and indSettings.showThreatBorder ~= false then
            local threatOverlay = RecycledFrame(frame, "BackdropTemplate")
            threatOverlay:SetAllPoints()
            threatOverlay:SetFrameLevel(baseLevel + CHROME_LEVELS.THREAT)
            local tc = indSettings.threatColor or { 1, 0, 0, 0.8 }
            ns.SkinBase.ApplyPixelBackdrop(threatOverlay, indSettings.threatBorderSize or 3, true, false, { tc[1], tc[2], tc[3], tc[4] or 0.8 }, { tc[1], tc[2], tc[3], indSettings.threatFillOpacity or 0.15 })
        end
    end

    local healerSettings = vdb.healer
    if prev and healerSettings then
        if prev.targetHighlight then
            local th = healerSettings.targetHighlight
            if th and th.enabled ~= false then
                local highlight = RecycledFrame(frame, "BackdropTemplate")
                highlight:SetPoint("TOPLEFT", -px, px)
                highlight:SetPoint("BOTTOMRIGHT", px, -px)
                highlight:SetFrameLevel(baseLevel + CHROME_LEVELS.TARGET)
                local hc = th.color or { 1, 1, 1, 0.6 }
                ns.SkinBase.ApplyPixelBackdrop(highlight, 2, true, false, { hc[1], hc[2], hc[3], hc[4] or 0.6 }, { hc[1], hc[2], hc[3], th.fillOpacity or 0.12 })
            end
        end

        if prev.dispelOverlay then
            local dsp = healerSettings.dispelOverlay
            if dsp then
                local sampleType = dsp.scope == "ALL_TYPED" and "Bleed" or "Magic"
                if dsp.enabled ~= false then
                    local dispel = RecycledFrame(frame, "BackdropTemplate")
                    dispel:SetPoint("TOPLEFT", -px, px)
                    dispel:SetPoint("BOTTOMRIGHT", px, -px)
                    dispel:SetFrameLevel(baseLevel + CHROME_LEVELS.DISPEL)
                    local palette = dsp.colors or {}
                    local dc = palette[sampleType] or { 0.26, 0.54, 1, 0.8 }
                    local opacity = dsp.opacity or 0.8
                    ns.SkinBase.ApplyPixelBackdrop(dispel, dsp.borderSize or 3, true, false, { dc[1], dc[2], dc[3], opacity }, { dc[1], dc[2], dc[3], dsp.fillOpacity or 0.18 })
                    if dsp.scope == "BY_ME_PLUS_TYPED" then
                        -- Sample the awareness gradient in a non-actionable
                        -- type's color (Bleed) under the actionable border.
                        local ChromeGF = ns.QUI_GroupFrameChrome
                        local gc = palette.Bleed or { 0.8, 0, 0, 1 }
                        local grad = RecycledTexture(dispel, "BACKGROUND", 1)
                        grad:SetTexture(ChromeGF and ChromeGF.DISPEL_GRADIENT_TEXTURE)
                        grad:SetPoint("TOPLEFT", dispel, "TOPLEFT", 0, 0)
                        grad:SetPoint("BOTTOMRIGHT", dispel, "BOTTOMRIGHT", 0, 0)
                        grad:SetVertexColor(gc[1], gc[2], gc[3], 1)
                        if ChromeGF and ChromeGF.LayoutDispelGradient then
                            local health = vdb.health
                            ChromeGF.LayoutDispelGradient(grad,
                                dsp.gradientStartOpacity, dsp.gradientEndOpacity,
                                (health and health.healthFillDirection) == "VERTICAL")
                        end
                    end
                end
                local Chrome = ns.QUI_GroupFrameChrome
                if dsp.showIcon == true and Chrome and Chrome.ApplyDispelIconLayout then
                    Chrome.ApplyDispelIconLayout(frame, dsp)
                    Chrome.ShowDispelTypeIcon(frame, sampleType)
                end
            end
        end
    end

    local auraSettings = vdb.auras
    if prev and auraSettings and auraSettings.enabled ~= false then
        RenderAuraElementsPreview(frame, auraSettings, baseLevel + CHROME_LEVELS.AURA_HOST, powerHeight, px, texturePath,
            isRaid and "raid" or "party")
    end

    local absorbSettings = vdb.absorbs
    local healPredSettings = vdb.healPrediction
    local fillRight = w * (healthPct / 100)
    local remaining = w - fillRight
    local absorbW = math.min(w * 0.12, remaining)
    local healPredW = math.min(w * 0.08, math.max(remaining - absorbW, 0))

    local previewCC = RAID_CLASS_COLORS[classToken]
    local ccR, ccG, ccB = previewCC and previewCC.r or 1, previewCC and previewCC.g or 1, previewCC and previewCC.b or 1

    if absorbSettings and absorbSettings.enabled ~= false and absorbW > 0 then
        local ac
        if absorbSettings.useClassColor then
            ac = { ccR, ccG, ccB, 1 }
        else
            ac = absorbSettings.color or {1, 1, 1, 1}
        end
        local aa = absorbSettings.opacity or 0.3
        local absorbOverlay = RecycledTexture(healthBar, "OVERLAY", 1)
        absorbOverlay:SetTexture("Interface\\RaidFrame\\Shield-Fill")
        absorbOverlay:SetVertexColor(ac[1], ac[2], ac[3], aa)
        absorbOverlay:SetPoint("TOPLEFT", healthBar, "TOPLEFT", fillRight, 0)
        absorbOverlay:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", fillRight, 0)
        absorbOverlay:SetWidth(absorbW)
    end

    if healPredSettings and healPredSettings.enabled ~= false and healPredW > 0 then
        local hc
        if healPredSettings.useClassColor then
            hc = { ccR, ccG, ccB, 1 }
        else
            hc = healPredSettings.color or {0.2, 1, 0.2}
        end
        local ha = healPredSettings.opacity or 0.5
        local healOverlay = RecycledTexture(healthBar, "OVERLAY", 1)
        healOverlay:SetTexture(texturePath)
        healOverlay:SetVertexColor(hc[1], hc[2], hc[3], ha)
        local healStart = fillRight + (absorbSettings and absorbSettings.enabled ~= false and absorbW or 0)
        healOverlay:SetPoint("TOPLEFT", healthBar, "TOPLEFT", healStart, 0)
        healOverlay:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", healStart, 0)
        healOverlay:SetWidth(healPredW)
    end

    RecycleFinish()
    frame:Show()
    return frame
end

local function DestroyTestFrames(onlyType)
    if onlyType then
        local frames = testFramesByType[onlyType]
        if frames then
            for _, frame in ipairs(frames) do ReleaseTestShell(frame) end
            wipe(frames)
        end
        testFramesByType[onlyType] = nil
        local keepContainer = testContainers[onlyType]
        testContainers[onlyType] = nil
        if not testContainers.party and not testContainers.raid then
            testContainer = nil
            wipe(testFrames)
        else
            testContainer = testContainers.party or testContainers.raid
        end
        if keepContainer then
            reuseContainers[#reuseContainers + 1] = keepContainer
        end
    else
        for _, frame in ipairs(testFrames) do
            if frame._quiTestShell then
                ReleaseTestShell(frame)
            else
                frame:Hide()
                frame:SetParent(nil)
            end
        end
        wipe(testFrames)
        for _, frames in pairs(testFramesByType) do
            for _, frame in ipairs(frames) do ReleaseTestShell(frame) end
        end
        wipe(testFramesByType)
        for _, container in pairs(testContainers) do
            reuseContainers[#reuseContainers + 1] = container
        end
        wipe(testContainers)
        testContainer = nil
    end
end

function QUI_GFEM:EnableTestMode(previewType)
    if testContainers[previewType] then return end

    if testFramesByType[previewType] then DestroyTestFrames(previewType) end

    local db = GetDB()
    if not db then return end

    isTestMode = true
    self._lastTestPreviewType = previewType

    local GF = ns.QUI_GroupFrames
    if GF then GF.testMode = true end

    local count
    if previewType == "raid" then
        count = db.testMode and db.testMode.raidCount or 25
    else
        count = db.testMode and db.testMode.partyCount or 5
    end

    local container = table.remove(reuseContainers)
    if container then
        container:SetParent(UIParent)
    else
        container = CreateFrame("Frame", nil, UIParent)
    end

    container:SetFrameStrata("LOW")
    container:ClearAllPoints()
    if isEditMode then
        local targetMover = groupMover
        if previewType == "raid" and raidMover then
            targetMover = raidMover
        end
        if targetMover then
            container:SetPoint("CENTER", targetMover, "CENTER", 0, 0)
        else
            container:SetPoint("CENTER", UIParent, "CENTER", -400, 0)
        end
    else
        local faKey = previewType == "raid" and "raidFrames" or "partyFrames"
        local core = ns.Helpers and ns.Helpers.GetCore and ns.Helpers.GetCore()
        local faDB = core and core.db and core.db.profile and core.db.profile.frameAnchoring
        local fa = faDB and faDB[faKey]
        if fa and fa.point then
            container:SetPoint(fa.point, UIParent, fa.relative or fa.point, fa.offsetX or 0, fa.offsetY or 0)
        else
            local posKey = previewType == "raid" and "raidPosition" or "position"
            local position = db[posKey]
            container:SetPoint("CENTER", UIParent, "CENTER", position and position.offsetX or -400, position and position.offsetY or 0)
        end
    end
    container:Show()
    testContainers[previewType] = container
    testContainer = container
    table_insert(testFrames, container)
    testFramesByType[previewType] = testFramesByType[previewType] or {}

    local isRaid = previewType == "raid"
    local vdb = isRaid and (db.raid or db) or (db.party or db)
    local layout = vdb.layout
    local spacing = layout and layout.spacing or 2
    local grow = layout and layout.growDirection or "DOWN"
    local groupGrowDir = layout and layout.groupGrowDirection
    local groupSpacing = layout and layout.groupSpacing or 10
    local horizontal = (grow == "LEFT" or grow == "RIGHT")
    if not groupGrowDir then
        groupGrowDir = horizontal and "DOWN" or "RIGHT"
    end

    local framesPerGroup = 5
    local numGroups = math.ceil(count / framesPerGroup)

    local mode
    if count <= 5 then mode = "party"
    elseif count <= 15 then mode = "small"
    elseif count <= 25 then mode = "medium"
    else mode = "large"
    end

    local dims = vdb and vdb.dimensions
    local frameW, frameH
    if mode == "party" then frameW, frameH = dims and dims.partyWidth or 200, dims and dims.partyHeight or 40
    elseif mode == "small" then frameW, frameH = dims and dims.smallRaidWidth or 180, dims and dims.smallRaidHeight or 36
    elseif mode == "medium" then frameW, frameH = dims and dims.mediumRaidWidth or 160, dims and dims.mediumRaidHeight or 30
    else frameW, frameH = dims and dims.largeRaidWidth or 140, dims and dims.largeRaidHeight or 24
    end

    for g = 1, numGroups do
        for i = 1, framesPerGroup do
            local index = (g - 1) * framesPerGroup + i
            if index > count then break end

            local classIdx = ((index - 1) % #FAKE_CLASSES) + 1
            local classToken = FAKE_CLASSES[classIdx]
            local name = FAKE_NAMES[((index - 1) % #FAKE_NAMES) + 1]
            local role
            if count <= 5 then
                role = FAKE_ROLES[((index - 1) % #FAKE_ROLES) + 1]
            else
                role = FAKE_RAID_ROLES[((index - 1) % #FAKE_RAID_ROLES) + 1]
            end
            local healthPct = GetFakeHealthPct(index)

            local testFrame = CreateTestFrame(container, index, count, classToken, name, role, healthPct, previewType)
            if testFrame then
                local col = g - 1
                local row = i - 1
                local xOff, yOff, anchor

                if horizontal then
                    if groupGrowDir == "UP" then
                        yOff = col * (frameH + groupSpacing)
                    else
                        yOff = -(col * (frameH + groupSpacing))
                    end
                    if grow == "RIGHT" then
                        anchor = groupGrowDir == "UP" and "BOTTOMLEFT" or "TOPLEFT"
                        xOff = row * (frameW + spacing)
                    else
                        anchor = groupGrowDir == "UP" and "BOTTOMRIGHT" or "TOPRIGHT"
                        xOff = -(row * (frameW + spacing))
                    end
                else
                    if grow == "DOWN" then
                        anchor = (groupGrowDir == "LEFT") and "TOPRIGHT" or "TOPLEFT"
                        yOff = -(row * (frameH + spacing))
                    else
                        anchor = (groupGrowDir == "LEFT") and "BOTTOMRIGHT" or "BOTTOMLEFT"
                        yOff = row * (frameH + spacing)
                    end
                    local groupRight = (groupGrowDir == "RIGHT")
                    xOff = groupRight and (col * (frameW + groupSpacing)) or -(col * (frameW + groupSpacing))
                end

                testFrame:SetPoint(anchor, container, anchor, xOff, yOff)
                table_insert(testFrames, testFrame)
                table_insert(testFramesByType[previewType], testFrame)
            end
        end
    end

    local totalW, totalH
    if horizontal then
        totalW = framesPerGroup * frameW + (framesPerGroup - 1) * spacing
        totalH = numGroups * frameH + (numGroups - 1) * groupSpacing
    else
        totalW = numGroups * frameW + (numGroups - 1) * groupSpacing
        totalH = framesPerGroup * frameH + (framesPerGroup - 1) * spacing
    end
    container:SetSize(totalW, totalH)

    if not isEditMode and _G.QUI_ApplyFrameAnchor then
        _G.QUI_ApplyFrameAnchor(previewType == "raid" and "raidFrames" or "partyFrames")
    end

    if isEditMode then
        self:SyncMoverToContent()
    end
end

local function CleanupReuseContainers()
    for i = #reuseContainers, 1, -1 do
        local container = reuseContainers[i]
        reuseContainers[i] = nil
        container:Hide()
        container:SetParent(nil)
    end
end

function QUI_GFEM:DisableTestMode(switching, onlyType)
    if onlyType then
        DestroyTestFrames(onlyType)
        CleanupReuseContainers()
        if not testContainers.party and not testContainers.raid then
            isTestMode = false
            self._lastTestPreviewType = nil
            local GF = ns.QUI_GroupFrames
            if GF then GF.testMode = false end
        else
            self._lastTestPreviewType = testContainers.party and "party" or "raid"
        end
    else
        DestroyTestFrames()
        CleanupReuseContainers()
        isTestMode = false
        self._lastTestPreviewType = nil
        local GF = ns.QUI_GroupFrames
        if GF then GF.testMode = false end
    end

    if not switching and not isTestMode and isEditMode and not IsInGroup() and not IsInRaid() then
        self:DisableEditMode()
    end
end

function QUI_GFEM:IsTestMode()
    return isTestMode
end

local refreshTimer = nil
function QUI_GFEM:RefreshTestMode()
    if not isTestMode then return end

    if refreshTimer then
        refreshTimer:Cancel()
    end

    refreshTimer = C_Timer.NewTimer(0.15, function()
        refreshTimer = nil
        if not isTestMode then return end

        local rebuildTypes = {}
        for tType in pairs(testContainers) do rebuildTypes[#rebuildTypes + 1] = tType end
        if #rebuildTypes == 0 then rebuildTypes = { self._lastTestPreviewType or "party" } end

        for _, pt in ipairs(rebuildTypes) do
            DestroyTestFrames(pt)
            self:EnableTestMode(pt)
            local syncKey = pt == "raid" and "raidFrames" or "partyFrames"
            if _G.QUI_LayoutModeSyncHandle then
                _G.QUI_LayoutModeSyncHandle(syncKey)
            end
        end
    end)
end

local function GetHeaderBounds(header, db)
    if not header then return 0, 0 end

    local childCount = 0
    local i = 1
    while true do
        local child = header:GetAttribute("child" .. i)
        if not child then break end
        childCount = childCount + 1
        i = i + 1
    end

    if childCount == 0 then return 0, 0 end

    local isRaid = childCount > 5
    local vdb = db and (isRaid and (db.raid or db) or (db.party or db))
    local layout = vdb and vdb.layout
    local dims = vdb and vdb.dimensions
    local spacing = layout and layout.spacing or 2
    local groupSpacing = layout and layout.groupSpacing or 10

    local mode
    if childCount <= 5 then mode = "party"
    elseif childCount <= 15 then mode = "small"
    elseif childCount <= 25 then mode = "medium"
    else mode = "large"
    end

    local w, h
    if dims then
        if mode == "party" then w, h = dims.partyWidth or 200, dims.partyHeight or 40
        elseif mode == "small" then w, h = dims.smallRaidWidth or 180, dims.smallRaidHeight or 36
        elseif mode == "medium" then w, h = dims.mediumRaidWidth or 160, dims.mediumRaidHeight or 30
        else w, h = dims.largeRaidWidth or 140, dims.largeRaidHeight or 24
        end
    else
        w, h = 200, 40
    end

    local framesPerGroup = 5
    local numGroups = math.ceil(childCount / framesPerGroup)
    local framesInTallestGroup = math.min(childCount, framesPerGroup)

    local grow = layout and layout.growDirection or "DOWN"
    local horizontal = (grow == "LEFT" or grow == "RIGHT")

    local totalW, totalH
    if horizontal then
        totalW = framesInTallestGroup * w + (framesInTallestGroup - 1) * spacing
        totalH = numGroups * h + (numGroups - 1) * groupSpacing
    else
        totalW = numGroups * w + (numGroups - 1) * groupSpacing
        totalH = framesInTallestGroup * h + (framesInTallestGroup - 1) * spacing
    end

    return totalW, totalH
end

local function CreateNudgeButton(parent, direction, deltaX, deltaY)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(18, 18)
    btn:SetFrameStrata("HIGH")
    btn:SetFrameLevel(100)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(0.1, 0.1, 0.1, 0.7)

    local line1 = btn:CreateTexture(nil, "ARTWORK")
    line1:SetColorTexture(1, 1, 1, 0.9)
    line1:SetSize(7, 2)

    local line2 = btn:CreateTexture(nil, "ARTWORK")
    line2:SetColorTexture(1, 1, 1, 0.9)
    line2:SetSize(7, 2)

    if direction == "DOWN" then
        line1:SetPoint("CENTER", btn, "CENTER", -2, 1)
        line1:SetRotation(math.rad(-45))
        line2:SetPoint("CENTER", btn, "CENTER", 2, 1)
        line2:SetRotation(math.rad(45))
    elseif direction == "UP" then
        line1:SetPoint("CENTER", btn, "CENTER", -2, -1)
        line1:SetRotation(math.rad(45))
        line2:SetPoint("CENTER", btn, "CENTER", 2, -1)
        line2:SetRotation(math.rad(-45))
    elseif direction == "LEFT" then
        line1:SetPoint("CENTER", btn, "CENTER", -1, -2)
        line1:SetRotation(math.rad(-45))
        line2:SetPoint("CENTER", btn, "CENTER", -1, 2)
        line2:SetRotation(math.rad(45))
    elseif direction == "RIGHT" then
        line1:SetPoint("CENTER", btn, "CENTER", 1, -2)
        line1:SetRotation(math.rad(45))
        line2:SetPoint("CENTER", btn, "CENTER", 1, 2)
        line2:SetRotation(math.rad(-45))
    end

    btn:SetScript("OnEnter", function(self)
        line1:SetColorTexture(0.376, 0.647, 0.980, 1)
        line2:SetColorTexture(0.376, 0.647, 0.980, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        line1:SetColorTexture(1, 1, 1, 0.9)
        line2:SetColorTexture(1, 1, 1, 0.9)
    end)

    btn:SetScript("OnClick", function()
        local shift = IsShiftKeyDown()
        local step = shift and 10 or 1
        local key = parent._nudgeKey or "party"
        QUI_GFEM:NudgeHeader(key, deltaX * step, deltaY * step)
    end)

    return btn
end

local function UpdateMoverPositionText(mover, oX, oY)
    if mover and mover.posText then
        local label = mover._label or "Group Frames"
        mover.posText:SetText(format("%s  X: %d  Y: %d", label, oX, oY))
    end
end

local function GetMoverPositionTable(mover)
    local db = GetDB()
    if not db then return nil end
    local key = mover and mover._positionKey or "position"
    return db[key]
end

local function SaveMoverPosition(mover)
    local selfX, selfY = mover:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    if not selfX or not selfY or not parentX or not parentY then return end

    local rawX = selfX - parentX
    local rawY = selfY - parentY
    local oX = QUICore.PixelRound and QUICore:PixelRound(rawX) or Round(rawX)
    local oY = QUICore.PixelRound and QUICore:PixelRound(rawY) or Round(rawY)

    local pos = GetMoverPositionTable(mover)
    if pos then
        pos.offsetX = oX
        pos.offsetY = oY
    end

    UpdateMoverPositionText(mover, oX, oY)
    return oX, oY
end

local function SizeMoverToHeader(mover, hdr, db)
    if not mover or not hdr then return 0, 0 end
    local GF = ns.QUI_GroupFrames
    local w, h = 0, 0

    if GF and GF.CalculateHeaderSize then
        local isRaid = (hdr == (GF.headers and GF.headers.raid))
        local count
        if isRaid then
            count = IsInRaid() and GetNumGroupMembers() or 25
            count = math.max(count, 5)
        else
            count = IsInGroup() and not IsInRaid() and GetNumGroupMembers() or 5
            count = math.min(count, 5)
        end
        w, h = GF.CalculateHeaderSize(db, count)
    end

    if w == 0 or h == 0 then
        if hdr:IsShown() then
            w = Helpers.SafeValue(hdr:GetWidth(), 0)
            h = Helpers.SafeValue(hdr:GetHeight(), 0)
        end
    end
    if w == 0 or h == 0 then
        w, h = GetHeaderBounds(hdr, db)
    end
    return w, h
end

local function ReparentHeaderToMover(hdr, mover)
    if not hdr or not mover then return end
    local hLeft = Helpers.SafeValue(hdr:GetLeft(), nil)
    local hBottom = Helpers.SafeValue(hdr:GetBottom(), nil)
    hdr:SetParent(mover)
    hdr:ClearAllPoints()
    if hLeft and hBottom then
        local mLeft = mover:GetLeft()
        local mBottom = mover:GetBottom()
        if mLeft and mBottom then
            hdr:SetPoint("BOTTOMLEFT", mover, "BOTTOMLEFT",
                hLeft - mLeft, hBottom - mBottom)
        else
            hdr:SetPoint("CENTER", mover, "CENTER", 0, 0)
        end
    else
        hdr:SetPoint("CENTER", mover, "CENTER", 0, 0)
    end
end

function QUI_GFEM:SyncMoverToContent()
    if not isEditMode or not groupMover then return end
    if InCombatLockdown() then return end

    local db = GetDB()
    local GF = ns.QUI_GroupFrames

    if GF then
        local partyHdr = GF.headers and GF.headers.party
        if partyHdr then
            local pw, ph = SizeMoverToHeader(groupMover, partyHdr, db)
            groupMover:SetSize(math.max(pw, 100), math.max(ph, 40))
            ReparentHeaderToMover(partyHdr, groupMover)
        else
            groupMover:SetSize(200, 40)
        end

        if GF.headers.self then
            ReparentHeaderToMover(GF.headers.self, groupMover)
        end

        if raidMover then
            local raidHdr = GF.headers and GF.headers.raid
            if raidHdr then
                local rw, rh = SizeMoverToHeader(raidMover, raidHdr, db)
                raidMover:SetSize(math.max(rw, 100), math.max(rh, 40))
                ReparentHeaderToMover(raidHdr, raidMover)
            else
                raidMover:SetSize(200, 40)
            end
        end
    end

    local function SyncTestContainerToMover(container, mover)
        if not container or not mover then return end
        local tw = Helpers.SafeValue(container:GetWidth(), 200)
        local th = Helpers.SafeValue(container:GetHeight(), 200)
        mover:SetSize(math.max(tw, 100), math.max(th, 40))

        local tLeft = Helpers.SafeValue(container:GetLeft(), nil)
        local tBottom = Helpers.SafeValue(container:GetBottom(), nil)
        container:SetParent(mover)
        container:ClearAllPoints()
        if tLeft and tBottom then
            local mLeft = mover:GetLeft()
            local mBottom = mover:GetBottom()
            if mLeft and mBottom then
                container:SetPoint("BOTTOMLEFT", mover, "BOTTOMLEFT",
                    tLeft - mLeft, tBottom - mBottom)
            else
                container:SetPoint("CENTER", mover, "CENTER", 0, 0)
            end
        else
            container:SetPoint("CENTER", mover, "CENTER", 0, 0)
        end
    end

    if testContainers.party then
        SyncTestContainerToMover(testContainers.party, groupMover)
    end
    if testContainers.raid and raidMover then
        SyncTestContainerToMover(testContainers.raid, raidMover)
    end
end

local function CreateGroupMover(moverType)
    moverType = moverType or "party"
    local frameName = moverType == "raid" and "QUI_RaidFramesMover" or "QUI_PartyFramesMover"
    local label = moverType == "raid" and "Raid Frames" or "Party Frames"
    local posKey = moverType == "raid" and "raidPosition" or "position"
    local nudgeKey = moverType == "raid" and "raid" or "party"

    local mover = CreateFrame("Frame", frameName, UIParent)
    mover:SetFrameStrata("HIGH")
    mover:SetClampedToScreen(true)
    mover:SetMovable(true)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")

    mover._label = label
    mover._positionKey = posKey
    mover._nudgeKey = nudgeKey
    mover._moverType = moverType

    local border = CreateFrame("Frame", nil, mover, "BackdropTemplate")
    border:SetAllPoints()
    border:SetFrameLevel(mover:GetFrameLevel() + 100)
    ns.SkinBase.ApplyPixelBackdrop(border, 2, true, false, { 0.2, 0.8, 1, 1 }, { 0.2, 0.8, 1, 0.08 })
    border:EnableMouse(false)
    mover.border = border

    local fontPath = ns.LSM:Fetch("font", "Quazii") or "Fonts\\FRIZQT__.TTF"
    local posText = border:CreateFontString(nil, "OVERLAY")
    CJKFont(posText, fontPath, 10, "OUTLINE")
    posText:SetPoint("CENTER", mover, "CENTER", 0, 0)
    posText:SetTextColor(0.2, 0.8, 1, 1)
    mover.posText = posText

    local hint = border:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    CJKFont(hint, fontPath, 9, "OUTLINE")
    hint:SetPoint("TOP", mover, "BOTTOM", 0, -4)
    hint:SetTextColor(0.6, 0.6, 0.6, 1)
    hint:SetText(ns.L["Drag to move  |  Arrows to nudge (Shift=10px)"])
    mover.hint = hint

    local nudgeUp = CreateNudgeButton(mover, "UP", 0, 1)
    nudgeUp:SetPoint("BOTTOM", mover, "TOP", 0, 4)
    mover.nudgeUp = nudgeUp

    local nudgeDown = CreateNudgeButton(mover, "DOWN", 0, -1)
    nudgeDown:SetPoint("TOP", mover, "BOTTOM", 0, -4)
    mover.nudgeDown = nudgeDown

    local nudgeLeft = CreateNudgeButton(mover, "LEFT", -1, 0)
    nudgeLeft:SetPoint("RIGHT", mover, "LEFT", -4, 0)
    mover.nudgeLeft = nudgeLeft

    local nudgeRight = CreateNudgeButton(mover, "RIGHT", 1, 0)
    nudgeRight:SetPoint("LEFT", mover, "RIGHT", 4, 0)
    mover.nudgeRight = nudgeRight

    mover:SetScript("OnMouseDown", function(self, button)
        ---@diagnostic disable-next-line: empty-block
        if button == "LeftButton" then
        end
    end)

    mover:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        local anchorKey = (self._nudgeKey or "party") .. "Frames"
        if _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor(anchorKey) then return end
        self:StartMoving()
        self._isMoving = true

        self:SetScript("OnUpdate", function(self)
            if not self._isMoving then
                self:SetScript("OnUpdate", nil)
                return
            end
            local selfX, selfY = self:GetCenter()
            local parentX, parentY = UIParent:GetCenter()
            if selfX and selfY and parentX and parentY then
                local oX = QUICore.PixelRound and QUICore:PixelRound(selfX - parentX) or Round(selfX - parentX)
                local oY = QUICore.PixelRound and QUICore:PixelRound(selfY - parentY) or Round(selfY - parentY)
                UpdateMoverPositionText(self, oX, oY)
            end
        end)
    end)

    mover:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self._isMoving = false
        self:SetScript("OnUpdate", nil)
        SaveMoverPosition(self)
    end)

    mover:Hide()
    return mover
end

local function RestoreHeaderAnchors()
    if InCombatLockdown() then return end

    local GF = ns.QUI_GroupFrames
    if not GF then return end

    local db = GetDB()

    for _, hKey in ipairs({"party", "raid"}) do
        local hdr = GF.headers[hKey]
        local target = GF.anchorFrames and GF.anchorFrames[hKey] or hdr
        if target then
            local pos
            if hKey == "raid" then
                pos = db and db.raidPosition
            else
                pos = db and db.position
            end
            local oX = pos and pos.offsetX or -400
            local oY = pos and pos.offsetY or 0

            target:SetParent(UIParent)
            target:ClearAllPoints()
            target:SetPoint("CENTER", UIParent, "CENTER", oX, oY)
        end
    end

    local selfHdr = GF.headers.self
    if selfHdr then
        selfHdr:ClearAllPoints()
    end
end

function QUI_GFEM:UpdateMoverLockedState() end

function QUI_GFEM:EnableEditMode(previewType)
    if InCombatLockdown() then return end

    local wantType = previewType or "party"

    if isEditMode then
        if self._lastTestPreviewType ~= wantType then
            self:EnableTestMode(wantType)
        end
        return
    end

    isEditMode = true

    local GF = ns.QUI_GroupFrames
    if not GF then return end
    GF.editMode = true

    local db = GetDB()

    local function PositionMover(mover, headerKey)
        local pos = GetMoverPositionTable(mover)
        local oX = pos and pos.offsetX or -400
        local oY = pos and pos.offsetY or 0

        if GF and GF.headers then
            local hdr = GF.headers[headerKey]
            if hdr and hdr:IsShown() then
                local parentCX, parentCY = UIParent:GetCenter()
                if parentCX and parentCY then
                    local rawCX, rawCY = hdr:GetCenter()
                    local hCX = Helpers.SafeValue(rawCX, nil)
                    local hCY = Helpers.SafeValue(rawCY, nil)
                    if hCX and hCY then
                        oX = QUICore.PixelRound and QUICore:PixelRound(hCX - parentCX) or Round(hCX - parentCX)
                        oY = QUICore.PixelRound and QUICore:PixelRound(hCY - parentCY) or Round(hCY - parentCY)
                    end
                end
            end
        end

        mover:ClearAllPoints()
        mover:SetPoint("CENTER", UIParent, "CENTER", oX, oY)
        UpdateMoverPositionText(mover, oX, oY)
        mover:Show()
        return oX, oY
    end

    if not groupMover then
        groupMover = CreateGroupMover("party")
    end
    if not raidMover then
        raidMover = CreateGroupMover("raid")
    end
    if wantType == "party" then
        PositionMover(groupMover, "party")
        raidMover:Hide()
    elseif wantType == "raid" then
        PositionMover(raidMover, "raid")
        groupMover:Hide()
    else
        PositionMover(groupMover, "party")
        PositionMover(raidMover, "raid")
    end

    local needTestFrames = false
    if wantType == "raid" then
        needTestFrames = not IsInRaid()
    elseif wantType == "party" then
        needTestFrames = not IsInGroup() or IsInRaid()
    else
        needTestFrames = not IsInGroup() or not IsInRaid()
    end
    if needTestFrames then
        if not isTestMode or self._lastTestPreviewType ~= wantType then
            self:EnableTestMode(wantType)
        end
    end

    self:SyncMoverToContent()

    self:UpdateMoverLockedState()

    if CompactPartyFrame and CompactPartyFrame.Selection then
        C_Timer.After(0, function()
            if CompactPartyFrame and CompactPartyFrame.Selection then
                CompactPartyFrame.Selection:SetAlpha(0)
            end
        end)
        if not partySelectionWatcher then
            partySelectionWatcher = CreateFrame("Frame", nil, UIParent)
            partySelectionWatcher:SetScript("OnUpdate", function()
                if not isEditMode then return end
                local sel = CompactPartyFrame and CompactPartyFrame.Selection
                if sel and sel:GetAlpha() > 0 then
                    C_Timer.After(0, function()
                        if sel then sel:SetAlpha(0) end
                    end)
                end
            end)
        else
            partySelectionWatcher:Show()
        end
    end

    if CompactRaidFrameContainer and CompactRaidFrameContainer.Selection then
        C_Timer.After(0, function()
            if CompactRaidFrameContainer and CompactRaidFrameContainer.Selection then
                CompactRaidFrameContainer.Selection:SetAlpha(0)
            end
        end)
        if not raidSelectionWatcher then
            raidSelectionWatcher = CreateFrame("Frame", nil, UIParent)
            raidSelectionWatcher:SetScript("OnUpdate", function()
                if not isEditMode then return end
                local sel = CompactRaidFrameContainer and CompactRaidFrameContainer.Selection
                if sel and sel:GetAlpha() > 0 then
                    C_Timer.After(0, function()
                        if sel then sel:SetAlpha(0) end
                    end)
                end
            end)
        else
            raidSelectionWatcher:Show()
        end
    end

end

function QUI_GFEM:DisableEditMode()
    if not isEditMode then return end
    isEditMode = false

    if partySelectionWatcher then
        partySelectionWatcher:Hide()
    end
    if raidSelectionWatcher then
        raidSelectionWatcher:Hide()
    end

    local GF = ns.QUI_GroupFrames
    if GF then GF.editMode = false end

    local function StopAndHideMover(mover)
        if not mover then return end
        if mover._isMoving then
            mover:StopMovingOrSizing()
            mover._isMoving = false
            mover:SetScript("OnUpdate", nil)
            SaveMoverPosition(mover)
        end
        mover:Hide()
    end
    StopAndHideMover(groupMover)
    StopAndHideMover(raidMover)

    RestoreHeaderAnchors()
    if GF and GF.UpdateAnchorFrames then
        GF:UpdateAnchorFrames()
    end

    if isTestMode then
        self:DisableTestMode()
    end
end

function QUI_GFEM:IsEditMode()
    return isEditMode
end

function QUI_GFEM:GetActiveFrame(frameType)
    if isEditMode then
        if frameType == "raid" and raidMover then
            return raidMover
        end
        if groupMover then
            return groupMover
        end
    end
    if isTestMode then
        if frameType then
            return testContainers[frameType]
        end
        if testContainer then return testContainer end
    end
    return nil
end

function QUI_GFEM:NudgeHeader(headerKey, dx, dy)
    if InCombatLockdown() then return end

    local db = GetDB()
    if not db then return end

    local posKey = "position"
    local mover = groupMover
    if headerKey == "raid" then
        posKey = "raidPosition"
        mover = raidMover or groupMover
    end

    local pos = db[posKey]
    if not pos then return end

    pos.offsetX = (pos.offsetX or 0) + dx
    pos.offsetY = (pos.offsetY or 0) + dy

    if mover then
        mover:ClearAllPoints()
        mover:SetPoint("CENTER", UIParent, "CENTER", pos.offsetX, pos.offsetY)
        UpdateMoverPositionText(mover, pos.offsetX, pos.offsetY)
    end
end

function QUI_GFEM:CreateSpotlightHeader()
    local db = GetDB()
    local spot = db and db.raid and db.raid.spotlight
    if not spot or not spot.enabled then return end
    if InCombatLockdown() then return end

    if spotlightContainer and spotlightContainer._previewFrames then
        return spotlightContainer
    end

    local GF = ns.QUI_GroupFrames
    if not spotlightContainer and GF and GF.spotlightContainer then
        spotlightContainer = GF.spotlightContainer
        spotlightHeader = GF.spotlightHeader
    end

    local w = spot.frameWidth or 180
    local h = spot.frameHeight or 36

    if not spotlightContainer then
        spotlightContainer = CreateFrame("Frame", "QUI_SpotlightContainer", UIParent)
        spotlightContainer:SetSize(w, h)
        spotlightContainer:SetMovable(true)
        spotlightContainer:SetClampedToScreen(true)
        spotlightContainer._editModeCreated = true

        local anchoring = QUI and QUI.db and QUI.db.profile and QUI.db.profile.frameAnchoring
        local saved = anchoring and anchoring.spotlightFrames
        if saved then
            spotlightContainer:SetPoint(saved.point or "CENTER", UIParent, saved.relative or "CENTER",
                saved.offsetX or 0, saved.offsetY or 0)
        else
            spotlightContainer:SetPoint("CENTER", UIParent, "CENTER", -400, 200)
        end

        local initConfigFunc = [[
            local header = self:GetParent()
            self:SetWidth(header:GetAttribute("_initialAttribute-unit-width") or 200)
            self:SetHeight(header:GetAttribute("_initialAttribute-unit-height") or 40)
            self:SetAttribute("*type1", "target")
            self:SetAttribute("*type2", "togglemenu")
            RegisterUnitWatch(self)
        ]]

        spotlightHeader = CreateFrame("Frame", "QUI_SpotlightHeader", spotlightContainer, "SecureGroupHeaderTemplate")
        spotlightHeader:SetAttribute("template", "SecureUnitButtonTemplate, BackdropTemplate")
        spotlightHeader:SetAttribute("initialConfigFunction", initConfigFunc)
        spotlightHeader:SetAttribute("showRaid", true)
        spotlightHeader:SetAttribute("showParty", true)
        spotlightHeader:SetPoint("TOPLEFT")

        if GF then
            GF.spotlightHeader = spotlightHeader
            GF.spotlightContainer = spotlightContainer
        end
    end

    spotlightContainer:Show()

    local filterMode = spot.filterMode or "ROLE"
    local spacing = spot.spacing or 2
    local grow = spot.growDirection or "DOWN"
    local previewFrames = {}
    local previewData = {}
    if filterMode == "ROLE" then
        if spot.filterTank then
            previewData[#previewData + 1] = { class = "WARRIOR", name = "Tankthor", role = "TANK", hp = 100 }
            previewData[#previewData + 1] = { class = "PALADIN", name = "Ironwall", role = "TANK", hp = 92 }
        end
        if spot.filterHealer then
            previewData[#previewData + 1] = { class = "PRIEST", name = "Healena", role = "HEALER", hp = 85 }
            previewData[#previewData + 1] = { class = "DRUID", name = "Natureza", role = "HEALER", hp = 78 }
            previewData[#previewData + 1] = { class = "SHAMAN", name = "Shamwow", role = "HEALER", hp = 95 }
        end
    elseif filterMode == "NAME" then
        local nameList = spot.nameList or ""
        local count = 0
        for _ in nameList:gmatch("[^,]+") do count = count + 1 end
        count = math.max(count, 1)
        count = math.min(count, 8)
        for i = 1, count do
            local ci = ((i - 1) % #FAKE_CLASSES) + 1
            previewData[#previewData + 1] = { class = FAKE_CLASSES[ci], name = FAKE_NAMES[i] or ("Player" .. i), role = "DAMAGER", hp = GetFakeHealthPct(i) }
        end
    end

    local totalCount = #previewData
    if totalCount > 0 then
        local horizontal = (grow == "LEFT" or grow == "RIGHT")
        for i, data in ipairs(previewData) do
            local testFrame = CreateTestFrame(spotlightContainer, 1000 + i, totalCount, data.class, data.name, data.role, data.hp, "raid")
            if testFrame then
                testFrame:SetSize(w, h)
                testFrame:ClearAllPoints()
                if i == 1 then
                    testFrame:SetPoint("TOPLEFT", spotlightContainer, "TOPLEFT", 0, 0)
                else
                    local prev = previewFrames[i - 1]
                    if horizontal then
                        testFrame:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
                    else
                        testFrame:SetPoint("TOP", prev, "BOTTOM", 0, -spacing)
                    end
                end
                testFrame:Show()
                previewFrames[i] = testFrame
            end
        end

        if horizontal then
            spotlightContainer:SetSize(totalCount * w + (totalCount - 1) * spacing, h)
        else
            spotlightContainer:SetSize(w, totalCount * h + (totalCount - 1) * spacing)
        end
    end

    spotlightContainer._previewFrames = previewFrames

    return spotlightContainer
end

function QUI_GFEM:DestroySpotlightHeader()
    if spotlightContainer and spotlightContainer._previewFrames then
        for _, f in ipairs(spotlightContainer._previewFrames) do
            ReleaseTestShell(f)
        end
        spotlightContainer._previewFrames = nil
    end

    if spotlightContainer and not spotlightContainer._editModeCreated then
        spotlightContainer = nil
        spotlightHeader = nil
        return
    end

    if spotlightHeader then
        if not InCombatLockdown() then
            spotlightHeader:Hide()
        end
        local GF = ns.QUI_GroupFrames
        if GF then GF.spotlightHeader = nil; GF.spotlightContainer = nil end
        spotlightHeader = nil
    end
    if spotlightContainer then
        spotlightContainer:Hide()
        spotlightContainer = nil
    end
end

do
    local function RegisterLayoutModeElements()
        local um = ns.QUI_LayoutMode
        if not um then return end

        local function GetGFDB()
            local core = ns.Helpers.GetCore()
            return core and core.db and core.db.profile and core.db.profile.quiGroupFrames
        end

        um:RegisterElement({
            key = "partyFrames",
            label = ns.L["Party Frames"],
            group = ns.L["Group Frames"],
            order = 1,
            isOwned = true,
            getFrame = function()
                local GFEM = ns.QUI_GroupFrameEditMode
                if GFEM then
                    local active = GFEM:GetActiveFrame("party")
                    if active then return active end
                end
                local GF = ns.QUI_GroupFrames
                if GF and GF.anchorFrames and GF.anchorFrames.party then
                    return GF.anchorFrames.party
                end
                return GF and GF.headers and GF.headers.party
            end,
            setGameplayHidden = function(hide)
                local GF = ns.QUI_GroupFrames
                local root = GF and GF.anchorFrames and GF.anchorFrames.party
                local header = GF and GF.headers and GF.headers.party
                local target = root or header
                if not target then return end
                if hide then
                    target:SetAlpha(0)
                    ns.SafeCallMethod("best-effort-style", target, "EnableMouse", false)
                else
                    target:SetAlpha(1)
                    ns.SafeCallMethod("best-effort-style", target, "EnableMouse", true)
                end
            end,
            onOpen = function()
                local GFEM = ns.QUI_GroupFrameEditMode
                if GFEM and (not IsInGroup() or IsInRaid()) then GFEM:EnableTestMode("party") end
            end,
            onClose = function()
                local GFEM = ns.QUI_GroupFrameEditMode
                if GFEM then GFEM:DisableTestMode(false, "party") end
            end,
        })

        um:RegisterElement({
            key = "raidFrames",
            label = ns.L["Raid Frames"],
            group = ns.L["Group Frames"],
            order = 2,
            isOwned = true,
            setGameplayHidden = function(hide)
                local GF = ns.QUI_GroupFrames
                local root = GF and GF.anchorFrames and GF.anchorFrames.raid
                local header = GF and GF.headers and GF.headers.raid
                local target = root or header
                if not target then return end
                if hide then
                    target:SetAlpha(0)
                    ns.SafeCallMethod("best-effort-style", target, "EnableMouse", false)
                else
                    target:SetAlpha(1)
                    ns.SafeCallMethod("best-effort-style", target, "EnableMouse", true)
                end
            end,
            getFrame = function()
                local GFEM = ns.QUI_GroupFrameEditMode
                if GFEM then
                    local active = GFEM:GetActiveFrame("raid")
                    if active then return active end
                end
                local GF = ns.QUI_GroupFrames
                if GF and GF.anchorFrames and GF.anchorFrames.raid then
                    return GF.anchorFrames.raid
                end
                return GF and GF.headers and GF.headers.raid
            end,
            onOpen = function()
                local GFEM = ns.QUI_GroupFrameEditMode
                if GFEM and not IsInRaid() then GFEM:EnableTestMode("raid") end
            end,
            onClose = function()
                local GFEM = ns.QUI_GroupFrameEditMode
                if GFEM then GFEM:DisableTestMode(false, "raid") end
            end,
        })

        um:RegisterElement({
            key = "spotlightFrames",
            label = ns.L["Spotlight"],
            group = ns.L["Group Frames"],
            order = 3,
            isOwned = true,
            isEnabled = function()
                local db = GetGFDB()
                if not db or db.enabled == false then return false end
                local spot = db.raid and db.raid.spotlight
                return spot and spot.enabled == true
            end,
            setEnabled = function(val)
                local db = GetGFDB()
                if not db then return end
                if not db.raid then db.raid = {} end
                if not db.raid.spotlight then db.raid.spotlight = {} end
                db.raid.spotlight.enabled = val
                local GF = ns.QUI_GroupFrames
                if GF then
                    if val then
                        if GF.RecreateSpotlightHeader then
                            GF:RecreateSpotlightHeader()
                        end
                    else
                        if GF.spotlightHeader and not InCombatLockdown() then
                            GF.spotlightHeader:Hide()
                        end
                        if GF.spotlightContainer then
                            GF.spotlightContainer:Hide()
                        end
                    end
                end
            end,
            setGameplayHidden = function(hide)
                local container = spotlightContainer
                    or (ns.QUI_GroupFrames and ns.QUI_GroupFrames.spotlightContainer)
                if not container then return end
                if hide then
                    container:SetAlpha(0)
                    ns.SafeCallMethod("best-effort-style", container, "EnableMouse", false)
                else
                    container:SetAlpha(1)
                    ns.SafeCallMethod("best-effort-style", container, "EnableMouse", true)
                end
            end,
            getFrame = function()
                return spotlightContainer
                    or (ns.QUI_GroupFrames and ns.QUI_GroupFrames.spotlightContainer)
            end,
            onOpen = function()
                local GFEM = ns.QUI_GroupFrameEditMode
                if GFEM then
                    GFEM:CreateSpotlightHeader()
                end
            end,
            onClose = function()
                local GFEM = ns.QUI_GroupFrameEditMode
                if GFEM then
                    GFEM:DestroySpotlightHeader()
                end
            end,
        })
    end

    C_Timer.After(2, RegisterLayoutModeElements)
end
