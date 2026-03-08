--[[
    QUI Group Frames - Edit Mode & Test/Preview System
    Handles header dragging, nudge controls, fake preview frames,
    spotlight feature, and Blizzard Edit Mode integration.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local QUICore = ns.Addon
local GetDB = Helpers.CreateDBGetter("quiGroupFrames")

---------------------------------------------------------------------------
-- MODULE TABLE
---------------------------------------------------------------------------
local QUI_GFEM = {}
ns.QUI_GroupFrameEditMode = QUI_GFEM

local isEditMode = false
local isTestMode = false
local testFrames = {}
local testContainer = nil  -- direct reference to the active test container
local groupMover = nil     -- party mover (or unified mover when unifiedPosition = true)
local raidMover = nil      -- separate raid mover (only used when unifiedPosition = false)
local spotlightHeader = nil
local partySelectionWatcher = nil   -- OnUpdate guard for CompactPartyFrame.Selection
local raidSelectionWatcher = nil    -- OnUpdate guard for CompactRaidFrameContainer.Selection

---------------------------------------------------------------------------
-- FAKE DATA: For test/preview mode
---------------------------------------------------------------------------
local FAKE_CLASSES = { "WARRIOR", "PALADIN", "PRIEST", "DRUID", "SHAMAN", "MAGE", "ROGUE", "HUNTER", "WARLOCK", "DEATHKNIGHT", "MONK", "DEMONHUNTER", "EVOKER" }
local FAKE_NAMES = { "Tankthor", "Healena", "Pwnadin", "Natureza", "Shamwow", "Frostina", "Stabsworth", "Bowmaster", "Felcaster", "Lichking", "Mistpaw", "Demonbane", "Scalewing",
    "Ironwall", "Lightbeam", "Shadowmend", "Wildgrowth", "Totemist", "Arcanist", "Backstab", "Marksman", "Doomcall", "Runeblade", "Zenmaster", "Havocwing", "Breathfire",
    "Shieldwall", "Holylight", "Mindblast", "Starfall", "Lavaflow", "Pyrolust", "Ambusher", "Snipeshot", "Soulburn", "Froststorm", "Tigerpaw", "Vengewing", "Glimmora",
    "Bulwark", "Divinity" }
local FAKE_ROLES = { "TANK", "HEALER", "DAMAGER", "DAMAGER", "DAMAGER" }
local FAKE_RAID_ROLES = { "TANK", "TANK", "HEALER", "HEALER", "HEALER", "HEALER",
    "DAMAGER", "DAMAGER", "DAMAGER", "DAMAGER", "DAMAGER", "DAMAGER", "DAMAGER", "DAMAGER",
    "DAMAGER", "DAMAGER", "DAMAGER", "DAMAGER", "DAMAGER", "DAMAGER", "DAMAGER", "DAMAGER",
    "DAMAGER", "DAMAGER", "DAMAGER" }

local FAKE_BUFF_ICONS = {
    136034,  -- Spell_Holy_Renew
    135940,  -- Spell_Holy_PowerWordShield
    136081,  -- Spell_Nature_Rejuvenation
}
local FAKE_DEBUFF_ICONS = {
    136207,  -- Spell_Shadow_ShadowWordPain
    136130,  -- Ability_Creature_Cursed_01
    136067,  -- Spell_Nature_NullifyPoison_02
}

-- Distribution tables — keyed by party frame index (1–5).
-- Each entry lists what preview indicators that frame should show.
-- Only used for party (first 5 frames); raid frames get no extras.
local PREVIEW_INDICATORS = {
    [1] = { leader = true, targetHighlight = true, threatBorder = true, buffs = 1 },
    [2] = { readyCheck = true, raidMarker = 1, debuffs = 2, buffs = 1 },
    [3] = { phaseIcon = true, resurrection = true, debuffs = 1, defensiveIndicator = true },
    [4] = { dispelOverlay = true, summonPending = true, debuffs = 3 },
    [5] = { raidMarker = 8, buffs = 2 },
}

local function GetFakeHealthPct(index)
    -- Varied health levels for visual interest
    local patterns = { 100, 85, 65, 45, 92, 78, 30, 95, 88, 55,
                       72, 100, 80, 60, 90, 75, 40, 98, 82, 68,
                       0, 100, 70, 50, 95, 85, 35, 100, 77, 62,
                       88, 42, 100, 73, 56, 91, 100, 83, 47, 100 }
    return patterns[((index - 1) % #patterns) + 1]
end

---------------------------------------------------------------------------
-- TEST MODE: Create fake frames for solo testing
---------------------------------------------------------------------------
local function CreateTestFrame(parent, index, totalCount, classToken, name, role, healthPct)
    local db = GetDB()
    if not db then return nil end

    local GF = ns.QUI_GroupFrames
    if not GF then return nil end

    local mode
    if totalCount <= 5 then mode = "party"
    elseif totalCount <= 15 then mode = "small"
    elseif totalCount <= 25 then mode = "medium"
    else mode = "large"
    end

    local dims = db.dimensions
    local w, h
    if mode == "party" then w, h = dims.partyWidth or 200, dims.partyHeight or 40
    elseif mode == "small" then w, h = dims.smallRaidWidth or 180, dims.smallRaidHeight or 36
    elseif mode == "medium" then w, h = dims.mediumRaidWidth or 160, dims.mediumRaidHeight or 30
    else w, h = dims.largeRaidWidth or 140, dims.largeRaidHeight or 24
    end

    local frame = CreateFrame("Frame", "QUI_TestFrame" .. index, parent, "BackdropTemplate")
    frame:SetSize(w, h)

    -- Visuals matching DecorateGroupFrame
    local general = db.general
    local borderPx = general and general.borderSize or 1
    local borderSize = borderPx > 0 and (QUICore.Pixels and QUICore:Pixels(borderPx, frame) or borderPx) or 0
    local px = QUICore.GetPixelSize and QUICore:GetPixelSize(frame) or 1

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = borderSize > 0 and "Interface\\Buttons\\WHITE8x8" or nil,
        edgeSize = borderSize > 0 and borderSize or nil,
    })
    -- Background color matching groupframes.lua behavior
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
    frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgAlpha)
    if borderSize > 0 then
        frame:SetBackdropBorderColor(0, 0, 0, 1)
    end

    -- Power bar
    local powerSettings = db.power
    local showPower = powerSettings and powerSettings.showPowerBar ~= false
    local powerHeight = showPower and (powerSettings.powerBarHeight or 4) or 0
    local separatorHeight = showPower and px or 0

    -- Health bar
    local LSM = LibStub("LibSharedMedia-3.0")
    local textureName = general and general.texture or "Quazii v5"
    local texturePath = LSM:Fetch("statusbar", textureName) or "Interface\\TargetingFrame\\UI-StatusBar"

    local healthBar = CreateFrame("StatusBar", nil, frame)
    healthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", borderSize, -borderSize)
    healthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize + powerHeight + separatorHeight)
    healthBar:SetStatusBarTexture(texturePath)
    healthBar:SetMinMaxValues(0, 100)
    healthBar:SetValue(healthPct)
    healthBar:SetAlpha(healthOpacity)

    -- Class color on health bar
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

    -- Power bar
    if showPower then
        local powerBar = CreateFrame("StatusBar", nil, frame)
        powerBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", borderSize, borderSize)
        powerBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize)
        powerBar:SetHeight(powerHeight)
        powerBar:SetStatusBarTexture(texturePath)
        powerBar:SetMinMaxValues(0, 100)
        powerBar:SetValue(100)
        powerBar:SetStatusBarColor(0, 0.5, 1, 1)

        local powerBg = powerBar:CreateTexture(nil, "BACKGROUND")
        powerBg:SetAllPoints()
        powerBg:SetTexture("Interface\\Buttons\\WHITE8x8")
        powerBg:SetVertexColor(0.05, 0.05, 0.05, 0.9)

        local sep = powerBar:CreateTexture(nil, "OVERLAY")
        sep:SetHeight(px)
        sep:SetPoint("BOTTOMLEFT", powerBar, "TOPLEFT", 0, 0)
        sep:SetPoint("BOTTOMRIGHT", powerBar, "TOPRIGHT", 0, 0)
        sep:SetTexture("Interface\\Buttons\\WHITE8x8")
        sep:SetVertexColor(0, 0, 0, 1)
    end

    -- Text frame
    local textFrame = CreateFrame("Frame", nil, frame)
    textFrame:SetAllPoints()
    textFrame:SetFrameLevel(healthBar:GetFrameLevel() + 3)

    local fontName = general and general.font or "Quazii"
    local fontPath = LSM:Fetch("font", fontName) or "Fonts\\FRIZQT__.TTF"
    local fontOutline = general and general.fontOutline or "OUTLINE"

    -- Anchor map for text positioning (two-point horizontal anchoring for proper justify)
    local ANCHOR_MAP = {
        LEFT       = { leftPoint = "LEFT",       rightPoint = "RIGHT",        justify = "LEFT",   justifyV = "MIDDLE" },
        RIGHT      = { leftPoint = "LEFT",       rightPoint = "RIGHT",        justify = "RIGHT",  justifyV = "MIDDLE" },
        CENTER     = { leftPoint = "LEFT",       rightPoint = "RIGHT",        justify = "CENTER", justifyV = "MIDDLE" },
        TOPLEFT    = { leftPoint = "TOPLEFT",    rightPoint = "TOPRIGHT",     justify = "LEFT",   justifyV = "TOP" },
        TOPRIGHT   = { leftPoint = "TOPLEFT",    rightPoint = "TOPRIGHT",     justify = "RIGHT",  justifyV = "TOP" },
        TOP        = { leftPoint = "TOPLEFT",    rightPoint = "TOPRIGHT",     justify = "CENTER", justifyV = "TOP" },
        BOTTOMLEFT = { leftPoint = "BOTTOMLEFT", rightPoint = "BOTTOMRIGHT",  justify = "LEFT",   justifyV = "BOTTOM" },
        BOTTOMRIGHT= { leftPoint = "BOTTOMLEFT", rightPoint = "BOTTOMRIGHT",  justify = "RIGHT",  justifyV = "BOTTOM" },
        BOTTOM     = { leftPoint = "BOTTOMLEFT", rightPoint = "BOTTOMRIGHT",  justify = "CENTER", justifyV = "BOTTOM" },
    }

    -- Name text
    local nameSettings = db.name
    if not nameSettings or nameSettings.showName ~= false then
        local nameAnchorInfo = ANCHOR_MAP[nameSettings and nameSettings.nameAnchor or "LEFT"] or ANCHOR_MAP.LEFT
        local nameOffsetX = nameSettings and nameSettings.nameOffsetX or 4
        local nameOffsetY = nameSettings and nameSettings.nameOffsetY or 0
        local namePadX = math.abs(nameOffsetX)
        local nameText = textFrame:CreateFontString(nil, "OVERLAY")
        nameText:SetFont(fontPath, nameSettings and nameSettings.nameFontSize or 12, fontOutline)
        nameText:SetPoint(nameAnchorInfo.leftPoint, frame, nameAnchorInfo.leftPoint, namePadX, nameOffsetY)
        nameText:SetPoint(nameAnchorInfo.rightPoint, frame, nameAnchorInfo.rightPoint, -namePadX, nameOffsetY)
        nameText:SetJustifyH(nameAnchorInfo.justify)
        nameText:SetJustifyV(nameAnchorInfo.justifyV)
        nameText:SetWordWrap(false)

        local displayName = name
        local maxLen = nameSettings and nameSettings.maxNameLength or 10
        if maxLen > 0 and #displayName > maxLen then
            displayName = displayName:sub(1, maxLen)
        end
        nameText:SetText(displayName)

        -- Name color
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

    -- Health text
    local healthSettings = db.health
    if not healthSettings or healthSettings.showHealthText ~= false then
        local healthAnchorInfo = ANCHOR_MAP[healthSettings and healthSettings.healthAnchor or "RIGHT"] or ANCHOR_MAP.RIGHT
        local healthOffsetX = healthSettings and healthSettings.healthOffsetX or -4
        local healthOffsetY = healthSettings and healthSettings.healthOffsetY or 0
        local healthPadX = math.abs(healthOffsetX)
        local healthText = textFrame:CreateFontString(nil, "OVERLAY")
        healthText:SetFont(fontPath, healthSettings and healthSettings.healthFontSize or 12, fontOutline)
        healthText:SetPoint(healthAnchorInfo.leftPoint, frame, healthAnchorInfo.leftPoint, healthPadX, healthOffsetY)
        healthText:SetPoint(healthAnchorInfo.rightPoint, frame, healthAnchorInfo.rightPoint, -healthPadX, healthOffsetY)
        healthText:SetJustifyH(healthAnchorInfo.justify)
        healthText:SetJustifyV(healthAnchorInfo.justifyV)
        healthText:SetWordWrap(false)

        if healthPct == 0 then
            healthText:SetText("Dead")
            healthText:SetTextColor(0.5, 0.5, 0.5, 1)
            healthBar:SetStatusBarColor(0.5, 0.5, 0.5, 1)
        else
            -- Format based on display style
            local style = healthSettings and healthSettings.healthDisplayStyle or "percent"
            local fakeHP = healthPct * 1000  -- Simulate ~100k max HP
            local fakeMax = 100000
            if style == "percent" then
                healthText:SetText(healthPct .. "%")
            elseif style == "absolute" then
                healthText:SetText(string.format("%.0fK", fakeHP / 1000))
            elseif style == "both" then
                healthText:SetText(string.format("%.0fK", fakeHP / 1000) .. " | " .. healthPct .. "%")
            elseif style == "deficit" then
                local deficit = fakeMax - fakeHP
                if deficit > 0 then
                    healthText:SetText("-" .. string.format("%.0fK", deficit / 1000))
                else
                    healthText:SetText("")
                end
            else
                healthText:SetText(healthPct .. "%")
            end

            -- Health text color
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

    -- Role icon
    local indSettings = db.indicators
    if indSettings and indSettings.showRoleIcon ~= false then
        local roleIcon = textFrame:CreateTexture(nil, "OVERLAY")
        roleIcon:SetSize(indSettings.roleIconSize or 12, indSettings.roleIconSize or 12)
        roleIcon:SetPoint(indSettings.roleIconAnchor or "TOPLEFT", frame, indSettings.roleIconAnchor or "TOPLEFT", 2, -2)
        local ROLE_ATLAS = { TANK = "roleicon-tiny-tank", HEALER = "roleicon-tiny-healer", DAMAGER = "roleicon-tiny-dps" }
        local atlas = ROLE_ATLAS[role]
        if atlas then
            roleIcon:SetAtlas(atlas)
        else
            roleIcon:Hide()
        end
    end

    ---------------------------------------------------------------------------
    -- PREVIEW INDICATORS / OVERLAYS / AURAS
    -- Only rendered for party-size previews (first 5 frames).
    ---------------------------------------------------------------------------
    local prev = totalCount <= 5 and PREVIEW_INDICATORS[index]
    local baseLevel = frame:GetFrameLevel()

    if prev and indSettings then
        -- Ready Check icon
        if prev.readyCheck and indSettings.showReadyCheck ~= false then
            local rc = textFrame:CreateTexture(nil, "OVERLAY")
            rc:SetSize(16, 16)
            rc:SetPoint("CENTER", frame, "CENTER", 0, 0)
            rc:SetTexture("INTERFACE\\RAIDFRAME\\ReadyCheck-Ready")
        end

        -- Resurrection icon
        if prev.resurrection and indSettings.showResurrection ~= false then
            local ri = textFrame:CreateTexture(nil, "OVERLAY")
            ri:SetSize(16, 16)
            ri:SetPoint("CENTER", frame, "CENTER", 0, 0)
            ri:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")
        end

        -- Summon Pending icon
        if prev.summonPending and indSettings.showSummonPending ~= false then
            local si = textFrame:CreateTexture(nil, "OVERLAY")
            si:SetSize(20, 20)
            si:SetPoint("CENTER", frame, "CENTER", 16, 0)
            si:SetTexture("Interface\\RaidFrame\\Raid-Icon-SummonPending")
        end

        -- Leader icon
        if prev.leader and indSettings.showLeaderIcon ~= false then
            local li = textFrame:CreateTexture(nil, "OVERLAY")
            li:SetSize(12, 12)
            li:SetPoint("TOP", frame, "TOP", 0, 6)
            li:SetAtlas("groupfinder-icon-leader")
        end

        -- Raid Target Marker
        if prev.raidMarker and indSettings.showTargetMarker ~= false then
            local rm = textFrame:CreateTexture(nil, "OVERLAY")
            rm:SetSize(14, 14)
            rm:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
            rm:SetAtlas("raidtargetingicon_" .. prev.raidMarker)
        end

        -- Phase icon
        if prev.phaseIcon and indSettings.showPhaseIcon ~= false then
            local pi = textFrame:CreateTexture(nil, "OVERLAY")
            pi:SetSize(16, 16)
            pi:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 2, 2)
            pi:SetAtlas("nameplates-icon-flag-horde")
        end

        -- Threat Border — edge + tinted fill over the whole frame
        if prev.threatBorder and indSettings.showThreatBorder ~= false then
            local threatOverlay = CreateFrame("Frame", nil, frame, "BackdropTemplate")
            threatOverlay:SetAllPoints()
            threatOverlay:SetFrameLevel(baseLevel + 5)
            local tc = indSettings.threatColor or { 1, 0, 0, 0.8 }
            threatOverlay:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = borderSize > 0 and borderSize * 2 or px * 2,
            })
            threatOverlay:SetBackdropColor(tc[1], tc[2], tc[3], indSettings.threatFillOpacity or 0.15)
            threatOverlay:SetBackdropBorderColor(tc[1], tc[2], tc[3], tc[4] or 0.8)
        end
    end

    -- Healer overlays
    local healerSettings = db.healer
    if prev and healerSettings then
        -- Target Highlight — edge + tinted fill
        if prev.targetHighlight then
            local th = healerSettings.targetHighlight
            if th and th.enabled ~= false then
                local highlight = CreateFrame("Frame", nil, frame, "BackdropTemplate")
                highlight:SetPoint("TOPLEFT", -px, px)
                highlight:SetPoint("BOTTOMRIGHT", px, -px)
                highlight:SetFrameLevel(baseLevel + 4)
                local hc = th.color or { 1, 1, 1, 0.6 }
                highlight:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8x8",
                    edgeFile = "Interface\\Buttons\\WHITE8x8",
                    edgeSize = px * 2,
                })
                highlight:SetBackdropColor(hc[1], hc[2], hc[3], th.fillOpacity or 0.12)
                highlight:SetBackdropBorderColor(hc[1], hc[2], hc[3], hc[4] or 0.6)
            end
        end

        -- Dispel Overlay — edge + tinted fill
        if prev.dispelOverlay then
            local dsp = healerSettings.dispelOverlay
            if dsp and dsp.enabled ~= false then
                local dispel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
                dispel:SetPoint("TOPLEFT", -px, px)
                dispel:SetPoint("BOTTOMRIGHT", px, -px)
                dispel:SetFrameLevel(baseLevel + 6)
                local dc = dsp.color or { 0.26, 0.54, 1, 0.8 }
                local opacity = dsp.opacity or 0.8
                dispel:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8x8",
                    edgeFile = "Interface\\Buttons\\WHITE8x8",
                    edgeSize = px * 3,
                })
                dispel:SetBackdropColor(dc[1], dc[2], dc[3], dsp.fillOpacity or 0.18)
                dispel:SetBackdropBorderColor(dc[1], dc[2], dc[3], opacity)
            end
        end
    end

    -- Defensive indicator preview
    if prev and prev.defensiveIndicator then
        local healerSettings = db.healer
        local defSettings = healerSettings and healerSettings.defensiveIndicator
        if defSettings and defSettings.enabled ~= false then
            local iconSize = defSettings.iconSize or 16
            local position = defSettings.position or "CENTER"
            local offsetX = defSettings.offsetX or 0
            local offsetY = defSettings.offsetY or 0

            local defIcon = CreateFrame("Frame", nil, frame, "BackdropTemplate")
            defIcon:SetSize(iconSize, iconSize)
            defIcon:SetPoint(position, frame, position, offsetX, offsetY)
            defIcon:SetFrameLevel(baseLevel + 10)
            defIcon:SetBackdrop({
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = px,
            })
            defIcon:SetBackdropBorderColor(0, 0.8, 0, 1)

            local icon = defIcon:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            icon:SetTexture(135936) -- Spell_Holy_SealOfProtection (Ironbark-like)
        end
    end

    -- Aura icons (buffs & debuffs; matches runtime: frame + 8)
    local auraSettings = db.auras
    if prev and auraSettings then
        local auraLevel = baseLevel + 8

        -- Debuff icons (anchored BOTTOMRIGHT, growing LEFT)
        if prev.debuffs and auraSettings.showDebuffs ~= false then
            local count = math.min(prev.debuffs, auraSettings.maxDebuffs or 3)
            local size = auraSettings.debuffIconSize or 16
            for i = 1, count do
                local iconFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
                iconFrame:SetSize(size, size)
                iconFrame:SetFrameLevel(auraLevel)
                iconFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -((i - 1) * (size + 1)) - 1, 1)
                iconFrame:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8x8",
                    edgeFile = "Interface\\Buttons\\WHITE8x8",
                    edgeSize = 1,
                })
                iconFrame:SetBackdropBorderColor(0.8, 0, 0, 1) -- red debuff border
                iconFrame:SetBackdropColor(0, 0, 0, 1)

                local icon = iconFrame:CreateTexture(nil, "ARTWORK")
                icon:SetPoint("TOPLEFT", 1, -1)
                icon:SetPoint("BOTTOMRIGHT", -1, 1)
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                icon:SetTexture(FAKE_DEBUFF_ICONS[((i - 1) % #FAKE_DEBUFF_ICONS) + 1])

                -- Stack count on second icon
                if i == 2 then
                    local stack = iconFrame:CreateFontString(nil, "OVERLAY")
                    stack:SetFont(fontPath, math.max(size * 0.55, 8), "OUTLINE")
                    stack:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 0, 0)
                    stack:SetText("3")
                end
            end
        end

        -- Buff icons (anchored TOPLEFT, growing RIGHT)
        if prev.buffs and auraSettings.showBuffs then
            local count = math.min(prev.buffs, auraSettings.maxBuffs or 3)
            local size = auraSettings.buffIconSize or 14
            for i = 1, count do
                local iconFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
                iconFrame:SetSize(size, size)
                iconFrame:SetFrameLevel(auraLevel)
                iconFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", ((i - 1) * (size + 1)) + 1, -1)
                iconFrame:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8x8",
                    edgeFile = "Interface\\Buttons\\WHITE8x8",
                    edgeSize = 1,
                })
                iconFrame:SetBackdropBorderColor(0, 0.6, 0, 1) -- green buff border
                iconFrame:SetBackdropColor(0, 0, 0, 1)

                local icon = iconFrame:CreateTexture(nil, "ARTWORK")
                icon:SetPoint("TOPLEFT", 1, -1)
                icon:SetPoint("BOTTOMRIGHT", -1, 1)
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                icon:SetTexture(FAKE_BUFF_ICONS[((i - 1) % #FAKE_BUFF_ICONS) + 1])
            end
        end
    end

    frame:Show()
    return frame
end

local function DestroyTestFrames()
    -- Clean up private aura placeholders
    local PA = ns.QUI_GroupFramePrivateAuras
    if PA and PA.CleanupTestFrames then
        PA:CleanupTestFrames()
    end

    for _, frame in ipairs(testFrames) do
        frame:Hide()
        frame:SetParent(nil)
    end
    wipe(testFrames)
    testContainer = nil
end

---------------------------------------------------------------------------
-- TEST MODE: Toggle
---------------------------------------------------------------------------
function QUI_GFEM:EnableTestMode(previewType)
    if isTestMode then self:DisableTestMode(true) end  -- true = switching, don't exit edit mode

    local db = GetDB()
    if not db then return end

    isTestMode = true
    self._lastTestPreviewType = previewType  -- remember for refresh

    local GF = ns.QUI_GroupFrames
    if GF then GF.testMode = true end

    -- Determine count
    local count
    if previewType == "raid" then
        count = db.testMode and db.testMode.raidCount or 25
    else
        count = db.testMode and db.testMode.partyCount or 5
    end

    -- Create container — anchor to mover if edit mode is active, otherwise UIParent
    local container = CreateFrame("Frame", nil, UIParent)
    if isEditMode then
        -- In non-unified mode, anchor to the mover matching preview type
        local targetMover = groupMover
        if not db.unifiedPosition and previewType == "raid" and raidMover then
            targetMover = raidMover
        end
        if targetMover then
            container:SetPoint("CENTER", targetMover, "CENTER", 0, 0)
        else
            local position = db.position
            container:SetPoint("CENTER", UIParent, "CENTER", position and position.offsetX or -400, position and position.offsetY or 0)
        end
    else
        -- Not in edit mode: use the appropriate position table
        local posKey = (not db.unifiedPosition and previewType == "raid") and "raidPosition" or "position"
        local position = db[posKey]
        container:SetPoint("CENTER", UIParent, "CENTER", position and position.offsetX or -400, position and position.offsetY or 0)
    end
    container:Show()
    testContainer = container  -- store direct reference
    table.insert(testFrames, container)

    -- Create test frames
    local layout = db.layout
    local spacing = layout and layout.spacing or 2
    local grow = layout and layout.growDirection or "DOWN"
    local groupGrowRight = (layout and layout.groupGrowDirection or "RIGHT") == "RIGHT"
    local groupSpacing = layout and layout.groupSpacing or 10
    local horizontal = (grow == "LEFT" or grow == "RIGHT")

    local framesPerGroup = 5
    local numGroups = math.ceil(count / framesPerGroup)

    -- Determine frame dimensions for the current mode
    local mode
    if count <= 5 then mode = "party"
    elseif count <= 15 then mode = "small"
    elseif count <= 25 then mode = "medium"
    else mode = "large"
    end

    local dims = db.dimensions
    local frameW, frameH
    if mode == "party" then frameW, frameH = dims.partyWidth or 200, dims.partyHeight or 40
    elseif mode == "small" then frameW, frameH = dims.smallRaidWidth or 180, dims.smallRaidHeight or 36
    elseif mode == "medium" then frameW, frameH = dims.mediumRaidWidth or 160, dims.mediumRaidHeight or 30
    else frameW, frameH = dims.largeRaidWidth or 140, dims.largeRaidHeight or 24
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

            local testFrame = CreateTestFrame(container, index, count, classToken, name, role, healthPct)
            if testFrame then
                local col = g - 1
                local row = i - 1
                local xOff, yOff, anchor

                if horizontal then
                    -- Frames within a group go left/right; groups stack down
                    yOff = -(col * (frameH + groupSpacing))
                    if grow == "RIGHT" then
                        anchor = "TOPLEFT"
                        xOff = row * (frameW + spacing)
                    else -- LEFT
                        anchor = "TOPRIGHT"
                        xOff = -(row * (frameW + spacing))
                    end
                else
                    -- Frames within a group go up/down; groups go left/right
                    if grow == "DOWN" then
                        anchor = "TOPLEFT"
                        yOff = -(row * (frameH + spacing))
                    else -- UP
                        anchor = "BOTTOMLEFT"
                        yOff = row * (frameH + spacing)
                    end
                    xOff = groupGrowRight and (col * (frameW + groupSpacing)) or -(col * (frameW + groupSpacing))
                end

                testFrame:SetPoint(anchor, container, anchor, xOff, yOff)
                table.insert(testFrames, testFrame)

                -- Attach private aura placeholders
                local PA = ns.QUI_GroupFramePrivateAuras
                if PA and PA.SetupTestFrame then
                    PA:SetupTestFrame(testFrame)
                end
            end
        end
    end

    -- Set container size
    local totalW, totalH
    if horizontal then
        totalW = framesPerGroup * frameW + (framesPerGroup - 1) * spacing
        totalH = numGroups * frameH + (numGroups - 1) * groupSpacing
    else
        totalW = numGroups * frameW + (numGroups - 1) * groupSpacing
        totalH = framesPerGroup * frameH + (framesPerGroup - 1) * spacing
    end
    container:SetSize(totalW, totalH)

    -- If edit mode is active, sync the mover size and re-anchor
    if isEditMode then
        self:SyncMoverToContent()
    end
end

function QUI_GFEM:DisableTestMode(switching)
    DestroyTestFrames()
    isTestMode = false
    self._lastTestPreviewType = nil

    local GF = ns.QUI_GroupFrames
    if GF then GF.testMode = false end

    -- If edit mode is active, there's no real group, and we're not just
    -- switching preview types, exit edit mode — the mover has nothing to
    -- control.
    if not switching and isEditMode and not IsInGroup() and not IsInRaid() then
        self:DisableEditMode()
    end
end

function QUI_GFEM:IsTestMode()
    return isTestMode
end

function QUI_GFEM:ToggleTestMode(previewType)
    if isTestMode then
        if self._lastTestPreviewType == previewType then
            -- Same type — toggle off
            self:DisableTestMode()
        else
            -- Different type — switch to the new type
            self:EnableTestMode(previewType or "party")
        end
    else
        self:EnableTestMode(previewType or "party")
    end
end

-- Rebuild test frames with current settings (called when options change).
-- Uses leading-edge + trailing-edge throttle: fires immediately on first
-- call, then suppresses rapid calls (slider drags) for a cooldown period
-- and fires one final rebuild when the cooldown expires.
local refreshTimer = nil
local refreshPending = false
function QUI_GFEM:RefreshTestMode()
    if not isTestMode then return end

    if refreshTimer then
        -- Inside cooldown window — just mark that another refresh is needed
        refreshPending = true
        return
    end

    -- Leading edge: fire immediately
    local previewType = self._lastTestPreviewType or "party"
    self:EnableTestMode(previewType)

    -- Start cooldown to suppress rapid-fire rebuilds (slider drags)
    refreshTimer = C_Timer.NewTimer(0.2, function()
        refreshTimer = nil
        if refreshPending then
            refreshPending = false
            if not isTestMode then return end
            local pt = self._lastTestPreviewType or "party"
            self:EnableTestMode(pt)
        end
    end)
end

---------------------------------------------------------------------------
-- EDIT MODE: Dragging + overlays
--
-- We create a single non-secure mover frame parented to UIParent.
-- During edit mode, headers and test containers are anchored TO the mover
-- so everything moves together.  On exit, headers are re-anchored to
-- UIParent at the saved offset.
---------------------------------------------------------------------------

-- Calculate the visual bounds of a header from its children
local function GetHeaderBounds(header, db)
    if not header then return 0, 0 end

    -- Count visible children
    local childCount = 0
    local i = 1
    while true do
        local child = header:GetAttribute("child" .. i)
        if not child then break end
        childCount = childCount + 1
        i = i + 1
    end

    if childCount == 0 then return 0, 0 end

    local layout = db and db.layout
    local dims = db and db.dimensions
    local spacing = layout and layout.spacing or 2
    local groupSpacing = layout and layout.groupSpacing or 10

    -- Determine mode and frame size
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

-- Helper: Create a nudge button (matches unitframe_editmode chevron style)
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
        line1:SetColorTexture(0.204, 0.827, 0.6, 1)
        line2:SetColorTexture(0.204, 0.827, 0.6, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        line1:SetColorTexture(1, 1, 1, 0.9)
        line2:SetColorTexture(1, 1, 1, 0.9)
    end)

    btn:SetScript("OnClick", function()
        local shift = IsShiftKeyDown()
        local step = shift and 10 or 1
        -- Use the mover's stored nudge key so party/raid mover nudge the right position
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

-- Returns the position table for a given mover (or "position" by default).
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
    QUI:DebugPrint(("[GF] SaveMoverPosition(%s): offset=(%d,%d)"):format(
        mover._positionKey or "position", oX, oY))
    return oX, oY
end

-- Helper: determine which mover owns a given header key.
local function GetMoverForHeaderKey(db, hKey)
    if db and not db.unifiedPosition and hKey == "raid" then
        return raidMover
    end
    return groupMover
end

-- Helper: size a single mover to a single header.
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

-- Helper: re-parent a single header to a mover using BOTTOMLEFT offsets.
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

-- Resize the mover(s) to match content and re-anchor all frames.
-- Called after any state change (test mode toggle, settings refresh, edit mode enter).
function QUI_GFEM:SyncMoverToContent()
    if not isEditMode or not groupMover then return end
    if InCombatLockdown() then return end

    local db = GetDB()
    local GF = ns.QUI_GroupFrames
    local unified = not db or db.unifiedPosition ~= false

    if unified then
        -- UNIFIED MODE: single mover for both headers (original behavior)
        local boundsW, boundsH = 0, 0
        local sizeSource = "none"

        if isTestMode and testContainer then
            boundsW = Helpers.SafeValue(testContainer:GetWidth(), 200)
            boundsH = Helpers.SafeValue(testContainer:GetHeight(), 200)
            sizeSource = "testContainer"
        elseif GF then
            if GF.CalculateHeaderSize then
                local memberCount = IsInRaid() and GetNumGroupMembers() or
                    (IsInGroup() and GetNumGroupMembers() or 5)
                if not IsInRaid() then memberCount = math.min(memberCount, 5) end
                boundsW, boundsH = GF.CalculateHeaderSize(db, memberCount)
                sizeSource = ("calc(n=%d)"):format(memberCount)
            end
            if boundsW == 0 or boundsH == 0 then
                for _, hKey in ipairs({"party", "raid"}) do
                    local hdr = GF.headers[hKey]
                    if hdr and hdr:IsShown() then
                        local w = Helpers.SafeValue(hdr:GetWidth(), 0)
                        local h = Helpers.SafeValue(hdr:GetHeight(), 0)
                        if w > boundsW then boundsW = w end
                        if h > boundsH then boundsH = h end
                    end
                end
                if boundsW > 0 and boundsH > 0 then sizeSource = "hdr:GetSize" end
            end
            if boundsW == 0 or boundsH == 0 then
                for _, hKey in ipairs({"party", "raid"}) do
                    local hdr = GF.headers[hKey]
                    if hdr then
                        local w, h = GetHeaderBounds(hdr, db)
                        if w > boundsW then boundsW = w end
                        if h > boundsH then boundsH = h end
                    end
                end
                if boundsW > 0 and boundsH > 0 then sizeSource = "GetHeaderBounds" end
            end
        end

        boundsW = math.max(boundsW, 100)
        boundsH = math.max(boundsH, 40)
        groupMover:SetSize(boundsW, boundsH)
        QUI:DebugPrint(("[GF] SyncMoverToContent: size=(%d,%d) source=%s testMode=%s"):format(
            boundsW, boundsH, sizeSource, tostring(isTestMode)))

        -- Re-parent all headers to the unified mover
        if GF then
            for _, hKey in ipairs({"party", "raid"}) do
                ReparentHeaderToMover(GF.headers[hKey], groupMover)
            end
        end

        if testContainer then
            local tLeft = Helpers.SafeValue(testContainer:GetLeft(), nil)
            local tBottom = Helpers.SafeValue(testContainer:GetBottom(), nil)
            testContainer:SetParent(groupMover)
            testContainer:ClearAllPoints()
            if tLeft and tBottom then
                local mLeft = groupMover:GetLeft()
                local mBottom = groupMover:GetBottom()
                if mLeft and mBottom then
                    testContainer:SetPoint("BOTTOMLEFT", groupMover, "BOTTOMLEFT",
                        tLeft - mLeft, tBottom - mBottom)
                else
                    testContainer:SetPoint("CENTER", groupMover, "CENTER", 0, 0)
                end
            else
                testContainer:SetPoint("CENTER", groupMover, "CENTER", 0, 0)
            end
        end
    else
        -- NON-UNIFIED MODE: party mover + raid mover
        if GF then
            local partyHdr = GF.headers and GF.headers.party
            if partyHdr then
                local pw, ph = SizeMoverToHeader(groupMover, partyHdr, db)
                groupMover:SetSize(math.max(pw, 100), math.max(ph, 40))
                ReparentHeaderToMover(partyHdr, groupMover)
            else
                groupMover:SetSize(200, 40)
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

        -- Test container: anchor to the mover matching the preview type
        if testContainer then
            local targetMover = groupMover
            if self._lastTestPreviewType == "raid" and raidMover then
                targetMover = raidMover
            end
            local tw = Helpers.SafeValue(testContainer:GetWidth(), 200)
            local th = Helpers.SafeValue(testContainer:GetHeight(), 200)
            targetMover:SetSize(math.max(tw, 100), math.max(th, 40))

            local tLeft = Helpers.SafeValue(testContainer:GetLeft(), nil)
            local tBottom = Helpers.SafeValue(testContainer:GetBottom(), nil)
            testContainer:SetParent(targetMover)
            testContainer:ClearAllPoints()
            if tLeft and tBottom then
                local mLeft = targetMover:GetLeft()
                local mBottom = targetMover:GetBottom()
                if mLeft and mBottom then
                    testContainer:SetPoint("BOTTOMLEFT", targetMover, "BOTTOMLEFT",
                        tLeft - mLeft, tBottom - mBottom)
                else
                    testContainer:SetPoint("CENTER", targetMover, "CENTER", 0, 0)
                end
            else
                testContainer:SetPoint("CENTER", targetMover, "CENTER", 0, 0)
            end
        end
    end
end

-- moverType: "unified" (default), "party", or "raid"
local function CreateGroupMover(moverType)
    moverType = moverType or "unified"
    local frameName = moverType == "raid" and "QUI_RaidFramesMover" or "QUI_GroupFramesMover"
    local label = moverType == "raid" and "Raid Frames"
        or moverType == "party" and "Party Frames"
        or "Group Frames"
    local posKey = moverType == "raid" and "raidPosition" or "position"
    local nudgeKey = moverType == "raid" and "raid" or "party"

    local mover = CreateFrame("Frame", frameName, UIParent)
    mover:SetFrameStrata("HIGH")
    mover:SetClampedToScreen(true)
    mover:SetMovable(true)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")

    -- Store metadata for SaveMoverPosition, UpdateMoverPositionText, NudgeHeader
    mover._label = label
    mover._positionKey = posKey
    mover._nudgeKey = nudgeKey
    mover._moverType = moverType

    local px = QUICore.GetPixelSize and QUICore:GetPixelSize(mover) or 1

    -- Border overlay: a separate frame at a high frame level so it renders
    -- on top of child content (test frames, headers) that gets re-parented
    -- to the mover during edit mode.
    local border = CreateFrame("Frame", nil, mover, "BackdropTemplate")
    border:SetAllPoints()
    border:SetFrameLevel(mover:GetFrameLevel() + 100)
    border:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px * 2,
    })
    border:SetBackdropColor(0.2, 0.8, 1, 0.08)
    border:SetBackdropBorderColor(0.2, 0.8, 1, 1)
    border:EnableMouse(false)  -- clicks pass through to the mover
    mover.border = border

    -- Position / label text above the mover (on the border overlay so it's on top)
    local fontPath = LibStub("LibSharedMedia-3.0"):Fetch("font", "Quazii") or "Fonts\\FRIZQT__.TTF"
    local posText = border:CreateFontString(nil, "OVERLAY")
    posText:SetFont(fontPath, 10, "OUTLINE")
    posText:SetPoint("CENTER", mover, "CENTER", 0, 0)
    posText:SetTextColor(0.2, 0.8, 1, 1)
    mover.posText = posText

    -- Hint text
    local hint = border:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetFont(fontPath, 9, "OUTLINE")
    hint:SetPoint("TOP", mover, "BOTTOM", 0, -4)
    hint:SetTextColor(0.6, 0.6, 0.6, 1)
    hint:SetText("Drag to move  |  Arrows to nudge (Shift=10px)")
    mover.hint = hint

    -- Nudge buttons
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

    -- Click to select (re-select after clicking another edit mode element)
    mover:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            QUICore:SelectEditModeElement("groupframes", self._nudgeKey or "mover")
        end
    end)

    -- Drag handlers
    mover:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        -- Block dragging when locked by anchoring system
        if _G.QUI_IsFrameLocked and _G.QUI_IsFrameLocked(self) then return end
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

-- Re-parent headers back to UIParent and restore saved offset (edit mode exit)
local function RestoreHeaderAnchors()
    if InCombatLockdown() then return end

    local GF = ns.QUI_GroupFrames
    if not GF then return end

    local db = GetDB()
    local unified = not db or db.unifiedPosition ~= false

    for _, hKey in ipairs({"party", "raid"}) do
        local hdr = GF.headers[hKey]
        if hdr then
            -- Determine position table for this header
            local pos
            if unified or hKey == "party" then
                pos = db and db.position
            else
                pos = db and db.raidPosition
            end
            local oX = pos and pos.offsetX or -400
            local oY = pos and pos.offsetY or 0

            hdr:SetParent(UIParent)
            hdr:ClearAllPoints()

            -- Recompute header size for current roster
            if GF.CalculateHeaderSize and db then
                local count
                if hKey == "party" then
                    count = IsInGroup() and not IsInRaid() and GetNumGroupMembers() or 5
                else
                    count = IsInRaid() and GetNumGroupMembers() or 25
                    count = math.max(count, 5)
                end
                local w, h = GF.CalculateHeaderSize(db, count)
                hdr:SetSize(w, h)
                QUI:DebugPrint(("[GF] RestoreHeaderAnchors %s: pos=(%d,%d) size=(%d,%d)"):format(hKey, oX, oY, w, h))
            end

            hdr:SetPoint("CENTER", UIParent, "CENTER", oX, oY)
        end
    end
end

-- Apply locked/unlocked styling to a single mover.
local function ApplyMoverLockedStyle(mover, isLocked)
    if not mover or not mover.border then return end

    local border = mover.border
    if isLocked then
        border:SetBackdropColor(0.5, 0.5, 0.5, 0.3)
        border:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
        if mover.posText then
            mover.posText:SetTextColor(0.5, 0.5, 0.5, 1)
            mover.posText:SetText((mover._label or "Group Frames") .. "  (Locked)")
        end
        if mover.hint then mover.hint:Hide() end
        if mover.nudgeUp then mover.nudgeUp:Hide() end
        if mover.nudgeDown then mover.nudgeDown:Hide() end
        if mover.nudgeLeft then mover.nudgeLeft:Hide() end
        if mover.nudgeRight then mover.nudgeRight:Hide() end
        mover:EnableMouse(false)
    else
        border:SetBackdropColor(0.2, 0.8, 1, 0.08)
        border:SetBackdropBorderColor(0.2, 0.8, 1, 1)
        if mover.posText then
            mover.posText:SetTextColor(0.2, 0.8, 1, 1)
            local pos = GetMoverPositionTable(mover)
            UpdateMoverPositionText(mover, pos and pos.offsetX or 0, pos and pos.offsetY or 0)
        end
        if mover.hint then mover.hint:Show() end
        if mover.nudgeUp then mover.nudgeUp:Show() end
        if mover.nudgeDown then mover.nudgeDown:Show() end
        if mover.nudgeLeft then mover.nudgeLeft:Show() end
        if mover.nudgeRight then mover.nudgeRight:Show() end
        mover:EnableMouse(true)
    end
end

-- Check if a mover is locked by the anchoring system.
local function IsMoverLocked(mover, headerKey)
    if not _G.QUI_IsFrameLocked then return false end
    if _G.QUI_IsFrameLocked(mover) then return true end
    local GF = ns.QUI_GroupFrames
    if GF and GF.headers and headerKey then
        local hdr = GF.headers[headerKey]
        if hdr and _G.QUI_IsFrameLocked(hdr) then return true end
    end
    return false
end

-- Apply locked (grey) or unlocked (blue) styling to the group mover(s) based on
-- whether the anchoring system has an active override for party/raid frames.
function QUI_GFEM:UpdateMoverLockedState()
    if not groupMover then return end

    local db = GetDB()
    local unified = not db or db.unifiedPosition ~= false

    if unified then
        -- Unified: check both headers
        local locked = IsMoverLocked(groupMover, "party") or IsMoverLocked(groupMover, "raid")
        ApplyMoverLockedStyle(groupMover, locked)
    else
        -- Non-unified: check each independently
        ApplyMoverLockedStyle(groupMover, IsMoverLocked(groupMover, "party"))
        if raidMover then
            ApplyMoverLockedStyle(raidMover, IsMoverLocked(raidMover, "raid"))
        end
    end
end

function QUI_GFEM:EnableEditMode(previewType)
    if InCombatLockdown() then return end

    local wantType = previewType or "party"

    -- Already in edit mode — switch preview type if different, else no-op
    if isEditMode then
        if self._lastTestPreviewType ~= wantType then
            self:EnableTestMode(wantType)
            -- SyncMoverToContent is called at the end of EnableTestMode
        end
        return
    end

    -- Fresh entry into edit mode
    isEditMode = true

    local GF = ns.QUI_GroupFrames
    if not GF then return end
    GF.editMode = true

    -- If not in a group, show test frames so there's something to see.
    if not IsInGroup() and not IsInRaid() then
        if not isTestMode or self._lastTestPreviewType ~= wantType then
            self:EnableTestMode(wantType)
        end
    end

    local db = GetDB()
    local unified = not db or db.unifiedPosition ~= false

    -- Helper: position a mover at its saved position (or derive from header)
    local function PositionMover(mover, headerKey)
        local pos = GetMoverPositionTable(mover)
        local oX = pos and pos.offsetX or -400
        local oY = pos and pos.offsetY or 0

        -- If the header is visible, derive from its actual screen center
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

    if unified then
        -- UNIFIED: single mover (original behavior)
        if not groupMover then
            groupMover = CreateGroupMover("unified")
        end
        local oX, oY = PositionMover(groupMover, "party")
        -- In unified mode, also check raid header for position derivation
        if GF and GF.headers and GF.headers.raid and GF.headers.raid:IsShown() then
            oX, oY = PositionMover(groupMover, "raid")
        end
        QUI:DebugPrint(("[GF] EnableEditMode(unified): mover pos=(%d,%d)"):format(oX, oY))
    else
        -- NON-UNIFIED: separate party + raid movers
        if not groupMover then
            groupMover = CreateGroupMover("party")
        end
        if not raidMover then
            raidMover = CreateGroupMover("raid")
        end
        local pX, pY = PositionMover(groupMover, "party")
        local rX, rY = PositionMover(raidMover, "raid")
        QUI:DebugPrint(("[GF] EnableEditMode(split): party=(%d,%d) raid=(%d,%d)"):format(pX, pY, rX, rY))
    end

    -- Size the mover(s) and anchor all content
    self:SyncMoverToContent()

    -- Check if group frames are locked by the anchoring system
    self:UpdateMoverLockedState()

    -- Hide Blizzard's CompactPartyFrame selection overlay (blue box in Edit Mode)
    -- Use SetAlpha(0) not Hide() — hidden frames return nil from GetRect(),
    -- crashing Blizzard's magnetic snap loop (GetScaledSelectionSides).
    if CompactPartyFrame and CompactPartyFrame.Selection then
        C_Timer.After(0, function()
            if CompactPartyFrame and CompactPartyFrame.Selection then
                CompactPartyFrame.Selection:SetAlpha(0)
            end
        end)
        -- Persistent watcher: Blizzard re-shows Selection on every click/select cycle
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

    -- Hide Blizzard's CompactRaidFrameContainer selection overlay
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

    -- Select the primary mover for arrow key nudging
    QUICore:SelectEditModeElement("groupframes", groupMover and groupMover._nudgeKey or "party")
end

function QUI_GFEM:DisableEditMode()
    if not isEditMode then return end
    isEditMode = false

    -- Stop suppressing Blizzard selection overlays
    if partySelectionWatcher then
        partySelectionWatcher:Hide()
    end
    if raidSelectionWatcher then
        raidSelectionWatcher:Hide()
    end

    local GF = ns.QUI_GroupFrames
    if GF then GF.editMode = false end

    -- Clear keyboard selection
    if QUICore.EditModeSelection and QUICore.EditModeSelection.selectedType == "groupframes" then
        QUICore:ClearEditModeSelection()
    end

    -- Save final position and hide mover(s)
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

    -- Re-anchor headers to UIParent at saved offset
    RestoreHeaderAnchors()

    -- Disable test mode if active
    if isTestMode then
        self:DisableTestMode()
    end
end

function QUI_GFEM:ToggleEditMode(previewType)
    if isEditMode then
        self:DisableEditMode()
    else
        self:EnableEditMode(previewType)
    end
end

function QUI_GFEM:IsEditMode()
    return isEditMode
end

function QUI_GFEM:IsTestMode()
    return isTestMode
end

-- Returns the currently visible frame for anchoring purposes.
-- During edit/test mode this is the mover or test container;
-- outside edit mode returns nil (callers should fall back to headers).
-- Optional frameType ("party" or "raid") returns the correct mover
-- when non-unified mode is active.
function QUI_GFEM:GetActiveFrame(frameType)
    if isEditMode then
        local db = GetDB()
        local unified = not db or db.unifiedPosition ~= false
        if not unified and frameType == "raid" and raidMover then
            return raidMover
        end
        if groupMover then
            return groupMover
        end
    end
    if isTestMode and testContainer then
        return testContainer
    end
    return nil
end

---------------------------------------------------------------------------
-- NUDGE: Pixel-level positioning
---------------------------------------------------------------------------
function QUI_GFEM:NudgeHeader(headerKey, dx, dy)
    if InCombatLockdown() then return end

    local db = GetDB()
    if not db then return end

    local unified = db.unifiedPosition ~= false

    -- Determine which position table and mover to nudge
    local posKey = "position"
    local mover = groupMover
    if not unified and headerKey == "raid" then
        posKey = "raidPosition"
        mover = raidMover or groupMover
    end

    local pos = db[posKey]
    if not pos then return end

    pos.offsetX = (pos.offsetX or 0) + dx
    pos.offsetY = (pos.offsetY or 0) + dy

    -- Move the mover (headers are anchored to it, so they follow)
    if mover then
        mover:ClearAllPoints()
        mover:SetPoint("CENTER", UIParent, "CENTER", pos.offsetX, pos.offsetY)
        UpdateMoverPositionText(mover, pos.offsetX, pos.offsetY)
    end
end

---------------------------------------------------------------------------
-- SPOTLIGHT: Pin specific members to a separate group
---------------------------------------------------------------------------
function QUI_GFEM:CreateSpotlightHeader()
    local db = GetDB()
    if not db or not db.spotlight or not db.spotlight.enabled then return end
    if InCombatLockdown() then return end

    if spotlightHeader then return spotlightHeader end

    local initConfigFunc = [[
        local header = self:GetParent()
        self:SetWidth(header:GetAttribute("_initialAttribute-unit-width") or 200)
        self:SetHeight(header:GetAttribute("_initialAttribute-unit-height") or 40)
        self:SetAttribute("*type1", "target")
        self:SetAttribute("*type2", "togglemenu")
        RegisterUnitWatch(self)
    ]]

    spotlightHeader = CreateFrame("Frame", "QUI_SpotlightHeader", UIParent, "SecureGroupHeaderTemplate")
    spotlightHeader:SetAttribute("template", "SecureUnitButtonTemplate, BackdropTemplate")
    spotlightHeader:SetAttribute("initialConfigFunction", initConfigFunc)
    spotlightHeader:SetAttribute("showRaid", true)
    spotlightHeader:SetAttribute("showParty", true)

    -- Filter by role
    local roles = db.spotlight.byRole
    if roles and #roles > 0 then
        spotlightHeader:SetAttribute("groupBy", "ASSIGNEDROLE")
        spotlightHeader:SetAttribute("groupingOrder", table.concat(roles, ","))
    end

    -- Dimensions
    local dims = db.dimensions
    local w = dims and dims.partyWidth or 200
    local h = dims and dims.partyHeight or 40
    if not db.spotlight.useMainFrameStyle then
        -- Could have separate dimensions, for now use main
    end
    spotlightHeader:SetAttribute("_initialAttribute-unit-width", w)
    spotlightHeader:SetAttribute("_initialAttribute-unit-height", h)

    -- Grow direction
    local spacing = db.spotlight.spacing or 2
    local grow = db.spotlight.growDirection or "DOWN"
    if grow == "DOWN" then
        spotlightHeader:SetAttribute("point", "TOP")
        spotlightHeader:SetAttribute("yOffset", -spacing)
    else
        spotlightHeader:SetAttribute("point", "BOTTOM")
        spotlightHeader:SetAttribute("yOffset", spacing)
    end

    -- Position
    local pos = db.spotlight.position
    spotlightHeader:SetPoint("CENTER", UIParent, "CENTER",
        pos and pos.offsetX or -400, pos and pos.offsetY or 200)
    spotlightHeader:SetMovable(true)
    spotlightHeader:SetClampedToScreen(true)

    -- Decorate children after a delay
    C_Timer.After(0.2, function()
        local GF = ns.QUI_GroupFrames
        if GF then
            local i = 1
            while true do
                local child = spotlightHeader:GetAttribute("child" .. i)
                if not child then break end
                -- Reuse the same decoration function
                if not child._quiDecorated then
                    -- We can't call DecorateGroupFrame directly since it's local,
                    -- but the child frames should already be decorated by the header system
                end
                i = i + 1
            end
        end
    end)

    spotlightHeader:Show()
    return spotlightHeader
end

function QUI_GFEM:DestroySpotlightHeader()
    if spotlightHeader then
        if not InCombatLockdown() then
            spotlightHeader:Hide()
        end
        spotlightHeader = nil
    end
end

---------------------------------------------------------------------------
-- SLASH COMMAND: /qui grouptest
---------------------------------------------------------------------------
-- Registered in init.lua via the existing slash command handler
-- This function is called from there
function QUI_GFEM:HandleSlashCommand(args)
    if args == "party" then
        self:ToggleTestMode("party")
    elseif args == "raid" then
        self:ToggleTestMode("raid")
    elseif args == "edit" then
        self:ToggleEditMode()
    else
        -- Default: toggle party test
        self:ToggleTestMode("party")
    end
end

---------------------------------------------------------------------------
-- BLIZZARD EDIT MODE INTEGRATION
---------------------------------------------------------------------------
local function OnEditModeEnter()
    -- Show our frames for positioning
    QUI_GFEM:EnableEditMode()
end

local function OnEditModeExit()
    QUI_GFEM:DisableEditMode()
end

-- Hook Blizzard Edit Mode via QUICore callback registry
QUICore:RegisterEditModeEnter(function()
    local db = GetDB()
    if not db or not db.enabled then return end
    OnEditModeEnter()
end)

QUICore:RegisterEditModeExit(function()
    local db = GetDB()
    if not db or not db.enabled then return end
    OnEditModeExit()
end)
