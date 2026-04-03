--[[
    QUI Group Frames - Party/Raid Frame System
    Creates secure group headers with auto-managed child frames for party and raid.
    Features: Class colors, absorbs, heal prediction, dispel overlay, range check,
    role icons, threat borders, target highlight, unified scaling, click-casting support.
]]

local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local LSM = ns.LSM
local Helpers = ns.Helpers
local IsSecretValue = Helpers.IsSecretValue
local SafeValue = Helpers.SafeValue
local SafeToNumber = Helpers.SafeToNumber
local issecretvalue = _G.issecretvalue
local GetDB = Helpers.CreateDBGetter("quiGroupFrames")

local GetCore = Helpers.GetCore

-- Upvalue caching for hot-path performance
local type = type
local pairs = pairs
local ipairs = ipairs
local pcall = pcall
local wipe = wipe
local tostring = tostring
local table_sort = table.sort
local table_insert = table.insert
local table_concat = table.concat
local select = select
local format = format
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime
local hooksecurefunc = hooksecurefunc
local string_format = string.format
local math_floor = math.floor
local math_min = math.min
local math_max = math.max

-- Upvalue hot-path WoW APIs
local UnitExists = UnitExists
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitClass = UnitClass
local UnitName = UnitName
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsConnected = UnitIsConnected
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitThreatSituation = UnitThreatSituation
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local UnitGetTotalHealAbsorbs = UnitGetTotalHealAbsorbs
local UnitIsUnit = UnitIsUnit
local UnitGUID = UnitGUID
local GetNumGroupMembers = GetNumGroupMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local RAID_CLASS_COLORS = RAID_CLASS_COLORS

-- Consolidated state/cache table to stay under Lua's 200-local limit.
-- Non-hot-path booleans, cached refs, and simple state live here.
local _state = {
    inInitSafeWindow = false,
    gruDeferredPending = false,
    cachedVDB_party = nil,
    cachedVDB_raid = nil,
    cachedModuleEnabled = false,
    cachedModuleDB = nil,
    lastMode = nil,
    rangeCheckTicker = nil,
    unitGuidCache = {},
    cachedMarkers = {},
}

---------------------------------------------------------------------------
-- MODULE TABLE
---------------------------------------------------------------------------
local QUI_GF = {}
ns.QUI_GroupFrames = QUI_GF

-- Frame references
QUI_GF.headers = {}          -- "party", "raid" header frames
QUI_GF.raidGroupHeaders = {} -- raid section headers (groups or custom self-first sections)
QUI_GF.anchorFrames = {}     -- non-secure runtime roots for party/raid blocks
QUI_GF.petHeader = nil       -- pet header
QUI_GF.spotlightHeader = nil -- spotlight header
QUI_GF.allFrames = {}        -- flat list of all child frames (for iteration)
QUI_GF.unitFrameMap = {}     -- unitToken → frame (O(1) event dispatch)
QUI_GF.initialized = false
QUI_GF.testMode = false
QUI_GF.editMode = false

-- State tables for taint safety (weak-keyed)
local frameState, GetFrameState = Helpers.CreateStateTable()

local RAID_SECTION_ROLE_ORDER = { "TANK", "HEALER", "DAMAGER", "NONE" }
local RAID_SECTION_CLASS_ORDER = {
    "WARRIOR", "DEATHKNIGHT", "PALADIN", "MONK", "PRIEST", "SHAMAN", "DRUID",
    "ROGUE", "MAGE", "WARLOCK", "HUNTER", "DEMONHUNTER", "EVOKER",
}
local RAID_SECTION_ROLE_PRIORITY = {}
local RAID_SECTION_CLASS_PRIORITY = {}
for i, role in ipairs(RAID_SECTION_ROLE_ORDER) do
    RAID_SECTION_ROLE_PRIORITY[role] = i
end
for i, classFile in ipairs(RAID_SECTION_CLASS_ORDER) do
    RAID_SECTION_CLASS_PRIORITY[classFile] = i
end
local MAX_RAID_SECTION_HEADERS = #RAID_SECTION_CLASS_ORDER
local GetRaidDisplaySections
local GetRaidSectionUnitsPerColumn
local CalculateRaidSectionHeaderSize
-- _state.unitGuidCache: frame → last-known GUID (for OnAttributeChanged skip)
-- _state.cachedMarkers: [unitToken] → markerIndex (RAID_TARGET_UPDATE short-circuit)

local powerThrottle = {}      -- unitToken → last update time
local THROTTLE_INTERVAL = 0.1 -- 100ms coalesce window

---------------------------------------------------------------------------
-- CACHED BACKDROP TABLES: Avoid allocating a new table every SetBackdrop
-- call. SetBackdrop does field-by-field comparison, but reusing the same
-- table reference lets it short-circuit and reduces GC pressure.
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- GROUP_ROSTER_UPDATE coalescing: GRU fires in bursts of 5-20 during roster
-- changes. Showing an already-shown frame is a no-op (automatic dedup), so
-- all GRU events in a single render frame collapse into one OnUpdate tick.
---------------------------------------------------------------------------
local gruCoalesceFrame = CreateFrame("Frame")
gruCoalesceFrame:Hide()
-- _state.gruDeferredPending: true while the 0.2s deferred timer is active

-- Font/texture caching
local _fontCache = {}

-- Pre-allocated color tables for common colors
local COLORS = {
    BLACK   = { 0, 0, 0, 1 },
    WHITE   = { 1, 1, 1, 1 },
    DEAD    = { 0.5, 0.5, 0.5, 1 },
    OFFLINE = { 0.4, 0.4, 0.4, 1 },
    GHOST   = { 0.6, 0.6, 0.6, 1 },
}

-- Dispel constants and cached state
local _dispel = {
    defaultColors = {
        Magic   = { 0.2, 0.6, 1.0, 1 },  -- Blue
        Curse   = { 0.6, 0.0, 1.0, 1 },  -- Purple
        Disease = { 0.6, 0.4, 0.0, 1 },  -- Brown
        Poison  = { 0.0, 0.6, 0.0, 1 },  -- Green
        Bleed   = { 0.8, 0.0, 0.0, 1 },  -- Red
    },
    allEnums = {1, 2, 3, 4, 9, 11},  -- WoW 12.0+, from SpellDispelType DB2
    enumNames = {
        [1] = "Magic", [2] = "Curse", [3] = "Disease", [4] = "Poison",
        [9] = "Bleed", [11] = "Bleed",
    },
    colorCurve = nil,
    cachedColors = nil,
    borderKeys = {"borderTop", "borderBottom", "borderLeft", "borderRight"},
}

-- Forward declarations; bodies defined later in file
local GetDispelColors
local InvalidateDispelColors
local UpdateSelectiveEvents

local function GetDispelColorCurve(opacity)
    if _dispel.colorCurve then return _dispel.colorCurve end
    if not C_CurveUtil or not C_CurveUtil.CreateColorCurve then return nil end
    local colors = GetDispelColors()
    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    curve:AddPoint(0, CreateColor(0, 0, 0, 0))  -- None = invisible
    for _, enumVal in ipairs(_dispel.allEnums) do
        local typeName = _dispel.enumNames[enumVal]
        local c = typeName and colors[typeName]
        if c then
            curve:AddPoint(enumVal, CreateColor(c[1], c[2], c[3], opacity or 0.8))
        end
    end
    _dispel.colorCurve = curve
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

-- Pending combat-deferred operations (consolidated to stay under Lua's 200-local limit)
local _pending = {
    resize = false,
    resizeForce = false,
    refreshSettings = false,
    visibilityUpdate = false,
    registerClicks = false,
    groupReflow = false,
    anchorUpdate = false,
    initSafe = true,
}

-- Multi-header mode: true when groupBy == "GROUP" (each raid group gets its own header).
-- The default groupBy is "GROUP" so nil also means multi-header.
local function IsMultiHeaderMode()
    local db = GetDB()
    if not db then return false end
    local raidVdb = db.raid or db
    local raidLayout = raidVdb and raidVdb.layout
    local groupBy = raidLayout and raidLayout.groupBy or "GROUP"
    return groupBy == "GROUP"
end

---------------------------------------------------------------------------
-- HELPERS: Settings access
---------------------------------------------------------------------------
local function GetSettings()
    return GetDB()
end

local function GetPartySelfFirst(db)
    db = db or GetSettings()
    if not db then return false end
    if db.partySelfFirst ~= nil then
        return db.partySelfFirst == true
    end
    return db.selfFirst == true
end

local function GetRaidSelfFirst(db)
    db = db or GetSettings()
    if not db then return false end
    if db.raidSelfFirst ~= nil then
        return db.raidSelfFirst == true
    end
    return db.selfFirst == true
end

local function UseRaidSectionHeaders(db)
    db = db or GetSettings()
    if not db then return false end
    return IsMultiHeaderMode() or GetRaidSelfFirst(db)
end

local function GetLayoutGrowDirection(layout, fallback)
    local grow = layout and layout.growDirection
    if grow == "UP" or grow == "DOWN" or grow == "LEFT" or grow == "RIGHT" then
        return grow
    end

    local orientation = layout and layout.orientation
    if orientation == "HORIZONTAL" then
        return "RIGHT"
    elseif orientation == "VERTICAL" then
        return "DOWN"
    end

    return fallback or "DOWN"
end

local function GetRaidColumnAnchorPoint(layout, grow)
    local horizontal = (grow == "LEFT" or grow == "RIGHT")
    if horizontal then
        -- When units grow horizontally, additional columns stack vertically.
        return "TOP"
    end

    local groupGrow = layout and layout.groupGrowDirection
    if groupGrow == "LEFT" then
        return "RIGHT"
    end
    return "LEFT"
end

-- Returns the party or raid visual settings sub-table.
-- Cached per party/raid to avoid 5-6 table lookups per call in hot paths
-- (UNIT_HEALTH fires for every damaged unit — 4 sub-functions each call this).
local function GetVisualDB(isRaid)
    if isRaid then
        if _state.cachedVDB_raid then return _state.cachedVDB_raid end
    else
        if _state.cachedVDB_party then return _state.cachedVDB_party end
    end
    local db = GetDB()
    if not db then return nil end
    if isRaid then
        _state.cachedVDB_raid = db.raid or db
        return _state.cachedVDB_raid
    else
        _state.cachedVDB_party = db.party or db
        return _state.cachedVDB_party
    end
end

local function GetGeneralSettings(isRaid)
    local vdb = GetVisualDB(isRaid)
    return vdb and vdb.general
end

local function GetLayoutSettings(isRaid)
    local vdb = GetVisualDB(isRaid)
    return vdb and vdb.layout
end

local function GetDimensionSettings(isRaid)
    local vdb = GetVisualDB(isRaid)
    return vdb and vdb.dimensions
end

local function GetHealthSettings(isRaid)
    local vdb = GetVisualDB(isRaid)
    return vdb and vdb.health
end

local function GetHealthFillDirection(isRaid)
    local vdb = GetVisualDB(isRaid)
    local h = vdb and vdb.health
    return h and h.healthFillDirection or "HORIZONTAL"
end

local function GetPowerSettings(isRaid)
    local vdb = GetVisualDB(isRaid)
    return vdb and vdb.power
end

local function GetNameSettings(isRaid)
    local vdb = GetVisualDB(isRaid)
    return vdb and vdb.name
end

local function GetIndicatorSettings(isRaid)
    local vdb = GetVisualDB(isRaid)
    return vdb and vdb.indicators
end

local function GetHealerSettings(isRaid)
    local vdb = GetVisualDB(isRaid)
    return vdb and vdb.healer
end

GetDispelColors = function()
    if _dispel.cachedColors then return _dispel.cachedColors end
    local hs = GetHealerSettings()
    local dbColors = hs and hs.dispelOverlay and hs.dispelOverlay.colors
    if not dbColors then
        _dispel.cachedColors = _dispel.defaultColors
        return _dispel.defaultColors
    end
    _dispel.cachedColors = {
        Magic   = dbColors.Magic   or _dispel.defaultColors.Magic,
        Curse   = dbColors.Curse   or _dispel.defaultColors.Curse,
        Disease = dbColors.Disease or _dispel.defaultColors.Disease,
        Poison  = dbColors.Poison  or _dispel.defaultColors.Poison,
        Bleed   = dbColors.Bleed   or _dispel.defaultColors.Bleed,
    }
    return _dispel.cachedColors
end

InvalidateDispelColors = function()
    _dispel.cachedColors = nil
end

local function GetRangeSettings(isRaid)
    local vdb = GetVisualDB(isRaid)
    return vdb and vdb.range
end

local function GetPortraitSettings(isRaid)
    local vdb = GetVisualDB(isRaid)
    return vdb and vdb.portrait
end

---------------------------------------------------------------------------
-- HELPERS: Font and texture
---------------------------------------------------------------------------
local function GetFontPath(isRaid)
    if _fontCache.fontPath then return _fontCache.fontPath end
    local general = GetGeneralSettings(isRaid)
    local fontName = general and general.font or "Quazii"
    _fontCache.fontPath = LSM:Fetch("font", fontName) or "Fonts\\FRIZQT__.TTF"
    return _fontCache.fontPath
end

local function GetFontOutline(isRaid)
    if _fontCache.fontOutline then return _fontCache.fontOutline end
    local general = GetGeneralSettings(isRaid)
    _fontCache.fontOutline = general and general.fontOutline or "OUTLINE"
    return _fontCache.fontOutline
end

local function GetTexturePath(textureName)
    if not textureName then
        if _fontCache.texturePath then return _fontCache.texturePath end
        local general = GetGeneralSettings()
        textureName = general and general.texture or "Quazii v5"
    end
    local path = LSM and LSM:Fetch("statusbar", textureName, true)
    if not path and textureName and textureName:find("[/\\]") then
        path = textureName
    end
    if not _fontCache.texturePath then
        _fontCache.texturePath = path
    end
    return path or "Interface\\Buttons\\WHITE8X8"
end

local function ApplyStatusBarTexture(statusBar, textureName)
    if not statusBar then return end

    statusBar:SetStatusBarTexture(GetTexturePath(textureName))

    -- Some texture objects retain stale coords/tiling after reload/layout churn.
    -- Re-selecting the texture in options fixes that because WoW rebuilds the
    -- internal region state; do the same normalization here.
    local tex = statusBar:GetStatusBarTexture()
    if tex then
        tex:SetTexCoord(0, 1, 0, 1)
        if tex.SetHorizTile then tex:SetHorizTile(false) end
        if tex.SetVertTile then tex:SetVertTile(false) end
    end
end

local function InvalidateCache()
    wipe(_fontCache)
    _state.cachedVDB_party = nil
    _state.cachedVDB_raid = nil
    InvalidateDispelColors()
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
    local isRaid = (mode ~= "party")
    local dims = GetDimensionSettings(isRaid)
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

    local isRaid = memberCount > 5
    local vdb = isRaid and (db.raid or db) or (db.party or db)
    local layout = vdb.layout or (isRaid and db.raidLayout or db.partyLayout) or db.layout
    local spacing = layout and layout.spacing or 2
    local groupSpacing = layout and layout.groupSpacing or 10
    local grow = GetLayoutGrowDirection(layout, "DOWN")

    -- Determine mode from member count
    local mode
    if memberCount <= 5 then mode = "party"
    elseif memberCount <= 15 then mode = "small"
    elseif memberCount <= 25 then mode = "medium"
    else mode = "large"
    end

    local w, h = GetFrameDimensions(mode)

    local groupBy = layout and layout.groupBy or "GROUP"
    local isFlat = (groupBy == "NONE")
    local framesPerGroup = isFlat and (layout and layout.unitsPerFlat or 5) or 5
    local numGroups = math.ceil(memberCount / framesPerGroup)
    local framesInTallestGroup = math_min(memberCount, framesPerGroup)
    local colSpacing = isFlat and spacing or groupSpacing

    local horizontal = (grow == "LEFT" or grow == "RIGHT")
    local totalW, totalH

    if horizontal then
        totalW = framesInTallestGroup * w + (framesInTallestGroup - 1) * spacing
        totalH = numGroups * h + (numGroups - 1) * colSpacing
    else
        totalW = numGroups * w + (numGroups - 1) * colSpacing
        totalH = framesInTallestGroup * h + (framesInTallestGroup - 1) * spacing
    end

    return math_max(totalW, 100), math_max(totalH, 40)
end

-- Expose for sub-modules
QUI_GF.GetVisualDB = GetVisualDB
QUI_GF.CalculateHeaderSize = CalculateHeaderSize

---------------------------------------------------------------------------
-- HELPERS: Unit tooltip
---------------------------------------------------------------------------
local function ShowUnitTooltip(frame)
    local general = GetGeneralSettings(frame._isRaid)
    if not general or general.showTooltips == false then return end
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
local function GetHealthBarColor(unit, isRaid)
    local general = GetGeneralSettings(isRaid)
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
local function GetPowerBarColor(unit, isRaid)
    local db = GetPowerSettings(isRaid)
    if db and not db.powerBarUsePowerColor then
        local c = db.powerBarColor or { 0.2, 0.4, 0.8, 1 }
        return c[1], c[2], c[3], c[4] or 1
    end

    local powerType = UnitPowerType(unit)
    if powerType then
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
    -- SetMinMaxValues(0, 100) is set once at frame creation (DecorateGroupFrame) — never changes.
    if frame.healthBar then
        if isDeadOrGhost then
            frame.healthBar:SetValue(0)
        else
            local pct = GetHealthPct(unit)
            frame.healthBar:SetValue(pct)
        end

        -- Color (dirty-checked: skip SetStatusBarColor when unchanged)
        local r, g, b, a
        if not isConnected then
            r, g, b, a = COLORS.OFFLINE[1], COLORS.OFFLINE[2], COLORS.OFFLINE[3], COLORS.OFFLINE[4]
        elseif isDeadOrGhost then
            r, g, b, a = COLORS.DEAD[1], COLORS.DEAD[2], COLORS.DEAD[3], COLORS.DEAD[4]
        elseif frame._auraIndicatorHealthColor then
            local c = frame._auraIndicatorHealthColor
            r, g, b, a = c[1] or 0.2, c[2] or 0.8, c[3] or 0.2, c[4] or 1
        else
            r, g, b, a = GetHealthBarColor(unit, frame._isRaid)
        end
        if r ~= frame._lastHealthColorR
            or g ~= frame._lastHealthColorG
            or b ~= frame._lastHealthColorB
            or a ~= frame._lastHealthColorA
        then
            frame._lastHealthColorR = r
            frame._lastHealthColorG = g
            frame._lastHealthColorB = b
            frame._lastHealthColorA = a
            frame.healthBar:SetStatusBarColor(r, g, b, a)
        end
    end

    -- Centered status text overlay for dead/offline
    if frame.statusText then
        if not isConnected then
            frame.statusText:SetText("OFFLINE")
            frame.statusText:SetTextColor(COLORS.OFFLINE[1], COLORS.OFFLINE[2], COLORS.OFFLINE[3])
            frame.statusText:Show()
        elseif isDeadOrGhost then
            local isGhost = UnitIsGhost(unit)
            frame.statusText:SetText(isGhost and "GHOST" or "DEAD")
            frame.statusText:SetTextColor(COLORS.DEAD[1], COLORS.DEAD[2], COLORS.DEAD[3])
            frame.statusText:Show()
            -- Dim the frame slightly for dead units (offline dimming handled in UpdateConnection)
            frame:SetAlpha(0.65)
        else
            frame.statusText:Hide()
        end
    end

    -- Health text — use SetFormattedText (C-side) which handles secret values natively
    local isRaid = frame._isRaid
    local healthSettings = GetHealthSettings(isRaid)
    if frame.healthText and healthSettings and healthSettings.showHealthText ~= false then
        if not isConnected then
            frame.healthText:SetText("")
        elseif isDeadOrGhost then
            frame.healthText:SetText("")
        else
            local style = healthSettings.healthDisplayStyle or "percent"
            local abbr = AbbreviateNumbers or AbbreviateLargeNumbers
            local pctFmt = healthSettings.hideHealthPercentSymbol and "%.0f" or "%.0f%%"
            if style == "percent" then
                local pct = GetHealthPct(unit)
                frame.healthText:SetFormattedText(pctFmt, pct)
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
                local bothFmt = healthSettings.hideHealthPercentSymbol and "%s | %.0f" or "%s | %.0f%%"
                if abbr then
                    frame.healthText:SetFormattedText(bothFmt, abbr(hp), pct)
                else
                    frame.healthText:SetFormattedText(bothFmt, hp, pct)
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
                frame.healthText:SetFormattedText(pctFmt, pct)
            end
            local tc = healthSettings.healthTextColor or COLORS.WHITE
            frame.healthText:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
        end
    elseif frame.healthText then
        frame.healthText:SetText("")
    end
end

---------------------------------------------------------------------------
-- UPDATE: Power
---------------------------------------------------------------------------
local function ShouldShowPowerForUnit(unit, isRaid)
    local ps = GetPowerSettings(isRaid)
    if not ps then return true end
    local onlyHealers = ps.powerBarOnlyHealers
    local onlyTanks = ps.powerBarOnlyTanks
    if not onlyHealers and not onlyTanks then return true end
    local role = UnitGroupRolesAssigned(unit)
    if onlyHealers and role == "HEALER" then return true end
    if onlyTanks and role == "TANK" then return true end
    return false
end

local function ResizeHealthForPower(frame, showPowerForUnit)
    if not frame.healthBar then return end
    local isRaid = frame._isRaid
    local general = GetGeneralSettings(isRaid)
    local borderPx = general and general.borderSize or 1
    local borderSize = borderPx > 0 and (QUICore.Pixels and QUICore:Pixels(borderPx, frame) or borderPx) or 0
    local px = QUICore.GetPixelSize and QUICore:GetPixelSize(frame) or 1

    local bottomPad = borderSize
    if showPowerForUnit then
        local powerSettings = GetPowerSettings(isRaid)
        local powerHeight = QUICore.PixelRound and QUICore:PixelRound(powerSettings.powerBarHeight or 4, frame) or 4
        bottomPad = borderSize + powerHeight + px
    end

    frame.healthBar:ClearAllPoints()
    frame.healthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", borderSize, -borderSize)
    frame.healthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, bottomPad)
end

local function UpdatePower(frame)
    if not frame or not frame.unit or not frame.powerBar then return end
    local unit = frame.unit

    if not UnitExists(unit) then
        frame.powerBar:SetValue(0)
        return
    end

    -- Role-based filtering
    if not ShouldShowPowerForUnit(unit, frame._isRaid) then
        frame.powerBar:Hide()
        if frame._powerSeparator then frame._powerSeparator:Hide() end
        if frame._powerBg then frame._powerBg:Hide() end
        ResizeHealthForPower(frame, false)
        return
    end
    frame.powerBar:Show()
    if frame._powerSeparator then frame._powerSeparator:Show() end
    if frame._powerBg then frame._powerBg:Show() end
    ResizeHealthForPower(frame, true)

    local power = UnitPower(unit)
    local maxPower = UnitPowerMax(unit)

    -- UnitPower/UnitPowerMax return nil for arena opponents — hide the bar.
    if type(power) ~= "number" or type(maxPower) ~= "number" then
        frame.powerBar:Hide()
        return
    end

    -- C-side SetMinMaxValues/SetValue handle secret values natively.
    -- Only update SetMinMaxValues when maxPower actually changes (rare: buffs/talents).
    -- Guard the Lua-side comparison with IsSecretValue to avoid errors from
    -- taint-propagated secret values.
    if IsSecretValue(maxPower) or maxPower ~= frame._lastMaxPower then
        if not IsSecretValue(maxPower) then
            frame._lastMaxPower = maxPower
        end
        frame.powerBar:SetMinMaxValues(0, maxPower)
    end
    frame.powerBar:SetValue(power)

    -- Color (dirty-checked: power color changes only on form/spec change, not every tick)
    local r, g, b, a = GetPowerBarColor(unit, frame._isRaid)
    if r ~= frame._lastPowerColorR then
        frame._lastPowerColorR = r
        frame.powerBar:SetStatusBarColor(r, g, b, a)
    end
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

    local isRaid = frame._isRaid
    local nameSettings = GetNameSettings(isRaid)
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
        local tc = nameSettings and nameSettings.nameTextColor or COLORS.WHITE
        frame.nameText:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
    else
        frame.nameText:SetText("")
    end
end

---------------------------------------------------------------------------
-- UPDATE: Absorbs
---------------------------------------------------------------------------
-- Absorbs: optional pre-computed args from fast health path avoid redundant API calls.
local function UpdateAbsorbs(frame, _unit, _maxHP)
    if not frame or not frame.absorbBar then return end
    local isRaid = frame._isRaid
    local vdb = GetVisualDB(isRaid)
    if not vdb or not vdb.absorbs or vdb.absorbs.enabled == false then
        frame.absorbBar:Hide()
        return
    end

    local unit = _unit or frame.unit
    if not unit then return end

    -- When called standalone (UNIT_ABSORB_AMOUNT_CHANGED), do our own guards.
    if not _unit then
        if not UnitExists(unit) or UnitIsDeadOrGhost(unit) then
            frame.absorbBar:Hide()
            return
        end
    end

    local maxHP = _maxHP or UnitHealthMax(unit)
    local absorbAmount = UnitGetTotalAbsorbs(unit)

    -- Only hide on nil (API unavailable). Do NOT check for zero — StatusBar
    -- naturally shows 0-width when value is 0 (matches QUI pattern).
    -- absorbAmount may be a secret value; pass directly to C-side.
    if not absorbAmount then
        frame.absorbBar:Hide()
        return
    end

    -- Geometry is set up at frame creation (SetFrameLevel, SetAllPoints,
    -- SetReverseFill, SetOrientation).  Only redo when orientation changes.
    if frame._absorbVertical ~= frame._isVerticalFill then
        frame.absorbBar:SetFrameLevel(frame.healthBar:GetFrameLevel() + 2)
        frame.absorbBar:ClearAllPoints()
        frame.absorbBar:SetAllPoints(frame.healthBar)
        frame.absorbBar:SetReverseFill(true)
        frame.absorbBar:SetOrientation(frame._isVerticalFill and "VERTICAL" or "HORIZONTAL")
        frame._absorbVertical = frame._isVerticalFill
    end

    -- C-side SetMinMaxValues/SetValue handle secret values natively.
    -- Always call — maxHP may be a secret value (combat), so Lua-side ~= is forbidden.
    frame.absorbBar:SetMinMaxValues(0, maxHP)
    frame.absorbBar:SetValue(absorbAmount)

    -- Color (dirty-checked: settings-driven or class-based, both stable per event)
    local aa = vdb.absorbs.opacity or 0.3
    local ar, ag, ab
    if vdb.absorbs.useClassColor then
        local _, class = UnitClass(unit)
        local cc = class and RAID_CLASS_COLORS[class]
        if cc then
            ar, ag, ab = cc.r, cc.g, cc.b
        else
            ar, ag, ab = 1, 1, 1
        end
    else
        local ac = vdb.absorbs.color or COLORS.WHITE
        ar, ag, ab = ac[1], ac[2], ac[3]
    end
    if ar ~= frame._lastAbsorbColorR or aa ~= frame._lastAbsorbColorA then
        frame._lastAbsorbColorR = ar
        frame._lastAbsorbColorA = aa
        frame.absorbBar:SetStatusBarColor(ar, ag, ab, aa)
    end
    frame.absorbBar:Show()
end

---------------------------------------------------------------------------
-- UPDATE: Heal Absorb (debuffs that absorb healing, e.g. Necrotic Wound)
---------------------------------------------------------------------------
local function UpdateHealAbsorb(frame, _unit, _maxHP)
    if not frame or not frame.healAbsorbBar then return end
    local isRaid = frame._isRaid
    local vdb = GetVisualDB(isRaid)
    if not vdb or not vdb.healAbsorbs or vdb.healAbsorbs.enabled == false then
        frame.healAbsorbBar:Hide()
        return
    end

    local unit = _unit or frame.unit
    if not unit then return end

    if not _unit then
        if not UnitExists(unit) or UnitIsDeadOrGhost(unit) then
            frame.healAbsorbBar:Hide()
            return
        end
    end

    local maxHP = _maxHP or UnitHealthMax(unit)
    local healAbsorbAmount = UnitGetTotalHealAbsorbs(unit)

    if not healAbsorbAmount then
        frame.healAbsorbBar:Hide()
        return
    end

    -- Redo geometry if orientation changed
    if frame._healAbsorbVertical ~= frame._isVerticalFill then
        frame.healAbsorbBar:SetFrameLevel(frame.healthBar:GetFrameLevel() + 3)
        frame.healAbsorbBar:ClearAllPoints()
        frame.healAbsorbBar:SetAllPoints(frame.healthBar)
        frame.healAbsorbBar:SetReverseFill(true)
        frame.healAbsorbBar:SetOrientation(frame._isVerticalFill and "VERTICAL" or "HORIZONTAL")
        frame._healAbsorbVertical = frame._isVerticalFill
    end

    -- C-side SetMinMaxValues handles secret values natively — no Lua comparison.
    frame.healAbsorbBar:SetMinMaxValues(0, maxHP)
    frame.healAbsorbBar:SetValue(healAbsorbAmount)

    -- Color (dirty-checked: settings-driven, never changes during combat)
    local ha = vdb.healAbsorbs.opacity or 0.6
    local hc = vdb.healAbsorbs.color or { 0.5, 0.1, 0.1 }
    if hc[1] ~= frame._lastHealAbsorbColorR or ha ~= frame._lastHealAbsorbColorA then
        frame._lastHealAbsorbColorR = hc[1]
        frame._lastHealAbsorbColorA = ha
        frame.healAbsorbBar:SetStatusBarColor(hc[1], hc[2], hc[3], ha)
    end
    frame.healAbsorbBar:Show()
end

---------------------------------------------------------------------------
-- UPDATE: Heal Prediction
---------------------------------------------------------------------------
-- HealPrediction: optional pre-computed args from fast health path avoid redundant API calls.
local function UpdateHealPrediction(frame, _unit, _maxHP)
    if not frame or not frame.healPredictionBar then return end
    local isRaid = frame._isRaid
    local vdb = GetVisualDB(isRaid)
    if not vdb or not vdb.healPrediction or vdb.healPrediction.enabled == false then
        frame.healPredictionBar:Hide()
        return
    end

    local unit = _unit or frame.unit
    if not unit then return end

    -- When called standalone (UNIT_HEAL_PREDICTION), do our own guards.
    if not _unit then
        if not UnitExists(unit) or UnitIsDeadOrGhost(unit) then
            frame.healPredictionBar:Hide()
            return
        end
    end

    local maxHP = _maxHP or UnitHealthMax(unit)
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

    -- Anchor from health fill edge.  Only redo geometry when orientation changes.
    if frame._healPredVertical ~= frame._isVerticalFill then
        local healthTexture = frame.healthBar:GetStatusBarTexture()
        frame.healPredictionBar:ClearAllPoints()
        if frame._isVerticalFill then
            frame.healPredictionBar:SetPoint("BOTTOMLEFT", healthTexture, "TOPLEFT", 0, 0)
            frame.healPredictionBar:SetPoint("TOPRIGHT", frame.healthBar, "TOPRIGHT", 0, 0)
            frame.healPredictionBar:SetOrientation("VERTICAL")
        else
            frame.healPredictionBar:SetPoint("TOPLEFT", healthTexture, "TOPRIGHT", 0, 0)
            frame.healPredictionBar:SetPoint("BOTTOMRIGHT", frame.healthBar, "BOTTOMRIGHT", 0, 0)
            frame.healPredictionBar:SetOrientation("HORIZONTAL")
        end
        frame._healPredVertical = frame._isVerticalFill
    end

    -- C-side SetMinMaxValues handles secret values natively — no Lua comparison.
    frame.healPredictionBar:SetMinMaxValues(0, maxHP)
    frame.healPredictionBar:SetValue(incomingHeals)

    -- Color (dirty-checked: settings-driven or class-based, both stable per event)
    local pa = vdb.healPrediction.opacity or 0.5
    local pr, pg, pb
    if vdb.healPrediction.useClassColor then
        local _, class = UnitClass(unit)
        local cc = class and RAID_CLASS_COLORS[class]
        if cc then
            pr, pg, pb = cc.r, cc.g, cc.b
        else
            pr, pg, pb = 0.2, 1, 0.2
        end
    else
        local pc = vdb.healPrediction.color
        if pc then
            pr, pg, pb = pc[1], pc[2], pc[3]
        else
            pr, pg, pb = 0.2, 1, 0.2
        end
    end
    if pr ~= frame._lastHealPredColorR or pa ~= frame._lastHealPredColorA then
        frame._lastHealPredColorR = pr
        frame._lastHealPredColorA = pa
        frame.healPredictionBar:SetStatusBarColor(pr, pg, pb, pa)
    end
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

local ROLE_TOGGLE_KEY = {
    TANK    = "showRoleTank",
    HEALER  = "showRoleHealer",
    DAMAGER = "showRoleDPS",
}

local function UpdateRoleIcon(frame)
    if not frame or not frame.unit or not frame.roleIcon then return end
    local isRaid = frame._isRaid
    local indSettings = GetIndicatorSettings(isRaid)
    if not indSettings or indSettings.showRoleIcon == false then
        frame.roleIcon:Hide()
        return
    end

    local role = UnitGroupRolesAssigned(frame.unit)
    -- Check per-role toggle
    local toggleKey = ROLE_TOGGLE_KEY[role]
    if toggleKey and indSettings[toggleKey] == false then
        frame.roleIcon:Hide()
        return
    end

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
    local isRaid = frame._isRaid
    local indSettings = GetIndicatorSettings(isRaid)
    if not indSettings or indSettings.showReadyCheck == false then
        frame.readyCheckIcon:Hide()
        return
    end

    local status = GetReadyCheckStatus(frame.unit)
    if status then
        -- QUI pattern: AFK players waiting on ready check show "not ready"
        if status == "waiting" then
            local isAFK = UnitIsAFK(frame.unit)
            if not IsSecretValue(isAFK) and isAFK then
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
    local isRaid = frame._isRaid
    local indSettings = GetIndicatorSettings(isRaid)
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
    local isRaid = frame._isRaid
    local indSettings = GetIndicatorSettings(isRaid)
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
    local isRaid = frame._isRaid
    local indSettings = GetIndicatorSettings(isRaid)
    if not indSettings or indSettings.showThreatBorder == false then
        frame.threatBorder:Hide()
        return
    end

    local status = UnitThreatSituation(frame.unit)
    if status and status >= 2 then
        local tc = indSettings.threatColor or { 1, 0, 0, 0.8 }
        frame.threatBorder:SetBackdropBorderColor(tc[1], tc[2], tc[3], tc[4] or 0.8)
        -- Keep threat border below icons/indicators — re-level in case frame
        -- base level shifted since decoration (secure header can re-level children)
        frame.threatBorder:SetFrameLevel(frame:GetFrameLevel() + 3)
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
    local isRaid = frame._isRaid
    local indSettings = GetIndicatorSettings(isRaid)
    if not indSettings or indSettings.showTargetMarker == false then
        frame.targetMarker:Hide()
        return
    end

    local index = GetRaidTargetIndex(frame.unit)
    if index then
        frame.targetMarker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        SetRaidTargetIconTexture(frame.targetMarker, index)
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
    local isRaid = frame._isRaid
    local indSettings = GetIndicatorSettings(isRaid)
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
    local isRaid = frame._isRaid
    local indSettings = GetIndicatorSettings(isRaid)
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
    local isRaid = frame._isRaid
    local healerSettings = GetHealerSettings(isRaid)
    if not healerSettings or not healerSettings.targetHighlight or healerSettings.targetHighlight.enabled == false then
        frame.targetHighlight:Hide()
        return
    end

    if frame.unit and UnitIsUnit(frame.unit, "target") then
        local c = healerSettings.targetHighlight.color or { 1, 1, 1, 0.6 }
        frame.targetHighlight:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 0.6)
        frame.targetHighlight:Show()
        -- Keep fast-path cache in sync (used by PLAYER_TARGET_CHANGED O(1) unhighlight)
        QUI_GF._targetHighlightFrame = frame
    else
        frame.targetHighlight:Hide()
    end
end

---------------------------------------------------------------------------
-- UPDATE: Dispel Overlay
---------------------------------------------------------------------------
-- Helper: apply color to all 4 StatusBar borders + fill
local function SetDispelBorderColor(overlay, r, g, b, a)
    for _, key in ipairs(_dispel.borderKeys) do
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

-- Helper: apply a ColorMixin (secret-safe) to all 4 StatusBar borders + fill
local function SetDispelBorderColorMixin(overlay, color)
    for _, key in ipairs(_dispel.borderKeys) do
        local border = overlay[key]
        if border then
            local tex = border:GetStatusBarTexture()
            -- GetRGBA() returns secret values; SetVertexColor is C-side and handles them
            tex:SetVertexColor(color:GetRGBA())
        end
    end
    if overlay.fill then
        -- Use the same RGB but with the fill opacity
        local fillA = overlay._fillOpacity or 0
        overlay.fill:SetVertexColor(color:GetRGBA())
        overlay.fill:SetAlpha(fillA)
    end
end

local function UpdateDispelOverlay(frame)
    if not frame or not frame.unit or not frame.dispelOverlay then return end
    local isRaid = frame._isRaid
    local healerSettings = GetHealerSettings(isRaid)
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

    -- Check shared aura cache first to avoid redundant C_UnitAuras.GetUnitAuras call.
    -- The cache was just populated by the aura dispatcher before this function runs.
    local GFA = ns.QUI_GroupFrameAuras
    local cache = GFA and GFA.unitAuraCache and GFA.unitAuraCache[unit]
    local hasDispellable = false
    local firstDispellableInstID = nil

    if cache and cache.harmful then
        for _, auraData in ipairs(cache.harmful) do
            if auraData.dispelName then
                local dType = SafeValue(auraData.dispelName, nil)
                if dType then
                    hasDispellable = true
                    firstDispellableInstID = auraData.auraInstanceID
                    break
                end
            end
        end
    end

    if not hasDispellable then
        overlay:Hide()
        return
    end

    -- WoW 12.0+ secret-safe path: C-side color resolution using cached auraInstanceID
    if firstDispellableInstID and C_UnitAuras.GetAuraDispelTypeColor then
        local opacity = healerSettings.dispelOverlay.opacity or 0.8
        local curve = GetDispelColorCurve(opacity)
        if curve then
            local cOk, color = pcall(C_UnitAuras.GetAuraDispelTypeColor, unit, firstDispellableInstID, curve)
            if cOk and color then
                SetDispelBorderColorMixin(overlay, color)
                overlay:Show()
                return
            end
        end
    end

    -- Fallback: use dispel type from cache directly
    local colors = GetDispelColors()
    if cache and cache.harmful then
        for _, auraData in ipairs(cache.harmful) do
            if auraData.dispelName then
                local dType = SafeValue(auraData.dispelName, nil)
                if dType and colors[dType] then
                    local c = colors[dType]
                    local fallbackOpacity = healerSettings.dispelOverlay.opacity or 0.8
                    SetDispelBorderColor(overlay, c[1], c[2], c[3], fallbackOpacity)
                    overlay:Show()
                    return
                end
            end
        end
    end
    overlay:Hide()
end

---------------------------------------------------------------------------
-- UPDATE: Defensive Indicator
---------------------------------------------------------------------------
-- Growth direction offsets for multi-icon layout
local DEFENSIVE_GROWTH_OFFSETS = {
    RIGHT  = function(size, spacing) return size + spacing, 0 end,
    LEFT   = function(size, spacing) return -(size + spacing), 0 end,
    CENTER = function(size, spacing) return size + spacing, 0 end,
    UP     = function(size, spacing) return 0, size + spacing end,
    DOWN   = function(size, spacing) return 0, -(size + spacing) end,
}

-- Defensive indicator state (scratch tables, classification cache, filter strings)
local _defensive = {
    foundAuras = {},     -- pooled scratch (wipe and reuse)
    seen = {},           -- pooled scratch (wipe and reuse)
    cache = {},          -- auraInstanceID → true/false (immutable per ID)
    filterBig = nil,     -- pre-cached filter string
    filterExternal = nil,
}

local function AuraMatchesDefensiveClassification(unit, auraInstanceID, classification)
    if not unit or not classification or not auraInstanceID or IsSecretValue(auraInstanceID) then
        return false
    end
    if not C_UnitAuras or not C_UnitAuras.IsAuraFilteredOutByInstanceID then
        return false
    end

    -- Use cached filter strings to avoid per-call string concatenation
    local filterStr
    if AuraUtil and AuraUtil.AuraFilters then
        if classification == AuraUtil.AuraFilters.BigDefensive then
            if not _defensive.filterBig then
                _defensive.filterBig = "HELPFUL|" .. classification
            end
            filterStr = _defensive.filterBig
        elseif classification == AuraUtil.AuraFilters.ExternalDefensive then
            if not _defensive.filterExternal then
                _defensive.filterExternal = "HELPFUL|" .. classification
            end
            filterStr = _defensive.filterExternal
        end
    end
    if not filterStr then
        filterStr = "HELPFUL|" .. classification
    end

    local ok, filteredOut = pcall(
        C_UnitAuras.IsAuraFilteredOutByInstanceID,
        unit,
        auraInstanceID,
        filterStr
    )
    if not ok or IsSecretValue(filteredOut) then
        return false
    end

    return not filteredOut
end

local function IsVerifiedDefensiveAura(unit, auraData)
    if not unit or not auraData then
        return false
    end

    -- Fast path: known spell IDs in the fallback allow-list.
    local spellID = SafeValue(auraData.spellId, nil)
    if spellID and DEFENSIVE_SPELL_IDS[spellID] then
        return true
    end

    -- Fail closed when aura data is obfuscated (common when units are far away).
    local auraInstanceID = auraData.auraInstanceID
    local filters = AuraUtil and AuraUtil.AuraFilters
    if not auraInstanceID or not filters then
        return false
    end

    -- Check cache first
    local cached = _defensive.cache[auraInstanceID]
    if cached ~= nil then
        return cached
    end

    if AuraMatchesDefensiveClassification(unit, auraInstanceID, filters.BigDefensive) then
        _defensive.cache[auraInstanceID] = true
        return true
    end
    if AuraMatchesDefensiveClassification(unit, auraInstanceID, filters.ExternalDefensive) then
        _defensive.cache[auraInstanceID] = true
        return true
    end

    _defensive.cache[auraInstanceID] = false
    return false
end

local function UpdateDefensiveIndicator(frame)
    if not frame or not frame.unit or not frame.defensiveIcons then return end

    local isRaid = frame._isRaid
    local healerSettings = GetHealerSettings(isRaid)
    if not healerSettings or not healerSettings.defensiveIndicator
       or not healerSettings.defensiveIndicator.enabled then
        for _, icon in ipairs(frame.defensiveIcons) do icon:Hide() end
        return
    end

    local unit = frame.unit
    if not UnitExists(unit) or UnitIsDeadOrGhost(unit) then
        for _, icon in ipairs(frame.defensiveIcons) do icon:Hide() end
        return
    end

    local defSettings = healerSettings.defensiveIndicator
    local maxIcons = defSettings.maxIcons or 3

    -- Collect defensive auras from the shared cache first (just populated by
    -- the aura dispatcher). This avoids 2-3 redundant C_UnitAuras.GetUnitAuras
    -- calls per unit per aura event (~60-100 saved C API calls per raid batch).
    local foundAuras = _defensive.foundAuras
    local seen = _defensive.seen
    wipe(foundAuras)
    wipe(seen)

    local GFA = ns.QUI_GroupFrameAuras
    local cache = GFA and GFA.unitAuraCache and GFA.unitAuraCache[unit]
    if cache and cache.helpful then
        for _, auraData in ipairs(cache.helpful) do
            if IsVerifiedDefensiveAura(unit, auraData) then
                local instID = auraData.auraInstanceID
                if not instID or not seen[instID] then
                    if instID then seen[instID] = true end
                    foundAuras[#foundAuras + 1] = auraData
                    if #foundAuras >= maxIcons then break end
                end
            end
        end
    end

    -- Layout settings
    local iconSize = defSettings.iconSize or 16
    local position = defSettings.position or "CENTER"
    local offsetX = defSettings.offsetX or 0
    local offsetY = defSettings.offsetY or 0
    local spacing = defSettings.spacing or 2
    local growDir = defSettings.growDirection or "RIGHT"
    local reverseSwipe = defSettings.reverseSwipe ~= false
    local growFn = DEFENSIVE_GROWTH_OFFSETS[growDir] or DEFENSIVE_GROWTH_OFFSETS.RIGHT
    local stepX, stepY = growFn(iconSize, spacing)

    -- CENTER: calculate centering offset based on visible count
    local centerOffX = 0
    if growDir == "CENTER" then
        local visibleCount = math_min(#foundAuras, #frame.defensiveIcons)
        local totalSpan = visibleCount * iconSize + math_max(visibleCount - 1, 0) * spacing
        centerOffX = -totalSpan / 2
    end

    -- Expose active defensive auraInstanceIDs for buff deduplication
    if not frame._defensiveAuraIDs then frame._defensiveAuraIDs = {} end
    wipe(frame._defensiveAuraIDs)
    for id in pairs(seen) do
        frame._defensiveAuraIDs[id] = true
    end

    for i, defIcon in ipairs(frame.defensiveIcons) do
        local aura = foundAuras[i]
        if aura then
            -- Update icon texture
            if aura.icon and defIcon.icon then
                pcall(defIcon.icon.SetTexture, defIcon.icon, aura.icon)
            end

            -- Update cooldown swipe
            local cd = defIcon.cooldown
            if cd and aura.duration and aura.expirationTime then
                if cd.SetReverse then
                    pcall(cd.SetReverse, cd, reverseSwipe)
                end
                if aura.auraInstanceID and C_UnitAuras.GetAuraDuration
                   and cd.SetCooldownFromDurationObject then
                    local ok, durationObj = pcall(C_UnitAuras.GetAuraDuration, unit, aura.auraInstanceID)
                    if ok and durationObj then
                        pcall(cd.SetCooldownFromDurationObject, cd, durationObj)
                    elseif not IsSecretValue(aura.expirationTime) and not IsSecretValue(aura.duration) then
                        if cd.SetCooldownFromExpirationTime then
                            pcall(cd.SetCooldownFromExpirationTime, cd, aura.expirationTime, aura.duration)
                        else
                            pcall(cd.SetCooldown, cd, aura.expirationTime - aura.duration, aura.duration)
                        end
                    else
                        cd:Clear()
                    end
                elseif not IsSecretValue(aura.expirationTime) and not IsSecretValue(aura.duration) then
                    if cd.SetCooldownFromExpirationTime then
                        pcall(cd.SetCooldownFromExpirationTime, cd, aura.expirationTime, aura.duration)
                    else
                        pcall(cd.SetCooldown, cd, aura.expirationTime - aura.duration, aura.duration)
                    end
                else
                    cd:Clear()
                end
            elseif cd then
                cd:Clear()
            end

            -- Position: first icon at anchor, subsequent offset by growth direction
            defIcon:SetSize(iconSize, iconSize)
            defIcon:ClearAllPoints()
            defIcon:SetPoint(position, frame, position, offsetX + centerOffX + stepX * (i - 1), offsetY + stepY * (i - 1))
            defIcon:SetFrameLevel(frame:GetFrameLevel() + 10)
            defIcon:Show()
        else
            defIcon:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- UPDATE: Portrait
---------------------------------------------------------------------------
local function UpdatePortrait(frame)
    if not frame or not frame.unit then return end
    local isRaid = frame._isRaid
    local portraitSettings = GetPortraitSettings(isRaid)

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
    local general = GetGeneralSettings(frame._isRaid)
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
    UpdateHealAbsorb(frame)
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

    -- Tag frame with party/raid context for settings resolution
    local parent = frame:GetParent()
    local isRaidParent = (parent == QUI_GF.headers.raid)
        or (parent == QUI_GF.spotlightHeader)
    if not isRaidParent then
        for _, header in ipairs(QUI_GF.raidGroupHeaders) do
            if parent == header then
                isRaidParent = true
                break
            end
        end
    end
    frame._isRaid = isRaidParent
    local isRaid = frame._isRaid

    local db = GetSettings()
    local general = GetGeneralSettings(isRaid)

    -- Backdrop
    local borderPx = general and general.borderSize or 1
    local borderSize = borderPx > 0 and (QUICore.Pixels and QUICore:Pixels(borderPx, frame) or borderPx) or 0
    local px = QUICore.GetPixelSize and QUICore:GetPixelSize(frame) or 1

    frame:SetBackdrop(GetCachedBackdrop(
        "Interface\\Buttons\\WHITE8x8",
        borderSize > 0 and "Interface\\Buttons\\WHITE8x8" or nil,
        borderSize > 0 and borderSize or nil
    ))

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
    local powerSettings = GetPowerSettings(isRaid)
    local showPower = powerSettings and powerSettings.showPowerBar ~= false
    local powerHeight = showPower and (QUICore.PixelRound and QUICore:PixelRound(powerSettings.powerBarHeight or 4, frame) or 4) or 0
    local separatorHeight = showPower and px or 0

    -- Health bar (reuse existing to avoid frame leaks on re-decoration)
    local healthBar = frame.healthBar or CreateFrame("StatusBar", nil, frame)
    healthBar:ClearAllPoints()
    healthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", borderSize, -borderSize)
    healthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize + powerHeight + separatorHeight)
    ApplyStatusBarTexture(healthBar)
    healthBar:SetMinMaxValues(0, 100)
    healthBar:SetValue(100)
    healthBar:EnableMouse(false)
    healthBar:SetAlpha(healthOpacity)
    local isVertical = (GetHealthFillDirection(isRaid) == "VERTICAL")
    healthBar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
    frame._isVerticalFill = isVertical
    frame.healthBar = healthBar

    -- No separate healthBg texture — the frame backdrop shows through the
    -- unfilled StatusBar area, matching unit frame behavior.
    if frame.healthBg then
        frame.healthBg:Hide()
        frame.healthBg = nil
    end

    -- Heal prediction bar (overlays health bar, peeks out beyond health fill)
    local vdb = GetVisualDB(isRaid)
    local predSettings = vdb and vdb.healPrediction
    local healPredictionBar = frame.healPredictionBar or CreateFrame("StatusBar", nil, healthBar)
    ApplyStatusBarTexture(healPredictionBar)
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
    local absorbSettings = vdb and vdb.absorbs
    local absorbBar = frame.absorbBar
    if not absorbBar then
        absorbBar = CreateFrame("StatusBar", nil, healthBar)
    end
    absorbBar:SetStatusBarTexture("Interface\\RaidFrame\\Shield-Fill")
    local ac = absorbSettings and absorbSettings.color or COLORS.WHITE
    local aa = absorbSettings and absorbSettings.opacity or 0.3
    absorbBar:SetStatusBarColor(ac[1], ac[2], ac[3], aa)
    absorbBar:SetFrameLevel(healthBar:GetFrameLevel() + 2)
    absorbBar:SetFrameStrata(healthBar:GetFrameStrata())
    absorbBar:ClearAllPoints()
    absorbBar:SetAllPoints(healthBar)
    absorbBar:SetReverseFill(true)
    absorbBar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
    absorbBar:SetMinMaxValues(0, 1)
    absorbBar:SetValue(0)
    absorbBar:Hide()
    frame.absorbBar = absorbBar

    -- Heal absorb bar (overlays health bar — shows heal absorb debuffs like Necrotic Wound)
    local healAbsorbSettings = vdb and vdb.healAbsorbs
    local healAbsorbBar = frame.healAbsorbBar
    if not healAbsorbBar then
        healAbsorbBar = CreateFrame("StatusBar", nil, healthBar)
    end
    healAbsorbBar:SetStatusBarTexture("Interface\\RaidFrame\\Shield-Fill")
    local hac = healAbsorbSettings and healAbsorbSettings.color or { 0.5, 0.1, 0.1 }
    local haa = healAbsorbSettings and healAbsorbSettings.opacity or 0.6
    healAbsorbBar:SetStatusBarColor(hac[1], hac[2], hac[3], haa)
    healAbsorbBar:SetFrameLevel(healthBar:GetFrameLevel() + 3)
    healAbsorbBar:SetFrameStrata(healthBar:GetFrameStrata())
    healAbsorbBar:ClearAllPoints()
    healAbsorbBar:SetAllPoints(healthBar)
    healAbsorbBar:SetReverseFill(true)
    healAbsorbBar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
    healAbsorbBar:SetMinMaxValues(0, 1)
    healAbsorbBar:SetValue(0)
    healAbsorbBar:Hide()
    frame.healAbsorbBar = healAbsorbBar

    -- Power bar
    if showPower then
        local powerBar = frame.powerBar or CreateFrame("StatusBar", nil, frame)
        powerBar:ClearAllPoints()
        powerBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", borderSize, borderSize)
        powerBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize)
        powerBar:SetHeight(powerHeight)
        ApplyStatusBarTexture(powerBar)
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

    -- Bottom-anchor offset: push elements above power bar + separator
    local bottomPad = powerHeight + separatorHeight + borderSize
    frame._bottomPad = bottomPad

    -- Name text
    local fontPath = GetFontPath()
    local fontOutline = GetFontOutline()
    local nameSettings = GetNameSettings(isRaid)
    local nameFontSize = nameSettings and nameSettings.nameFontSize or 12
    local nameAnchor = GetTextAnchorInfo(nameSettings and nameSettings.nameAnchor or "LEFT")
    local nameOffsetX = nameSettings and nameSettings.nameOffsetX or 4
    local nameOffsetY = nameSettings and nameSettings.nameOffsetY or 0
    local nameBottomPad = nameAnchor.point:find("BOTTOM") and bottomPad or 0

    local nameText = frame.nameText or textFrame:CreateFontString(nil, "OVERLAY")
    nameText:ClearAllPoints()
    nameText:SetFont(fontPath, nameFontSize, fontOutline)
    local namePadX = math.abs(nameOffsetX)
    nameText:SetPoint(nameAnchor.leftPoint, frame, nameAnchor.leftPoint, namePadX, nameOffsetY + nameBottomPad)
    nameText:SetPoint(nameAnchor.rightPoint, frame, nameAnchor.rightPoint, -namePadX, nameOffsetY + nameBottomPad)
    local nameJustify = nameSettings and nameSettings.nameJustify or nameAnchor.justify
    nameText:SetJustifyH(nameJustify)
    nameText:SetJustifyV(nameAnchor.justifyV)
    nameText:SetTextColor(1, 1, 1, 1)
    nameText:SetWordWrap(false)
    frame.nameText = nameText

    -- Health text
    local healthSettings = GetHealthSettings(isRaid)
    local healthFontSize = healthSettings and healthSettings.healthFontSize or 12
    local healthAnchor = GetTextAnchorInfo(healthSettings and healthSettings.healthAnchor or "RIGHT")
    local healthOffsetX = healthSettings and healthSettings.healthOffsetX or -4
    local healthOffsetY = healthSettings and healthSettings.healthOffsetY or 0
    local healthBottomPad = healthAnchor.point:find("BOTTOM") and bottomPad or 0

    local healthText = frame.healthText or textFrame:CreateFontString(nil, "OVERLAY")
    healthText:ClearAllPoints()
    healthText:SetFont(fontPath, healthFontSize, fontOutline)
    local healthPadX = math.abs(healthOffsetX)
    healthText:SetPoint(healthAnchor.leftPoint, frame, healthAnchor.leftPoint, healthPadX, healthOffsetY + healthBottomPad)
    healthText:SetPoint(healthAnchor.rightPoint, frame, healthAnchor.rightPoint, -healthPadX, healthOffsetY + healthBottomPad)
    local healthJustify = healthSettings and healthSettings.healthJustify or healthAnchor.justify
    healthText:SetJustifyH(healthJustify)
    healthText:SetJustifyV(healthAnchor.justifyV)
    healthText:SetTextColor(1, 1, 1, 1)
    healthText:SetWordWrap(false)
    frame.healthText = healthText

    -- Read indicator positioning from DB
    local indDB = GetIndicatorSettings(isRaid) or {}

    -- Helper: add bottomPad to Y offset for any BOTTOM* anchor
    local function BottomPadY(anchor, offY)
        if anchor:find("BOTTOM") then return offY + bottomPad end
        return offY
    end

    -- Role icon
    local roleIconSize = indDB.roleIconSize or 12
    local roleAnchor = indDB.roleIconAnchor or "TOPLEFT"
    local roleOffX = indDB.roleIconOffsetX or 2
    local roleOffY = indDB.roleIconOffsetY or -2

    local roleIcon = frame.roleIcon or textFrame:CreateTexture(nil, "OVERLAY")
    roleIcon:ClearAllPoints()
    roleIcon:SetSize(roleIconSize, roleIconSize)
    roleIcon:SetPoint(roleAnchor, frame, roleAnchor, roleOffX, BottomPadY(roleAnchor, roleOffY))
    roleIcon:Hide()
    frame.roleIcon = roleIcon

    -- Ready check icon
    local readyCheckIcon = frame.readyCheckIcon or textFrame:CreateTexture(nil, "OVERLAY")
    readyCheckIcon:ClearAllPoints()
    local rcSize = indDB.readyCheckSize or 16
    readyCheckIcon:SetSize(rcSize, rcSize)
    local rcAnchor = indDB.readyCheckAnchor or "CENTER"
    readyCheckIcon:SetPoint(rcAnchor, frame, rcAnchor, indDB.readyCheckOffsetX or 0, BottomPadY(rcAnchor, indDB.readyCheckOffsetY or 0))
    readyCheckIcon:Hide()
    frame.readyCheckIcon = readyCheckIcon

    -- Resurrection icon
    local resIcon = frame.resIcon or textFrame:CreateTexture(nil, "OVERLAY")
    resIcon:ClearAllPoints()
    local resSize = indDB.resurrectionSize or 16
    resIcon:SetSize(resSize, resSize)
    local resAnchor = indDB.resurrectionAnchor or "CENTER"
    resIcon:SetPoint(resAnchor, frame, resAnchor, indDB.resurrectionOffsetX or 0, BottomPadY(resAnchor, indDB.resurrectionOffsetY or 0))
    resIcon:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")
    resIcon:Hide()
    frame.resIcon = resIcon

    -- Summon pending icon
    local summonIcon = frame.summonIcon or textFrame:CreateTexture(nil, "OVERLAY")
    summonIcon:ClearAllPoints()
    local sumSize = indDB.summonSize or 20
    summonIcon:SetSize(sumSize, sumSize)
    local sumAnchor = indDB.summonAnchor or "CENTER"
    summonIcon:SetPoint(sumAnchor, frame, sumAnchor, indDB.summonOffsetX or 16, BottomPadY(sumAnchor, indDB.summonOffsetY or 0))
    summonIcon:SetAtlas("RaidFrame-Icon-SummonPending")
    summonIcon:Hide()
    frame.summonIcon = summonIcon

    -- Leader icon
    local leaderIcon = frame.leaderIcon or textFrame:CreateTexture(nil, "OVERLAY")
    leaderIcon:ClearAllPoints()
    local ldrSize = indDB.leaderSize or 12
    leaderIcon:SetSize(ldrSize, ldrSize)
    local ldrAnchor = indDB.leaderAnchor or "TOP"
    leaderIcon:SetPoint(ldrAnchor, frame, ldrAnchor, indDB.leaderOffsetX or 0, BottomPadY(ldrAnchor, indDB.leaderOffsetY or 6))
    leaderIcon:Hide()
    frame.leaderIcon = leaderIcon

    -- Target marker (raid icon)
    local targetMarker = frame.targetMarker or textFrame:CreateTexture(nil, "OVERLAY")
    targetMarker:ClearAllPoints()
    local tmSize = indDB.targetMarkerSize or 14
    targetMarker:SetSize(tmSize, tmSize)
    local tmAnchor = indDB.targetMarkerAnchor or "TOPRIGHT"
    targetMarker:SetPoint(tmAnchor, frame, tmAnchor, indDB.targetMarkerOffsetX or -2, BottomPadY(tmAnchor, indDB.targetMarkerOffsetY or -2))
    targetMarker:Hide()
    frame.targetMarker = targetMarker

    -- Phase icon
    local phaseIcon = frame.phaseIcon or textFrame:CreateTexture(nil, "OVERLAY")
    phaseIcon:ClearAllPoints()
    local phSize = indDB.phaseSize or 16
    phaseIcon:SetSize(phSize, phSize)
    local phAnchor = indDB.phaseAnchor or "BOTTOMLEFT"
    phaseIcon:SetPoint(phAnchor, frame, phAnchor, indDB.phaseOffsetX or 2, BottomPadY(phAnchor, indDB.phaseOffsetY or 2))
    phaseIcon:SetTexture("Interface\\TargetingFrame\\UI-PhasingIcon")
    phaseIcon:Hide()
    frame.phaseIcon = phaseIcon

    -- Threat border (overlay frame)
    indDB = GetIndicatorSettings(isRaid) or {}
    local threatBorderPx = px * (indDB.threatBorderSize or 3)
    local threatBorder = frame.threatBorder or CreateFrame("Frame", nil, frame, "BackdropTemplate")
    threatBorder:ClearAllPoints()
    threatBorder:SetPoint("TOPLEFT", -px, px)
    threatBorder:SetPoint("BOTTOMRIGHT", px, -px)
    threatBorder:SetFrameLevel(frame:GetFrameLevel() + 3)
    threatBorder:SetBackdrop(GetCachedBackdrop(nil, "Interface\\Buttons\\WHITE8x8", threatBorderPx))
    threatBorder:Hide()
    frame.threatBorder = threatBorder

    -- Target highlight (overlay frame)
    local targetHighlight = frame.targetHighlight or CreateFrame("Frame", nil, frame, "BackdropTemplate")
    targetHighlight:ClearAllPoints()
    targetHighlight:SetPoint("TOPLEFT", -px, px)
    targetHighlight:SetPoint("BOTTOMRIGHT", px, -px)
    targetHighlight:SetFrameLevel(frame:GetFrameLevel() + 4)
    targetHighlight:SetBackdrop(GetCachedBackdrop(nil, "Interface\\Buttons\\WHITE8x8", px * 2))
    targetHighlight:Hide()
    frame.targetHighlight = targetHighlight

    -- Dispel overlay (StatusBar borders for secret-value-safe SetVertexColor)
    local dispelOverlay = frame.dispelOverlay or CreateFrame("Frame", nil, frame)
    dispelOverlay:ClearAllPoints()
    dispelOverlay:SetAllPoints(frame)
    dispelOverlay:SetFrameLevel(frame:GetFrameLevel() + 6)

    local healerDB = GetHealerSettings(isRaid)
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

    -- Fill texture (full-frame tint behind borders)
    local dispelFill = dispelOverlay.fill
    if not dispelFill then
        dispelFill = dispelOverlay:CreateTexture(nil, "BACKGROUND")
        dispelOverlay.fill = dispelFill
    end
    dispelFill:SetAllPoints(dispelOverlay)
    dispelFill:SetColorTexture(1, 1, 1, 1)
    dispelFill:SetVertexColor(0, 0, 0, 0) -- colored dynamically by SetDispelBorderColor
    dispelOverlay._fillOpacity = dispelSettings and dispelSettings.fillOpacity or 0

    dispelOverlay:Hide()
    frame.dispelOverlay = dispelOverlay

    -- Defensive indicator icons (pool of up to MAX_DEFENSIVE_ICONS)
    local MAX_DEFENSIVE_ICONS = 5
    if not frame.defensiveIcons then frame.defensiveIcons = {} end
    for i = 1, MAX_DEFENSIVE_ICONS do
        local defIcon = frame.defensiveIcons[i] or CreateFrame("Frame", nil, frame, "BackdropTemplate")
        defIcon:SetSize(16, 16)
        defIcon:ClearAllPoints()
        defIcon:SetPoint("CENTER", frame, "CENTER", 0, 0)
        defIcon:SetFrameLevel(frame:GetFrameLevel() + 10)

        local defTex = defIcon.icon or defIcon:CreateTexture(nil, "ARTWORK")
        defTex:SetAllPoints()
        defTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        defIcon.icon = defTex

        defIcon:SetBackdrop(GetCachedBackdrop(nil, "Interface\\Buttons\\WHITE8x8", px))
        defIcon:SetBackdropBorderColor(0, 0.8, 0, 1)

        local healerDB = GetHealerSettings(isRaid)
        local defReverse = healerDB and healerDB.defensiveIndicator and healerDB.defensiveIndicator.reverseSwipe ~= false
        local defCD = defIcon.cooldown or CreateFrame("Cooldown", nil, defIcon, "CooldownFrameTemplate")
        defCD:SetAllPoints(defTex)
        defCD:SetDrawEdge(false)
        defCD:SetDrawSwipe(true)
        defCD:SetReverse(defReverse)
        defCD:SetHideCountdownNumbers(false)
        defIcon.cooldown = defCD

        if defIcon.SetMouseClickEnabled then
            defIcon:SetMouseClickEnabled(false)
        end
        defIcon:EnableMouse(false)

        defIcon:Hide()
        frame.defensiveIcons[i] = defIcon
    end
    -- Keep backward compat alias for single-icon references
    frame.defensiveIcon = frame.defensiveIcons[1]

    -- Party Tracker: store px for lazy icon creation (icons created on
    -- first use, not at decoration time, to avoid backdrop overhead)
    frame._partyTrackerPx = px

    -- Portrait (optional, side-attached)
    local portraitSettings = GetPortraitSettings(isRaid)
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

        portrait:SetBackdrop(GetCachedBackdrop(nil, "Interface\\Buttons\\WHITE8x8", portraitBorderPx))
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

        -- Sync unit attribute → frame.unit whenever the secure header changes it.
        -- GUID-based skip: avoids expensive UpdateFrame when the same player is
        -- reassigned to a different slot (common during roster shuffles).
        --   Level 0: Both old and new nil → skip (empty slot noise)
        --   Level 1: Same unit + same GUID → skip (no real change)
        --   Level 2: Different unit, same GUID → light update (remap only)
        --   Level 3: Genuinely different player → full UpdateFrame
        frame:HookScript("OnAttributeChanged", function(self, key, value)
            if key ~= "unit" then return end
            local oldUnit = self.unit
            -- Level 0: both nil — nothing to do
            if not oldUnit and not value then return end

            self.unit = value

            -- Clean up old mapping
            if oldUnit and QUI_GF.unitFrameMap[oldUnit] == self then
                QUI_GF.unitFrameMap[oldUnit] = nil
            end

            if not value then
                -- Unit cleared (frame hidden by header)
                _state.unitGuidCache[self] = nil
                return
            end

            -- Register new mapping immediately (so events dispatch correctly)
            QUI_GF.unitFrameMap[value] = self

            -- GUID comparison: detect whether the actual player changed.
            -- UnitGUID returns secret strings during combat — coerce to nil
            -- so we never store or compare secret values.
            local rawGuid = UnitGUID(value)
            local newGuid = (rawGuid and not IsSecretValue(rawGuid)) and rawGuid or nil
            local oldGuid = _state.unitGuidCache[self]
            if newGuid then
                _state.unitGuidCache[self] = newGuid
            end

            if oldGuid and newGuid and oldGuid == newGuid then
                if oldUnit == value then
                    -- Level 1: same unit, same player — nothing changed
                    return
                end
                -- Level 2: slot moved (e.g., raid3 → raid5), same player.
                -- Map is already updated; skip full refresh.
                return
            end

            -- Level 3: genuinely different player (or first assignment)
            UpdateFrame(self)
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

-- Expose for spotlight (and any future external headers)
QUI_GF.DecorateGroupFrame = DecorateGroupFrame

---------------------------------------------------------------------------
-- UNIT FRAME MAP: Rebuild unit → frame lookup
---------------------------------------------------------------------------
local function CollectHeaderUnits(header)
    if not header or not header:IsShown() then return end
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

local function RebuildUnitFrameMap()
    wipe(QUI_GF.unitFrameMap)

    CollectHeaderUnits(QUI_GF.headers.party)
    CollectHeaderUnits(QUI_GF.headers.self)

    if UseRaidSectionHeaders() and IsInRaid() then
        for _, header in ipairs(QUI_GF.raidGroupHeaders) do
            CollectHeaderUnits(header)
        end
    else
        CollectHeaderUnits(QUI_GF.headers.raid)
    end
end

local function EnsureAnchorFrame(key)
    local root = QUI_GF.anchorFrames[key]
    if root then return root end

    local name = key == "raid" and "QUI_RaidFramesRoot" or "QUI_PartyFramesRoot"
    -- On /reload, WoW does not destroy frames — the old root from the previous
    -- session survives with its children (headers + unit buttons) still visible.
    -- Hide it before creating the replacement to prevent duplicate frames.
    local old = _G[name]
    if old then old:Hide() end

    root = CreateFrame("Frame", name, UIParent)
    root:EnableMouse(false)
    root:Hide()

    QUI_GF.anchorFrames[key] = root
    return root
end

local function GetAnchorPosition(key, db)
    if key == "raid" and db and db.unifiedPosition == false then
        local pos = db.raidPosition
        return pos and pos.offsetX or -400, pos and pos.offsetY or 0
    end

    local pos = db and db.position
    return pos and pos.offsetX or -400, pos and pos.offsetY or 0
end

local function GetHeaderLeadEdge(isRaid)
    local layout = GetLayoutSettings(isRaid)
    local grow = GetLayoutGrowDirection(layout, "DOWN")
    local groupBy = isRaid and (layout and layout.groupBy or "GROUP") or "GROUP"
    local leadEdge = "LEFT"

    if grow == "LEFT" then
        leadEdge = "RIGHT"
    elseif isRaid and (grow == "DOWN" or grow == "UP") and groupBy ~= "NONE" and
        (layout and layout.groupGrowDirection) == "LEFT" then
        leadEdge = "RIGHT"
    end

    return grow, leadEdge
end

local function AnchorHeaderToRoot(root, header, grow, leadEdge, attachTo, gap, isSelfHeader)
    if not (root and header) then return end

    header:SetParent(root)
    header:ClearAllPoints()

    if attachTo then
        if grow == "UP" then
            header:SetPoint("BOTTOM" .. leadEdge, attachTo, "TOP" .. leadEdge, 0, gap or 0)
        elseif grow == "LEFT" then
            if isSelfHeader then
                header:SetPoint("TOPRIGHT", attachTo, "TOPLEFT", -(gap or 0), 0)
            else
                header:SetPoint("TOPRIGHT", attachTo, "TOPLEFT", -(gap or 0), 0)
            end
        elseif grow == "RIGHT" then
            if isSelfHeader then
                header:SetPoint("TOPLEFT", attachTo, "TOPRIGHT", gap or 0, 0)
            else
                header:SetPoint("TOPLEFT", attachTo, "TOPRIGHT", gap or 0, 0)
            end
        else
            header:SetPoint("TOP" .. leadEdge, attachTo, "BOTTOM" .. leadEdge, 0, -(gap or 0))
        end
        return
    end

    if grow == "UP" then
        header:SetPoint("BOTTOM" .. leadEdge, root, "BOTTOM" .. leadEdge, 0, 0)
    elseif grow == "LEFT" then
        header:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
    elseif grow == "RIGHT" then
        header:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    else
        header:SetPoint("TOP" .. leadEdge, root, "TOP" .. leadEdge, 0, 0)
    end
end

local function UpdateAnchorRoot(key, mainHeader, selfHeader, isRaid)
    local root = EnsureAnchorFrame(key)
    local grow, leadEdge = GetHeaderLeadEdge(isRaid)
    local gap = 4

    local mainVisible = mainHeader and mainHeader:IsShown()
    local selfVisible = selfHeader and selfHeader:IsShown()

    if not mainVisible and not selfVisible then
        root:ClearAllPoints()
        root:Hide()
        return
    end

    local mainW = mainVisible and Helpers.SafeValue(mainHeader:GetWidth(), 1) or 0
    local mainH = mainVisible and Helpers.SafeValue(mainHeader:GetHeight(), 1) or 0
    local selfW = selfVisible and Helpers.SafeValue(selfHeader:GetWidth(), 1) or 0
    local selfH = selfVisible and Helpers.SafeValue(selfHeader:GetHeight(), 1) or 0

    local totalW, totalH
    if grow == "LEFT" or grow == "RIGHT" then
        totalW = math_max(1, mainW + (mainVisible and selfVisible and gap or 0) + selfW)
        totalH = math_max(1, math_max(mainH, selfH))
    else
        totalW = math_max(1, math_max(mainW, selfW))
        totalH = math_max(1, mainH + (mainVisible and selfVisible and gap or 0) + selfH)
    end

    root:SetSize(totalW, totalH)

    if selfVisible then
        AnchorHeaderToRoot(root, selfHeader, grow, leadEdge, nil, 0, true)
    end

    if mainVisible then
        AnchorHeaderToRoot(root, mainHeader, grow, leadEdge, selfVisible and selfHeader or nil, selfVisible and gap or 0, false)
    end

    root:Show()
end

-- Compute total dimensions of all visible group headers for the anchor root
local function GetMultiHeaderTotalSize()
    local layout = GetLayoutSettings(true)
    local grow = GetLayoutGrowDirection(layout, "DOWN")
    local groupGrow = layout and layout.groupGrowDirection
    local groupSpacing = layout and layout.groupSpacing or 10
    local horizontal = (grow == "LEFT" or grow == "RIGHT")
    if not groupGrow then
        groupGrow = horizontal and "DOWN" or "RIGHT"
    end

    local totalW, totalH = 0, 0
    local visibleCount = 0

    for _, header in ipairs(QUI_GF.raidGroupHeaders) do
        if header and header:IsShown() then
            local hW = Helpers.SafeValue(header:GetWidth(), 1)
            local hH = Helpers.SafeValue(header:GetHeight(), 1)
            visibleCount = visibleCount + 1

            if horizontal then
                -- Groups stack vertically; width = max, height = sum
                totalW = math_max(totalW, hW)
                totalH = totalH + hH
            else
                -- Groups stack horizontally; width = sum, height = max
                totalW = totalW + hW
                totalH = math_max(totalH, hH)
            end
        end
    end

    -- Add group spacing between visible groups
    if visibleCount > 1 then
        if horizontal then
            totalH = totalH + (visibleCount - 1) * groupSpacing
        else
            totalW = totalW + (visibleCount - 1) * groupSpacing
        end
    end

    return math_max(totalW, 1), math_max(totalH, 1)
end

local function UpdateAnchorFrames()
    if not _pending.initSafe and InCombatLockdown() then
        _pending.anchorUpdate = true
        return
    end
    local db = GetSettings()
    if not db then return end

    local partyRoot = EnsureAnchorFrame("party")
    local raidRoot = EnsureAnchorFrame("raid")
    local partyX, partyY = GetAnchorPosition("party", db)
    local raidX, raidY = GetAnchorPosition("raid", db)

    -- Resize roots FIRST so that size-stable CENTER anchoring in
    -- ApplyFrameAnchor uses the correct dimensions. Previously the
    -- external position was computed before the resize, causing a
    -- CENTER offset mismatch that ApplyAllFrameAnchors would later
    -- "correct" — producing visible jumps during combat.
    local selfHdr = QUI_GF.headers.self
    local selfOnParty = selfHdr and selfHdr:IsShown() and not IsInRaid()

    UpdateAnchorRoot("party", QUI_GF.headers.party, selfOnParty and selfHdr or nil, false)

    if UseRaidSectionHeaders(db) and IsInRaid() then
        local root = raidRoot

        local mW, mH = GetMultiHeaderTotalSize()
        local anyVisible = mW > 1 or mH > 1

        if not anyVisible then
            root:ClearAllPoints()
            root:Hide()
            -- Still position both roots even when raid sections are invisible
            local applyAnchor = _G.QUI_ApplyFrameAnchor
            local hasAnchor = _G.QUI_HasFrameAnchor
            if hasAnchor and hasAnchor("partyFrames") and applyAnchor then
                applyAnchor("partyFrames")
            elseif partyRoot:GetNumPoints() == 0 then
                partyRoot:SetPoint("CENTER", UIParent, "CENTER", partyX, partyY)
            end
            if hasAnchor and hasAnchor("raidFrames") and applyAnchor then
                applyAnchor("raidFrames")
            elseif raidRoot:GetNumPoints() == 0 then
                raidRoot:SetPoint("CENTER", UIParent, "CENTER", raidX, raidY)
            end
            return
        end

        root:SetSize(math_max(1, mW), math_max(1, mH))
        root:Show()
    else
        UpdateAnchorRoot("raid", QUI_GF.headers.raid, nil, true)
    end

    -- Position roots AFTER resize: delegate to the anchoring system when it
    -- owns the frame (preserves size-stable CENTER anchoring), otherwise
    -- fall back to legacy.
    local applyAnchor = _G.QUI_ApplyFrameAnchor
    local hasAnchor = _G.QUI_HasFrameAnchor
    if hasAnchor and hasAnchor("partyFrames") and applyAnchor then
        applyAnchor("partyFrames")
    elseif partyRoot:GetNumPoints() == 0 then
        partyRoot:SetPoint("CENTER", UIParent, "CENTER", partyX, partyY)
    end
    if hasAnchor and hasAnchor("raidFrames") and applyAnchor then
        applyAnchor("raidFrames")
    elseif raidRoot:GetNumPoints() == 0 then
        raidRoot:SetPoint("CENTER", UIParent, "CENTER", raidX, raidY)
    end
end

---------------------------------------------------------------------------
-- HEADER: Configure secure header attributes
---------------------------------------------------------------------------
local function GetVisiblePartyUnitCount()
    local layout = GetLayoutSettings(false)
    if not layout then return 0 end

    local db = GetSettings()
    local selfFirst = GetPartySelfFirst(db)

    if IsInRaid() then
        return 0
    end

    if IsInGroup() then
        local subgroupCount
        if type(GetNumSubgroupMembers) == "function" then
            subgroupCount = GetNumSubgroupMembers() or 0
        else
            subgroupCount = math_max((GetNumGroupMembers() or 0) - 1, 0)
        end

        if selfFirst or layout.showPlayer == false then
            return subgroupCount
        end

        return subgroupCount + 1
    end

    if selfFirst or not layout.showSolo then
        return 0
    end

    return 1
end

local function ConfigurePartyHeader(header)
    local layout = GetLayoutSettings(false)
    if not layout then return end

    local db = GetSettings()
    local selfFirst = GetPartySelfFirst(db)
    local inParty = IsInGroup() and not IsInRaid()
    local showSolo = (not inParty) and layout.showSolo and not selfFirst

    header:SetAttribute("showParty", true)
    header:SetAttribute("showPlayer", (not selfFirst and ((inParty and layout.showPlayer ~= false) or showSolo)) and true or false)
    header:SetAttribute("showRaid", false)
    header:SetAttribute("showSolo", showSolo or false)
    header:SetAttribute("maxColumns", 1)
    header:SetAttribute("unitsPerColumn", 5)

    local mode = "party"
    local w, h = GetFrameDimensions(mode)
    local spacing = layout.spacing or 2

    -- Grow direction
    local grow = GetLayoutGrowDirection(layout, "DOWN")
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
    local layout = GetLayoutSettings(true)
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
    local grow = GetLayoutGrowDirection(layout, "DOWN")
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
    local groupBy = layout.groupBy or "GROUP"
    local isFlat = (groupBy == "NONE")

    if isFlat then
        local upc = layout.unitsPerFlat or 5
        header:SetAttribute("unitsPerColumn", upc)
        header:SetAttribute("maxColumns", math.ceil(40 / upc))
        header:SetAttribute("columnSpacing", spacing)
    else
        header:SetAttribute("maxColumns", 8)
        header:SetAttribute("unitsPerColumn", 5)
        header:SetAttribute("columnSpacing", groupSpacing)
    end

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
    if groupBy == "NONE" then
        header:SetAttribute("groupBy", nil)
        header:SetAttribute("groupFilter", nil)
        header:SetAttribute("groupingOrder", nil)
    elseif groupBy == "GROUP" then
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
-- MULTI-HEADER: Configure per-group raid headers
---------------------------------------------------------------------------
local function ConfigureRaidGroupHeaders()
    local layout = GetLayoutSettings(true)
    if not layout then return end

    local mode = GetGroupMode()
    local w, h = GetFrameDimensions(mode)
    local spacing = layout.spacing or 2

    local grow = GetLayoutGrowDirection(layout, "DOWN")
    local point, xOff, yOff
    if grow == "DOWN" then
        point, xOff, yOff = "TOP", 0, -spacing
    elseif grow == "UP" then
        point, xOff, yOff = "BOTTOM", 0, spacing
    elseif grow == "RIGHT" then
        point, xOff, yOff = "LEFT", spacing, 0
    elseif grow == "LEFT" then
        point, xOff, yOff = "RIGHT", -spacing, 0
    end
    local columnAnchorPoint = GetRaidColumnAnchorPoint(layout, grow)

    local sortMethod = layout.sortMethod or "INDEX"
    local sortByRole = layout.sortByRole
    local db = GetSettings()
    local raidSelfFirst = GetRaidSelfFirst(db)
    local sections = raidSelfFirst and GetRaidDisplaySections() or nil

    for g, header in ipairs(QUI_GF.raidGroupHeaders) do
        local section = sections and sections[g] or nil
        if header then
            header:SetAttribute("point", point)
            header:SetAttribute("xOffset", xOff)
            header:SetAttribute("yOffset", yOff)
            header:SetAttribute("showRaid", true)
            header:SetAttribute("showParty", false)
            header:SetAttribute("showPlayer", false)
            header:SetAttribute("showSolo", false)
            header:SetAttribute("columnSpacing", spacing)
            header:SetAttribute("columnAnchorPoint", columnAnchorPoint)
            header:SetAttribute("sortDir", "ASC")

            if section then
                local unitsPerColumn = math_max(1, math_min(section.memberCount, GetRaidSectionUnitsPerColumn(layout)))
                header:SetAttribute("maxColumns", math_max(1, math.ceil(section.memberCount / unitsPerColumn)))
                header:SetAttribute("unitsPerColumn", unitsPerColumn)
                header:SetAttribute("groupBy", nil)
                header:SetAttribute("groupFilter", nil)
                header:SetAttribute("groupingOrder", nil)
                header:SetAttribute("nameList", section.nameList)
                header:SetAttribute("sortMethod", "NAMELIST")
                header:SetAttribute("sortDir", "ASC")
            elseif raidSelfFirst then
                header:SetAttribute("maxColumns", 1)
                header:SetAttribute("unitsPerColumn", 1)
                header:SetAttribute("groupBy", nil)
                header:SetAttribute("groupFilter", nil)
                header:SetAttribute("groupingOrder", nil)
                header:SetAttribute("nameList", nil)
                header:SetAttribute("sortMethod", "INDEX")
            else
                header:SetAttribute("maxColumns", 1)
                header:SetAttribute("unitsPerColumn", 5)
                if g <= 8 then
                    header:SetAttribute("groupBy", "GROUP")
                    header:SetAttribute("groupFilter", tostring(g))
                    header:SetAttribute("groupingOrder", tostring(g))
                    header:SetAttribute("nameList", nil)

                    if sortByRole then
                        header:SetAttribute("sortMethod", "NAME")
                    else
                        header:SetAttribute("sortMethod", sortMethod)
                    end
                else
                    header:SetAttribute("groupBy", nil)
                    header:SetAttribute("groupFilter", nil)
                    header:SetAttribute("groupingOrder", nil)
                    header:SetAttribute("nameList", nil)
                    header:SetAttribute("sortMethod", "INDEX")
                end
            end

            header:SetAttribute("_initialAttributeNames", "unit-width,unit-height")
            header:SetAttribute("_initialAttribute-unit-width", w)
            header:SetAttribute("_initialAttribute-unit-height", h)
        end
    end

    return sections
end

---------------------------------------------------------------------------
-- MULTI-HEADER: Position per-group headers with group spacing
---------------------------------------------------------------------------
local function PositionRaidGroupHeaders()
    if InCombatLockdown() then
        _pending.groupReflow = true
        return
    end

    local layout = GetLayoutSettings(true)
    if not layout then return end

    local grow = GetLayoutGrowDirection(layout, "DOWN")
    local groupGrow = layout.groupGrowDirection
    local groupSpacing = layout.groupSpacing or 10
    local horizontal = (grow == "LEFT" or grow == "RIGHT")

    -- Determine default group grow direction based on primary axis
    if not groupGrow then
        groupGrow = horizontal and "DOWN" or "RIGHT"
    end

    local raidRoot = QUI_GF.anchorFrames.raid
    local prevHeader = nil

    for _, header in ipairs(QUI_GF.raidGroupHeaders) do
        if header and header:IsShown() then
            header:ClearAllPoints()

            if not prevHeader then
                -- First visible header: anchor to root
                if horizontal then
                    if groupGrow == "UP" then
                        if grow == "RIGHT" then
                            header:SetPoint("BOTTOMLEFT", raidRoot, "BOTTOMLEFT", 0, 0)
                        else
                            header:SetPoint("BOTTOMRIGHT", raidRoot, "BOTTOMRIGHT", 0, 0)
                        end
                    else -- DOWN
                        if grow == "RIGHT" then
                            header:SetPoint("TOPLEFT", raidRoot, "TOPLEFT", 0, 0)
                        else
                            header:SetPoint("TOPRIGHT", raidRoot, "TOPRIGHT", 0, 0)
                        end
                    end
                else
                    if groupGrow == "LEFT" then
                        if grow == "DOWN" then
                            header:SetPoint("TOPRIGHT", raidRoot, "TOPRIGHT", 0, 0)
                        else
                            header:SetPoint("BOTTOMRIGHT", raidRoot, "BOTTOMRIGHT", 0, 0)
                        end
                    else -- RIGHT
                        if grow == "DOWN" then
                            header:SetPoint("TOPLEFT", raidRoot, "TOPLEFT", 0, 0)
                        else
                            header:SetPoint("BOTTOMLEFT", raidRoot, "BOTTOMLEFT", 0, 0)
                        end
                    end
                end
            else
                -- Subsequent headers: anchor relative to previous
                if horizontal then
                    if groupGrow == "UP" then
                        if grow == "RIGHT" then
                            header:SetPoint("BOTTOMLEFT", prevHeader, "TOPLEFT", 0, groupSpacing)
                        else
                            header:SetPoint("BOTTOMRIGHT", prevHeader, "TOPRIGHT", 0, groupSpacing)
                        end
                    else -- DOWN
                        if grow == "RIGHT" then
                            header:SetPoint("TOPLEFT", prevHeader, "BOTTOMLEFT", 0, -groupSpacing)
                        else
                            header:SetPoint("TOPRIGHT", prevHeader, "BOTTOMRIGHT", 0, -groupSpacing)
                        end
                    end
                else
                    if groupGrow == "LEFT" then
                        if grow == "DOWN" then
                            header:SetPoint("TOPRIGHT", prevHeader, "TOPLEFT", -groupSpacing, 0)
                        else
                            header:SetPoint("BOTTOMRIGHT", prevHeader, "BOTTOMLEFT", -groupSpacing, 0)
                        end
                    else -- RIGHT
                        if grow == "DOWN" then
                            header:SetPoint("TOPLEFT", prevHeader, "TOPRIGHT", groupSpacing, 0)
                        else
                            header:SetPoint("BOTTOMLEFT", prevHeader, "BOTTOMRIGHT", groupSpacing, 0)
                        end
                    end
                end
            end

            prevHeader = header
        end
    end
end

---------------------------------------------------------------------------
-- HEADER: Create secure group headers
---------------------------------------------------------------------------
local function CreateHeaders()
    local db = GetSettings()
    if not db then return end
    local position = db.position
    local partyRoot = EnsureAnchorFrame("party")
    local raidRoot = EnsureAnchorFrame("raid")

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
    local partyHeader = CreateFrame("Frame", "QUI_PartyHeader", partyRoot, "SecureGroupHeaderTemplate")
    partyHeader:SetAttribute("template", "SecureUnitButtonTemplate, BackdropTemplate")
    partyHeader:SetAttribute("initialConfigFunction", initConfigFunc)
    ConfigurePartyHeader(partyHeader)

    -- Position: prefer frameAnchoring if available, fall back to legacy db.position
    local partyW, partyH = CalculateHeaderSize(db, 5)
    partyHeader:SetSize(partyW, partyH)
    partyRoot:ClearAllPoints()
    local faDB = QUI.db and QUI.db.profile and QUI.db.profile.frameAnchoring
    local faParty = faDB and faDB.partyFrames
    if faParty and faParty.point then
        partyRoot:SetPoint(faParty.point, UIParent, faParty.relative or faParty.point, faParty.offsetX or 0, faParty.offsetY or 0)
    else
        local offsetX = position and position.offsetX or -400
        local offsetY = position and position.offsetY or 0
        partyRoot:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
    end
    partyHeader:SetMovable(true)
    partyHeader:SetClampedToScreen(true)

    -- Pre-create all 5 party frames upfront so no frames are created mid-combat.
    -- Two requirements for SecureGroupHeaderTemplate to create children:
    --   1. Parent root must be shown (hidden parent prevents child creation)
    --   2. At least 1 managed unit must exist (showPlayer + showSolo forces the player)
    partyRoot:Show()
    partyHeader:SetAttribute("showPlayer", true)
    partyHeader:SetAttribute("showSolo", true)
    partyHeader:SetAttribute("startingIndex", -4)
    partyHeader:Show()
    partyHeader:SetAttribute("startingIndex", 1)
    partyHeader:Hide()
    partyRoot:Hide()
    -- Restore correct show* attributes for runtime operation
    ConfigurePartyHeader(partyHeader)

    QUI_GF.headers.party = partyHeader
    -- Watch for new children added by the secure header (handles late NPC frames)
    partyHeader:HookScript("OnAttributeChanged", function(self, key, value)
        if value and type(key) == "string" and key:match("^child") then
            DecorateGroupFrame(value)
            if not InCombatLockdown() then
                value:RegisterForClicks("AnyUp")
            else
                _pending.registerClicks = true
            end
        end
    end)

    -- Raid header
    local raidHeader = CreateFrame("Frame", "QUI_RaidHeader", raidRoot, "SecureGroupHeaderTemplate")
    raidHeader:SetAttribute("template", "SecureUnitButtonTemplate, BackdropTemplate")
    raidHeader:SetAttribute("initialConfigFunction", initConfigFunc)
    ConfigureRaidHeader(raidHeader)

    local raidCount = math_max(IsInRaid() and GetNumGroupMembers() or 25, 5)
    local raidW, raidH = CalculateHeaderSize(db, raidCount)
    raidHeader:SetSize(raidW, raidH)

    -- Raid position: position raidRoot from frameAnchoring (matching partyRoot).
    -- UpdateAnchorRoot will position the header within raidRoot.
    raidRoot:ClearAllPoints()
    local faRaid = faDB and faDB.raidFrames
    if faRaid and faRaid.point then
        raidRoot:SetPoint(faRaid.point, UIParent, faRaid.relative or faRaid.point, faRaid.offsetX or 0, faRaid.offsetY or 0)
    else
        local raidPos = db.raidPosition
        local raidOffX = raidPos and raidPos.offsetX or -400
        local raidOffY = raidPos and raidPos.offsetY or 0
        raidRoot:SetPoint("CENTER", UIParent, "CENTER", raidOffX, raidOffY)
    end
    raidHeader:SetMovable(true)
    raidHeader:SetClampedToScreen(true)

    -- Pre-create all 40 raid frames upfront so no frames are created mid-combat.
    -- Force showPlayer + showSolo so the header has at least 1 managed unit.
    raidRoot:Show()
    raidHeader:SetAttribute("showPlayer", true)
    raidHeader:SetAttribute("showSolo", true)
    raidHeader:SetAttribute("startingIndex", -39)
    raidHeader:Show()
    raidHeader:SetAttribute("startingIndex", 1)
    raidHeader:Hide()
    raidRoot:Hide()
    ConfigureRaidHeader(raidHeader)

    QUI_GF.headers.raid = raidHeader
    -- Watch for new children on raid header too
    raidHeader:HookScript("OnAttributeChanged", function(self, key, value)
        if value and type(key) == "string" and key:match("^child") then
            DecorateGroupFrame(value)
            if not InCombatLockdown() then
                value:RegisterForClicks("AnyUp")
            else
                _pending.registerClicks = true
            end
        end
    end)

    -- Raid section headers. Reused for grouped raids and for raid self-first mode.
    raidRoot:Show()  -- Parent must be visible for child creation
    for g = 1, MAX_RAID_SECTION_HEADERS do
        local groupHeader = CreateFrame("Frame", "QUI_RaidGroup" .. g .. "Header", raidRoot, "SecureGroupHeaderTemplate")
        groupHeader:SetAttribute("template", "SecureUnitButtonTemplate, BackdropTemplate")
        groupHeader:SetAttribute("initialConfigFunction", initConfigFunc)
        groupHeader:SetAttribute("showRaid", true)
        groupHeader:SetAttribute("showParty", false)
        groupHeader:SetAttribute("showPlayer", false)
        groupHeader:SetAttribute("showSolo", false)
        groupHeader:SetAttribute("groupBy", "GROUP")
        groupHeader:SetAttribute("groupFilter", tostring(g))
        groupHeader:SetAttribute("groupingOrder", tostring(g))
        groupHeader:SetAttribute("maxColumns", 8)
        groupHeader:SetAttribute("unitsPerColumn", 5)
        groupHeader:SetAttribute("_initialAttributeNames", "unit-width,unit-height")

        local rW, rH = GetFrameDimensions("small")
        groupHeader:SetAttribute("_initialAttribute-unit-width", rW)
        groupHeader:SetAttribute("_initialAttribute-unit-height", rH)
        groupHeader:SetSize(rW, rH)
        groupHeader:SetMovable(true)
        groupHeader:SetClampedToScreen(true)

        -- Set child layout attributes BEFORE pre-creation Show() so the
        -- SecureGroupHeaderTemplate positions children correctly on the
        -- very first layout pass.  Without this, children get the template's
        -- default positioning and may not fully reposition on /reload.
        local layoutDB = GetLayoutSettings(true)
        local preGrow = GetLayoutGrowDirection(layoutDB, "DOWN")
        local preSpacing = layoutDB and layoutDB.spacing or 2
        local preColumnAnchorPoint = GetRaidColumnAnchorPoint(layoutDB, preGrow)
        if preGrow == "DOWN" then
            groupHeader:SetAttribute("point", "TOP")
            groupHeader:SetAttribute("xOffset", 0)
            groupHeader:SetAttribute("yOffset", -preSpacing)
        elseif preGrow == "UP" then
            groupHeader:SetAttribute("point", "BOTTOM")
            groupHeader:SetAttribute("xOffset", 0)
            groupHeader:SetAttribute("yOffset", preSpacing)
        elseif preGrow == "RIGHT" then
            groupHeader:SetAttribute("point", "LEFT")
            groupHeader:SetAttribute("xOffset", preSpacing)
            groupHeader:SetAttribute("yOffset", 0)
        elseif preGrow == "LEFT" then
            groupHeader:SetAttribute("point", "RIGHT")
            groupHeader:SetAttribute("xOffset", -preSpacing)
            groupHeader:SetAttribute("yOffset", 0)
        end
        groupHeader:SetAttribute("columnAnchorPoint", preColumnAnchorPoint)

        -- Pre-create enough children for the largest possible section so
        -- custom raid self-first ordering never needs to create frames in combat.
        groupHeader:SetAttribute("showPlayer", true)
        groupHeader:SetAttribute("showSolo", true)
        groupHeader:SetAttribute("startingIndex", -39)
        groupHeader:Show()
        groupHeader:SetAttribute("startingIndex", 1)
        groupHeader:Hide()
        groupHeader:SetAttribute("showPlayer", false)
        groupHeader:SetAttribute("showSolo", false)

        groupHeader:HookScript("OnAttributeChanged", function(self, key, value)
            if value and type(key) == "string" and key:match("^child") then
                DecorateGroupFrame(value)
                if not InCombatLockdown() then
                    value:RegisterForClicks("AnyUp")
                else
                    _pending.registerClicks = true
                end
            end
        end)

        groupHeader._raidGroupIndex = g
        QUI_GF.raidGroupHeaders[g] = groupHeader
    end
    raidRoot:Hide()

    -- Self header — shows only the player for party/solo self-first.
    local selfHeader = CreateFrame("Frame", "QUI_SelfHeader", partyRoot, "SecureGroupHeaderTemplate")
    selfHeader:SetAttribute("template", "SecureUnitButtonTemplate, BackdropTemplate")
    selfHeader:SetAttribute("initialConfigFunction", initConfigFunc)
    selfHeader:SetAttribute("showPlayer", true)
    selfHeader:SetAttribute("showParty", false)
    selfHeader:SetAttribute("showRaid", false)
    selfHeader:SetAttribute("showSolo", true)
    selfHeader:SetAttribute("maxColumns", 1)
    selfHeader:SetAttribute("unitsPerColumn", 1)

    -- Use party dimensions for self header
    local partyDims = db.party and db.party.dimensions
    local selfW = partyDims and partyDims.partyWidth or 200
    local selfH = partyDims and partyDims.partyHeight or 40
    selfHeader:SetAttribute("_initialAttributeNames", "unit-width,unit-height")
    selfHeader:SetAttribute("_initialAttribute-unit-width", selfW)
    selfHeader:SetAttribute("_initialAttribute-unit-height", selfH)
    selfHeader:SetSize(selfW, selfH)
    selfHeader:SetMovable(true)
    selfHeader:SetClampedToScreen(true)

    -- Pre-create the single child (parent must be shown for creation to work)
    partyRoot:Show()
    selfHeader:SetAttribute("startingIndex", 1)
    selfHeader:Show()
    selfHeader:Hide()
    partyRoot:Hide()

    QUI_GF.headers.self = selfHeader
    selfHeader:HookScript("OnAttributeChanged", function(self, key, value)
        if value and type(key) == "string" and key:match("^child") then
            DecorateGroupFrame(value)
            if not InCombatLockdown() then
                value:RegisterForClicks("AnyUp")
            else
                _pending.registerClicks = true
            end
        end
    end)
end

---------------------------------------------------------------------------
-- HEADER: Helper to determine which raid groups (1-8) have at least one member
---------------------------------------------------------------------------
local function GetPopulatedRaidGroups()
    local populated = {}
    for i = 1, GetNumGroupMembers() do
        local _, _, subgroup = GetRaidRosterInfo(i)
        if subgroup then
            populated[subgroup] = true
        end
    end
    return populated
end

local function NormalizeRaidRole(role)
    if role == "TANK" or role == "HEALER" or role == "DAMAGER" then
        return role
    end
    return "NONE"
end

local function CompareRaidSectionMembers(a, b, sortMethod, sortByRole, playerFirst)
    if playerFirst and a.isPlayer ~= b.isPlayer then
        return a.isPlayer
    end

    if sortByRole and a.role ~= b.role then
        return (RAID_SECTION_ROLE_PRIORITY[a.role] or 99) < (RAID_SECTION_ROLE_PRIORITY[b.role] or 99)
    end

    if sortMethod == "NAME" then
        if a.name ~= b.name then
            return a.name < b.name
        end
    else
        if a.index ~= b.index then
            return a.index < b.index
        end
    end

    return a.index < b.index
end

GetRaidDisplaySections = function()
    if not IsInRaid() then
        return {}
    end

    local db = GetSettings()
    local layout = GetLayoutSettings(true)
    if not db or not layout then
        return {}
    end

    local raidSelfFirst = GetRaidSelfFirst(db)
    local groupBy = layout.groupBy or "GROUP"
    local sortMethod = layout.sortMethod or "INDEX"
    local sortByRole = layout.sortByRole == true and groupBy ~= "ROLE"
    local playerSectionKey
    local sectionsByKey = {}
    local sections = {}

    for i = 1, GetNumGroupMembers() do
        local unit = "raid" .. i
        local name, _, subgroup = GetRaidRosterInfo(i)
        if name then
            local _, classFile = UnitClass(unit)
            local role = NormalizeRaidRole(UnitGroupRolesAssigned(unit))
            local sectionKey, sectionOrder

            if groupBy == "NONE" then
                sectionKey, sectionOrder = "ALL", 1
            elseif groupBy == "ROLE" then
                sectionKey = role
                sectionOrder = RAID_SECTION_ROLE_PRIORITY[role] or 99
            elseif groupBy == "CLASS" then
                sectionKey = classFile or "UNKNOWN"
                sectionOrder = RAID_SECTION_CLASS_PRIORITY[sectionKey] or 99
            else
                sectionKey = tostring(subgroup or 0)
                sectionOrder = subgroup or 99
            end

            local section = sectionsByKey[sectionKey]
            if not section then
                section = {
                    key = sectionKey,
                    order = sectionOrder,
                    members = {},
                }
                sectionsByKey[sectionKey] = section
                table_insert(sections, section)
            end

            local isPlayer = UnitIsUnit(unit, "player")
            table_insert(section.members, {
                name = name,
                index = i,
                subgroup = subgroup or 0,
                classFile = classFile or "UNKNOWN",
                role = role,
                isPlayer = isPlayer,
            })

            if isPlayer then
                playerSectionKey = sectionKey
            end
        end
    end

    for _, section in ipairs(sections) do
        table_sort(section.members, function(a, b)
            return CompareRaidSectionMembers(a, b, sortMethod, sortByRole, raidSelfFirst)
        end)

        local names = {}
        for _, member in ipairs(section.members) do
            table_insert(names, member.name)
        end

        section.memberCount = #section.members
        section.nameList = table_concat(names, ",")
    end

    table_sort(sections, function(a, b)
        if raidSelfFirst and playerSectionKey then
            if a.key == playerSectionKey and b.key ~= playerSectionKey then
                return true
            end
            if b.key == playerSectionKey and a.key ~= playerSectionKey then
                return false
            end
        end

        if a.order ~= b.order then
            return a.order < b.order
        end

        return tostring(a.key) < tostring(b.key)
    end)

    return sections
end

GetRaidSectionUnitsPerColumn = function(layout)
    if not layout then return 5 end
    if (layout.groupBy or "GROUP") == "NONE" then
        return math_max(layout.unitsPerFlat or 5, 1)
    end
    return 5
end

CalculateRaidSectionHeaderSize = function(sectionCount, mode, layout)
    if not sectionCount or sectionCount <= 0 then
        return 1, 1
    end

    local frameW, frameH = GetFrameDimensions(mode)
    local spacing = layout and layout.spacing or 2
    local grow = GetLayoutGrowDirection(layout, "DOWN")
    local unitsPerColumn = math_max(1, math_min(sectionCount, GetRaidSectionUnitsPerColumn(layout)))
    local columnCount = math_max(1, math.ceil(sectionCount / unitsPerColumn))
    local leadingCount = math_min(sectionCount, unitsPerColumn)
    local horizontal = (grow == "LEFT" or grow == "RIGHT")

    if horizontal then
        return leadingCount * frameW + (leadingCount - 1) * spacing,
            columnCount * frameH + (columnCount - 1) * spacing
    end

    return columnCount * frameW + (columnCount - 1) * spacing,
        leadingCount * frameH + (leadingCount - 1) * spacing
end

-- Forward declaration: defined after UpdateHeaderVisibility (used in deferred callback)
local ApplyChildFrameLayout

---------------------------------------------------------------------------
-- HEADER: Update header sizes based on current roster
---------------------------------------------------------------------------
local function UpdateHeaderSizes()
    if InCombatLockdown() and not _state.inInitSafeWindow then return end
    local db = GetSettings()
    if not db then return end

    local partyHdr = QUI_GF.headers.party
    if partyHdr then
        local count = math_max(GetVisiblePartyUnitCount(), 1)
        local w, h = CalculateHeaderSize(db, count)
        partyHdr:SetSize(w, h)
    end

    if UseRaidSectionHeaders(db) and IsInRaid() then
        -- Section-header mode: size each visible raid section individually.
        local mode = GetGroupMode()
        local raidVdb = db.raid or db
        local layout = raidVdb and raidVdb.layout
        local sections = GetRaidSelfFirst(db) and GetRaidDisplaySections() or nil
        local populated = sections and nil or GetPopulatedRaidGroups()

        for g, header in ipairs(QUI_GF.raidGroupHeaders) do
            if sections then
                local section = sections[g]
                if section then
                    local hdrW, hdrH = CalculateRaidSectionHeaderSize(section.memberCount, mode, layout)
                    header:SetSize(hdrW, hdrH)
                else
                    header:SetSize(1, 1)
                end
            elseif g <= 8 and populated and populated[g] then
                local groupCount = 0
                for i = 1, GetNumGroupMembers() do
                    local _, _, subgroup = GetRaidRosterInfo(i)
                    if subgroup == g then
                        groupCount = groupCount + 1
                    end
                end
                local hdrW, hdrH = CalculateRaidSectionHeaderSize(math_max(groupCount, 1), mode, layout)
                header:SetSize(hdrW, hdrH)
            else
                header:SetSize(1, 1)
            end
        end

        -- Hide single raid header whenever section headers are active.
        if QUI_GF.headers.raid then QUI_GF.headers.raid:SetSize(1, 1) end
    else
        local raidHdr = QUI_GF.headers.raid
        if raidHdr then
            local count = IsInRaid() and GetNumGroupMembers() or 25
            count = math_max(count, 5)
            local w, h = CalculateHeaderSize(db, count)
            raidHdr:SetSize(w, h)
        end
    end

    -- Self header uses party dimensions; root layout handles ordering.
    local selfHdr = QUI_GF.headers.self
    if selfHdr then
        local partyDims = db.party and db.party.dimensions
        local sw = partyDims and partyDims.partyWidth or 200
        local sh = partyDims and partyDims.partyHeight or 40
        selfHdr:SetAttribute("_initialAttribute-unit-width", sw)
        selfHdr:SetAttribute("_initialAttribute-unit-height", sh)
        selfHdr:SetSize(sw, sh)
        -- Resize existing child
        local child = selfHdr:GetAttribute("child1")
        if child then child:SetSize(sw, sh) end
        -- Self header is party-only, so keep it chained to the party block.
        if not (_G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("partyFrames")) then
            selfHdr:ClearAllPoints()
            if partyHdr then
                selfHdr:SetPoint("BOTTOMLEFT", partyHdr, "TOPLEFT", 0, 4)
            end
        end
    end

    UpdateAnchorFrames()
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
            _pending.registerClicks = true
        end
        i = i + 1
    end
end

---------------------------------------------------------------------------
-- HEADER: Batched decoration — stagger across ticks to avoid "script ran
-- too long" when decorating 40+ raid frames at init.
---------------------------------------------------------------------------
local function CollectHeaderChildren(header, out)
    if not header then return end
    local i = 1
    while true do
        local child = header:GetAttribute("child" .. i)
        if not child then break end
        out[#out + 1] = child
        i = i + 1
    end
end

local function DecorateBatched(frames, onComplete)
    local total = #frames
    if total == 0 then
        if onComplete then onComplete() end
        return
    end

    -- Small groups (party/small raid): decorate all at once — no visible stagger.
    -- Only batch for 25+ frames to guard against "script ran too long".
    local BATCH_THRESHOLD = 25
    local inCombat = InCombatLockdown()

    if total <= BATCH_THRESHOLD then
        for i = 1, total do
            DecorateGroupFrame(frames[i])
            if not inCombat then
                frames[i]:RegisterForClicks("AnyUp")
            else
                _pending.registerClicks = true
            end
        end
        if onComplete then onComplete() end
        return
    end

    -- Large raids: batch 20 per tick
    local idx = 1
    local function ProcessBatch()
        local batchEnd = math_min(idx + 19, total)
        for i = idx, batchEnd do
            DecorateGroupFrame(frames[i])
            if not inCombat then
                frames[i]:RegisterForClicks("AnyUp")
            else
                _pending.registerClicks = true
            end
        end
        idx = batchEnd + 1
        if idx <= total then
            C_Timer.After(0, ProcessBatch)
        elseif onComplete then
            onComplete()
        end
    end
    ProcessBatch()
end

---------------------------------------------------------------------------
-- HEADER: Show/hide based on group status
---------------------------------------------------------------------------
-- Show/hide per-group headers; hide single raid header
local function ShowRaidGroupHeaders()
    if QUI_GF.headers.raid then QUI_GF.headers.raid:Hide() end

    local db = GetSettings()
    local raidSelfFirst = GetRaidSelfFirst(db)
    local sections = ConfigureRaidGroupHeaders()
    local populated = raidSelfFirst and nil or GetPopulatedRaidGroups()

    for g, header in ipairs(QUI_GF.raidGroupHeaders) do
        if raidSelfFirst then
            if sections and sections[g] then
                header:Show()
            else
                header:Hide()
            end
        elseif g <= 8 and populated and populated[g] then
            header:Show()
        else
            header:Hide()
        end
    end

    PositionRaidGroupHeaders()
end

-- Hide all per-group headers
local function HideRaidGroupHeaders()
    for _, header in ipairs(QUI_GF.raidGroupHeaders) do
        if header then header:Hide() end
    end
end

local function UpdateHeaderVisibility()
    if InCombatLockdown() and not _state.inInitSafeWindow then
        _pending.visibilityUpdate = true
        return
    end

    local db = GetSettings()
    if not db or not db.enabled then
        if QUI_GF.headers.party then QUI_GF.headers.party:Hide() end
        if QUI_GF.headers.raid then QUI_GF.headers.raid:Hide() end
        if QUI_GF.headers.self then QUI_GF.headers.self:Hide() end
        HideRaidGroupHeaders()
        UpdateAnchorFrames()
        return
    end

    if QUI_GF.testMode then
        -- Test mode handled by edit mode module
        UpdateAnchorFrames()
        return
    end

    local partySelfFirst = GetPartySelfFirst(db)
    local selfHeader = QUI_GF.headers.self
    local useRaidSections = UseRaidSectionHeaders(db)

    if QUI_GF.headers.party then ConfigurePartyHeader(QUI_GF.headers.party) end

    -- Configure single or multi-header raid headers
    if useRaidSections then
        -- Single header is hidden; per-group headers are configured below
    else
        if QUI_GF.headers.raid then ConfigureRaidHeader(QUI_GF.headers.raid) end
        HideRaidGroupHeaders()
    end

    if selfHeader then
        selfHeader:SetAttribute("showSolo", partySelfFirst and true or false)
    end

    if IsInRaid() then
        if QUI_GF.headers.party then QUI_GF.headers.party:Hide() end
        if useRaidSections then
            ShowRaidGroupHeaders()
        else
            if QUI_GF.headers.raid then QUI_GF.headers.raid:Show() end
            HideRaidGroupHeaders()
        end
        if selfHeader then
            selfHeader:Hide()
        end
    elseif IsInGroup() then
        if QUI_GF.headers.raid then QUI_GF.headers.raid:Hide() end
        HideRaidGroupHeaders()
        if QUI_GF.headers.party then QUI_GF.headers.party:Show() end
        if selfHeader then
            if partySelfFirst then selfHeader:Show() else selfHeader:Hide() end
        end
    else
        -- Solo: check showSolo setting
        local partyLayout = GetLayoutSettings(false)
        local showSolo = partyLayout and partyLayout.showSolo
        if partySelfFirst then showSolo = false end
        if showSolo then
            if QUI_GF.headers.raid then QUI_GF.headers.raid:Hide() end
            HideRaidGroupHeaders()
            if QUI_GF.headers.party then QUI_GF.headers.party:Show() end
        else
            if QUI_GF.headers.party then QUI_GF.headers.party:Hide() end
            if QUI_GF.headers.raid then QUI_GF.headers.raid:Hide() end
            HideRaidGroupHeaders()
        end
        if selfHeader then
            if partySelfFirst then selfHeader:Show() else selfHeader:Hide() end
        end
    end

    -- On first layout (no decorated children yet), hide anchor roots so
    -- the user never sees unstyled raw rectangles pop in one by one.
    -- The secure header still creates children (the root is Shown via
    -- UpdateAnchorFrames), but alpha 0 keeps them invisible until ready.
    -- Skip for subsequent roster updates when frames are already styled.
    local needsReveal = not _state.initialLayoutDone
    if needsReveal then
        for _, root in pairs(QUI_GF.anchorFrames) do
            root:SetAlpha(0)
        end
    end

    UpdateHeaderSizes()
    UpdateAnchorFrames()

    -- End safe period before the deferred callback so combat guards apply
    _pending.initSafe = false

    -- Defer decoration + map rebuild to next frame (after header creates children).
    -- Batched only for 25+ frames to avoid "script ran too long" in large raids.
    C_Timer.After(0, function()
        local allChildren = {}
        CollectHeaderChildren(QUI_GF.headers.party, allChildren)
        if UseRaidSectionHeaders() and IsInRaid() then
            for _, header in ipairs(QUI_GF.raidGroupHeaders) do
                CollectHeaderChildren(header, allChildren)
            end
        else
            CollectHeaderChildren(QUI_GF.headers.raid, allChildren)
        end
        CollectHeaderChildren(QUI_GF.headers.self, allChildren)

        DecorateBatched(allChildren, function()
            ApplyChildFrameLayout()
            RebuildUnitFrameMap()
            QUI_GF:RefreshAllFrames()
            UpdateAnchorFrames()
            initSafePeriod = false

            -- Reveal: all frames are now decorated, sized, and populated.
            if needsReveal then
                _state.initialLayoutDone = true
                for _, root in pairs(QUI_GF.anchorFrames) do
                    root:SetAlpha(1)
                end
            end
        end)
    end)
end

---------------------------------------------------------------------------
-- SCALING: Resize frames based on group size thresholds
---------------------------------------------------------------------------
-- Resize/layout unit buttons and bars. SetSize on the secure unit buttons
-- themselves is protected, so skip it during combat — the pending resize
-- will re-apply after combat via PLAYER_REGEN_ENABLED.
-- Uses per-child dimensions: party/self children get party dims, raid
-- children get current raid-mode dims. This prevents cross-contamination
-- when the group transitions between party and raid.
ApplyChildFrameLayout = function()
    local inCombat = InCombatLockdown()
    local partyW, partyH = GetFrameDimensions("party")
    local raidMode = GetGroupMode()
    local raidW, raidH = GetFrameDimensions(raidMode ~= "party" and raidMode or "small")

    local function LayoutChildren(header)
        if not header then return end
        local i = 1
        while true do
            local child = header:GetAttribute("child" .. i)
            if not child then break end
            if not inCombat then
                local cw, ch = child._isRaid and raidW or partyW, child._isRaid and raidH or partyH
                child:SetSize(cw, ch)
            end
            if child.healthBar and child.powerBar then
                local general = GetGeneralSettings(child._isRaid)
                local borderPx = general and general.borderSize or 1
                local borderSize = borderPx > 0 and (QUICore.Pixels and QUICore:Pixels(borderPx, child) or borderPx) or 0
                local powerSettings = GetPowerSettings(child._isRaid)
                local powerHeight = powerSettings and powerSettings.showPowerBar ~= false and
                    (QUICore.PixelRound and QUICore:PixelRound(powerSettings.powerBarHeight or 4, child) or 4) or 0
                local px = QUICore.GetPixelSize and QUICore:GetPixelSize(child) or 1
                local sepH = powerHeight > 0 and px or 0

                child.healthBar:ClearAllPoints()
                child.healthBar:SetPoint("TOPLEFT", child, "TOPLEFT", borderSize, -borderSize)
                child.healthBar:SetPoint("BOTTOMRIGHT", child, "BOTTOMRIGHT", -borderSize, borderSize + powerHeight + sepH)
                ApplyStatusBarTexture(child.healthBar)

                local vertFill = (GetHealthFillDirection(child._isRaid) == "VERTICAL")
                child.healthBar:SetOrientation(vertFill and "VERTICAL" or "HORIZONTAL")
                child._isVerticalFill = vertFill

                if child.powerBar then
                    child.powerBar:ClearAllPoints()
                    child.powerBar:SetPoint("BOTTOMLEFT", child, "BOTTOMLEFT", borderSize, borderSize)
                    child.powerBar:SetPoint("BOTTOMRIGHT", child, "BOTTOMRIGHT", -borderSize, borderSize)
                    child.powerBar:SetHeight(powerHeight)
                    ApplyStatusBarTexture(child.powerBar)
                end
                if child.healPredictionBar then ApplyStatusBarTexture(child.healPredictionBar) end
            end
            i = i + 1
        end
    end

    for _, headerKey in ipairs({"party", "raid", "self"}) do
        LayoutChildren(QUI_GF.headers[headerKey])
    end
    for _, header in ipairs(QUI_GF.raidGroupHeaders) do
        LayoutChildren(header)
    end
end

local function UpdateFrameScaling(forceUpdate)
    local mode = GetGroupMode()

    if InCombatLockdown() and not _state.inInitSafeWindow then
        _pending.resize = true
        _pending.resizeForce = _pending.resizeForce or (forceUpdate and true or false)
        ApplyChildFrameLayout()
        return
    end

    if not forceUpdate and mode == _state.lastMode then return end
    _state.lastMode = mode

    -- Per-header-type attributes: party/self get party dims, raid headers
    -- get current raid-mode dims. This ensures initialConfigFunction uses
    -- the correct dimensions if the secure system ever creates new children.
    local partyW, partyH = GetFrameDimensions("party")
    local raidW, raidH = GetFrameDimensions(mode ~= "party" and mode or "small")

    local partyHeader = QUI_GF.headers.party
    if partyHeader then
        partyHeader:SetAttribute("_initialAttribute-unit-width", partyW)
        partyHeader:SetAttribute("_initialAttribute-unit-height", partyH)
    end
    local selfHeader = QUI_GF.headers.self
    if selfHeader then
        selfHeader:SetAttribute("_initialAttribute-unit-width", partyW)
        selfHeader:SetAttribute("_initialAttribute-unit-height", partyH)
    end
    local raidHeader = QUI_GF.headers.raid
    if raidHeader then
        raidHeader:SetAttribute("_initialAttribute-unit-width", raidW)
        raidHeader:SetAttribute("_initialAttribute-unit-height", raidH)
    end
    for _, header in ipairs(QUI_GF.raidGroupHeaders) do
        if header then
            header:SetAttribute("_initialAttribute-unit-width", raidW)
            header:SetAttribute("_initialAttribute-unit-height", raidH)
        end
    end

    ApplyChildFrameLayout()
    UpdateHeaderSizes()
end

---------------------------------------------------------------------------
-- RANGE CHECK: Ticker-based range dimming (spell-based for combat safety)
---------------------------------------------------------------------------
-- _state.rangeCheckTicker: range check C_Timer ticker

-- Range-check spell lookup tables
local RANGE_SPELLS = {
    -- Spec → friendly spell ID (validated with IsPlayerSpell).
    -- DK: no friendly spell — Death Coil returns nil on player targets; use UnitInRange / hostile spell.
    spec = {
        [250] = nil, [251] = nil, [252] = nil,          -- Death Knight
        [577] = nil, [581] = nil,                        -- Demon Hunter
        [102] = 8936, [103] = 8936, [104] = 8936,       -- Druid: Regrowth
        [105] = 774,                                     -- Resto Druid: Rejuvenation
        [1467] = 360995, [1468] = 360995, [1473] = 360995, -- Evoker: Emerald Blossom
        [253] = nil, [254] = nil, [255] = nil,           -- Hunter
        [62] = 1459, [63] = 1459, [64] = 1459,          -- Mage: Arcane Intellect
        [268] = 116670, [269] = 116670, [270] = 116670, -- Monk: Vivify
        [65] = 19750, [66] = 19750, [70] = 19750,       -- Paladin: Flash of Light
        [256] = 17, [257] = 2061, [258] = 17,           -- Priest: PW:S / Flash Heal
        [259] = 57934, [260] = 57934, [261] = 57934,    -- Rogue: Tricks of the Trade
        [262] = 8004, [263] = 8004, [264] = 8004,       -- Shaman: Healing Surge
        [265] = 5697, [266] = 5697, [267] = 5697,       -- Warlock: Unending Breath
        [71] = nil, [72] = nil, [73] = nil,             -- Warrior
    },
    -- Hostile spell per spec (UnitCanAttack)
    specHostile = {
        [250] = 47541, [251] = 47541, [252] = 47541,
        [577] = 185123, [581] = 185123,
        [102] = 8921, [103] = 8921, [104] = 8921, [105] = 8921,
        [1467] = 361469, [1468] = 361469, [1473] = 361469,
        [253] = 193455, [254] = 19434, [255] = 259491,
        [62] = 30451, [63] = 133, [64] = 116,
        [268] = 115546, [269] = 115546, [270] = 115546,
        [65] = 62124, [66] = 62124, [70] = 62124,
        [256] = 585, [257] = 585, [258] = 585,
        [259] = 36554, [260] = 185763, [261] = 36554,
        [262] = 188196, [263] = 188196, [264] = 188196,
        [265] = 686, [266] = 686, [267] = 29722,
        [71] = 355, [72] = 355, [73] = 355,
    },
    -- Class fallback: used if spec not detected or spec spell not known
    class = {
        PRIEST      = { 2061, 17 },          -- Flash Heal, Power Word: Shield
        PALADIN     = { 19750 },             -- Flash of Light
        DRUID       = { 8936, 774 },         -- Regrowth, Rejuvenation
        SHAMAN      = { 8004 },              -- Healing Surge
        MONK        = { 116670 },            -- Vivify
        EVOKER      = { 360995, 361469 },    -- Emerald Blossom, Living Flame
        MAGE        = { 1459 },              -- Arcane Intellect
        WARLOCK     = { 5697 },              -- Unending Breath
        ROGUE       = { 57934 },             -- Tricks of the Trade
        DEATHKNIGHT = {},
        WARRIOR     = {},
        DEMONHUNTER = {},
        HUNTER      = {},
    },
    classHostile = {
        DEATHKNIGHT = 47541, DEMONHUNTER = 185123, DRUID = 8921,
        EVOKER = 361469, HUNTER = 75, MAGE = 116, MONK = 115546,
        PALADIN = 62124, PRIEST = 585, ROGUE = 36554,
        SHAMAN = 188196, WARLOCK = 686, WARRIOR = 355,
    },
    -- Class → single rez spell ID (Druid: Rebirth resolved in ResolveRangeSpells)
    res = {
        PRIEST = 2006, PALADIN = 7328, DRUID = 50769,
        SHAMAN = 2008, MONK = 115178, EVOKER = 361227, DEATHKNIGHT = 61999,
    },
}

local _range = {
    playerClass = nil,
    spell = nil,         -- Resolved friendly spell ID for living targets
    hostileSpell = nil,  -- Resolved hostile spell for UnitCanAttack targets
    resSpell = nil,      -- Resolved rez spell ID for dead targets
    cache = {},          -- unit → boolean (change detection, avoids redundant SetAlpha)
    cacheTime = {},      -- unit → GetTime() (skip recently event-updated units in ticker)
}

local function ResolveRangeSpells()
    if not _range.playerClass then
        _range.playerClass = select(2, UnitClass("player"))
    end

    -- Clear cache — spells changed, previous results may be stale
    wipe(_range.cache)

    -- Resolve primary range spell (spec-based first, then class fallback)
    _range.spell = nil
    local specIndex = GetSpecialization and GetSpecialization()
    local specID = specIndex and GetSpecializationInfo and GetSpecializationInfo(specIndex)
    if specID and RANGE_SPELLS.spec[specID] then
        local spellID = RANGE_SPELLS.spec[specID]
        if spellID and IsPlayerSpell(spellID) then
            _range.spell = spellID
        end
    end

    -- Class fallback if spec lookup didn't resolve
    if not _range.spell then
        local candidates = RANGE_SPELLS.class[_range.playerClass]
        if candidates then
            for _, spellID in ipairs(candidates) do
                if IsPlayerSpell(spellID) then
                    _range.spell = spellID
                    break
                end
            end
        end
    end

    _range.hostileSpell = nil
    if specID and RANGE_SPELLS.specHostile[specID] then
        local hid = RANGE_SPELLS.specHostile[specID]
        if hid and IsPlayerSpell(hid) then
            _range.hostileSpell = hid
        end
    end
    if not _range.hostileSpell then
        local hid = RANGE_SPELLS.classHostile[_range.playerClass]
        if hid and IsPlayerSpell(hid) then
            _range.hostileSpell = hid
        end
    end

    -- Resolve rez spell (Druid: Rebirth for combat-consistent corpse range)
    _range.resSpell = nil
    if _range.playerClass == "DRUID" then
        if IsPlayerSpell(20484) then
            _range.resSpell = 20484
        elseif IsPlayerSpell(50769) then
            _range.resSpell = 50769
        end
    else
        local rezID = RANGE_SPELLS.res[_range.playerClass]
        if rezID and IsPlayerSpell(rezID) then
            _range.resSpell = rezID
        end
    end
end

local function CheckUnitRange(unit)
    if UnitIsUnit(unit, "player") then return true end
    if not UnitExists(unit) then return true end

    -- Phased units are always out of range
    if UnitPhaseReason and UnitPhaseReason(unit) then
        return false
    end

    local connected = UnitIsConnected(unit)
    if IsSecretValue(connected) then connected = true end
    if not connected then
        if not IsNPCPartyMember(unit) then return true end
    end

    local isDead = UnitIsDeadOrGhost(unit)
    if IsSecretValue(isDead) then isDead = false end

    local friendlyReturnedNil = false

    -- Hostile units (UnitCanAttack): check hostile spell range first;
    -- also handles edge cases with cross-faction party members.
    if UnitCanAttack("player", unit) then
        if _range.hostileSpell then
            local inRangeH = C_Spell.IsSpellInRange(_range.hostileSpell, unit)
            if inRangeH ~= nil then
                return inRangeH
            end
        end
        return true
    end

    if _range.spell and not isDead then
        local result = C_Spell.IsSpellInRange(_range.spell, unit)
        if result == true then
            return true
        elseif result == false then
            if not InCombatLockdown() and CheckInteractDistance(unit, 4) then
                return true
            end
            return false
        else
            friendlyReturnedNil = true
        end
        -- result == nil: spell not applicable, fall through to UnitInRange
    end

    if isDead and _range.resSpell then
        local result = C_Spell.IsSpellInRange(_range.resSpell, unit)
        if result ~= nil then return result end
    end

    if not InCombatLockdown() then
        return CheckInteractDistance(unit, 4) and true or false
    end

    -- In-combat fallback: UnitInRange (~38-40 yd) before treating friendly nil as OOR.
    -- Returns secret booleans in Midnight+ — SetAlphaFromBoolean handles them natively.
    if UnitInRange then
        local inRange = UnitInRange(unit)
        if issecretvalue and issecretvalue(inRange) then
            return inRange
        end
        if inRange ~= nil then return inRange end
    end

    if _range.spell and friendlyReturnedNil and connected and not isDead then
        return false
    end

    return true
end

local function ApplyRangeAlpha(frame, inRange, outAlpha)
    -- SetAlphaFromBoolean handles secret booleans natively (Midnight+ C-side API).
    -- When UnitInRange returns a secret boolean, this resolves it correctly.
    if frame.SetAlphaFromBoolean then
        frame:SetAlphaFromBoolean(inRange, 1, outAlpha)
    else
        frame:SetAlpha(inRange and 1 or outAlpha)
    end
end

local function DoRangeCheck()
    -- Fallback ticker: catches edge cases not covered by UNIT_IN_RANGE_UPDATE
    -- (LibRangeCheck spells with non-38yd thresholds, OOC interact distance).
    -- Skips units recently updated by the event handler.
    local partyRange = GetRangeSettings(false)
    local raidRange = GetRangeSettings(true)
    if (not partyRange or partyRange.enabled == false) and (not raidRange or raidRange.enabled == false) then return end

    local now = GetTime()
    for unit, frame in pairs(QUI_GF.unitFrameMap) do
        if frame and frame:IsShown() then
            -- Skip units updated by UNIT_IN_RANGE_UPDATE within the last 0.4s
            local lastEventTime = _range.cacheTime[unit]
            if lastEventTime and (now - lastEventTime) < 0.4 then
                -- Event-driven update is still fresh, skip this unit
            else
                local rangeSettings = GetRangeSettings(frame._isRaid)
                if rangeSettings and rangeSettings.enabled ~= false then
                    local outAlpha = rangeSettings.outOfRangeAlpha or 0.4
                    local inRange = CheckUnitRange(unit)
                    local state = GetFrameState(frame)

                    local cached = _range.cache[unit]
                    local isSecret = issecretvalue and (issecretvalue(inRange) or issecretvalue(cached))

                    if isSecret or cached ~= inRange or state.outOfRange == nil then
                        _range.cache[unit] = inRange
                        state.outOfRange = true
                        state.inRange = inRange
                        ApplyRangeAlpha(frame, inRange, outAlpha)
                    end
                end
            end
        end
    end
end

local function StartRangeCheck()
    if _state.rangeCheckTicker then return end
    -- Start if either party or raid has range checking enabled
    local partyRange = GetRangeSettings(false)
    local raidRange = GetRangeSettings(true)
    if (not partyRange or partyRange.enabled == false) and (not raidRange or raidRange.enabled == false) then return end

    -- Ensure spells are resolved before starting
    if not _range.spell and not _range.resSpell and not _range.hostileSpell then
        ResolveRangeSpells()
    end

    -- Slow fallback interval — UNIT_IN_RANGE_UPDATE is the primary driver.
    -- Large raids use a longer interval to reduce per-tick work (40+ frames).
    local interval = GetGroupSize() > 25 and 1.0 or 0.75
    _state.rangeCheckTicker = C_Timer.NewTicker(interval, DoRangeCheck)
end

local function StopRangeCheck()
    if _state.rangeCheckTicker then
        _state.rangeCheckTicker:Cancel()
        _state.rangeCheckTicker = nil
    end
    wipe(_range.cache)
    wipe(_range.cacheTime)
end

---------------------------------------------------------------------------
-- GROUP_ROSTER_UPDATE: Hoisted deferred callback (avoids closure allocation)
-- Called 0.2s after the coalesced GRU fires, giving secure headers time to
-- create/reassign children before we rebuild the unit→frame map.
---------------------------------------------------------------------------
local function GRU_DeferredWork()
    _state.gruDeferredPending = false
    DecorateHeaderChildren(QUI_GF.headers.party)
    if UseRaidSectionHeaders() and IsInRaid() then
        for _, header in ipairs(QUI_GF.raidGroupHeaders) do
            DecorateHeaderChildren(header)
        end
    else
        DecorateHeaderChildren(QUI_GF.headers.raid)
    end
    RebuildUnitFrameMap()
    -- Refresh GUID cache so OnAttributeChanged skip has fresh data
    for unit, frame in pairs(QUI_GF.unitFrameMap) do
        _state.unitGuidCache[frame] = UnitGUID(unit)
    end
    wipe(_range.cache)  -- Fresh map — force re-evaluate all units
    wipe(_range.cacheTime)
    wipe(_state.cachedMarkers)
    -- Evict stale aura cache entries for units no longer in the group
    local GFA = ns.QUI_GroupFrameAuras
    if GFA and GFA.PruneAuraCache then GFA.PruneAuraCache() end
    UpdateFrameScaling(true)
    QUI_GF:RefreshAllFrames()
    -- Ensure ticker is running (may not have started yet on first roster event)
    StartRangeCheck()
end

-- Coalescing OnUpdate: fires once on the render frame AFTER the GRU burst.
gruCoalesceFrame:SetScript("OnUpdate", function(self)
    self:Hide()  -- One-shot: process once, then stop
    UpdateHeaderVisibility()
    UpdateFrameScaling(true)
    UpdateHeaderSizes()
    UpdateSelectiveEvents()
    -- Schedule deferred work (secure headers need time to create children).
    -- Cancel-and-reschedule: if a previous timer is still pending from an
    -- earlier burst that hasn't fired yet, this replaces it harmlessly
    -- (the flag prevents double-processing).
    if not _state.gruDeferredPending then
        _state.gruDeferredPending = true
        C_Timer.After(0.2, GRU_DeferredWork)
    end
end)

---------------------------------------------------------------------------
-- EVENTS: Centralized event dispatch
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")

-- Cached module-enabled flag: refreshed on settings change, avoids
-- GetSettings() (5-6 table lookups) on every single unit event.
local function RefreshCachedEnabled()
    local db = GetSettings()
    _state.cachedModuleEnabled = db and db.enabled or false
    _state.cachedModuleDB = db
end

local function OnEvent(self, event, arg1, ...)
    if not QUI_GF.initialized then return end

    -- Fast path: unit events use O(1) map lookup.
    -- Skip GetSettings() entirely for units not in the map (nameplates,
    -- boss, arena, target, focus, pet) — saves ~20k table lookups/sec in raids.
    if type(arg1) == "string" then
        local frame = QUI_GF.unitFrameMap[arg1]

        if not frame then
            -- Self-healing: rebuild map on miss for party/raid/player units.
            -- Fast prefix check avoids per-event regex (string.sub vs :match).
            local p4 = arg1:sub(1, 4)
            if p4 == "part" or p4 == "raid" or arg1 == "player" then
                local now = GetTime()
                if not QUI_GF.lastMapRebuild or (now - QUI_GF.lastMapRebuild) > 1.0 then
                    QUI_GF.lastMapRebuild = now
                    RebuildUnitFrameMap()
                    frame = QUI_GF.unitFrameMap[arg1]
                end
            end
            if not frame then return end  -- Not a tracked unit, bail early
        end

        -- Matched frame — check cached enabled state
        if not _state.cachedModuleEnabled then return end

        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            -- No throttle — UNIT_HEALTH is already coalesced by the WoW client.
            -- Fast path: share unit/dead/maxHP across all three updates to avoid
            -- redundant UnitExists, UnitIsDeadOrGhost, UnitHealthMax API calls
            -- (3→1 of each per event in a 20-person raid).
            local unit = frame.unit
            if not unit or not UnitExists(unit) then return end
            UpdateHealth(frame)
            local isDead = UnitIsDeadOrGhost(unit)
            if isDead then
                if frame.absorbBar then frame.absorbBar:Hide() end
                if frame.healAbsorbBar then frame.healAbsorbBar:Hide() end
                if frame.healPredictionBar then frame.healPredictionBar:Hide() end
            else
                local maxHP = UnitHealthMax(unit)
                UpdateAbsorbs(frame, unit, maxHP)
                UpdateHealAbsorb(frame, unit, maxHP)
                UpdateHealPrediction(frame, unit, maxHP)
            end

        elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
            local now = GetTime()
            local last = powerThrottle[arg1] or 0
            if (now - last) < THROTTLE_INTERVAL then return end
            powerThrottle[arg1] = now
            UpdatePower(frame)

        elseif event == "UNIT_MAXPOWER" then
            frame._lastMaxPower = nil  -- force SetMinMaxValues refresh
            UpdatePower(frame)

        elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" then
            UpdateAbsorbs(frame)

        elseif event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
            UpdateHealAbsorb(frame)

        elseif event == "UNIT_HEAL_PREDICTION" then
            UpdateHealPrediction(frame)

        elseif event == "UNIT_NAME_UPDATE" then
            UpdateName(frame)

        elseif event == "UNIT_THREAT_SITUATION_UPDATE" then
            UpdateThreat(frame)

        -- UNIT_AURA handled by centralized dispatcher → groupframes_auras.lua

        elseif event == "UNIT_CONNECTION" or event == "UNIT_FLAGS" then
            UpdateConnection(frame)
            UpdateHealth(frame)
            UpdatePower(frame)

        elseif event == "UNIT_IN_RANGE_UPDATE" then
            -- Instant range update from Blizzard (~38yd boundary crossing).
            -- Primary driver for range checks; ticker is a slow fallback.
            local isRaid = frame._isRaid
            local rangeSettings = GetRangeSettings(isRaid)
            if rangeSettings and rangeSettings.enabled ~= false then
                local outAlpha = rangeSettings.outOfRangeAlpha or 0.4
                local inRange = CheckUnitRange(arg1)
                local cached = _range.cache[arg1]
                local isSecret = issecretvalue and (issecretvalue(inRange) or issecretvalue(cached))
                if isSecret or cached ~= inRange then
                    _range.cache[arg1] = inRange
                    local state = GetFrameState(frame)
                    state.outOfRange = true
                    state.inRange = inRange
                    ApplyRangeAlpha(frame, inRange, outAlpha)
                end
                _range.cacheTime[arg1] = GetTime()
            end

        elseif event == "UNIT_PHASE" then
            UpdatePhaseIcon(frame)

        elseif event == "INCOMING_RESURRECT_CHANGED" then
            wipe(_range.cache)
            UpdateResurrection(frame)

        elseif event == "INCOMING_SUMMON_CHANGED" then
            UpdateSummonPending(frame)

        elseif event == "READY_CHECK_CONFIRM" then
            -- READY_CHECK_CONFIRM arg1 is a unit token — dispatch to that frame only.
            -- GetReadyCheckStatus is per-unit, no cross-frame dependency.
            UpdateReadyCheck(frame)
        end
        return
    end  -- end unit event block (type(arg1) == "string")

    -- Non-unit events — check enabled via cached flag
    if not _state.cachedModuleEnabled then return end

    if event == "GROUP_ROSTER_UPDATE" then
        -- Coalesce: show the throttle frame. Multiple GRU events in the same
        -- render frame collapse into one OnUpdate tick (Show on already-shown
        -- frame is a no-op). The heavy work runs once, next frame.
        gruCoalesceFrame:Show()

    elseif event == "PLAYER_TARGET_CHANGED" then
        -- O(1) unhighlight + O(N/2) average find-and-highlight with early exit
        -- (replaces unconditional O(N) UpdateTargetHighlight on all 40 frames)
        local prev = QUI_GF._targetHighlightFrame
        if prev and prev.targetHighlight then
            prev.targetHighlight:Hide()
        end
        QUI_GF._targetHighlightFrame = nil
        for _, frame in pairs(QUI_GF.unitFrameMap) do
            if frame.unit and UnitIsUnit(frame.unit, "target") then
                UpdateTargetHighlight(frame)
                QUI_GF._targetHighlightFrame = frame
                break
            end
        end

    elseif event == "READY_CHECK" or event == "READY_CHECK_CONFIRM" then
        -- QUI pattern: iterate all frames for both events.
        -- READY_CHECK fires with arg1=initiatorName (not a unit token).
        -- READY_CHECK_CONFIRM fires per-unit but we refresh all frames to
        -- avoid relying on unitFrameMap lookup which can miss stale tokens.
        -- Cancel any pending hide timer from a previous ready check
        if event == "READY_CHECK" and QUI_GF._readyCheckHideTimer then
            QUI_GF._readyCheckHideTimer:Cancel()
            QUI_GF._readyCheckHideTimer = nil
        end
        for _, frame in pairs(QUI_GF.unitFrameMap) do
            UpdateReadyCheck(frame)
        end

    elseif event == "READY_CHECK_FINISHED" then
        -- Do NOT call UpdateReadyCheck here — GetReadyCheckStatus returns nil
        -- after READY_CHECK_FINISHED, which would hide icons immediately.
        -- Icons already show the correct state from READY_CHECK_CONFIRM events.
        -- Just schedule hiding after persist delay (QUI pattern).
        -- Single timer hides all icons at once (avoids N closures + N timers).
        if QUI_GF._readyCheckHideTimer then
            QUI_GF._readyCheckHideTimer:Cancel()
        end
        QUI_GF._readyCheckHideTimer = C_Timer.NewTimer(6, function()
            for _, f in pairs(QUI_GF.unitFrameMap) do
                if f.readyCheckIcon then
                    f.readyCheckIcon:Hide()
                end
            end
            QUI_GF._readyCheckHideTimer = nil
        end)

    elseif event == "RAID_TARGET_UPDATE" then
        local inCombat = InCombatLockdown()
        for _, frame in pairs(QUI_GF.unitFrameMap) do
            if inCombat then
                UpdateTargetMarker(frame)
            else
                local marker = frame.unit and GetRaidTargetIndex(frame.unit)
                if marker ~= _state.cachedMarkers[frame.unit] then
                    _state.cachedMarkers[frame.unit] = marker
                    UpdateTargetMarker(frame)
                end
            end
        end

    elseif event == "PARTY_LEADER_CHANGED" then
        for _, frame in pairs(QUI_GF.unitFrameMap) do
            UpdateLeaderIcon(frame)
        end

    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Combat started: clear range cache so stale OOC values
        -- (CheckInteractDistance) don't persist into combat where
        -- that API is unavailable.
        wipe(_range.cache)
        wipe(_range.cacheTime)

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Combat ended: clear range cache so combat-era results
        -- don't prevent OOC methods from updating.
        wipe(_range.cache)
        wipe(_range.cacheTime)
        -- Evict defensive classification cache — auraInstanceIDs are globally
        -- unique per application, so entries accumulate unboundedly during
        -- long encounters. Safe to wipe OOC since new auras get fresh IDs.
        wipe(_defensive.cache)

        -- Process deferred operations
        if _pending.refreshSettings then
            _pending.refreshSettings = false
            -- Full refresh: repositions headers AND reconfigures children.
            -- RefreshSettings deferred during combat because SetAttribute on
            -- SecureGroupHeaders is protected.
            QUI_GF:RefreshSettings()
        elseif _pending.resize then
            _pending.resize = false
            local force = _pending.resizeForce
            _pending.resizeForce = false
            UpdateFrameScaling(force)
        end
        if _pending.visibilityUpdate then
            _pending.visibilityUpdate = false
            UpdateHeaderVisibility()
        end
        if _pending.groupReflow then
            _pending.groupReflow = false
            PositionRaidGroupHeaders()
        end
        if _pending.registerClicks then
            _pending.registerClicks = false
            DecorateHeaderChildren(QUI_GF.headers.party)
            if UseRaidSectionHeaders() then
                for _, header in ipairs(QUI_GF.raidGroupHeaders) do
                    DecorateHeaderChildren(header)
                end
            else
                DecorateHeaderChildren(QUI_GF.headers.raid)
            end
            -- Re-register click-casting for frames that were decorated during
            -- combat but missed click-cast setup (SetupFrameClickCast bails
            -- out during InCombatLockdown — the frame is marked _quiDecorated
            -- but never got its secure click attributes applied).
            local GFCC = ns.QUI_GroupFrameClickCast
            if GFCC and GFCC:IsEnabled() then
                GFCC:RegisterAllFrames()
            end
        end
        if _pending.anchorUpdate then
            _pending.anchorUpdate = false
            UpdateAnchorFrames()
        end
        if pendingAnchorUpdate then
            pendingAnchorUpdate = false
            UpdateAnchorFrames()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0.5, function()
            UpdateHeaderVisibility()
            UpdateFrameScaling(true)
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
    eventFrame:RegisterEvent("UNIT_MAXPOWER")
    eventFrame:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
    eventFrame:RegisterEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
    eventFrame:RegisterEvent("UNIT_HEAL_PREDICTION")
    eventFrame:RegisterEvent("UNIT_NAME_UPDATE")
    eventFrame:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    -- UNIT_AURA handled by centralized dispatcher (core/aura_events.lua)
    eventFrame:RegisterEvent("UNIT_CONNECTION")
    eventFrame:RegisterEvent("UNIT_FLAGS")
    eventFrame:RegisterEvent("UNIT_PHASE")
    eventFrame:RegisterEvent("INCOMING_RESURRECT_CHANGED")
    eventFrame:RegisterEvent("INCOMING_SUMMON_CHANGED")

    -- Range event (instant ~38yd boundary crossing, supplements ticker polling)
    eventFrame:RegisterEvent("UNIT_IN_RANGE_UPDATE")

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
-- SELECTIVE EVENT REGISTRATION: Unregister noisy events when their
-- corresponding visual feature is disabled, reducing wasted Lua dispatch.
---------------------------------------------------------------------------
UpdateSelectiveEvents = function()
    local db = GetSettings()
    local mode = GetGroupMode()
    local isRaid = (mode ~= "party")

    -- Power events: unregister in large raids when power bar hidden
    local powerSettings = GetPowerSettings(isRaid)
    if mode == "large" and (not powerSettings or powerSettings.showPowerBar == false) then
        eventFrame:UnregisterEvent("UNIT_POWER_UPDATE")
        eventFrame:UnregisterEvent("UNIT_POWER_FREQUENT")
        eventFrame:UnregisterEvent("UNIT_MAXPOWER")
    else
        eventFrame:RegisterEvent("UNIT_POWER_UPDATE")
        eventFrame:RegisterEvent("UNIT_MAXPOWER")
    end

    -- Threat events: UNIT_THREAT_SITUATION_UPDATE fires for ALL units in the
    -- game world (not just group members) because it uses global RegisterEvent.
    -- When threat borders are disabled, unregister to avoid ~100s of wasted
    -- dispatches per second in raids with many adds.
    local partyInd = GetIndicatorSettings(false)
    local raidInd = GetIndicatorSettings(true)
    local partyThreat = partyInd and partyInd.showThreatBorder ~= false
    local raidThreat = raidInd and raidInd.showThreatBorder ~= false
    if partyThreat or raidThreat then
        eventFrame:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    else
        eventFrame:UnregisterEvent("UNIT_THREAT_SITUATION_UPDATE")
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

function QUI_GF:RefreshHealth(frame)
    UpdateHealth(frame)
end

---------------------------------------------------------------------------
-- REFRESH ALL: Update all visible frames
---------------------------------------------------------------------------
function QUI_GF:RefreshAllFrames()
    -- Pre-loop setup that each module's RefreshAll does once before iteration.
    -- Inlining per-frame work from auras + indicators avoids 2 extra full
    -- iterations of unitFrameMap (was 4 passes, now 1 + private auras).
    local GFA = ns.QUI_GroupFrameAuras
    if GFA and GFA.InvalidateLayout then GFA:InvalidateLayout() end
    local GFI = ns.QUI_GroupFrameIndicators

    for _, frame in pairs(self.unitFrameMap) do
        if frame and frame:IsShown() then
            if frame.healthBar then ApplyStatusBarTexture(frame.healthBar) end
            if frame.healPredictionBar then ApplyStatusBarTexture(frame.healPredictionBar) end
            if frame.powerBar then ApplyStatusBarTexture(frame.powerBar) end
            UpdateFrame(frame)

            -- Auras: scan + render (was a separate full iteration)
            if GFA and GFA.RefreshFrame then GFA:RefreshFrame(frame) end
            -- Indicators: update tracked spells (was a separate full iteration)
            if GFI and GFI.RefreshFrame then GFI:RefreshFrame(frame) end
        end
    end

    -- Private auras use a different clear-all + rebuild pattern that can't
    -- be inlined into the per-frame loop (needs wipe(frameState) first).
    if ns.QUI_GroupFramePrivateAuras and ns.QUI_GroupFramePrivateAuras.RefreshAll then
        ns.QUI_GroupFramePrivateAuras:RefreshAll()
    end

    -- Party Tracker modules
    local ptCCIcons = ns.PartyTracker_CCIcons
    if ptCCIcons and ptCCIcons.RefreshAll then ptCCIcons.RefreshAll() end
    local ptKickTimer = ns.PartyTracker_KickTimer
    if ptKickTimer and ptKickTimer.RefreshAll then ptKickTimer.RefreshAll() end
    local ptCDDisplay = ns.PartyTracker_CooldownDisplay
    if ptCDDisplay and ptCDDisplay.RefreshAll then ptCDDisplay.RefreshAll() end
end

---------------------------------------------------------------------------
-- REFRESH: Settings changed (called from options panel)
---------------------------------------------------------------------------
function QUI_GF:RefreshSettings()
    InvalidateCache()
    RefreshCachedEnabled()
    _dispel.colorCurve = nil  -- Rebuild with new opacity on next use

    if not self.initialized then
        return
    end

    local db = GetSettings()
    if not db or not db.enabled then
        self:Disable()
        return
    end

    if InCombatLockdown() and not _state.inInitSafeWindow then
        _pending.refreshSettings = true
        return
    end

    -- Restore root frame positions from the (possibly new) profile DB.
    -- Prefer frameAnchoring positions; fall back to legacy db.position.
    -- Position the ROOT frames (not headers) — UpdateAnchorRoot handles
    -- internal header layout within each root.
    -- Skip repositioning when the anchoring override system owns the frame.
    local faDB = QUI.db and QUI.db.profile and QUI.db.profile.frameAnchoring
    local partyRoot = self.anchorFrames and self.anchorFrames.party
    if partyRoot and not (_G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("partyFrames")) then
        local faParty = faDB and faDB.partyFrames
        partyRoot:ClearAllPoints()
        if faParty and faParty.point then
            partyRoot:SetPoint(faParty.point, UIParent, faParty.relative or faParty.point, faParty.offsetX or 0, faParty.offsetY or 0)
        else
            local position = db.position
            local offsetX = position and position.offsetX or -400
            local offsetY = position and position.offsetY or 0
            partyRoot:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
        end
    end
    local raidRoot = self.anchorFrames and self.anchorFrames.raid
    if raidRoot and not (_G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("raidFrames")) then
        local faRaid = faDB and faDB.raidFrames
        raidRoot:ClearAllPoints()
        if faRaid and faRaid.point then
            raidRoot:SetPoint(faRaid.point, UIParent, faRaid.relative or faRaid.point, faRaid.offsetX or 0, faRaid.offsetY or 0)
        else
            local raidPos = db.raidPosition
            local raidOffX = raidPos and raidPos.offsetX or -400
            local raidOffY = raidPos and raidPos.offsetY or 0
            raidRoot:SetPoint("CENTER", UIParent, "CENTER", raidOffX, raidOffY)
        end
    end

    -- Re-configure headers
    if self.headers.party then ConfigurePartyHeader(self.headers.party) end
    if UseRaidSectionHeaders(db) then
        ConfigureRaidGroupHeaders()
    else
        if self.headers.raid then ConfigureRaidHeader(self.headers.raid) end
    end
    -- Self header uses party settings; re-apply self-first visibility
    if self.headers.self then
        local partySelfFirst = GetPartySelfFirst(db)
        self.headers.self:SetAttribute("showSolo", partySelfFirst and true or false)
    end

    -- Force re-decoration of all children
    for _, frame in pairs(self.allFrames) do
        frame._quiDecorated = false
    end
    wipe(self.allFrames)

    -- Also clear decorated flag on header children directly
    local function ClearDecoratedFlags(header)
        if not header then return end
        local i = 1
        while true do
            local child = header:GetAttribute("child" .. i)
            if not child then break end
            child._quiDecorated = false
            i = i + 1
        end
    end
    for _, headerKey in ipairs({"party", "raid", "self"}) do
        ClearDecoratedFlags(self.headers[headerKey])
    end
    for _, header in ipairs(self.raidGroupHeaders) do
        ClearDecoratedFlags(header)
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
        for _, headerKey in ipairs({"party", "raid", "self"}) do
            local header = QUI_GF.headers[headerKey]
            if header then
                pcall(header.SetFrameLevel, header, frameLevel)
            end
        end
        for _, header in ipairs(QUI_GF.raidGroupHeaders) do
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

    -- ADDON_LOADED safe window: protected calls are allowed even though
    -- InCombatLockdown() returns true during a combat /reload.
    _state.inInitSafeWindow = true
    _state.initialLayoutDone = false

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
    RefreshCachedEnabled()

    -- Initialize click-casting
    local GFCC = ns.QUI_GroupFrameClickCast
    if GFCC then
        GFCC:Initialize()
        -- Group frames were pre-created before GFCC was initialized,
        -- so they missed registration — catch up now.
        if GFCC:IsEnabled() then
            GFCC:RegisterAllFrames()
        end
    end

    -- Hide Blizzard group frames
    if ns.QUI_GroupFrameBlizzard and ns.QUI_GroupFrameBlizzard.HideBlizzardFrames then
        ns.QUI_GroupFrameBlizzard:HideBlizzardFrames()
    end

    _state.inInitSafeWindow = false
end

---------------------------------------------------------------------------
-- DISABLE
---------------------------------------------------------------------------
function QUI_GF:Disable()
    _state.cachedModuleEnabled = false
    _state.cachedModuleDB = nil
    UnregisterEvents()
    StopRangeCheck()

    if InCombatLockdown() then return end

    for _, headerKey in ipairs({"party", "raid", "self"}) do
        local header = self.headers[headerKey]
        if header then
            header:Hide()
        end
    end
    for _, header in ipairs(self.raidGroupHeaders) do
        if header then header:Hide() end
    end

    for _, proxy in pairs(self.anchorFrames) do
        proxy:Hide()
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
-- STARTUP: Init on ADDON_LOADED
---------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")

initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        self:UnregisterEvent("ADDON_LOADED")
        QUI_GF:Initialize()
    end
end)

---------------------------------------------------------------------------
-- PUBLIC API (for other modules)
---------------------------------------------------------------------------

function QUI_GF:GetAnchorFrame(frameType)
    if self.editMode or self.testMode then
        return nil
    end
    local frame = self.anchorFrames and self.anchorFrames[frameType]
    if frame and frame:IsShown() then
        return frame
    end
    return nil
end

function QUI_GF:UpdateAnchorFrames()
    UpdateAnchorFrames()
end

function QUI_GF:IsEnabled()
    local db = GetSettings()
    return db and db.enabled
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

if ns.Registry then
    ns.Registry:Register("groupframes", {
        refresh = _G.QUI_RefreshGroupFrames,
        priority = 20,
        group = "frames",
        importCategories = { "groupFrames" },
    })
end
