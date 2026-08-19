local ADDON_NAME, ns = ...
-- luacheck: globals SLASH_QUIAZTAREC1
local Helpers = ns.Helpers

local GetSettings = Helpers.CreateDBGetter("general")

local MARKERS = { "STAR", "CIRCLE", "DIAMOND", "TRIANGLE" }
local MARKER_IDS = { STAR = 1, CIRCLE = 2, DIAMOND = 3, TRIANGLE = 4 }
local MARKER_OFFSET = 62
local MARKER_POINTS = {
    STAR = { "CENTER", "CENTER", 0, MARKER_OFFSET },
    CIRCLE = { "CENTER", "CENTER", MARKER_OFFSET, 0 },
    DIAMOND = { "CENTER", "CENTER", 0, -MARKER_OFFSET },
    TRIANGLE = { "CENTER", "CENTER", -MARKER_OFFSET, 0 },
}
local ALIASES = {
    ["1"] = "STAR", ["2"] = "CIRCLE", ["3"] = "DIAMOND", ["4"] = "TRIANGLE",
    STAR = "STAR", CIRCLE = "CIRCLE", DIAMOND = "DIAMOND", TRIANGLE = "TRIANGLE",
}
local DEFAULT_OFFSET_X = 0
local DEFAULT_OFFSET_Y = 0
local FRAME_SIZE = 360
local MAP_WIDTH = 320
local MAP_HEIGHT = 250
local MAP_ZOOM = 3.5
local MAP_PAN_X = 0.5
local MAP_PAN_Y = 0.40
local AZTAREC_MAP_ID = 2634
local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}

local state = {
    sequence = {},
    frame = nil,
    map = nil,
    mapCanvas = nil,
    mapBackground = nil,
    mapFallback = {},
    mapArt = nil,
    mapLayers = {},
    sequenceText = nil,
    buttons = {},
    markerNumbers = {},
    orderText = "",
    autoShown = false,
    autoShownMapID = nil,
    autoRefreshPending = false,
    pendingShow = false,
}

local function Settings()
    local general = GetSettings()
    if not general then return nil end
    if type(general.aztarecHelper) ~= "table" then
        general.aztarecHelper = {}
    end
    local settings = general.aztarecHelper
    if settings.offsetX == nil then settings.offsetX = DEFAULT_OFFSET_X end
    if settings.offsetY == nil then settings.offsetY = DEFAULT_OFFSET_Y end
    if settings.locked == nil then settings.locked = false end
    return settings
end

local function NormalizeMarker(value)
    if value == nil then return nil end
    if type(value) == "string" and ALIASES[value] then return ALIASES[value] end
    local marker = string.upper(tostring(value)):gsub("%s+", "")
    if ALIASES[marker] then return ALIASES[marker] end
    for _, candidate in ipairs(MARKERS) do
        if marker == candidate then return candidate end
    end
    return nil
end

local function SetFont(fontString, size)
    local font = Helpers.GetGeneralFont and Helpers.GetGeneralFont()
    if Helpers.ApplyFontWithFallback then
        Helpers.ApplyFontWithFallback(fontString, font or STANDARD_TEXT_FONT, size, "OUTLINE")
    else
        fontString:SetFont(font or STANDARD_TEXT_FONT, size, "OUTLINE")
    end
end

local function ApplyPosition()
    if not state.frame then return end
    local settings = Settings()
    state.frame:ClearAllPoints()
    state.frame:SetPoint("CENTER", UIParent, "CENTER",
        settings and settings.offsetX or DEFAULT_OFFSET_X,
        settings and settings.offsetY or DEFAULT_OFFSET_Y)
end

local function ApplyLock()
    if not state.frame then return end
    local settings = Settings()
    local locked = settings and settings.locked == true
    state.frame:SetMovable(not locked)
    if state.dragBar then state.dragBar:EnableMouse(not locked) end
end

local function UpdateDisplay()
    if not state.frame then return end

    for _, marker in ipairs(MARKERS) do
        local button = state.buttons[marker]
        button:SetText(state.markerNumbers[marker] or "")
    end

    if state.orderText == "" then
        state.sequenceText:SetText(ns.L["Order: —"])
    else
        state.sequenceText:SetText(ns.L["Order: "] .. state.orderText)
    end
end

local function CallWoW(fn, ...)
    return ns.SafeCall("report", fn, ...)
end

local function GetCurrentMapID()
    if not C_Map or type(C_Map.GetBestMapForUnit) ~= "function" then return nil end
    local ok, mapID = CallWoW(C_Map.GetBestMapForUnit, "player")
    return ok and mapID or nil
end

local function RefreshMapBackground()
    if not C_Map then return end

    local mapID = AZTAREC_MAP_ID
    local hasLayers = type(C_Map.GetMapArtLayers) == "function"
    local okLayers, layers
    if hasLayers then
        okLayers, layers = CallWoW(C_Map.GetMapArtLayers, mapID)
        hasLayers = okLayers and type(layers) == "table" and #layers > 0
    end
    if state.mapCanvas and hasLayers then
        local okCanvas = CallWoW(state.mapCanvas.SetMapID, state.mapCanvas, mapID)
        if okCanvas then
            local layerInfo = layers[1]
            local width = tonumber(layerInfo.layerWidth) or 0
            local height = tonumber(layerInfo.layerHeight) or 0
            if width > 0 and height > 0 then
                local scale = math.min(state.map:GetWidth() / width, state.map:GetHeight() / height) * MAP_ZOOM
                state.mapCanvas:ClearAllPoints()
                state.mapCanvas:SetSize(state.map:GetWidth(), state.map:GetHeight())
                state.mapCanvas:SetPoint("CENTER", state.map, "CENTER")
                local scroll = state.mapCanvas.ScrollContainer
                if scroll and scroll.InstantPanAndZoom then
                    scroll:InstantPanAndZoom(scale, MAP_PAN_X, MAP_PAN_Y, true)
                end
            end
            state.mapCanvas:Show()
            if state.mapBackground then state.mapBackground:Hide() end
            for _, tile in ipairs(state.mapFallback) do tile:Hide() end
            return
        end
    elseif state.mapCanvas then
        state.mapCanvas:Hide()
    end
    if not state.mapArt then return end
    local hasAtlas = false
    if state.mapBackground and type(C_Map.GetMapArtBackgroundAtlas) == "function" then
        local okBackground, atlas = CallWoW(C_Map.GetMapArtBackgroundAtlas, mapID)
        if okBackground and type(atlas) == "string" and atlas ~= "" then
            state.mapBackground:SetAtlas(atlas, true)
            state.mapBackground:Show()
            hasAtlas = true
        else
            state.mapBackground:Hide()
        end
    end
    for _, tile in ipairs(state.mapFallback) do tile:SetShown(not hasAtlas) end
    if type(C_Map.GetMapArtLayers) ~= "function" or type(C_Map.GetMapArtLayerTextures) ~= "function" then return end
    local ok = okLayers
    if not ok or type(layers) ~= "table" or #layers == 0 then return end

    local maxWidth, maxHeight = 0, 0
    for _, info in ipairs(layers) do
        maxWidth = math.max(maxWidth, tonumber(info.layerWidth) or 0)
        maxHeight = math.max(maxHeight, tonumber(info.layerHeight) or 0)
    end
    if maxWidth <= 0 or maxHeight <= 0 then return end

    local scale = math.min(state.map:GetWidth() / maxWidth, state.map:GetHeight() / maxHeight) * MAP_ZOOM
    local artWidth = maxWidth * scale
    local artHeight = maxHeight * scale
    state.mapArt:ClearAllPoints()
    state.mapArt:SetSize(artWidth, artHeight)
    state.mapArt:SetPoint("TOPLEFT", state.map, "TOPLEFT",
        state.map:GetWidth() * 0.5 - artWidth * MAP_PAN_X,
        state.map:GetHeight() * 0.5 - artHeight * MAP_PAN_Y)

    for index = #layers + 1, #state.mapLayers do
        state.mapLayers[index]:Hide()
    end

    for index, info in ipairs(layers) do
        local width = tonumber(info.layerWidth) or 0
        local height = tonumber(info.layerHeight) or 0
        local tileWidth = tonumber(info.tileWidth) or 256
        local tileHeight = tonumber(info.tileHeight) or 256
        if width > 0 and height > 0 then
            local layer = state.mapLayers[index]
            if not layer then
                layer = CreateFrame("Frame", nil, state.mapArt)
                state.mapLayers[index] = layer
                layer.tiles = {}
            end
            layer:ClearAllPoints()
            layer:SetSize(width * scale, height * scale)
            layer:SetPoint("TOPLEFT", state.mapArt, "TOPLEFT")
            layer:SetFrameLevel(state.map:GetFrameLevel() + index + 1)
            layer:Show()

            local tileColumns = math.ceil(width / tileWidth)
            local tileRows = math.ceil(height / tileHeight)
            local okTextures, textures = CallWoW(C_Map.GetMapArtLayerTextures, mapID, index)
            if okTextures and type(textures) == "table" then
                for tileIndex = 1, tileColumns * tileRows do
                    local tile = layer.tiles[tileIndex]
                    if not tile then
                        tile = layer:CreateTexture(nil, "BACKGROUND", nil, -8 + index)
                        layer.tiles[tileIndex] = tile
                    end
                    local row = math.floor((tileIndex - 1) / tileColumns)
                    local column = (tileIndex - 1) % tileColumns
                    tile:ClearAllPoints()
                    tile:SetSize(tileWidth * scale, tileHeight * scale)
                    tile:SetPoint("TOPLEFT", layer, "TOPLEFT",
                        column * tileWidth * scale, -row * tileHeight * scale)
                    tile:SetTexture(textures[tileIndex], nil, nil, "TRILINEAR")
                    tile:Show()
                end
                for tileIndex = tileColumns * tileRows + 1, #layer.tiles do
                    layer.tiles[tileIndex]:Hide()
                end
            else
                for _, tile in ipairs(layer.tiles) do tile:Hide() end
            end
        end
    end
end

local function Record(marker)
    marker = NormalizeMarker(marker)
    if not marker then return false end
    local index = #state.sequence + 1
    state.sequence[index] = marker
    local numbers = state.markerNumbers[marker]
    state.markerNumbers[marker] = numbers and (numbers .. ", " .. index) or tostring(index)
    state.orderText = index == 1 and marker
        or state.orderText .. (index == 5 and "\n" or "  →  ") .. marker
    if state.frame then
        state.buttons[marker]:SetText(state.markerNumbers[marker])
        state.sequenceText:SetText(ns.L["Order: "] .. state.orderText)
    end
    return true
end

local function ResetSequence()
    for index = #state.sequence, 1, -1 do state.sequence[index] = nil end
    for _, marker in ipairs(MARKERS) do state.markerNumbers[marker] = nil end
    state.orderText = ""
    UpdateDisplay()
end

local function CreateButton(marker, parent)
    local point = MARKER_POINTS[marker]
    local button = CreateFrame("Button", "QUI_AztaRec_" .. marker, parent, "BackdropTemplate")
    button:SetSize(64, 54)
    button:SetFrameLevel(60)
    button:SetPoint(point[1], parent, point[2], point[3], point[4])
    button:SetBackdrop(BACKDROP)
    button:SetBackdropColor(0.08, 0.08, 0.08, 0.35)
    button:SetBackdropBorderColor(0.25, 0.65, 1, 1)
    button:RegisterForClicks("AnyUp")
    button:SetScript("OnClick", function()
        Record(marker)
    end)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(34, 34)
    icon:SetPoint("CENTER", button, "CENTER", 0, 3)
    icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. MARKER_IDS[marker])
    local text = button:CreateFontString(nil, "OVERLAY")
    text:SetAllPoints(button)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("BOTTOM")
    SetFont(text, 14)
    text:SetTextColor(1, 1, 1, 1)
    button:SetFontString(text)
    return button
end

local function EnsureFrame()
    if state.frame then return state.frame end

    local frame = CreateFrame("Frame", "QUI_AztaRecFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_SIZE, FRAME_SIZE)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(50)
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(0.02, 0.02, 0.02, 0.92)
    frame:SetBackdropBorderColor(0.2, 0.7, 1, 1)
    frame:SetClampedToScreen(true)
    state.frame = frame

    local title = frame:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOP", frame, "TOP", 0, -7)
    SetFont(title, 16)
    title:SetTextColor(0.25, 0.85, 1, 1)
    title:SetText(ns.L["Azta'rec — Safe Marker Order"])

    local help = frame:CreateFontString(nil, "OVERLAY")
    help:SetPoint("TOP", title, "BOTTOM", 0, -2)
    SetFont(help, 10)
    help:SetTextColor(0.75, 0.75, 0.75, 1)
    help:SetText(ns.L["Place markers to match this map, then click the safe marker. Numbers show order."])

    local sequenceText = frame:CreateFontString(nil, "OVERLAY")
    sequenceText:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -48)
    sequenceText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -48)
    SetFont(sequenceText, 13)
    sequenceText:SetTextColor(1, 0.85, 0.25, 1)
    sequenceText:SetJustifyH("CENTER")
    sequenceText:SetSpacing(4)
    state.sequenceText = sequenceText

    local map = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    map:SetSize(MAP_WIDTH, MAP_HEIGHT)
    map:SetPoint("TOP", frame, "TOP", 0, -68)
    map:SetBackdrop(BACKDROP)
    map:SetBackdropColor(0.04, 0.06, 0.08, 0.95)
    map:SetBackdropBorderColor(0.15, 0.35, 0.45, 1)
    map:SetFrameStrata("HIGH")
    map:SetFrameLevel(51)
    if map.SetClipsChildren then map:SetClipsChildren(true) end
    state.map = map

    local mapCanvasMixin = _G.MapCanvasMixin
    if type(mapCanvasMixin) == "table" and type(Mixin) == "function" then
        local okCanvas, mapCanvas = CallWoW(function()
            local canvas = CreateFrame("Frame", nil, map)
            local border = CreateFrame("Frame", nil, canvas)
            border:SetAllPoints(canvas)
            local scroll = CreateFrame("ScrollFrame", nil, canvas, "MapCanvasFrameScrollContainerTemplate")
            scroll:SetAllPoints(canvas)
            canvas.BorderFrame = border
            canvas.ScrollContainer = scroll
            Mixin(canvas, mapCanvasMixin)
            canvas:SetSize(MAP_WIDTH, MAP_HEIGHT)
            canvas:SetPoint("CENTER", map, "CENTER")
            canvas:SetFrameStrata("HIGH")
            canvas:SetFrameLevel(52)
            canvas:OnLoad()
            return canvas
        end)
        if okCanvas and mapCanvas and type(mapCanvas.SetMapID) == "function" then
            state.mapCanvas = mapCanvas
        end
    end

    local mapBackground = map:CreateTexture(nil, "BACKGROUND", nil, -8)
    mapBackground:SetAllPoints(map)
    state.mapBackground = mapBackground
    local fallback = {
        { "TOPLEFT", 2, -2, 156, 62, 0.12, 0.22, 0.28, 0.8 },
        { "TOPRIGHT", -2, -2, 156, 62, 0.16, 0.25, 0.3, 0.8 },
        { "BOTTOMLEFT", 2, 2, 156, 62, 0.16, 0.25, 0.3, 0.8 },
        { "BOTTOMRIGHT", -2, 2, 156, 62, 0.12, 0.22, 0.28, 0.8 },
    }
    for _, spec in ipairs(fallback) do
        local tile = map:CreateTexture(nil, "BACKGROUND", nil, -7)
        tile:SetTexture("Interface\\Buttons\\WHITE8X8")
        tile:SetVertexColor(spec[6], spec[7], spec[8], spec[9])
        tile:SetSize(spec[4], spec[5])
        tile:SetPoint(spec[1], map, spec[1], spec[2], spec[3])
        state.mapFallback[#state.mapFallback + 1] = tile
    end

    local mapArt = CreateFrame("Frame", nil, map)
    mapArt:SetAllPoints(map)
    state.mapArt = mapArt

    local roomText = map:CreateFontString(nil, "OVERLAY")
    roomText:SetPoint("CENTER", map, "CENTER")
    SetFont(roomText, 12)
    roomText:SetTextColor(0.45, 0.55, 0.6, 1)
    roomText:SetText(ns.L["ROOM"])

    for _, marker in ipairs(MARKERS) do
        state.buttons[marker] = CreateButton(marker, map)
    end

    local reset = CreateFrame("Button", nil, frame, "BackdropTemplate")
    reset:SetSize(70, 22)
    reset:SetPoint("BOTTOM", frame, "BOTTOM", 0, 8)
    reset:SetBackdrop(BACKDROP)
    reset:SetBackdropColor(0.15, 0.05, 0.05, 0.9)
    reset:SetBackdropBorderColor(0.8, 0.25, 0.25, 1)
    reset:RegisterForClicks("AnyUp")
    reset:SetScript("OnClick", function()
        ResetSequence()
    end)
    local resetText = reset:CreateFontString(nil, "OVERLAY")
    resetText:SetAllPoints(reset)
    SetFont(resetText, 11)
    resetText:SetText(ns.L["Reset"])

    local dragBar = CreateFrame("Button", nil, frame)
    dragBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    dragBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    dragBar:SetHeight(22)
    dragBar:RegisterForDrag("LeftButton")
    dragBar:SetScript("OnDragStart", function()
        local settings = Settings()
        if settings and settings.locked ~= true then frame:StartMoving() end
    end)
    dragBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local settings = Settings()
        local _, _, _, x, y = frame:GetPoint()
        if settings then
            settings.offsetX = x or DEFAULT_OFFSET_X
            settings.offsetY = y or DEFAULT_OFFSET_Y
        end
    end)
    state.dragBar = dragBar

    ApplyPosition()
    ApplyLock()
    UpdateDisplay()
    RefreshMapBackground()
    frame:Hide()
    return frame
end

local function IsInAztaRecLair()
    local delves = _G.C_DelvesUI
    if not delves then return false end

    local mapID = GetCurrentMapID()
    if mapID ~= AZTAREC_MAP_ID then return false end
    if type(delves.HasActiveLair) ~= "function" then return true, mapID end
    local okLair, activeLair = CallWoW(delves.HasActiveLair)
    return okLair and activeLair == true, mapID
end

local API = {}
ns.QUI_AztaRec = API

function API.Show()
    if not state.frame and type(InCombatLockdown) == "function" and InCombatLockdown() then
        state.pendingShow = true
        return false
    end
    local frame = EnsureFrame()
    state.pendingShow = false
    RefreshMapBackground()
    frame:Show()
    return true
end

function API.Hide()
    state.pendingShow = false
    if state.frame then state.frame:Hide() end
end

function API.RefreshAutoVisibility()
    local inLair, mapID = IsInAztaRecLair()
    if inLair then
        if not state.autoShown or state.autoShownMapID ~= mapID then
            API.Show()
            state.autoShownMapID = mapID
        end
        state.autoShown = true
    elseif state.autoShown then
        API.Hide()
        state.autoShown = false
        state.autoShownMapID = nil
    end
end

function API.Toggle()
    if not state.frame then
        API.Show()
        return
    end
    local frame = state.frame
    if frame:IsShown() then
        frame:Hide()
    else
        RefreshMapBackground()
        frame:Show()
    end
end

function API.Reset()
    ResetSequence()
end

function API.Record(direction)
    return Record(direction)
end

function API.Lock(locked)
    local settings = Settings()
    if not settings then return false end
    settings.locked = locked == true
    ApplyLock()
    return true
end

function API.GetSequence()
    local result = {}
    for index, direction in ipairs(state.sequence) do result[index] = direction end
    return result
end

SLASH_QUIAZTAREC1 = "/azt"
SlashCmdList["QUIAZTAREC"] = function(message)
    local command = string.upper(strtrim(message or ""))
    if command == "" or command == "TOGGLE" then
        API.Toggle()
    elseif command == "SHOW" then
        API.Show()
    elseif command == "HIDE" then
        API.Hide()
    elseif command == "RESET" or command == "CLEAR" then
        API.Reset()
    elseif command == "LOCK" then
        API.Lock(true)
    elseif command == "UNLOCK" then
        API.Lock(false)
    elseif NormalizeMarker(command) then
        API.Show()
        API.Record(command)
    else
        print(ns.L["|cff30d1ffQUI:|r /azt [show|hide|reset|lock|unlock|STAR|CIRCLE|DIAMOND|TRIANGLE]"])
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("ACTIVE_DELVE_DATA_UPDATE")
eventFrame:RegisterEvent("NEW_WMO_CHUNK")
eventFrame:RegisterEvent("AREA_POIS_UPDATED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function()
    if state.autoRefreshPending then return end
    state.autoRefreshPending = true
    C_Timer.After(0.5, function()
        state.autoRefreshPending = false
        if state.pendingShow and (type(InCombatLockdown) ~= "function" or not InCombatLockdown()) then
            API.Show()
        end
        API.RefreshAutoVisibility()
    end)
end)
