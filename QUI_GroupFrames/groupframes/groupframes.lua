local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local LSM = ns.LSM
local Helpers = ns.Helpers
local Chrome = ns.QUI_GroupFrameChrome
local IsSecretValue = Helpers.IsSecretValue
local SafeValue = Helpers.SafeValue
local SafeToNumber = Helpers.SafeToNumber
local issecretvalue = _G.issecretvalue
local GetDB = Helpers.CreateDBGetter("quiGroupFrames")

local GetCore = Helpers.GetCore

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
local math_ceil = math.ceil

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
local UnitIsGhost = UnitIsGhost
local UnitGUID = UnitGUID
local GetNumGroupMembers = GetNumGroupMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local RAID_CLASS_COLORS = RAID_CLASS_COLORS

local _state = {
    inInitSafeWindow = false,
    gruDeferredPending = false,
    cachedVDB_party = nil,
    cachedVDB_raid = nil,
    cachedModuleEnabled = false,
    lastMode = nil,
    rangeCheckTicker = nil,
    unitGuidCache = {},
    cachedMarkers = {},
    lastGroupRosterUpdateTime = 0,
    raidRosterSortCache = {},
    unitEventRegistrationEnabled = false,
    unitEventFrames = {},
    unitEventRegistered = {},
    rangeListenerFrames = {},
    healAbsorbThrottle = {},
    healthThrottle = {},
    unitEventActive = {
        UNIT_HEALTH = true,
        UNIT_MAXHEALTH = true,
        UNIT_POWER_UPDATE = true,
        UNIT_MAXPOWER = true,
        UNIT_ABSORB_AMOUNT_CHANGED = true,
        UNIT_HEAL_ABSORB_AMOUNT_CHANGED = true,
        UNIT_HEAL_PREDICTION = true,
        UNIT_NAME_UPDATE = true,
        UNIT_LEVEL = true,
        UNIT_CONNECTION = true,
    },
    unitEventList = {
        "UNIT_HEALTH",
        "UNIT_MAXHEALTH",
        "UNIT_POWER_UPDATE",
        "UNIT_POWER_FREQUENT",
        "UNIT_MAXPOWER",
        "UNIT_ABSORB_AMOUNT_CHANGED",
        "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
        "UNIT_HEAL_PREDICTION",
        "UNIT_NAME_UPDATE",
        "UNIT_LEVEL",
        "UNIT_CONNECTION",
    },
    defaultColors = ns.QUI_GroupFrameChrome.DEFAULT_COLORS,
    backdropReapplyInterval = 0.5,
}

local QUI_GF = {}
ns.QUI_GroupFrames = QUI_GF
_G.QUI_GroupFrames = QUI_GF

QUI_GF.headers = {}
QUI_GF.raidGroupHeaders = {}
QUI_GF.anchorFrames = {}
QUI_GF.petHeader = nil
QUI_GF.spotlightHeader = nil
QUI_GF.spotlightContainer = nil
QUI_GF.allFrames = {}
QUI_GF.unitFrameMap = {}
QUI_GF.initialized = false
QUI_GF.testMode = false
QUI_GF.editMode = false

local function AddFrameToMap(unit, frame)
    if not unit or not frame then return end
    local list = QUI_GF.unitFrameMap[unit]
    if list then
        for i = 1, #list do
            if list[i] == frame then return end
        end
        list[#list + 1] = frame
    else
        QUI_GF.unitFrameMap[unit] = { frame }
        if _state.RegisterUnitEventsForUnit then
            _state.RegisterUnitEventsForUnit(unit)
        end
    end
end

local function RemoveFrameFromMap(unit, frame)
    if not unit or not frame then return end
    local list = QUI_GF.unitFrameMap[unit]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == frame then
            table.remove(list, i)
        end
    end
    if #list == 0 then
        QUI_GF.unitFrameMap[unit] = nil
        if _state.UnregisterUnitEventsForUnit then
            _state.UnregisterUnitEventsForUnit(unit)
        end
    end
end

QUI_GF.AddFrameToMap = AddFrameToMap
QUI_GF.RemoveFrameFromMap = RemoveFrameFromMap

local frameState, GetFrameState = Helpers.CreateStateTable()

function QUI_GF.GetFrameUnit(frame)
    if not frame then return nil end
    local state = frameState[frame]
    if state and state.groupUnit then return state.groupUnit end
    return frame.previewUnit
end

function QUI_GF.SetFrameUnit(frame, unit)
    if not frame then return end
    GetFrameState(frame).groupUnit = unit
end

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

local powerThrottle = {}
local absorbThrottle = {}
local healPredThrottle = {}
local THROTTLE_INTERVAL = 0.1

ns.QUI_GroupFrameIconLayout.HEADER_INIT_CONFIG_FUNC = [[
        local header = self:GetParent()
        local w = header:GetAttribute("_initialAttribute-unit-width") or 200
        local h = header:GetAttribute("_initialAttribute-unit-height") or 40
        self:SetWidth(w)
        self:SetHeight(h)
        self:SetAttribute("*type1", "target")
        self:SetAttribute("*type2", "togglemenu")
        RegisterUnitWatch(self)
        self:GetParent():CallMethod("QUI_OnChildCreated", self:GetName())
    ]]

local GetCachedBackdrop    = Chrome.GetCachedBackdrop
local EnsureBackdrop       = Chrome.EnsureBackdrop
local SetBackdropFillColor = Chrome.SetBackdropFillColor

local gruCoalesceFrame = CreateFrame("Frame")
gruCoalesceFrame:Hide()

local COLORS = {
    BLACK   = { 0, 0, 0, 1 },
    WHITE   = { 1, 1, 1, 1 },
    DEAD    = { 0.5, 0.5, 0.5, 1 },
    OFFLINE = { 0.4, 0.4, 0.4, 1 },
    GHOST   = { 0.6, 0.6, 0.6, 1 },
}

local _dispel = {
    defaultColors = ns.QUI_GroupFrameIconLayout.DISPEL_DEFAULT_COLORS,
    allEnums = {1, 2, 3, 4, 9, 11},
    enumNames = {
        [1] = "Magic", [2] = "Curse", [3] = "Disease", [4] = "Poison",
        [9] = "Bleed", [11] = "Bleed",
    },
    colorCurves = {},
    gradientCurves = {},
    iconCurves = {},
    cachedColors = {},
    auraBorderCurves = {},
    borderKeys = {"borderTop", "borderBottom", "borderLeft", "borderRight"},
}

local GetDispelColors
local InvalidateDispelColors
local UpdateSelectiveEvents
local UpdateDarkModeVisuals

local function DispelContextKey(isRaid)
    return isRaid and "raid" or "party"
end

local function GetDispelColorCurve(isRaid, opacity)
    local key = DispelContextKey(isRaid)
    if _dispel.colorCurves[key] then return _dispel.colorCurves[key] end
    if not C_CurveUtil or not C_CurveUtil.CreateColorCurve then return nil end
    local colors = GetDispelColors(isRaid)
    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    curve:AddPoint(0, CreateColor(0, 0, 0, 0))
    for _, enumVal in ipairs(_dispel.allEnums) do
        local typeName = _dispel.enumNames[enumVal]
        local c = typeName and colors[typeName]
        if c then
            curve:AddPoint(enumVal, CreateColor(c[1], c[2], c[3], opacity or 0.8))
        end
    end
    _dispel.colorCurves[key] = curve
    return curve
end

-- Like GetDispelColorCurve but at full alpha: the awareness gradient's
-- strength is the texture's own alpha ramp times gradientOpacity, so the
-- curve only supplies the type color. Lives on _dispel rather than a local:
-- this chunk is at Lua's 200-local ceiling.
function _dispel.GetGradientCurve(isRaid)
    local key = DispelContextKey(isRaid)
    if _dispel.gradientCurves[key] then return _dispel.gradientCurves[key] end
    if not C_CurveUtil or not C_CurveUtil.CreateColorCurve then return nil end
    local colors = GetDispelColors(isRaid)
    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    curve:AddPoint(0, CreateColor(0, 0, 0, 0))
    for _, enumVal in ipairs(_dispel.allEnums) do
        local typeName = _dispel.enumNames[enumVal]
        local c = typeName and colors[typeName]
        if c then
            curve:AddPoint(enumVal, CreateColor(c[1], c[2], c[3], 1))
        end
    end
    _dispel.gradientCurves[key] = curve
    return curve
end

local POWER_COLORS = {
    [0]  = { 0, 0.50, 1 },
    [1]  = { 1, 0, 0 },
    [2]  = { 1, 0.5, 0.25 },
    [3]  = { 1, 1, 0 },
    [6]  = { 0, 0.82, 1 },
    [8]  = { 0.3, 0.52, 0.9 },
    [11] = { 0, 0.5, 1 },
    [13] = { 0.4, 0, 0.8 },
    [17] = { 0.79, 0.26, 0.99 },
    [18] = { 1, 0.61, 0 },
}

local ROLE_SORT_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3, NONE = 4 }

local function IsNPCPartyMember(unit)
    return UnitExists(unit) and not UnitIsPlayer(unit)
end

local _pending = {
    resize = false,
    resizeForce = false,
    refreshSettings = false,
    visibilityUpdate = false,
    registerClicks = false,
    groupReflow = false,
    anchorUpdate = false,
    markerUpdate = false,
    initSafe = true,
}

local function IsMultiHeaderMode()
    local db = GetDB()
    if not db then return false end
    local raidVdb = db.raid or db
    local raidLayout = raidVdb and raidVdb.layout
    local groupBy = raidLayout and raidLayout.groupBy or "GROUP"
    return groupBy == "GROUP"
end

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

-- Hidden players: user-maintained name list (db.hiddenPlayers) whose frames
-- are removed from the party/raid headers entirely. The secure header only
-- has include-filters (nameList/groupFilter/roleFilter), so exclusion is
-- expressed by computing include-lists that omit these names. Parse result
-- is cached on the raw string so roster-burst callers don't re-split.
do  -- do-block: keeps the cache upvalues off the main chunk's 200-local budget
    local cacheKey, cacheSet
    _state.GetHiddenPlayerSet = function(db)
        db = db or GetSettings()
        local raw = db and db.hiddenPlayers
        if type(raw) ~= "string" or raw == "" then return nil end
        if raw ~= cacheKey then
            cacheKey = raw
            cacheSet = Helpers.ParseNameListString(raw)
        end
        return cacheSet
    end
end

local function UseRaidSectionHeaders(db)
    db = db or GetSettings()
    if not db then return false end
    local raidVdb = db.raid or db
    local layout = raidVdb and raidVdb.layout
    return IsMultiHeaderMode()
        or GetRaidSelfFirst(db)
        or (layout and layout.limitGroupsByRaidSize == true)
        -- Hidden players need computed nameLists in every raid mode, so the
        -- single groupFilter-driven raid header can't be used.
        or _state.GetHiddenPlayerSet(db) ~= nil
end

_state.UseRaidNameListSections = function(db, layout)
    db = db or GetSettings()
    if not layout and db then
        local raidVdb = db.raid or db
        layout = raidVdb and raidVdb.layout
    end
    if GetRaidSelfFirst(db) then
        return true
    end
    -- A non-empty hidden-players list forces nameList sections: every raid
    -- section header is driven from a computed nameList and
    -- GetRaidDisplaySections skips the hidden names.
    if _state.GetHiddenPlayerSet(db) ~= nil then
        return true
    end
    return layout
        and layout.limitGroupsByRaidSize == true
        and (layout.groupBy or "GROUP") ~= "GROUP"
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

_state.GetRaidGroupLimit = function(layout)
    if not layout or layout.limitGroupsByRaidSize ~= true then
        return 8
    end

    local difficultyID = _G.GetInstanceInfo and select(3, _G.GetInstanceInfo())
    return difficultyID == 16 and 4 or 6
end

_state.GetRaidGroupFilterString = function(layout)
    local limit = _state.GetRaidGroupLimit(layout)
    if limit == 4 then
        return "1,2,3,4"
    elseif limit == 6 then
        return "1,2,3,4,5,6"
    end
    return "1,2,3,4,5,6,7,8"
end

_state.IsRaidSubgroupAllowed = function(subgroup, layout)
    local limit = _state.GetRaidGroupLimit(layout)
    if limit >= 8 then
        return true
    end
    subgroup = tonumber(subgroup)
    return subgroup ~= nil and subgroup >= 1 and subgroup <= limit
end

local function GetRaidColumnAnchorPoint(layout, grow)
    local horizontal = (grow == "LEFT" or grow == "RIGHT")
    if horizontal then
        return "TOP"
    end

    local groupGrow = layout and layout.groupGrowDirection
    if groupGrow == "LEFT" then
        return "RIGHT"
    end
    return "LEFT"
end

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

GetDispelColors = function(isRaid)
    local key = DispelContextKey(isRaid)
    if _dispel.cachedColors[key] then return _dispel.cachedColors[key] end
    local hs = GetHealerSettings(isRaid)
    local dbColors = hs and hs.dispelOverlay and hs.dispelOverlay.colors
    if not dbColors then
        _dispel.cachedColors[key] = _dispel.defaultColors
        return _dispel.defaultColors
    end
    _dispel.cachedColors[key] = {
        Magic   = dbColors.Magic   or _dispel.defaultColors.Magic,
        Curse   = dbColors.Curse   or _dispel.defaultColors.Curse,
        Disease = dbColors.Disease or _dispel.defaultColors.Disease,
        Poison  = dbColors.Poison  or _dispel.defaultColors.Poison,
        Bleed   = dbColors.Bleed   or _dispel.defaultColors.Bleed,
    }
    return _dispel.cachedColors[key]
end

InvalidateDispelColors = function()
    _dispel.cachedColors = {}
    _dispel.colorCurves = {}
    _dispel.gradientCurves = {}
    _dispel.auraBorderCurves = {}
end

-- >>> QUI_TEST_EXTRACT GetAuraBorderColorCurve (sentinel used by
ns.QUI_GroupFrameAuraBorderCurve = function(isRaid)
    local vdb = GetVisualDB(isRaid)
    local auras = vdb and vdb.auras
    if not auras or auras.debuffBorderByType ~= true then return nil end
    local key = isRaid and "raid" or "party"
    if _dispel.auraBorderCurves[key] then return _dispel.auraBorderCurves[key] end
    if not C_CurveUtil or not C_CurveUtil.CreateColorCurve then return nil end
    local colors = GetDispelColors(isRaid)
    local sr, sg, sb, sa = 0, 0, 0, 1
    if ns.Helpers and ns.Helpers.GetSkinBorderColor then
        sr, sg, sb, sa = ns.Helpers.GetSkinBorderColor()
    end
    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    curve:AddPoint(0, CreateColor(sr, sg, sb, sa))
    for _, enumVal in ipairs(_dispel.allEnums) do
        local typeName = _dispel.enumNames[enumVal]
        local c = typeName and colors[typeName]
        if c then
            curve:AddPoint(enumVal, CreateColor(c[1], c[2], c[3], 1))
        end
    end
    _dispel.auraBorderCurves[key] = curve
    return curve
end
-- <<< QUI_TEST_EXTRACT GetAuraBorderColorCurve

local function GetRangeSettings(isRaid)
    local vdb = GetVisualDB(isRaid)
    return vdb and vdb.range
end

local function GetPortraitSettings(isRaid)
    local vdb = GetVisualDB(isRaid)
    return vdb and vdb.portrait
end

local function GetFontPath(isRaid)
    return Chrome.FontPath(GetGeneralSettings(isRaid))
end

local function GetFontOutline(isRaid)
    return Chrome.FontOutline(GetGeneralSettings(isRaid))
end

local function GetTexturePath(textureName, isRaid)
    return Chrome.TexturePath(textureName, GetGeneralSettings(isRaid))
end

local function ApplyStatusBarTexture(statusBar, textureName, isRaid)
    return Chrome.ApplyStatusBarTexture(statusBar, textureName, GetGeneralSettings(isRaid))
end

-- it from there via the QUI_TEST_EXTRACT sentinel.
local ApplyOverlayBar = Chrome.ApplyOverlayBar
local function InvalidateCache()
    Chrome.InvalidateAssetCache()
    _state.cachedVDB_party = nil
    _state.cachedVDB_raid = nil
    InvalidateDispelColors()
end

local GetTextAnchorInfo = Chrome.TextAnchorInfo

function _state.FormatLevelText(unit)
    local ok, text = pcall(function()
        local level = UnitLevel(unit)
        if not level then return "" end
        if level < 0 then return "??" end
        if level == 0 then return "" end
        return tostring(level)
    end)
    return ok and text or ""
end

function _state.UpdateLevelText(frame)
    if not frame or not frame.levelText then return end
    local unit = QUI_GF.GetFrameUnit(frame)
    if not unit then return end

    local nameSettings = GetNameSettings(frame._isRaid)
    if not nameSettings or nameSettings.showLevel ~= true then
        frame.levelText:SetText("")
        frame.levelText:Hide()
        return
    end

    if not UnitExists(unit) then
        frame.levelText:SetText("")
        frame.levelText:Hide()
        return
    end

    local text = _state.FormatLevelText(unit)
    if text == "" then
        frame.levelText:SetText("")
        frame.levelText:Hide()
        return
    end

    frame.levelText:SetText(text)
    local tc = nameSettings.levelTextColor or COLORS.WHITE
    frame.levelText:SetTextColor(tc[1] or 1, tc[2] or 1, tc[3] or 1, tc[4] or 1)
    frame.levelText:Show()
end

local function GetHealthPct(unit)
    return UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
end

local function GetGroupSize()
    if IsInGroup() then
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
    return Chrome.FrameDimensions(GetVisualDB(isRaid), mode)
end

local function CalculateHeaderSize(db, memberCount)
    if not db or not memberCount or memberCount <= 0 then return 100, 40 end

    local isRaid = memberCount > 5
    local vdb = isRaid and (db.raid or db) or (db.party or db)
    local layout = vdb.layout or (isRaid and db.raidLayout or db.partyLayout) or db.layout
    local spacing = layout and layout.spacing or 2
    local groupSpacing = layout and layout.groupSpacing or 10
    local grow = GetLayoutGrowDirection(layout, "DOWN")

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

QUI_GF.GetVisualDB = GetVisualDB
QUI_GF.CalculateHeaderSize = CalculateHeaderSize

local function ShowUnitTooltip(frame)
    local general = GetGeneralSettings(frame._isRaid)
    if not general or general.showTooltips == false then return end
    local unit = QUI_GF.GetFrameUnit(frame)
    if not unit or not UnitExists(unit) then return end
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:SetUnit(unit)
    GameTooltip:Show()
end

local function HideUnitTooltip()
    local t = _state._tooltipTimer
    if t then t:Cancel(); _state._tooltipTimer = nil end
    _state._tooltipPending = nil
    GameTooltip:Hide()
end

local function GetHealthBarColor(unit, isRaid)
    local general = GetGeneralSettings(isRaid)
    if general and general.darkMode then
        local c = general.darkModeHealthColor or _state.defaultColors.darkHealth
        return c[1], c[2], c[3], c[4] or 1
    end

    if general and general.useClassColor ~= false then
        local _, class = UnitClass(unit)
        -- @secret-policy: collapse-only — fallback color below
        if IsSecretValue(class) then class = nil end
        if class then
            local cc = RAID_CLASS_COLORS[class]
            if cc then
                return cc.r, cc.g, cc.b, 1
            end
        end
    end

    local c = general and general.healthBarColor
    if c then
        return c[1], c[2], c[3], c[4] or 1
    end
    return 0.2, 0.8, 0.2, 1
end

local function GetPowerBarColor(unit, isRaid)
    local db = GetPowerSettings(isRaid)
    if db and not db.powerBarUsePowerColor then
        local c = db.powerBarColor or _state.defaultColors.powerBar
        return c[1], c[2], c[3], c[4] or 1
    end

    local powerType = UnitPowerType(unit)
    if powerType then
        local c = POWER_COLORS[powerType]
        if c then return c[1], c[2], c[3], 1 end
    end
    return 0, 0.5, 1, 1
end

local function NormalizeUnitFlag(value, fallback)
    if IsSecretValue(value) then
        return fallback or false
    end
    return value and true or false
end

local function GetUnitLifeState(unit)
    local isConnected = NormalizeUnitFlag(UnitIsConnected(unit), true)
    if not isConnected and IsNPCPartyMember(unit) then
        isConnected = true
    end

    local isDeadOrGhost = NormalizeUnitFlag(UnitIsDeadOrGhost(unit), false)
    local isGhost = false
    if isDeadOrGhost then
        isGhost = NormalizeUnitFlag(UnitIsGhost(unit), false)
    end

    return isConnected, isDeadOrGhost, isGhost
end

local function UpdateHealth(frame)
    if not frame then return end
    local unit = QUI_GF.GetFrameUnit(frame)
    if not unit then return end

    local Feeder = ns.QUI_GFDispelFeeder

    if not UnitExists(unit) then
        if frame.healthBar then frame.healthBar:SetValue(0) end
        local Render = ns.QUI_GroupFrameAuraRender
        if Render and Render.SyncHealthBarTint then
            Render:SyncHealthBarTint(frame, 0, false)
        end
        if frame.healthText then frame.healthText:SetText("") end
        if Feeder and Feeder.SetLifeGate then Feeder.SetLifeGate(frame, false) end
        return
    end

    UpdateDarkModeVisuals(frame)

    local isConnected, isDeadOrGhost, isGhost = GetUnitLifeState(unit)

    -- Legacy dispel-overlay parity: dead/ghost units wear no dispel visuals.
    -- Aura presence itself stays engine-driven inside the feeder slots.
    if Feeder and Feeder.SetLifeGate then
        Feeder.SetLifeGate(frame, not isDeadOrGhost)
    end

    if frame.healthBar then
        local healthPct = 0
        if isDeadOrGhost then
            frame.healthBar:SetValue(0)
        else
            healthPct = GetHealthPct(unit)
            frame.healthBar:SetValue(healthPct)
        end

        local r, g, b, a
        if not isConnected then
            r, g, b, a = COLORS.OFFLINE[1], COLORS.OFFLINE[2], COLORS.OFFLINE[3], COLORS.OFFLINE[4]
        elseif isDeadOrGhost then
            r, g, b, a = COLORS.DEAD[1], COLORS.DEAD[2], COLORS.DEAD[3], COLORS.DEAD[4]
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

        local Render = ns.QUI_GroupFrameAuraRender
        if Render and Render.SyncHealthBarTint then
            Render:SyncHealthBarTint(frame, healthPct, isConnected and not isDeadOrGhost) -- @secret-safe: SyncHealthBarTint and StartHealthTintAnimation probe IsSecretValue before any truth-test on healthPct and forward the opaque value to the SetValue sink (round-13 hand-audit)
        end
    end

    if frame.statusText then
        local statusKey
        if not isConnected then statusKey = 1
        elseif isDeadOrGhost then statusKey = isGhost and 3 or 2
        else statusKey = 0 end

        if statusKey ~= frame._lastStatusKey then
            frame._lastStatusKey = statusKey
            local state = GetFrameState(frame)
            if statusKey == 1 then
                frame.statusText:SetText(ns.L["OFFLINE"])
                frame.statusText:SetTextColor(COLORS.OFFLINE[1], COLORS.OFFLINE[2], COLORS.OFFLINE[3])
                frame.statusText:Show()
                state.lifeFaded = true
            elseif statusKey == 2 or statusKey == 3 then
                frame.statusText:SetText(statusKey == 3 and ns.L["GHOST"] or ns.L["DEAD"])
                frame.statusText:SetTextColor(COLORS.DEAD[1], COLORS.DEAD[2], COLORS.DEAD[3])
                frame.statusText:Show()
                state.lifeFaded = true
                frame:SetAlpha(0.65)
            else
                frame.statusText:Hide()
                if state.lifeFaded then
                    _state.ReleaseLifeFade(frame, unit)
                end
            end
        end
    end

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
            local ok
            if style == "percent" then
                local pct = GetHealthPct(unit)
                ok = ns.SafeCallMethod("sink-forward", frame.healthText, "SetFormattedText", pctFmt, pct)
            elseif style == "absolute" then
                local hp = UnitHealth(unit, true)
                if abbr then
                    ok = ns.SafeCallMethod("sink-forward", frame.healthText, "SetText", abbr(hp))
                else
                    ok = ns.SafeCallMethod("sink-forward", frame.healthText, "SetFormattedText", "%s", hp)
                end
            elseif style == "both" then
                local hp = UnitHealth(unit, true)
                local pct = GetHealthPct(unit)
                local bothFmt = healthSettings.hideHealthPercentSymbol and "%s | %.0f" or "%s | %.0f%%"
                if abbr then
                    ok = ns.SafeCallMethod("sink-forward", frame.healthText, "SetFormattedText", bothFmt, abbr(hp), pct)
                else
                    ok = ns.SafeCallMethod("sink-forward", frame.healthText, "SetFormattedText", bothFmt, hp, pct)
                end
            elseif style == "deficit" then
                local miss = UnitHealthMissing(unit, true)
                if IsSecretValue(miss) then
                    ok = ns.SafeCallMethod("sink-forward", frame.healthText, "SetFormattedText", "-%s", miss)
                elseif C_StringUtil and C_StringUtil.TruncateWhenZero and C_StringUtil.WrapString then
                    local truncated = C_StringUtil.TruncateWhenZero(miss)
                    local result = C_StringUtil.WrapString(truncated, "-")
                    ok = ns.SafeCallMethod("sink-forward", frame.healthText, "SetText", result)
                elseif abbr then
                    ok = ns.SafeCallMethod("sink-forward", frame.healthText, "SetFormattedText", "-%s", abbr(miss))
                else
                    ok = ns.SafeCallMethod("sink-forward", frame.healthText, "SetFormattedText", "-%s", miss)
                end
            else
                local pct = GetHealthPct(unit)
                ok = ns.SafeCallMethod("sink-forward", frame.healthText, "SetFormattedText", pctFmt, pct)
            end
            if not ok then
                frame.healthText:SetText("")
            end
            local tc = healthSettings.healthTextColor or COLORS.WHITE
            frame.healthText:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
        end
    elseif frame.healthText then
        frame.healthText:SetText("")
    end
end

local function ShouldShowPowerForUnit(unit, isRaid)
    local ps = GetPowerSettings(isRaid)
    if not ps then return true end
    if ps.showPowerBar == false then return false end
    local onlyHealers = ps.powerBarOnlyHealers
    local onlyTanks = ps.powerBarOnlyTanks
    if not onlyHealers and not onlyTanks then return true end
    local role = UnitGroupRolesAssigned(unit)
    if onlyHealers and role == "HEALER" then return true end
    if onlyTanks and role == "TANK" then return true end
    return false
end

local function ResizeHealthForPower(frame, showPowerForUnit)
    Chrome.ResizeHealthForPower(frame, GetVisualDB(frame._isRaid), showPowerForUnit, GetFrameState(frame))
end

local function UpdatePower(frame)
    if not frame or not frame.powerBar then return end
    local unit = QUI_GF.GetFrameUnit(frame)
    if not unit then return end

    if not UnitExists(unit) then
        frame.powerBar:SetValue(0)
        return
    end

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

    if type(power) ~= "number" or type(maxPower) ~= "number" then
        frame.powerBar:Hide()
        return
    end

    if IsSecretValue(maxPower) or maxPower ~= frame._lastMaxPower then
        if not IsSecretValue(maxPower) then
            frame._lastMaxPower = maxPower
        end
        frame.powerBar:SetMinMaxValues(0, maxPower)
    end
    frame.powerBar:SetValue(power)

    local r, g, b, a = GetPowerBarColor(unit, frame._isRaid)
    if r ~= frame._lastPowerColorR
        or g ~= frame._lastPowerColorG
        or b ~= frame._lastPowerColorB
        or a ~= frame._lastPowerColorA
    then
        frame._lastPowerColorR = r
        frame._lastPowerColorG = g
        frame._lastPowerColorB = b
        frame._lastPowerColorA = a
        frame.powerBar:SetStatusBarColor(r, g, b, a)
    end
end

local function UpdateName(frame)
    if not frame or not frame.nameText then return end
    local unit = QUI_GF.GetFrameUnit(frame)
    if not unit then return end

    local isRaid = frame._isRaid
    local nameSettings = GetNameSettings(isRaid)
    Chrome.AnchorBottomPadded(frame, GetVisualDB(isRaid), frame._bottomPad)
    if nameSettings and nameSettings.showName == false then
        frame.nameText:SetText("")
        return
    end

    if not UnitExists(unit) then return end

    local name = UnitName(unit)
    if not IsSecretValue(name) and not name then return end

    local maxLen = nameSettings and nameSettings.maxNameLength or 10
    if maxLen > 0 then
        name = Helpers.TruncateUTF8(name, maxLen)
    end
    frame.nameText:SetText(name)

    if nameSettings and nameSettings.nameTextUseClassColor then
        local _, class = UnitClass(unit)
        -- @secret-policy: collapse-only — settings text color below
        if IsSecretValue(class) then class = nil end
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
end

local function UpdateAbsorbs(frame, _unit, _maxHP)
    if not frame or not frame.absorbBar then return end
    local isRaid = frame._isRaid
    local vdb = GetVisualDB(isRaid)
    if not vdb or not vdb.absorbs or vdb.absorbs.enabled == false then
        frame.absorbBar:Hide()
        return
    end

    local unit = _unit or QUI_GF.GetFrameUnit(frame)
    if not unit then return end

    if not _unit then
        local _, isDeadOrGhost = GetUnitLifeState(unit)
        if not UnitExists(unit) or isDeadOrGhost then
            frame.absorbBar:Hide()
            return
        end
    end

    local maxHP = _maxHP or UnitHealthMax(unit)
    local absorbAmount = UnitGetTotalAbsorbs(unit)

    if not IsSecretValue(absorbAmount)
        and (not absorbAmount or SafeToNumber(absorbAmount, 0) <= 0) then
        frame.absorbBar:SetValue(0)
        frame.absorbBar:Hide()
        return
    end

    frame.absorbBar:SetMinMaxValues(0, maxHP)
    frame.absorbBar:SetValue(absorbAmount)

    local aa = vdb.absorbs.opacity or 0.3
    local ar, ag, ab
    if vdb.absorbs.useClassColor then
        local _, class = UnitClass(unit)
        -- @secret-policy: collapse-only — white fallback below
        if IsSecretValue(class) then class = nil end
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
    if ar ~= frame._lastAbsorbColorR or ag ~= frame._lastAbsorbColorG
        or ab ~= frame._lastAbsorbColorB or aa ~= frame._lastAbsorbColorA then
        frame._lastAbsorbColorR = ar
        frame._lastAbsorbColorG = ag
        frame._lastAbsorbColorB = ab
        frame._lastAbsorbColorA = aa
        frame.absorbBar:SetStatusBarColor(ar, ag, ab, aa)
    end
    frame.absorbBar:Show()
end

local function UpdateHealAbsorb(frame, _unit, _maxHP)
    if not frame or not frame.healAbsorbBar then return end
    local isRaid = frame._isRaid
    local vdb = GetVisualDB(isRaid)
    if not vdb or not vdb.healAbsorbs or vdb.healAbsorbs.enabled == false then
        frame.healAbsorbBar:Hide()
        return
    end

    local unit = _unit or QUI_GF.GetFrameUnit(frame)
    if not unit then return end

    if not _unit then
        local _, isDeadOrGhost = GetUnitLifeState(unit)
        if not UnitExists(unit) or isDeadOrGhost then
            frame.healAbsorbBar:Hide()
            return
        end
    end

    local maxHP = _maxHP or UnitHealthMax(unit)
    local healAbsorbAmount = UnitGetTotalHealAbsorbs(unit)

    if not IsSecretValue(healAbsorbAmount)
        and (not healAbsorbAmount or SafeToNumber(healAbsorbAmount, 0) <= 0) then
        frame.healAbsorbBar:SetValue(0)
        frame.healAbsorbBar:Hide()
        return
    end

    frame.healAbsorbBar:SetMinMaxValues(0, maxHP)
    frame.healAbsorbBar:SetValue(healAbsorbAmount)

    local ha = vdb.healAbsorbs.opacity or 0.6
    local hc = vdb.healAbsorbs.color or _state.defaultColors.healAbsorb
    if hc[1] ~= frame._lastHealAbsorbColorR or hc[2] ~= frame._lastHealAbsorbColorG
        or hc[3] ~= frame._lastHealAbsorbColorB or ha ~= frame._lastHealAbsorbColorA then
        frame._lastHealAbsorbColorR = hc[1]
        frame._lastHealAbsorbColorG = hc[2]
        frame._lastHealAbsorbColorB = hc[3]
        frame._lastHealAbsorbColorA = ha
        frame.healAbsorbBar:SetStatusBarColor(hc[1], hc[2], hc[3], ha)
    end
    frame.healAbsorbBar:Show()
end

local function UpdateHealPrediction(frame, _unit, _maxHP)
    if not frame or not frame.healPredictionBar then return end
    local isRaid = frame._isRaid
    local vdb = GetVisualDB(isRaid)
    if not vdb or not vdb.healPrediction or vdb.healPrediction.enabled == false then
        frame.healPredictionBar:Hide()
        return
    end

    local unit = _unit or QUI_GF.GetFrameUnit(frame)
    if not unit then return end

    if not _unit then
        local _, isDeadOrGhost = GetUnitLifeState(unit)
        if not UnitExists(unit) or isDeadOrGhost then
            frame.healPredictionBar:Hide()
            return
        end
    end

    local maxHP = _maxHP or UnitHealthMax(unit)
    local incomingHeals

    if CreateUnitHealPredictionCalculator then
        if not frame._healPredCalc then
            frame._healPredCalc = CreateUnitHealPredictionCalculator()
            frame._healPredCalc:SetIncomingHealClampMode(0)
            frame._healPredCalc:SetIncomingHealOverflowPercent(1.0)
        end
        local calc = frame._healPredCalc
        UnitGetDetailedHealPrediction(unit, nil, calc)
        incomingHeals = calc:GetIncomingHeals()
    else
        incomingHeals = UnitGetIncomingHeals(unit)
    end

    if IsSecretValue(incomingHeals) then
    elseif not incomingHeals then
        frame.healPredictionBar:Hide()
        return
    end

    frame.healPredictionBar:SetMinMaxValues(0, maxHP)
    frame.healPredictionBar:SetValue(incomingHeals)

    local pa = vdb.healPrediction.opacity or 0.5
    local pr, pg, pb
    if vdb.healPrediction.useClassColor then
        local _, class = UnitClass(unit)
        -- @secret-policy: collapse-only — green fallback below
        if IsSecretValue(class) then class = nil end
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
    if pr ~= frame._lastHealPredColorR or pg ~= frame._lastHealPredColorG
        or pb ~= frame._lastHealPredColorB or pa ~= frame._lastHealPredColorA then
        frame._lastHealPredColorR = pr
        frame._lastHealPredColorG = pg
        frame._lastHealPredColorB = pb
        frame._lastHealPredColorA = pa
        frame.healPredictionBar:SetStatusBarColor(pr, pg, pb, pa)
    end
    frame.healPredictionBar:Show()
end

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

ns.QUI_GroupFrameRoleAtlas = ROLE_ATLAS
ns.QUI_GroupFrameRoleToggleKey = ROLE_TOGGLE_KEY

local function UpdateRoleIcon(frame)
    if not frame or not frame.roleIcon then return end
    local unit = QUI_GF.GetFrameUnit(frame)
    if not unit then return end
    local isRaid = frame._isRaid
    local indSettings = GetIndicatorSettings(isRaid)
    if not indSettings or indSettings.showRoleIcon == false then
        frame.roleIcon:Hide()
        return
    end

    local role = UnitGroupRolesAssigned(unit)
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

local READY_CHECK_TEXTURES = {
    ready    = "INTERFACE\\RAIDFRAME\\ReadyCheck-Ready",
    notready = "INTERFACE\\RAIDFRAME\\ReadyCheck-NotReady",
    waiting  = "INTERFACE\\RAIDFRAME\\ReadyCheck-Waiting",
}

local function UpdateReadyCheck(frame)
    if not frame or not frame.readyCheckIcon then return end
    local unit = QUI_GF.GetFrameUnit(frame)
    if not unit then return end
    local isRaid = frame._isRaid
    local indSettings = GetIndicatorSettings(isRaid)
    if not indSettings or indSettings.showReadyCheck == false then
        frame.readyCheckIcon:Hide()
        return
    end

    local status = GetReadyCheckStatus(unit)
    if status then
        if status == "waiting" then
            local isAFK = UnitIsAFK(unit)
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

local function UpdateResurrection(frame)
    if not frame or not frame.resIcon then return end
    local unit = QUI_GF.GetFrameUnit(frame)
    if not unit then return end
    local isRaid = frame._isRaid
    local indSettings = GetIndicatorSettings(isRaid)
    if not indSettings or indSettings.showResurrection == false then
        frame.resIcon:Hide()
        return
    end

    local hasRes = UnitHasIncomingResurrection(unit)
    if hasRes then
        frame.resIcon:Show()
    else
        frame.resIcon:Hide()
    end
end

_state.IsPlayerUnit = function(unit)
    if unit == "player" then return true end
    if UnitIsUnit then
        local ok, isPlayer = pcall(UnitIsUnit, unit, "player")
        if not ok then return false end
        if IsSecretValue(isPlayer) then return false end -- @secret-policy: reject-secret-ids
        return isPlayer == true
    end
    return false
end

_state.IsUnitTarget = function(unit)
    if not unit then return false end
    if UnitIsUnit then
        local ok, isTarget = pcall(UnitIsUnit, unit, "target")
        if not ok then return false end
        if IsSecretValue(isTarget) then return false end -- @secret-policy: reject-secret-value
        return isTarget == true
    end
    return false
end

_state.GetActivePlayerSummonPopup = function()
    if not StaticPopup_FindVisible then return nil, nil end

    local checkedPopup = false
    local popup = StaticPopup_FindVisible("CONFIRM_SUMMON")
    if not IsSecretValue(popup) then
        if popup then return true, "CONFIRM_SUMMON" end
        checkedPopup = true
    end

    popup = StaticPopup_FindVisible("CONFIRM_SUMMON_SCENARIO")
    if not IsSecretValue(popup) then
        if popup then return true, "CONFIRM_SUMMON_SCENARIO" end
        checkedPopup = true
    end

    popup = StaticPopup_FindVisible("CONFIRM_SUMMON_STARTING_AREA")
    if not IsSecretValue(popup) then
        if popup then return true, "CONFIRM_SUMMON_STARTING_AREA" end
        checkedPopup = true
    end

    if checkedPopup then return false, nil end
    return nil, nil
end

_state.HasActivePlayerSummonConfirmation = function()
    local popupVisible = _state.GetActivePlayerSummonPopup()
    if popupVisible ~= nil then return popupVisible end

    if C_SummonInfo and C_SummonInfo.GetSummonConfirmTimeLeft then
        local timeLeft = C_SummonInfo.GetSummonConfirmTimeLeft()
        if not IsSecretValue(timeLeft) then
            return SafeToNumber(timeLeft, 0) > 0
        end
    end
    return false
end

local function UpdateSummonPending(frame)
    if not frame or not frame.summonIcon then return end
    local unit = QUI_GF.GetFrameUnit(frame)
    if not unit then return end
    if not UnitExists(unit) then
        frame.summonIcon:Hide()
        return
    end

    local isRaid = frame._isRaid
    local indSettings = GetIndicatorSettings(isRaid)
    if not indSettings or indSettings.showSummonPending == false then
        frame.summonIcon:Hide()
        return
    end

    local showSummon = false
    if C_IncomingSummon and C_IncomingSummon.HasIncomingSummon and C_IncomingSummon.IncomingSummonStatus then
        local okHas, hasSummon = pcall(C_IncomingSummon.HasIncomingSummon, unit)
        local okStatus, status = pcall(C_IncomingSummon.IncomingSummonStatus, unit)
        if okHas and okStatus and not IsSecretValue(hasSummon) and not IsSecretValue(status) and hasSummon == true then
            local pendingStatus = Enum and Enum.SummonStatus and Enum.SummonStatus.Pending or 1
            showSummon = status == pendingStatus
        end
    elseif C_IncomingSummon and C_IncomingSummon.HasIncomingSummon then
        local ok, hasSummon = pcall(C_IncomingSummon.HasIncomingSummon, unit)
        if ok and not IsSecretValue(hasSummon) then
            showSummon = hasSummon == true
        end
    end

    if showSummon and _state.IsPlayerUnit(unit) then
        showSummon = _state.HasActivePlayerSummonConfirmation()
    end

    if showSummon then
        frame.summonIcon:Show()
    else
        frame.summonIcon:Hide()
    end
end

local function UpdateThreat(frame)
    if not frame or not frame.threatBorder then return end
    local unit = QUI_GF.GetFrameUnit(frame)
    if not unit then return end
    local isRaid = frame._isRaid
    local indSettings = GetIndicatorSettings(isRaid)
    if not indSettings or indSettings.showThreatBorder == false then
        frame.threatBorder:Hide()
        return
    end

    local status = UnitThreatSituation(unit)
    -- @secret-policy: reject-secret-value
    if IsSecretValue(status) then
        frame.threatBorder:Hide()
        return
    end
    if status and status >= 2 then
        local tc = indSettings.threatColor or _state.defaultColors.threat
        Chrome.SetBackdropOverlayColor(frame.threatBorder, tc[1], tc[2], tc[3], tc[4] or 0.8)
        frame.threatBorder:SetFrameLevel(frame:GetFrameLevel() + Chrome.LEVELS.THREAT)
        frame.threatBorder:Show()
    else
        frame.threatBorder:Hide()
    end
end

local function UpdateTargetMarker(frame)
    if not frame or not frame.targetMarker then return end
    local unit = QUI_GF.GetFrameUnit(frame)
    if not unit then return end
    local isRaid = frame._isRaid
    local indSettings = GetIndicatorSettings(isRaid)
    if not indSettings or indSettings.showTargetMarker == false then
        frame.targetMarker:Hide()
        return
    end

    local index = GetRaidTargetIndex(unit)
    if IsSecretValue(index) then
        frame.targetMarker:Hide()
        return
    end
    if index then
        frame.targetMarker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        SetRaidTargetIconTexture(frame.targetMarker, index)
        frame.targetMarker:Show()
    else
        frame.targetMarker:Hide()
    end
end

local function UpdateLeaderIcon(frame)
    if not frame or not frame.leaderIcon then return end
    local unit = QUI_GF.GetFrameUnit(frame)
    if not unit then return end
    local isRaid = frame._isRaid
    local indSettings = GetIndicatorSettings(isRaid)
    if not indSettings or indSettings.showLeaderIcon == false then
        frame.leaderIcon:Hide()
        return
    end

    local isLeader = UnitIsGroupLeader(unit)
    local isAssistant = UnitIsGroupAssistant(unit)
    -- @secret-policy: collapse-only — hidden icon fallback
    if IsSecretValue(isLeader) then isLeader = nil end
    if IsSecretValue(isAssistant) then isAssistant = nil end
    if isLeader then
        frame.leaderIcon:SetAtlas("groupfinder-icon-leader")
        frame.leaderIcon:Show()
    elseif isAssistant then
        frame.leaderIcon:SetAtlas("groupfinder-icon-leader")
        frame.leaderIcon:SetAlpha(0.6)
        frame.leaderIcon:Show()
    else
        frame.leaderIcon:Hide()
        frame.leaderIcon:SetAlpha(1)
    end
end

local function UpdatePhaseIcon(frame)
    if not frame or not frame.phaseIcon then return end
    local unit = QUI_GF.GetFrameUnit(frame)
    if not unit then return end
    local isRaid = frame._isRaid
    local indSettings = GetIndicatorSettings(isRaid)
    if not indSettings or indSettings.showPhaseIcon == false then
        frame.phaseIcon:Hide()
        return
    end

    -- @secret-policy: collapse-only — hidden icon fallback
    local phaseReason = UnitPhaseReason(unit)
    if IsSecretValue(phaseReason) then phaseReason = nil end
    local phased = phaseReason ~= nil and UnitExists(unit)
    if phased then
        frame.phaseIcon:Show()
    else
        frame.phaseIcon:Hide()
    end
end

local function UpdateConnection(frame)
    if not frame then return end
    local unit = QUI_GF.GetFrameUnit(frame)
    if not unit then return end

    local isConnected, isDead = GetUnitLifeState(unit)
    local state = GetFrameState(frame)

    if not isConnected and UnitExists(unit) then
        state.lifeFaded = true
        frame:SetAlpha(0.5)
    elseif isDead then
        state.lifeFaded = true
        frame:SetAlpha(0.65)
    elseif state.lifeFaded then
        _state.ReleaseLifeFade(frame, unit)
    elseif state.outOfRange == nil then
        frame:SetAlpha(1)
    end
end

local function UpdateTargetHighlight(frame)
    if not frame or not frame.targetHighlight then return end
    local unit = QUI_GF.GetFrameUnit(frame)
    local isRaid = frame._isRaid
    local healerSettings = GetHealerSettings(isRaid)
    if not healerSettings or not healerSettings.targetHighlight or healerSettings.targetHighlight.enabled == false then
        frame.targetHighlight:Hide()
        return
    end

    if unit and _state.IsUnitTarget(unit) then
        local c = healerSettings.targetHighlight.color or _state.defaultColors.targetHighlight
        Chrome.SetBackdropOverlayColor(frame.targetHighlight, c[1], c[2], c[3], c[4] or 0.6)
        frame.targetHighlight:SetFrameLevel(frame:GetFrameLevel() + Chrome.LEVELS.TARGET)
        frame.targetHighlight:Show()
        local list = QUI_GF._targetHighlightFrames
        if not list then
            list = {}
            QUI_GF._targetHighlightFrames = list
        end
        for i = 1, #list do
            if list[i] == frame then return end
        end
        list[#list + 1] = frame
    else
        frame.targetHighlight:Hide()
    end
end

local SetDispelBorderColor = Chrome.SetDispelBorderColor

local function SetDispelBorderColorMixin(overlay, color)
    for _, key in ipairs(_dispel.borderKeys) do
        local border = overlay[key]
        if border then
            local tex = border:GetStatusBarTexture()
            tex:SetVertexColor(color:GetRGBA())
        end
    end
    if overlay.fill then
        local fillA = overlay._fillOpacity or 0
        overlay.fill:SetVertexColor(color:GetRGBA())
        overlay.fill:SetAlpha(fillA)
    end
end

local function ShowConfiguredDispelOverlay(overlay, colors, dispelType, opacity)
    if not dispelType or not colors then return false end

    local c = colors[dispelType]
    if not c then return false end

    SetDispelBorderColor(overlay, c[1], c[2], c[3], opacity)
    overlay:Show()
    return true
end

-- >>> QUI_TEST_EXTRACT DispelTypeIconRuntime
function _dispel.ReadableType(auraData)
    if IsSecretValue(auraData) then
        return nil -- @secret-policy: reject-secret-value
    end
    local dispelName = auraData and auraData.dispelName
    if IsSecretValue(dispelName) then
        -- @secret-policy: reject-secret-value — selection is deferred to the
        dispelName = nil
    end
    if dispelName == "Enrage" then return "Bleed" end
    if dispelName == "Magic" or dispelName == "Curse"
        or dispelName == "Disease" or dispelName == "Poison"
        or dispelName == "Bleed" then
        return dispelName
    end

    local dispelEnum = auraData and auraData.dispelType
    if IsSecretValue(dispelEnum) then
        -- @secret-policy: reject-secret-value
        dispelEnum = nil
    end
    return _dispel.enumNames[dispelEnum]
end

function _dispel.SelectCachedAura(cache, unit, orderKey, setKey, excludeSet)
    local order = cache and cache[orderKey]
    local set = cache and cache[setKey]
    if not order or not set then return nil, nil end

    local GetAuraByInstanceID = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
    if GetAuraByInstanceID and C_Secrets and C_Secrets.ShouldAurasBeSecret
        and C_Secrets.ShouldAurasBeSecret() then
        GetAuraByInstanceID = nil
    end
    for i = 1, #order do
        local instID = order[i]
        if instID and set[instID] and not (excludeSet and excludeSet[instID]) then
            local stillLive = true
            if GetAuraByInstanceID and not IsSecretValue(instID) then
                local live = GetAuraByInstanceID(unit, instID) -- @secret-safe: the AurasAreSecret gate above disables this access while restricted
                if not IsSecretValue(live) and live == nil then
                    stillLive = false
                end
            end
            if stillLive then
                local auraData = cache.debuffsByID and cache.debuffsByID[instID]
                return instID, _dispel.ReadableType(auraData)
            end
        end
    end
    return nil, nil
end

function _dispel.GetIconCurve(typeName)
    local cached = _dispel.iconCurves[typeName]
    if cached then return cached end
    if not C_CurveUtil or not C_CurveUtil.CreateColorCurve then return nil end

    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    curve:AddPoint(0, CreateColor(1, 1, 1, 0))
    for _, enumVal in ipairs(_dispel.allEnums) do
        local alpha = _dispel.enumNames[enumVal] == typeName and 1 or 0
        curve:AddPoint(enumVal, CreateColor(1, 1, 1, alpha))
    end
    _dispel.iconCurves[typeName] = curve
    return curve
end

function _dispel.ShowIconWithCurves(frame, unit, auraInstanceID)
    local icons = frame and frame.dispelTypeIcons
    local GetTypeColor = C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor
    if not icons or not GetTypeColor or not auraInstanceID then return false end

    Chrome.HideDispelTypeIcons(frame)
    local showed = false
    for _, typeName in ipairs(Chrome.DISPEL_ICON_TYPES) do
        local icon = icons[typeName]
        local curve = _dispel.GetIconCurve(typeName)
        if icon and curve then
            local ok = pcall(function()
                local color = GetTypeColor(unit, auraInstanceID, curve)
                icon:GetStatusBarTexture():SetVertexColor(color:GetRGBA())
            end)
            if ok then
                icon:Show()
                showed = true
            else
                icon:Hide()
            end
        end
    end
    return showed
end

function _dispel.HideVisuals(frame)
    if frame.dispelOverlay then frame.dispelOverlay:Hide() end
    Chrome.HideDispelTypeIcons(frame)
    if frame.cleanseGlow then frame.cleanseGlow:Hide() end
end
-- <<< QUI_TEST_EXTRACT DispelTypeIconRuntime

-- BY_ME_PLUS_TYPED awareness gradient (legacy/preview path): tint the chrome
-- gradient ramp + flat base with the typed debuff's color, laid out along
-- the health fill direction. Returns whether the gradient ended up shown.
function _dispel.UpdateGradient(frame, unit, dispelCfg, typedInstID, typedType)
    local overlay = frame.dispelOverlay
    local tex = overlay and overlay.gradient
    if not tex then return false end
    if not typedInstID then
        tex:Hide()
        return false
    end

    Chrome.LayoutDispelGradient(tex,
        dispelCfg and dispelCfg.gradientStartOpacity,
        dispelCfg and dispelCfg.gradientEndOpacity,
        frame._isVerticalFill)

    if C_UnitAuras.GetAuraDispelTypeColor then
        local curve = _dispel.GetGradientCurve(frame._isRaid)
        if curve then
            local cOk, color = pcall(C_UnitAuras.GetAuraDispelTypeColor,
                unit, typedInstID, curve)
            if cOk then
                if IsSecretValue(color) then color = nil end
                if color then
                    tex:SetVertexColor(color:GetRGBA())
                    tex:Show()
                    return true
                end
            end
        end
    end

    local colors = GetDispelColors(frame._isRaid)
    local c = (typedType and colors and colors[typedType])
        or (colors and colors.Magic)
        or _state.defaultColors.dispelFallback
    tex:SetVertexColor(c[1], c[2], c[3], 1)
    tex:Show()
    return true
end

local function UpdateDispelOverlay(frame)
    if not frame or not frame.dispelOverlay then return end
    -- Live frames with an active dispel feeder render the overlay through
    -- secure engine slots (see groupframes_dispel_feeder.lua); the cache-fed
    -- legacy art below stays hidden. Preview fakes never get a feeder and
    -- keep using this path.
    if frame._quiDispelFeederActive then
        _dispel.HideVisuals(frame)
        return
    end
    local unit = QUI_GF.GetFrameUnit(frame)
    if not unit then
        _dispel.HideVisuals(frame)
        return
    end

    local healerSettings = GetHealerSettings(frame._isRaid)
    local dispelCfg = healerSettings and healerSettings.dispelOverlay
    local glowCfg = healerSettings and healerSettings.cleanseGlow
    local borderOn = dispelCfg ~= nil and dispelCfg.enabled ~= false
    local iconOn = dispelCfg ~= nil and dispelCfg.showIcon == true
    local glowOn = glowCfg ~= nil and glowCfg.enabled == true
    if not borderOn and not iconOn and not glowOn then
        _dispel.HideVisuals(frame)
        return
    end

    local _, isDeadOrGhost = GetUnitLifeState(unit)
    if not UnitExists(unit) or isDeadOrGhost then
        _dispel.HideVisuals(frame)
        return
    end

    local GFA = ns.QUI_GroupFrameAuras
    local cache = GFA and GFA.unitAuraCache and GFA.unitAuraCache[unit]
    local playerInstID = _dispel.SelectCachedAura(
        cache, unit, "playerDispellableOrder", "playerDispellable"
    )

    local visualInstID, visualType
    local typedInstID, typedType
    local scope = dispelCfg and dispelCfg.scope
    if scope == "ALL_TYPED" then
        visualInstID, visualType = _dispel.SelectCachedAura(
            cache, unit, "typedDebuffOrder", "typedDebuffs"
        )
    else
        visualInstID, visualType = _dispel.SelectCachedAura(
            cache, unit, "playerDispellableOrder", "playerDispellable"
        )
        if scope == "BY_ME_PLUS_TYPED" then
            -- Awareness only: auras the player could dispel already carry the
            -- actionable overlay, so they never feed the gradient.
            typedInstID, typedType = _dispel.SelectCachedAura(
                cache, unit, "typedDebuffOrder", "typedDebuffs",
                cache and cache.playerDispellable
            )
        end
    end

    local glowFrame = frame.cleanseGlow
    if glowFrame then
        if glowOn and playerInstID then
            Chrome.SetCleanseGlowColor(glowFrame.art, glowCfg and glowCfg.color)
            glowFrame:Show()
        else
            glowFrame:Hide()
        end
    end

    local gradientShown = _dispel.UpdateGradient(frame, unit, dispelCfg,
        borderOn and typedInstID or nil, typedType)

    if not visualInstID then
        -- BY_ME_PLUS_TYPED: a typed-but-not-actionable debuff shows only the
        -- awareness gradient, so the overlay frame must stay up with the
        -- border art suppressed.
        if gradientShown then
            Chrome.SetDispelBordersShown(frame.dispelOverlay, false)
            frame.dispelOverlay:Show()
        else
            frame.dispelOverlay:Hide()
        end
        Chrome.HideDispelTypeIcons(frame)
        return
    end
    Chrome.SetDispelBordersShown(frame.dispelOverlay, true)

    if iconOn then
        local shown = visualType and Chrome.ShowDispelTypeIcon(frame, visualType)
        if not shown then
            _dispel.ShowIconWithCurves(frame, unit, visualInstID)
        end
    else
        Chrome.HideDispelTypeIcons(frame)
    end

    if not borderOn then
        frame.dispelOverlay:Hide()
        return
    end

    local overlay = frame.dispelOverlay
    if C_UnitAuras.GetAuraDispelTypeColor then
        local opacity = dispelCfg.opacity or 0.8
        local curve = GetDispelColorCurve(frame._isRaid, opacity)
        if curve then
            local cOk, color = pcall(C_UnitAuras.GetAuraDispelTypeColor, unit, visualInstID, curve)
            if cOk then
                if IsSecretValue(color) then color = nil end
                if color then
                    SetDispelBorderColorMixin(overlay, color)
                    overlay:Show()
                    return
                end
            end
        end
    end

    local colors = GetDispelColors(frame._isRaid)
    local fallbackOpacity = dispelCfg.opacity or 0.8
    if ShowConfiguredDispelOverlay(overlay, colors, visualType, fallbackOpacity) then
        return
    end

    local fallback = (colors and colors.Magic) or _state.defaultColors.dispelFallback
    SetDispelBorderColor(overlay, fallback[1], fallback[2], fallback[3], fallbackOpacity)
    overlay:Show()
end

local function UpdatePortrait(frame)
    if not frame then return end
    local unit = QUI_GF.GetFrameUnit(frame)
    if not unit then return end
    local isRaid = frame._isRaid
    local portraitSettings = GetPortraitSettings(isRaid)

    if not portraitSettings or not portraitSettings.showPortrait then
        if frame.portrait then frame.portrait:Hide() end
        return
    end

    if not frame.portrait or not frame.portraitTexture then return end

    if not UnitExists(unit) then
        frame.portrait:Hide()
        return
    end

    ns.SafeCall("best-effort-style", SetPortraitTexture, frame.portraitTexture, unit, true)
    frame.portraitTexture:SetTexCoord(0.15, 0.85, 0.15, 0.85)

    local isConnected, isDeadOrGhost = GetUnitLifeState(unit)
    frame.portraitTexture:SetDesaturated(isDeadOrGhost or not isConnected)

    frame.portrait:Show()
end

UpdateDarkModeVisuals = function(frame, force)
    if not frame then return end
    local general = GetGeneralSettings(frame._isRaid)
    local bgColor, healthOpacity, bgOpacity
    if general and general.darkMode then
        bgColor = general.darkModeBgColor or _state.defaultColors.darkModeBg
        healthOpacity = general.darkModeHealthOpacity or 1.0
        bgOpacity = general.darkModeBgOpacity or 1.0
    else
        bgColor = general and general.defaultBgColor or _state.defaultColors.frameBg
        healthOpacity = general and general.defaultHealthOpacity or 1.0
        bgOpacity = general and general.defaultBgOpacity or 1.0
    end
    local bgAlpha = (bgColor[4] or 1) * bgOpacity
    local now
    if force
        or bgColor[1] ~= frame._lastBackdropColorR
        or bgColor[2] ~= frame._lastBackdropColorG
        or bgColor[3] ~= frame._lastBackdropColorB
        or bgAlpha ~= frame._lastBackdropColorA
    then
        frame._lastBackdropColorR = bgColor[1]
        frame._lastBackdropColorG = bgColor[2]
        frame._lastBackdropColorB = bgColor[3]
        frame._lastBackdropColorA = bgAlpha
        now = GetTime()
        frame._lastBackdropReapplyTime = now
        SetBackdropFillColor(frame, bgColor[1], bgColor[2], bgColor[3], bgAlpha)
    else
        now = GetTime()
        if (now - (frame._lastBackdropReapplyTime or 0)) >= _state.backdropReapplyInterval then
            frame._lastBackdropReapplyTime = now
            SetBackdropFillColor(frame, bgColor[1], bgColor[2], bgColor[3], bgAlpha)
        end
    end
    if frame.healthBar then
        if healthOpacity ~= frame._lastHealthBarAlpha then
            frame._lastHealthBarAlpha = healthOpacity
            frame.healthBar:SetAlpha(healthOpacity)
        end
    end
end

local function UpdateFrame(frame)
    if not frame or not QUI_GF.GetFrameUnit(frame) then return end
    UpdateDarkModeVisuals(frame, true)
    UpdateHealth(frame)
    UpdatePower(frame)
    UpdateName(frame)
    _state.UpdateLevelText(frame)
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
    UpdatePortrait(frame)
end

local function DecorateGroupFrame(frame)
    if not frame or frame._quiDecorated then return end
    frame._quiDecorated = true

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

    local vdb = GetVisualDB(isRaid)

    Chrome.Apply(frame, vdb, GetFrameState(frame))

    if not frame._quiHooked then
        frame._quiHooked = true

        frame:HookScript("OnEnter", function(self)
            local general = GetGeneralSettings(self._isRaid)
            if not general or general.showTooltips == false then return end
            _state._tooltipPending = self
            if _state._tooltipTimer then return end
            _state._tooltipTimer = C_Timer.NewTimer(0.10, function()
                _state._tooltipTimer = nil
                local f = _state._tooltipPending
                _state._tooltipPending = nil
                if f and f.IsShown and f:IsShown() then
                    ShowUnitTooltip(f)
                end
            end)
        end)
        frame:HookScript("OnLeave", HideUnitTooltip)

        frame:HookScript("OnAttributeChanged", function(self, key, value)
            if key ~= "unit" then return end
            local oldUnit = QUI_GF.GetFrameUnit(self)
            if not oldUnit and not value then return end

            QUI_GF.SetFrameUnit(self, value)

            if oldUnit then
                RemoveFrameFromMap(oldUnit, self)
            end

            if not value then
                _state.unitGuidCache[self] = nil
                if self.summonIcon then self.summonIcon:Hide() end
                local GFADisable = ns.QUI_GroupFrameAuras
                if GFADisable and GFADisable.DisableStripContainers then
                    GFADisable.DisableStripContainers(self)
                end
                return
            end

            AddFrameToMap(value, self)

            local GFAStrip = ns.QUI_GroupFrameAuras
            if GFAStrip and GFAStrip.UpdateStripContainers then
                GFAStrip.UpdateStripContainers(self)
            end

            local rawGuid = UnitGUID(value)
            local newGuid = rawGuid
            if IsSecretValue(newGuid) then newGuid = nil end
            local oldGuid = _state.unitGuidCache[self]
            if newGuid then
                _state.unitGuidCache[self] = newGuid
            end

            if oldGuid and newGuid and oldGuid == newGuid then return end

            self._quiRosterAuraDirty = true
            UpdateFrame(self)
        end)
    end

    local currentUnit = frame:GetAttribute("unit")
    if currentUnit then
        frame._quiRosterAuraDirty = true
        QUI_GF.SetFrameUnit(frame, currentUnit)
        AddFrameToMap(currentUnit, frame)
        local GFADecorate = ns.QUI_GroupFrameAuras
        if GFADecorate and GFADecorate.UpdateStripContainers then
            GFADecorate.UpdateStripContainers(frame)
        end
    end

    if ClickCastFrames then
        ClickCastFrames[frame] = true
    end

    local GFCC = ns.QUI_GroupFrameClickCast
    if GFCC and GFCC:IsEnabled() then
        GFCC:RegisterFrame(frame)
    end

    table.insert(QUI_GF.allFrames, frame)
end

QUI_GF.DecorateGroupFrame = DecorateGroupFrame

function QUI_GF:InitializeHeaderChild(frame)
    if not frame then return end
    DecorateGroupFrame(frame)
    if not InCombatLockdown() then
        frame:RegisterForClicks("AnyUp")
    else
        _pending.registerClicks = true
    end
end

function QUI_GF.HeaderChildCreated(_, childName)
    local child = childName and _G[childName]
    if child then
        QUI_GF:InitializeHeaderChild(child)
    end
end

local function CollectHeaderUnits(header)
    if not header or not header:IsShown() then return end
    local i = 1
    while true do
        local child = header:GetAttribute("child" .. i)
        if not child then break end
        local unit = child:GetAttribute("unit")
        QUI_GF.SetFrameUnit(child, unit)
        if unit then
            AddFrameToMap(unit, child)
        end
        i = i + 1
    end
end

local function RebuildUnitFrameMap()
    local previousUnits = {}
    for unit in pairs(QUI_GF.unitFrameMap) do
        previousUnits[unit] = true
    end
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

    CollectHeaderUnits(QUI_GF.spotlightHeader)

    if _state.RefreshUnitEventRegistrations then
        _state.RefreshUnitEventRegistrations(previousUnits)
    end
end

local function EnsureAnchorFrame(key)
    local root = QUI_GF.anchorFrames[key]
    if root then return root end

    local name = key == "raid" and "QUI_RaidFramesRoot" or "QUI_PartyFramesRoot"
    local old = _G[name]
    if old then old:Hide() end

    root = CreateFrame("Frame", name, UIParent)
    root:EnableMouse(false)
    root:Hide()

    QUI_GF.anchorFrames[key] = root
    return root
end

local function GetAnchorPosition(key, db)
    local x, y
    if key == "raid" and db and db.unifiedPosition == false then
        local pos = db.raidPosition
        x, y = pos and pos.offsetX or -400, pos and pos.offsetY or 0
    else
        local pos = db and db.position
        x, y = pos and pos.offsetX or -400, pos and pos.offsetY or 0
    end

    if key == "raid" then
        local offX, offY = QUI_GF:GetRaidSizeOffset(db)
        x = x + offX
        y = y + offY
    end

    return x, y
end

function QUI_GF:GetRaidSizeOffset(db)
    if db and db.raidPerSizePositions and db.raidSizeOffsets then
        local off = db.raidSizeOffsets[GetGroupMode()]
        if off then
            return off.offsetX or 0, off.offsetY or 0
        end
    end
    return 0, 0
end

function QUI_GF:ApplyRaidAnchorWithSizeOffset(db)
    if not (_G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("raidFrames")) then
        return false
    end

    local anchoring = ns.QUI_Anchoring
    local faDB = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.frameAnchoring
    local settings = faDB and faDB.raidFrames
    if not (anchoring and anchoring.ApplyFrameAnchor and settings) then
        if _G.QUI_ApplyFrameAnchor then _G.QUI_ApplyFrameAnchor("raidFrames") end
        return true
    end

    local offX, offY = self:GetRaidSizeOffset(db)
    if offX == 0 and offY == 0 then
        anchoring:ApplyFrameAnchor("raidFrames", settings)
        return true
    end

    local effective = {}
    for k, v in pairs(settings) do effective[k] = v end
    effective.offsetX = (effective.offsetX or 0) + offX
    effective.offsetY = (effective.offsetY or 0) + offY
    anchoring:ApplyFrameAnchor("raidFrames", effective)
    return true
end

local function GetAnchorFallbackSize(key, db)
    local isRaid = key == "raid"
    local vdb = isRaid and (db and (db.raid or db)) or (db and (db.party or db))
    local layout = (vdb and vdb.layout)
        or (db and ((isRaid and db.raidLayout) or db.partyLayout))
        or (db and db.layout)

    local count
    if isRaid then
        count = (db and db.testMode and db.testMode.raidCount) or 25
    else
        count = 5
    end

    local framesPerGroup = 5
    local numGroups = math_ceil(count / framesPerGroup)
    local spacing = (layout and layout.spacing) or 2
    local groupSpacing = (layout and layout.groupSpacing) or 10
    local grow = (layout and layout.growDirection) or "DOWN"
    local horizontal = (grow == "LEFT" or grow == "RIGHT")

    local dims = vdb and vdb.dimensions
    local mode
    if count <= 5 then mode = "party"
    elseif count <= 15 then mode = "small"
    elseif count <= 25 then mode = "medium"
    else mode = "large"
    end

    local frameW, frameH
    if mode == "party" then
        frameW, frameH = (dims and dims.partyWidth) or 200, (dims and dims.partyHeight) or 40
    elseif mode == "small" then
        frameW, frameH = (dims and dims.smallRaidWidth) or 180, (dims and dims.smallRaidHeight) or 36
    elseif mode == "medium" then
        frameW, frameH = (dims and dims.mediumRaidWidth) or 160, (dims and dims.mediumRaidHeight) or 30
    else
        frameW, frameH = (dims and dims.largeRaidWidth) or 140, (dims and dims.largeRaidHeight) or 24
    end

    local totalW, totalH
    if horizontal then
        totalW = framesPerGroup * frameW + (framesPerGroup - 1) * spacing
        totalH = numGroups * frameH + (numGroups - 1) * groupSpacing
    else
        totalW = numGroups * frameW + (numGroups - 1) * groupSpacing
        totalH = framesPerGroup * frameH + (framesPerGroup - 1) * spacing
    end

    return math_max(totalW, 1), math_max(totalH, 1)
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
            header:SetPoint("TOPRIGHT", attachTo, "TOPLEFT", -(gap or 0), 0)
        elseif grow == "RIGHT" then
            header:SetPoint("TOPLEFT", attachTo, "TOPRIGHT", gap or 0, 0)
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
    local db = GetSettings()
    local vdb = db and (isRaid and (db.raid or db) or (db.party or db))
    local layout = vdb and vdb.layout or (db and ((isRaid and db.raidLayout) or db.partyLayout)) or (db and db.layout)
    local gap = layout and layout.spacing or 2

    local mainVisible = mainHeader and mainHeader:IsShown()
    local selfVisible = selfHeader and selfHeader:IsShown()

    if not mainVisible and not selfVisible then
        local fallbackW, fallbackH = GetAnchorFallbackSize(key, db)
        local posX, posY = GetAnchorPosition(key, db)
        root:ClearAllPoints()
        root:SetPoint("CENTER", UIParent, "CENTER", posX, posY)
        root:SetSize(fallbackW, fallbackH)
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
                totalW = math_max(totalW, hW)
                totalH = totalH + hH
            else
                totalW = totalW + hW
                totalH = math_max(totalH, hH)
            end
        end
    end

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
            local applyAnchor = _G.QUI_ApplyFrameAnchor
            local hasAnchor = _G.QUI_HasFrameAnchor
            if hasAnchor and hasAnchor("partyFrames") and applyAnchor then
                applyAnchor("partyFrames")
            elseif partyRoot:GetNumPoints() == 0 then
                partyRoot:SetPoint("CENTER", UIParent, "CENTER", partyX, partyY)
            end
            if QUI_GF:ApplyRaidAnchorWithSizeOffset(db) then
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

    local applyAnchor = _G.QUI_ApplyFrameAnchor
    local hasAnchor = _G.QUI_HasFrameAnchor
    if hasAnchor and hasAnchor("partyFrames") and applyAnchor then
        applyAnchor("partyFrames")
    elseif partyRoot:GetNumPoints() == 0 then
        partyRoot:SetPoint("CENTER", UIParent, "CENTER", partyX, partyY)
    end
    if QUI_GF:ApplyRaidAnchorWithSizeOffset(db) then
    elseif raidRoot:GetNumPoints() == 0 then
        raidRoot:SetPoint("CENTER", UIParent, "CENTER", raidX, raidY)
    end
end

---------------------------------------------------------------------------
-- Party include-list (hidden players active). The secure header only honors
-- nameList when NEITHER groupFilter nor roleFilter is set, and its nameList
-- branch ignores groupBy entirely (SecureGroupHeaders.lua:410-495) — so
-- hideDPS and role ordering are folded into the computed list here and the
-- header sorts by NAMELIST order. The header's showPlayer/showParty/showSolo
-- attributes still gate which units are iterated at all.
---------------------------------------------------------------------------
do  -- do-block: keeps these helpers off the main chunk's 200-local budget
local PARTY_NAMELIST_UNITS = { "player", "party1", "party2", "party3", "party4" }

local function BuildPartyNameListEntries(layout, hiddenSet)
    local entries = {}
    local needRole = layout.hideDPS == true or layout.sortByRole == true
    for i = 1, #PARTY_NAMELIST_UNITS do
        local unit = PARTY_NAMELIST_UNITS[i]
        if UnitExists(unit) then
            local name, server = UnitName(unit)
            if IsSecretValue(name) then name = nil end
            if IsSecretValue(server) then server = nil end
            if name then
                -- Mirror SecureGroupHeaders' GetGroupRosterInfo name format
                -- so include-list tokens compare equal for cross-realm units.
                if server and server ~= "" then
                    name = name .. "-" .. server
                end
                local role = "NONE"
                if needRole then
                    role = UnitGroupRolesAssigned(unit)
                    if IsSecretValue(role) or not role then role = "NONE" end
                end
                local keep = not Helpers.NameListContains(hiddenSet, name)
                if keep and layout.hideDPS == true then
                    -- Same semantics as the roleFilter="TANK,HEALER" path,
                    -- including hiding a DPS-spec player's own frame.
                    keep = role == "TANK" or role == "HEALER"
                end
                if keep then
                    entries[#entries + 1] = { name = name, role = role, index = i }
                end
            end
        end
    end

    if layout.sortByRole == true then
        table_sort(entries, function(a, b)
            local pa = RAID_SECTION_ROLE_PRIORITY[a.role] or 99
            local pb = RAID_SECTION_ROLE_PRIORITY[b.role] or 99
            if pa ~= pb then return pa < pb end
            return a.index < b.index
        end)
    elseif layout.sortMethod == "NAME" then
        table_sort(entries, function(a, b)
            if a.name ~= b.name then return a.name < b.name end
            return a.index < b.index
        end)
    end

    return entries
end

-- Returns nil when no hidden-players list is configured (normal attribute
-- path applies). Otherwise: nameList (may be "" — a valid everyone-filtered
-- include list that keeps the header showing nobody), the count of non-player
-- members kept, and whether the player's own entry survived the filters.
_state.GetPartyNameListInfo = function(layout, db)
    local hiddenSet = _state.GetHiddenPlayerSet(db)
    if not hiddenSet then return nil end

    local entries = BuildPartyNameListEntries(layout, hiddenSet)
    local names, memberCount, hasPlayer = {}, 0, false
    for i = 1, #entries do
        names[i] = entries[i].name
        if entries[i].index == 1 then
            hasPlayer = true
        else
            memberCount = memberCount + 1
        end
    end

    return {
        nameList = table_concat(names, ","),
        memberCount = memberCount,
        hasPlayer = hasPlayer,
    }
end
end  -- do-block

local function GetVisiblePartyUnitCount()
    local layout = GetLayoutSettings(false)
    if not layout then return 0 end

    local db = GetSettings()
    local selfFirst = GetPartySelfFirst(db)

    if IsInRaid() then
        return 0
    end

    local info = _state.GetPartyNameListInfo(layout, db)

    if IsInGroup() then
        local subgroupCount
        if info then
            subgroupCount = info.memberCount
        elseif type(GetNumSubgroupMembers) == "function" then
            subgroupCount = GetNumSubgroupMembers() or 0
        else
            subgroupCount = math_max((GetNumGroupMembers() or 0) - 1, 0)
        end

        if selfFirst or layout.showPlayer == false then
            return subgroupCount
        end

        return subgroupCount + ((not info or info.hasPlayer) and 1 or 0)
    end

    if selfFirst or not layout.showSolo then
        return 0
    end

    return (not info or info.hasPlayer) and 1 or 0
end

local function ConfigurePartyHeader(header)
    local layout = GetLayoutSettings(false)
    if not layout then return end

    local db = GetSettings()
    local selfFirst = GetPartySelfFirst(db)
    local inParty = IsInGroup() and not IsInRaid()
    local showSolo = (not inParty) and layout.showSolo and not selfFirst

    _state.SetHeaderAttributeIfChanged(header, "showParty", true)
    _state.SetHeaderAttributeIfChanged(header, "showPlayer", (not selfFirst and ((inParty and layout.showPlayer ~= false) or showSolo)) and true or false)
    _state.SetHeaderAttributeIfChanged(header, "showRaid", false)
    _state.SetHeaderAttributeIfChanged(header, "showSolo", showSolo or false)
    _state.SetHeaderAttributeIfChanged(header, "maxColumns", 1)
    _state.SetHeaderAttributeIfChanged(header, "unitsPerColumn", 5)

    local mode = "party"
    local w, h = GetFrameDimensions(mode)
    local spacing = layout.spacing or 2

    local grow = GetLayoutGrowDirection(layout, "DOWN")
    if grow == "DOWN" then
        _state.SetHeaderAttributeIfChanged(header, "point", "TOP")
        _state.SetHeaderAttributeIfChanged(header, "yOffset", -spacing)
        _state.SetHeaderAttributeIfChanged(header, "xOffset", 0)
    elseif grow == "UP" then
        _state.SetHeaderAttributeIfChanged(header, "point", "BOTTOM")
        _state.SetHeaderAttributeIfChanged(header, "yOffset", spacing)
        _state.SetHeaderAttributeIfChanged(header, "xOffset", 0)
    elseif grow == "RIGHT" then
        _state.SetHeaderAttributeIfChanged(header, "point", "LEFT")
        _state.SetHeaderAttributeIfChanged(header, "xOffset", spacing)
        _state.SetHeaderAttributeIfChanged(header, "yOffset", 0)
    elseif grow == "LEFT" then
        _state.SetHeaderAttributeIfChanged(header, "point", "RIGHT")
        _state.SetHeaderAttributeIfChanged(header, "xOffset", -spacing)
        _state.SetHeaderAttributeIfChanged(header, "yOffset", 0)
    end

    local nameListInfo = _state.GetPartyNameListInfo(layout, db)
    if nameListInfo then
        -- Include-list mode (hidden players configured): drive the header
        -- from a computed nameList. Ordering discipline mirrors the raid
        -- section path — set nameList/sortMethod FIRST so no intermediate
        -- state leaves the header filterless, then clear roleFilter/groupBy
        -- (a set roleFilter would make the header ignore nameList entirely).
        _state.SetHeaderAttributeIfChanged(header, "nameList", nameListInfo.nameList)
        _state.SetHeaderAttributeIfChanged(header, "sortMethod", "NAMELIST")
        _state.SetHeaderAttributeIfChanged(header, "groupBy", nil)
        _state.SetHeaderAttributeIfChanged(header, "groupingOrder", nil)
        _state.SetHeaderAttributeIfChanged(header, "roleFilter", nil)
    else
        if layout.sortByRole then
            _state.SetHeaderAttributeIfChanged(header, "groupBy", "ASSIGNEDROLE")
            _state.SetHeaderAttributeIfChanged(header, "groupingOrder", "TANK,HEALER,DAMAGER,NONE")
        else
            _state.SetHeaderAttributeIfChanged(header, "groupBy", nil)
            _state.SetHeaderAttributeIfChanged(header, "groupingOrder", nil)
        end
        -- NAMELIST sorting only exists in include-list mode; restore the
        -- layout sort when leaving it (change-guard no-ops otherwise).
        _state.SetHeaderAttributeIfChanged(header, "sortMethod", layout.sortMethod or "INDEX")

        _state.SetHeaderAttributeIfChanged(header, "roleFilter", layout.hideDPS and "TANK,HEALER" or nil)
        -- Cleared LAST when leaving include-list mode: while roleFilter/groupBy
        -- are being restored above, a still-set nameList keeps the header in a
        -- valid filtered state instead of briefly showing everyone.
        _state.SetHeaderAttributeIfChanged(header, "nameList", nil)
    end

    _state.SetHeaderAttributeIfChanged(header, "_initialAttributeNames", "unit-width,unit-height")
    _state.SetHeaderAttributeIfChanged(header, "_initialAttribute-unit-width", w)
    _state.SetHeaderAttributeIfChanged(header, "_initialAttribute-unit-height", h)
end

local function ConfigureRaidHeader(header)
    local layout = GetLayoutSettings(true)
    if not layout then return end

    _state.SetHeaderAttributeIfChanged(header, "showRaid", true)
    _state.SetHeaderAttributeIfChanged(header, "showParty", false)
    _state.SetHeaderAttributeIfChanged(header, "showPlayer", false)
    _state.SetHeaderAttributeIfChanged(header, "showSolo", false)

    local mode = GetGroupMode()
    local w, h = GetFrameDimensions(mode)
    local spacing = layout.spacing or 2
    local groupSpacing = layout.groupSpacing or 10

    local grow = GetLayoutGrowDirection(layout, "DOWN")
    if grow == "DOWN" then
        _state.SetHeaderAttributeIfChanged(header, "point", "TOP")
        _state.SetHeaderAttributeIfChanged(header, "yOffset", -spacing)
        _state.SetHeaderAttributeIfChanged(header, "xOffset", 0)
    elseif grow == "UP" then
        _state.SetHeaderAttributeIfChanged(header, "point", "BOTTOM")
        _state.SetHeaderAttributeIfChanged(header, "yOffset", spacing)
        _state.SetHeaderAttributeIfChanged(header, "xOffset", 0)
    elseif grow == "RIGHT" then
        _state.SetHeaderAttributeIfChanged(header, "point", "LEFT")
        _state.SetHeaderAttributeIfChanged(header, "xOffset", spacing)
        _state.SetHeaderAttributeIfChanged(header, "yOffset", 0)
    elseif grow == "LEFT" then
        _state.SetHeaderAttributeIfChanged(header, "point", "RIGHT")
        _state.SetHeaderAttributeIfChanged(header, "xOffset", -spacing)
        _state.SetHeaderAttributeIfChanged(header, "yOffset", 0)
    end

    local horizontal = (grow == "LEFT" or grow == "RIGHT")
    local groupBy = layout.groupBy or "GROUP"
    local isFlat = (groupBy == "NONE")
    local groupLimit = _state.GetRaidGroupLimit(layout)
    local groupFilter = _state.GetRaidGroupFilterString(layout)

    if isFlat then
        local upc = layout.unitsPerFlat or 5
        _state.SetHeaderAttributeIfChanged(header, "unitsPerColumn", upc)
        _state.SetHeaderAttributeIfChanged(header, "maxColumns", math.ceil((groupLimit * 5) / upc))
        _state.SetHeaderAttributeIfChanged(header, "columnSpacing", spacing)
    else
        _state.SetHeaderAttributeIfChanged(header, "maxColumns", groupLimit)
        _state.SetHeaderAttributeIfChanged(header, "unitsPerColumn", 5)
        _state.SetHeaderAttributeIfChanged(header, "columnSpacing", groupSpacing)
    end

    if horizontal then
        _state.SetHeaderAttributeIfChanged(header, "columnAnchorPoint", "TOP")
    else
        local groupGrow = layout.groupGrowDirection or "RIGHT"
        if groupGrow == "RIGHT" then
            _state.SetHeaderAttributeIfChanged(header, "columnAnchorPoint", "LEFT")
        else
            _state.SetHeaderAttributeIfChanged(header, "columnAnchorPoint", "RIGHT")
        end
    end

    if groupBy == "NONE" then
        _state.SetHeaderAttributeIfChanged(header, "groupBy", nil)
        _state.SetHeaderAttributeIfChanged(header, "groupFilter", groupLimit < 8 and groupFilter or nil)
        _state.SetHeaderAttributeIfChanged(header, "groupingOrder", nil)
    elseif groupBy == "GROUP" then
        _state.SetHeaderAttributeIfChanged(header, "groupBy", "GROUP")
        _state.SetHeaderAttributeIfChanged(header, "groupFilter", groupFilter)
        _state.SetHeaderAttributeIfChanged(header, "groupingOrder", groupFilter)
    elseif groupBy == "ROLE" then
        _state.SetHeaderAttributeIfChanged(header, "groupBy", "ASSIGNEDROLE")
        _state.SetHeaderAttributeIfChanged(header, "groupingOrder", "TANK,HEALER,DAMAGER,NONE")
    elseif groupBy == "CLASS" then
        _state.SetHeaderAttributeIfChanged(header, "groupBy", "CLASS")
        _state.SetHeaderAttributeIfChanged(header, "groupingOrder", "WARRIOR,DEATHKNIGHT,PALADIN,MONK,PRIEST,SHAMAN,DRUID,ROGUE,MAGE,WARLOCK,HUNTER,DEMONHUNTER,EVOKER")
    end

    if layout.sortByRole and groupBy ~= "ROLE" then
        _state.SetHeaderAttributeIfChanged(header, "sortMethod", "NAME")
    else
        _state.SetHeaderAttributeIfChanged(header, "sortMethod", layout.sortMethod or "INDEX")
    end

    _state.SetHeaderAttributeIfChanged(header, "_initialAttributeNames", "unit-width,unit-height")
    _state.SetHeaderAttributeIfChanged(header, "_initialAttribute-unit-width", w)
    _state.SetHeaderAttributeIfChanged(header, "_initialAttribute-unit-height", h)
end

_state.SetHeaderAttributeIfChanged = function(header, name, value)
    if header:GetAttribute(name) ~= value then
        header:SetAttribute(name, value)
    end
end

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
    local useNameListSections = _state.UseRaidNameListSections(db, layout)
    local sections = useNameListSections and GetRaidDisplaySections() or nil
    local groupLimit = _state.GetRaidGroupLimit(layout)

    for g, header in ipairs(QUI_GF.raidGroupHeaders) do
        local section = sections and sections[g] or nil
        if header then
            _state.SetHeaderAttributeIfChanged(header, "point", point)
            _state.SetHeaderAttributeIfChanged(header, "xOffset", xOff)
            _state.SetHeaderAttributeIfChanged(header, "yOffset", yOff)
            _state.SetHeaderAttributeIfChanged(header, "showRaid", true)
            _state.SetHeaderAttributeIfChanged(header, "showParty", false)
            _state.SetHeaderAttributeIfChanged(header, "showPlayer", false)
            _state.SetHeaderAttributeIfChanged(header, "showSolo", false)
            _state.SetHeaderAttributeIfChanged(header, "columnSpacing", spacing)
            _state.SetHeaderAttributeIfChanged(header, "columnAnchorPoint", columnAnchorPoint)
            _state.SetHeaderAttributeIfChanged(header, "sortDir", "ASC")

            if section then
                local unitsPerColumn = math_max(1, math_min(section.memberCount, GetRaidSectionUnitsPerColumn(layout)))
                _state.SetHeaderAttributeIfChanged(header, "maxColumns", math_max(1, math.ceil(section.memberCount / unitsPerColumn)))
                _state.SetHeaderAttributeIfChanged(header, "unitsPerColumn", unitsPerColumn)
                _state.SetHeaderAttributeIfChanged(header, "nameList", section.nameList)
                _state.SetHeaderAttributeIfChanged(header, "sortMethod", "NAMELIST")
                _state.SetHeaderAttributeIfChanged(header, "sortDir", "ASC")
                _state.SetHeaderAttributeIfChanged(header, "groupBy", nil)
                _state.SetHeaderAttributeIfChanged(header, "groupFilter", nil)
                _state.SetHeaderAttributeIfChanged(header, "groupingOrder", nil)
            elseif useNameListSections then
                _state.SetHeaderAttributeIfChanged(header, "maxColumns", 1)
                _state.SetHeaderAttributeIfChanged(header, "unitsPerColumn", 1)
                _state.SetHeaderAttributeIfChanged(header, "groupBy", nil)
                _state.SetHeaderAttributeIfChanged(header, "groupFilter", nil)
                _state.SetHeaderAttributeIfChanged(header, "groupingOrder", nil)
                _state.SetHeaderAttributeIfChanged(header, "nameList", nil)
                _state.SetHeaderAttributeIfChanged(header, "sortMethod", "INDEX")
            else
                _state.SetHeaderAttributeIfChanged(header, "maxColumns", 1)
                _state.SetHeaderAttributeIfChanged(header, "unitsPerColumn", 5)
                if g <= groupLimit then
                    _state.SetHeaderAttributeIfChanged(header, "groupBy", "GROUP")
                    _state.SetHeaderAttributeIfChanged(header, "groupFilter", tostring(g))
                    _state.SetHeaderAttributeIfChanged(header, "groupingOrder", tostring(g))
                    _state.SetHeaderAttributeIfChanged(header, "nameList", nil)

                    if sortByRole then
                        _state.SetHeaderAttributeIfChanged(header, "sortMethod", "NAME")
                    else
                        _state.SetHeaderAttributeIfChanged(header, "sortMethod", sortMethod)
                    end
                else
                    _state.SetHeaderAttributeIfChanged(header, "groupBy", nil)
                    _state.SetHeaderAttributeIfChanged(header, "groupFilter", nil)
                    _state.SetHeaderAttributeIfChanged(header, "groupingOrder", nil)
                    _state.SetHeaderAttributeIfChanged(header, "nameList", nil)
                    _state.SetHeaderAttributeIfChanged(header, "sortMethod", "INDEX")
                end
            end

            _state.SetHeaderAttributeIfChanged(header, "_initialAttributeNames", "unit-width,unit-height")
            _state.SetHeaderAttributeIfChanged(header, "_initialAttribute-unit-width", w)
            _state.SetHeaderAttributeIfChanged(header, "_initialAttribute-unit-height", h)
        end
    end

    return sections
end

function _state.UpdateRaidGroupLabel(header, g, layout)
    if not header then return end
    local vdb = GetVisualDB(true)
    local s = vdb and vdb.groupNumber
    local groupedByGroup = ((layout and layout.groupBy) or "GROUP") == "GROUP"
    local show = s and s.showGroupNumber == true and groupedByGroup and header:IsShown()

    local lbl = header._quiGroupLabel
    if not show then
        if lbl then lbl:Hide() end
        return
    end

    if not lbl then
        lbl = CreateFrame("Frame", nil, header)
        lbl:SetAllPoints(header)
        lbl.text = lbl:CreateFontString(nil, "OVERLAY")
        header._quiGroupLabel = lbl
    end
    lbl:SetFrameLevel(header:GetFrameLevel() + 10)

    local size = tonumber(s.groupNumberFontSize) or 12
    ns.Helpers.ApplyFontWithFallback(lbl.text, GetFontPath(true), size, GetFontOutline(true))
    lbl.text:SetText(((ns.L and ns.L["Group"]) or "Group") .. " " .. g)
    local c = s.groupNumberTextColor or COLORS.WHITE
    lbl.text:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    lbl.text:SetWordWrap(false)

    local anchor = s.groupNumberAnchor or "TOPRIGHT"
    local selfPoint, blockPoint = anchor, anchor
    if anchor == "CENTER" then
        selfPoint, blockPoint = "CENTER", "CENTER"
    elseif anchor:find("TOP") then
        selfPoint = (anchor:gsub("TOP", "BOTTOM"))
    elseif anchor:find("BOTTOM") then
        selfPoint = (anchor:gsub("BOTTOM", "TOP"))
    elseif anchor == "LEFT" then
        selfPoint = "RIGHT"
    elseif anchor == "RIGHT" then
        selfPoint = "LEFT"
    end
    lbl.text:ClearAllPoints()
    lbl.text:SetPoint(selfPoint, lbl, blockPoint,
        tonumber(s.groupNumberOffsetX) or 0, tonumber(s.groupNumberOffsetY) or 0)

    lbl:Show()
    lbl.text:Show()
end

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

    if not groupGrow then
        groupGrow = horizontal and "DOWN" or "RIGHT"
    end

    local raidRoot = QUI_GF.anchorFrames.raid
    local prevHeader = nil

    for g, header in ipairs(QUI_GF.raidGroupHeaders) do
        if header and header:IsShown() then
            header:ClearAllPoints()

            if not prevHeader then
                if horizontal then
                    if groupGrow == "UP" then
                        if grow == "RIGHT" then
                            header:SetPoint("BOTTOMLEFT", raidRoot, "BOTTOMLEFT", 0, 0)
                        else
                            header:SetPoint("BOTTOMRIGHT", raidRoot, "BOTTOMRIGHT", 0, 0)
                        end
                    else
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
                    else
                        if grow == "DOWN" then
                            header:SetPoint("TOPLEFT", raidRoot, "TOPLEFT", 0, 0)
                        else
                            header:SetPoint("BOTTOMLEFT", raidRoot, "BOTTOMLEFT", 0, 0)
                        end
                    end
                end
            else
                if horizontal then
                    if groupGrow == "UP" then
                        if grow == "RIGHT" then
                            header:SetPoint("BOTTOMLEFT", prevHeader, "TOPLEFT", 0, groupSpacing)
                        else
                            header:SetPoint("BOTTOMRIGHT", prevHeader, "TOPRIGHT", 0, groupSpacing)
                        end
                    else
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
                    else
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
        _state.UpdateRaidGroupLabel(header, g, layout)
    end
end

function _state.RefreshAllRaidGroupLabels()
    if InCombatLockdown() then return end
    if not QUI_GF.raidGroupHeaders then return end
    local layout = GetLayoutSettings(true)
    for g, header in ipairs(QUI_GF.raidGroupHeaders) do
        _state.UpdateRaidGroupLabel(header, g, layout)
    end
end

local function CreateHeaders()
    local db = GetSettings()
    if not db then return end
    local position = db.position
    local partyRoot = EnsureAnchorFrame("party")
    local raidRoot = EnsureAnchorFrame("raid")

    local initConfigFunc = ns.QUI_GroupFrameIconLayout.HEADER_INIT_CONFIG_FUNC

    local partyHeader = CreateFrame("Frame", "QUI_PartyHeader", partyRoot, "SecureGroupHeaderTemplate")
    partyHeader:SetAttribute("template", "SecureUnitButtonTemplate,BackdropTemplate,PingableUnitFrameTemplate")
    partyHeader.QUI_OnChildCreated = QUI_GF.HeaderChildCreated
    partyHeader:SetAttribute("initialConfigFunction", initConfigFunc)
    QUI_GF.headers.party = partyHeader
    ConfigurePartyHeader(partyHeader)

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

    partyRoot:Show()
    partyHeader:SetAttribute("showPlayer", true)
    partyHeader:SetAttribute("showSolo", true)
    partyHeader:SetAttribute("startingIndex", -4)
    partyHeader:Show()
    partyHeader:SetAttribute("startingIndex", 1)
    partyHeader:Hide()
    partyRoot:Hide()
    ConfigurePartyHeader(partyHeader)

    local raidHeader = CreateFrame("Frame", "QUI_RaidHeader", raidRoot, "SecureGroupHeaderTemplate")
    raidHeader:SetAttribute("template", "SecureUnitButtonTemplate,BackdropTemplate,PingableUnitFrameTemplate")
    raidHeader.QUI_OnChildCreated = QUI_GF.HeaderChildCreated
    raidHeader:SetAttribute("initialConfigFunction", initConfigFunc)
    QUI_GF.headers.raid = raidHeader
    ConfigureRaidHeader(raidHeader)

    local raidCount = math_max(IsInRaid() and GetNumGroupMembers() or 25, 5)
    local raidW, raidH = CalculateHeaderSize(db, raidCount)
    raidHeader:SetSize(raidW, raidH)

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

    raidRoot:Show()
    raidHeader:SetAttribute("showPlayer", true)
    raidHeader:SetAttribute("showSolo", true)
    raidHeader:SetAttribute("startingIndex", -39)
    raidHeader:Show()
    raidHeader:SetAttribute("startingIndex", 1)
    raidHeader:Hide()
    raidRoot:Hide()
    ConfigureRaidHeader(raidHeader)

    raidRoot:Show()
    for g = 1, MAX_RAID_SECTION_HEADERS do
        local groupHeader = CreateFrame("Frame", "QUI_RaidGroup" .. g .. "Header", raidRoot, "SecureGroupHeaderTemplate")
        groupHeader:SetAttribute("template", "SecureUnitButtonTemplate,BackdropTemplate,PingableUnitFrameTemplate")
        groupHeader.QUI_OnChildCreated = QUI_GF.HeaderChildCreated
        groupHeader:SetAttribute("initialConfigFunction", initConfigFunc)
        groupHeader._raidGroupIndex = g
        QUI_GF.raidGroupHeaders[g] = groupHeader
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

        groupHeader:SetAttribute("showPlayer", true)
        groupHeader:SetAttribute("showSolo", true)
        groupHeader:SetAttribute("startingIndex", -39)
        groupHeader:Show()
        groupHeader:SetAttribute("startingIndex", 1)
        groupHeader:Hide()
        groupHeader:SetAttribute("showPlayer", false)
        groupHeader:SetAttribute("showSolo", false)
    end
    raidRoot:Hide()

    local selfHeader = CreateFrame("Frame", "QUI_SelfHeader", partyRoot, "SecureGroupHeaderTemplate")
    selfHeader:SetAttribute("template", "SecureUnitButtonTemplate,BackdropTemplate,PingableUnitFrameTemplate")
    selfHeader.QUI_OnChildCreated = QUI_GF.HeaderChildCreated
    selfHeader:SetAttribute("initialConfigFunction", initConfigFunc)
    QUI_GF.headers.self = selfHeader
    selfHeader:SetAttribute("showPlayer", true)
    selfHeader:SetAttribute("showParty", false)
    selfHeader:SetAttribute("showRaid", false)
    selfHeader:SetAttribute("showSolo", true)
    selfHeader:SetAttribute("maxColumns", 1)
    selfHeader:SetAttribute("unitsPerColumn", 1)

    local partyDims = db.party and db.party.dimensions
    local selfW = partyDims and partyDims.partyWidth or 200
    local selfH = partyDims and partyDims.partyHeight or 40
    selfHeader:SetAttribute("_initialAttributeNames", "unit-width,unit-height")
    selfHeader:SetAttribute("_initialAttribute-unit-width", selfW)
    selfHeader:SetAttribute("_initialAttribute-unit-height", selfH)
    selfHeader:SetSize(selfW, selfH)
    selfHeader:SetMovable(true)
    selfHeader:SetClampedToScreen(true)

    partyRoot:Show()
    selfHeader:SetAttribute("startingIndex", 1)
    selfHeader:Show()
    selfHeader:Hide()
    partyRoot:Hide()
end

local function InitSpotlightChildren(header, force)
    if not header then return 0 end

    local s = GetSettings()
    s = s and s.raid and s.raid.spotlight
    local fw = s and s.frameWidth or 180
    local fh = s and s.frameHeight or 36

    local initialized = 0
    local i = 1
    while true do
        local child = header:GetAttribute("child" .. i)
        if not child then break end
        if force then child._quiDecorated = nil end
        if not child._quiDecorated then
            child:SetSize(fw, fh)
            QUI_GF:InitializeHeaderChild(child)
            initialized = initialized + 1
        end
        i = i + 1
    end

    if initialized > 0 then
        local GFCC = ns.QUI_GroupFrameClickCast
        if GFCC and GFCC.RegisterFrame and GFCC:IsEnabled() then
            local j = 1
            while true do
                local child = header:GetAttribute("child" .. j)
                if not child then break end
                GFCC:RegisterFrame(child)
                j = j + 1
            end
        end
    end

    return initialized
end

local _parkedSpotlight = nil

local function ApplySpotlightHeaderConfig(container, header, spot)
    local w = spot.frameWidth or 180
    local h = spot.frameHeight or 36

    container:SetSize(w, h)
    container:ClearAllPoints()

    local faDB = QUI.db and QUI.db.profile and QUI.db.profile.frameAnchoring
    local saved = faDB and faDB.spotlightFrames
    if saved and saved.point then
        container:SetPoint(saved.point, UIParent, saved.relative or saved.point,
            saved.offsetX or 0, saved.offsetY or 0)
    else
        local pos = spot.position
        container:SetPoint("CENTER", UIParent, "CENTER",
            pos and pos.offsetX or -400, pos and pos.offsetY or 200)
    end

    local initConfigFunc = ns.QUI_GroupFrameIconLayout.HEADER_INIT_CONFIG_FUNC

    header:SetAttribute("template", "SecureUnitButtonTemplate,BackdropTemplate,PingableUnitFrameTemplate")
    header.QUI_OnChildCreated = QUI_GF.HeaderChildCreated
    header:SetAttribute("initialConfigFunction", initConfigFunc)
    header:SetAttribute("showRaid", true)
    header:SetAttribute("showParty", false)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT")

    header:SetAttribute("roleFilter", nil)
    header:SetAttribute("groupBy", nil)
    header:SetAttribute("groupingOrder", nil)
    header:SetAttribute("nameList", nil)

    local filterMode = spot.filterMode or "ROLE"
    if filterMode == "ROLE" then
        local roles = {}
        if spot.filterTank then roles[#roles + 1] = "TANK" end
        if spot.filterHealer then roles[#roles + 1] = "HEALER" end
        if #roles > 0 then
            header:SetAttribute("roleFilter", table.concat(roles, ","))
            header:SetAttribute("groupBy", "ASSIGNEDROLE")
            header:SetAttribute("groupingOrder", table.concat(roles, ","))
        end
    elseif filterMode == "NAME" then
        local nameList = spot.nameList
        if nameList and nameList ~= "" then
            header:SetAttribute("nameList", nameList)
        end
    end

    header:SetAttribute("_initialAttribute-unit-width", w)
    header:SetAttribute("_initialAttribute-unit-height", h)

    header:SetAttribute("point", nil)
    header:SetAttribute("xOffset", nil)
    header:SetAttribute("yOffset", nil)

    local spacing = spot.spacing or 2
    local grow = spot.growDirection or "DOWN"
    if grow == "DOWN" then
        header:SetAttribute("point", "TOP")
        header:SetAttribute("yOffset", -spacing)
    elseif grow == "UP" then
        header:SetAttribute("point", "BOTTOM")
        header:SetAttribute("yOffset", spacing)
    elseif grow == "RIGHT" then
        header:SetAttribute("point", "LEFT")
        header:SetAttribute("xOffset", spacing)
    elseif grow == "LEFT" then
        header:SetAttribute("point", "RIGHT")
        header:SetAttribute("xOffset", -spacing)
    end
end

local function CreateSpotlightHeader()
    local db = GetSettings()
    if not db then return end
    local spot = db.raid and db.raid.spotlight
    if not spot or not spot.enabled then return end
    if InCombatLockdown() and not _state.inInitSafeWindow then return end

    local container = QUI_GF.spotlightContainer
    local header = QUI_GF.spotlightHeader

    if not container and _parkedSpotlight then
        container = _parkedSpotlight.container
        header = _parkedSpotlight.header
        _parkedSpotlight = nil
    end

    if not container then
        container = CreateFrame("Frame", "QUI_SpotlightContainer", UIParent)
        container:SetMovable(true)
        container:SetClampedToScreen(true)
        header = CreateFrame("Frame", "QUI_SpotlightRTHeader", container, "SecureGroupHeaderTemplate")
    end

    ApplySpotlightHeaderConfig(container, header, spot)

    QUI_GF.spotlightHeader = header
    QUI_GF.spotlightContainer = container

    container:Show()
    header:Show()

    C_Timer.After(0, function()
        InitSpotlightChildren(QUI_GF.spotlightHeader, true)
    end)
end

local function DestroySpotlightHeader()
    if InCombatLockdown() then return end
    local header = QUI_GF.spotlightHeader
    local container = QUI_GF.spotlightContainer
    if header then
        header:Hide()
        QUI_GF.spotlightHeader = nil
    end
    if container then
        container:Hide()
        QUI_GF.spotlightContainer = nil
    end
    if container and header then
        _parkedSpotlight = { container = container, header = header }
    end
end

function QUI_GF:RecreateSpotlightHeader()
    if InCombatLockdown() then return end
    DestroySpotlightHeader()
    CreateSpotlightHeader()
end

local function GetPopulatedRaidGroups()
    local layout = GetLayoutSettings(true)
    local populated = {}
    for i = 1, GetNumGroupMembers() do
        local _, _, subgroup = GetRaidRosterInfo(i)
        if subgroup and _state.IsRaidSubgroupAllowed(subgroup, layout) then
            populated[subgroup] = (populated[subgroup] or 0) + 1
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

_state.GetRaidSortNameParts = function(name)
    if type(name) ~= "string" then
        return "", ""
    end

    local dash = string.find(name, "-", 1, true)
    if dash then
        return string.lower(name:sub(1, dash - 1)), string.lower(name:sub(dash + 1))
    end

    return string.lower(name), ""
end

_state.UnitNameMatchesRoster = function(unit, rosterName)
    if not unit or not rosterName then return false end

    local unitName, unitRealm = UnitName(unit)
    if IsSecretValue(unitName) then return false end -- @secret-policy: reject-secret-ids
    if not unitName then return false end
    if IsSecretValue(unitRealm) then unitRealm = nil end

    if string.find(rosterName, "-", 1, true) then
        if unitRealm and unitRealm ~= "" then
            return rosterName == (unitName .. "-" .. unitRealm)
        end
        return rosterName == unitName
    end

    return rosterName == unitName
end

_state.GetPlayerRosterNames = function()
    local playerName, playerRealm = UnitName("player")
    if IsSecretValue(playerName) then return nil, nil end -- @secret-policy: reject-secret-ids
    if not playerName then return nil, nil end
    if IsSecretValue(playerRealm) then playerRealm = nil end
    if playerRealm and playerRealm ~= "" then
        return playerName, playerName .. "-" .. playerRealm
    end
    return playerName, playerName
end

_state.IsPlayerRosterName = function(name, playerName, playerFullName)
    return name and (name == playerName or name == playerFullName)
end

_state.GetStableRaidRosterRole = function(name, unit, rosterRole, unitMatchesRoster, now)
    local role = NormalizeRaidRole(rosterRole)

    if role == "NONE" and unitMatchesRoster then
        local unitRole = NormalizeRaidRole(UnitGroupRolesAssigned(unit))
        if unitRole ~= "NONE" then
            role = unitRole
        end
    end

    local cache = _state.raidRosterSortCache
    local cached = cache[name]
    local inSettlingWindow = now
        and _state.lastGroupRosterUpdateTime
        and (now - _state.lastGroupRosterUpdateTime) <= 2.0

    if role == "NONE" and inSettlingWindow and cached and cached.role and cached.role ~= "NONE" then
        role = cached.role
    end

    if cached then
        cached.role = role
    else
        cache[name] = { role = role }
    end

    return role
end

local function CompareRaidSectionMembers(a, b, sortMethod, sortByRole, playerFirst)
    if playerFirst and a.isPlayer ~= b.isPlayer then
        return a.isPlayer
    end

    if sortByRole and a.role ~= b.role then
        return (RAID_SECTION_ROLE_PRIORITY[a.role] or 99) < (RAID_SECTION_ROLE_PRIORITY[b.role] or 99)
    end

    if sortMethod == "NAME" then
        if a.sortName ~= b.sortName then
            return a.sortName < b.sortName
        end
        if a.sortRealm ~= b.sortRealm then
            return a.sortRealm < b.sortRealm
        end
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
        wipe(_state.raidRosterSortCache)
        return {}
    end

    local db = GetSettings()
    local layout = GetLayoutSettings(true)
    if not db or not layout then
        return {}
    end

    local raidSelfFirst = GetRaidSelfFirst(db)
    local hiddenSet = _state.GetHiddenPlayerSet(db)
    local groupBy = layout.groupBy or "GROUP"
    local sortMethod = layout.sortMethod or "INDEX"
    local sortByRole = layout.sortByRole == true and groupBy ~= "ROLE"
    local playerSectionKey
    local sectionsByKey = {}
    local sections = {}
    local seenRosterNames = {}
    local playerName, playerFullName = _state.GetPlayerRosterNames()
    local now = GetTime()

    for i = 1, GetNumGroupMembers() do
        local unit = "raid" .. i
        local name, _, subgroup, _, _, rosterClassFile, _, _, _, _, _, rosterRole = GetRaidRosterInfo(i)
        if name and _state.IsRaidSubgroupAllowed(subgroup, layout)
            and not Helpers.NameListContains(hiddenSet, name) then
            seenRosterNames[name] = true

            local unitMatchesRoster = _state.UnitNameMatchesRoster(unit, name)
            local classFile = rosterClassFile
            -- @secret-policy: collapse-only — UNKNOWN section fallback
            if IsSecretValue(classFile) then classFile = nil end
            if not classFile and unitMatchesRoster then
                local _, unitClassFile = UnitClass(unit)
                if IsSecretValue(unitClassFile) then unitClassFile = nil end
                classFile = unitClassFile
            end
            classFile = classFile or "UNKNOWN"

            local role = _state.GetStableRaidRosterRole(name, unit, rosterRole, unitMatchesRoster, now)
            local sortName, sortRealm = _state.GetRaidSortNameParts(name)
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

            local isPlayer = _state.IsPlayerRosterName(name, playerName, playerFullName)
                or (unitMatchesRoster and _state.IsPlayerUnit(unit))
            table_insert(section.members, {
                name = name,
                index = i,
                subgroup = subgroup or 0,
                classFile = classFile,
                role = role,
                isPlayer = isPlayer,
                sortName = sortName,
                sortRealm = sortRealm,
            })

            if isPlayer then
                playerSectionKey = sectionKey
            end
        end
    end

    for name in pairs(_state.raidRosterSortCache) do
        if not seenRosterNames[name] then
            _state.raidRosterSortCache[name] = nil
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

local ApplyChildFrameLayout

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
        local mode = GetGroupMode()
        local raidVdb = db.raid or db
        local layout = raidVdb and raidVdb.layout
        local sections = _state.UseRaidNameListSections(db, layout) and GetRaidDisplaySections() or nil
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
                local hdrW, hdrH = CalculateRaidSectionHeaderSize(math_max(populated[g], 1), mode, layout)
                header:SetSize(hdrW, hdrH)
            else
                header:SetSize(1, 1)
            end
        end

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

    local selfHdr = QUI_GF.headers.self
    if selfHdr then
        local partyDims = db.party and db.party.dimensions
        local sw = partyDims and partyDims.partyWidth or 200
        local sh = partyDims and partyDims.partyHeight or 40
        _state.SetHeaderAttributeIfChanged(selfHdr, "_initialAttribute-unit-width", sw)
        _state.SetHeaderAttributeIfChanged(selfHdr, "_initialAttribute-unit-height", sh)
        selfHdr:SetSize(sw, sh)
        local child = selfHdr:GetAttribute("child1")
        if child then child:SetSize(sw, sh) end
        if not (_G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("partyFrames")) then
            selfHdr:ClearAllPoints()
            if partyHdr then
                selfHdr:SetPoint("BOTTOMLEFT", partyHdr, "TOPLEFT", 0, 4)
            end
        end
    end

    UpdateAnchorFrames()
end

local function ShowRaidGroupHeaders()
    if QUI_GF.headers.raid then QUI_GF.headers.raid:Hide() end

    local db = GetSettings()
    local layout = GetLayoutSettings(true)
    local useNameListSections = _state.UseRaidNameListSections(db, layout)
    local sections = ConfigureRaidGroupHeaders()
    local populated = useNameListSections and nil or GetPopulatedRaidGroups()

    for g, header in ipairs(QUI_GF.raidGroupHeaders) do
        if useNameListSections then
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

local function HideRaidGroupHeaders()
    for _, header in ipairs(QUI_GF.raidGroupHeaders) do
        if header then header:Hide() end
    end
end

_state.EnsureCombatVisibleRoots = function()
    local layoutMode = ns.QUI_LayoutMode
    local hidden = layoutMode and layoutMode._gameplayHidden
    local partyRoot = QUI_GF.anchorFrames and QUI_GF.anchorFrames.party
    if partyRoot and not (hidden and hidden.partyFrames) then
        partyRoot:SetAlpha(1)
    end

    local raidRoot = QUI_GF.anchorFrames and QUI_GF.anchorFrames.raid
    if raidRoot and not (hidden and hidden.raidFrames) then
        raidRoot:SetAlpha(1)
    end

    if QUI_GF.spotlightContainer and not (hidden and hidden.spotlightFrames) then
        QUI_GF.spotlightContainer:SetAlpha(1)
    end
end

local function UpdateHeaderVisibility(skipDeferredRefresh)
    if InCombatLockdown() and not _state.inInitSafeWindow then
        _state.EnsureCombatVisibleRoots()
        _pending.visibilityUpdate = true
        return
    end

    local db = GetSettings()
    if not db or not db.enabled then
        if QUI_GF.headers.party then QUI_GF.headers.party:Hide() end
        if QUI_GF.headers.raid then QUI_GF.headers.raid:Hide() end
        if QUI_GF.headers.self then QUI_GF.headers.self:Hide() end
        if QUI_GF.spotlightHeader then QUI_GF.spotlightHeader:Hide() end
        if QUI_GF.spotlightContainer then QUI_GF.spotlightContainer:Hide() end
        HideRaidGroupHeaders()
        UpdateAnchorFrames()
        return
    end

    if QUI_GF.testMode then
        UpdateAnchorFrames()
        return
    end

    local partySelfFirst = GetPartySelfFirst(db)
    local selfHeader = QUI_GF.headers.self
    local useRaidSections = UseRaidSectionHeaders(db)

    if QUI_GF.headers.party then ConfigurePartyHeader(QUI_GF.headers.party) end

    if useRaidSections then
    else
        if QUI_GF.headers.raid then ConfigureRaidHeader(QUI_GF.headers.raid) end
        HideRaidGroupHeaders()
    end

    if selfHeader then
        _state.SetHeaderAttributeIfChanged(selfHeader, "showSolo", partySelfFirst and true or false)
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

    if QUI_GF.spotlightContainer then
        if IsInRaid() then
            QUI_GF.spotlightContainer:Show()
            if QUI_GF.spotlightHeader then QUI_GF.spotlightHeader:Show() end
            local refreshReason = skipDeferredRefresh and "roster" or nil
            C_Timer.After(0.2, function()
                if InitSpotlightChildren(QUI_GF.spotlightHeader) > 0 then
                    RebuildUnitFrameMap()
                    QUI_GF:RefreshAllFrames(refreshReason)
                end
            end)
        else
            if QUI_GF.spotlightHeader then QUI_GF.spotlightHeader:Hide() end
            QUI_GF.spotlightContainer:Hide()
        end
    end

    local needsReveal = not _state.initialLayoutDone
    if needsReveal then
        for _, root in pairs(QUI_GF.anchorFrames) do
            root:SetAlpha(0)
        end
    end

    if skipDeferredRefresh then
        ApplyChildFrameLayout()
    end
    UpdateHeaderSizes()
    UpdateAnchorFrames()

    _pending.initSafe = false

    if skipDeferredRefresh then return end

    C_Timer.After(0, function()
        ApplyChildFrameLayout()
        RebuildUnitFrameMap()
        QUI_GF:RefreshAllFrames()
        UpdateAnchorFrames()

        if needsReveal then
            _state.initialLayoutDone = true
            for _, root in pairs(QUI_GF.anchorFrames) do
                root:SetAlpha(1)
            end
        end
    end)
end

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
            if not child._quiDecorated and (not inCombat or _state.inInitSafeWindow) then
                QUI_GF:InitializeHeaderChild(child)
            end
            local isRaidChild = child._isRaid and true or false
            if not inCombat then
                local cw, ch = isRaidChild and raidW or partyW, isRaidChild and raidH or partyH
                child:SetSize(cw, ch)
            end
            if child.healthBar and child.powerBar then
                local general = GetGeneralSettings(isRaidChild)
                local borderPx = general and general.borderSize or 1
                local borderSize = borderPx > 0 and (QUICore.Pixels and QUICore:Pixels(borderPx, child) or borderPx) or 0
                local powerSettings = GetPowerSettings(isRaidChild)
                local powerHeight = powerSettings and powerSettings.showPowerBar ~= false and
                    (QUICore.PixelRound and QUICore:PixelRound(powerSettings.powerBarHeight or 4, child) or 4) or 0

                local showForUnit
                local unit = QUI_GF.GetFrameUnit(child)
                if unit then
                    showForUnit = ShouldShowPowerForUnit(unit, isRaidChild) and true or false
                else
                    showForUnit = powerHeight > 0
                end
                ResizeHealthForPower(child, showForUnit)
                ApplyStatusBarTexture(child.healthBar)

                local vertFill = (GetHealthFillDirection(isRaidChild) == "VERTICAL")
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

    local partyW, partyH = GetFrameDimensions("party")
    local raidW, raidH = GetFrameDimensions(mode ~= "party" and mode or "small")

    local partyHeader = QUI_GF.headers.party
    if partyHeader then
        _state.SetHeaderAttributeIfChanged(partyHeader, "_initialAttribute-unit-width", partyW)
        _state.SetHeaderAttributeIfChanged(partyHeader, "_initialAttribute-unit-height", partyH)
    end
    local selfHeader = QUI_GF.headers.self
    if selfHeader then
        _state.SetHeaderAttributeIfChanged(selfHeader, "_initialAttribute-unit-width", partyW)
        _state.SetHeaderAttributeIfChanged(selfHeader, "_initialAttribute-unit-height", partyH)
    end
    local raidHeader = QUI_GF.headers.raid
    if raidHeader then
        _state.SetHeaderAttributeIfChanged(raidHeader, "_initialAttribute-unit-width", raidW)
        _state.SetHeaderAttributeIfChanged(raidHeader, "_initialAttribute-unit-height", raidH)
    end
    for _, header in ipairs(QUI_GF.raidGroupHeaders) do
        if header then
            _state.SetHeaderAttributeIfChanged(header, "_initialAttribute-unit-width", raidW)
            _state.SetHeaderAttributeIfChanged(header, "_initialAttribute-unit-height", raidH)
        end
    end

    ApplyChildFrameLayout()
    UpdateHeaderSizes()
end

local RANGE_SPELLS = {
    spec = {
        [250] = nil, [251] = nil, [252] = nil,
        [577] = nil, [581] = nil,
        [102] = 8936, [103] = 8936, [104] = 8936,
        [105] = 774,
        [1467] = 360995, [1468] = 360995, [1473] = 360995,
        [253] = nil, [254] = nil, [255] = nil,
        [62] = 1459, [63] = 1459, [64] = 1459,
        [268] = 116670, [269] = 116670, [270] = 116670,
        [65] = 19750, [66] = 19750, [70] = 19750,
        [256] = 17, [257] = 2061, [258] = 17,
        [259] = 57934, [260] = 57934, [261] = 57934,
        [262] = 8004, [263] = 8004, [264] = 8004,
        [265] = 5697, [266] = 5697, [267] = 5697,
        [71] = nil, [72] = nil, [73] = nil,
    },
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
    class = {
        PRIEST      = { 2061, 17 },
        PALADIN     = { 19750 },
        DRUID       = { 8936, 774 },
        SHAMAN      = { 8004 },
        MONK        = { 116670 },
        EVOKER      = { 360995, 361469 },
        MAGE        = { 1459 },
        WARLOCK     = { 5697 },
        ROGUE       = { 57934 },
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
    res = {
        PRIEST = 2006, PALADIN = 7328, DRUID = 50769,
        SHAMAN = 2008, MONK = 115178, EVOKER = 361227, DEATHKNIGHT = 61999,
    },
}

local _range = {
    playerClass = nil,
    spell = nil,
    hostileSpell = nil,
    resSpell = nil,
    cache = {},
    cacheTime = {},
    -- Unit tokens that are the player, resolved at roster-rebuild time so the
    -- in-combat range tick never depends on a possibly-secret UnitIsUnit.
    selfUnits = {},
}

local function ResolveRangeSpells()
    if not _range.playerClass then
        _range.playerClass = select(2, UnitClass("player"))
    end

    wipe(_range.cache)

    _range.spell = nil
    local specIndex = GetSpecialization and GetSpecialization()
    local specID = specIndex and GetSpecializationInfo and GetSpecializationInfo(specIndex)
    if specID and RANGE_SPELLS.spec[specID] then
        local spellID = RANGE_SPELLS.spec[specID]
        if spellID and IsPlayerSpell(spellID) then
            _range.spell = spellID
        end
    end

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

function _state.RefreshTrackedSlotAssist(unit, frames)
    local GFA = ns.QUI_GroupFrameAuras
    if not (GFA and GFA.TrackedAssistStale and GFA.UpdateStripContainers) then return end
    for i = 1, #frames do
        local frame = frames[i]
        if GFA.TrackedAssistStale(frame) then
            GFA.UpdateStripContainers(frame)
        end
    end
end

function _state.SweepTrackedSlotAssist()
    if not _state.cachedModuleEnabled then return end
    local map = QUI_GF.unitFrameMap
    if not map then return end
    for unit, frames in pairs(map) do
        _state.RefreshTrackedSlotAssist(unit, frames)
    end
end

local function CheckUnitRange(unit)
    if _range.selfUnits[unit] then return true end
    local isSelf = UnitIsUnit(unit, "player")
    if IsSecretValue(isSelf) then isSelf = nil end -- @secret-policy: reject-secret-value
    if isSelf then return true end
    if not UnitExists(unit) then return true end

    if UnitPhaseReason then
        -- @secret-policy: collapse-only — restricted phase treated as unphased so the range tick proceeds
        local phaseReason = UnitPhaseReason(unit)
        if IsSecretValue(phaseReason) then phaseReason = nil end
        if phaseReason ~= nil then
            return false
        end
    end

    local connected = UnitIsConnected(unit)
    if IsSecretValue(connected) then connected = true end
    if not connected then
        if not IsNPCPartyMember(unit) then return true end
    end

    local isDead = UnitIsDeadOrGhost(unit)
    if IsSecretValue(isDead) then isDead = false end

    local friendlyReturnedNil = false

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
    end

    if isDead and _range.resSpell then
        local result = C_Spell.IsSpellInRange(_range.resSpell, unit)
        if result ~= nil then return result end
    end

    if not InCombatLockdown() then
        return CheckInteractDistance(unit, 4) and true or false
    end

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

QUI_GF.CheckUnitRange = CheckUnitRange

-- Called when a frame leaves the dead/offline fade (rez, reconnect). The range
-- system only writes alpha on cached-answer transitions, so hand alpha back to
-- it explicitly: restore full alpha now, then forget the unit's cached answer
-- so the next tick re-applies the real range fade (<=1s) for every frame
-- showing this unit.
function _state.ReleaseLifeFade(frame, unit)
    local state = GetFrameState(frame)
    state.lifeFaded = nil
    state.outOfRange = nil
    state.inRange = nil
    if unit then
        _range.cache[unit] = nil
        _range.cacheTime[unit] = nil
    end
    frame:SetAlpha(1)
end

local function ApplyRangeAlpha(frame, inRange, outAlpha)
    if frame.SetAlphaFromBoolean then
        frame:SetAlphaFromBoolean(inRange, 1, outAlpha)
    else
        frame:SetAlpha(inRange and 1 or outAlpha)
    end
end

local function DoRangeCheck()
    local partyRange = GetRangeSettings(false)
    local raidRange = GetRangeSettings(true)
    if (not partyRange or partyRange.enabled == false) and (not raidRange or raidRange.enabled == false) then return end

    local now = GetTime()
    for unit, list in pairs(QUI_GF.unitFrameMap) do
        local lastEventTime = _range.cacheTime[unit]
        if not (lastEventTime and (now - lastEventTime) < 0.4) then
            local inRange = CheckUnitRange(unit)
            local cached = _range.cache[unit]
            local isSecret = issecretvalue and (issecretvalue(inRange) or issecretvalue(cached))
            local rangeChanged = isSecret or cached ~= inRange
            if rangeChanged then
                _range.cache[unit] = inRange
            end
            local GFA = ns.QUI_GroupFrameAuras
            for i = 1, #list do
                local frame = list[i]
                if frame and frame:IsShown() then
                    if rangeChanged and GFA and GFA.ApplyRangeGate then
                        GFA.ApplyRangeGate(frame, inRange)
                    end
                    local rangeSettings = GetRangeSettings(frame._isRaid)
                    if rangeSettings and rangeSettings.enabled ~= false then
                        local outAlpha = rangeSettings.outOfRangeAlpha or 0.4
                        local state = GetFrameState(frame)
                        if rangeChanged or state.outOfRange == nil then
                            state.outOfRange = true
                            state.inRange = inRange
                            -- Dead/offline fade owns alpha until ReleaseLifeFade
                            if not state.lifeFaded then
                                ApplyRangeAlpha(frame, inRange, outAlpha)
                            end
                        end
                    end
                end
            end
        end
    end
end

local function StartRangeCheck()
    if _state.rangeCheckTicker then return end
    local partyRange = GetRangeSettings(false)
    local raidRange = GetRangeSettings(true)
    if (not partyRange or partyRange.enabled == false) and (not raidRange or raidRange.enabled == false) then return end

    if not _range.spell and not _range.resSpell and not _range.hostileSpell then
        ResolveRangeSpells()
    end

    local interval = GetGroupSize() > 25 and 1.0 or 0.75
    _state.rangeCheckTicker = C_Timer.NewTicker(interval, DoRangeCheck)
end

local function GRU_DeferredWork()
    _state.gruDeferredPending = false
    RebuildUnitFrameMap()
    local playerGUID = UnitGUID("player")
    if IsSecretValue(playerGUID) then playerGUID = nil end
    wipe(_range.selfUnits)
    for unit, list in pairs(QUI_GF.unitFrameMap) do
        local guid = UnitGUID(unit)
        if IsSecretValue(guid) then guid = nil end
        if guid and playerGUID then
            if guid == playerGUID then
                _range.selfUnits[unit] = true
            end
        else
            -- @secret-policy: collapse-only — secret identity just skips the fast path
            local isSelf = UnitIsUnit(unit, "player")
            if IsSecretValue(isSelf) then isSelf = nil end
            if isSelf then
                _range.selfUnits[unit] = true
            end
        end
        for i = 1, #list do
            _state.unitGuidCache[list[i]] = guid
        end
    end
    wipe(_range.cache)
    wipe(_range.cacheTime)
    wipe(_state.cachedMarkers)
    wipe(powerThrottle)
    wipe(absorbThrottle)
    wipe(_state.healAbsorbThrottle)
    wipe(_state.healthThrottle)
    wipe(healPredThrottle)
    local GFA = ns.QUI_GroupFrameAuras
    if GFA and GFA.PruneAuraCache then GFA.PruneAuraCache() end
    UpdateHeaderSizes()
    QUI_GF:RefreshAllFrames("roster")
    StartRangeCheck()
    local PartyTargets = ns.QUI_GroupFramePartyTargets
    if PartyTargets then PartyTargets:Reanchor(QUI_GF) end
end

gruCoalesceFrame:SetScript("OnUpdate", function(self)
    self:Hide()
    UpdateHeaderVisibility(true)
    UpdateFrameScaling()
    UpdateSelectiveEvents()
    if not _state.gruDeferredPending then
        _state.gruDeferredPending = true
        C_Timer.After(0.2, GRU_DeferredWork)
    end
end)

local eventFrame = CreateFrame("Frame")

local function RefreshCachedEnabled()
    local db = GetSettings()
    _state.cachedModuleEnabled = db and db.enabled or false
end

local trailingPending = { health = {}, power = {}, absorb = {}, healAbsorb = {}, healPred = {} }
local trailingScheduled = { health = false, power = false, absorb = false, healAbsorb = false, healPred = false }
local trailingDrainers = {}

local function RunTrailingUpdate(family, frames)
    local n = #frames
    if family == "health" then
        for i = 1, n do UpdateHealth(frames[i]) end
    elseif family == "power" then
        for i = 1, n do UpdatePower(frames[i]) end
    elseif family == "absorb" then
        for i = 1, n do UpdateAbsorbs(frames[i]) end
    elseif family == "healAbsorb" then
        for i = 1, n do UpdateHealAbsorb(frames[i]) end
    else
        for i = 1, n do UpdateHealPrediction(frames[i]) end
    end
end

local function TrailingThrottleTable(family)
    if family == "health" then return _state.healthThrottle
    elseif family == "power" then return powerThrottle
    elseif family == "absorb" then return absorbThrottle
    elseif family == "healAbsorb" then return _state.healAbsorbThrottle
    else return healPredThrottle end
end

for _, family in ipairs({ "health", "power", "absorb", "healAbsorb", "healPred" }) do
    trailingDrainers[family] = function()
        trailingScheduled[family] = false
        local pending = trailingPending[family]
        if not _state.cachedModuleEnabled then wipe(pending) return end
        local throttle = TrailingThrottleTable(family)
        local now = GetTime()
        for unit in pairs(pending) do
            pending[unit] = nil
            local frames = QUI_GF.unitFrameMap[unit]
            if frames and UnitExists(unit) then
                throttle[unit] = now
                RunTrailingUpdate(family, frames)
            end
        end
    end
end

local function ScheduleTrailingDrain(family, unit)
    trailingPending[family][unit] = true
    if trailingScheduled[family] then return end
    trailingScheduled[family] = true
    C_Timer.After(THROTTLE_INTERVAL, trailingDrainers[family])
end

local function OnEvent(self, event, arg1, ...)
    if not QUI_GF.initialized then return end

    if event == "READY_CHECK" then
        if not _state.cachedModuleEnabled then return end
        if QUI_GF._readyCheckHideTimer then
            QUI_GF._readyCheckHideTimer:Cancel()
            QUI_GF._readyCheckHideTimer = nil
        end
        for _, list in pairs(QUI_GF.unitFrameMap) do
            for i = 1, #list do
                UpdateReadyCheck(list[i])
            end
        end
        return
    end

    if type(arg1) == "string" then
        local frames = QUI_GF.unitFrameMap[arg1] -- @secret-safe: READY_CHECK terminated above; arg1 is a plain unit token here

        if not frames then
            local p4 = arg1:sub(1, 4)
            if p4 == "part" or p4 == "raid" or arg1 == "player" then -- @secret-safe: READY_CHECK terminated above; arg1 is a plain unit token here
                local now = GetTime()
                if not QUI_GF.lastMapRebuild or (now - QUI_GF.lastMapRebuild) > 1.0 then
                    QUI_GF.lastMapRebuild = now
                    RebuildUnitFrameMap()
                    frames = QUI_GF.unitFrameMap[arg1] -- @secret-safe: READY_CHECK terminated above; arg1 is a plain unit token here
                end
            end
            if not frames then return end
        end

        if not _state.cachedModuleEnabled then return end
        local nFrames = #frames

        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            local pf = ns.QUI_PerfFlags
            if pf and pf.disabled and pf.disabled.health then return end
            if not UnitExists(arg1) then return end
            local now = GetTime()
            if (now - (_state.healthThrottle[arg1] or 0)) < THROTTLE_INTERVAL then
                ScheduleTrailingDrain("health", arg1)
                return
            end
            _state.healthThrottle[arg1] = now
            for i = 1, nFrames do UpdateHealth(frames[i]) end

        elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
            local now = GetTime()
            local last = powerThrottle[arg1] or 0
            if (now - last) < THROTTLE_INTERVAL then
                ScheduleTrailingDrain("power", arg1)
                return
            end
            powerThrottle[arg1] = now
            for i = 1, nFrames do UpdatePower(frames[i]) end

        elseif event == "UNIT_MAXPOWER" then
            for i = 1, nFrames do
                local frame = frames[i]
                frame._lastMaxPower = nil
                UpdatePower(frame)
            end

        elseif event == "UNIT_ABSORB_AMOUNT_CHANGED"
            or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED"
            or event == "UNIT_HEAL_PREDICTION" then
            local now = GetTime()
            local tbl = absorbThrottle
            if event == "UNIT_HEAL_PREDICTION" then
                tbl = healPredThrottle
            elseif event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
                tbl = _state.healAbsorbThrottle
            end
            local last = tbl[arg1] or 0
            if (now - last) < THROTTLE_INTERVAL then
                if event == "UNIT_HEAL_PREDICTION" then
                    ScheduleTrailingDrain("healPred", arg1)
                elseif event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
                    ScheduleTrailingDrain("healAbsorb", arg1)
                else
                    ScheduleTrailingDrain("absorb", arg1)
                end
                return
            end
            tbl[arg1] = now
            if event == "UNIT_ABSORB_AMOUNT_CHANGED" then
                for i = 1, nFrames do UpdateAbsorbs(frames[i]) end
            elseif event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
                for i = 1, nFrames do UpdateHealAbsorb(frames[i]) end
            else
                for i = 1, nFrames do UpdateHealPrediction(frames[i]) end
            end

        elseif event == "UNIT_NAME_UPDATE" then
            for i = 1, nFrames do
                UpdateName(frames[i])
                _state.UpdateLevelText(frames[i])
            end

        elseif event == "UNIT_LEVEL" then
            for i = 1, nFrames do _state.UpdateLevelText(frames[i]) end

        elseif event == "UNIT_THREAT_SITUATION_UPDATE" then
            for i = 1, nFrames do UpdateThreat(frames[i]) end

        elseif event == "UNIT_CONNECTION" or event == "UNIT_FLAGS" then
            for i = 1, nFrames do
                local frame = frames[i]
                UpdateConnection(frame)
                UpdateHealth(frame)
                UpdatePower(frame)
            end
            _state.RefreshTrackedSlotAssist(arg1, frames)

        elseif event == "UNIT_FACTION" then
            _state.RefreshTrackedSlotAssist(arg1, frames)

        elseif event == "UNIT_PHASE" then
            for i = 1, nFrames do UpdatePhaseIcon(frames[i]) end
            _state.RefreshTrackedSlotAssist(arg1, frames)

        elseif event == "INCOMING_RESURRECT_CHANGED" then
            wipe(_range.cache)
            for i = 1, nFrames do UpdateResurrection(frames[i]) end

        elseif event == "INCOMING_SUMMON_CHANGED" then
            for i = 1, nFrames do UpdateSummonPending(frames[i]) end

        elseif event == "READY_CHECK_CONFIRM" then
            for i = 1, nFrames do UpdateReadyCheck(frames[i]) end
        end
        return
    end

    if not _state.cachedModuleEnabled then return end

    if event == "GROUP_ROSTER_UPDATE" then
        _state.lastGroupRosterUpdateTime = GetTime()
        gruCoalesceFrame:Show()

    elseif event == "PLAYER_TARGET_CHANGED" then
        local prevList = QUI_GF._targetHighlightFrames
        if prevList then
            for i = 1, #prevList do
                local f = prevList[i]
                if f.targetHighlight then f.targetHighlight:Hide() end
            end
            wipe(prevList)
        else
            QUI_GF._targetHighlightFrames = {}
            prevList = QUI_GF._targetHighlightFrames
        end
        local targetUnit = UnitExists("target") and "target" or nil
        if targetUnit then
            for _, list in pairs(QUI_GF.unitFrameMap) do
                for i = 1, #list do
                    local frame = list[i]
                    local unit = QUI_GF.GetFrameUnit(frame)
                    if unit and _state.IsUnitTarget(unit) then
                        UpdateTargetHighlight(frame)
                        prevList[#prevList + 1] = frame
                    end
                end
            end
        end

    elseif event == "READY_CHECK_FINISHED" then
        if QUI_GF._readyCheckHideTimer then
            QUI_GF._readyCheckHideTimer:Cancel()
        end
        QUI_GF._readyCheckHideTimer = C_Timer.NewTimer(6, function()
            for _, list in pairs(QUI_GF.unitFrameMap) do
                for i = 1, #list do
                    local f = list[i]
                    if f.readyCheckIcon then
                        f.readyCheckIcon:Hide()
                    end
                end
            end
            QUI_GF._readyCheckHideTimer = nil
        end)

    elseif event == "RAID_TARGET_UPDATE" then
        local inCombat = InCombatLockdown()
        if inCombat then
            if _pending.markerUpdate then
                return
            end
            _pending.markerUpdate = true
            C_Timer.After(0, function()
                _pending.markerUpdate = false
                for _, list in pairs(QUI_GF.unitFrameMap) do
                    for i = 1, #list do UpdateTargetMarker(list[i]) end
                end
            end)
        else
            for unit, list in pairs(QUI_GF.unitFrameMap) do
                local marker = GetRaidTargetIndex(unit)
                local safeMarker = Helpers.SafeValue(marker, 0)
                if safeMarker ~= _state.cachedMarkers[unit] then
                    _state.cachedMarkers[unit] = safeMarker
                    for i = 1, #list do UpdateTargetMarker(list[i]) end
                end
            end
        end

    elseif event == "PARTY_LEADER_CHANGED" then
        for _, list in pairs(QUI_GF.unitFrameMap) do
            for i = 1, #list do
                UpdateLeaderIcon(list[i])
            end
        end

    elseif event == "PLAYER_REGEN_DISABLED" then
        _state.EnsureCombatVisibleRoots()
        wipe(_range.cache)
        wipe(_range.cacheTime)

    elseif event == "PLAYER_REGEN_ENABLED" then
        wipe(_range.cache)
        wipe(_range.cacheTime)

        if _pending.refreshSettings then
            _pending.refreshSettings = false
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
            for _, frame in ipairs(QUI_GF.allFrames) do
                frame:RegisterForClicks("AnyUp")
            end
            local GFCC = ns.QUI_GroupFrameClickCast
            if GFCC and GFCC:IsEnabled() then
                GFCC:RegisterAllFrames()
            end
        end
        if _pending.anchorUpdate then
            _pending.anchorUpdate = false
            UpdateAnchorFrames()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0.5, function()
            UpdateHeaderVisibility()
            UpdateFrameScaling(true)
            ResolveRangeSpells()
            _state.SweepTrackedSlotAssist()
        end)

    elseif event == "ZONE_CHANGED_NEW_AREA" then
        C_Timer.After(0.5, _state.SweepTrackedSlotAssist)

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "SPELLS_CHANGED" then
        ResolveRangeSpells()
    end
end

eventFrame:SetScript("OnEvent", OnEvent)

function _state.HandleRangeUpdate(unit)
    if not _state.cachedModuleEnabled then return end
    local frames = QUI_GF.unitFrameMap[unit]
    if not frames then return end
    local inRange = CheckUnitRange(unit)
    local cached = _range.cache[unit]
    local isSecret = issecretvalue and (issecretvalue(inRange) or issecretvalue(cached))
    if isSecret or cached ~= inRange then
        _range.cache[unit] = inRange
        local GFA = ns.QUI_GroupFrameAuras
        for i = 1, #frames do
            local frame = frames[i]
            if GFA and GFA.ApplyRangeGate then
                GFA.ApplyRangeGate(frame, inRange)
            end
            local rangeSettings = GetRangeSettings(frame._isRaid)
            if rangeSettings and rangeSettings.enabled ~= false then
                local outAlpha = rangeSettings.outOfRangeAlpha or 0.4
                local state = GetFrameState(frame)
                state.outOfRange = true
                state.inRange = inRange
                -- Dead/offline fade owns alpha until ReleaseLifeFade
                if not state.lifeFaded then
                    ApplyRangeAlpha(frame, inRange, outAlpha)
                end
            end
        end
    end
    _range.cacheTime[unit] = GetTime()
end

function _state.RegisterUnitEventsForUnit(unit)
    if not _state.unitEventRegistrationEnabled or not unit or not QUI_GF.unitFrameMap[unit] then return end

    local frame = _state.unitEventFrames[unit]
    if not frame then
        frame = CreateFrame("Frame")
        frame:Hide()
        frame:SetScript("OnEvent", OnEvent)
        _state.unitEventFrames[unit] = frame
    end

    local active = _state.unitEventActive
    for i = 1, #_state.unitEventList do
        local event = _state.unitEventList[i]
        if active[event] then
            frame:RegisterUnitEvent(event, unit)
        else
            frame:UnregisterEvent(event)
        end
    end

    local rangeListener = _state.rangeListenerFrames[unit]
    if not rangeListener then
        rangeListener = CreateFrame("Frame")
        rangeListener:Hide()
        rangeListener:SetScript("OnEvent", function()
            _state.HandleRangeUpdate(unit)
        end)
        _state.rangeListenerFrames[unit] = rangeListener
    end
    rangeListener:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", unit)
    _state.unitEventRegistered[unit] = true
end

function _state.UnregisterUnitEventsForUnit(unit)
    local frame = unit and _state.unitEventFrames[unit]
    local rangeListener = unit and _state.rangeListenerFrames[unit]
    if rangeListener then
        rangeListener:UnregisterEvent("UNIT_IN_RANGE_UPDATE")
    end
    _state.unitEventRegistered[unit] = nil
    if not frame then return end

    for i = 1, #_state.unitEventList do
        frame:UnregisterEvent(_state.unitEventList[i])
    end
end

function _state.UnregisterAllUnitEventFrames()
    for unit in pairs(_state.unitEventFrames) do
        _state.UnregisterUnitEventsForUnit(unit)
    end
end

function _state.RefreshUnitEventRegistrations(previousUnits)
    if not _state.unitEventRegistrationEnabled then return end

    for unit in pairs(_state.unitEventFrames) do
        if not QUI_GF.unitFrameMap[unit] then
            _state.UnregisterUnitEventsForUnit(unit)
        end
    end
    for unit in pairs(QUI_GF.unitFrameMap) do
        if not previousUnits or not previousUnits[unit] or not _state.unitEventRegistered[unit] then
            _state.RegisterUnitEventsForUnit(unit)
        end
    end
end

function _state.SetUnitEventActive(event, active)
    local enabled = active and true or nil
    if _state.unitEventActive[event] == enabled then return end

    _state.unitEventActive[event] = enabled
    if not _state.unitEventRegistrationEnabled then return end

    if enabled then
        for unit in pairs(QUI_GF.unitFrameMap) do
            _state.RegisterUnitEventsForUnit(unit)
        end
    else
        for _, frame in pairs(_state.unitEventFrames) do
            frame:UnregisterEvent(event)
        end
    end
end

do
local function SetupDebugInstrumentation()
    local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "GF_powerThrottle",    tbl = powerThrottle }
    mp[#mp + 1] = { name = "GF_absorbThrottle",   tbl = absorbThrottle }
    mp[#mp + 1] = { name = "GF_healAbsorbThrottle", tbl = _state.healAbsorbThrottle }
    mp[#mp + 1] = { name = "GF_healPredThrottle", tbl = healPredThrottle }
    mp[#mp + 1] = { name = "GF_unitGuidCache",  fn = function()
        local n = 0; for _ in pairs(_state.unitGuidCache) do n = n + 1 end; return n, 0
    end }
    mp[#mp + 1] = { name = "GF_cachedMarkers",  fn = function()
        local n = 0; for _ in pairs(_state.cachedMarkers) do n = n + 1 end; return n, 0
    end }
    mp[#mp + 1] = { name = "GF_unitFrameMap",   fn = function()
        local count, deep = 0, 0
        for _, list in pairs(QUI_GF.unitFrameMap) do
            count = count + 1
            if type(list) == "table" then deep = deep + #list end
        end
        return count, deep
    end }
    mp[#mp + 1] = { name = "GF_unitEventFrames",  fn = function()
        local n = 0; for _ in pairs(_state.unitEventFrames) do n = n + 1 end; return n, 0
    end }
    mp[#mp + 1] = { name = "GF_allFrames",      fn = function()
        return #QUI_GF.allFrames, 0
    end }
    mp[#mp + 1] = { name = "GF_backdropCache", tbl = Chrome.BackdropCache }
    mp[#mp + 1] = { name = "GF_fontCache", tbl = Chrome.FontPathCache }
    ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
    ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "GroupFrames", frame = eventFrame }
end
if ns.DebugRegister then
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation()
end
end

local function RegisterEvents()
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    if not _state.assistSweepTicker then
        _state.assistSweepTicker = C_Timer.NewTicker(5, _state.SweepTrackedSlotAssist)
    end

    _state.unitEventRegistrationEnabled = true
    _state.RefreshUnitEventRegistrations()

    eventFrame:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    eventFrame:RegisterEvent("UNIT_FLAGS")
    eventFrame:RegisterEvent("UNIT_PHASE")
    eventFrame:RegisterEvent("UNIT_FACTION")
    eventFrame:RegisterEvent("INCOMING_RESURRECT_CHANGED")
    eventFrame:RegisterEvent("INCOMING_SUMMON_CHANGED")

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
    _state.unitEventRegistrationEnabled = false
    _state.UnregisterAllUnitEventFrames()
end

UpdateSelectiveEvents = function()
    local mode = GetGroupMode()
    local isRaid = (mode ~= "party")

    local powerSettings = GetPowerSettings(isRaid)
    if mode == "large" and (not powerSettings or powerSettings.showPowerBar == false) then
        _state.SetUnitEventActive("UNIT_POWER_UPDATE", false)
        _state.SetUnitEventActive("UNIT_POWER_FREQUENT", false)
        _state.SetUnitEventActive("UNIT_MAXPOWER", false)
    else
        _state.SetUnitEventActive("UNIT_POWER_UPDATE", true)
        _state.SetUnitEventActive("UNIT_POWER_FREQUENT", false)
        _state.SetUnitEventActive("UNIT_MAXPOWER", true)
    end

    local vdb = GetVisualDB(isRaid)
    local absorbEnabled = vdb and vdb.absorbs and vdb.absorbs.enabled ~= false
    local healAbsorbEnabled = vdb and vdb.healAbsorbs and vdb.healAbsorbs.enabled ~= false
    local healPredEnabled = vdb and vdb.healPrediction and vdb.healPrediction.enabled ~= false
    _state.SetUnitEventActive("UNIT_ABSORB_AMOUNT_CHANGED", absorbEnabled and true or false)
    _state.SetUnitEventActive("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", healAbsorbEnabled and true or false)
    if healPredEnabled then
        _state.SetUnitEventActive("UNIT_HEAL_PREDICTION", true)
    else
        _state.SetUnitEventActive("UNIT_HEAL_PREDICTION", false)
    end

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

function QUI_GF:UpdateDispelOverlay(frame)
    UpdateDispelOverlay(frame)
end

function QUI_GF:RefreshAllFrames(_reason)
    local GFA = ns.QUI_GroupFrameAuras
    local rosterRefresh = _reason == "roster"
    if not rosterRefresh and GFA and GFA.InvalidateLayout then GFA:InvalidateLayout() end
    local auraCacheAvailable = GFA and GFA.ScanUnitAuras and GFA.RenderFrame

    for unit, list in pairs(self.unitFrameMap) do
        local auraScanned = false
        for i = 1, #list do
            local frame = list[i]
            if frame and frame:IsShown() then
                if frame.healthBar then ApplyStatusBarTexture(frame.healthBar) end
                if frame.healPredictionBar then ApplyStatusBarTexture(frame.healPredictionBar) end
                if frame.powerBar then ApplyStatusBarTexture(frame.powerBar) end
                local auraDirty = not rosterRefresh or frame._quiRosterAuraDirty
                local auraCacheRender = auraCacheAvailable and auraDirty
                    and (not GFA.HasActiveConsumersForFrame or GFA:HasActiveConsumersForFrame(frame))
                if auraCacheRender and not auraScanned then
                    GFA.ScanUnitAuras(unit)
                    auraScanned = true
                end
                UpdateFrame(frame)

                if auraDirty and auraCacheAvailable then
                    GFA:RenderFrame(frame)
                elseif auraDirty and not auraCacheAvailable and GFA and GFA.RefreshFrame then
                    GFA:RefreshFrame(frame)
                end
                if not rosterRefresh and GFA and GFA.UpdateStripContainers then
                    GFA.UpdateStripContainers(frame)
                end
                if rosterRefresh then
                    frame._quiRosterAuraDirty = nil
                end
            end
        end
    end

end

function QUI_GF:RefreshSettings()
    InvalidateCache()
    RefreshCachedEnabled()

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
            if db.raidPerSizePositions and db.raidSizeOffsets then
                local szOff = db.raidSizeOffsets[GetGroupMode()]
                if szOff then
                    raidOffX = raidOffX + (szOff.offsetX or 0)
                    raidOffY = raidOffY + (szOff.offsetY or 0)
                end
            end
            raidRoot:SetPoint("CENTER", UIParent, "CENTER", raidOffX, raidOffY)
        end
    end

    if self.headers.party then ConfigurePartyHeader(self.headers.party) end
    if UseRaidSectionHeaders(db) then
        ConfigureRaidGroupHeaders()
    else
        if self.headers.raid then ConfigureRaidHeader(self.headers.raid) end
    end
    if self.headers.self then
        local partySelfFirst = GetPartySelfFirst(db)
        self.headers.self:SetAttribute("showSolo", partySelfFirst and true or false)
    end

    for _, frame in pairs(self.allFrames) do
        frame._quiDecorated = false
        frame._lastBackdropColorR = nil
        frame._lastBackdropColorG = nil
        frame._lastBackdropColorB = nil
        frame._lastBackdropColorA = nil
        frame._lastHealthBarAlpha = nil
        frame._lastHealthColorR = nil
        frame._lastHealthColorG = nil
        frame._lastHealthColorB = nil
        frame._lastHealthColorA = nil
    end
    wipe(self.allFrames)

    local function ClearDecoratedFlags(header)
        if not header then return end
        local i = 1
        while true do
            local child = header:GetAttribute("child" .. i)
            if not child then break end
            child._quiDecorated = false
            child._lastBackdropColorR = nil
            child._lastBackdropColorG = nil
            child._lastBackdropColorB = nil
            child._lastBackdropColorA = nil
            child._lastHealthBarAlpha = nil
            child._lastHealthColorR = nil
            child._lastHealthColorG = nil
            child._lastHealthColorB = nil
            child._lastHealthColorA = nil
            i = i + 1
        end
    end
    for _, headerKey in ipairs({"party", "raid", "self"}) do
        ClearDecoratedFlags(self.headers[headerKey])
    end
    for _, header in ipairs(self.raidGroupHeaders) do
        ClearDecoratedFlags(header)
    end

    UpdateHeaderVisibility()
    UpdateFrameScaling(true)
    UpdateHeaderSizes()
    UpdateSelectiveEvents()

    if not InCombatLockdown() then
        self:RefreshAllFrames()
    end

    _state.RefreshAllRaidGroupLabels()

    local PartyTargets = ns.QUI_GroupFramePartyTargets
    if PartyTargets then PartyTargets:Configure(self) end
end

local function ApplyHUDLayering()
    local profile = QUI.db and QUI.db.profile
    local layering = profile and profile.hudLayering
    local level = layering and layering.groupFrames or 4

    if QUICore.GetHUDFrameLevel then
        local frameLevel = QUICore:GetHUDFrameLevel(level)
        for _, headerKey in ipairs({"party", "raid", "self"}) do
            local header = QUI_GF.headers[headerKey]
            if header then
                ns.SafeCallMethod("sink-forward", header, "SetFrameLevel", frameLevel)
            end
        end
        for _, header in ipairs(QUI_GF.raidGroupHeaders) do
            if header then
                ns.SafeCallMethod("sink-forward", header, "SetFrameLevel", frameLevel)
            end
        end
    end
end

function QUI_GF:Initialize()
    local db = GetSettings()
    if not db or not db.enabled then return end

    _state.inInitSafeWindow = true
    _state.initialLayoutDone = false

    CreateHeaders()

    CreateSpotlightHeader()

    RegisterEvents()

    ApplyHUDLayering()

    UpdateHeaderVisibility()
    UpdateFrameScaling(true)

    ResolveRangeSpells()
    StartRangeCheck()

    self.initialized = true
    RefreshCachedEnabled()

    local GFCC = ns.QUI_GroupFrameClickCast
    if GFCC then
        GFCC:Initialize()
        if GFCC:IsEnabled() then
            GFCC:RegisterAllFrames()
        end
    end

    if ns.QUI_GroupFrameBlizzard and ns.QUI_GroupFrameBlizzard.HideBlizzardFrames then
        ns.QUI_GroupFrameBlizzard:HideBlizzardFrames()
    end

    _state.inInitSafeWindow = false
end

function QUI_GF:Disable()
    _state.cachedModuleEnabled = false
    UnregisterEvents()
    -- slot — see QUI_TEST_EXTRACT ApplyOverlayBar note in task-2-report.md)
    if _state.rangeCheckTicker then
        _state.rangeCheckTicker:Cancel()
        _state.rangeCheckTicker = nil
    end
    if _state.assistSweepTicker then
        _state.assistSweepTicker:Cancel()
        _state.assistSweepTicker = nil
    end
    wipe(_range.cache)
    wipe(_range.cacheTime)

    local PartyTargets = ns.QUI_GroupFramePartyTargets
    if PartyTargets then PartyTargets:Teardown() end

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

    if self.spotlightHeader then self.spotlightHeader:Hide() end
    if self.spotlightContainer then self.spotlightContainer:Hide() end

    wipe(self.unitFrameMap)
    self.initialized = false

    if ns.QUI_GroupFrameBlizzard and ns.QUI_GroupFrameBlizzard.RestoreBlizzardFrames then
        ns.QUI_GroupFrameBlizzard:RestoreBlizzardFrames()
    end
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")

initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        self:UnregisterEvent("ADDON_LOADED")
        QUI_GF:Initialize()
    end
end)

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

_G.QUI_RefreshGroupFrames = function()
    QUI_GF:RefreshSettings()
    local editMode = ns.QUI_GroupFrameEditMode
    if editMode and editMode.RefreshTestMode then
        editMode:RefreshTestMode()
    end
end

ns.QUI_RefreshGroupFrameAuras = function()
    if QUI_GF and QUI_GF.RefreshAllFrames then
        QUI_GF:RefreshAllFrames("auraContext")
    end
    if _G.QUI_RefreshGroupFramePreview then
        _G.QUI_RefreshGroupFramePreview()
    end
end

if ns.Registry then
    ns.Registry:Register("groupframes", {
        refresh = _G.QUI_RefreshGroupFrames,
        priority = 20,
        group = "frames",
        importCategories = { "groupFrames" },
    })
    ns.Registry:Register("groupframesSkin", {
        refresh = _G.QUI_RefreshGroupFrames,
        priority = 20,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end
