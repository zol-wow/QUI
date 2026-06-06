--[[
    QUI Group Frames - Parent
    Defines shared state/helpers. Update logic lives in groupframes_* satellites.
]]

local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local LSM = ns.LSM
local Helpers = ns.Helpers
local IsSecretValue = Helpers.IsSecretValue
local SafeValue = Helpers.SafeValue
local SafeToNumber = Helpers.SafeToNumber
local ApplyCooldownFromAura = Helpers.ApplyCooldownFromAura
local GetDB = Helpers.CreateDBGetter("quiGroupFrames")

local type = type
local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local tostring = tostring
local select = select
local CreateFrame = CreateFrame
local UnitExists = UnitExists
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsConnected = UnitIsConnected
local UnitIsGhost = UnitIsGhost
local UnitClass = UnitClass
local UnitName = UnitName
local UnitIsPlayer = UnitIsPlayer
local UnitIsUnit = UnitIsUnit
local GetNumGroupMembers = GetNumGroupMembers
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local math_min = math.min
local math_max = math.max
local math_ceil = math.ceil

local QUI_GF = {}
ns.QUI_GroupFrames = QUI_GF
_G.QUI_GroupFrames = QUI_GF
QUI_GF._ = {}
local _ = QUI_GF._

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
    lastGroupRosterUpdateTime = 0,
    raidRosterSortCache = {},
    unitEventRegistrationEnabled = false,
    unitEventFrames = {},
    unitEventActive = {
        UNIT_HEALTH = true,
        UNIT_MAXHEALTH = true,
        UNIT_POWER_UPDATE = true,
        UNIT_MAXPOWER = true,
        UNIT_ABSORB_AMOUNT_CHANGED = true,
        UNIT_HEAL_ABSORB_AMOUNT_CHANGED = true,
        UNIT_HEAL_PREDICTION = true,
        UNIT_NAME_UPDATE = true,
        UNIT_CONNECTION = true,
    },
    unitEventList = {
        "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT",
        "UNIT_MAXPOWER", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
        "UNIT_HEAL_PREDICTION", "UNIT_NAME_UPDATE", "UNIT_CONNECTION",
    },
    defaultColors = {
        darkHealth = { 0.15, 0.15, 0.15, 1 },
        powerBar = { 0.2, 0.4, 0.8, 1 },
        healAbsorb = { 0.5, 0.1, 0.1, 1 },
        threat = { 1, 0, 0, 0.8 },
        targetHighlight = { 1, 1, 1, 0.6 },
        dispelFallback = { 0.2, 0.6, 1.0, 1 },
        darkModeBg = { 0.25, 0.25, 0.25, 1 },
        frameBg = { 0.1, 0.1, 0.1, 0.9 },
        healPrediction = { 0.2, 1, 0.2, 1 },
    },
    backdropReapplyInterval = 0.5,
}
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
local COLORS = {
    BLACK   = { 0, 0, 0, 1 },
    WHITE   = { 1, 1, 1, 1 },
    DEAD    = { 0.5, 0.5, 0.5, 1 },
    OFFLINE = { 0.4, 0.4, 0.4, 1 },
    GHOST   = { 0.6, 0.6, 0.6, 1 },
}

local frameState, GetFrameState = Helpers.CreateStateTable()
local _fontCache = {}
local _backdropCache = {}

local function SetupDebugInstrumentation()
    local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "GF_fontCache", tbl = _fontCache }
    mp[#mp + 1] = { name = "GF_backdropCache", tbl = _backdropCache }
    mp[#mp + 1] = { name = "GF_unitGuidCache", fn = function() local n = 0; for _ in pairs(_state.unitGuidCache) do n = n + 1 end; return n, 0 end }
    mp[#mp + 1] = { name = "GF_cachedMarkers", fn = function() local n = 0; for _ in pairs(_state.cachedMarkers) do n = n + 1 end; return n, 0 end }
    mp[#mp + 1] = { name = "GF_unitFrameMap", fn = function() local count, deep = 0, 0; for _, list in pairs(QUI_GF.unitFrameMap) do count = count + 1; if type(list) == "table" then deep = deep + #list end end; return count, deep end }
    mp[#mp + 1] = { name = "GF_unitEventFrames", fn = function() local n = 0; for _ in pairs(_state.unitEventFrames) do n = n + 1 end; return n, 0 end }
    mp[#mp + 1] = { name = "GF_allFrames", fn = function() return #QUI_GF.allFrames, 0 end }
end

if ns.DebugRegister then
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation()
end

local RAID_SECTION_ROLE_ORDER = { "TANK", "HEALER", "DAMAGER", "NONE" }
local RAID_SECTION_CLASS_ORDER = {
    "WARRIOR", "DEATHKNIGHT", "PALADIN", "MONK", "PRIEST", "SHAMAN", "DRUID",
    "ROGUE", "MAGE", "WARLOCK", "HUNTER", "DEMONHUNTER", "EVOKER",
}
local RAID_SECTION_ROLE_PRIORITY = {}
local RAID_SECTION_CLASS_PRIORITY = {}
for i, role in ipairs(RAID_SECTION_ROLE_ORDER) do RAID_SECTION_ROLE_PRIORITY[role] = i end
for i, classFile in ipairs(RAID_SECTION_CLASS_ORDER) do RAID_SECTION_CLASS_PRIORITY[classFile] = i end
local MAX_RAID_SECTION_HEADERS = #RAID_SECTION_CLASS_ORDER

local function AddFrameToMap(unit, frame)
    if not unit or not frame then return end
    local list = QUI_GF.unitFrameMap[unit]
    if list then
        for i = 1, #list do if list[i] == frame then return end end
        list[#list + 1] = frame
    else
        QUI_GF.unitFrameMap[unit] = { frame }
        if _state.RegisterUnitEventsForUnit then _state.RegisterUnitEventsForUnit(unit) end
    end
end
local function RemoveFrameFromMap(unit, frame)
    if not unit or not frame then return end
    local list = QUI_GF.unitFrameMap[unit]
    if not list then return end
    for i = #list, 1, -1 do if list[i] == frame then table.remove(list, i) end end
    if #list == 0 then
        QUI_GF.unitFrameMap[unit] = nil
        if _state.UnregisterUnitEventsForUnit then _state.UnregisterUnitEventsForUnit(unit) end
    end
end
QUI_GF.AddFrameToMap = AddFrameToMap
QUI_GF.RemoveFrameFromMap = RemoveFrameFromMap

local function GetCachedBackdrop(bgFile, edgeFile, edgeSize)
    local key = (bgFile or "") .. "|" .. (edgeFile or "") .. "|" .. (edgeSize or 0)
    local bd = _backdropCache[key]
    if not bd then
        bd = { bgFile = bgFile, edgeFile = edgeFile or nil, edgeSize = edgeSize and edgeSize > 0 and edgeSize or nil }
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
    if center then center:SetVertexColor(r, g, b, a) end
end

local function GetSettings() return GetDB() end
local function GetPartySelfFirst(db) db = db or GetSettings(); if not db then return false end; if db.partySelfFirst ~= nil then return db.partySelfFirst == true end; return db.selfFirst == true end
local function GetRaidSelfFirst(db) db = db or GetSettings(); if not db then return false end; if db.raidSelfFirst ~= nil then return db.raidSelfFirst == true end; return db.selfFirst == true end
local function IsMultiHeaderMode() local db = GetDB(); if not db then return false end; local raidVdb = db.raid or db; local raidLayout = raidVdb and raidVdb.layout; local groupBy = raidLayout and raidLayout.groupBy or "GROUP"; return groupBy == "GROUP" end
local function UseRaidSectionHeaders(db) db = db or GetSettings(); if not db then return false end; local raidVdb = db.raid or db; local layout = raidVdb and raidVdb.layout; return IsMultiHeaderMode() or GetRaidSelfFirst(db) or (layout and layout.limitGroupsByRaidSize == true) end
local function GetLayoutGrowDirection(layout, fallback)
    local grow = layout and layout.growDirection
    if grow == "UP" or grow == "DOWN" or grow == "LEFT" or grow == "RIGHT" then return grow end
    local orientation = layout and layout.orientation
    if orientation == "HORIZONTAL" then return "RIGHT" elseif orientation == "VERTICAL" then return "DOWN" end
    return fallback or "DOWN"
end
local function GetRaidColumnAnchorPoint(layout, grow) if grow == "LEFT" or grow == "RIGHT" then return "TOP" end; return layout and layout.groupGrowDirection == "LEFT" and "RIGHT" or "LEFT" end
local function GetVisualDB(isRaid)
    if isRaid then if _state.cachedVDB_raid then return _state.cachedVDB_raid end else if _state.cachedVDB_party then return _state.cachedVDB_party end end
    local db = GetDB(); if not db then return nil end
    if isRaid then _state.cachedVDB_raid = db.raid or db; return _state.cachedVDB_raid end
    _state.cachedVDB_party = db.party or db; return _state.cachedVDB_party
end
local function GetGeneralSettings(isRaid) local vdb = GetVisualDB(isRaid); return vdb and vdb.general end
local function GetLayoutSettings(isRaid) local vdb = GetVisualDB(isRaid); return vdb and vdb.layout end
local function GetDimensionSettings(isRaid) local vdb = GetVisualDB(isRaid); return vdb and vdb.dimensions end
local function GetHealthSettings(isRaid) local vdb = GetVisualDB(isRaid); return vdb and vdb.health end
local function GetHealthFillDirection(isRaid) local vdb = GetVisualDB(isRaid); local h = vdb and vdb.health; return h and h.healthFillDirection or "HORIZONTAL" end
local function GetPowerSettings(isRaid) local vdb = GetVisualDB(isRaid); return vdb and vdb.power end
local function GetNameSettings(isRaid) local vdb = GetVisualDB(isRaid); return vdb and vdb.name end
local function GetIndicatorSettings(isRaid) local vdb = GetVisualDB(isRaid); return vdb and vdb.indicators end
local function GetHealerSettings(isRaid) local vdb = GetVisualDB(isRaid); return vdb and vdb.healer end
local function GetRangeSettings(isRaid) local vdb = GetVisualDB(isRaid); return vdb and vdb.range end
local function GetPortraitSettings(isRaid) local vdb = GetVisualDB(isRaid); return vdb and vdb.portrait end

_state.GetRaidGroupLimit = function(layout) if not layout or layout.limitGroupsByRaidSize ~= true then return 8 end; local difficultyID = _G.GetInstanceInfo and select(3, _G.GetInstanceInfo()); return difficultyID == 16 and 4 or 6 end
_state.GetRaidGroupFilterString = function(layout) local limit = _state.GetRaidGroupLimit(layout); if limit == 4 then return "1,2,3,4" elseif limit == 6 then return "1,2,3,4,5,6" end; return "1,2,3,4,5,6,7,8" end
_state.IsRaidSubgroupAllowed = function(subgroup, layout) local limit = _state.GetRaidGroupLimit(layout); if limit >= 8 then return true end; subgroup = tonumber(subgroup); return subgroup ~= nil and subgroup >= 1 and subgroup <= limit end
_state.UseRaidNameListSections = function(db, layout) db = db or GetSettings(); if not layout and db then local raidVdb = db.raid or db; layout = raidVdb and raidVdb.layout end; if GetRaidSelfFirst(db) then return true end; return layout and layout.limitGroupsByRaidSize == true and (layout.groupBy or "GROUP") ~= "GROUP" end

local function GetFontPath(isRaid) if _fontCache.fontPath then return _fontCache.fontPath end; local general = GetGeneralSettings(isRaid); local fontName = general and general.font or "Quazii"; _fontCache.fontPath = LSM:Fetch("font", fontName) or "Fonts\\FRIZQT__.TTF"; return _fontCache.fontPath end
local function GetFontOutline(isRaid) if _fontCache.fontOutline then return _fontCache.fontOutline end; local general = GetGeneralSettings(isRaid); _fontCache.fontOutline = general and general.fontOutline or "OUTLINE"; return _fontCache.fontOutline end
local function GetTexturePath(textureName)
    if not textureName then if _fontCache.texturePath then return _fontCache.texturePath end; local general = GetGeneralSettings(); textureName = general and general.texture or "Quazii v5" end
    local texturePath = LSM and LSM:Fetch("statusbar", textureName, true)
    if not texturePath and textureName and textureName:find("[/\\]") then texturePath = textureName end
    if not _fontCache.texturePath then _fontCache.texturePath = texturePath end
    return texturePath or "Interface\\Buttons\\WHITE8X8"
end
local function ApplyStatusBarTexture(statusBar, textureName)
    if not statusBar then return end
    statusBar:SetStatusBarTexture(GetTexturePath(textureName))
    local tex = statusBar:GetStatusBarTexture()
    if tex then tex:SetTexCoord(0, 1, 0, 1); if tex.SetHorizTile then tex:SetHorizTile(false) end; if tex.SetVertTile then tex:SetVertTile(false) end end
end
local function InvalidateCache() wipe(_fontCache); _state.cachedVDB_party = nil; _state.cachedVDB_raid = nil; if _.InvalidateDispelColors then _.InvalidateDispelColors() end end

local ANCHOR_MAP = {
    LEFT={ point="LEFT", leftPoint="LEFT", rightPoint="RIGHT", justify="LEFT", justifyV="MIDDLE" }, RIGHT={ point="RIGHT", leftPoint="LEFT", rightPoint="RIGHT", justify="RIGHT", justifyV="MIDDLE" }, CENTER={ point="CENTER", leftPoint="LEFT", rightPoint="RIGHT", justify="CENTER", justifyV="MIDDLE" },
    TOPLEFT={ point="TOPLEFT", leftPoint="TOPLEFT", rightPoint="TOPRIGHT", justify="LEFT", justifyV="TOP" }, TOPRIGHT={ point="TOPRIGHT", leftPoint="TOPLEFT", rightPoint="TOPRIGHT", justify="RIGHT", justifyV="TOP" }, TOP={ point="TOP", leftPoint="TOPLEFT", rightPoint="TOPRIGHT", justify="CENTER", justifyV="TOP" },
    BOTTOMLEFT={ point="BOTTOMLEFT", leftPoint="BOTTOMLEFT", rightPoint="BOTTOMRIGHT", justify="LEFT", justifyV="BOTTOM" }, BOTTOMRIGHT={ point="BOTTOMRIGHT", leftPoint="BOTTOMLEFT", rightPoint="BOTTOMRIGHT", justify="RIGHT", justifyV="BOTTOM" }, BOTTOM={ point="BOTTOM", leftPoint="BOTTOMLEFT", rightPoint="BOTTOMRIGHT", justify="CENTER", justifyV="BOTTOM" },
}
local function GetTextAnchorInfo(anchorName) return ANCHOR_MAP[anchorName] or ANCHOR_MAP.LEFT end
local function GetGroupSize() if IsInRaid() then return GetNumGroupMembers() elseif IsInGroup() then return GetNumGroupMembers() end; return 0 end
local function GetGroupMode() if IsInRaid() then local size = GetNumGroupMembers(); if size > 25 then return "large" end; if size > 15 then return "medium" end; return "small" end; return "party" end
local function GetFrameDimensions(mode) local isRaid = mode ~= "party"; local dims = GetDimensionSettings(isRaid); if not dims then return 200, 40 end; if mode == "party" then return dims.partyWidth or 200, dims.partyHeight or 40 elseif mode == "small" then return dims.smallRaidWidth or 180, dims.smallRaidHeight or 36 elseif mode == "medium" then return dims.mediumRaidWidth or 160, dims.mediumRaidHeight or 30 elseif mode == "large" then return dims.largeRaidWidth or 140, dims.largeRaidHeight or 24 end; return 200, 40 end
local function CalculateHeaderSize(db, memberCount)
    if not db or not memberCount or memberCount <= 0 then return 100, 40 end
    local isRaid = memberCount > 5
    local vdb = isRaid and (db.raid or db) or (db.party or db)
    local layout = vdb.layout or (isRaid and db.raidLayout or db.partyLayout) or db.layout
    local spacing = layout and layout.spacing or 2
    local groupSpacing = layout and layout.groupSpacing or 10
    local grow = GetLayoutGrowDirection(layout, "DOWN")
    local mode = memberCount <= 5 and "party" or (memberCount <= 15 and "small" or (memberCount <= 25 and "medium" or "large"))
    local w, h = GetFrameDimensions(mode)
    local groupBy = layout and layout.groupBy or "GROUP"
    local isFlat = groupBy == "NONE"
    local framesPerGroup = isFlat and (layout and layout.unitsPerFlat or 5) or 5
    local numGroups = math_ceil(memberCount / framesPerGroup)
    local framesInTallestGroup = math_min(memberCount, framesPerGroup)
    local colSpacing = isFlat and spacing or groupSpacing
    if grow == "LEFT" or grow == "RIGHT" then
        return math_max(framesInTallestGroup * w + (framesInTallestGroup - 1) * spacing, 100), math_max(numGroups * h + (numGroups - 1) * colSpacing, 40)
    end
    return math_max(numGroups * w + (numGroups - 1) * colSpacing, 100), math_max(framesInTallestGroup * h + (framesInTallestGroup - 1) * spacing, 40)
end

local function ShowUnitTooltip(frame) local general = GetGeneralSettings(frame._isRaid); if not general or general.showTooltips == false then return end; local unit = frame.unit; if not unit or not UnitExists(unit) then return end; GameTooltip:SetOwner(frame, "ANCHOR_RIGHT"); GameTooltip:SetUnit(unit); GameTooltip:Show() end
local function HideUnitTooltip() GameTooltip:Hide() end
local function IsNPCPartyMember(unit) return UnitExists(unit) and not UnitIsPlayer(unit) end
local function NormalizeUnitFlag(value, fallback) if IsSecretValue(value) then return fallback or false end; return value and true or false end
local function GetUnitLifeState(unit) local isConnected = NormalizeUnitFlag(UnitIsConnected(unit), true); if not isConnected and IsNPCPartyMember(unit) then isConnected = true end; local isDeadOrGhost = NormalizeUnitFlag(UnitIsDeadOrGhost(unit), false); local isGhost = isDeadOrGhost and NormalizeUnitFlag(UnitIsGhost(unit), false) or false; return isConnected, isDeadOrGhost, isGhost end

QUI_GF.GetVisualDB = GetVisualDB
QUI_GF.CalculateHeaderSize = CalculateHeaderSize

_.QUICore, _.Helpers = QUICore, Helpers
_.IsSecretValue, _.SafeValue, _.SafeToNumber = IsSecretValue, SafeValue, SafeToNumber
_.ApplyCooldownFromAura = ApplyCooldownFromAura
_.state, _.pending, _.COLORS = _state, _pending, COLORS
_.RAID_CLASS_COLORS = RAID_CLASS_COLORS
_.RAID_SECTION_ROLE_PRIORITY, _.RAID_SECTION_CLASS_PRIORITY = RAID_SECTION_ROLE_PRIORITY, RAID_SECTION_CLASS_PRIORITY
_.MAX_RAID_SECTION_HEADERS = MAX_RAID_SECTION_HEADERS
_.AddFrameToMap, _.RemoveFrameFromMap = AddFrameToMap, RemoveFrameFromMap
_.GetFrameState = GetFrameState
_.GetCachedBackdrop, _.EnsureBackdrop, _.SetBackdropFillColor = GetCachedBackdrop, EnsureBackdrop, SetBackdropFillColor
_.GetSettings, _.GetPartySelfFirst, _.GetRaidSelfFirst = GetSettings, GetPartySelfFirst, GetRaidSelfFirst
_.IsMultiHeaderMode, _.UseRaidSectionHeaders = IsMultiHeaderMode, UseRaidSectionHeaders
_.GetLayoutGrowDirection, _.GetRaidColumnAnchorPoint = GetLayoutGrowDirection, GetRaidColumnAnchorPoint
_.GetVisualDB, _.GetGeneralSettings, _.GetLayoutSettings = GetVisualDB, GetGeneralSettings, GetLayoutSettings
_.GetDimensionSettings, _.GetHealthSettings, _.GetHealthFillDirection = GetDimensionSettings, GetHealthSettings, GetHealthFillDirection
_.GetPowerSettings, _.GetNameSettings, _.GetIndicatorSettings = GetPowerSettings, GetNameSettings, GetIndicatorSettings
_.GetHealerSettings, _.GetRangeSettings, _.GetPortraitSettings = GetHealerSettings, GetRangeSettings, GetPortraitSettings
_.GetFontPath, _.GetFontOutline, _.GetTexturePath, _.ApplyStatusBarTexture = GetFontPath, GetFontOutline, GetTexturePath, ApplyStatusBarTexture
_.InvalidateCache, _.GetTextAnchorInfo = InvalidateCache, GetTextAnchorInfo
_.GetGroupSize, _.GetGroupMode, _.GetFrameDimensions, _.CalculateHeaderSize = GetGroupSize, GetGroupMode, GetFrameDimensions, CalculateHeaderSize
_.ShowUnitTooltip, _.HideUnitTooltip = ShowUnitTooltip, HideUnitTooltip
_.IsNPCPartyMember, _.GetUnitLifeState = IsNPCPartyMember, GetUnitLifeState

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event ~= "ADDON_LOADED" or arg1 ~= ADDON_NAME then return end
    self:UnregisterEvent("ADDON_LOADED")
    if QUI_GF.Initialize then QUI_GF:Initialize() end
end)

function QUI_GF:GetAnchorFrame(frameType)
    if self.editMode or self.testMode then return nil end
    local frame = self.anchorFrames and self.anchorFrames[frameType]
    if frame and frame:IsShown() then return frame end
    return nil
end
function QUI_GF:UpdateAnchorFrames() if _.UpdateAnchorFrames then _.UpdateAnchorFrames() end end
function QUI_GF:IsEnabled() local db = GetSettings(); return db and db.enabled end

_G.QUI_RefreshGroupFrames = function()
    if QUI_GF.RefreshSettings then QUI_GF:RefreshSettings() end
    local editMode = ns.QUI_GroupFrameEditMode
    if editMode and editMode.RefreshTestMode then editMode:RefreshTestMode() end
    if _G.QUI_RefreshGroupFramePreview then _G.QUI_RefreshGroupFramePreview() end
end

if ns.Registry then
    ns.Registry:Register("groupframes", { refresh = _G.QUI_RefreshGroupFrames, priority = 20, group = "frames", importCategories = { "groupFrames" } })
    ns.Registry:Register("groupframesSkin", { refresh = _G.QUI_RefreshGroupFrames, priority = 20, group = "skinning", importCategories = { "skinning", "theme" } })
end
