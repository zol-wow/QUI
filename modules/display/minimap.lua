--- QUI Minimap Module
--- Provides clean, customizable minimap functionality
--- All settings stored in AceDB for profile export/import

local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local Helpers = ns.Helpers
local LSM = LibStub("LibSharedMedia-3.0")
local LibDBIcon = LibStub("LibDBIcon-1.0", true)

-- Module reference
local Minimap_Module = {}
QUICore.Minimap = Minimap_Module

-- Local references for performance
local Minimap = Minimap
local MinimapCluster = MinimapCluster
local UIParent = UIParent

-- Frames created by this module
local backdropFrame, backdrop, mask
local clockFrame, clockText
local coordsFrame, coordsText
local zoneTextFrame, zoneTextFont
local minimapTooltip

-- Datatext panel (3-slot architecture using QUICore.Datatexts registry)
local datatextFrame

-- Performance: Cached settings and tickers (avoid per-frame GetSettings calls)
local cachedSettings = nil
local clockTicker = nil
local coordsTicker = nil

---=================================================================================
--- BLIZZARD BUG WORKAROUND: Indicator frames need parent with Layout method
--- When reparenting IndicatorFrame children, the new parent needs Layout method.
--- We ensure Minimap has a Layout method (hiddenButtonParent gets one below).
---=================================================================================
do
    local function EnsureLayoutMethods()
        -- Ensure Minimap has Layout method
        if Minimap and not Minimap.Layout then
            Minimap.Layout = function() end
        end
        -- Ensure IndicatorFrame has Layout method
        if MinimapCluster and MinimapCluster.IndicatorFrame and not MinimapCluster.IndicatorFrame.Layout then
            MinimapCluster.IndicatorFrame.Layout = function() end
        end
    end
    
    -- Apply on login and entering world
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", function(self, event)
        EnsureLayoutMethods()
    end)
    
    -- Try immediately
    EnsureLayoutMethods()
end

---=================================================================================
--- HELPER FUNCTIONS
---=================================================================================

local function GetSettings()
    if cachedSettings then return cachedSettings end
    cachedSettings = Helpers.GetModuleDB("minimap")
    return cachedSettings
end

local function InvalidateSettingsCache()
    cachedSettings = nil
end

local function GetClassColor()
    local _, class = UnitClass("player")
    -- Support custom class color addons, fallback to standard
    local color = CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class] or RAID_CLASS_COLORS[class]
    return color
end

---=================================================================================
--- MINIMAP SHAPE
---=================================================================================

local function SetMinimapShape(shape)
    if shape == "SQUARE" then
        Minimap:SetMaskTexture("Interface\\BUTTONS\\WHITE8X8")
        if mask then
            mask:SetTexture("Interface\\BUTTONS\\WHITE8X8")
        end
        _G.GetMinimapShape = function() return "SQUARE" end
        
        -- Handle HybridMinimap (Delves/scenarios)
        if HybridMinimap then
            HybridMinimap.MapCanvas:SetUseMaskTexture(false)
            HybridMinimap.CircleMask:SetTexture("Interface\\BUTTONS\\WHITE8X8")
            HybridMinimap.MapCanvas:SetUseMaskTexture(true)
        end
        
        -- Remove the waffle texture in quest areas
        Minimap:SetArchBlobRingScalar(0)
        Minimap:SetArchBlobRingAlpha(0)
        Minimap:SetQuestBlobRingScalar(0)
        Minimap:SetQuestBlobRingAlpha(0)
    else
        -- Round shape - use default circle mask
        Minimap:SetMaskTexture("Interface\\MINIMAP\\UI-Minimap-Background")
        if mask then
            mask:SetTexture("Interface\\MINIMAP\\UI-Minimap-Background")
        end
        _G.GetMinimapShape = function() return "ROUND" end
        
        if HybridMinimap then
            HybridMinimap.MapCanvas:SetUseMaskTexture(false)
            HybridMinimap.CircleMask:SetTexture("Interface\\MINIMAP\\UI-Minimap-Background")
            HybridMinimap.MapCanvas:SetUseMaskTexture(true)
        end
    end
    
    -- Refresh LibDBIcon button positions if available
    if LibDBIcon then
        local buttons = LibDBIcon:GetButtonList()
        for i = 1, #buttons do
            LibDBIcon:Refresh(buttons[i])
        end
    end
end

---=================================================================================
--- BACKDROP / BORDER
---=================================================================================

local function CreateBackdrop()
    if backdropFrame then return end
    
    backdropFrame = CreateFrame("Frame", "QUI_MinimapBackdrop", Minimap)
    backdropFrame:SetFrameStrata("BACKGROUND")
    backdropFrame:SetFrameLevel(1)
    backdropFrame:SetFixedFrameStrata(true)
    backdropFrame:SetFixedFrameLevel(true)
    backdropFrame:Show()
    
    backdrop = backdropFrame:CreateTexture(nil, "BACKGROUND")
    backdrop:SetPoint("CENTER", Minimap, "CENTER")
    
    mask = backdropFrame:CreateMaskTexture()
    mask:SetAllPoints(backdrop)
    mask:SetParent(backdropFrame)
    backdrop:AddMaskTexture(mask)
end

local function UpdateBackdrop()
    local settings = GetSettings()
    if not settings or not settings.enabled then return end
    if not backdrop then CreateBackdrop() end
    
    -- Border shows on all 4 sides, so we need size + (borderSize * 2)
    local fullSize = settings.size + (settings.borderSize * 2)
    backdrop:SetSize(fullSize, fullSize)
    
    -- Apply border color
    local r, g, b, a = unpack(settings.borderColor)
    if settings.useClassColorBorder then
        local color = GetClassColor()
        if color then
            r, g, b = color.r, color.g, color.b
        end
    end
    backdrop:SetColorTexture(r, g, b, a)
    
    -- Update mask based on shape
    if settings.shape == "SQUARE" then
        mask:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    else
        mask:SetTexture("Interface\\MINIMAP\\UI-Minimap-Background")
    end
end

---=================================================================================
--- DATATEXT PANEL (integrated below minimap)
---=================================================================================

local function GetDatatextSettings()
    if not QUICore or not QUICore.db or not QUICore.db.profile then
        return nil
    end
    return QUICore.db.profile.datatext
end

local function ColorWrap(text, r, g, b)
    return string.format("|cff%02x%02x%02x%s|r", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), text)
end

local function FormatGold(copper)
    local gold = math.floor(copper / 10000)
    local goldStr = tostring(gold)
    if gold >= 1000 then
        goldStr = string.format("%d,%03d", math.floor(gold / 1000), gold % 1000)
    end
    if gold >= 1000000 then
        local millions = math.floor(gold / 1000000)
        local thousands = math.floor((gold % 1000000) / 1000)
        goldStr = string.format("%d,%03d,%03d", millions, thousands, gold % 1000)
    end
    return goldStr .. "g"
end

---=================================================================================
--- DATATEXT PANEL (3-Slot Architecture)
---=================================================================================

local function CreateDatatextPanel()
    if datatextFrame then return end

    -- Container frame for 3 datatext slots
    datatextFrame = CreateFrame("Frame", "QUI_DatatextPanel", UIParent)
    datatextFrame:SetFrameStrata("LOW")
    datatextFrame:SetFrameLevel(100)

    -- Create 4 border edge textures
    datatextFrame.borderLeft = datatextFrame:CreateTexture(nil, "BACKGROUND")
    datatextFrame.borderRight = datatextFrame:CreateTexture(nil, "BACKGROUND")
    datatextFrame.borderTop = datatextFrame:CreateTexture(nil, "BACKGROUND")
    datatextFrame.borderBottom = datatextFrame:CreateTexture(nil, "BACKGROUND")

    -- Background texture
    datatextFrame.bg = datatextFrame:CreateTexture(nil, "BACKGROUND")
    datatextFrame.bg:SetAllPoints()

    -- Create 3 slot frames for individual datatexts
    datatextFrame.slots = {}
    for i = 1, 3 do
        local slot = CreateFrame("Button", nil, datatextFrame)
        slot:EnableMouse(true)
        slot:RegisterForClicks("AnyUp")

        -- Create text for datatext use
        slot.text = slot:CreateFontString(nil, "OVERLAY")
        -- Anchor to both edges to constrain width and enable auto-truncation
        slot.text:SetPoint("LEFT", slot, "LEFT", 1, 0)
        slot.text:SetPoint("RIGHT", slot, "RIGHT", -1, 0)
        slot.text:SetJustifyH("CENTER")
        slot.text:SetWordWrap(false)
        slot.index = i

        datatextFrame.slots[i] = slot
    end
end

-- Attach datatexts to the 3 minimap panel slots
local function RefreshDatatextSlots()
    if not datatextFrame or not datatextFrame.slots then return end
    if not QUICore or not QUICore.Datatexts then return end

    local dtSettings = GetDatatextSettings()
    if not dtSettings then return end

    local slots = dtSettings.slots or {"time", "friends", "guild"}

    -- Apply font settings to all slots
    local generalFont = "Quazii"
    local generalOutline = "OUTLINE"
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general then
        local general = QUICore.db.profile.general
        generalFont = general.font or "Quazii"
        generalOutline = general.fontOutline or "OUTLINE"
    end
    local fontPath = LSM:Fetch("font", generalFont) or "Fonts\\FRIZQT__.TTF"
    local fontSize = dtSettings.fontSize or 12

    -- Count active (non-empty) slots for flexible width calculation
    local activeCount = 0
    for i = 1, 3 do
        local datatextID = slots[i]
        if datatextID and datatextID ~= "" then
            activeCount = activeCount + 1
        end
    end

    -- Calculate flexible slot widths based on active count
    local panelWidth = datatextFrame:GetWidth()
    local slotWidth = panelWidth / math.max(1, activeCount)
    local slotHeight = datatextFrame:GetHeight()

    -- Position only active slots, hide empty ones
    local xPos = 0
    for i, slot in ipairs(datatextFrame.slots) do
        local datatextID = slots[i]
        local slotConfig = dtSettings["slot" .. i] or {}

        -- Detach any existing datatext first
        if slot.datatextInstance then
            QUICore.Datatexts:DetachFromSlot(slot)
        end

        -- Apply font to ALL slots (prevents "Font not set" error on empty slots)
        QUICore:SafeSetFont(slot.text, fontPath, fontSize, generalOutline)

        if datatextID and datatextID ~= "" then
            -- Active slot: size, position, show
            slot:SetSize(slotWidth, slotHeight)
            slot:ClearAllPoints()
            -- Apply per-slot offsets
            local xOff = slotConfig.xOffset or 0
            local yOff = slotConfig.yOffset or 0
            slot:SetPoint("LEFT", datatextFrame, "LEFT", xPos + xOff, yOff)
            slot:Show()
            xPos = xPos + slotWidth

            slot.text:SetTextColor(1, 1, 1, 1)

            -- Store per-slot shortLabel/noLabel on the slot for datatext to read
            slot.shortLabel = slotConfig.shortLabel or false
            slot.noLabel = slotConfig.noLabel or false

            -- Attach datatext
            QUICore.Datatexts:AttachToSlot(slot, datatextID, dtSettings)
        else
            -- Empty slot: hide
            slot:Hide()
            slot.text:SetText("")
        end
    end
end

local function UpdateDatatextPanel()
    local minimapSettings = GetSettings()
    local dtSettings = GetDatatextSettings()

    if not minimapSettings or not minimapSettings.enabled then return end
    if not dtSettings or not dtSettings.enabled then
        if datatextFrame then datatextFrame:Hide() end
        return
    end

    if not datatextFrame then CreateDatatextPanel() end

    local minimapSize = minimapSettings.size or 160
    local minimapScale = minimapSettings.scale or 1.0
    local minimapBorderSize = minimapSettings.borderSize or 3
    local dtBorderSize = dtSettings.borderSize or 2
    local dtBorderColor = dtSettings.borderColor or {0, 0, 0, 1}  -- (#90)
    local dtHeight = dtSettings.height or 22
    local yOffset = dtSettings.offsetY or 0
    local bgAlpha = (dtSettings.bgOpacity or 60) / 100

    -- Content frame size = minimap size
    datatextFrame:SetSize(minimapSize, dtHeight)

    -- Only apply scale if not default (avoids WoW rendering quirk at exactly 1.0)
    if minimapScale ~= 1.0 then
        datatextFrame:SetScale(minimapScale)
    elseif datatextFrame:GetScale() ~= 1 then
        datatextFrame:SetScale(1)
    end

    -- Position below minimap (content touches minimap border bottom)
    datatextFrame:ClearAllPoints()
    datatextFrame:SetPoint("TOP", Minimap, "BOTTOM", 0, -(minimapBorderSize + yOffset))

    -- Left border (extends outward)
    datatextFrame.borderLeft:ClearAllPoints()
    datatextFrame.borderLeft:SetPoint("TOPRIGHT", datatextFrame, "TOPLEFT", 0, dtBorderSize)
    datatextFrame.borderLeft:SetPoint("BOTTOMRIGHT", datatextFrame, "BOTTOMLEFT", 0, -dtBorderSize)
    datatextFrame.borderLeft:SetWidth(dtBorderSize)
    datatextFrame.borderLeft:SetColorTexture(unpack(dtBorderColor))

    -- Right border (extends outward)
    datatextFrame.borderRight:ClearAllPoints()
    datatextFrame.borderRight:SetPoint("TOPLEFT", datatextFrame, "TOPRIGHT", 0, dtBorderSize)
    datatextFrame.borderRight:SetPoint("BOTTOMLEFT", datatextFrame, "BOTTOMRIGHT", 0, -dtBorderSize)
    datatextFrame.borderRight:SetWidth(dtBorderSize)
    datatextFrame.borderRight:SetColorTexture(unpack(dtBorderColor))

    -- Top border (extends outward)
    datatextFrame.borderTop:ClearAllPoints()
    datatextFrame.borderTop:SetPoint("BOTTOMLEFT", datatextFrame, "TOPLEFT", 0, 0)
    datatextFrame.borderTop:SetPoint("BOTTOMRIGHT", datatextFrame, "TOPRIGHT", 0, 0)
    datatextFrame.borderTop:SetHeight(dtBorderSize)
    datatextFrame.borderTop:SetColorTexture(unpack(dtBorderColor))

    -- Bottom border (extends outward)
    datatextFrame.borderBottom:ClearAllPoints()
    datatextFrame.borderBottom:SetPoint("TOPLEFT", datatextFrame, "BOTTOMLEFT", 0, 0)
    datatextFrame.borderBottom:SetPoint("TOPRIGHT", datatextFrame, "BOTTOMRIGHT", 0, 0)
    datatextFrame.borderBottom:SetHeight(dtBorderSize)
    datatextFrame.borderBottom:SetColorTexture(unpack(dtBorderColor))

    -- Hide borders when borderSize is 0 (matches extra panels behavior) (#90)
    local showBorder = dtBorderSize > 0
    datatextFrame.borderLeft:SetShown(showBorder)
    datatextFrame.borderRight:SetShown(showBorder)
    datatextFrame.borderTop:SetShown(showBorder)
    datatextFrame.borderBottom:SetShown(showBorder)

    -- Background (content area with opacity)
    datatextFrame.bg:SetColorTexture(0, 0, 0, bgAlpha)

    datatextFrame:Show()

    -- Attach datatexts to slots
    RefreshDatatextSlots()
end

---=================================================================================
--- CLOCK
---=================================================================================

local function CreateClock()
    if clockFrame then return end
    
    clockFrame = CreateFrame("Button", nil, Minimap)
    clockText = clockFrame:CreateFontString(nil, "OVERLAY")
    clockText:SetAllPoints(clockFrame)
    
    -- Hide Blizzard clock
    if TimeManagerClockButton then
        TimeManagerClockButton:SetParent(CreateFrame("Frame"))
        TimeManagerClockButton:Hide()
    end
    if TimeManagerClockTicker then
        TimeManagerClockTicker:SetParent(CreateFrame("Frame"))
        TimeManagerClockTicker:Hide()
    end
    
    clockFrame:EnableMouse(true)
    clockFrame:RegisterForClicks("AnyUp")

    clockFrame:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            ToggleCalendar()
        elseif button == "RightButton" then
            if TimeManagerFrame then
                if TimeManagerFrame:IsShown() then
                    TimeManagerFrame:Hide()
                else
                    TimeManagerFrame:Show()
                end
            end
        end
    end)

    clockFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(TIMEMANAGER_TOOLTIP_TITLE, 1, 1, 1)
        GameTooltip:AddDoubleLine(TIMEMANAGER_TOOLTIP_REALMTIME, GameTime_GetGameTime(true), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine(TIMEMANAGER_TOOLTIP_LOCALTIME, GameTime_GetLocalTime(true), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffFFFFFFLeft Click:|r Open Calendar", 0.2, 1, 0.2)
        GameTooltip:AddLine("|cffFFFFFFRight Click:|r Toggle Clock", 0.2, 1, 0.2)
        GameTooltip:Show()
    end)
    
    clockFrame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function UpdateClock()
    local settings = GetSettings()
    if not settings or not settings.enabled then return end
    if not clockFrame then CreateClock() end
    
    local clockConfig = settings.clockConfig
    
    if not settings.showClock then
        clockFrame:Hide()
        return
    end
    
    clockFrame:Show()
    clockFrame:ClearAllPoints()
    clockFrame:SetPoint("TOPLEFT", Minimap, "TOPLEFT", clockConfig.offsetX, clockConfig.offsetY)
    clockFrame:SetHeight(clockConfig.fontSize + 1)
    
    -- Build font flags
    local flags = nil
    if clockConfig.monochrome and clockConfig.outline ~= "NONE" then
        flags = "MONOCHROME," .. clockConfig.outline
    elseif clockConfig.monochrome then
        flags = "MONOCHROME"
    elseif clockConfig.outline ~= "NONE" then
        flags = clockConfig.outline
    end
    
    local fontPath = LSM:Fetch("font", clockConfig.font) or "Fonts\\FRIZQT__.TTF"
    QUICore:SafeSetFont(clockText, fontPath, clockConfig.fontSize, flags)
    clockText:SetJustifyH(clockConfig.align)
    
    -- Set color
    local r, g, b, a = unpack(clockConfig.color)
    if clockConfig.useClassColor then
        local color = GetClassColor()
        if color then
            r, g, b = color.r, color.g, color.b
        end
    end
    clockText:SetTextColor(r, g, b, a)
    
    -- Calculate width
    clockText:SetText("99:99")
    local width = clockText:GetUnboundedStringWidth()
    clockFrame:SetWidth(width + 5)
end

local function UpdateClockTime()
    if not clockFrame or not clockText then return end
    local settings = GetSettings()
    if not settings or not settings.showClock then return end
    
    local clockConfig = settings.clockConfig
    
    -- Ensure font is set before formatting text
    local currentFont = clockText:GetFont()
    if not currentFont then
        local fontPath = LSM:Fetch("font", clockConfig.font) or "Fonts\\FRIZQT__.TTF"
        local flags = nil
        if clockConfig.monochrome and clockConfig.outline ~= "NONE" then
            flags = "MONOCHROME," .. clockConfig.outline
        elseif clockConfig.monochrome then
            flags = "MONOCHROME"
        elseif clockConfig.outline ~= "NONE" then
            flags = clockConfig.outline
        end
        QUICore:SafeSetFont(clockText, fontPath, clockConfig.fontSize, flags)
    end
    
    local hour, minute
    
    -- Use our own setting instead of CVar
    local useLocalTime = (clockConfig.timeFormat == "local")
    
    if useLocalTime then
        hour, minute = tonumber(date("%H")), tonumber(date("%M"))
    else
        hour, minute = GetGameTime()
    end
    
    if GetCVarBool("timeMgrUseMilitaryTime") then
        clockText:SetFormattedText(TIMEMANAGER_TICKER_24HOUR, hour, minute)
    else
        if hour == 0 then
            hour = 12
        elseif hour > 12 then
            hour = hour - 12
        end
        clockText:SetFormattedText(TIMEMANAGER_TICKER_12HOUR, hour, minute)
    end
end

---=================================================================================
--- COORDINATES
---=================================================================================

local function CreateCoords()
    if coordsFrame then return end
    
    coordsFrame = CreateFrame("Frame", nil, Minimap)
    coordsText = coordsFrame:CreateFontString(nil, "OVERLAY")
    coordsText:SetAllPoints(coordsFrame)
end

local function UpdateCoords()
    local settings = GetSettings()
    if not settings or not settings.enabled then return end
    if not coordsFrame then CreateCoords() end
    
    local coordsConfig = settings.coordsConfig
    
    if not settings.showCoords then
        coordsFrame:Hide()
        return
    end
    
    coordsFrame:Show()
    coordsFrame:ClearAllPoints()
    coordsFrame:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", coordsConfig.offsetX, coordsConfig.offsetY)
    coordsFrame:SetHeight(coordsConfig.fontSize + 1)
    
    -- Build font flags
    local flags = nil
    if coordsConfig.monochrome and coordsConfig.outline ~= "NONE" then
        flags = "MONOCHROME," .. coordsConfig.outline
    elseif coordsConfig.monochrome then
        flags = "MONOCHROME"
    elseif coordsConfig.outline ~= "NONE" then
        flags = coordsConfig.outline
    end
    
    local fontPath = LSM:Fetch("font", coordsConfig.font) or "Fonts\\FRIZQT__.TTF"
    QUICore:SafeSetFont(coordsText, fontPath, coordsConfig.fontSize, flags)
    coordsText:SetJustifyH(coordsConfig.align)
    
    -- Set color
    local r, g, b, a = unpack(coordsConfig.color)
    if coordsConfig.useClassColor then
        local color = GetClassColor()
        if color then
            r, g, b = color.r, color.g, color.b
        end
    end
    coordsText:SetTextColor(r, g, b, a)
    
    -- Calculate width
    coordsText:SetFormattedText(settings.coordPrecision, 100.77, 100.77)
    local width = coordsText:GetUnboundedStringWidth()
    coordsFrame:SetWidth(width + 5)
end

local function UpdateCoordsPosition()
    if not coordsFrame or not coordsText then return end
    local settings = GetSettings()
    if not settings or not settings.showCoords then return end
    
    -- Ensure font is set before formatting text
    local coordsConfig = settings.coordsConfig
    local currentFont = coordsText:GetFont()
    if not currentFont then
        local fontPath = LSM:Fetch("font", coordsConfig.font) or "Fonts\\FRIZQT__.TTF"
        local flags = nil
        if coordsConfig.monochrome and coordsConfig.outline ~= "NONE" then
            flags = "MONOCHROME," .. coordsConfig.outline
        elseif coordsConfig.monochrome then
            flags = "MONOCHROME"
        elseif coordsConfig.outline ~= "NONE" then
            flags = coordsConfig.outline
        end
        QUICore:SafeSetFont(coordsText, fontPath, coordsConfig.fontSize, flags)
    end
    
    local uiMapID = C_Map.GetBestMapForUnit("player")
    if uiMapID then
        local pos = C_Map.GetPlayerMapPosition(uiMapID, "player")
        if pos then
            coordsText:SetFormattedText(settings.coordPrecision, pos.x * 100, pos.y * 100)
            return
        end
    end
    coordsText:SetText("0,0")
end

---=================================================================================
--- ZONE TEXT
---=================================================================================

local function CreateZoneText()
    if zoneTextFrame then return end
    
    zoneTextFrame = CreateFrame("Button", nil, Minimap)
    zoneTextFont = zoneTextFrame:CreateFontString(nil, "OVERLAY")
    zoneTextFont:SetAllPoints(zoneTextFrame)
    
    -- Hide Blizzard zone text
    if MinimapCluster and MinimapCluster.ZoneTextButton then
        MinimapCluster.ZoneTextButton:SetParent(CreateFrame("Frame"))
        MinimapCluster.ZoneTextButton:Hide()
    end
    if MinimapCluster and MinimapCluster.BorderTop then
        MinimapCluster.BorderTop:SetParent(CreateFrame("Frame"))
        MinimapCluster.BorderTop:Hide()
    end
    
    zoneTextFrame:RegisterEvent("ZONE_CHANGED")
    zoneTextFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
    zoneTextFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    
    zoneTextFrame:SetScript("OnEvent", function()
        UpdateZoneTextDisplay()
    end)
    
    zoneTextFrame:SetScript("OnEnter", function(self)
        local GetZonePVPInfo = C_PvP and C_PvP.GetZonePVPInfo or GetZonePVPInfo
        local pvpType, _, factionName = GetZonePVPInfo()
        local zoneName = GetZoneText()
        local subzoneName = GetSubZoneText()
        
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(zoneName, 1, 1, 1)
        
        if subzoneName and subzoneName ~= "" and subzoneName ~= zoneName then
            if pvpType == "sanctuary" then
                GameTooltip:AddLine(subzoneName, 0.41, 0.8, 0.94)
                GameTooltip:AddLine(SANCTUARY_TERRITORY, 0.41, 0.8, 0.94)
            elseif pvpType == "arena" or pvpType == "combat" then
                GameTooltip:AddLine(subzoneName, 1, 0.1, 0.1)
                GameTooltip:AddLine(pvpType == "arena" and FREE_FOR_ALL_TERRITORY or COMBAT_ZONE, 1, 0.1, 0.1)
            elseif pvpType == "friendly" then
                GameTooltip:AddLine(subzoneName, 0.1, 1, 0.1)
                if factionName and factionName ~= "" then
                    GameTooltip:AddLine(FACTION_CONTROLLED_TERRITORY:format(factionName), 0.1, 1, 0.1)
                end
            elseif pvpType == "hostile" then
                GameTooltip:AddLine(subzoneName, 1, 0.1, 0.1)
                if factionName and factionName ~= "" then
                    GameTooltip:AddLine(FACTION_CONTROLLED_TERRITORY:format(factionName), 1, 0.1, 0.1)
                end
            elseif pvpType == "contested" then
                GameTooltip:AddLine(subzoneName, 1, 0.7, 0)
                GameTooltip:AddLine(CONTESTED_TERRITORY, 1, 0.7, 0)
            else
                GameTooltip:AddLine(subzoneName, 1, 0.82, 0)
            end
        end
        
        GameTooltip:Show()
    end)
    
    zoneTextFrame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function UpdateZoneText()
    local settings = GetSettings()
    if not settings or not settings.enabled then return end
    if not zoneTextFrame then CreateZoneText() end
    
    local zoneConfig = settings.zoneTextConfig
    
    if not settings.showZoneText then
        zoneTextFrame:Hide()
        return
    end
    
    zoneTextFrame:Show()
    zoneTextFrame:ClearAllPoints()
    zoneTextFrame:SetPoint("TOP", Minimap, "TOP", zoneConfig.offsetX, zoneConfig.offsetY)
    zoneTextFrame:SetWidth(settings.size)
    zoneTextFrame:SetHeight(zoneConfig.fontSize + 1)
    
    -- Build font flags
    local flags = nil
    if zoneConfig.monochrome and zoneConfig.outline ~= "NONE" then
        flags = "MONOCHROME," .. zoneConfig.outline
    elseif zoneConfig.monochrome then
        flags = "MONOCHROME"
    elseif zoneConfig.outline ~= "NONE" then
        flags = generalOutline
    end
    
    -- Use general font settings
    local generalFont = "Quazii"
    local generalOutline = "OUTLINE"
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general then
        local general = QUICore.db.profile.general
        generalFont = general.font or "Quazii"
        generalOutline = general.fontOutline or "OUTLINE"
    end
    
    -- Override flags with general outline if not using monochrome
    if not zoneConfig.monochrome then
        flags = generalOutline
    end
    
    local fontPath = LSM:Fetch("font", generalFont) or "Fonts\\FRIZQT__.TTF"
    QUICore:SafeSetFont(zoneTextFont, fontPath, zoneConfig.fontSize, flags)
    zoneTextFont:SetJustifyH(zoneConfig.align)

    UpdateZoneTextDisplay()
end

function UpdateZoneTextDisplay()
    if not zoneTextFrame or not zoneTextFont then return end
    local settings = GetSettings()
    if not settings or not settings.showZoneText then return end
    
    local zoneConfig = settings.zoneTextConfig
    
    -- Ensure font is set before setting text
    local currentFont = zoneTextFont:GetFont()
    if not currentFont then
        -- Use general font settings
        local generalFont = "Quazii"
        local generalOutline = "OUTLINE"
        if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general then
            local general = QUICore.db.profile.general
            generalFont = general.font or "Quazii"
            generalOutline = general.fontOutline or "OUTLINE"
        end
        
        local fontPath = LSM:Fetch("font", generalFont) or "Fonts\\FRIZQT__.TTF"
        local flags = nil
        if zoneConfig.monochrome and generalOutline ~= "NONE" then
            flags = "MONOCHROME," .. generalOutline
        elseif zoneConfig.monochrome then
            flags = "MONOCHROME"
        elseif generalOutline ~= "NONE" then
            flags = generalOutline
        end
        QUICore:SafeSetFont(zoneTextFont, fontPath, zoneConfig.fontSize, flags)
    end

    local text = GetMinimapZoneText()
    
    -- Apply all caps if enabled
    if zoneConfig.allCaps then
        text = string.upper(text)
    end
    
    zoneTextFont:SetText(text)
    
    -- Color based on PvP zone type
    local GetZonePVPInfo = C_PvP and C_PvP.GetZonePVPInfo or GetZonePVPInfo
    local pvpType = GetZonePVPInfo()
    
    local r, g, b, a
    if zoneConfig.useClassColor then
        local color = GetClassColor()
        if color then
            r, g, b, a = color.r, color.g, color.b, 1
        end
    elseif pvpType == "sanctuary" then
        r, g, b, a = unpack(zoneConfig.colorSanctuary)
    elseif pvpType == "arena" then
        r, g, b, a = unpack(zoneConfig.colorArena)
    elseif pvpType == "friendly" then
        r, g, b, a = unpack(zoneConfig.colorFriendly)
    elseif pvpType == "hostile" then
        r, g, b, a = unpack(zoneConfig.colorHostile)
    elseif pvpType == "contested" then
        r, g, b, a = unpack(zoneConfig.colorContested)
    else
        r, g, b, a = unpack(zoneConfig.colorNormal)
    end
    
    zoneTextFont:SetTextColor(r, g, b, a)
end

---=================================================================================
--- BUTTON VISIBILITY
---=================================================================================

-- Hidden frame to parent hidden buttons to
local hiddenButtonParent = CreateFrame("Frame")
hiddenButtonParent:Hide()
hiddenButtonParent.Layout = function() end  -- Prevent nil errors when Blizzard code calls Layout on children

-- Hook Show() on zoom buttons to prevent Blizzard from re-showing them
if Minimap.ZoomIn and not Minimap.ZoomIn._QUI_ShowHooked then
    Minimap.ZoomIn._QUI_ShowHooked = true
    hooksecurefunc(Minimap.ZoomIn, "Show", function(self)
        local s = GetSettings()
        if s and not s.showZoomButtons then
            self:Hide()
        end
    end)
end

if Minimap.ZoomOut and not Minimap.ZoomOut._QUI_ShowHooked then
    Minimap.ZoomOut._QUI_ShowHooked = true
    hooksecurefunc(Minimap.ZoomOut, "Show", function(self)
        local s = GetSettings()
        if s and not s.showZoomButtons then
            self:Hide()
        end
    end)
end

local function UpdateButtonVisibility()
    local settings = GetSettings()
    if not settings or not settings.enabled then return end
    
    local minimapSize = settings.size or 160
    local halfSize = minimapSize / 2
    
    -- Zoom buttons - position at bottom right corner
    if Minimap.ZoomIn and Minimap.ZoomOut then
        if settings.showZoomButtons then
            Minimap.ZoomIn:SetParent(Minimap)
            Minimap.ZoomIn:ClearAllPoints()
            Minimap.ZoomIn:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", -5, 25)
            Minimap.ZoomIn:Show()
            
            Minimap.ZoomOut:SetParent(Minimap)
            Minimap.ZoomOut:ClearAllPoints()
            Minimap.ZoomOut:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", -5, 5)
            Minimap.ZoomOut:Show()
        else
            Minimap.ZoomIn:SetParent(hiddenButtonParent)
            Minimap.ZoomIn:Hide()
            Minimap.ZoomOut:SetParent(hiddenButtonParent)
            Minimap.ZoomOut:Hide()
        end
    end

    -- Mail indicator - position at bottom left
    if MinimapCluster and MinimapCluster.IndicatorFrame and MinimapCluster.IndicatorFrame.MailFrame then
        local mailFrame = MinimapCluster.IndicatorFrame.MailFrame
        
        -- Ensure frame has Layout method (Blizzard's event handlers call self:Layout())
        if not mailFrame.Layout then
            mailFrame.Layout = function() end
        end
        
        if settings.showMail then
            mailFrame:SetParent(Minimap)
            mailFrame:ClearAllPoints()
            mailFrame:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", 2, 2)
            mailFrame:SetScale(0.8)  -- Scale down slightly for cleaner look
            mailFrame:Show()
        else
            mailFrame:SetParent(hiddenButtonParent)
            mailFrame:Hide()
        end
    end
    
    -- Crafting order indicator - position next to mail
    if MinimapCluster and MinimapCluster.IndicatorFrame and MinimapCluster.IndicatorFrame.CraftingOrderFrame then
        local craftingFrame = MinimapCluster.IndicatorFrame.CraftingOrderFrame
        
        -- Ensure frame has Layout method (Blizzard's event handlers call self:Layout())
        if not craftingFrame.Layout then
            craftingFrame.Layout = function() end
        end
        
        if settings.showCraftingOrder then
            craftingFrame:SetParent(Minimap)
            craftingFrame:ClearAllPoints()
            craftingFrame:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", 28, 2)  -- Offset from mail
            craftingFrame:SetScale(0.8)
            craftingFrame:Show()
        else
            craftingFrame:SetParent(hiddenButtonParent)
            craftingFrame:Hide()
        end
    end
    
    -- Addon compartment - position at top right
    if AddonCompartmentFrame then
        if settings.showAddonCompartment then
            AddonCompartmentFrame:SetParent(Minimap)
            AddonCompartmentFrame:ClearAllPoints()
            AddonCompartmentFrame:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", -2, -2)
            AddonCompartmentFrame:Show()
        else
            AddonCompartmentFrame:SetParent(hiddenButtonParent)
            AddonCompartmentFrame:Hide()
        end
    end
    
    -- Difficulty indicator - position at top left
    if MinimapCluster and MinimapCluster.InstanceDifficulty then
        local diffFrame = MinimapCluster.InstanceDifficulty
        if settings.showDifficulty then
            diffFrame:SetParent(Minimap)
            diffFrame:ClearAllPoints()
            diffFrame:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 2, -2)
        else
            diffFrame:SetParent(hiddenButtonParent)
        end
    end
    
    -- Expansion landing page button (missions) - position at left side
    if ExpansionLandingPageMinimapButton then
        if settings.showMissions then
            ExpansionLandingPageMinimapButton:SetParent(Minimap)
            ExpansionLandingPageMinimapButton:ClearAllPoints()
            ExpansionLandingPageMinimapButton:SetPoint("LEFT", Minimap, "LEFT", -5, 0)
            ExpansionLandingPageMinimapButton:Show()
        else
            ExpansionLandingPageMinimapButton:SetParent(hiddenButtonParent)
            ExpansionLandingPageMinimapButton:Hide()
        end
    end
    
    -- Calendar - position at top right (next to addon compartment if shown)
    if GameTimeFrame then
        if settings.showCalendar then
            GameTimeFrame:SetParent(Minimap)
            GameTimeFrame:ClearAllPoints()
            if settings.showAddonCompartment then
                GameTimeFrame:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", -28, -2)
            else
                GameTimeFrame:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", -2, -2)
            end
            GameTimeFrame:Show()
        else
            GameTimeFrame:SetParent(hiddenButtonParent)
            GameTimeFrame:Hide()
        end
    end
    
    -- Tracking button - position at top left (next to difficulty if shown)
    if MinimapCluster and MinimapCluster.Tracking then
        local trackingFrame = MinimapCluster.Tracking
        if settings.showTracking then
            trackingFrame:SetParent(Minimap)
            trackingFrame:ClearAllPoints()
            if settings.showDifficulty then
                trackingFrame:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 35, -2)
            else
                trackingFrame:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 2, -2)
            end
        else
            trackingFrame:SetParent(hiddenButtonParent)
        end
    end
end

---=================================================================================
--- DUNGEON EYE (QUEUE STATUS BUTTON)
---=================================================================================

local dungeonEyeOriginalParent = nil
local dungeonEyeOriginalPoint = nil
local dungeonEyeHooked = false

local function RestoreDungeonEye()
    local btn = QueueStatusButton
    if not btn then return end

    -- Restore original parent if we saved it
    if dungeonEyeOriginalParent then
        btn:SetParent(dungeonEyeOriginalParent)
    end

    -- Restore original position if we saved it
    if dungeonEyeOriginalPoint then
        btn:ClearAllPoints()
        local point, relativeTo, relativePoint, x, y = unpack(dungeonEyeOriginalPoint)
        if point and relativePoint then
            btn:SetPoint(point, relativeTo, relativePoint, x or 0, y or 0)
        end
    end

    -- Reset scale
    btn:SetScale(1.0)
end

local function UpdateDungeonEyePosition()
    local settings = GetSettings()
    if not settings or not settings.enabled then return end

    local eyeSettings = settings.dungeonEye
    if not eyeSettings then return end

    local btn = QueueStatusButton
    if not btn then return end

    -- Store original state on first run (before we modify it)
    if not dungeonEyeOriginalParent then
        dungeonEyeOriginalParent = btn:GetParent()
        local point, relativeTo, relativePoint, x, y = btn:GetPoint()
        if point then
            dungeonEyeOriginalPoint = {point, relativeTo, relativePoint, x, y}
        end
    end

    if eyeSettings.enabled then
        -- Reparent to Minimap - Blizzard controls visibility based on queue status
        btn:SetParent(Minimap)
        btn:ClearAllPoints()

        -- Calculate corner position with offsets
        local corner = eyeSettings.corner or "BOTTOMRIGHT"
        local offsetX = eyeSettings.offsetX or 0
        local offsetY = eyeSettings.offsetY or 0

        -- Corner-specific positioning (inside minimap bounds)
        local cornerOffsets = {
            TOPRIGHT    = { anchor = "TOPRIGHT",    x = -5 + offsetX, y = -5 + offsetY },
            TOPLEFT     = { anchor = "TOPLEFT",     x = 5 + offsetX,  y = -5 + offsetY },
            BOTTOMRIGHT = { anchor = "BOTTOMRIGHT", x = -5 + offsetX, y = 5 + offsetY },
            BOTTOMLEFT  = { anchor = "BOTTOMLEFT",  x = 5 + offsetX,  y = 5 + offsetY },
        }

        local pos = cornerOffsets[corner] or cornerOffsets.BOTTOMRIGHT
        btn:SetPoint(pos.anchor, Minimap, pos.anchor, pos.x, pos.y)

        -- Apply scale
        local scale = eyeSettings.scale or 1.0
        btn:SetScale(scale)
        -- Do NOT call btn:Show() - let Blizzard control visibility based on queue status
    else
        -- Restore original position
        RestoreDungeonEye()
    end
end

local function SetupDungeonEyeHook()
    if dungeonEyeHooked then return end
    if not QueueStatusButton then return end

    -- Hook UpdatePosition to re-apply our positioning after Blizzard resets it
    if QueueStatusButton.UpdatePosition then
        hooksecurefunc(QueueStatusButton, "UpdatePosition", function()
            local settings = GetSettings()
            if settings and settings.dungeonEye and settings.dungeonEye.enabled then
                -- Use C_Timer.After to avoid infinite hook recursion
                C_Timer.After(0, UpdateDungeonEyePosition)
            end
        end)
        dungeonEyeHooked = true
    end
end

---=================================================================================
--- ADDON BUTTON HIDING
---=================================================================================

local function SetupAddonButtonHiding()
    local settings = GetSettings()
    if not settings or not settings.enabled or not LibDBIcon then return end
    
    if settings.hideAddonButtons then
        local buttons = LibDBIcon:GetButtonList()
        for i = 1, #buttons do
            LibDBIcon:ShowOnEnter(buttons[i], true)
        end
        
        -- Hook for new buttons
        LibDBIcon.RegisterCallback(Minimap_Module, "LibDBIcon_IconCreated", function(_, _, buttonName)
            LibDBIcon:ShowOnEnter(buttonName, true)
        end)
    else
        local buttons = LibDBIcon:GetButtonList()
        for i = 1, #buttons do
            LibDBIcon:ShowOnEnter(buttons[i], false)
        end
        LibDBIcon.UnregisterCallback(Minimap_Module, "LibDBIcon_IconCreated")
    end
end

---=================================================================================
--- MINIMAP SIZE AND POSITION
---=================================================================================

local function UpdateMinimapSize()
    local settings = GetSettings()
    if not settings or not settings.enabled then return end
    
    -- Set minimap size
    Minimap:SetSize(settings.size, settings.size)

    -- Apply scale multiplier
    Minimap:SetScale(settings.scale or 1.0)

    -- Force render update by toggling zoom
    if Minimap:GetZoom() ~= 5 then
        Minimap.ZoomIn:Click()
        Minimap.ZoomOut:Click()
    else
        Minimap.ZoomOut:Click()
        Minimap.ZoomIn:Click()
    end
    
    -- Update LibDBIcon button radius for square minimap
    if LibDBIcon then
        if settings.shape == "SQUARE" then
            LibDBIcon:SetButtonRadius(settings.buttonRadius or 2)
        else
            LibDBIcon:SetButtonRadius(1)
        end
    end
end

local function SetupMinimapDragging()
    local settings = GetSettings()
    if not settings or not settings.enabled then return end
    
    -- Reparent minimap to UIParent for proper positioning
    Minimap:SetParent(UIParent)
    Minimap:SetFrameStrata("LOW")
    Minimap:SetFrameLevel(2)
    Minimap:SetFixedFrameStrata(true)
    Minimap:SetFixedFrameLevel(true)
    
    -- Disable MinimapCluster mouse
    if MinimapCluster then
        MinimapCluster:EnableMouse(false)
    end
    
    -- Setup dragging - MUST enable mouse for drag to work
    Minimap:EnableMouse(true)
    Minimap:SetMovable(not settings.lock)
    Minimap:SetClampedToScreen(true)
    Minimap:RegisterForDrag("LeftButton")
    
    Minimap:SetScript("OnDragStart", function(self)
        if self:IsMovable() then
            self:StartMoving()
        end
    end)
    
    Minimap:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        settings.position = {point, relPoint, x, y}
    end)
    
    -- Apply saved position (handles both array format from drag and keyed format from defaults)
    local pos = settings.position
    if pos then
        local point = pos[1] or pos.point or "TOPLEFT"
        local relPoint = pos[2] or pos.relPoint or "BOTTOMLEFT"
        local x = pos[3] or pos.x or 790
        local y = pos[4] or pos.y or 285
        Minimap:ClearAllPoints()
        Minimap:SetPoint(point, UIParent, relPoint, x, y)
    else
        -- No position saved, use default
        Minimap:ClearAllPoints()
        Minimap:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 790, 285)
    end
end

---=================================================================================
--- EDIT MODE SUPPORT
---=================================================================================

-- Track original lock state for Edit Mode restoration
local editModeWasLocked = nil

-- Enable minimap movement during Edit Mode (ignore lock setting)
function QUICore:EnableMinimapEditMode()
    local settings = GetSettings()
    if not settings then return end

    -- Remember lock state
    editModeWasLocked = settings.lock

    -- Temporarily enable movement (ignore lock during Edit Mode)
    Minimap:SetMovable(true)
end

-- Disable minimap Edit Mode (restore lock setting)
function QUICore:DisableMinimapEditMode()
    local settings = GetSettings()
    if not settings then return end

    -- Restore original lock state
    if editModeWasLocked ~= nil then
        Minimap:SetMovable(not editModeWasLocked)
        editModeWasLocked = nil
    else
        Minimap:SetMovable(not settings.lock)
    end
end

---=================================================================================
--- MOUSE WHEEL ZOOM
---=================================================================================

local function SetupMouseWheelZoom()
    Minimap:EnableMouseWheel(true)
    Minimap:SetScript("OnMouseWheel", function(_, delta)
        if delta > 0 then
            Minimap.ZoomIn:Click()
        else
            Minimap.ZoomOut:Click()
        end
    end)
end

---=================================================================================
--- AUTO ZOOM OUT
---=================================================================================

local autoZoomTimer = 0
local autoZoomCurrent = 0

local function SetupAutoZoom()
    local settings = GetSettings()
    if not settings or not settings.enabled or not settings.autoZoom then return end
    
    local function ZoomOut()
        autoZoomCurrent = autoZoomCurrent + 1
        if autoZoomTimer == autoZoomCurrent then
            Minimap:SetZoom(0)
            if Minimap.ZoomIn then Minimap.ZoomIn:Enable() end
            if Minimap.ZoomOut then Minimap.ZoomOut:Disable() end
            autoZoomTimer, autoZoomCurrent = 0, 0
        end
    end
    
    local function OnZoom()
        if settings.autoZoom then
            autoZoomTimer = autoZoomTimer + 1
            C_Timer.After(10, ZoomOut)
        end
    end
    
    if Minimap.ZoomIn then
        Minimap.ZoomIn:HookScript("OnClick", OnZoom)
    end
    if Minimap.ZoomOut then
        Minimap.ZoomOut:HookScript("OnClick", OnZoom)
    end
    
    -- Initial zoom out
    OnZoom()
end

---=================================================================================
--- UPDATE TIMERS (Ticker-based for performance)
---=================================================================================

local function StartUpdateTickers()
    local settings = GetSettings()
    if not settings or not settings.enabled then return end

    -- Cancel existing tickers if any
    if clockTicker then clockTicker:Cancel() end
    if coordsTicker then coordsTicker:Cancel() end

    -- Clock ticker: Updates every 1 second
    clockTicker = C_Timer.NewTicker(1, function()
        local s = GetSettings()
        if s and s.enabled then
            UpdateClockTime()
        end
    end)

    -- Coords ticker: Updates based on setting (default 1 second)
    local coordInterval = settings.coordUpdateInterval or 1
    coordsTicker = C_Timer.NewTicker(coordInterval, function()
        local s = GetSettings()
        if s and s.enabled then
            UpdateCoordsPosition()
        end
    end)

    -- Datatext updates are handled by individual datatext tickers via the registry
end

local function StopUpdateTickers()
    if clockTicker then clockTicker:Cancel(); clockTicker = nil end
    if coordsTicker then coordsTicker:Cancel(); coordsTicker = nil end
end

---=================================================================================
--- MAIN INITIALIZATION
---=================================================================================

function Minimap_Module:Initialize()
    local settings = GetSettings()
    if not settings then return end
    
    if not settings.enabled then
        -- If disabled, make sure we don't interfere
        return
    end
    
    -- Set shape first (affects other elements)
    SetMinimapShape(settings.shape)
    
    -- Create and update elements
    CreateBackdrop()
    UpdateBackdrop()
    
    SetupMinimapDragging()
    UpdateMinimapSize()
    
    CreateClock()
    UpdateClock()
    UpdateClockTime()
    
    CreateCoords()
    UpdateCoords()
    UpdateCoordsPosition()
    
    CreateZoneText()
    UpdateZoneText()
    
    -- Datatext panel (integrated below minimap with 3 slots)
    CreateDatatextPanel()
    UpdateDatatextPanel()

    UpdateButtonVisibility()
    SetupAddonButtonHiding()
    SetupDungeonEyeHook()
    UpdateDungeonEyePosition()
    SetupMouseWheelZoom()
    SetupAutoZoom()

    -- Start performance-optimized ticker updates
    StartUpdateTickers()

    -- Hide Blizzard decorations
    if MinimapBackdrop then
        MinimapBackdrop:Hide()
    end
    if MinimapNorthTag then
        MinimapNorthTag:SetParent(CreateFrame("Frame"))
    end
    if MinimapBorder then
        MinimapBorder:SetParent(CreateFrame("Frame"))
    end
    if MinimapBorderTop then
        MinimapBorderTop:SetParent(CreateFrame("Frame"))
    end
    
    -- Hide any backdrop on the Minimap itself (this removes the built-in border)
    if Minimap.SetBackdrop then
        Minimap:SetBackdrop(nil)
    end
    
    -- Hide the backdrop edge textures that Blizzard creates (LeftEdge, RightEdge, TopEdge, BottomEdge, corners, etc.)
    local edgeNames = {"LeftEdge", "RightEdge", "TopEdge", "BottomEdge", "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner", "Center"}
    for _, edgeName in ipairs(edgeNames) do
        if Minimap[edgeName] then
            Minimap[edgeName]:Hide()
            Minimap[edgeName]:SetAlpha(0)
        end
    end
    
    -- Also check for backdropInfo table which stores edge references
    if Minimap.backdropInfo then
        for _, edgeName in ipairs(edgeNames) do
            if Minimap.backdropInfo[edgeName] then
                Minimap.backdropInfo[edgeName] = nil
            end
        end
    end
    
    -- Hide MinimapCluster backdrop if it exists
    if MinimapCluster and MinimapCluster.SetBackdrop then
        MinimapCluster:SetBackdrop(nil)
    end
    
    -- Hide the minimap's built-in border texture if present
    if Minimap.BorderTop then
        Minimap.BorderTop:Hide()
    end
    if Minimap.Background then
        Minimap.Background:Hide()
    end
    
    -- Iterate through all children to find and hide edge textures
    for _, child in pairs({Minimap:GetChildren()}) do
        -- Check if child has edge-related name or is a backdrop frame
        local name = child:GetName()
        if name and (name:find("Edge") or name:find("Corner") or name:find("Border")) then
            child:Hide()
        end
        -- Also hide any backdrop on child frames
        if child.SetBackdrop then
            child:SetBackdrop(nil)
        end
    end
end

function Minimap_Module:Refresh()
    -- Invalidate cached settings so we get fresh values
    InvalidateSettingsCache()

    local settings = GetSettings()

    -- Handle case where settings don't exist at all
    if not settings then
        return
    end

    -- Handle disabled state - ensure minimap is still visible in Blizzard default state
    if not settings.enabled then
        StopUpdateTickers()
        -- Hide QUI customizations but keep minimap visible
        if minimapBackdrop then
            minimapBackdrop:Hide()
        end
        if datatextPanel then
            datatextPanel:Hide()
        end
        -- Ensure minimap is still visible
        Minimap:Show()
        return
    end

    -- Restart tickers with potentially new intervals
    StartUpdateTickers()

    SetMinimapShape(settings.shape)
    UpdateBackdrop()
    UpdateMinimapSize()
    UpdateClock()
    UpdateCoords()
    UpdateZoneText()
    UpdateDatatextPanel()
    UpdateButtonVisibility()
    SetupAddonButtonHiding()
    UpdateDungeonEyePosition()

    -- Update lock/movable state and ensure drag is registered
    Minimap:SetMovable(not settings.lock)
    Minimap:EnableMouse(true)
    Minimap:RegisterForDrag("LeftButton")
    
    -- Re-setup drag scripts (may have been lost)
    Minimap:SetScript("OnDragStart", function(self)
        if self:IsMovable() then
            self:StartMoving()
        end
    end)
    
    Minimap:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        settings.position = {point, relPoint, x, y}
    end)
    
    -- Restore saved position from profile (validate position data exists)
    if settings.position and settings.position[1] and settings.position[2] then
        Minimap:ClearAllPoints()
        Minimap:SetPoint(settings.position[1], UIParent, settings.position[2], settings.position[3] or 0, settings.position[4] or 0)
    end
end

-- Expose datatext refresh for config panel
function Minimap_Module:RefreshDatatext()
    UpdateDatatextPanel()
end

---=================================================================================
--- EVENT HANDLING
---=================================================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("ADDON_LOADED")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Blizzard_HybridMinimap" then
        -- Handle HybridMinimap loading (Delves/scenarios)
        local settings = GetSettings()
        if settings and settings.enabled then
            SetMinimapShape(settings.shape)
        end
    elseif event == "PLAYER_LOGIN" then
        -- Delay initialization slightly to ensure all frames exist
        C_Timer.After(0.5, function()
            Minimap_Module:Initialize()
        end)
    end
end)

-- Calendar pending invites handling
local calendarFrame = CreateFrame("Frame")
calendarFrame:RegisterEvent("CALENDAR_UPDATE_PENDING_INVITES")
calendarFrame:RegisterEvent("CALENDAR_ACTION_PENDING")
calendarFrame:SetScript("OnEvent", function()
    local settings = GetSettings()
    if not settings or not settings.enabled then return end
    
    if settings.showCalendar and GameTimeFrame then
        if C_Calendar.GetNumPendingInvites() < 1 then
            GameTimeFrame:Hide()
        else
            GameTimeFrame:Show()
        end
    end
end)

-- Pet battle handling
local petBattleFrame = CreateFrame("Frame")
petBattleFrame:RegisterEvent("PET_BATTLE_OPENING_START")
petBattleFrame:RegisterEvent("PET_BATTLE_CLOSE")
petBattleFrame:SetScript("OnEvent", function(self, event)
    if event == "PET_BATTLE_OPENING_START" then
        Minimap:Hide()
    else
        Minimap:Show()
    end
end)

