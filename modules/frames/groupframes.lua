--[[
    QUI Group Frames - Party/Raid Frame System
    Creates secure group headers with auto-managed child frames for party and raid.
    Features: Class colors, absorbs, heal prediction, dispel overlay, range check,
    role icons, threat borders, target highlight, unified scaling, click-casting support.
]]

local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local LSM = LibStub("LibSharedMedia-3.0")
local Helpers = ns.Helpers
local IsSecretValue = Helpers.IsSecretValue
local SafeValue = Helpers.SafeValue
local SafeToNumber = Helpers.SafeToNumber
local GetDB = Helpers.CreateDBGetter("quiGroupFrames")

local GetCore = Helpers.GetCore

---------------------------------------------------------------------------
-- MODULE TABLE
---------------------------------------------------------------------------
local QUI_GF = {}
ns.QUI_GroupFrames = QUI_GF

-- Frame references
QUI_GF.headers = {}          -- "party", "raid" header frames
QUI_GF.petHeader = nil       -- pet header
QUI_GF.spotlightHeader = nil -- spotlight header
QUI_GF.allFrames = {}        -- flat list of all child frames (for iteration)
QUI_GF.unitFrameMap = {}     -- unitToken → frame (O(1) event dispatch)
QUI_GF.initialized = false
QUI_GF.testMode = false
QUI_GF.editMode = false

-- State tables for taint safety (weak-keyed)
local frameState, GetFrameState = Helpers.CreateStateTable()

local healthThrottle = {}     -- unitToken → last update time
local powerThrottle = {}      -- unitToken → last update time
local THROTTLE_INTERVAL = 0.1 -- 100ms coalesce window

-- Font/texture caching
local cachedFontPath = nil
local cachedTexturePath = nil
local cachedFontOutline = nil

-- Pre-allocated color tables for common colors
local COLOR_BLACK = { 0, 0, 0, 1 }
local COLOR_WHITE = { 1, 1, 1, 1 }
local COLOR_DEAD = { 0.5, 0.5, 0.5, 1 }
local COLOR_OFFLINE = { 0.4, 0.4, 0.4, 1 }
local COLOR_GHOST = { 0.6, 0.6, 0.6, 1 }

-- Dispel type → color mapping
local DISPEL_COLORS = {
    Magic   = { 0.2, 0.6, 1.0, 1 },  -- Blue
    Curse   = { 0.6, 0.0, 1.0, 1 },  -- Purple
    Disease = { 0.6, 0.4, 0.0, 1 },  -- Brown
    Poison  = { 0.0, 0.6, 0.0, 1 },  -- Green
    Bleed   = { 0.8, 0.0, 0.0, 1 },  -- Red
}

-- Dispel type enum values (WoW 12.0+, from SpellDispelType DB2)
local ALL_DISPEL_ENUMS = {1, 2, 3, 4, 9, 11}

-- Map enum → color (reuses existing DISPEL_COLORS values)
local DISPEL_ENUM_COLORS = {
    [1] = DISPEL_COLORS.Magic,
    [2] = DISPEL_COLORS.Curse,
    [3] = DISPEL_COLORS.Disease,
    [4] = DISPEL_COLORS.Poison,
    [9] = DISPEL_COLORS.Bleed,   -- Enrage uses Bleed color
    [11] = DISPEL_COLORS.Bleed,
}

local dispelColorCurve = nil

local function GetDispelColorCurve(opacity)
    if dispelColorCurve then return dispelColorCurve end
    if not C_CurveUtil or not C_CurveUtil.CreateColorCurve then return nil end
    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    curve:AddPoint(0, CreateColor(0, 0, 0, 0))  -- None = invisible
    for _, enumVal in ipairs(ALL_DISPEL_ENUMS) do
        local c = DISPEL_ENUM_COLORS[enumVal]
        if c then
            curve:AddPoint(enumVal, CreateColor(c[1], c[2], c[3], opacity or 0.8))
        end
    end
    dispelColorCurve = curve
    return curve
end

-- Power type → color mapping
local POWER_COLORS = {
    [0]  = { 0, 0.50, 1 },       -- Mana
    [1]  = { 1, 0, 0 },          -- Rage
    [2]  = { 1, 0.5, 0.25 },     -- Focus
    [3]  = { 1, 1, 0 },          -- Energy
    [6]  = { 0, 0.82, 1 },       -- Runic Power
    [8]  = { 0.3, 0.52, 0.9 },   -- Lunar Power
    [11] = { 0, 0.5, 1 },        -- Maelstrom
    [13] = { 0.4, 0, 0.8 },      -- Insanity
    [17] = { 0.79, 0.26, 0.99 }, -- Fury
    [18] = { 1, 0.61, 0 },       -- Pain
}

-- Defensive cooldown spell IDs (fallback when AuraUtil.AuraFilters unavailable)
local DEFENSIVE_SPELL_IDS = {
    -- External defensives
    [102342] = true, -- Ironbark
    [33206]  = true, -- Pain Suppression
    [47788]  = true, -- Guardian Spirit
    [6940]   = true, -- Blessing of Sacrifice
    [116849] = true, -- Life Cocoon
    [357170] = true, -- Time Dilation
    [98008]  = true, -- Spirit Link Totem
    -- Big personal defensives
    [48707]  = true, -- Anti-Magic Shell
    [48792]  = true, -- Icebound Fortitude
    [61336]  = true, -- Survival Instincts
    [22812]  = true, -- Barkskin
    [186265] = true, -- Aspect of the Turtle
    [45438]  = true, -- Ice Block
    [55233]  = true, -- Vampiric Blood
    [184364] = true, -- Enraged Regeneration
    [12975]  = true, -- Last Stand
    [871]    = true, -- Shield Wall
    [31224]  = true, -- Cloak of Shadows
    [5277]   = true, -- Evasion
    [104773] = true, -- Unending Resolve
    [47585]  = true, -- Dispersion
    [19236]  = true, -- Desperate Prayer
    [108271] = true, -- Astral Shift
    [122278] = true, -- Dampen Harm
    [122783] = true, -- Diffuse Magic
    [363916] = true, -- Obsidian Scales
}

-- Role sorting priority
local ROLE_SORT_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3, NONE = 4 }

-- NPC party member detection (follower dungeons)
local function IsNPCPartyMember(unit)
    return UnitExists(unit) and not UnitIsPlayer(unit)
end

-- Pending combat-deferred operations
local pendingResize = false
local pendingVisibilityUpdate = false
local pendingInitialize = false
local pendingRegisterClicks = false

---------------------------------------------------------------------------
-- HELPERS: Settings access
---------------------------------------------------------------------------
local function GetSettings()
    return GetDB()
end

local function GetGeneralSettings()
    local db = GetDB()
    return db and db.general
end

local function GetLayoutSettings()
    local db = GetDB()
    return db and db.layout
end

local function GetDimensionSettings()
    local db = GetDB()
    return db and db.dimensions
end

local function GetHealthSettings()
    local db = GetDB()
    return db and db.health
end

local function GetPowerSettings()
    local db = GetDB()
    return db and db.power
end

local function GetNameSettings()
    local db = GetDB()
    return db and db.name
end

local function GetIndicatorSettings()
    local db = GetDB()
    return db and db.indicators
end

local function GetHealerSettings()
    local db = GetDB()
    return db and db.healer
end

local function GetRangeSettings()
    local db = GetDB()
    return db and db.range
end

local function GetAuraSettings()
    local db = GetDB()
    return db and db.auras
end

local function GetPortraitSettings()
    local db = GetDB()
    return db and db.portrait
end

---------------------------------------------------------------------------
-- HELPERS: Font and texture
---------------------------------------------------------------------------
local function GetFontPath()
    if cachedFontPath then return cachedFontPath end
    local general = GetGeneralSettings()
    local fontName = general and general.font or "Quazii"
    cachedFontPath = LSM:Fetch("font", fontName) or "Fonts\\FRIZQT__.TTF"
    return cachedFontPath
end

local function GetFontOutline()
    if cachedFontOutline then return cachedFontOutline end
    local general = GetGeneralSettings()
    cachedFontOutline = general and general.fontOutline or "OUTLINE"
    return cachedFontOutline
end

local function GetTexturePath(textureName)
    if not textureName then
        if cachedTexturePath then return cachedTexturePath end
        local general = GetGeneralSettings()
        textureName = general and general.texture or "Quazii v5"
    end
    local path = LSM:Fetch("statusbar", textureName)
    if not cachedTexturePath then
        cachedTexturePath = path
    end
    return path or "Interface\\TargetingFrame\\UI-StatusBar"
end

local function InvalidateCache()
    cachedFontPath = nil
    cachedTexturePath = nil
    cachedFontOutline = nil
end

---------------------------------------------------------------------------
-- HELPERS: Anchor info
---------------------------------------------------------------------------
local ANCHOR_MAP = {
    LEFT       = { point = "LEFT",       leftPoint = "LEFT",       rightPoint = "RIGHT",        justify = "LEFT",   justifyV = "MIDDLE" },
    RIGHT      = { point = "RIGHT",      leftPoint = "LEFT",       rightPoint = "RIGHT",        justify = "RIGHT",  justifyV = "MIDDLE" },
    CENTER     = { point = "CENTER",     leftPoint = "LEFT",       rightPoint = "RIGHT",        justify = "CENTER", justifyV = "MIDDLE" },
    TOPLEFT    = { point = "TOPLEFT",    leftPoint = "TOPLEFT",    rightPoint = "TOPRIGHT",     justify = "LEFT",   justifyV = "TOP" },
    TOPRIGHT   = { point = "TOPRIGHT",   leftPoint = "TOPLEFT",    rightPoint = "TOPRIGHT",     justify = "RIGHT",  justifyV = "TOP" },
    TOP        = { point = "TOP",        leftPoint = "TOPLEFT",    rightPoint = "TOPRIGHT",     justify = "CENTER", justifyV = "TOP" },
    BOTTOMLEFT = { point = "BOTTOMLEFT", leftPoint = "BOTTOMLEFT", rightPoint = "BOTTOMRIGHT",  justify = "LEFT",   justifyV = "BOTTOM" },
    BOTTOMRIGHT= { point = "BOTTOMRIGHT",leftPoint = "BOTTOMLEFT", rightPoint = "BOTTOMRIGHT",  justify = "RIGHT",  justifyV = "BOTTOM" },
    BOTTOM     = { point = "BOTTOM",     leftPoint = "BOTTOMLEFT", rightPoint = "BOTTOMRIGHT",  justify = "CENTER", justifyV = "BOTTOM" },
}

local function GetTextAnchorInfo(anchorName)
    return ANCHOR_MAP[anchorName] or ANCHOR_MAP.LEFT
end

---------------------------------------------------------------------------
-- HELPERS: Health formatting
---------------------------------------------------------------------------
local function FormatNumber(num)
    if not num or num == 0 then return "0" end
    local ok, result = pcall(function()
        if num >= 1000000000 then
            return format("%.1fB", num / 1000000000)
        elseif num >= 1000000 then
            return format("%.1fM", num / 1000000)
        elseif num >= 1000 then
            return format("%.0fK", num / 1000)
        end
        return tostring(math.floor(num))
    end)
    if ok then return result end
    return "?"
end

local function GetHealthPct(unit)
    -- C-side UnitHealthPercent handles secret values natively — no pcall needed
    -- Returns 0-100 via CurveConstants.ScaleTo100 (matches QUI pattern)
    return UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
end

---------------------------------------------------------------------------
-- HELPERS: Group size + dimensions
---------------------------------------------------------------------------
local function GetGroupSize()
    if IsInRaid() then
        return GetNumGroupMembers()
    elseif IsInGroup() then
        return GetNumGroupMembers()
    end
    return 0
end

local function GetGroupMode()
    if IsInRaid() then
        local size = GetNumGroupMembers()
        if size > 25 then return "large" end
        if size > 15 then return "medium" end
        return "small"
    end
    return "party"
end

local function GetFrameDimensions(mode)
    local dims = GetDimensionSettings()
    if not dims then return 200, 40 end

    if mode == "party" then
        return dims.partyWidth or 200, dims.partyHeight or 40
    elseif mode == "small" then
        return dims.smallRaidWidth or 180, dims.smallRaidHeight or 36
    elseif mode == "medium" then
        return dims.mediumRaidWidth or 160, dims.mediumRaidHeight or 30
    elseif mode == "large" then
        return dims.largeRaidWidth or 140, dims.largeRaidHeight or 24
    end
    return 200, 40
end

--- Compute expected header pixel dimensions from settings + member count.
--- Works without child frames (unlike GetHeaderBounds in editmode).
local function CalculateHeaderSize(db, memberCount)
    if not db or not memberCount or memberCount <= 0 then return 100, 40 end

    local layout = db.layout
    local spacing = layout and layout.spacing or 2
    local groupSpacing = layout and layout.groupSpacing or 10
    local grow = layout and layout.growDirection or "DOWN"

    -- Determine mode from member count
    local mode
    if memberCount <= 5 then mode = "party"
    elseif memberCount <= 15 then mode = "small"
    elseif memberCount <= 25 then mode = "medium"
    else mode = "large"
    end

    local w, h = GetFrameDimensions(mode)

    local framesPerGroup = 5
    local numGroups = math.ceil(memberCount / framesPerGroup)
    local framesInTallestGroup = math.min(memberCount, framesPerGroup)

    local horizontal = (grow == "LEFT" or grow == "RIGHT")
    local totalW, totalH

    if horizontal then
        totalW = framesInTallestGroup * w + (framesInTallestGroup - 1) * spacing
        totalH = numGroups * h + (numGroups - 1) * groupSpacing
    else
        totalW = numGroups * w + (numGroups - 1) * groupSpacing
        totalH = framesInTallestGroup * h + (framesInTallestGroup - 1) * spacing
    end

    return math.max(totalW, 100), math.max(totalH, 40)
end

-- Expose for editmode module
QUI_GF.CalculateHeaderSize = CalculateHeaderSize

---------------------------------------------------------------------------
-- HELPERS: Unit tooltip
---------------------------------------------------------------------------
local function ShowUnitTooltip(frame)
    local db = GetSettings()
    if not db or not db.general or db.general.showTooltips == false then return end
    local unit = frame.unit
    if not unit or not UnitExists(unit) then return end
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:SetUnit(unit)
    GameTooltip:Show()
end

local function HideUnitTooltip()
    GameTooltip:Hide()
end

---------------------------------------------------------------------------
-- HELPERS: Health bar color
---------------------------------------------------------------------------
local function GetHealthBarColor(unit)
    local general = GetGeneralSettings()
    if general and general.darkMode then
        local c = general.darkModeHealthColor or { 0.15, 0.15, 0.15, 1 }
        return c[1], c[2], c[3], c[4] or 1
    end

    if general and general.useClassColor ~= false then
        local _, class = UnitClass(unit)
        if class then
            local cc = RAID_CLASS_COLORS[class]
            if cc then
                return cc.r, cc.g, cc.b, 1
            end
        end
    end

    return 0.2, 0.8, 0.2, 1 -- Fallback green
end

---------------------------------------------------------------------------
-- HELPERS: Power bar color
---------------------------------------------------------------------------
local function GetPowerBarColor(unit)
    local db = GetPowerSettings()
    if db and not db.powerBarUsePowerColor then
        local c = db.powerBarColor or { 0.2, 0.4, 0.8, 1 }
        return c[1], c[2], c[3], c[4] or 1
    end

    local ok, powerType = pcall(UnitPowerType, unit)
    if ok and powerType then
        local c = POWER_COLORS[powerType]
        if c then return c[1], c[2], c[3], 1 end
    end
    return 0, 0.5, 1, 1 -- Default mana blue
end

---------------------------------------------------------------------------
-- UPDATE: Health
---------------------------------------------------------------------------
local function UpdateHealth(frame)
    if not frame or not frame.unit then return end
    local unit = frame.unit

    if not UnitExists(unit) then
        if frame.healthBar then frame.healthBar:SetValue(0) end
        if frame.healthText then frame.healthText:SetText("") end
        return
    end

    local isDeadOrGhost = UnitIsDeadOrGhost(unit)
    local isConnected = UnitIsConnected(unit) or IsNPCPartyMember(unit)

    -- Health bar value — use percentage-based approach
    -- UnitHealthPercent returns 0-100 via CurveConstants.ScaleTo100, C-side handles secrets
    if frame.healthBar then
        frame.healthBar:SetMinMaxValues(0, 100)
        if isDeadOrGhost then
            frame.healthBar:SetValue(0)
        else
            local pct = GetHealthPct(unit)
            frame.healthBar:SetValue(pct)
        end

        -- Color
        if not isConnected then
            frame.healthBar:SetStatusBarColor(COLOR_OFFLINE[1], COLOR_OFFLINE[2], COLOR_OFFLINE[3], COLOR_OFFLINE[4])
        elseif isDeadOrGhost then
            frame.healthBar:SetStatusBarColor(COLOR_DEAD[1], COLOR_DEAD[2], COLOR_DEAD[3], COLOR_DEAD[4])
        else
            local r, g, b, a = GetHealthBarColor(unit)
            frame.healthBar:SetStatusBarColor(r, g, b, a)
        end
    end

    -- Centered status text overlay for dead/offline
    if frame.statusText then
        if not isConnected then
            frame.statusText:SetText("OFFLINE")
            frame.statusText:SetTextColor(COLOR_OFFLINE[1], COLOR_OFFLINE[2], COLOR_OFFLINE[3])
            frame.statusText:Show()
        elseif isDeadOrGhost then
            local isGhost = UnitIsGhost(unit)
            frame.statusText:SetText(isGhost and "GHOST" or "DEAD")
            frame.statusText:SetTextColor(COLOR_DEAD[1], COLOR_DEAD[2], COLOR_DEAD[3])
            frame.statusText:Show()
            -- Dim the frame slightly for dead units (offline dimming handled in UpdateConnection)
            frame:SetAlpha(0.65)
        else
            frame.statusText:Hide()
        end
    end

    -- Health text — use SetFormattedText (C-side) which handles secret values natively
    local healthSettings = GetHealthSettings()
    if frame.healthText and healthSettings and healthSettings.showHealthText ~= false then
        if not isConnected then
            frame.healthText:SetText("")
        elseif isDeadOrGhost then
            frame.healthText:SetText("")
        else
            local style = healthSettings.healthDisplayStyle or "percent"
            local abbr = AbbreviateNumbers or AbbreviateLargeNumbers
            if style == "percent" then
                local pct = GetHealthPct(unit)
                frame.healthText:SetFormattedText("%.0f%%", pct)
            elseif style == "absolute" then
                local hp = UnitHealth(unit, true)
                if abbr then
                    frame.healthText:SetText(abbr(hp))
                else
                    frame.healthText:SetFormattedText("%s", hp)
                end
            elseif style == "both" then
                local hp = UnitHealth(unit, true)
                local pct = GetHealthPct(unit)
                if abbr then
                    frame.healthText:SetFormattedText("%s | %.0f%%", abbr(hp), pct)
                else
                    frame.healthText:SetFormattedText("%s | %.0f%%", hp, pct)
                end
            elseif style == "deficit" then
                local miss = UnitHealthMissing(unit, true)
                if C_StringUtil and C_StringUtil.TruncateWhenZero and C_StringUtil.WrapString then
                    local truncated = C_StringUtil.TruncateWhenZero(miss)
                    local result = C_StringUtil.WrapString(truncated, "-")
                    frame.healthText:SetText(result)
                elseif abbr then
                    frame.healthText:SetFormattedText("-%s", abbr(miss))
                else
                    frame.healthText:SetFormattedText("-%s", miss)
                end
            else
                local pct = GetHealthPct(unit)
                frame.healthText:SetFormattedText("%.0f%%", pct)
            end
            local tc = healthSettings.healthTextColor or COLOR_WHITE
            frame.healthText:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
        end
    elseif frame.healthText then
        frame.healthText:SetText("")
    end
end

---------------------------------------------------------------------------
-- UPDATE: Power
---------------------------------------------------------------------------
local function UpdatePower(frame)
    if not frame or not frame.unit or not frame.powerBar then return end
    local unit = frame.unit

    if not UnitExists(unit) then
        frame.powerBar:SetValue(0)
        return
    end

    local power = UnitPower(unit)
    local maxPower = UnitPowerMax(unit)

    -- If values are secret (not numbers), hide the bar (matches QUI pattern)
    if type(power) ~= "number" or type(maxPower) ~= "number" then
        frame.powerBar:Hide()
        return
    end

    -- C-side SetMinMaxValues/SetValue handle values natively — no pcall needed
    frame.powerBar:SetMinMaxValues(0, maxPower)
    frame.powerBar:SetValue(power)

    -- Update color
    local r, g, b, a = GetPowerBarColor(unit)
    frame.powerBar:SetStatusBarColor(r, g, b, a)
end

---------------------------------------------------------------------------
-- UPDATE: Name
---------------------------------------------------------------------------
local function UpdateName(frame)
    if not frame or not frame.unit or not frame.nameText then return end
    local unit = frame.unit

    if not UnitExists(unit) then
        frame.nameText:SetText("")
        return
    end

    local nameSettings = GetNameSettings()
    if nameSettings and nameSettings.showName == false then
        frame.nameText:SetText("")
        return
    end

    local name = UnitName(unit)
    if name then
        local maxLen = nameSettings and nameSettings.maxNameLength or 10
        if maxLen > 0 and #name > maxLen then
            name = Helpers.TruncateUTF8 and Helpers.TruncateUTF8(name, maxLen) or name:sub(1, maxLen)
        end
        frame.nameText:SetText(name)

        -- Color
        if nameSettings and nameSettings.nameTextUseClassColor then
            local _, class = UnitClass(unit)
            if class then
                local cc = RAID_CLASS_COLORS[class]
                if cc then
                    frame.nameText:SetTextColor(cc.r, cc.g, cc.b, 1)
                    return
                end
            end
        end
        local tc = nameSettings and nameSettings.nameTextColor or COLOR_WHITE
        frame.nameText:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
    else
        frame.nameText:SetText("")
    end
end

---------------------------------------------------------------------------
-- UPDATE: Absorbs
---------------------------------------------------------------------------
local function UpdateAbsorbs(frame)
    if not frame or not frame.unit or not frame.absorbBar then return end
    local db = GetSettings()
    if not db or not db.absorbs or db.absorbs.enabled == false then
        frame.absorbBar:Hide()
        return
    end

    local unit = frame.unit
    if not UnitExists(unit) or UnitIsDeadOrGhost(unit) then
        frame.absorbBar:Hide()
        return
    end

    local maxHP = UnitHealthMax(unit)
    local absorbAmount = UnitGetTotalAbsorbs(unit)

    -- Only hide on nil (API unavailable). Do NOT check for zero — StatusBar
    -- naturally shows 0-width when value is 0 (matches QUI pattern).
    -- absorbAmount may be a secret value; pass directly to C-side.
    if not absorbAmount then
        frame.absorbBar:Hide()
        return
    end

    -- C-side SetMinMaxValues/SetValue handle secret values natively — no pcall needed
    -- Reverse fill from right, clamped to maxHP by StatusBar
    frame.absorbBar:SetFrameLevel(frame.healthBar:GetFrameLevel() + 2)
    frame.absorbBar:ClearAllPoints()
    frame.absorbBar:SetAllPoints(frame.healthBar)
    frame.absorbBar:SetReverseFill(true)
    frame.absorbBar:SetMinMaxValues(0, maxHP)
    frame.absorbBar:SetValue(absorbAmount)

    local ac = db.absorbs.color or COLOR_WHITE
    local aa = db.absorbs.opacity or 0.3
    frame.absorbBar:SetStatusBarColor(ac[1], ac[2], ac[3], aa)
    frame.absorbBar:Show()
end

---------------------------------------------------------------------------
-- UPDATE: Heal Prediction
---------------------------------------------------------------------------
local function UpdateHealPrediction(frame)
    if not frame or not frame.unit or not frame.healPredictionBar then return end
    local db = GetSettings()
    if not db or not db.healPrediction or db.healPrediction.enabled == false then
        frame.healPredictionBar:Hide()
        return
    end

    local unit = frame.unit
    if not UnitExists(unit) or UnitIsDeadOrGhost(unit) then
        frame.healPredictionBar:Hide()
        return
    end

    local maxHP = UnitHealthMax(unit)
    local incomingHeals

    -- Use CreateUnitHealPredictionCalculator (11.1+) if available (matches QUI pattern)
    if CreateUnitHealPredictionCalculator then
        if not frame._healPredCalc then
            frame._healPredCalc = CreateUnitHealPredictionCalculator()
        end
        local calc = frame._healPredCalc
        calc:SetIncomingHealClampMode(0) -- Clamp to max health
        calc:SetIncomingHealOverflowPercent(1.0)
        UnitGetDetailedHealPrediction(unit, nil, calc)
        incomingHeals = calc:GetIncomingHeals()
    else
        -- Fallback to simple API
        incomingHeals = UnitGetIncomingHeals(unit)
    end

    -- Only hide on nil (API unavailable). Do NOT check for zero — StatusBar
    -- naturally shows 0-width when value is 0 (matches QUI pattern).
    if not incomingHeals then
        frame.healPredictionBar:Hide()
        return
    end

    -- Anchor from health fill edge to health bar right edge — naturally constrains
    -- to remaining space, no Lua-side math needed.
    local healthTexture = frame.healthBar:GetStatusBarTexture()

    frame.healPredictionBar:ClearAllPoints()
    frame.healPredictionBar:SetPoint("TOPLEFT", healthTexture, "TOPRIGHT", 0, 0)
    frame.healPredictionBar:SetPoint("BOTTOMRIGHT", frame.healthBar, "BOTTOMRIGHT", 0, 0)

    -- C-side SetMinMaxValues/SetValue handle secret values natively — no pcall needed
    frame.healPredictionBar:SetMinMaxValues(0, maxHP)
    frame.healPredictionBar:SetValue(incomingHeals)
    frame.healPredictionBar:Show()
end

---------------------------------------------------------------------------
-- UPDATE: Role Icon
---------------------------------------------------------------------------
local ROLE_ATLAS = {
    TANK   = "roleicon-tiny-tank",
    HEALER = "roleicon-tiny-healer",
    DAMAGER = "roleicon-tiny-dps",
}

local function UpdateRoleIcon(frame)
    if not frame or not frame.unit or not frame.roleIcon then return end
    local indSettings = GetIndicatorSettings()
    if not indSettings or indSettings.showRoleIcon == false then
        frame.roleIcon:Hide()
        return
    end

    local role = UnitGroupRolesAssigned(frame.unit)
    local atlas = ROLE_ATLAS[role]
    if atlas then
        frame.roleIcon:SetAtlas(atlas)
        frame.roleIcon:Show()
    else
        frame.roleIcon:Hide()
    end
end

---------------------------------------------------------------------------
-- UPDATE: Ready Check
---------------------------------------------------------------------------
local READY_CHECK_TEXTURES = {
    ready    = "INTERFACE\\RAIDFRAME\\ReadyCheck-Ready",
    notready = "INTERFACE\\RAIDFRAME\\ReadyCheck-NotReady",
    waiting  = "INTERFACE\\RAIDFRAME\\ReadyCheck-Waiting",
}

local function UpdateReadyCheck(frame)
    if not frame or not frame.unit or not frame.readyCheckIcon then return end
    local indSettings = GetIndicatorSettings()
    if not indSettings or indSettings.showReadyCheck == false then
        frame.readyCheckIcon:Hide()
        return
    end

    local status = GetReadyCheckStatus(frame.unit)
    if status then
        -- QUI pattern: AFK players waiting on ready check show "not ready"
        if status == "waiting" then
            local isAFK = nil
            pcall(function() isAFK = UnitIsAFK(frame.unit) end)
            if isAFK and not IsSecretValue(isAFK) and isAFK == true then
                status = "notready"
            end
        end
        local tex = READY_CHECK_TEXTURES[status] or READY_CHECK_TEXTURES.waiting
        frame.readyCheckIcon:SetTexture(tex)
        frame.readyCheckIcon:Show()
    else
        frame.readyCheckIcon:Hide()
    end
end

---------------------------------------------------------------------------
-- UPDATE: Resurrection
---------------------------------------------------------------------------
local function UpdateResurrection(frame)
    if not frame or not frame.unit or not frame.resIcon then return end
    local indSettings = GetIndicatorSettings()
    if not indSettings or indSettings.showResurrection == false then
        frame.resIcon:Hide()
        return
    end

    local hasRes = UnitHasIncomingResurrection(frame.unit)
    if hasRes then
        frame.resIcon:Show()
    else
        frame.resIcon:Hide()
    end
end

---------------------------------------------------------------------------
-- UPDATE: Summon Pending
---------------------------------------------------------------------------
local function UpdateSummonPending(frame)
    if not frame or not frame.unit or not frame.summonIcon then return end
    local indSettings = GetIndicatorSettings()
    if not indSettings or indSettings.showSummonPending == false then
        frame.summonIcon:Hide()
        return
    end

    local hasSummon = C_IncomingSummon and C_IncomingSummon.HasIncomingSummon(frame.unit)
    if hasSummon then
        frame.summonIcon:Show()
    else
        frame.summonIcon:Hide()
    end
end

---------------------------------------------------------------------------
-- UPDATE: Threat Border
---------------------------------------------------------------------------
local function UpdateThreat(frame)
    if not frame or not frame.unit or not frame.threatBorder then return end
    local indSettings = GetIndicatorSettings()
    if not indSettings or indSettings.showThreatBorder == false then
        frame.threatBorder:Hide()
        return
    end

    local ok, status = pcall(UnitThreatSituation, frame.unit)
    if ok and status and status >= 2 then
        local tc = indSettings.threatColor or { 1, 0, 0, 0.8 }
        frame.threatBorder:SetBackdropBorderColor(tc[1], tc[2], tc[3], tc[4] or 0.8)
        frame.threatBorder:Show()
    else
        frame.threatBorder:Hide()
    end
end

---------------------------------------------------------------------------
-- UPDATE: Target Marker (Raid Icon)
---------------------------------------------------------------------------
local function UpdateTargetMarker(frame)
    if not frame or not frame.unit or not frame.targetMarker then return end
    local indSettings = GetIndicatorSettings()
    if not indSettings or indSettings.showTargetMarker == false then
        frame.targetMarker:Hide()
        return
    end

    local index = GetRaidTargetIndex(frame.unit)
    if index then
        frame.targetMarker:SetAtlas("raidtargetingicon_" .. index)
        frame.targetMarker:Show()
    else
        frame.targetMarker:Hide()
    end
end

---------------------------------------------------------------------------
-- UPDATE: Leader Icon
---------------------------------------------------------------------------
local function UpdateLeaderIcon(frame)
    if not frame or not frame.unit or not frame.leaderIcon then return end
    local indSettings = GetIndicatorSettings()
    if not indSettings or indSettings.showLeaderIcon == false then
        frame.leaderIcon:Hide()
        return
    end

    local isLeader = UnitIsGroupLeader(frame.unit)
    local isAssistant = UnitIsGroupAssistant(frame.unit)
    if isLeader then
        frame.leaderIcon:SetAtlas("groupfinder-icon-leader")
        frame.leaderIcon:Show()
    elseif isAssistant then
        frame.leaderIcon:SetAtlas("groupfinder-icon-leader") -- Same icon, slight dimming
        frame.leaderIcon:SetAlpha(0.6)
        frame.leaderIcon:Show()
    else
        frame.leaderIcon:Hide()
        frame.leaderIcon:SetAlpha(1)
    end
end

---------------------------------------------------------------------------
-- UPDATE: Phase Icon
---------------------------------------------------------------------------
local function UpdatePhaseIcon(frame)
    if not frame or not frame.unit or not frame.phaseIcon then return end
    local indSettings = GetIndicatorSettings()
    if not indSettings or indSettings.showPhaseIcon == false then
        frame.phaseIcon:Hide()
        return
    end

    local phased = UnitPhaseReason(frame.unit) ~= nil and UnitExists(frame.unit)
    if phased then
        frame.phaseIcon:Show()
    else
        frame.phaseIcon:Hide()
    end
end

---------------------------------------------------------------------------
-- UPDATE: Connection (offline dimming)
---------------------------------------------------------------------------
local function UpdateConnection(frame)
    if not frame or not frame.unit then return end
    local unit = frame.unit

    -- Guard against secret values (WoW 12.0+ combat taint)
    local isConnected = UnitIsConnected(unit) or IsNPCPartyMember(unit)
    if IsSecretValue(isConnected) then isConnected = true end

    local isDead = UnitIsDeadOrGhost(unit)
    if IsSecretValue(isDead) then isDead = false end

    if not isConnected and UnitExists(unit) then
        frame:SetAlpha(0.5)
    elseif isDead then
        -- Dead dimming (set in UpdateHealth) — don't override with 1.0
        frame:SetAlpha(0.65)
    else
        -- Alive + connected: don't fight with DoRangeCheck for alpha ownership.
        -- Range check ticker runs every 0.2s and owns the alpha for alive targets.
        -- Only set alpha here if range check hasn't initialized state yet.
        local state = GetFrameState(frame)
        if state.outOfRange == nil then
            frame:SetAlpha(1)
        end
    end
end

---------------------------------------------------------------------------
-- UPDATE: Target Highlight
---------------------------------------------------------------------------
local function UpdateTargetHighlight(frame)
    if not frame or not frame.targetHighlight then return end
    local healerSettings = GetHealerSettings()
    if not healerSettings or not healerSettings.targetHighlight or healerSettings.targetHighlight.enabled == false then
        frame.targetHighlight:Hide()
        return
    end

    if frame.unit and UnitIsUnit(frame.unit, "target") then
        local c = healerSettings.targetHighlight.color or { 1, 1, 1, 0.6 }
        frame.targetHighlight:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 0.6)
        frame.targetHighlight:Show()
    else
        frame.targetHighlight:Hide()
    end
end

---------------------------------------------------------------------------
-- UPDATE: Dispel Overlay
---------------------------------------------------------------------------
-- Helper: apply color to all 4 StatusBar borders
local function SetDispelBorderColor(overlay, r, g, b, a)
    for _, key in ipairs({"borderTop", "borderBottom", "borderLeft", "borderRight"}) do
        local border = overlay[key]
        if border then
            border:GetStatusBarTexture():SetVertexColor(r, g, b, a)
        end
    end
end

-- Helper: apply a ColorMixin (secret-safe) to all 4 StatusBar borders
local function SetDispelBorderColorMixin(overlay, color)
    for _, key in ipairs({"borderTop", "borderBottom", "borderLeft", "borderRight"}) do
        local border = overlay[key]
        if border then
            local tex = border:GetStatusBarTexture()
            -- GetRGBA() returns secret values; SetVertexColor is C-side and handles them
            tex:SetVertexColor(color:GetRGBA())
        end
    end
end

local function UpdateDispelOverlay(frame)
    if not frame or not frame.unit or not frame.dispelOverlay then return end
    local healerSettings = GetHealerSettings()
    if not healerSettings or not healerSettings.dispelOverlay or healerSettings.dispelOverlay.enabled == false then
        frame.dispelOverlay:Hide()
        return
    end

    if not UnitExists(frame.unit) or UnitIsDeadOrGhost(frame.unit) then
        frame.dispelOverlay:Hide()
        return
    end

    local unit = frame.unit
    local overlay = frame.dispelOverlay

    -- WoW 12.0+ secret-safe path: C-side detection + color resolution
    if C_UnitAuras.GetUnitAuras and C_UnitAuras.GetAuraDispelTypeColor then
        local opacity = healerSettings.dispelOverlay.opacity or 0.8
        local curve = GetDispelColorCurve(opacity)
        if curve then
            -- C-side filtering: no secret value reads in Lua
            local ok, dispellables = pcall(C_UnitAuras.GetUnitAuras, unit, "HARMFUL|RAID_PLAYER_DISPELLABLE", 1)
            if ok and dispellables and dispellables[1] then
                local auraInstanceID = dispellables[1].auraInstanceID
                if auraInstanceID then
                    -- C-side dispel type → color resolution (returns ColorMixin)
                    local cOk, color = pcall(C_UnitAuras.GetAuraDispelTypeColor, unit, auraInstanceID, curve)
                    if cOk and color then
                        SetDispelBorderColorMixin(overlay, color)
                        overlay:Show()
                        return
                    end
                end
            end
            -- No dispellable debuff found (or API returned nil)
            overlay:Hide()
            return
        end
    end

    -- Fallback: check shared aura cache (avoids redundant slot-scanning)
    local dispelType = nil
    local GFA = ns.QUI_GroupFrameAuras
    local cache = GFA and GFA.unitAuraCache and GFA.unitAuraCache[unit]
    if cache and cache.harmful then
        for _, auraData in ipairs(cache.harmful) do
            if auraData.isHarmful and auraData.dispelName then
                local dType = SafeValue(auraData.dispelName, nil)
                if dType and DISPEL_COLORS[dType] then
                    dispelType = dType
                    break
                end
            end
        end
    end

    if dispelType then
        local c = DISPEL_COLORS[dispelType]
        local fallbackOpacity = healerSettings.dispelOverlay.opacity or 0.8
        SetDispelBorderColor(overlay, c[1], c[2], c[3], fallbackOpacity)
        overlay:Show()
    else
        overlay:Hide()
    end
end

---------------------------------------------------------------------------
-- UPDATE: Defensive Indicator
---------------------------------------------------------------------------
local function UpdateDefensiveIndicator(frame)
    if not frame or not frame.unit or not frame.defensiveIcon then return end

    local healerSettings = GetHealerSettings()
    if not healerSettings or not healerSettings.defensiveIndicator
       or not healerSettings.defensiveIndicator.enabled then
        frame.defensiveIcon:Hide()
        return
    end

    local unit = frame.unit
    if not UnitExists(unit) or UnitIsDeadOrGhost(unit) then
        frame.defensiveIcon:Hide()
        return
    end

    -- Try WoW 12.0+ AuraUtil.AuraFilters first (C-side, secret-safe, 1 result each)
    local foundAura = nil
    if C_UnitAuras and C_UnitAuras.GetUnitAuras then
        -- BIG_DEFENSIVE filter
        if AuraUtil and AuraUtil.AuraFilters and AuraUtil.AuraFilters.BigDefensive then
            local ok, auras = pcall(C_UnitAuras.GetUnitAuras, unit,
                "HELPFUL|" .. AuraUtil.AuraFilters.BigDefensive, 1)
            if ok and auras and auras[1] then
                foundAura = auras[1]
            end
        end
        -- EXTERNAL_DEFENSIVE filter (if no big defensive found)
        if not foundAura and AuraUtil and AuraUtil.AuraFilters
           and AuraUtil.AuraFilters.ExternalDefensive then
            local ok, auras = pcall(C_UnitAuras.GetUnitAuras, unit,
                "HELPFUL|" .. AuraUtil.AuraFilters.ExternalDefensive, 1)
            if ok and auras and auras[1] then
                foundAura = auras[1]
            end
        end
        -- Fallback: check shared aura cache for known defensive spell IDs
        -- (cache populated by groupframes_auras.lua — avoids redundant bulk scan)
        if not foundAura then
            local GFA = ns.QUI_GroupFrameAuras
            local cache = GFA and GFA.unitAuraCache and GFA.unitAuraCache[unit]
            if cache and cache.helpful then
                for _, auraData in ipairs(cache.helpful) do
                    local spellID = SafeValue(auraData.spellId, nil)
                    if spellID and DEFENSIVE_SPELL_IDS[spellID] then
                        foundAura = auraData
                        break
                    end
                end
            end
        end
    end

    if not foundAura then
        frame.defensiveIcon:Hide()
        return
    end

    -- Update icon texture (C-side SetTexture handles secret values)
    if foundAura.icon and frame.defensiveIcon.icon then
        pcall(frame.defensiveIcon.icon.SetTexture, frame.defensiveIcon.icon, foundAura.icon)
    end

    -- Update cooldown swipe
    local cd = frame.defensiveIcon.cooldown
    if cd and foundAura.duration and foundAura.expirationTime then
        if foundAura.auraInstanceID and C_UnitAuras.GetAuraDuration
           and cd.SetCooldownFromDurationObject then
            local ok, durationObj = pcall(C_UnitAuras.GetAuraDuration, unit, foundAura.auraInstanceID)
            if ok and durationObj then
                pcall(cd.SetCooldownFromDurationObject, cd, durationObj)
            elseif cd.SetCooldownFromExpirationTime then
                pcall(cd.SetCooldownFromExpirationTime, cd, foundAura.expirationTime, foundAura.duration)
            end
        elseif cd.SetCooldownFromExpirationTime then
            pcall(cd.SetCooldownFromExpirationTime, cd, foundAura.expirationTime, foundAura.duration)
        else
            pcall(function()
                cd:SetCooldown(foundAura.expirationTime - foundAura.duration, foundAura.duration)
            end)
        end
    elseif cd then
        cd:Clear()
    end

    -- Size and position
    local defSettings = healerSettings.defensiveIndicator
    local iconSize = defSettings.iconSize or 16
    local position = defSettings.position or "CENTER"
    local offsetX = defSettings.offsetX or 0
    local offsetY = defSettings.offsetY or 0
    frame.defensiveIcon:SetSize(iconSize, iconSize)
    frame.defensiveIcon:ClearAllPoints()
    frame.defensiveIcon:SetPoint(position, frame, position, offsetX, offsetY)
    frame.defensiveIcon:SetFrameLevel(frame:GetFrameLevel() + 10)

    frame.defensiveIcon:Show()
end

---------------------------------------------------------------------------
-- UPDATE: Portrait
---------------------------------------------------------------------------
local function UpdatePortrait(frame)
    if not frame or not frame.unit then return end
    local portraitSettings = GetPortraitSettings()

    if not portraitSettings or not portraitSettings.showPortrait then
        if frame.portrait then frame.portrait:Hide() end
        return
    end

    if not frame.portrait or not frame.portraitTexture then return end

    local unit = frame.unit
    if not UnitExists(unit) then
        frame.portrait:Hide()
        return
    end

    -- Update texture
    pcall(SetPortraitTexture, frame.portraitTexture, unit, true)
    frame.portraitTexture:SetTexCoord(0.15, 0.85, 0.15, 0.85)

    -- Desaturate for dead/offline
    local isDeadOrGhost = UnitIsDeadOrGhost(unit)
    local isConnected = UnitIsConnected(unit) or IsNPCPartyMember(unit)
    frame.portraitTexture:SetDesaturated(isDeadOrGhost or not isConnected)

    frame.portrait:Show()
end

---------------------------------------------------------------------------
-- UPDATE: Full frame refresh
---------------------------------------------------------------------------
-- UPDATE: Dark Mode Visuals (backdrop, health bar alpha)
---------------------------------------------------------------------------
local function UpdateDarkModeVisuals(frame)
    if not frame then return end
    local general = GetGeneralSettings()
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
    if frame.healthBar then
        frame.healthBar:SetAlpha(healthOpacity)
    end
end

---------------------------------------------------------------------------
local function UpdateFrame(frame)
    if not frame or not frame.unit then return end
    UpdateDarkModeVisuals(frame)
    UpdateHealth(frame)
    UpdatePower(frame)
    UpdateName(frame)
    UpdateAbsorbs(frame)
    UpdateHealPrediction(frame)
    UpdateRoleIcon(frame)
    UpdateReadyCheck(frame)
    UpdateResurrection(frame)
    UpdateSummonPending(frame)
    UpdateThreat(frame)
    UpdateTargetMarker(frame)
    UpdateLeaderIcon(frame)
    UpdatePhaseIcon(frame)
    UpdateConnection(frame)
    UpdateTargetHighlight(frame)
    UpdateDispelOverlay(frame)
    UpdateDefensiveIndicator(frame)
    UpdatePortrait(frame)
end

---------------------------------------------------------------------------
-- DECORATE: Apply QUI visuals to a SecureGroupHeader child frame
---------------------------------------------------------------------------
local function DecorateGroupFrame(frame)
    if not frame or frame._quiDecorated then return end
    frame._quiDecorated = true


    local db = GetSettings()
    local general = GetGeneralSettings()
    local mode = GetGroupMode()
    local frameWidth, frameHeight = GetFrameDimensions(mode)

    -- Backdrop
    local borderPx = general and general.borderSize or 1
    local borderSize = borderPx > 0 and (QUICore.Pixels and QUICore:Pixels(borderPx, frame) or borderPx) or 0
    local px = QUICore.GetPixelSize and QUICore:GetPixelSize(frame) or 1

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = borderSize > 0 and "Interface\\Buttons\\WHITE8x8" or nil,
        edgeSize = borderSize > 0 and borderSize or nil,
    })

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

    -- Power bar height calculation
    local powerSettings = GetPowerSettings()
    local showPower = powerSettings and powerSettings.showPowerBar ~= false
    local powerHeight = showPower and (QUICore.PixelRound and QUICore:PixelRound(powerSettings.powerBarHeight or 4, frame) or 4) or 0
    local separatorHeight = showPower and px or 0

    -- Health bar (reuse existing to avoid frame leaks on re-decoration)
    local healthBar = frame.healthBar or CreateFrame("StatusBar", nil, frame)
    healthBar:ClearAllPoints()
    healthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", borderSize, -borderSize)
    healthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize + powerHeight + separatorHeight)
    healthBar:SetStatusBarTexture(GetTexturePath())
    healthBar:SetMinMaxValues(0, 100)
    healthBar:SetValue(100)
    healthBar:EnableMouse(false)
    healthBar:SetAlpha(healthOpacity)
    frame.healthBar = healthBar

    -- No separate healthBg texture — the frame backdrop shows through the
    -- unfilled StatusBar area, matching unit frame behavior.
    if frame.healthBg then
        frame.healthBg:Hide()
        frame.healthBg = nil
    end

    -- Heal prediction bar (overlays health bar, peeks out beyond health fill)
    local predSettings = db and db.healPrediction
    local healPredictionBar = frame.healPredictionBar or CreateFrame("StatusBar", nil, healthBar)
    healPredictionBar:SetStatusBarTexture(GetTexturePath())
    healPredictionBar:SetFrameLevel(healthBar:GetFrameLevel() + 1)
    healPredictionBar:ClearAllPoints()
    healPredictionBar:SetAllPoints(healthBar)
    healPredictionBar:SetMinMaxValues(0, 1)
    healPredictionBar:SetValue(0)
    local pc = predSettings and predSettings.color or { 0.2, 1, 0.2 }
    local pa = predSettings and predSettings.opacity or 0.5
    healPredictionBar:SetStatusBarColor(pc[1] or 0.2, pc[2] or 1, pc[3] or 0.2, pa)
    healPredictionBar:Hide()
    frame.healPredictionBar = healPredictionBar

    -- Absorb bar (overlays health bar, reverse-fills from right)
    local absorbSettings = db and db.absorbs
    local absorbBar = frame.absorbBar
    if not absorbBar then
        absorbBar = CreateFrame("StatusBar", nil, healthBar)
    end
    absorbBar:SetStatusBarTexture("Interface\\RaidFrame\\Shield-Fill")
    local ac = absorbSettings and absorbSettings.color or COLOR_WHITE
    local aa = absorbSettings and absorbSettings.opacity or 0.3
    absorbBar:SetStatusBarColor(ac[1], ac[2], ac[3], aa)
    absorbBar:SetFrameLevel(healthBar:GetFrameLevel() + 2)
    absorbBar:SetFrameStrata(healthBar:GetFrameStrata())
    absorbBar:ClearAllPoints()
    absorbBar:SetAllPoints(healthBar)
    absorbBar:SetReverseFill(true)
    absorbBar:SetMinMaxValues(0, 1)
    absorbBar:SetValue(0)
    absorbBar:Hide()
    frame.absorbBar = absorbBar

    -- Power bar
    if showPower then
        local powerBar = frame.powerBar or CreateFrame("StatusBar", nil, frame)
        powerBar:ClearAllPoints()
        powerBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", borderSize, borderSize)
        powerBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize)
        powerBar:SetHeight(powerHeight)
        powerBar:SetStatusBarTexture(GetTexturePath())
        powerBar:SetMinMaxValues(0, 100)
        powerBar:SetValue(100)
        powerBar:EnableMouse(false)
        frame.powerBar = powerBar

        -- Power bar background
        if not frame._powerBg then
            local powerBg = powerBar:CreateTexture(nil, "BACKGROUND")
            powerBg:SetAllPoints()
            powerBg:SetTexture("Interface\\Buttons\\WHITE8x8")
            powerBg:SetVertexColor(0.05, 0.05, 0.05, 0.9)
            frame._powerBg = powerBg
        end

        -- Separator
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

    -- Text frame (above health bar for layering)
    local textFrame = frame._textFrame or CreateFrame("Frame", nil, frame)
    textFrame:SetAllPoints()
    textFrame:SetFrameLevel(healthBar:GetFrameLevel() + 3)
    frame._textFrame = textFrame

    -- Centered status text (DEAD / OFFLINE overlay)
    local statusText = frame.statusText or textFrame:CreateFontString(nil, "OVERLAY")
    statusText:ClearAllPoints()
    statusText:SetFont(GetFontPath(), 14, "OUTLINE")
    statusText:SetPoint("CENTER", frame, "CENTER", 0, 0)
    statusText:SetJustifyH("CENTER")
    statusText:SetJustifyV("MIDDLE")
    statusText:SetTextColor(0.9, 0.9, 0.9, 1)
    statusText:Hide()
    frame.statusText = statusText

    -- Name text
    local fontPath = GetFontPath()
    local fontOutline = GetFontOutline()
    local nameSettings = GetNameSettings()
    local nameFontSize = nameSettings and nameSettings.nameFontSize or 12
    local nameAnchor = GetTextAnchorInfo(nameSettings and nameSettings.nameAnchor or "LEFT")
    local nameOffsetX = nameSettings and nameSettings.nameOffsetX or 4
    local nameOffsetY = nameSettings and nameSettings.nameOffsetY or 0

    local nameText = frame.nameText or textFrame:CreateFontString(nil, "OVERLAY")
    nameText:ClearAllPoints()
    nameText:SetFont(fontPath, nameFontSize, fontOutline)
    local namePadX = math.abs(nameOffsetX)
    nameText:SetPoint(nameAnchor.leftPoint, frame, nameAnchor.leftPoint, namePadX, nameOffsetY)
    nameText:SetPoint(nameAnchor.rightPoint, frame, nameAnchor.rightPoint, -namePadX, nameOffsetY)
    nameText:SetJustifyH(nameAnchor.justify)
    nameText:SetJustifyV(nameAnchor.justifyV)
    nameText:SetTextColor(1, 1, 1, 1)
    nameText:SetWordWrap(false)
    frame.nameText = nameText

    -- Health text
    local healthSettings = GetHealthSettings()
    local healthFontSize = healthSettings and healthSettings.healthFontSize or 12
    local healthAnchor = GetTextAnchorInfo(healthSettings and healthSettings.healthAnchor or "RIGHT")
    local healthOffsetX = healthSettings and healthSettings.healthOffsetX or -4
    local healthOffsetY = healthSettings and healthSettings.healthOffsetY or 0

    local healthText = frame.healthText or textFrame:CreateFontString(nil, "OVERLAY")
    healthText:ClearAllPoints()
    healthText:SetFont(fontPath, healthFontSize, fontOutline)
    local healthPadX = math.abs(healthOffsetX)
    healthText:SetPoint(healthAnchor.leftPoint, frame, healthAnchor.leftPoint, healthPadX, healthOffsetY)
    healthText:SetPoint(healthAnchor.rightPoint, frame, healthAnchor.rightPoint, -healthPadX, healthOffsetY)
    healthText:SetJustifyH(healthAnchor.justify)
    healthText:SetJustifyV(healthAnchor.justifyV)
    healthText:SetTextColor(1, 1, 1, 1)
    healthText:SetWordWrap(false)
    frame.healthText = healthText

    -- Role icon
    local indSettings = GetIndicatorSettings()
    local roleIconSize = indSettings and indSettings.roleIconSize or 12
    local roleAnchor = indSettings and indSettings.roleIconAnchor or "TOPLEFT"

    local roleIcon = frame.roleIcon or textFrame:CreateTexture(nil, "OVERLAY")
    roleIcon:ClearAllPoints()
    roleIcon:SetSize(roleIconSize, roleIconSize)
    roleIcon:SetPoint(roleAnchor, frame, roleAnchor, 2, -2)
    roleIcon:Hide()
    frame.roleIcon = roleIcon

    -- Ready check icon
    local readyCheckIcon = frame.readyCheckIcon or textFrame:CreateTexture(nil, "OVERLAY")
    readyCheckIcon:ClearAllPoints()
    readyCheckIcon:SetSize(16, 16)
    readyCheckIcon:SetPoint("CENTER", frame, "CENTER", 0, 0)
    readyCheckIcon:Hide()
    frame.readyCheckIcon = readyCheckIcon

    -- Resurrection icon
    local resIcon = frame.resIcon or textFrame:CreateTexture(nil, "OVERLAY")
    resIcon:ClearAllPoints()
    resIcon:SetSize(16, 16)
    resIcon:SetPoint("CENTER", frame, "CENTER", 0, 0)
    resIcon:SetAtlas("nameplates-icon-flag-horde") -- Placeholder, will be proper res icon
    resIcon:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")
    resIcon:Hide()
    frame.resIcon = resIcon

    -- Summon pending icon
    local summonIcon = frame.summonIcon or textFrame:CreateTexture(nil, "OVERLAY")
    summonIcon:ClearAllPoints()
    summonIcon:SetSize(16, 16)
    summonIcon:SetPoint("CENTER", frame, "CENTER", 16, 0)
    summonIcon:SetAtlas("Raid-Icon-SummonPending")
    summonIcon:Hide()
    frame.summonIcon = summonIcon

    -- Leader icon
    local leaderIcon = frame.leaderIcon or textFrame:CreateTexture(nil, "OVERLAY")
    leaderIcon:ClearAllPoints()
    leaderIcon:SetSize(12, 12)
    leaderIcon:SetPoint("TOP", frame, "TOP", 0, 6)
    leaderIcon:Hide()
    frame.leaderIcon = leaderIcon

    -- Target marker (raid icon)
    local targetMarker = frame.targetMarker or textFrame:CreateTexture(nil, "OVERLAY")
    targetMarker:ClearAllPoints()
    targetMarker:SetSize(14, 14)
    targetMarker:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    targetMarker:Hide()
    frame.targetMarker = targetMarker

    -- Phase icon
    local phaseIcon = frame.phaseIcon or textFrame:CreateTexture(nil, "OVERLAY")
    phaseIcon:ClearAllPoints()
    phaseIcon:SetSize(16, 16)
    phaseIcon:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 2, 2)
    phaseIcon:SetAtlas("nameplates-icon-flag-horde") -- Placeholder
    phaseIcon:SetTexture("Interface\\TargetingFrame\\UI-PhasingIcon")
    phaseIcon:Hide()
    frame.phaseIcon = phaseIcon

    -- Threat border (overlay frame)
    local threatBorder = frame.threatBorder or CreateFrame("Frame", nil, frame, "BackdropTemplate")
    threatBorder:SetAllPoints()
    threatBorder:SetFrameLevel(frame:GetFrameLevel() + 5)
    threatBorder:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = borderSize > 0 and borderSize * 2 or px * 2,
    })
    threatBorder:Hide()
    frame.threatBorder = threatBorder

    -- Target highlight (overlay frame)
    local targetHighlight = frame.targetHighlight or CreateFrame("Frame", nil, frame, "BackdropTemplate")
    targetHighlight:ClearAllPoints()
    targetHighlight:SetPoint("TOPLEFT", -px, px)
    targetHighlight:SetPoint("BOTTOMRIGHT", px, -px)
    targetHighlight:SetFrameLevel(frame:GetFrameLevel() + 4)
    targetHighlight:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px * 2,
    })
    targetHighlight:Hide()
    frame.targetHighlight = targetHighlight

    -- Dispel overlay (StatusBar borders for secret-value-safe SetVertexColor)
    local dispelOverlay = frame.dispelOverlay or CreateFrame("Frame", nil, frame)
    dispelOverlay:ClearAllPoints()
    dispelOverlay:SetPoint("TOPLEFT", -px, px)
    dispelOverlay:SetPoint("BOTTOMRIGHT", px, -px)
    dispelOverlay:SetFrameLevel(frame:GetFrameLevel() + 6)

    local dispelBorderSize = px * 3
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

    dispelOverlay:Hide()
    frame.dispelOverlay = dispelOverlay

    -- Defensive indicator icon (centered, high frame level)
    local defensiveIcon = frame.defensiveIcon or CreateFrame("Frame", nil, frame, "BackdropTemplate")
    defensiveIcon:SetSize(16, 16)
    defensiveIcon:ClearAllPoints()
    defensiveIcon:SetPoint("CENTER", frame, "CENTER", 0, 0)
    defensiveIcon:SetFrameLevel(frame:GetFrameLevel() + 10)

    local defTex = defensiveIcon.icon or defensiveIcon:CreateTexture(nil, "ARTWORK")
    defTex:SetAllPoints()
    defTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    defensiveIcon.icon = defTex

    defensiveIcon:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    defensiveIcon:SetBackdropBorderColor(0, 0.8, 0, 1)

    local defCD = defensiveIcon.cooldown or CreateFrame("Cooldown", nil, defensiveIcon, "CooldownFrameTemplate")
    defCD:SetAllPoints(defTex)
    defCD:SetDrawEdge(false)
    defCD:SetDrawSwipe(true)
    defCD:SetReverse(true)
    defCD:SetHideCountdownNumbers(false)
    defensiveIcon.cooldown = defCD

    -- Disable mouse on the icon so clicks pass through to the unit frame
    if defensiveIcon.SetMouseClickEnabled then
        defensiveIcon:SetMouseClickEnabled(false)
    end
    defensiveIcon:EnableMouse(false)

    defensiveIcon:Hide()
    frame.defensiveIcon = defensiveIcon

    -- Portrait (optional, side-attached)
    local portraitSettings = GetPortraitSettings()
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

        portrait:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = portraitBorderPx,
        })
        portrait:SetBackdropBorderColor(0, 0, 0, 1)
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

    -- One-time hooks (only on first decoration)
    if not frame._quiHooked then
        frame._quiHooked = true

        frame:HookScript("OnEnter", function(self)
            ShowUnitTooltip(self)
        end)
        frame:HookScript("OnLeave", HideUnitTooltip)

        -- Sync unit attribute → frame.unit whenever the secure header changes it
        frame:HookScript("OnAttributeChanged", function(self, key, value)
            if key ~= "unit" then return end
            local oldUnit = self.unit
            self.unit = value
            if oldUnit and QUI_GF.unitFrameMap[oldUnit] == self then
                QUI_GF.unitFrameMap[oldUnit] = nil
            end
            if value then
                QUI_GF.unitFrameMap[value] = self
                UpdateFrame(self)
            end
        end)
    end

    -- Pick up the current unit if already assigned by the secure header
    local currentUnit = frame:GetAttribute("unit")
    if currentUnit then
        frame.unit = currentUnit
        QUI_GF.unitFrameMap[currentUnit] = frame
    end

    -- Register with Clique / click-cast
    if ClickCastFrames then
        ClickCastFrames[frame] = true
    end

    -- Register with QUI click-cast system
    local GFCC = ns.QUI_GroupFrameClickCast
    if GFCC and GFCC:IsEnabled() then
        GFCC:RegisterFrame(frame)
    end

    -- Store in flat list
    table.insert(QUI_GF.allFrames, frame)
end

---------------------------------------------------------------------------
-- UNIT FRAME MAP: Rebuild unit → frame lookup
---------------------------------------------------------------------------
local function RebuildUnitFrameMap()
    wipe(QUI_GF.unitFrameMap)

    for _, headerKey in ipairs({"party", "raid"}) do
        local header = QUI_GF.headers[headerKey]
        if header and header:IsShown() then
            local i = 1
            while true do
                local child = header:GetAttribute("child" .. i)
                if not child then break end
                local unit = child:GetAttribute("unit")
                child.unit = unit  -- sync Lua property (nil clears stale)
                if unit then
                    QUI_GF.unitFrameMap[unit] = child
                end
                i = i + 1
            end
        end
    end
end

---------------------------------------------------------------------------
-- HEADER: Configure secure header attributes
---------------------------------------------------------------------------
local function ConfigurePartyHeader(header)
    local layout = GetLayoutSettings()
    if not layout then return end

    header:SetAttribute("showParty", true)
    header:SetAttribute("showPlayer", layout.showPlayer ~= false)
    header:SetAttribute("showRaid", false)
    header:SetAttribute("showSolo", false)
    header:SetAttribute("maxColumns", 1)
    header:SetAttribute("unitsPerColumn", 5)

    local mode = "party"
    local w, h = GetFrameDimensions(mode)
    local spacing = layout.spacing or 2

    -- Grow direction
    local grow = layout.growDirection or "DOWN"
    if grow == "DOWN" then
        header:SetAttribute("point", "TOP")
        header:SetAttribute("yOffset", -spacing)
        header:SetAttribute("xOffset", 0)
    elseif grow == "UP" then
        header:SetAttribute("point", "BOTTOM")
        header:SetAttribute("yOffset", spacing)
        header:SetAttribute("xOffset", 0)
    elseif grow == "RIGHT" then
        header:SetAttribute("point", "LEFT")
        header:SetAttribute("xOffset", spacing)
        header:SetAttribute("yOffset", 0)
    elseif grow == "LEFT" then
        header:SetAttribute("point", "RIGHT")
        header:SetAttribute("xOffset", -spacing)
        header:SetAttribute("yOffset", 0)
    end

    -- Sorting
    if layout.sortByRole then
        header:SetAttribute("groupBy", "ASSIGNEDROLE")
        header:SetAttribute("groupingOrder", "TANK,HEALER,DAMAGER,NONE")
    else
        local sortMethod = layout.sortMethod or "INDEX"
        header:SetAttribute("sortMethod", sortMethod)
    end

    -- Frame size via initial config
    header:SetAttribute("_initialAttributeNames", "unit-width,unit-height")
    header:SetAttribute("_initialAttribute-unit-width", w)
    header:SetAttribute("_initialAttribute-unit-height", h)
end

local function ConfigureRaidHeader(header)
    local layout = GetLayoutSettings()
    if not layout then return end

    header:SetAttribute("showRaid", true)
    header:SetAttribute("showParty", false)
    header:SetAttribute("showPlayer", false)
    header:SetAttribute("showSolo", false)

    local mode = GetGroupMode()
    local w, h = GetFrameDimensions(mode)
    local spacing = layout.spacing or 2
    local groupSpacing = layout.groupSpacing or 10

    -- Grow direction (within each group column)
    local grow = layout.growDirection or "DOWN"
    if grow == "DOWN" then
        header:SetAttribute("point", "TOP")
        header:SetAttribute("yOffset", -spacing)
        header:SetAttribute("xOffset", 0)
    elseif grow == "UP" then
        header:SetAttribute("point", "BOTTOM")
        header:SetAttribute("yOffset", spacing)
        header:SetAttribute("xOffset", 0)
    elseif grow == "RIGHT" then
        header:SetAttribute("point", "LEFT")
        header:SetAttribute("xOffset", spacing)
        header:SetAttribute("yOffset", 0)
    elseif grow == "LEFT" then
        header:SetAttribute("point", "RIGHT")
        header:SetAttribute("xOffset", -spacing)
        header:SetAttribute("yOffset", 0)
    end

    -- Columns for groups
    -- When frames within a group are horizontal, groups stack vertically (and vice versa)
    local horizontal = (grow == "LEFT" or grow == "RIGHT")
    header:SetAttribute("maxColumns", 8)
    header:SetAttribute("unitsPerColumn", 5)
    header:SetAttribute("columnSpacing", groupSpacing)

    if horizontal then
        -- Groups stack vertically when intra-group is horizontal
        header:SetAttribute("columnAnchorPoint", "TOP")
    else
        local groupGrow = layout.groupGrowDirection or "RIGHT"
        if groupGrow == "RIGHT" then
            header:SetAttribute("columnAnchorPoint", "LEFT")
        else
            header:SetAttribute("columnAnchorPoint", "RIGHT")
        end
    end

    -- Group filtering
    local groupBy = layout.groupBy or "GROUP"
    if groupBy == "GROUP" then
        header:SetAttribute("groupBy", "GROUP")
        header:SetAttribute("groupFilter", "1,2,3,4,5,6,7,8")
        header:SetAttribute("groupingOrder", "1,2,3,4,5,6,7,8")
    elseif groupBy == "ROLE" then
        header:SetAttribute("groupBy", "ASSIGNEDROLE")
        header:SetAttribute("groupingOrder", "TANK,HEALER,DAMAGER,NONE")
    elseif groupBy == "CLASS" then
        header:SetAttribute("groupBy", "CLASS")
        header:SetAttribute("groupingOrder", "WARRIOR,DEATHKNIGHT,PALADIN,MONK,PRIEST,SHAMAN,DRUID,ROGUE,MAGE,WARLOCK,HUNTER,DEMONHUNTER,EVOKER")
    end

    -- Sorting
    if layout.sortByRole and groupBy ~= "ROLE" then
        -- Role sort within groups
        header:SetAttribute("sortMethod", "NAME")
    else
        header:SetAttribute("sortMethod", layout.sortMethod or "INDEX")
    end

    -- Frame size via initial config
    header:SetAttribute("_initialAttributeNames", "unit-width,unit-height")
    header:SetAttribute("_initialAttribute-unit-width", w)
    header:SetAttribute("_initialAttribute-unit-height", h)
end

---------------------------------------------------------------------------
-- HEADER: Create secure group headers
---------------------------------------------------------------------------
local function CreateHeaders()
    local db = GetSettings()
    if not db then return end
    local layout = GetLayoutSettings()
    local position = db.position

    -- initialConfigFunction runs in secure context for each new child
    local initConfigFunc = [[
        local header = self:GetParent()
        local w = header:GetAttribute("_initialAttribute-unit-width") or 200
        local h = header:GetAttribute("_initialAttribute-unit-height") or 40
        self:SetWidth(w)
        self:SetHeight(h)
        self:SetAttribute("*type1", "target")
        self:SetAttribute("*type2", "togglemenu")
        RegisterUnitWatch(self)
    ]]

    -- Party header
    local partyHeader = CreateFrame("Frame", "QUI_PartyHeader", UIParent, "SecureGroupHeaderTemplate")
    partyHeader:SetAttribute("template", "SecureUnitButtonTemplate, BackdropTemplate")
    partyHeader:SetAttribute("initialConfigFunction", initConfigFunc)
    ConfigurePartyHeader(partyHeader)

    -- Position
    local offsetX = position and position.offsetX or -400
    local offsetY = position and position.offsetY or 0
    local partyW, partyH = CalculateHeaderSize(db, 5)
    partyHeader:SetSize(partyW, partyH)
    partyHeader:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
    partyHeader:SetMovable(true)
    partyHeader:SetClampedToScreen(true)

    -- Pre-create all 5 party frames upfront so no frames are created mid-combat
    partyHeader:SetAttribute("startingIndex", -4)
    partyHeader:Show()
    partyHeader:SetAttribute("startingIndex", 1)
    partyHeader:Hide()

    QUI_GF.headers.party = partyHeader
    QUI:DebugPrint(("[GF] CreateHeaders party: pos=(%d,%d) size=(%d,%d)"):format(offsetX, offsetY, partyW, partyH))

    -- Watch for new children added by the secure header (handles late NPC frames)
    partyHeader:HookScript("OnAttributeChanged", function(self, key, value)
        if value and type(key) == "string" and key:match("^child") then
            DecorateGroupFrame(value)
            if not InCombatLockdown() then
                value:RegisterForClicks("AnyUp")
            else
                pendingRegisterClicks = true
            end
        end
    end)

    -- Raid header
    local raidHeader = CreateFrame("Frame", "QUI_RaidHeader", UIParent, "SecureGroupHeaderTemplate")
    raidHeader:SetAttribute("template", "SecureUnitButtonTemplate, BackdropTemplate")
    raidHeader:SetAttribute("initialConfigFunction", initConfigFunc)
    ConfigureRaidHeader(raidHeader)

    local raidCount = math.max(IsInRaid() and GetNumGroupMembers() or 25, 5)
    local raidW, raidH = CalculateHeaderSize(db, raidCount)
    raidHeader:SetSize(raidW, raidH)
    raidHeader:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
    raidHeader:SetMovable(true)
    raidHeader:SetClampedToScreen(true)

    -- Pre-create all 40 raid frames upfront so no frames are created mid-combat
    raidHeader:SetAttribute("startingIndex", -39)
    raidHeader:Show()
    raidHeader:SetAttribute("startingIndex", 1)
    raidHeader:Hide()

    QUI_GF.headers.raid = raidHeader
    QUI:DebugPrint(("[GF] CreateHeaders raid: pos=(%d,%d) size=(%d,%d)"):format(offsetX, offsetY, raidW, raidH))

    -- Watch for new children on raid header too
    raidHeader:HookScript("OnAttributeChanged", function(self, key, value)
        if value and type(key) == "string" and key:match("^child") then
            DecorateGroupFrame(value)
            if not InCombatLockdown() then
                value:RegisterForClicks("AnyUp")
            else
                pendingRegisterClicks = true
            end
        end
    end)
end

---------------------------------------------------------------------------
-- HEADER: Update header sizes based on current roster
---------------------------------------------------------------------------
local function UpdateHeaderSizes()
    if InCombatLockdown() then return end
    local db = GetSettings()
    if not db then return end

    local partyHdr = QUI_GF.headers.party
    if partyHdr then
        local count = IsInGroup() and not IsInRaid() and GetNumGroupMembers() or 5
        if db.layout and db.layout.showPlayer ~= false then
            count = math.max(count, 1)  -- showPlayer adds the player
        end
        local w, h = CalculateHeaderSize(db, count)
        partyHdr:SetSize(w, h)
        QUI:DebugPrint(("[GF] UpdateHeaderSizes party: count=%d size=(%d,%d)"):format(count, w, h))
    end

    local raidHdr = QUI_GF.headers.raid
    if raidHdr then
        local count = IsInRaid() and GetNumGroupMembers() or 25
        count = math.max(count, 5)
        local w, h = CalculateHeaderSize(db, count)
        raidHdr:SetSize(w, h)
        QUI:DebugPrint(("[GF] UpdateHeaderSizes raid: count=%d size=(%d,%d)"):format(count, w, h))
    end
end

---------------------------------------------------------------------------
-- HEADER: Decorate all child frames in a header
---------------------------------------------------------------------------
local function DecorateHeaderChildren(header)
    if not header then return end
    local i = 1
    while true do
        local child = header:GetAttribute("child" .. i)
        if not child then break end
        DecorateGroupFrame(child)
        -- RegisterForClicks is protected — defer during combat
        if not InCombatLockdown() then
            child:RegisterForClicks("AnyUp")
        else
            pendingRegisterClicks = true
        end
        i = i + 1
    end
end

---------------------------------------------------------------------------
-- HEADER: Show/hide based on group status
---------------------------------------------------------------------------
local function UpdateHeaderVisibility()
    if InCombatLockdown() then
        pendingVisibilityUpdate = true
        return
    end

    local db = GetSettings()
    if not db or not db.enabled then
        if QUI_GF.headers.party then QUI_GF.headers.party:Hide() end
        if QUI_GF.headers.raid then QUI_GF.headers.raid:Hide() end
        return
    end

    if QUI_GF.testMode then
        -- Test mode handled by edit mode module
        return
    end

    if IsInRaid() then
        if QUI_GF.headers.party then QUI_GF.headers.party:Hide() end
        if QUI_GF.headers.raid then QUI_GF.headers.raid:Show() end
    elseif IsInGroup() then
        if QUI_GF.headers.raid then QUI_GF.headers.raid:Hide() end
        if QUI_GF.headers.party then QUI_GF.headers.party:Show() end
    else
        if QUI_GF.headers.party then QUI_GF.headers.party:Hide() end
        if QUI_GF.headers.raid then QUI_GF.headers.raid:Hide() end
    end

    -- Defer decoration + map rebuild to next frame (after header creates children)
    C_Timer.After(0.1, function()
        DecorateHeaderChildren(QUI_GF.headers.party)
        DecorateHeaderChildren(QUI_GF.headers.raid)
        RebuildUnitFrameMap()
        QUI_GF:RefreshAllFrames()
    end)
end

---------------------------------------------------------------------------
-- SCALING: Resize frames based on group size thresholds
---------------------------------------------------------------------------
local lastMode = nil

local function UpdateFrameScaling(forceUpdate)
    local mode = GetGroupMode()
    if not forceUpdate and mode == lastMode then return end
    lastMode = mode

    if InCombatLockdown() then
        pendingResize = true
        return
    end

    local w, h = GetFrameDimensions(mode)

    -- Update header attributes (secure context — must be out of combat)
    for _, headerKey in ipairs({"party", "raid"}) do
        local header = QUI_GF.headers[headerKey]
        if header then
            header:SetAttribute("_initialAttribute-unit-width", w)
            header:SetAttribute("_initialAttribute-unit-height", h)

            -- Resize existing children
            local i = 1
            while true do
                local child = header:GetAttribute("child" .. i)
                if not child then break end
                child:SetSize(w, h)
                -- Re-layout health/power bars
                if child.healthBar and child.powerBar then
                    local general = GetGeneralSettings()
                    local borderPx = general and general.borderSize or 1
                    local borderSize = borderPx > 0 and (QUICore.Pixels and QUICore:Pixels(borderPx, child) or borderPx) or 0
                    local powerSettings = GetPowerSettings()
                    local powerHeight = powerSettings and powerSettings.showPowerBar ~= false and
                        (QUICore.PixelRound and QUICore:PixelRound(powerSettings.powerBarHeight or 4, child) or 4) or 0
                    local px = QUICore.GetPixelSize and QUICore:GetPixelSize(child) or 1
                    local sepH = powerHeight > 0 and px or 0

                    child.healthBar:ClearAllPoints()
                    child.healthBar:SetPoint("TOPLEFT", child, "TOPLEFT", borderSize, -borderSize)
                    child.healthBar:SetPoint("BOTTOMRIGHT", child, "BOTTOMRIGHT", -borderSize, borderSize + powerHeight + sepH)

                    if child.powerBar then
                        child.powerBar:ClearAllPoints()
                        child.powerBar:SetPoint("BOTTOMLEFT", child, "BOTTOMLEFT", borderSize, borderSize)
                        child.powerBar:SetPoint("BOTTOMRIGHT", child, "BOTTOMRIGHT", -borderSize, borderSize)
                        child.powerBar:SetHeight(powerHeight)
                    end
                end
                i = i + 1
            end
        end
    end

    UpdateHeaderSizes()
end

---------------------------------------------------------------------------
-- RANGE CHECK: Ticker-based range dimming (spell-based for combat safety)
---------------------------------------------------------------------------
local rangeCheckTicker = nil

-- Spec → friendly spell ID for range checking (validated with IsPlayerSpell).
-- Spec-based gives better coverage than class-based: every healer/caster spec
-- has a friendly spell that returns true/false (not nil) on alive targets.
local SPEC_RANGE_SPELLS = {
    -- Death Knight
    [250] = 47541,  -- Blood: Death Coil (heals undead allies, works as range check)
    [251] = 47541,  -- Frost: Death Coil
    [252] = 47541,  -- Unholy: Death Coil
    -- Demon Hunter
    [577] = nil,    -- Havoc: no friendly spell
    [581] = nil,    -- Vengeance: no friendly spell
    -- Druid
    [102] = 8936,   -- Balance: Regrowth
    [103] = 8936,   -- Feral: Regrowth
    [104] = 8936,   -- Guardian: Regrowth
    [105] = 774,    -- Restoration: Rejuvenation
    -- Evoker
    [1467] = 360995, -- Devastation: Emerald Blossom
    [1468] = 360995, -- Preservation: Emerald Blossom
    [1473] = 360995, -- Augmentation: Emerald Blossom
    -- Hunter
    [253] = nil,    -- Beast Mastery
    [254] = nil,    -- Marksmanship
    [255] = nil,    -- Survival
    -- Mage
    [62]  = 1459,   -- Arcane: Arcane Intellect
    [63]  = 1459,   -- Fire: Arcane Intellect
    [64]  = 1459,   -- Frost: Arcane Intellect
    -- Monk
    [268] = 116670, -- Brewmaster: Vivify
    [269] = 116670, -- Windwalker: Vivify
    [270] = 116670, -- Mistweaver: Vivify
    -- Paladin
    [65]  = 19750,  -- Holy: Flash of Light
    [66]  = 19750,  -- Protection: Flash of Light
    [70]  = 19750,  -- Retribution: Flash of Light
    -- Priest
    [256] = 17,     -- Discipline: Power Word: Shield
    [257] = 2061,   -- Holy: Flash Heal
    [258] = 17,     -- Shadow: Power Word: Shield
    -- Rogue
    [259] = 57934,  -- Assassination: Tricks of the Trade
    [260] = 57934,  -- Outlaw: Tricks of the Trade
    [261] = 57934,  -- Subtlety: Tricks of the Trade
    -- Shaman
    [262] = 8004,   -- Elemental: Healing Surge
    [263] = 8004,   -- Enhancement: Healing Surge
    [264] = 8004,   -- Restoration: Healing Surge
    -- Warlock
    [265] = 5697,   -- Affliction: Unending Breath
    [266] = 5697,   -- Demonology: Unending Breath
    [267] = 5697,   -- Destruction: Unending Breath
    -- Warrior
    [71]  = nil,    -- Arms
    [72]  = nil,    -- Fury
    [73]  = nil,    -- Protection
}

-- Class fallback: used if spec not detected or spec spell not known
local CLASS_RANGE_SPELLS = {
    PRIEST      = { 2061, 17 },          -- Flash Heal, Power Word: Shield
    PALADIN     = { 19750 },             -- Flash of Light
    DRUID       = { 8936, 774 },         -- Regrowth, Rejuvenation
    SHAMAN      = { 8004 },              -- Healing Surge
    MONK        = { 116670 },            -- Vivify
    EVOKER      = { 360995, 361469 },    -- Emerald Blossom, Living Flame
    MAGE        = { 1459 },              -- Arcane Intellect
    WARLOCK     = { 5697 },              -- Unending Breath
    ROGUE       = { 57934 },             -- Tricks of the Trade
    DEATHKNIGHT = { 47541 },             -- Death Coil
    WARRIOR     = {},
    DEMONHUNTER = {},
    HUNTER      = {},
}

-- Class → single rez spell ID for dead-target range checking.
local RES_SPELLS = {
    PRIEST      = 2006,   -- Resurrection
    PALADIN     = 7328,   -- Redemption
    DRUID       = 50769,  -- Revive
    SHAMAN      = 2008,   -- Ancestral Spirit
    MONK        = 115178, -- Resuscitate
    EVOKER      = 361227, -- Return
    DEATHKNIGHT = 61999,  -- Raise Ally
}

local playerClass = nil
local rangeSpell = nil   -- Resolved friendly spell ID for living targets
local resSpell = nil     -- Resolved rez spell ID for dead targets
local rangeCache = {}    -- unit → boolean (change detection, avoids redundant SetAlpha)

local function ResolveRangeSpells()
    if not playerClass then
        playerClass = select(2, UnitClass("player"))
    end

    -- Clear cache — spells changed, previous results may be stale
    wipe(rangeCache)

    -- Resolve primary range spell (spec-based first, then class fallback)
    rangeSpell = nil
    local specIndex = GetSpecialization and GetSpecialization()
    local specID = specIndex and GetSpecializationInfo and GetSpecializationInfo(specIndex)
    if specID and SPEC_RANGE_SPELLS[specID] then
        local spellID = SPEC_RANGE_SPELLS[specID]
        if spellID and IsPlayerSpell(spellID) then
            rangeSpell = spellID
        end
    end

    -- Class fallback if spec lookup didn't resolve
    if not rangeSpell then
        local candidates = CLASS_RANGE_SPELLS[playerClass]
        if candidates then
            for _, spellID in ipairs(candidates) do
                if IsPlayerSpell(spellID) then
                    rangeSpell = spellID
                    break
                end
            end
        end
    end

    -- Resolve rez spell
    resSpell = nil
    local rezID = RES_SPELLS[playerClass]
    if rezID and IsPlayerSpell(rezID) then
        resSpell = rezID
    end
end

local function CheckUnitRange(unit)
    if UnitIsUnit(unit, "player") then return true end
    if not UnitExists(unit) then return true end

    local connected = UnitIsConnected(unit)
    if IsSecretValue(connected) then connected = true end
    if not connected then
        if not IsNPCPartyMember(unit) then return true end
    end

    local isDead = UnitIsDeadOrGhost(unit)
    if IsSecretValue(isDead) then isDead = false end

    local spellReturnedNil = false

    -- Primary: friendly spell range check
    -- IsSpellInRange returns true/false/nil (normal booleans, not secret values)
    if rangeSpell and not isDead then
        local result = C_Spell.IsSpellInRange(rangeSpell, unit)
        if result ~= nil then
            return result
        else
            spellReturnedNil = true
        end
    end

    -- Dead target: rez spell range check
    if isDead and resSpell then
        local result = C_Spell.IsSpellInRange(resSpell, unit)
        if result ~= nil then return result end
    end

    -- Out of combat: interact distance (~28 yards)
    if not InCombatLockdown() then
        return CheckInteractDistance(unit, 4)
    end

    -- NIL-ON-ALIVE: friendly spell returned nil on alive connected target in
    -- combat — target is likely extremely distant (outside position awareness).
    if spellReturnedNil and connected and not isDead then
        return false
    end

    -- In-combat last resort: UnitInRange (Warrior/DH/Hunter with no friendly spell)
    if UnitInRange then
        local inRange, checked = UnitInRange(unit)
        -- Guard against secret values (Midnight+)
        if IsSecretValue(inRange) or IsSecretValue(checked) then
            return true  -- Can't trust secret values, assume in range
        end
        if checked and not inRange then return false end
    end

    -- No method available — assume in range
    return true
end

local function DoRangeCheck()
    local rangeSettings = GetRangeSettings()
    if not rangeSettings or rangeSettings.enabled == false then return end

    local outAlpha = rangeSettings.outOfRangeAlpha or 0.4

    for unit, frame in pairs(QUI_GF.unitFrameMap) do
        if frame and frame:IsShown() then
            local inRange = CheckUnitRange(unit)
            local state = GetFrameState(frame)

            if rangeCache[unit] ~= inRange then
                rangeCache[unit] = inRange
                state.outOfRange = not inRange
                frame:SetAlpha(inRange and 1 or outAlpha)
            elseif state.outOfRange == nil then
                state.outOfRange = not inRange
                frame:SetAlpha(inRange and 1 or outAlpha)
            end
        end
    end
end

local function StartRangeCheck()
    if rangeCheckTicker then return end
    local rangeSettings = GetRangeSettings()
    if not rangeSettings or rangeSettings.enabled == false then return end

    -- Ensure spells are resolved before starting
    if not rangeSpell and not resSpell then
        ResolveRangeSpells()
    end

    -- Longer interval for large raids
    local interval = GetGroupSize() > 25 and 0.3 or 0.2
    rangeCheckTicker = C_Timer.NewTicker(interval, DoRangeCheck)
end

local function StopRangeCheck()
    if rangeCheckTicker then
        rangeCheckTicker:Cancel()
        rangeCheckTicker = nil
    end
    wipe(rangeCache)
end

---------------------------------------------------------------------------
-- EVENTS: Centralized event dispatch
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")

local function OnEvent(self, event, arg1, ...)
    if not QUI_GF.initialized then return end
    local db = GetSettings()
    if not db or not db.enabled then return end

    -- Unit-specific events — dispatch via lookup map
    local frame = arg1 and QUI_GF.unitFrameMap[arg1]

    -- Self-healing: rebuild map on lookup miss (QUI pattern)
    -- Handles stale maps from combat zone transitions or delayed header updates
    if arg1 and not frame and (arg1:match("^party%d") or arg1:match("^raid%d") or arg1 == "player") then
        local now = GetTime()
        if not QUI_GF.lastMapRebuild or (now - QUI_GF.lastMapRebuild) > 1.0 then
            QUI_GF.lastMapRebuild = now
            RebuildUnitFrameMap()
            frame = QUI_GF.unitFrameMap[arg1]
        end
    end

    if frame then

        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            -- No throttle — UNIT_HEALTH is already coalesced by the WoW client.
            -- Throttling drops the final update, leaving the bar stale.
            -- Process every UNIT_HEALTH without throttling.
            UpdateHealth(frame)
            UpdateAbsorbs(frame)
            UpdateHealPrediction(frame)

        elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
            local now = GetTime()
            local last = powerThrottle[arg1] or 0
            if (now - last) < THROTTLE_INTERVAL then return end
            powerThrottle[arg1] = now
            UpdatePower(frame)

        elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" then
            UpdateAbsorbs(frame)

        elseif event == "UNIT_HEAL_PREDICTION" then
            UpdateHealPrediction(frame)

        elseif event == "UNIT_NAME_UPDATE" then
            UpdateName(frame)

        elseif event == "UNIT_THREAT_SITUATION_UPDATE" then
            UpdateThreat(frame)

        elseif event == "UNIT_AURA" then
            -- All aura-driven updates (icons, dispel, defensive) are handled
            -- by the shared throttled scan in groupframes_auras.lua.
            -- This avoids redundant GetUnitAuras calls.

        elseif event == "UNIT_CONNECTION" or event == "UNIT_FLAGS" then
            UpdateConnection(frame)
            UpdateHealth(frame)

        elseif event == "UNIT_PHASE" then
            UpdatePhaseIcon(frame)

        elseif event == "INCOMING_RESURRECT_CHANGED" then
            UpdateResurrection(frame)

        elseif event == "INCOMING_SUMMON_CHANGED" then
            UpdateSummonPending(frame)

        elseif event == "READY_CHECK_CONFIRM" then
            -- READY_CHECK_CONFIRM arg1 is a unit token, so it lands here.
            -- Update ALL frames (not just the confirming unit) to stay consistent.
            for _, f in pairs(QUI_GF.unitFrameMap) do
                UpdateReadyCheck(f)
            end
        end
        return
    end

    -- Non-unit events — iterate relevant frames
    if event == "GROUP_ROSTER_UPDATE" then
        UpdateHeaderVisibility()
        UpdateFrameScaling(true)
        UpdateHeaderSizes()
        -- Rebuild map after a short delay (header needs time to create children)
        StopRangeCheck()
        C_Timer.After(0.2, function()
            DecorateHeaderChildren(QUI_GF.headers.party)
            DecorateHeaderChildren(QUI_GF.headers.raid)
            RebuildUnitFrameMap()
            UpdateFrameScaling(true)
            QUI_GF:RefreshAllFrames()
            -- Restart range check AFTER map rebuild so it iterates fresh data
            StartRangeCheck()
        end)

    elseif event == "PLAYER_TARGET_CHANGED" then
        for _, frame in pairs(QUI_GF.unitFrameMap) do
            UpdateTargetHighlight(frame)
        end

    elseif event == "READY_CHECK" or event == "READY_CHECK_CONFIRM" then
        -- QUI pattern: iterate all frames for both events.
        -- READY_CHECK fires with arg1=initiatorName (not a unit token).
        -- READY_CHECK_CONFIRM fires per-unit but we refresh all frames to
        -- avoid relying on unitFrameMap lookup which can miss stale tokens.
        for _, frame in pairs(QUI_GF.unitFrameMap) do
            UpdateReadyCheck(frame)
        end

    elseif event == "READY_CHECK_FINISHED" then
        -- Do NOT call UpdateReadyCheck here — GetReadyCheckStatus returns nil
        -- after READY_CHECK_FINISHED, which would hide icons immediately.
        -- Icons already show the correct state from READY_CHECK_CONFIRM events.
        -- Just schedule hiding after persist delay (QUI pattern).
        for _, frame in pairs(QUI_GF.unitFrameMap) do
            -- Cancel any existing timer for this frame
            if frame._readyCheckHideTimer then
                frame._readyCheckHideTimer:Cancel()
                frame._readyCheckHideTimer = nil
            end
            frame._readyCheckHideTimer = C_Timer.NewTimer(6, function()
                if frame.readyCheckIcon then
                    frame.readyCheckIcon:Hide()
                end
                frame._readyCheckHideTimer = nil
            end)
        end

    elseif event == "RAID_TARGET_UPDATE" then
        for _, frame in pairs(QUI_GF.unitFrameMap) do
            UpdateTargetMarker(frame)
        end

    elseif event == "PARTY_LEADER_CHANGED" then
        for _, frame in pairs(QUI_GF.unitFrameMap) do
            UpdateLeaderIcon(frame)
        end

    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Combat started: clear range cache so stale OOC values
        -- (CheckInteractDistance) don't persist into combat where
        -- that API is unavailable. (QUI pattern)
        wipe(rangeCache)

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Combat ended: clear range cache so combat-era results
        -- don't prevent OOC methods from updating.
        wipe(rangeCache)

        -- Process deferred operations
        if pendingResize then
            pendingResize = false
            UpdateFrameScaling()
        end
        if pendingVisibilityUpdate then
            pendingVisibilityUpdate = false
            UpdateHeaderVisibility()
        end
        if pendingInitialize then
            pendingInitialize = false
            QUI_GF:Initialize()
        end
        if pendingRegisterClicks then
            pendingRegisterClicks = false
            DecorateHeaderChildren(QUI_GF.headers.party)
            DecorateHeaderChildren(QUI_GF.headers.raid)
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1.0, function()
            UpdateHeaderVisibility()
            UpdateFrameScaling()
            ResolveRangeSpells()
        end)

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "SPELLS_CHANGED" then
        ResolveRangeSpells()
    end
end

eventFrame:SetScript("OnEvent", OnEvent)

---------------------------------------------------------------------------
-- EVENT REGISTRATION
---------------------------------------------------------------------------
local function RegisterEvents()
    -- Group events
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

    -- Unit events (will be routed via unitFrameMap)
    eventFrame:RegisterEvent("UNIT_HEALTH")
    eventFrame:RegisterEvent("UNIT_MAXHEALTH")
    eventFrame:RegisterEvent("UNIT_POWER_UPDATE")
    eventFrame:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
    eventFrame:RegisterEvent("UNIT_HEAL_PREDICTION")
    eventFrame:RegisterEvent("UNIT_NAME_UPDATE")
    eventFrame:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    eventFrame:RegisterEvent("UNIT_AURA")
    eventFrame:RegisterEvent("UNIT_CONNECTION")
    eventFrame:RegisterEvent("UNIT_FLAGS")
    eventFrame:RegisterEvent("UNIT_PHASE")
    eventFrame:RegisterEvent("INCOMING_RESURRECT_CHANGED")
    eventFrame:RegisterEvent("INCOMING_SUMMON_CHANGED")

    -- Non-unit events
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("SPELLS_CHANGED")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("READY_CHECK")
    eventFrame:RegisterEvent("READY_CHECK_CONFIRM")
    eventFrame:RegisterEvent("READY_CHECK_FINISHED")
    eventFrame:RegisterEvent("RAID_TARGET_UPDATE")
    eventFrame:RegisterEvent("PARTY_LEADER_CHANGED")
end

local function UnregisterEvents()
    eventFrame:UnregisterAllEvents()
end

---------------------------------------------------------------------------
-- SELECTIVE EVENT REGISTRATION: Unregister power events for large raids
---------------------------------------------------------------------------
local function UpdateSelectiveEvents()
    local db = GetSettings()
    local powerSettings = GetPowerSettings()
    local mode = GetGroupMode()

    if mode == "large" and (not powerSettings or powerSettings.showPowerBar == false) then
        eventFrame:UnregisterEvent("UNIT_POWER_UPDATE")
        eventFrame:UnregisterEvent("UNIT_POWER_FREQUENT")
    else
        eventFrame:RegisterEvent("UNIT_POWER_UPDATE")
    end
end

---------------------------------------------------------------------------
-- PUBLIC: Expose dispel/defensive updates for the shared aura scan in
-- groupframes_auras.lua (avoids redundant GetUnitAuras calls)
---------------------------------------------------------------------------
function QUI_GF:UpdateDispelOverlay(frame)
    UpdateDispelOverlay(frame)
end

function QUI_GF:UpdateDefensiveIndicator(frame)
    UpdateDefensiveIndicator(frame)
end

---------------------------------------------------------------------------
-- REFRESH ALL: Update all visible frames
---------------------------------------------------------------------------
function QUI_GF:RefreshAllFrames()
    for _, frame in pairs(self.unitFrameMap) do
        if frame and frame:IsShown() then
            UpdateFrame(frame)
        end
    end

    -- Also trigger aura/indicator updates via module callbacks
    if ns.QUI_GroupFrameAuras and ns.QUI_GroupFrameAuras.RefreshAll then
        ns.QUI_GroupFrameAuras:RefreshAll()
    end
    if ns.QUI_GroupFrameIndicators and ns.QUI_GroupFrameIndicators.RefreshAll then
        ns.QUI_GroupFrameIndicators:RefreshAll()
    end
    if ns.QUI_GroupFramePrivateAuras and ns.QUI_GroupFramePrivateAuras.RefreshAll then
        ns.QUI_GroupFramePrivateAuras:RefreshAll()
    end
end

---------------------------------------------------------------------------
-- REFRESH: Settings changed (called from options panel)
---------------------------------------------------------------------------
function QUI_GF:RefreshSettings()
    InvalidateCache()
    dispelColorCurve = nil  -- Rebuild with new opacity on next use

    if not self.initialized then
        return
    end

    local db = GetSettings()
    if not db or not db.enabled then
        self:Disable()
        return
    end

    if InCombatLockdown() then
        pendingResize = true
        return
    end

    -- Re-configure headers
    if self.headers.party then ConfigurePartyHeader(self.headers.party) end
    if self.headers.raid then ConfigureRaidHeader(self.headers.raid) end

    -- Force re-decoration of all children
    for _, frame in pairs(self.allFrames) do
        frame._quiDecorated = false
    end
    wipe(self.allFrames)

    -- Also clear decorated flag on header children directly
    for _, headerKey in ipairs({"party", "raid"}) do
        local header = self.headers[headerKey]
        if header then
            local i = 1
            while true do
                local child = header:GetAttribute("child" .. i)
                if not child then break end
                child._quiDecorated = false
                i = i + 1
            end
        end
    end

    -- Update visibility + redecorate
    UpdateHeaderVisibility()
    UpdateFrameScaling(true)
    UpdateHeaderSizes()
    UpdateSelectiveEvents()
end

---------------------------------------------------------------------------
-- HUD LAYERING
---------------------------------------------------------------------------
local function ApplyHUDLayering()
    local profile = QUI.db and QUI.db.profile
    local layering = profile and profile.hudLayering
    local level = layering and layering.groupFrames or 4

    if QUICore.GetHUDFrameLevel then
        local frameLevel = QUICore:GetHUDFrameLevel(level)
        for _, headerKey in ipairs({"party", "raid"}) do
            local header = QUI_GF.headers[headerKey]
            if header then
                pcall(header.SetFrameLevel, header, frameLevel)
            end
        end
    end
end

---------------------------------------------------------------------------
-- INITIALIZE
---------------------------------------------------------------------------
function QUI_GF:Initialize()
    local db = GetSettings()
    if not db or not db.enabled then return end

    if InCombatLockdown() then
        pendingInitialize = true
        return
    end

    -- Create headers
    CreateHeaders()

    -- Register events
    RegisterEvents()

    -- Apply HUD layering
    ApplyHUDLayering()

    -- Show appropriate header based on group status
    UpdateHeaderVisibility()
    UpdateFrameScaling(true)

    -- Resolve range check spells and start ticker
    ResolveRangeSpells()
    StartRangeCheck()

    self.initialized = true

    -- Initialize click-casting
    local GFCC = ns.QUI_GroupFrameClickCast
    if GFCC then
        GFCC:Initialize()
    end

    -- Hide Blizzard group frames
    if ns.QUI_GroupFrameBlizzard and ns.QUI_GroupFrameBlizzard.HideBlizzardFrames then
        ns.QUI_GroupFrameBlizzard:HideBlizzardFrames()
    end

    -- Delayed full refresh
    C_Timer.After(1.5, function()
        self:RefreshAllFrames()
    end)
end

---------------------------------------------------------------------------
-- DISABLE
---------------------------------------------------------------------------
function QUI_GF:Disable()
    UnregisterEvents()
    StopRangeCheck()

    if InCombatLockdown() then return end

    for _, headerKey in ipairs({"party", "raid"}) do
        local header = self.headers[headerKey]
        if header then
            header:Hide()
        end
    end

    if ns.QUI_GroupFramePrivateAuras and ns.QUI_GroupFramePrivateAuras.CleanupAll then
        ns.QUI_GroupFramePrivateAuras:CleanupAll()
    end

    wipe(self.unitFrameMap)
    self.initialized = false

    -- Restore Blizzard frames
    if ns.QUI_GroupFrameBlizzard and ns.QUI_GroupFrameBlizzard.RestoreBlizzardFrames then
        ns.QUI_GroupFrameBlizzard:RestoreBlizzardFrames()
    end
end

---------------------------------------------------------------------------
-- STARTUP: Init on PLAYER_LOGIN
---------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(0.5, function()
            QUI_GF:Initialize()
        end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        if QUI_GF.initialized then
            C_Timer.After(1.0, function()
                UpdateHeaderVisibility()
                UpdateFrameScaling(true)
                QUI_GF:RefreshAllFrames()
            end)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingInitialize then
            pendingInitialize = false
            QUI_GF:Initialize()
        end
    end
end)

---------------------------------------------------------------------------
-- PUBLIC API (for other modules)
---------------------------------------------------------------------------
function QUI_GF:GetUnitFrame(unit)
    return self.unitFrameMap[unit]
end

function QUI_GF:GetAllFrames()
    return self.unitFrameMap
end

function QUI_GF:GetHeaders()
    return self.headers
end

function QUI_GF:IsEnabled()
    local db = GetSettings()
    return db and db.enabled
end

function QUI_GF:IsInitialized()
    return self.initialized
end

-- Global refresh function for options panel
_G.QUI_RefreshGroupFrames = function()
    QUI_GF:RefreshSettings()
    -- Also refresh test/preview frames if active
    local editMode = ns.QUI_GroupFrameEditMode
    if editMode and editMode.RefreshTestMode then
        editMode:RefreshTestMode()
    end
end
