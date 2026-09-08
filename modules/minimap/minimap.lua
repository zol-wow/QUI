local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local Helpers = ns.Helpers
local SkinBase = ns.SkinBase

local function CJKFont(fs, p, s, f)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fs, p, s, f)
    else
        fs:SetFont(p, s, f)
    end
end
local LSM = ns.LSM
local LibDBIcon = LibStub("LibDBIcon-1.0", true)

local Minimap_Module = {}
QUICore.Minimap = Minimap_Module

local Minimap = Minimap
local MinimapCluster = MinimapCluster
local UIParent = UIParent

local backdropFrame, backdrop, mask
local clockFrame, clockText
local coordsFrame, coordsText
local zoneTextFrame, zoneTextFont
local greatVaultButton
local customMailButton
local minimapTooltip
local middleClickMenuFrame
local middleClickMenuBlocker
local middleClickMenuRows = {}

local minimapAnchor

local datatextFrame

local cachedSettings = nil
local lastAppliedZoomLevel = nil
local clockTicker = nil
local coordsTicker = nil

local inInitSafeWindow = false
local pendingMinimapRefresh = false
local pendingDrawerSetup = false
local pendingDatatextPanelUpdate = false
local middleClickMenuHooked = false

local externalHudActive = false
local quiUpdatingMinimap = false
local hudDetectedCount = 0
local HUD_DEBOUNCE_THRESHOLD = 2
local HUD_CHECK_SUPPRESS_DURATION = 0.5
local MINIMAP_RENDER_ZOOM_NUDGE_ENABLED = false
local suppressHudChecksUntil = 0
local externalHudHooksInstalled = false
local externalHudTicker = nil
local externalHudCheckPending = false
local minimapDebugStats = {
    lastFlush = 0,
    refresh = 0,
    size = 0,
    datatextPanel = 0,
    datatextSlots = 0,
    hud = 0,
    hudDefer = 0,
    hideDecor = 0,
    zoomNudge = 0,
}

local function InstallMinimapLayoutNoop()
    if Minimap and not Minimap.Layout then
        ---@type fun(...)
        Minimap.Layout = function() end
        return true
    end
    return Minimap and Minimap.Layout ~= nil
end

if not InCombatLockdown() then
    InstallMinimapLayoutNoop()
else
    local layoutRetryFrame = CreateFrame("Frame")
    layoutRetryFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    layoutRetryFrame:SetScript("OnEvent", function(self)
        if InstallMinimapLayoutNoop() then
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            self:SetScript("OnEvent", nil)
        end
    end)
end

local function GetSettings()
    if cachedSettings then return cachedSettings end
    cachedSettings = Helpers.GetModuleDB("minimap")
    return cachedSettings
end

local function InvalidateSettingsCache()
    cachedSettings = nil
end

local function MissionButtonInDrawer()
    local s = GetSettings()
    if not s then return false end
    return (s.showMissions and s.missionsInDrawer
        and s.buttonDrawer and s.buttonDrawer.enabled) and true or false
end

local function SuppressExternalHudChecks(duration)
    local now = (type(GetTime) == "function") and GetTime() or 0
    suppressHudChecksUntil = math.max(suppressHudChecksUntil or 0, now + (duration or HUD_CHECK_SUPPRESS_DURATION))
end

local function BeginQUIControlledMinimapUpdate(duration)
    quiUpdatingMinimap = true
    SuppressExternalHudChecks(duration)
end

local function EndQUIControlledMinimapUpdate(duration)
    SuppressExternalHudChecks(duration)
    quiUpdatingMinimap = false
end

local function IsExternalHudCheckSuppressed()
    if quiUpdatingMinimap then
        return true
    end

    local now = (type(GetTime) == "function") and GetTime() or 0
    return now < (suppressHudChecksUntil or 0)
end

local function IsMinimapDebugEnabled()
    local addon = _G.QUI
    return addon and addon.DEBUG_MODE and type(addon.DebugPrint) == "function"
end

local function MinimapDebugPrint(...)
    local addon = _G.QUI
    if addon and type(addon.DebugPrint) == "function" then
        addon:DebugPrint("|cff8be9fd[MinimapDbg]|r", ...)
    end
end

local function FlushMinimapDebugStats(force)
    if not IsMinimapDebugEnabled() then return end

    local stats = minimapDebugStats
    local total = (stats.refresh or 0)
        + (stats.size or 0)
        + (stats.datatextPanel or 0)
        + (stats.datatextSlots or 0)
        + (stats.hud or 0)
        + (stats.hudDefer or 0)
        + (stats.hideDecor or 0)
        + (stats.zoomNudge or 0)
    if total == 0 and not force then return end

    local now = (type(GetTime) == "function") and GetTime() or 0
    if not force and (now - (stats.lastFlush or 0)) < 1 then
        return
    end

    stats.lastFlush = now

    stats.refresh = 0
    stats.size = 0
    stats.datatextPanel = 0
    stats.datatextSlots = 0
    stats.hud = 0
    stats.hudDefer = 0
    stats.hideDecor = 0
    stats.zoomNudge = 0
end

local function CountMinimapDebug(key)
    if not IsMinimapDebugEnabled() then return end
    minimapDebugStats[key] = (minimapDebugStats[key] or 0) + 1
    FlushMinimapDebugStats(false)
end

local function LogExternalHudTransition(state, reason, scale, alpha, width, parent)
    if not IsMinimapDebugEnabled() then return end
    MinimapDebugPrint(format(
        "externalHud=%s reason=%s scale=%.2f alpha=%.2f width=%.1f parent=%s",
        state and "on" or "off",
        tostring(reason or "unknown"),
        tonumber(scale) or 0,
        tonumber(alpha) or 0,
        tonumber(width) or 0,
        tostring(parent or "nil")
    ))
end

local function GetClassColor()
    local _, class = UnitClass("player")
    return Helpers.GetClassColorTable(class)
end

local function SafeExecute(func)
    if type(func) ~= "function" then return end
    local ok = pcall(func)
    return ok
end

local function ClickMicroButton(...)
    for i = 1, select("#", ...) do
        local button = _G[select(i, ...)]
        if button and button.IsShown and button:IsShown() and button.Click then
            button:Click()
            return true
        end
    end

    for i = 1, select("#", ...) do
        local button = _G[select(i, ...)]
        if button and button.Click then
            button:Click()
            return true
        end
    end

    return false
end

local PLAYER_SPELLS_TABS = {
    spellbook = {
        subFrame = "SpellBookFrame",
        labels = { "SPELLBOOK", "SPELLBOOK_ABILITIES_BUTTON" },
        candidates = {
            "PlayerSpellsFrameSpellBookFrameTabButton",
            "PlayerSpellsFrameSpellBookTabButton",
            "PlayerSpellsSpellBookTabButton",
        },
        micro = { "SpellbookMicroButton" },
        toggle = function() ToggleSpellBook(BOOKTYPE_SPELL) end,
    },
    talents = {
        subFrame = "TalentsFrame",
        labels = { "TALENTS" },
        candidates = {
            "PlayerSpellsFrameTalentsFrameTabButton",
            "PlayerSpellsFrameTalentsTabButton",
            "PlayerSpellsTalentsTabButton",
        },
        micro = { "TalentMicroButton", "PlayerSpellsMicroButton" },
        toggle = function() ToggleTalentFrame() end,
    },
    specialization = {
        subFrame = "SpecFrame",
        labels = { "SPECIALIZATION", "SPECIALIZATIONS" },
        candidates = {
            "PlayerSpellsFrameSpecFrameTabButton",
            "PlayerSpellsFrameSpecTabButton",
            "PlayerSpellsFrameSpecializationTabButton",
            "PlayerSpellsSpecializationTabButton",
        },
        micro = { "PlayerSpellsMicroButton", "TalentMicroButton" },
    },
}

local function ActivatePlayerSpellsTab(def)
    local function MatchesTabLabel(label)
        for i = 1, #def.labels do
            local want = _G[def.labels[i]]
            if want and want ~= "" and (label == want or label:find(want, 1, true)) then
                return true
            end
        end
        return false
    end

    local function FindAndClickTabButton(parent, maxDepth, depth)
        if not parent or depth > maxDepth then return false end
        local children = { parent:GetChildren() }
        for i = 1, #children do
            local child = children[i]
            if child then
                if child.IsObjectType and child:IsObjectType("Button") and child.Click then
                    local label = nil
                    if child.GetText then
                        label = child:GetText()
                    end
                    if (not label or label == "") and child.Text and child.Text.GetText then
                        label = child.Text:GetText()
                    end
                    if label and label ~= "" and MatchesTabLabel(label) then
                        child:Click()
                        return true
                    end
                end

                if FindAndClickTabButton(child, maxDepth, depth + 1) then
                    return true
                end
            end
        end
        return false
    end

    local frame = _G.PlayerSpellsFrame
    if not frame or (frame.IsShown and not frame:IsShown()) then
        return false
    end

    local sub = frame[def.subFrame]
    if sub then
        if sub.TabButton and sub.TabButton.Click then
            sub.TabButton:Click()
            return true
        end
        if sub.Show then
            sub:Show()
        end
    end

    if ClickMicroButton(unpack(def.candidates)) then
        return true
    end

    return FindAndClickTabButton(frame, 4, 0)
end

local function TryOpenPlayerSpellsTab(key)
    local def = PLAYER_SPELLS_TABS[key]
    if not def then return false end

    local opened = false
    if ClickMicroButton(unpack(def.micro)) then
        opened = true
    elseif def.toggle and SafeExecute(def.toggle) then
        opened = true
    else
        opened = SafeExecute(TogglePlayerSpellsFrame) and true or false
    end

    local function Activate()
        return ActivatePlayerSpellsTab(def)
    end

    local activated = Activate()
    if not activated then
        C_Timer.After(0, Activate)
        C_Timer.After(0.05, Activate)
        C_Timer.After(0.15, Activate)
    end

    return opened or activated
end

local function SetMinimapShape(shape)
    if shape == "SQUARE" then
        Minimap:SetMaskTexture("Interface\\BUTTONS\\WHITE8X8")
        if mask then
            mask:SetTexture("Interface\\BUTTONS\\WHITE8X8")
        end
        _G.GetMinimapShape = function() return "SQUARE" end

        if HybridMinimap then
            HybridMinimap.MapCanvas:SetUseMaskTexture(false)
            HybridMinimap.CircleMask:SetTexture("Interface\\BUTTONS\\WHITE8X8")
            HybridMinimap.MapCanvas:SetUseMaskTexture(true)
        end

        Minimap:SetArchBlobRingScalar(0)
        Minimap:SetArchBlobRingAlpha(0)
        Minimap:SetQuestBlobRingScalar(0)
        Minimap:SetQuestBlobRingAlpha(0)
    else
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

    if LibDBIcon then
        local buttons = LibDBIcon:GetButtonList()
        for i = 1, #buttons do
            LibDBIcon:Refresh(buttons[i])
        end
    end
end

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
    if not settings then return end
    if not backdrop then CreateBackdrop() end

    backdropFrame:Show()

    local fullSize = settings.size + (settings.borderSize * 2)
    backdrop:SetSize(fullSize, fullSize)

    local r, g, b, a = Helpers.GetSkinBorderColor(settings, "")
    backdrop:SetColorTexture(r, g, b, a)

    if settings.shape == "SQUARE" then
        mask:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    else
        mask:SetTexture("Interface\\MINIMAP\\UI-Minimap-Background")
    end
end

local function GetDatatextSettings()
    if not QUICore or not QUICore.db or not QUICore.db.profile then
        return nil
    end
    return QUICore.db.profile.datatext
end

local function CreateDatatextPanel()
    if datatextFrame then return end

    datatextFrame = CreateFrame("Frame", "QUI_DatatextPanel", UIParent)
    datatextFrame:SetFrameStrata("LOW")
    datatextFrame:SetFrameLevel(100)

    datatextFrame.borderLeft = datatextFrame:CreateTexture(nil, "BACKGROUND")
    datatextFrame.borderRight = datatextFrame:CreateTexture(nil, "BACKGROUND")
    datatextFrame.borderTop = datatextFrame:CreateTexture(nil, "BACKGROUND")
    datatextFrame.borderBottom = datatextFrame:CreateTexture(nil, "BACKGROUND")

    datatextFrame.bg = datatextFrame:CreateTexture(nil, "BACKGROUND")
    datatextFrame.bg:SetAllPoints()

    datatextFrame.slots = {}
    for i = 1, 3 do
        local slot = CreateFrame("Button", nil, datatextFrame)
        slot:EnableMouse(true)
        slot:RegisterForClicks("AnyUp")

        slot.text = slot:CreateFontString(nil, "OVERLAY")
        slot.text:SetPoint("LEFT", slot, "LEFT", 1, 0)
        slot.text:SetPoint("RIGHT", slot, "RIGHT", -1, 0)
        slot.text:SetJustifyH("CENTER")
        slot.text:SetWordWrap(false)
        slot.index = i

        datatextFrame.slots[i] = slot
    end
end

local function RefreshDatatextSlots()
    if not datatextFrame or not datatextFrame.slots then return end
    if not QUICore or not QUICore.Datatexts then return end
    CountMinimapDebug("datatextSlots")

    local dtSettings = GetDatatextSettings()
    if not dtSettings then return end

    local slots = dtSettings.slots or {"time", "friends", "guild"}

    local generalFont = "Quazii"
    local generalOutline = "OUTLINE"
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general then
        local general = QUICore.db.profile.general
        generalFont = general.font or "Quazii"
        generalOutline = general.fontOutline or "OUTLINE"
    end
    local fontPath = LSM:Fetch("font", generalFont) or "Fonts\\FRIZQT__.TTF"
    local fontSize = dtSettings.fontSize or 12

    local activeCount = 0
    for i = 1, 3 do
        local datatextID = slots[i]
        if datatextID and datatextID ~= "" then
            activeCount = activeCount + 1
        end
    end

    local panelWidth = datatextFrame:GetWidth()
    local slotWidth = panelWidth / math.max(1, activeCount)
    local slotHeight = datatextFrame:GetHeight()

    local xPos = 0
    for i, slot in ipairs(datatextFrame.slots) do
        local datatextID = slots[i]
        local slotConfig = dtSettings["slot" .. i] or {}

        if slot.datatextInstance then
            QUICore.Datatexts:DetachFromSlot(slot)
        end

        QUICore:SafeSetFont(slot.text, fontPath, fontSize, generalOutline)

        if datatextID and datatextID ~= "" then
            slot:SetSize(slotWidth, slotHeight)
            slot:ClearAllPoints()
            local xOff = slotConfig.xOffset or 0
            local yOff = slotConfig.yOffset or 0
            slot:SetPoint("LEFT", datatextFrame, "LEFT", xPos + xOff, yOff)
            slot:Show()
            xPos = xPos + slotWidth

            slot.text:SetTextColor(1, 1, 1, 1)

            slot.shortLabel = slotConfig.shortLabel or false
            slot.noLabel = slotConfig.noLabel or false

            QUICore.Datatexts:AttachToSlot(slot, datatextID, dtSettings)
        else
            slot:Hide()
            slot.text:SetText("")
        end
    end
end

local function UpdateDatatextPanel()
    if InCombatLockdown() and not (inInitSafeWindow or ns._inInitSafeWindow) then
        pendingDatatextPanelUpdate = true
        return
    end

    local minimapSettings = GetSettings()
    local dtSettings = GetDatatextSettings()
    CountMinimapDebug("datatextPanel")

    if not minimapSettings then return end
    if not dtSettings or not dtSettings.enabled then
        if datatextFrame then datatextFrame:Hide() end
        return
    end

    if not (QUICore and QUICore.Datatexts) then
        if datatextFrame then datatextFrame:Hide() end
        return
    end

    if not datatextFrame then CreateDatatextPanel() end

    local minimapSize = minimapSettings.size or 160
    local minimapScale = minimapSettings.scale or 1.0
    local minimapBorderSize = minimapSettings.borderSize or 3
    local dtBorderSize = dtSettings.borderSize or 2
    local dtBr, dtBg, dtBb, dtBa = Helpers.GetSkinBorderColor(dtSettings, "")
    local dtBorderColor = { dtBr, dtBg, dtBb, dtBa }
    local dtHeight = dtSettings.height or 22
    local yOffset = dtSettings.offsetY or 0
    local bgAlpha = (dtSettings.bgOpacity or 60) / 100

    datatextFrame:SetSize(minimapSize, dtHeight)

    if minimapScale ~= 1.0 then
        datatextFrame:SetScale(minimapScale)
    elseif datatextFrame:GetScale() ~= 1 then
        datatextFrame:SetScale(1)
    end

    datatextFrame:ClearAllPoints()
    datatextFrame:SetPoint("TOP", Minimap, "BOTTOM", 0, -(minimapBorderSize + yOffset))

    datatextFrame.borderLeft:ClearAllPoints()
    datatextFrame.borderLeft:SetPoint("TOPRIGHT", datatextFrame, "TOPLEFT", 0, dtBorderSize)
    datatextFrame.borderLeft:SetPoint("BOTTOMRIGHT", datatextFrame, "BOTTOMLEFT", 0, -dtBorderSize)
    datatextFrame.borderLeft:SetWidth(dtBorderSize)
    datatextFrame.borderLeft:SetColorTexture(unpack(dtBorderColor))

    datatextFrame.borderRight:ClearAllPoints()
    datatextFrame.borderRight:SetPoint("TOPLEFT", datatextFrame, "TOPRIGHT", 0, dtBorderSize)
    datatextFrame.borderRight:SetPoint("BOTTOMLEFT", datatextFrame, "BOTTOMRIGHT", 0, -dtBorderSize)
    datatextFrame.borderRight:SetWidth(dtBorderSize)
    datatextFrame.borderRight:SetColorTexture(unpack(dtBorderColor))

    datatextFrame.borderTop:ClearAllPoints()
    datatextFrame.borderTop:SetPoint("BOTTOMLEFT", datatextFrame, "TOPLEFT", 0, 0)
    datatextFrame.borderTop:SetPoint("BOTTOMRIGHT", datatextFrame, "TOPRIGHT", 0, 0)
    datatextFrame.borderTop:SetHeight(dtBorderSize)
    datatextFrame.borderTop:SetColorTexture(unpack(dtBorderColor))

    datatextFrame.borderBottom:ClearAllPoints()
    datatextFrame.borderBottom:SetPoint("TOPLEFT", datatextFrame, "BOTTOMLEFT", 0, 0)
    datatextFrame.borderBottom:SetPoint("TOPRIGHT", datatextFrame, "BOTTOMRIGHT", 0, 0)
    datatextFrame.borderBottom:SetHeight(dtBorderSize)
    datatextFrame.borderBottom:SetColorTexture(unpack(dtBorderColor))

    local showBorder = dtBorderSize > 0
    datatextFrame.borderLeft:SetShown(showBorder)
    datatextFrame.borderRight:SetShown(showBorder)
    datatextFrame.borderTop:SetShown(showBorder)
    datatextFrame.borderBottom:SetShown(showBorder)

    do
        local bgR, bgG, bgB = 0, 0, 0
        if Helpers and Helpers.GetSkinBgColor then
            bgR, bgG, bgB = Helpers.GetSkinBgColor()
        end
        datatextFrame.bg:SetColorTexture(bgR or 0, bgG or 0, bgB or 0, bgAlpha)
    end

    datatextFrame:Show()

    RefreshDatatextSlots()
end

local function CreateClock()
    if clockFrame then return end

    clockFrame = CreateFrame("Button", nil, Minimap)
    clockText = clockFrame:CreateFontString(nil, "OVERLAY")
    clockText:SetAllPoints(clockFrame)

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
        GameTooltip:AddLine(ns.L["|cffFFFFFFLeft Click:|r Open Calendar"], 0.2, 1, 0.2)
        GameTooltip:AddLine(ns.L["|cffFFFFFFRight Click:|r Toggle Clock"], 0.2, 1, 0.2)
        GameTooltip:Show()
    end)

    clockFrame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function UpdateClock()
    local settings = GetSettings()
    if not settings then return end
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

    local generalFont = "Quazii"
    local generalOutline = "OUTLINE"
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general then
        local general = QUICore.db.profile.general
        generalFont = general.font or "Quazii"
        generalOutline = general.fontOutline or "OUTLINE"
    end

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

    local r, g, b, a = unpack(clockConfig.color)
    if clockConfig.useClassColor then
        local color = GetClassColor()
        if color then
            r, g, b = color.r, color.g, color.b
        end
    end
    clockText:SetTextColor(r, g, b, a)

    clockText:SetText("99:99")
    local width = clockText:GetUnboundedStringWidth()
    clockFrame:SetWidth(width + 5)
end

local function UpdateClockTime()
    if not clockFrame or not clockText then return end
    local settings = GetSettings()
    if not settings or not settings.showClock then return end

    local clockConfig = settings.clockConfig

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

local function CreateCoords()
    if coordsFrame then return end

    coordsFrame = CreateFrame("Frame", nil, Minimap)
    coordsText = coordsFrame:CreateFontString(nil, "OVERLAY")
    coordsText:SetAllPoints(coordsFrame)
end

local function UpdateCoords()
    local settings = GetSettings()
    if not settings then return end
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

    local r, g, b, a = unpack(coordsConfig.color)
    if coordsConfig.useClassColor then
        local color = GetClassColor()
        if color then
            r, g, b = color.r, color.g, color.b
        end
    end
    coordsText:SetTextColor(r, g, b, a)

    coordsText:SetFormattedText(settings.coordPrecision, 100.77, 100.77)
    local width = coordsText:GetUnboundedStringWidth()
    coordsFrame:SetWidth(width + 5)
end

local function UpdateCoordsPosition()
    if not coordsFrame or not coordsText then return end
    local settings = GetSettings()
    if not settings or not settings.showCoords then return end

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

local UpdateZoneTextDisplay

local function CreateZoneText()
    if zoneTextFrame then return end

    zoneTextFrame = CreateFrame("Button", nil, Minimap)
    zoneTextFont = zoneTextFrame:CreateFontString(nil, "OVERLAY")
    zoneTextFont:SetAllPoints(zoneTextFrame)

    if MinimapCluster and MinimapCluster.ZoneTextButton then
        MinimapCluster.ZoneTextButton:SetParent(CreateFrame("Frame"))
        MinimapCluster.ZoneTextButton:Hide()
    end
    if MinimapCluster and MinimapCluster.BorderTop then
        local hiddenBorder = CreateFrame("Frame")
        hiddenBorder:Hide()
        MinimapCluster.BorderTop:SetParent(hiddenBorder)
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
    if not settings then return end
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

    local generalFont = "Quazii"
    local generalOutline = "OUTLINE"
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general then
        local general = QUICore.db.profile.general
        generalFont = general.font or "Quazii"
        generalOutline = general.fontOutline or "OUTLINE"
    end

    local flags
    if zoneConfig.monochrome and zoneConfig.outline ~= "NONE" then
        flags = "MONOCHROME," .. zoneConfig.outline
    elseif zoneConfig.monochrome then
        flags = "MONOCHROME"
    else
        flags = generalOutline
    end

    local fontPath = LSM:Fetch("font", generalFont) or "Fonts\\FRIZQT__.TTF"
    QUICore:SafeSetFont(zoneTextFont, fontPath, zoneConfig.fontSize, flags)
    zoneTextFont:SetJustifyH(zoneConfig.align)

    UpdateZoneTextDisplay()
end

UpdateZoneTextDisplay = function()
    if not zoneTextFrame or not zoneTextFont then return end
    local settings = GetSettings()
    if not settings or not settings.showZoneText then return end

    local zoneConfig = settings.zoneTextConfig

    local currentFont = zoneTextFont:GetFont()
    if not currentFont then
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

    if zoneConfig.allCaps then
        text = Helpers.UpperUTF8(text)
    end

    zoneTextFont:SetText(text)

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

local hiddenButtonParent = CreateFrame("Frame")
hiddenButtonParent:Hide()
hiddenButtonParent.Layout = function() end

local function ForEachDifficultyFrame(callback)
    if type(callback) ~= "function" then return end

    local seen = {}
    local function handle(frame)
        if frame and not seen[frame] then
            seen[frame] = true
            callback(frame)
        end
    end

    if MinimapCluster and MinimapCluster.InstanceDifficulty then
        handle(MinimapCluster.InstanceDifficulty)
    end

    handle(_G.MiniMapInstanceDifficulty)
    handle(_G.GuildInstanceDifficulty)
    handle(_G.MiniMapChallengeMode)
end

local ADDON_ASSET_ROOT = ns.Helpers.AssetPath or "Interface\\AddOns\\QUI\\assets\\"
local GREAT_VAULT_ICON_PATH = ADDON_ASSET_ROOT .. "great_vault_64.png"
local GREAT_VAULT_BUTTON_SIZE = 24
local GREAT_VAULT_DEFAULT_ANCHOR = "TOPLEFT"
local GREAT_VAULT_VALID_ANCHORS = {
    TOPLEFT = true,
    TOP = true,
    TOPRIGHT = true,
    LEFT = true,
    CENTER = true,
    RIGHT = true,
    BOTTOMLEFT = true,
    BOTTOM = true,
    BOTTOMRIGHT = true,
}
local MAIL_ICON_UP_ATLAS = "UI-HUD-Minimap-Mail-Up"
local MAIL_ICON_OVER_ATLAS = "UI-HUD-Minimap-Mail-Mouseover"
local greatVaultHoverHooksInstalled = false

local function HasUnreadMailSafe()
    if type(HasNewMail) ~= "function" then
        return false
    end

    local ok, raw = pcall(HasNewMail)
    if not ok then
        return false
    end

    if type(issecretvalue) == "function" and issecretvalue(raw) then
        return false
    end

    return raw and true or false
end

local function GetGreatVaultTargetAlpha()
    local settings = GetSettings()
    local vaultSettings = settings and settings.greatVault
    if not vaultSettings or not vaultSettings.enabled or not vaultSettings.fadeWhenMouseOut then
        return 1
    end

    if (greatVaultButton and greatVaultButton:IsMouseOver()) or (Minimap and Minimap:IsMouseOver()) then
        return 1
    end

    local alpha = vaultSettings.fadeOpacity
    if type(alpha) ~= "number" then
        alpha = 0
    end

    if alpha < 0 then
        alpha = 0
    elseif alpha > 1 then
        alpha = 1
    end

    return alpha
end

local function UpdateGreatVaultButtonAlpha()
    if not greatVaultButton then return end
    greatVaultButton:SetAlpha(GetGreatVaultTargetAlpha())
end

local function ScheduleGreatVaultButtonAlphaUpdate()
    C_Timer.After(0, function()
        if greatVaultButton and greatVaultButton:IsShown() then
            UpdateGreatVaultButtonAlpha()
        end
    end)
end

local function RegisterGreatVaultEscClose()
    if not UISpecialFrames then return end
    for _, name in ipairs(UISpecialFrames) do
        if name == "WeeklyRewardsFrame" then
            return
        end
    end
    table.insert(UISpecialFrames, "WeeklyRewardsFrame")
end

local function ToggleGreatVault()
    local IsLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
    local Load = (C_AddOns and C_AddOns.LoadAddOn) or _G.LoadAddOn
    if Load and IsLoaded and not IsLoaded("Blizzard_WeeklyRewards") then
        Load("Blizzard_WeeklyRewards")
    end

    RegisterGreatVaultEscClose()
    if WeeklyRewardsFrame then
        WeeklyRewardsFrame:SetShown(not WeeklyRewardsFrame:IsShown())
    end
end

local function CreateGreatVaultButton()
    if greatVaultButton then return end

    greatVaultButton = ns.UIKit.CreateIconButton(UIParent, {
        name = "QUI_GreatVaultButton",
        size = GREAT_VAULT_BUTTON_SIZE,
        icon = GREAT_VAULT_ICON_PATH,
        registerClicks = "LeftButtonUp",
        tooltipAnchor = "ANCHOR_LEFT",
        tooltip = function(self)
            GameTooltip:AddLine(ns.L["Great Vault"], 1, 1, 1)
            GameTooltip:AddLine(ns.L["|cffFFFFFFLeft Click:|r Open Great Vault"], 0.2, 1, 0.2)
        end,
        onClick = function()
            ToggleGreatVault()
        end,
        onEnter = function()
            UpdateGreatVaultButtonAlpha()
        end,
        onLeave = function()
            ScheduleGreatVaultButtonAlphaUpdate()
        end,
    })
    greatVaultButton:SetFrameStrata("MEDIUM")
    greatVaultButton:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 10)
    greatVaultButton:EnableMouse(true)

    if not greatVaultHoverHooksInstalled and Minimap then
        greatVaultHoverHooksInstalled = true
        Minimap:HookScript("OnEnter", ScheduleGreatVaultButtonAlphaUpdate)
        Minimap:HookScript("OnLeave", ScheduleGreatVaultButtonAlphaUpdate)
    end
end

local function UpdateGreatVaultButton()
    local settings = GetSettings()
    local vaultSettings = settings and settings.greatVault

    if not vaultSettings or not vaultSettings.enabled then
        if greatVaultButton then
            greatVaultButton:SetAlpha(1)
            greatVaultButton:Hide()
        end
        return
    end

    CreateGreatVaultButton()

    if not vaultSettings.anchor then
        vaultSettings.anchor = GREAT_VAULT_DEFAULT_ANCHOR
    end
    if vaultSettings.offsetX == nil then
        vaultSettings.offsetX = 1
    end
    if vaultSettings.offsetY == nil then
        vaultSettings.offsetY = -1
    end

    local anchor = vaultSettings.anchor or GREAT_VAULT_DEFAULT_ANCHOR
    if not GREAT_VAULT_VALID_ANCHORS[anchor] then
        anchor = GREAT_VAULT_DEFAULT_ANCHOR
        vaultSettings.anchor = anchor
    end
    greatVaultButton:SetParent(UIParent)
    greatVaultButton:SetFrameStrata("MEDIUM")
    greatVaultButton:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 10)
    greatVaultButton:ClearAllPoints()
    greatVaultButton:SetPoint(anchor, Minimap, anchor, vaultSettings.offsetX or 0, vaultSettings.offsetY or 0)
    greatVaultButton:SetScale(vaultSettings.scale or 1.0)
    greatVaultButton:Show()
    UpdateGreatVaultButtonAlpha()
end

local function ShowCustomMailTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")

    if type(MinimapMailFrameUpdate) == "function" then
        local ok = ns.SafeCall("best-effort-style", MinimapMailFrameUpdate)
        if ok then
            return
        end
    end

    local senders = {}
    if type(GetLatestThreeSenders) == "function" then
        local ok, sender1, sender2, sender3 = ns.SafeCall("best-effort-style", GetLatestThreeSenders)
        if ok then
            if sender1 then senders[#senders + 1] = sender1 end
            if sender2 then senders[#senders + 1] = sender2 end
            if sender3 then senders[#senders + 1] = sender3 end
        end
    end

    local headerText = #senders >= 1 and (HAVE_MAIL_FROM or "Unread mail from:") or (HAVE_MAIL or "You have unread mail")
    if type(FormatUnreadMailTooltip) == "function" then
        FormatUnreadMailTooltip(GameTooltip, headerText, senders)
    else
        GameTooltip:SetText(headerText)
        for _, sender in ipairs(senders) do
            GameTooltip:AddLine(sender)
        end
    end
    GameTooltip:Show()
end

local function CreateCustomMailButton()
    if customMailButton then return end

    customMailButton = CreateFrame("Button", "QUI_MinimapMailButton", UIParent)
    customMailButton:SetSize(20, 20)
    customMailButton:SetFrameStrata("MEDIUM")
    customMailButton:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 10)
    customMailButton:EnableMouse(true)

    local icon = customMailButton:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetAtlas(MAIL_ICON_UP_ATLAS)
    customMailButton.icon = icon

    customMailButton:SetScript("OnEnter", function(self)
        self.icon:SetAtlas(MAIL_ICON_OVER_ATLAS)
        ShowCustomMailTooltip(self)
    end)
    customMailButton:SetScript("OnLeave", function(self)
        self.icon:SetAtlas(MAIL_ICON_UP_ATLAS)
        GameTooltip:Hide()
    end)
end

local function UpdateCustomMailButton()
    local settings = GetSettings()
    local indicator = MinimapCluster and MinimapCluster.IndicatorFrame
    local mailFrame = indicator and indicator.MailFrame
    local hasMail = HasUnreadMailSafe()

    if mailFrame and not hasMail then
        hasMail = mailFrame:IsShown()
    end

    if not settings or not settings.showMail or not hasMail then
        if customMailButton then
            customMailButton:Hide()
        end
        return
    end

    CreateCustomMailButton()

    if mailFrame then
        mailFrame:SetAlpha(0)
        mailFrame:EnableMouse(false)
        if not mailFrame._quiVisibilityHooked then
            mailFrame._quiVisibilityHooked = true
            local function RefreshMailIndicator()
                if InCombatLockdown() then
                    pendingMinimapRefresh = true
                    return
                end
                UpdateCustomMailButton()
            end
            hooksecurefunc(mailFrame, "Show", RefreshMailIndicator)
            hooksecurefunc(mailFrame, "Hide", RefreshMailIndicator)
        end
    end

    customMailButton:SetParent(UIParent)
    customMailButton:SetFrameStrata("MEDIUM")
    customMailButton:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 10)
    customMailButton:ClearAllPoints()
    local mc = settings.mailConfig
    local mailAnchor = (mc and mc.anchor) or "BOTTOMLEFT"
    local mailOX = (mc and mc.offsetX) or 2
    local mailOY = (mc and mc.offsetY) or 2
    customMailButton:SetScale((mc and mc.scale) or 1)
    customMailButton:SetPoint(mailAnchor, Minimap, mailAnchor, mailOX, mailOY)
    customMailButton:Show()
end

local zoomInShowHooked = false
local zoomOutShowHooked = false

if Minimap.ZoomIn and not zoomInShowHooked then
    zoomInShowHooked = true
    hooksecurefunc(Minimap.ZoomIn, "Show", function(self)
        C_Timer.After(0, function()
            local s = GetSettings()
            if s and not s.showZoomButtons then
                self:Hide()
            end
        end)
    end)
end

if Minimap.ZoomOut and not zoomOutShowHooked then
    zoomOutShowHooked = true
    hooksecurefunc(Minimap.ZoomOut, "Show", function(self)
        C_Timer.After(0, function()
            local s = GetSettings()
            if s and not s.showZoomButtons then
                self:Hide()
            end
        end)
    end)
end

local expansionButtonHooked = false
local expansionButtonReparenting = false
if ExpansionLandingPageMinimapButton and not expansionButtonHooked then
    expansionButtonHooked = true
    hooksecurefunc(ExpansionLandingPageMinimapButton, "SetParent", function()
        if expansionButtonReparenting then return end
        C_Timer.After(0, function()
            local s = GetSettings()
            if not s then return end
            if MissionButtonInDrawer() then return end
            if s.showMissions and ExpansionLandingPageMinimapButton.title then
                expansionButtonReparenting = true
                ExpansionLandingPageMinimapButton:SetParent(Minimap)
                expansionButtonReparenting = false
            end
        end)
    end)
    hooksecurefunc(ExpansionLandingPageMinimapButton, "UpdateIconForGarrison", function()
        C_Timer.After(0, function()
            local s = GetSettings()
            if not s or not s.showMissions then return end
            if MissionButtonInDrawer() then return end
            if InCombatLockdown() then return end
            ExpansionLandingPageMinimapButton:ClearAllPoints()
            ExpansionLandingPageMinimapButton:SetPoint("LEFT", Minimap, "LEFT", -5, 0)
        end)
    end)
end

local function UpdateButtonVisibility()
    if InCombatLockdown() and not inInitSafeWindow then return end
    local settings = GetSettings()
    if not settings then return end

    local minimapSize = settings.size or 160
    local halfSize = minimapSize / 2

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

    if MinimapCluster and MinimapCluster.IndicatorFrame and MinimapCluster.IndicatorFrame.MailFrame then
        local mailFrame = MinimapCluster.IndicatorFrame.MailFrame
        if settings.showMail then
            mailFrame:SetAlpha(0)
            mailFrame:EnableMouse(false)
            UpdateCustomMailButton()
        else
            if customMailButton then
                customMailButton:Hide()
            end
        end
    end

    if MinimapCluster and MinimapCluster.IndicatorFrame and MinimapCluster.IndicatorFrame.CraftingOrderFrame then
        local craftingFrame = MinimapCluster.IndicatorFrame.CraftingOrderFrame

        if not craftingFrame._quiSetParentHooked then
            craftingFrame._quiSetParentHooked = true
            hooksecurefunc(craftingFrame, "SetParent", function(_, parent)
                if type(parent) == "table" and parent.Layout == nil then
                    ---@type fun(...)
                    parent.Layout = function() end
                end
            end)
        end

        if settings.showCraftingOrder then
            craftingFrame:SetParent(Minimap)
            craftingFrame:ClearAllPoints()
            craftingFrame:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", 28, 2)
            craftingFrame:SetScale(0.8)
        else
            craftingFrame:SetParent(hiddenButtonParent)
            craftingFrame:Hide()
        end
    end

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

    ForEachDifficultyFrame(function(diffFrame)
        if settings.showDifficulty then
            diffFrame:SetParent(Minimap)
            diffFrame:ClearAllPoints()
            diffFrame:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 2, -2)
        else
            diffFrame:SetParent(hiddenButtonParent)
        end
    end)

    if ExpansionLandingPageMinimapButton then
        if settings.showMissions and ExpansionLandingPageMinimapButton.title then
            if MissionButtonInDrawer() then
                ExpansionLandingPageMinimapButton:SetParent(Minimap)
                ExpansionLandingPageMinimapButton:Show()
            else
                ExpansionLandingPageMinimapButton:SetParent(Minimap)
                ExpansionLandingPageMinimapButton:ClearAllPoints()
                ExpansionLandingPageMinimapButton:SetPoint("LEFT", Minimap, "LEFT", -5, 0)
                ExpansionLandingPageMinimapButton:Show()
            end
        else
            ExpansionLandingPageMinimapButton:SetParent(hiddenButtonParent)
            ExpansionLandingPageMinimapButton:Hide()
        end
    end

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

    if MinimapCluster and MinimapCluster.Tracking then
        local trackingFrame = MinimapCluster.Tracking
        if settings.showTracking then
            local tc = settings.trackingConfig
            local anchor = (tc and tc.anchor) or "TOPLEFT"
            local ox = (tc and tc.offsetX) or 0
            local oy = (tc and tc.offsetY) or 0
            trackingFrame:SetParent(Minimap)
            trackingFrame:ClearAllPoints()
            if anchor == "TOPLEFT" then
                local baseX = settings.showDifficulty and 35 or 2
                trackingFrame:SetPoint("TOPLEFT", Minimap, "TOPLEFT", baseX + ox, -2 + oy)
            else
                trackingFrame:SetPoint(anchor, Minimap, anchor, ox, oy)
            end
        else
            trackingFrame:SetParent(hiddenButtonParent)
        end
    end

    UpdateGreatVaultButton()
    if MinimapCluster then
        MinimapCluster:Layout()
    end
end

local function BuildMiddleClickMenu()
    local settings = GetSettings() or {}

    return {
        { text = ns.L["QUI Menu"], isTitle = true, notCheckable = true },
        { text = ns.L["Achievements"], notCheckable = true, func = function()
            if not SafeExecute(ToggleAchievementFrame) then
                ClickMicroButton("AchievementMicroButton")
            end
        end },
        { text = ns.L["Calendar"], notCheckable = true, func = function() SafeExecute(ToggleCalendar) end },
        { text = ns.L["Character Info"], notCheckable = true, func = function()
            if not SafeExecute(function() ToggleCharacter("PaperDollFrame") end) then
                ClickMicroButton("CharacterMicroButton")
            end
        end },
        { text = ns.L["Chat Channels"], notCheckable = true, func = function()
            if not SafeExecute(ToggleChannelFrame) then
                ClickMicroButton("ChatFrameChannelButton")
            end
        end },
        { text = ns.L["Clock"], notCheckable = true, func = function()
            if not SafeExecute(TimeManager_Toggle) then
                SafeExecute(function()
                    if TimeManagerFrame then
                        if TimeManagerFrame:IsShown() then TimeManagerFrame:Hide() else TimeManagerFrame:Show() end
                    end
                end)
            end
        end },
        { text = ns.L["Dungeon Journal"], notCheckable = true, func = function()
            if not SafeExecute(ToggleEncounterJournal) then
                ClickMicroButton("EJMicroButton")
            end
        end },
        { text = ns.L["Guild"], notCheckable = true, func = function()
            if not SafeExecute(ToggleGuildFrame) then
                ClickMicroButton("GuildMicroButton")
            end
        end },
        { text = ns.L["Looking For Group"], notCheckable = true, func = function()
            if not SafeExecute(PVEFrame_ToggleFrame) then
                ClickMicroButton("LFDMicroButton")
            end
        end },
        { text = ns.L["Professions"], notCheckable = true, func = function()
            if not SafeExecute(ToggleProfessionsBook) then
                ClickMicroButton("ProfessionMicroButton")
            end
        end },
        { text = ns.L["Quest Log"], notCheckable = true, func = function() SafeExecute(ToggleQuestLog) end },
        { text = ns.L["Shop"], notCheckable = true, func = function()
            if not SafeExecute(StoreMicroButton_OnClick) then
                ClickMicroButton("StoreMicroButton")
            end
        end },
        { text = ns.L["Social"], notCheckable = true, func = function()
            if not SafeExecute(ToggleFriendsFrame) then
                ClickMicroButton("SocialsMicroButton")
            end
        end },
        { text = ns.L["Specialization"], notCheckable = true, func = function() TryOpenPlayerSpellsTab("specialization") end },
        { text = ns.L["Talents"], notCheckable = true, func = function() TryOpenPlayerSpellsTab("talents") end },
        { text = ns.L["Spellbook"], notCheckable = true, func = function()
            TryOpenPlayerSpellsTab("spellbook")
        end },
        { text = ns.L["Warband Collections"], notCheckable = true, func = function()
            if not SafeExecute(ToggleCollectionsJournal) then
                ClickMicroButton("CollectionsMicroButton")
            end
        end },
        { text = ns.L["Game Menu"], notCheckable = true, func = function()
            if InCombatLockdown() then return end

            local function OpenGameMenu()
                if GameMenuFrame and GameMenuFrame.IsShown and GameMenuFrame:IsShown() then
                    return true
                end

                if ShowUIPanel and GameMenuFrame then
                    ShowUIPanel(GameMenuFrame)
                    if GameMenuFrame:IsShown() then
                        return true
                    end
                end

                if ToggleGameMenu then
                    ToggleGameMenu()
                    if GameMenuFrame and GameMenuFrame:IsShown() then
                        return true
                    end
                end

                if GameMenuFrame and GameMenuFrame.Show then
                    GameMenuFrame:Show()
                    if ShowUIPanel then
                        ShowUIPanel(GameMenuFrame)
                    end
                end
                return GameMenuFrame and GameMenuFrame:IsShown()
            end

            SafeExecute(OpenGameMenu)
        end },
        { text = ns.L["Customer Support"], notCheckable = true, func = function()
            if not SafeExecute(ToggleHelpFrame) then
                ClickMicroButton("HelpMicroButton")
            end
        end },
    }
end

local function ShowMiddleClickMenu(keepPosition)
    if not middleClickMenuFrame then
        middleClickMenuFrame = CreateFrame("Frame", "QUI_MinimapMiddleClickMenu", UIParent, "BackdropTemplate")
        middleClickMenuFrame:SetFrameStrata("DIALOG")
        middleClickMenuFrame:SetFrameLevel(250)
        middleClickMenuFrame:SetClampedToScreen(true)
        middleClickMenuFrame:EnableMouse(true)
    end

    if not middleClickMenuBlocker then
        middleClickMenuBlocker = CreateFrame("Frame", nil, UIParent)
        middleClickMenuBlocker:SetAllPoints(UIParent)
        middleClickMenuBlocker:SetFrameStrata("DIALOG")
        middleClickMenuBlocker:SetFrameLevel(240)
        middleClickMenuBlocker:EnableMouse(true)
        middleClickMenuBlocker:SetScript("OnMouseDown", function()
            if middleClickMenuFrame then
                middleClickMenuFrame:Hide()
            end
            middleClickMenuBlocker:Hide()
        end)
        middleClickMenuBlocker:Hide()
    end

    local menuData = BuildMiddleClickMenu()
    local fontPath = Helpers.GetGeneralFont()
    local fontSize = 12
    local borderR, borderG, borderB, borderA = 0.2, 0.8, 0.6, 1
    local bgR, bgG, bgB, bgA = 0.03, 0.03, 0.03, 0.98
    if Helpers and Helpers.GetSkinBorderColor then
        borderR, borderG, borderB, borderA = Helpers.GetSkinBorderColor()
    elseif QUI and QUI.GetAddonAccentColor then
        borderR, borderG, borderB, borderA = QUI:GetAddonAccentColor()
    end
    borderA = borderA or 1

    if Helpers and Helpers.GetSkinBgColor then
        bgR, bgG, bgB, bgA = Helpers.GetSkinBgColor()
    else
        local core = Helpers.GetCore and Helpers.GetCore() or nil
        if core and core.db and core.db.profile and core.db.profile.general and core.db.profile.general.skinBgColor then
            local c = core.db.profile.general.skinBgColor
            bgR, bgG, bgB, bgA = c[1] or bgR, c[2] or bgG, c[3] or bgB, c[4] or bgA
        end
    end

    SkinBase.ApplyPixelBackdrop(middleClickMenuFrame, 1, true, true, { borderR, borderG, borderB, borderA }, { bgR, bgG, bgB, bgA }, nil, nil, 1)

    for i = 1, #middleClickMenuRows do
        middleClickMenuRows[i]:Hide()
    end

    local maxWidth = 180
    local y = -8
    local itemHeight = 18
    local sepHeight = 8
    local totalHeight = 12
    local rowIndex = 0

    for i = 1, #menuData do
        local item = menuData[i]
        rowIndex = rowIndex + 1
        local row = middleClickMenuRows[rowIndex]
        if not row then
            row = CreateFrame("Button", nil, middleClickMenuFrame)
            row:SetPoint("RIGHT", middleClickMenuFrame, "RIGHT", -8, 0)
            row:SetHeight(itemHeight)
            row:SetNormalFontObject("GameFontNormal")
            row:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
            row.text = row:CreateFontString(nil, "OVERLAY")
            row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
            row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            row.text:SetJustifyH("LEFT")
            row.text:SetFontObject(GameFontNormal)
            row.separator = row:CreateTexture(nil, "ARTWORK")
            row.separator:SetColorTexture(borderR, borderG, borderB, 0.7)
            row.separator:SetHeight(1)
            row.separator:SetPoint("LEFT", row, "LEFT", 2, 0)
            row.separator:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            row:SetScript("OnEnter", function(self)
                local hl = self:GetHighlightTexture()
                if hl then
                    hl:SetVertexColor(borderR, borderG, borderB, 0.2)
                end
            end)
            middleClickMenuRows[rowIndex] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", middleClickMenuFrame, "TOPLEFT", 8, y)
        row:SetPoint("RIGHT", middleClickMenuFrame, "RIGHT", -8, 0)

        row.item = item
        row.separator:Hide()
        row:EnableMouse(false)
        row:SetScript("OnClick", nil)

        if item.text == "" or item.disabled then
            row.text:SetFontObject(GameFontNormal)
            row.text:SetText("")
            row.separator:Show()
            row:SetHeight(sepHeight)
            totalHeight = totalHeight + sepHeight
            y = y - sepHeight
        else
            local label = item.text
            if item.checked ~= nil then
                label = (item.checked and "|cff55ff55[x]|r " or "|cff777777[ ]|r ") .. label
            end
            CJKFont(row.text, fontPath, fontSize, "OUTLINE")
            row.text:SetText(label)

            if item.isTitle then
                row.text:SetTextColor(borderR, borderG, borderB, 1)
                row:EnableMouse(false)
            else
                row.text:SetTextColor(0.9, 0.9, 0.9, 1)
                row:EnableMouse(true)
                row:SetScript("OnClick", function(self)
                    local data = self.item
                    if data and data.func then
                        data.func()
                    end
                    if not (data and data.keepShownOnClick) then
                        middleClickMenuFrame:Hide()
                        middleClickMenuBlocker:Hide()
                    else
                        ShowMiddleClickMenu(true)
                    end
                end)
            end

            local tw = row.text:GetStringWidth() or 0
            if tw + 30 > maxWidth then
                maxWidth = tw + 30
            end
            row:SetHeight(itemHeight)
            totalHeight = totalHeight + itemHeight
            y = y - itemHeight
        end

        row:Show()
    end

    middleClickMenuFrame:SetSize(maxWidth + 16, totalHeight + 8)

    if not keepPosition or not middleClickMenuFrame:IsShown() then
        local scale = UIParent:GetEffectiveScale() or 1
        local x, yCursor = GetCursorPosition()
        x = x / scale
        yCursor = yCursor / scale
        local w, h = middleClickMenuFrame:GetWidth(), middleClickMenuFrame:GetHeight()
        local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
        local left = x + 12
        local top = yCursor - 12
        if left + w > screenW then
            left = screenW - w - 8
        end
        if top - h < 0 then
            top = h + 8
        end
        if left < 8 then left = 8 end
        if top > screenH - 8 then top = screenH - 8 end

        middleClickMenuFrame:ClearAllPoints()
        middleClickMenuFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end
    middleClickMenuBlocker:Show()
    middleClickMenuFrame:Show()

    ---@diagnostic disable-next-line: empty-block
    if EasyMenu then
    end
end

local function UpdateMiddleClickMenuOverlayState()
    local settings = GetSettings()
    local enabled = settings and settings.middleClickMenuEnabled

    if not enabled then
        if middleClickMenuFrame then
            middleClickMenuFrame:Hide()
        end
        if middleClickMenuBlocker then
            middleClickMenuBlocker:Hide()
        end
    end
end

local function SetupMiddleClickMenu()
    if middleClickMenuHooked then return end
    middleClickMenuHooked = true

    Minimap:HookScript("OnMouseUp", function(_, button)
        local settings = GetSettings()
        if settings and settings.middleClickMenuEnabled and button == "MiddleButton" then
            ShowMiddleClickMenu()
        end
    end)

    UpdateMiddleClickMenuOverlayState()
end

local dungeonEyeOriginalParent = nil
local dungeonEyeOriginalPoint = nil
local dungeonEyeOriginalSize = nil
local dungeonEyeBaseSize = nil
local dungeonEyeHooksInstalled = false
local dungeonEyeApplyingOurState = false
local dungeonEyeReapplyPending = false
local DUNGEON_EYE_DEFAULT_SIZE = 32
local DUNGEON_EYE_MIN_BASE_SIZE = 16
local DUNGEON_EYE_MAX_BASE_SIZE = 64

local UpdateDungeonEyePosition

local function GetSaneDungeonEyeDimension(value)
    value = tonumber(value)
    if value and value >= DUNGEON_EYE_MIN_BASE_SIZE and value <= DUNGEON_EYE_MAX_BASE_SIZE then
        return value
    end
    return DUNGEON_EYE_DEFAULT_SIZE
end

local function CaptureDungeonEyeState(btn)
    if not btn then return end

    if not dungeonEyeOriginalParent then
        dungeonEyeOriginalParent = btn:GetParent()
        local point, relativeTo, relativePoint, x, y = btn:GetPoint()
        if point then
            dungeonEyeOriginalPoint = {point, relativeTo, relativePoint, x, y}
        end
    end

    if not dungeonEyeOriginalSize or not dungeonEyeBaseSize then
        local width = GetSaneDungeonEyeDimension(btn:GetWidth())
        local height = GetSaneDungeonEyeDimension(btn:GetHeight())
        if not dungeonEyeOriginalSize then
            dungeonEyeOriginalSize = {width, height}
        end
        if not dungeonEyeBaseSize then
            dungeonEyeBaseSize = {width, height}
        end
    end
end

local function ApplyDungeonEyeVisuals(btn, eyeSettings)
    if not btn then return end

    local width = (dungeonEyeBaseSize and dungeonEyeBaseSize[1]) or DUNGEON_EYE_DEFAULT_SIZE
    local height = (dungeonEyeBaseSize and dungeonEyeBaseSize[2]) or DUNGEON_EYE_DEFAULT_SIZE
    btn:SetSize(width, height)
    btn:SetScale(tonumber(eyeSettings and eyeSettings.scale) or 1.0)
    btn:SetFrameStrata("MEDIUM")
end

local function ScheduleDungeonEyeReapply()
    if dungeonEyeApplyingOurState then return end
    if dungeonEyeReapplyPending then return end
    dungeonEyeReapplyPending = true
    C_Timer.After(0, function()
        dungeonEyeReapplyPending = false
        UpdateDungeonEyePosition()
    end)
end

local function InstallDungeonEyeHooks(btn)
    if dungeonEyeHooksInstalled then return end
    if not btn then return end
    dungeonEyeHooksInstalled = true

    hooksecurefunc(btn, "SetParent",      ScheduleDungeonEyeReapply)
    hooksecurefunc(btn, "SetScale",       ScheduleDungeonEyeReapply)
    hooksecurefunc(btn, "SetPoint",       ScheduleDungeonEyeReapply)
    hooksecurefunc(btn, "ClearAllPoints", ScheduleDungeonEyeReapply)
    hooksecurefunc(btn, "SetSize",        ScheduleDungeonEyeReapply)
    hooksecurefunc(btn, "SetWidth",       ScheduleDungeonEyeReapply)
    hooksecurefunc(btn, "SetHeight",      ScheduleDungeonEyeReapply)
    if btn.UpdatePosition then
        hooksecurefunc(btn, "UpdatePosition", ScheduleDungeonEyeReapply)
    end
end

local function TryRestoreDungeonEyeViaBlizzard(btn)
    if not (btn and btn.UpdatePosition) then return false end
    if not (MicroMenu and MicroMenuContainer and MicroMenuContainer.GetPosition) then return false end

    local ok, position = ns.SafeCallMethod("report", MicroMenuContainer, "GetPosition")
    local isHorizontal = MicroMenu.isHorizontal
    if not ok or not position or type(isHorizontal) ~= "boolean" then return false end

    btn:UpdatePosition(position, isHorizontal)
    return true
end

local function RestoreDungeonEyeOriginalPoint(btn)
    if not dungeonEyeOriginalPoint then return end

    btn:ClearAllPoints()
    local point, relativeTo, relativePoint, x, y = unpack(dungeonEyeOriginalPoint)
    if point and relativePoint then
        btn:SetPoint(point, relativeTo, relativePoint, x or 0, y or 0)
    end
end

local function RestoreDungeonEye()
    local btn = QueueStatusButton
    if not btn then return end

    dungeonEyeApplyingOurState = true

    if dungeonEyeOriginalParent then
        btn:SetParent(dungeonEyeOriginalParent)
    end

    if not TryRestoreDungeonEyeViaBlizzard(btn) then
        RestoreDungeonEyeOriginalPoint(btn)
    end

    btn:SetScale(1.0)
    if dungeonEyeOriginalSize then
        btn:SetSize(dungeonEyeOriginalSize[1], dungeonEyeOriginalSize[2])
    end
    btn:SetFrameStrata("MEDIUM")

    dungeonEyeApplyingOurState = false
end

UpdateDungeonEyePosition = function()
    local settings = GetSettings()
    if not settings then return end

    local eyeSettings = settings.dungeonEye
    if not eyeSettings then return end

    local btn = QueueStatusButton
    if not btn then return end

    CaptureDungeonEyeState(btn)

    if eyeSettings.enabled then
        InstallDungeonEyeHooks(btn)

        if InCombatLockdown() then
            pendingMinimapRefresh = true
            if not (btn.IsProtected and btn:IsProtected()) then
                dungeonEyeApplyingOurState = true
                ApplyDungeonEyeVisuals(btn, eyeSettings)
                dungeonEyeApplyingOurState = false
            end
            return
        end

        dungeonEyeApplyingOurState = true

        btn:SetParent(Minimap)
        btn:ClearAllPoints()
        ApplyDungeonEyeVisuals(btn, eyeSettings)

        local corner = eyeSettings.corner or "BOTTOMRIGHT"
        local offsetX = eyeSettings.offsetX or 0
        local offsetY = eyeSettings.offsetY or 0

        local cornerOffsets = {
            TOPRIGHT    = { anchor = "TOPRIGHT",    x = -5 + offsetX, y = -5 + offsetY },
            TOPLEFT     = { anchor = "TOPLEFT",     x = 5 + offsetX,  y = -5 + offsetY },
            BOTTOMRIGHT = { anchor = "BOTTOMRIGHT", x = -5 + offsetX, y = 5 + offsetY },
            BOTTOMLEFT  = { anchor = "BOTTOMLEFT",  x = 5 + offsetX,  y = 5 + offsetY },
        }

        local pos = cornerOffsets[corner] or cornerOffsets.BOTTOMRIGHT
        btn:SetPoint(pos.anchor, Minimap, pos.anchor, pos.x, pos.y)

        dungeonEyeApplyingOurState = false
    else
        if InCombatLockdown() then
            pendingMinimapRefresh = true
            return
        end
        RestoreDungeonEye()
    end
end

local function SetupAddonButtonHiding()
    local settings = GetSettings()
    if not settings or not LibDBIcon then return end
    if settings.buttonDrawer and settings.buttonDrawer.enabled then return end

    if settings.hideAddonButtons then
        local buttons = LibDBIcon:GetButtonList()
        for i = 1, #buttons do
            LibDBIcon:ShowOnEnter(buttons[i], true)
        end

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

local DRAWER_BLACKLIST = {
    ["MiniMapMailFrame"] = true,
    ["MinimapZoomIn"] = true,
    ["MinimapZoomOut"] = true,
    ["MiniMapTracking"] = true,
    ["MinimapBackdrop"] = true,
    ["GameTimeFrame"] = true,
    ["TimeManagerClockButton"] = true,
    ["QueueStatusButton"] = true,
    ["QueueStatusMinimapButton"] = true,
    ["MiniMapLFGFrame"] = true,
    ["GarrisonLandingPageMinimapButton"] = true,
    ["ExpansionLandingPageMinimapButton"] = true,
    ["AddonCompartmentFrame"] = true,
    ["QUI_MinimapBackdrop"] = true,
    ["QUI_MinimapButtonDrawer"] = true,
    ["QUI_DrawerToggle"] = true,
}

---@type Frame
local drawerFrame
local drawerToggleButton
local collectedButtons = {}
local drawerVisible = false
local autoHideTimer = nil
local drawerCallbackRegistered = false
local toggleAutoHideHooked = false
local drawerAnimationFrame = nil
local drawerAnimationState = nil
local drawerExpandedWidth = 40
local drawerExpandedHeight = 40
local ScanAndCollectButtons

local function IsMinimapButton(frame)
    if not frame or not frame.IsObjectType then return false end
    if not (frame:IsObjectType("Frame") or frame:IsObjectType("Button")) then return false end
    local name = frame:GetName()
    if not name then return false end
    if name == "ExpansionLandingPageMinimapButton" then
        return MissionButtonInDrawer() and ExpansionLandingPageMinimapButton.title ~= nil
    end
    if DRAWER_BLACKLIST[name] then return false end
    if issecurevariable(_G, name) then return false end
    if name:match("^LibDBIcon10_") then return true end
    if name:match("%d$") then return false end
    if name:match("MinimapButton") or name:match("MinimapFrame") or name:match("MinimapIcon") then return true end
    if name:match("Minimap$") then return true end
    local parent = frame:GetParent()
    if parent and (parent == Minimap or parent == MinimapBackdrop or parent == MinimapCluster) then
        local ok, hasClick = ns.SafeCall("best-effort-style", function() return frame:HasScript("OnClick") and frame:GetScript("OnClick") end)
        local ok2, hasMouseUp = ns.SafeCall("best-effort-style", function() return frame:HasScript("OnMouseUp") and frame:GetScript("OnMouseUp") end)
        local ok3, hasMouseDown = ns.SafeCall("best-effort-style", function() return frame:HasScript("OnMouseDown") and frame:GetScript("OnMouseDown") end)
        if (ok and hasClick) or (ok2 and hasMouseUp) or (ok3 and hasMouseDown) then
            return true
        end
    end
    return false
end

local function ShouldSkipDrawerButton(name)
    if not name then return true end
    if name == "ExpansionLandingPageMinimapButton" then
        return not MissionButtonInDrawer()
    end
    if DRAWER_BLACKLIST[name] then return true end
    if name == "LibDBIcon10_QUI" then
        local profile = QUICore and QUICore.db and QUICore.db.profile
        local minimapButtonDB = profile and profile.minimapButton
        if minimapButtonDB and minimapButtonDB.hide then
            return true
        end
    end
    return false
end

local function SaveOriginalState(frame, name)
    local points = {}
    for i = 1, frame:GetNumPoints() do
        points[i] = { frame:GetPoint(i) }
    end
    local iconTex = frame.icon
    if not iconTex then
        ns.SafeCall("best-effort-style", function()
            for _, region in ipairs({ frame:GetRegions() }) do
                if region:IsObjectType("Texture") and region:GetTexture() and region:GetDrawLayer() == "ARTWORK" then
                    iconTex = region
                    break
                end
            end
        end)
    end
    local origOnDragStart, origOnDragStop
    ns.SafeCall("best-effort-style", function()
        if frame:HasScript("OnDragStart") then origOnDragStart = frame:GetScript("OnDragStart") end
        if frame:HasScript("OnDragStop") then origOnDragStop = frame:GetScript("OnDragStop") end
    end)
    collectedButtons[name] = {
        frame = frame,
        origParent = frame:GetParent(),
        origPoints = points,
        origOnDragStart = origOnDragStart,
        origOnDragStop = origOnDragStop,
        origMovable = frame:IsMovable(),
        wasShown = frame:IsShown(),
        iconTex = iconTex,
        origStrata = frame:GetFrameStrata(),
        origLevel = frame:GetFrameLevel(),
    }
end

local function CancelAutoHide()
    if autoHideTimer then
        autoHideTimer:Cancel()
        autoHideTimer = nil
    end
end

local function EnsureDrawerAnimator()
    if drawerAnimationFrame then return end
    drawerAnimationFrame = CreateFrame("Frame")
    drawerAnimationFrame:Hide()
    drawerAnimationFrame:SetScript("OnUpdate", function(self, elapsed)
        if not drawerAnimationState or not drawerFrame then
            self:Hide()
            return
        end

        local state = drawerAnimationState
        state.elapsed = state.elapsed + elapsed
        local t = state.elapsed / state.duration
        if t > 1 then t = 1 end

        local eased = t * t * (3 - 2 * t)
        local alpha = state.fromAlpha + (state.toAlpha - state.fromAlpha) * eased
        local width = state.fromWidth + (state.toWidth - state.fromWidth) * eased
        local height = state.fromHeight + (state.toHeight - state.fromHeight) * eased
        drawerFrame:SetAlpha(alpha)
        drawerFrame:SetSize(width, height)

        if t >= 1 then
            if state.show then
                drawerFrame:SetAlpha(1)
                drawerFrame:SetSize(state.fullWidth, state.fullHeight)
            else
                drawerFrame:SetAlpha(0)
                drawerFrame:Hide()
                drawerFrame:SetSize(state.fullWidth, state.fullHeight)
            end
            drawerAnimationState = nil
            self:Hide()
        end
    end)
end

local function StopDrawerAnimation(resetVisualState)
    drawerAnimationState = nil
    if drawerAnimationFrame then
        drawerAnimationFrame:Hide()
    end
    if resetVisualState and drawerFrame then
        drawerFrame:SetAlpha(1)
        drawerFrame:SetSize(drawerExpandedWidth, drawerExpandedHeight)
    end
end

local function StartDrawerAnimation(show)
    if not drawerFrame then return end
    local settings = GetSettings()
    local drawerSettings = settings and settings.buttonDrawer or nil
    local direction = drawerSettings and drawerSettings.growthDirection or "RIGHT"
    local centerGrowth = drawerSettings and drawerSettings.centerGrowth and true or false

    EnsureDrawerAnimator()

    local fullWidth = drawerExpandedWidth > 0 and drawerExpandedWidth or drawerFrame:GetWidth()
    local fullHeight = drawerExpandedHeight > 0 and drawerExpandedHeight or drawerFrame:GetHeight()
    local collapsedSize = 2
    local collapsedWidth, collapsedHeight
    if centerGrowth then
        collapsedWidth = collapsedSize
        collapsedHeight = collapsedSize
    elseif direction == "LEFT" or direction == "RIGHT" then
        collapsedWidth = collapsedSize
        collapsedHeight = fullHeight
    else
        collapsedWidth = fullWidth
        collapsedHeight = collapsedSize
    end

    if show and not drawerFrame:IsShown() then
        drawerFrame:SetSize(collapsedWidth, collapsedHeight)
        drawerFrame:SetAlpha(0)
        drawerFrame:Show()
    elseif not show and not drawerFrame:IsShown() then
        return
    end

    local fromAlpha = drawerFrame:GetAlpha() or (show and 0 or 1)
    local toAlpha = show and 1 or 0
    local fromWidth = drawerFrame:GetWidth()
    local fromHeight = drawerFrame:GetHeight()
    local toWidth = show and fullWidth or collapsedWidth
    local toHeight = show and fullHeight or collapsedHeight

    drawerAnimationState = {
        show = show,
        elapsed = 0,
        duration = show and 0.22 or 0.16,
        fromAlpha = fromAlpha,
        toAlpha = toAlpha,
        fromWidth = fromWidth,
        toWidth = toWidth,
        fromHeight = fromHeight,
        toHeight = toHeight,
        fullWidth = fullWidth,
        fullHeight = fullHeight,
    }
    drawerAnimationFrame:Show()
end

local function HideDrawer()
    if drawerFrame and (drawerVisible or drawerFrame:IsShown()) then
        drawerVisible = false
        StartDrawerAnimation(false)
    end
    local settings = GetSettings()
    if settings and settings.buttonDrawer and settings.buttonDrawer.autoHideToggle and drawerToggleButton then
        if not drawerToggleButton:IsMouseOver() then
            drawerToggleButton:SetAlpha(0)
        end
    end
end

local function ShowDrawer()
    if drawerFrame and (not drawerVisible or not drawerFrame:IsShown()) then
        if ScanAndCollectButtons and not InCombatLockdown() then
            ScanAndCollectButtons()
        end
        drawerVisible = true
        StartDrawerAnimation(true)
    end
    if drawerToggleButton then
        drawerToggleButton:SetAlpha(1)
    end
end

local function ShowToggleButton()
    if drawerToggleButton then
        drawerToggleButton:SetAlpha(1)
    end
end

local function HideToggleButton()
    if drawerVisible then return end
    local settings = GetSettings()
    if settings and settings.buttonDrawer and settings.buttonDrawer.autoHideToggle and drawerToggleButton then
        drawerToggleButton:SetAlpha(0)
    end
end

local function ToggleDrawer()
    if drawerVisible then
        CancelAutoHide()
        HideDrawer()
    else
        ShowDrawer()
    end
end

local function StartAutoHide()
    local settings = GetSettings()
    if not settings or not settings.buttonDrawer then return end
    local delay = settings.buttonDrawer.autoHideDelay or 1.5
    if delay <= 0 then return end
    CancelAutoHide()
    autoHideTimer = C_Timer.NewTimer(delay, function()
        autoHideTimer = nil
        HideDrawer()
    end)
end

local function IsMouseOverDrawer()
    if drawerFrame and drawerFrame:IsMouseOver() then return true end
    if drawerToggleButton and drawerToggleButton:IsMouseOver() then return true end
    for _, data in pairs(collectedButtons) do
        if data.frame and data.frame:IsMouseOver() then return true end
    end
    return false
end

local function OnDrawerLeave()
    C_Timer.After(0.05, function()
        if not IsMouseOverDrawer() then
            StartAutoHide()
        end
    end)
end

local function MakeButtonSquare(data, bSize)
    if not data or not data.frame then return end
    if data.squareDone then return end
    local frame = data.frame
    data.hiddenRegions = {}

    local iconTex = frame.icon or frame.Icon or data.iconTex

    local ok = ns.SafeCall("best-effort-style", function()
        local regions = { frame:GetRegions() }
        for _, region in ipairs(regions) do
            if region:IsObjectType("Texture") then
                local layer = region:GetDrawLayer()
                local isIcon = (region == iconTex)

                if isIcon then
                    region:ClearAllPoints()
                    region:SetAllPoints(frame)
                    region:SetTexCoord(0, 1, 0, 1)
                    region:Show()
                    ns.SafeCallMethodIfPresent("best-effort-style", region, "SetMask", "")
                elseif layer == "HIGHLIGHT" then
                else
                    region:Hide()
                    data.hiddenRegions[#data.hiddenRegions + 1] = region
                end
            end
        end
    end)
    data.squareDone = true
end

local function LayoutDrawerButtons()
    if not drawerFrame then return end
    local settings = GetSettings()
    if not settings or not settings.buttonDrawer then return end

    local bSize = settings.buttonDrawer.buttonSize or 28
    local bSpacing = settings.buttonDrawer.buttonSpacing or 2
    local cols = math.max(1, settings.buttonDrawer.columns or 1)
    local direction = settings.buttonDrawer.growthDirection or "RIGHT"
    local centerGrowth = settings.buttonDrawer.centerGrowth and true or false
    if direction ~= "RIGHT" and direction ~= "LEFT" and direction ~= "UP" and direction ~= "DOWN" then
        direction = "RIGHT"
    end
    local padding = math.max(0, settings.buttonDrawer.padding or 6)

    local hiddenButtons = settings.buttonDrawer.hiddenButtons or {}

    local sorted = {}
    for name, data in pairs(collectedButtons) do
        if hiddenButtons[name] or ShouldSkipDrawerButton(name) then
            local mt = getmetatable(data.frame)
            if mt and mt.__index then
                mt.__index.Hide(data.frame)
            end
        else
            sorted[#sorted + 1] = { name = name, frame = data.frame }
        end
    end
    table.sort(sorted, function(a, b) return a.name < b.name end)

    local count = #sorted
    if count == 0 then
        drawerExpandedWidth = bSize + padding * 2
        drawerExpandedHeight = bSize + padding * 2
        drawerFrame:SetSize(drawerExpandedWidth, drawerExpandedHeight)
        return
    end

    local step = bSize + bSpacing
    local primaryHorizontal = (direction == "RIGHT" or direction == "LEFT")

    local laneCount = cols
    local laneSizes = {}
    for lane = 1, laneCount do
        laneSizes[lane] = 0
    end
    for i = 1, count do
        local lane = ((i - 1) % laneCount) + 1
        laneSizes[lane] = laneSizes[lane] + 1
    end

    local minX, maxX, minY, maxY

    for i, entry in ipairs(sorted) do
        local laneIndex = ((i - 1) % laneCount) + 1
        local primaryIndex = math.floor((i - 1) / laneCount)
        local laneSize = laneSizes[laneIndex] or 1

        local primaryOffset
        if centerGrowth then
            local centerIndex = (laneSize - 1) / 2
            primaryOffset = (primaryIndex - centerIndex) * step
            if direction == "LEFT" or direction == "DOWN" then
                primaryOffset = -primaryOffset
            end
        elseif direction == "RIGHT" then
            primaryOffset = primaryIndex * step
        elseif direction == "LEFT" then
            primaryOffset = -primaryIndex * step
        elseif direction == "DOWN" then
            primaryOffset = -primaryIndex * step
        else
            primaryOffset = primaryIndex * step
        end

        local secondaryOffset = (laneIndex - 1) * step
        local centerX, centerY
        if primaryHorizontal then
            centerX = primaryOffset
            centerY = -secondaryOffset
        else
            centerX = secondaryOffset
            centerY = primaryOffset
        end

        entry.centerX = centerX
        entry.centerY = centerY

        local half = bSize * 0.5
        local left = centerX - half
        local right = centerX + half
        local bottom = centerY - half
        local top = centerY + half
        minX = minX and math.min(minX, left) or left
        maxX = maxX and math.max(maxX, right) or right
        minY = minY and math.min(minY, bottom) or bottom
        maxY = maxY and math.max(maxY, top) or top
    end

    local width = padding * 2 + (maxX - minX)
    local height = padding * 2 + (maxY - minY)
    drawerExpandedWidth = width
    drawerExpandedHeight = height
    drawerFrame:SetSize(width, height)

    for _, entry in ipairs(sorted) do
        local f = entry.frame
        local centerX = padding + (entry.centerX - minX)
        local centerY = padding + (entry.centerY - minY)
        local mt = getmetatable(f)
        local raw = mt and mt.__index
        if raw then
            raw.ClearAllPoints(f)
            raw.SetPoint(f, "CENTER", drawerFrame, "BOTTOMLEFT", centerX, centerY)
        else
            f:ClearAllPoints()
            f:SetPoint("CENTER", drawerFrame, "BOTTOMLEFT", centerX, centerY)
        end
        f:SetSize(bSize, bSize)

        if raw then
            raw.SetAlpha(f, 1)
            raw.Show(f)
        end

        local data = collectedButtons[entry.name]
        if data then
            MakeButtonSquare(data, bSize)
        end
    end
end

local function StyleDrawerFrame()
    if not drawerFrame then return end
    local settings = GetSettings()
    local drawerSettings = settings and settings.buttonDrawer or nil

    local borderR, borderG, borderB, borderA = 0.2, 0.8, 0.6, 1
    local bgR, bgG, bgB, bgA = 0.03, 0.03, 0.03, 0.98

    if Helpers and Helpers.GetSkinBorderColor then
        borderR, borderG, borderB, borderA = Helpers.GetSkinBorderColor(drawerSettings, "")
    end
    borderA = borderA or 1

    if Helpers and Helpers.GetSkinBgColor then
        bgR, bgG, bgB, bgA = Helpers.GetSkinBgColor()
    end

    if drawerSettings and type(drawerSettings.bgColor) == "table" then
        local c = drawerSettings.bgColor
        bgR = c[1] or bgR
        bgG = c[2] or bgG
        bgB = c[3] or bgB
        bgA = c[4] or bgA
    end
    if drawerSettings and drawerSettings.bgOpacity ~= nil then
        local pct = math.max(0, math.min(100, drawerSettings.bgOpacity))
        bgA = pct / 100
    end

    local borderSize = 1
    if drawerSettings and drawerSettings.borderSize ~= nil then
        borderSize = drawerSettings.borderSize
    end
    borderSize = math.max(0, borderSize)
    local hasBorder = borderSize > 0

    SkinBase.ApplyPixelBackdrop(drawerFrame, hasBorder and borderSize or 0, true, hasBorder, { borderR, borderG, borderB, hasBorder and borderA or 0 }, { bgR, bgG, bgB, bgA }, nil, nil, borderSize)
end

local function CreateDrawerFrame()
    if drawerFrame then return end
    drawerFrame = CreateFrame("Frame", "QUI_MinimapButtonDrawer", UIParent, "BackdropTemplate")
    drawerFrame:SetFrameStrata("MEDIUM")
    drawerFrame:SetClampedToScreen(true)
    drawerFrame:SetSize(40, 40)
    if drawerFrame.SetClipsChildren then
        drawerFrame:SetClipsChildren(true)
    end
    drawerFrame:SetAlpha(0)
    drawerFrame:Hide()
    drawerFrame:EnableMouse(true)
    StyleDrawerFrame()
    drawerFrame:SetScript("OnEnter", function() CancelAutoHide() end)
    drawerFrame:SetScript("OnLeave", OnDrawerLeave)
end

local DEFAULT_TOGGLE_SIZE = 20

local UpdateToggleIcon
do
    local TOGGLE_ICON_TEXTURES = {
        qui = ADDON_ASSET_ROOT .. "QUI.tga",
        hammer = ADDON_ASSET_ROOT .. "quazii_hammer",
    }

    function UpdateToggleIcon()
        if not drawerToggleButton then return end
        local s = GetSettings()
        local icon = (s and s.buttonDrawer and s.buttonDrawer.toggleIcon) or "qui"
        local texturePath = TOGGLE_ICON_TEXTURES[icon]
        if drawerToggleButton._iconTexture then
            if texturePath then
                drawerToggleButton._iconTexture:SetTexture(texturePath)
            end
            drawerToggleButton._iconTexture:SetShown(texturePath ~= nil)
        end
        if drawerToggleButton._gridDots then
            for _, dot in ipairs(drawerToggleButton._gridDots) do
                dot:SetShown(texturePath == nil)
            end
        end
    end
end

local function CreateDrawerToggleButton()
    if drawerToggleButton then return end
    drawerToggleButton = CreateFrame("Button", "QUI_DrawerToggle", UIParent)
    drawerToggleButton:SetSize(DEFAULT_TOGGLE_SIZE, DEFAULT_TOGGLE_SIZE)
    drawerToggleButton:SetFrameStrata("HIGH")
    drawerToggleButton:SetFrameLevel(Minimap:GetFrameLevel() + 5)

    local bg = drawerToggleButton:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    do
        local bgR, bgG, bgB
        if SkinBase and SkinBase.GetDepthColor then
            bgR, bgG, bgB = SkinBase.GetDepthColor("PANEL")
        end
        if not bgR and Helpers.GetSkinBgColor then
            bgR, bgG, bgB = Helpers.GetSkinBgColor()
        end
        bg:SetColorTexture(bgR or 0.05, bgG or 0.05, bgB or 0.05, 0.9)
    end

    local iconTexture = drawerToggleButton:CreateTexture(nil, "ARTWORK")
    iconTexture:SetPoint("TOPLEFT", 2, -2)
    iconTexture:SetPoint("BOTTOMRIGHT", -2, 2)
    drawerToggleButton._iconTexture = iconTexture

    drawerToggleButton._gridDots = {}
    local r, g, b = 0.2, 0.8, 0.6
    if Helpers and Helpers.GetSkinBorderColor then
        r, g, b = Helpers.GetSkinBorderColor()
    end
    for row = 0, 1 do
        for col = 0, 1 do
            local dot = drawerToggleButton:CreateTexture(nil, "ARTWORK")
            dot:SetColorTexture(r, g, b, 1)
            drawerToggleButton._gridDots[#drawerToggleButton._gridDots + 1] = dot
        end
    end

    UpdateToggleIcon()

    local border = drawerToggleButton:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints()
    border:SetColorTexture(1, 1, 1, 0.15)
    local inner = drawerToggleButton:CreateTexture(nil, "OVERLAY", nil, 1)
    inner:SetPoint("TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", -1, 1)
    inner:SetColorTexture(0, 0, 0, 0)
    border:SetDrawLayer("OVERLAY", 0)
    inner:SetDrawLayer("OVERLAY", 1)

    drawerToggleButton:SetScript("OnClick", ToggleDrawer)
    drawerToggleButton:SetScript("OnEnter", function(self)
        CancelAutoHide()
        ShowToggleButton()
        local s = GetSettings()
        if s and s.buttonDrawer and s.buttonDrawer.openOnMouseover ~= false then
            ShowDrawer()
        end
        if s and s.buttonDrawer and s.buttonDrawer.showTooltip == false then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(ns.L["Addon Button Drawer"])
        GameTooltip:AddLine(ns.L["|cffFFFFFFMouseover:|r Open drawer"], 0.2, 1, 0.2)
        local total, hidden = 0, 0
        local hiddenButtons = (s and s.buttonDrawer and s.buttonDrawer.hiddenButtons) or {}
        for name in pairs(collectedButtons) do
            total = total + 1
            if hiddenButtons[name] then hidden = hidden + 1 end
        end
        local visible = total - hidden
        local line = visible .. " button" .. (visible ~= 1 and "s" or "")
        if hidden > 0 then
            line = line .. " (" .. hidden .. " hidden)"
        end
        GameTooltip:AddLine(line, 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    drawerToggleButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
        OnDrawerLeave()
        if not drawerVisible then
            HideToggleButton()
        end
    end)
end

local function ResizeDrawerToggle()
    if not drawerToggleButton then return end
    local s = GetSettings()
    local size = (s and s.buttonDrawer and s.buttonDrawer.toggleSize) or DEFAULT_TOGGLE_SIZE
    drawerToggleButton:SetSize(size, size)

    local scale = size / DEFAULT_TOGGLE_SIZE
    local gridSize = math.max(1, math.floor(5 * scale + 0.5))
    local gridGap = math.max(1, math.floor(2 * scale + 0.5))
    local gridOfs = math.max(1, math.floor(4 * scale + 0.5))
    local dots = drawerToggleButton._gridDots
    if dots then
        local idx = 1
        for row = 0, 1 do
            for col = 0, 1 do
                local dot = dots[idx]
                if dot then
                    dot:ClearAllPoints()
                    dot:SetSize(gridSize, gridSize)
                    dot:SetPoint("TOPLEFT", drawerToggleButton, "TOPLEFT", gridOfs + col * (gridSize + gridGap), -(gridOfs + row * (gridSize + gridGap)))
                end
                idx = idx + 1
            end
        end
    end

    if drawerToggleButton._iconTexture then
        local inset = math.max(1, math.floor(2 * scale + 0.5))
        drawerToggleButton._iconTexture:ClearAllPoints()
        drawerToggleButton._iconTexture:SetPoint("TOPLEFT", inset, -inset)
        drawerToggleButton._iconTexture:SetPoint("BOTTOMRIGHT", -inset, inset)
    end

    UpdateToggleIcon()
end

local function UpdateDrawerAnchor()
    if not drawerFrame or not drawerToggleButton then return end
    local settings = GetSettings()
    if not settings or not settings.buttonDrawer then return end
    local anchor = settings.buttonDrawer.anchor or "RIGHT"
    local direction = settings.buttonDrawer.growthDirection or "RIGHT"
    local centerGrowth = settings.buttonDrawer.centerGrowth and true or false
    local ofsX = settings.buttonDrawer.offsetX or 0
    local ofsY = settings.buttonDrawer.offsetY or 0
    local tOfsX = settings.buttonDrawer.toggleOffsetX or 0
    local tOfsY = settings.buttonDrawer.toggleOffsetY or 0
    local gap = 4

    drawerToggleButton:SetFrameStrata("HIGH")
    drawerToggleButton:SetFrameLevel(Minimap:GetFrameLevel() + 5)

    drawerToggleButton:ClearAllPoints()

    if anchor == "RIGHT" then
        drawerToggleButton:SetPoint("RIGHT", Minimap, "RIGHT", -2 + tOfsX, tOfsY)
    elseif anchor == "LEFT" then
        drawerToggleButton:SetPoint("LEFT", Minimap, "LEFT", 2 + tOfsX, tOfsY)
    elseif anchor == "BOTTOM" then
        drawerToggleButton:SetPoint("BOTTOM", Minimap, "BOTTOM", tOfsX, 2 + tOfsY)
    elseif anchor == "TOP" then
        drawerToggleButton:SetPoint("TOP", Minimap, "TOP", tOfsX, -2 + tOfsY)
    elseif anchor == "TOPLEFT" then
        drawerToggleButton:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 2 + tOfsX, -2 + tOfsY)
    elseif anchor == "TOPRIGHT" then
        drawerToggleButton:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", -2 + tOfsX, -2 + tOfsY)
    elseif anchor == "BOTTOMLEFT" then
        drawerToggleButton:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", 2 + tOfsX, 2 + tOfsY)
    elseif anchor == "BOTTOMRIGHT" then
        drawerToggleButton:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", -2 + tOfsX, 2 + tOfsY)
    end

    drawerFrame:ClearAllPoints()
    if centerGrowth then
        drawerFrame:SetPoint("CENTER", drawerToggleButton, "CENTER", ofsX, ofsY)
    elseif direction == "LEFT" then
        drawerFrame:SetPoint("RIGHT", drawerToggleButton, "LEFT", -gap + ofsX, ofsY)
    elseif direction == "RIGHT" then
        drawerFrame:SetPoint("LEFT", drawerToggleButton, "RIGHT", gap + ofsX, ofsY)
    elseif direction == "UP" then
        drawerFrame:SetPoint("BOTTOM", drawerToggleButton, "TOP", ofsX, gap + ofsY)
    else
        drawerFrame:SetPoint("TOP", drawerToggleButton, "BOTTOM", ofsX, -gap + ofsY)
    end
end

---@param frame Frame
---@param name string
local function CollectButton(frame, name)
    if collectedButtons[name] then return end
    SaveOriginalState(frame, name)
    local data = collectedButtons[name]

    if LibDBIcon and name:match("^LibDBIcon10_") then
        local buttonName = name:gsub("^LibDBIcon10_", "")
        LibDBIcon:ShowOnEnter(buttonName, false)
        ns.SafeCall("best-effort-style", function()
            if frame.fadeOut then frame.fadeOut:Stop() end
            for _, child in ipairs({ frame:GetChildren() }) do
                if child.Stop and child:IsObjectType("AnimationGroup") then
                    child:Stop()
                end
            end
        end)
    end

    frame:SetParent(drawerFrame)
    frame:SetScale(1)
    if frame.SetIgnoreParentScale then
        frame:SetIgnoreParentScale(false)
    end

    frame:SetFrameStrata(drawerFrame:GetFrameStrata())
    frame:SetFrameLevel(drawerFrame:GetFrameLevel() + 5)

    local mt = getmetatable(frame)
    local mtSetAlpha = mt and mt.__index and mt.__index.SetAlpha
    ---@type fun(...)
    frame.Hide = function() end
    frame.SetShown = function(self, shown)
        if shown and mt and mt.__index then
            mt.__index.Show(self)
        end
    end
    frame.SetAlpha = function(self, alpha)
        if mtSetAlpha then
            mtSetAlpha(self, 1)
        end
    end
    frame.SetParent = function() end
    frame.ClearAllPoints = function() end
    frame.SetPoint = function() end
    frame.SetFrameStrata = function() end
    frame.SetFrameLevel = function() end
    if mtSetAlpha then mtSetAlpha(frame, 1) end
    if mt and mt.__index then mt.__index.Show(frame) end

    if frame:HasScript("OnDragStart") then
        frame:SetScript("OnDragStart", nil)
    end
    if frame:HasScript("OnDragStop") then
        frame:SetScript("OnDragStop", nil)
    end
    frame:SetMovable(false)
    if frame:HasScript("OnEnter") then
        frame:HookScript("OnEnter", function() CancelAutoHide() end)
    end
    if frame:HasScript("OnLeave") then
        frame:HookScript("OnLeave", OnDrawerLeave)
    end
end

ScanAndCollectButtons = function()
    if not drawerFrame then return end

    for _, child in ipairs({ Minimap:GetChildren() }) do
        if IsMinimapButton(child) then
            local name = child:GetName()
            if name and not ShouldSkipDrawerButton(name) then
                CollectButton(child, name)
            end
        end
    end
    if MinimapBackdrop then
        for _, child in ipairs({ MinimapBackdrop:GetChildren() }) do
            if IsMinimapButton(child) then
                local name = child:GetName()
                if name and not ShouldSkipDrawerButton(name) then
                    CollectButton(child, name)
                end
            end
        end
    end
    if MinimapCluster then
        for _, child in ipairs({ MinimapCluster:GetChildren() }) do
            if IsMinimapButton(child) then
                local name = child:GetName()
                if name and not ShouldSkipDrawerButton(name) then
                    CollectButton(child, name)
                end
            end
        end
    end
    for _, child in ipairs({ UIParent:GetChildren() }) do
        local ok, name = ns.SafeCallMethod("best-effort-style", child, "GetName")
        if ok and name and not collectedButtons[name] and IsMinimapButton(child) then
            if not ShouldSkipDrawerButton(name) then
                CollectButton(child, name)
            end
        end
    end

    LayoutDrawerButtons()
end

local function ReleaseAllButtons()
    for name, data in pairs(collectedButtons) do
        local frame = data.frame
        if frame then
            frame.Hide = nil
            frame.SetShown = nil
            frame.SetAlpha = nil
            frame.SetParent = nil
            frame.ClearAllPoints = nil
            frame.SetPoint = nil
            frame.SetFrameStrata = nil
            frame.SetFrameLevel = nil
            if data.origStrata then
                ns.SafeCallMethod("best-effort-style", frame, "SetFrameStrata", data.origStrata)
            end
            if data.origLevel then
                ns.SafeCallMethod("best-effort-style", frame, "SetFrameLevel", data.origLevel)
            end
            if data.hiddenRegions then
                for _, region in ipairs(data.hiddenRegions) do
                    region:Show()
                end
            end
            frame:SetParent(data.origParent)
            frame:ClearAllPoints()
            for _, pt in ipairs(data.origPoints) do
                frame:SetPoint(unpack(pt))
            end
            if data.origMovable ~= nil then
                frame:SetMovable(data.origMovable)
            end
            ns.SafeCall("best-effort-style", function()
                if data.origOnDragStart and frame:HasScript("OnDragStart") then
                    frame:SetScript("OnDragStart", data.origOnDragStart)
                end
                if data.origOnDragStop and frame:HasScript("OnDragStop") then
                    frame:SetScript("OnDragStop", data.origOnDragStop)
                end
            end)
        end
    end
    collectedButtons = {}
    if drawerCallbackRegistered and LibDBIcon then
        LibDBIcon.UnregisterCallback("QUI_ButtonDrawer", "LibDBIcon_IconCreated")
        drawerCallbackRegistered = false
    end
end

local function SetupButtonDrawer()
    local settings = GetSettings()
    if not settings or not settings.buttonDrawer or not settings.buttonDrawer.enabled then
        ReleaseAllButtons()
        StopDrawerAnimation(true)
        if drawerFrame then drawerFrame:Hide() end
        if drawerToggleButton then drawerToggleButton:Hide() end
        drawerVisible = false
        return
    end

    if InCombatLockdown() and not inInitSafeWindow then
        pendingDrawerSetup = true
        return
    end

    CreateDrawerFrame()
    CreateDrawerToggleButton()
    ResizeDrawerToggle()
    StyleDrawerFrame()
    ScanAndCollectButtons()
    LayoutDrawerButtons()
    UpdateDrawerAnchor()
    drawerToggleButton:Show()

    if settings.buttonDrawer.autoHideToggle then
        drawerToggleButton:SetAlpha(0)
        if not toggleAutoHideHooked then
            Minimap:HookScript("OnEnter", ShowToggleButton)
            Minimap:HookScript("OnLeave", function()
                C_Timer.After(0.1, function()
                    if not IsMouseOverDrawer() and not (Minimap:IsMouseOver()) then
                        HideToggleButton()
                    end
                end)
            end)
            toggleAutoHideHooked = true
        end
    else
        drawerToggleButton:SetAlpha(1)
    end

    if LibDBIcon and not drawerCallbackRegistered then
        LibDBIcon.RegisterCallback("QUI_ButtonDrawer", "LibDBIcon_IconCreated", function(_, button, buttonName)
            local frameName = "LibDBIcon10_" .. buttonName
            if not ShouldSkipDrawerButton(frameName) then
                C_Timer.After(0.1, function()
                    local settings2 = GetSettings()
                    if not settings2 or not settings2.buttonDrawer or not settings2.buttonDrawer.enabled then return end
                    local frame = _G[frameName]
                    if frame and IsMinimapButton(frame) then
                        local name = frame:GetName()
                        if name and not ShouldSkipDrawerButton(name) then
                            CollectButton(frame, name)
                        end
                        LayoutDrawerButtons()
                    end
                end)
            end
        end)
        drawerCallbackRegistered = true
    end

    C_Timer.After(0, function()
        local s = GetSettings()
        if s and s.buttonDrawer and s.buttonDrawer.enabled then
            ScanAndCollectButtons()
        end
    end)
    C_Timer.After(1, function()
        local s = GetSettings()
        if s and s.buttonDrawer and s.buttonDrawer.enabled then
            ScanAndCollectButtons()
        end
    end)
end

local function RefreshButtonDrawer()
    local settings = GetSettings()
    if not settings or not settings.buttonDrawer or not settings.buttonDrawer.enabled then
        SetupButtonDrawer()
        return
    end
    if drawerFrame then
        ResizeDrawerToggle()
        StyleDrawerFrame()
        LayoutDrawerButtons()
        UpdateDrawerAnchor()

        if drawerToggleButton then
            drawerToggleButton:Show()
        end

        if drawerToggleButton then
            if settings.buttonDrawer.autoHideToggle then
                if not toggleAutoHideHooked then
                    Minimap:HookScript("OnEnter", ShowToggleButton)
                    Minimap:HookScript("OnLeave", function()
                        C_Timer.After(0.1, function()
                            if not IsMouseOverDrawer() and not (Minimap:IsMouseOver()) then
                                HideToggleButton()
                            end
                        end)
                    end)
                    toggleAutoHideHooked = true
                end
                if not Minimap:IsMouseOver() and not IsMouseOverDrawer() then
                    drawerToggleButton:SetAlpha(0)
                end
            else
                drawerToggleButton:SetAlpha(1)
            end
        end
    else
        SetupButtonDrawer()
    end
end

local function UpdateMinimapSize()
    if InCombatLockdown() and not inInitSafeWindow then
        return
    end
    local settings = GetSettings()
    if not settings then return end
    CountMinimapDebug("size")

    BeginQUIControlledMinimapUpdate()
    Minimap:SetSize(settings.size, settings.size)
    Minimap:SetScale(settings.scale or 1.0)
    if minimapAnchor then
        minimapAnchor:SetSize(settings.size, settings.size)
        minimapAnchor:SetScale(settings.scale or 1.0)
    end
    EndQUIControlledMinimapUpdate()

    if MINIMAP_RENDER_ZOOM_NUDGE_ENABLED then
        CountMinimapDebug("zoomNudge")
        local z = Minimap:GetZoom()
        if z < 5 then
            Minimap:SetZoom(z + 1)
            Minimap:SetZoom(z)
        else
            Minimap:SetZoom(z - 1)
            Minimap:SetZoom(z)
        end
    end

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
    if not settings then
        return
    end

    if not minimapAnchor then
        minimapAnchor = CreateFrame("Frame", "QUI_MinimapAnchor", UIParent)
        minimapAnchor:SetFrameStrata("LOW")
        minimapAnchor:SetFrameLevel(1)

        local function MirrorOwnsMinimap()
            if externalHudActive then return false end
            local parent = Minimap:GetParent()
            return not parent or parent == UIParent
        end
        hooksecurefunc(minimapAnchor, "ClearAllPoints", function()
            if not MirrorOwnsMinimap() then return end
            Minimap:ClearAllPoints()
        end)
        hooksecurefunc(minimapAnchor, "SetPoint", function(self, pt, relTo, relPt, ox, oy)
            if not MirrorOwnsMinimap() then return end
            Minimap:SetPoint(pt, relTo, relPt, ox, oy)
        end)
    end

    Minimap:SetParent(UIParent)
    Minimap:SetFrameStrata("LOW")
    Minimap:SetFrameLevel(2)
    Minimap:SetFixedFrameStrata(true)
    Minimap:SetFixedFrameLevel(true)

    if MinimapCluster then
        local hiddenCluster = CreateFrame("Frame")
        hiddenCluster:Hide()
        MinimapCluster:SetParent(hiddenCluster)
        MinimapCluster:EnableMouse(false)
    end

    Minimap:EnableMouse(true)
    Minimap:SetMovable(false)
    Minimap:SetClampedToScreen(true)
    Minimap:RegisterForDrag("LeftButton")

    Minimap:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        if self:IsMovable() then
            self:StartMoving()
        end
    end)

    Minimap:SetScript("OnDragStop", function(self)
        if InCombatLockdown() then return end
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = QUICore:SnapFramePosition(self)
        if point then
            local s = GetSettings()
            if s then
                s.position = {point, relPoint, x, y}
            end
        end
        if minimapAnchor and point then
            minimapAnchor:ClearAllPoints()
            minimapAnchor:SetPoint(point, UIParent, relPoint, x, y)
        end
    end)

    local function ApplyMinimapPosition(pt, parent, rel, ox, oy)
        if minimapAnchor then
            minimapAnchor:ClearAllPoints()
            minimapAnchor:SetPoint(pt, parent, rel, ox, oy)
        else
            Minimap:ClearAllPoints()
            Minimap:SetPoint(pt, parent, rel, ox, oy)
        end
    end

    if _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("minimap") then
        local quiDB = _G.QUI and _G.QUI.db and _G.QUI.db.profile
        local anchorSettings = quiDB and quiDB.frameAnchoring and quiDB.frameAnchoring["minimap"]
        if anchorSettings and anchorSettings.enabled ~= false then
            local pt = anchorSettings.point or "CENTER"
            local rel = anchorSettings.relative or "CENTER"
            local ox = anchorSettings.offsetX or 0
            local oy = anchorSettings.offsetY or 0
            local parent = UIParent
            if anchorSettings.parent and anchorSettings.parent ~= "screen" then
                local resolved = _G[anchorSettings.parent]
                if resolved then parent = resolved end
            end
            ApplyMinimapPosition(pt, parent, rel, ox, oy)
        end
        return
    end

    local pos = settings.position
    if pos then
        local point = pos[1] or pos.point or "TOPLEFT"
        local relPoint = pos[2] or pos.relPoint or "BOTTOMLEFT"
        local x = pos[3] or pos.x or 790
        local y = pos[4] or pos.y or 285
        ApplyMinimapPosition(point, UIParent, relPoint, x, y)
    else
        ApplyMinimapPosition("TOPLEFT", UIParent, "BOTTOMLEFT", 790, 285)
    end
end

local function HideAllDecorations()
    CountMinimapDebug("hideDecor")
    if backdropFrame then backdropFrame:Hide() end
    if clockFrame then clockFrame:Hide() end
    if coordsFrame then coordsFrame:Hide() end
    if zoneTextFrame then zoneTextFrame:Hide() end
    if greatVaultButton then greatVaultButton:Hide() end
    if customMailButton then customMailButton:Hide() end
    if datatextFrame then datatextFrame:Hide() end
    if drawerToggleButton then drawerToggleButton:Hide() end
    if drawerFrame then drawerFrame:Hide() end
    if middleClickMenuFrame then middleClickMenuFrame:Hide() end
    if middleClickMenuBlocker then middleClickMenuBlocker:Hide() end
    if clockTicker then clockTicker:Cancel(); clockTicker = nil end
    if coordsTicker then coordsTicker:Cancel(); coordsTicker = nil end
end

local function CheckExternalHud()
    if IsExternalHudCheckSuppressed() then return end
    CountMinimapDebug("hud")

    local um = ns.QUI_LayoutMode
    if um and um.isActive then return end

    local settings = GetSettings()
    if not settings then return end

    local expectedScale = settings.scale or 1.0
    local expectedSize = settings.size or 140

    local currentScale = Helpers.SafeToNumber(Minimap:GetScale(), expectedScale)
    local currentAlpha = Helpers.SafeToNumber(Minimap:GetEffectiveAlpha(), 1)
    local currentWidth = Helpers.SafeToNumber(Minimap:GetWidth(), expectedSize)

    local hudDetected = (currentScale > expectedScale * 2.0)
        or (currentAlpha < 0.5)
        or (currentWidth > expectedSize * 2.0)
        or (Minimap:GetParent() ~= UIParent)

    if not hudDetected then
        local left, bottom, width, height = Minimap:GetRect()
        if left and width then
            local safeWidth = Helpers.SafeToNumber(width, 0)
            local uiScale = Helpers.SafeToNumber(UIParent:GetEffectiveScale(), 1)
            local mapScale = Helpers.SafeToNumber(Minimap:GetEffectiveScale(), 1)
            local renderedSize = safeWidth * mapScale
            local expectedPixels = expectedSize * expectedScale * uiScale
            if renderedSize > expectedPixels * 2.0 then
                hudDetected = true
            end
        end
    end

    if hudDetected then
        hudDetectedCount = hudDetectedCount + 1
        if hudDetectedCount >= HUD_DEBOUNCE_THRESHOLD and not externalHudActive then
            externalHudActive = true
            LogExternalHudTransition(true, "detected", currentScale, currentAlpha, currentWidth, Minimap:GetParent() and (Minimap:GetParent():GetName() or tostring(Minimap:GetParent())) or "nil")
            HideAllDecorations()
        end
    else
        hudDetectedCount = 0
        if externalHudActive then
            externalHudActive = false
            LogExternalHudTransition(false, "cleared", currentScale, currentAlpha, currentWidth, Minimap:GetParent() and (Minimap:GetParent():GetName() or tostring(Minimap:GetParent())) or "nil")
            Minimap_Module:Refresh()
        end
    end
end

local function DeferCheckExternalHud()
    if externalHudCheckPending or IsExternalHudCheckSuppressed() then return end
    CountMinimapDebug("hudDefer")
    externalHudCheckPending = true
    C_Timer.After(0, function()
        externalHudCheckPending = false
        CheckExternalHud()
    end)
end

local zoomPersistenceHooked = false

local function PersistMinimapZoom(zoom)
    local normalizedZoom = math.max(0, math.floor((zoom or 0) + 0.5))
    local indoorZoom = math.min(normalizedZoom, 3)

    if C_CVar and C_CVar.SetCVar then
        C_CVar.SetCVar("minimapZoom", tostring(normalizedZoom))
        C_CVar.SetCVar("minimapInsideZoom", tostring(indoorZoom))
    elseif SetCVar then
        SetCVar("minimapZoom", normalizedZoom)
        SetCVar("minimapInsideZoom", indoorZoom)
    end
end

local function SetupZoomPersistence()
    if zoomPersistenceHooked then return end
    zoomPersistenceHooked = true

    local function PersistCurrentZoom()
        C_Timer.After(0, function()
            if Minimap and Minimap.GetZoom then
                local z = Minimap:GetZoom()
                PersistMinimapZoom(z)
                lastAppliedZoomLevel = z
                if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.minimap then
                    QUICore.db.profile.minimap.zoomLevel = z
                    InvalidateSettingsCache()
                end
            end
        end)
    end

    if Minimap.ZoomIn then
        Minimap.ZoomIn:HookScript("OnClick", PersistCurrentZoom)
    end
    if Minimap.ZoomOut then
        Minimap.ZoomOut:HookScript("OnClick", PersistCurrentZoom)
    end
end

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

local function GetMaxZoomLevel()
    if Minimap.GetZoomLevels then
        local levels = Minimap:GetZoomLevels()
        if levels and levels > 0 then
            return levels - 1
        end
    end
    return 5
end

local function ApplyZoomLevel(zoomLevel)
    zoomLevel = tonumber(zoomLevel) or 0
    if zoomLevel < 0 then zoomLevel = 0 end
    local maxZoom = GetMaxZoomLevel()
    if zoomLevel > maxZoom then zoomLevel = maxZoom end
    if lastAppliedZoomLevel == zoomLevel then return end
    lastAppliedZoomLevel = zoomLevel
    if Minimap.SetZoom then Minimap:SetZoom(zoomLevel) end
    PersistMinimapZoom(zoomLevel)
    if Minimap.ZoomIn and Minimap.ZoomIn.Enable then Minimap.ZoomIn:Enable() end
    if Minimap.ZoomOut and Minimap.ZoomOut.Enable then Minimap.ZoomOut:Enable() end
end

local autoZoomTimer = 0
local autoZoomCurrent = 0

local function SetupAutoZoom()
    local settings = GetSettings()
    if not settings then return end

    local function ZoomOut()
        autoZoomCurrent = autoZoomCurrent + 1
        if autoZoomTimer == autoZoomCurrent then
            autoZoomTimer, autoZoomCurrent = 0, 0
            local s = GetSettings()
            if not s or not s.autoZoom then return end
            PersistMinimapZoom(0)
            Minimap:SetZoom(0)
            if Minimap.ZoomIn then Minimap.ZoomIn:Enable() end
            if Minimap.ZoomOut then Minimap.ZoomOut:Disable() end
        end
    end

    local function OnZoom()
        local s = GetSettings()
        if s and s.autoZoom then
            autoZoomTimer = autoZoomTimer + 1
            C_Timer.After(10, ZoomOut)
        end
    end

    if not Minimap_Module._autoZoomHooked then
        Minimap_Module._autoZoomHooked = true
        if Minimap.ZoomIn then
            Minimap.ZoomIn:HookScript("OnClick", function()
                C_Timer.After(0, OnZoom)
            end)
        end
        if Minimap.ZoomOut then
            Minimap.ZoomOut:HookScript("OnClick", function()
                C_Timer.After(0, OnZoom)
            end)
        end
    end

    if settings.autoZoom then
        OnZoom()
    end
end

local function StartUpdateTickers()
    local settings = GetSettings()
    if not settings then return end

    if clockTicker then clockTicker:Cancel(); clockTicker = nil end
    if coordsTicker then coordsTicker:Cancel(); coordsTicker = nil end

    if settings.showClock then
        UpdateClockTime()
        local function scheduleClockTick()
            local delay = 60.1 - (tonumber(date("%S")) or 0)
            clockTicker = C_Timer.NewTimer(delay, function()
                UpdateClockTime()
                scheduleClockTick()
            end)
        end
        scheduleClockTick()
    end

    if settings.showCoords then
        local coordInterval = settings.coordUpdateInterval or 1
        coordsTicker = C_Timer.NewTicker(coordInterval, function()
            local s = GetSettings()
            if s then
                UpdateCoordsPosition()
            end
        end)
    end

end

function Minimap_Module:Initialize()
    local icl = InCombatLockdown()

    local settings = GetSettings()
    if not settings then return end

    inInitSafeWindow = true
    BeginQUIControlledMinimapUpdate(1.0)

    SetMinimapShape(settings.shape)

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

    CreateDatatextPanel()
    UpdateDatatextPanel()

    UpdateButtonVisibility()
    SetupAddonButtonHiding()
    SetupButtonDrawer()
    UpdateDungeonEyePosition()
    SetupZoomPersistence()
    SetupMouseWheelZoom()
    SetupMiddleClickMenu()
    SetupAutoZoom()

    if not externalHudHooksInstalled then
        externalHudHooksInstalled = true
        hooksecurefunc(Minimap, "SetScale", function() DeferCheckExternalHud() end)
        hooksecurefunc(Minimap, "SetAlpha", function() DeferCheckExternalHud() end)
        hooksecurefunc(Minimap, "SetSize", function() DeferCheckExternalHud() end)
        hooksecurefunc(Minimap, "SetParent", function()
            if IsExternalHudCheckSuppressed() then return end
            local um = ns.QUI_LayoutMode
            if um and um.isActive then return end
            local parent = Minimap:GetParent()
            if parent and parent ~= UIParent and not externalHudActive then
                externalHudActive = true
                LogExternalHudTransition(true, "reparented",
                    Helpers.SafeToNumber(Minimap:GetScale(), 1),
                    Helpers.SafeToNumber(Minimap:GetEffectiveAlpha(), 1),
                    Helpers.SafeToNumber(Minimap:GetWidth(), 0),
                    parent:GetName() or tostring(parent))
                HideAllDecorations()
            elseif parent == UIParent and externalHudActive then
                DeferCheckExternalHud()
            end
        end)
        hooksecurefunc(Minimap, "SetWidth", function() DeferCheckExternalHud() end)
        hooksecurefunc(Minimap, "SetHeight", function() DeferCheckExternalHud() end)
        hooksecurefunc(Minimap, "SetPoint", function() DeferCheckExternalHud() end)
    end

    if not externalHudTicker then
        externalHudTicker = C_Timer.NewTicker(5, CheckExternalHud)
    end

    StartUpdateTickers()

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

    if Minimap.SetBackdrop then
        Minimap:SetBackdrop(nil)
    end

    local edgeNames = {"LeftEdge", "RightEdge", "TopEdge", "BottomEdge", "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner", "Center"}
    for _, edgeName in ipairs(edgeNames) do
        if Minimap[edgeName] then
            Minimap[edgeName]:Hide()
            Minimap[edgeName]:SetAlpha(0)
        end
    end

    if Minimap.backdropInfo then
        for _, edgeName in ipairs(edgeNames) do
            if Minimap.backdropInfo[edgeName] then
                Minimap.backdropInfo[edgeName] = nil
            end
        end
    end

    if MinimapCluster and MinimapCluster.SetBackdrop then
        MinimapCluster:SetBackdrop(nil)
    end

    if Minimap.BorderTop then
        Minimap.BorderTop:Hide()
    end
    if Minimap.Background then
        Minimap.Background:Hide()
    end

    for _, child in pairs({Minimap:GetChildren()}) do
        local name = child:GetName()
        if name and (name:find("Edge") or name:find("Corner") or name:find("Border")) then
            child:Hide()
        end
        if child.SetBackdrop then
            child:SetBackdrop(nil)
        end
    end

    inInitSafeWindow = false
    EndQUIControlledMinimapUpdate(1.0)
end

function Minimap_Module:Refresh()
    if InCombatLockdown() then
        pendingMinimapRefresh = true
        return
    end
    CountMinimapDebug("refresh")

    InvalidateSettingsCache()

    local settings = GetSettings()

    if not settings then
        return
    end

    if externalHudActive then
        HideAllDecorations()
        return
    end

    BeginQUIControlledMinimapUpdate(0.75)

    StartUpdateTickers()

    Minimap:SetFrameStrata("LOW")
    Minimap:SetFrameLevel(2)
    Minimap:SetFixedFrameStrata(true)
    Minimap:SetFixedFrameLevel(true)

    SetMinimapShape(settings.shape)
    UpdateBackdrop()
    UpdateMinimapSize()
    ApplyZoomLevel(settings.zoomLevel)
    UpdateClock()
    UpdateClockTime()
    UpdateCoords()
    UpdateCoordsPosition()
    UpdateZoneText()
    UpdateDatatextPanel()
    UpdateButtonVisibility()
    SetupAddonButtonHiding()
    RefreshButtonDrawer()
    UpdateDungeonEyePosition()
    UpdateMiddleClickMenuOverlayState()
    SetupAutoZoom()

    if not (_G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("minimap")) then
        if settings.position and settings.position[1] and settings.position[2] then
            local pt = settings.position[1]
            local relPt = settings.position[2]
            local ox = settings.position[3] or 0
            local oy = settings.position[4] or 0
            if minimapAnchor then
                minimapAnchor:ClearAllPoints()
                minimapAnchor:SetPoint(pt, UIParent, relPt, ox, oy)
            else
                Minimap:ClearAllPoints()
                Minimap:SetPoint(pt, UIParent, relPt, ox, oy)
            end
        end
    end

    if MinimapCluster then
        MinimapCluster:Layout()
    end
    EndQUIControlledMinimapUpdate(0.75)
    FlushMinimapDebugStats(false)
end

function Minimap_Module:InitializeOnce()
    if self._initialized then return end
    local _p = QUICore and QUICore.db and QUICore.db.profile
    if _p and _p.minimap and _p.minimap.enabled == false then return end
    self._initialized = true
    self:Initialize()
    local settings = GetSettings()
    if settings then
        if C_AddOns.IsAddOnLoaded("Blizzard_QueueStatusFrame") then
            UpdateDungeonEyePosition()
        end
        if C_AddOns.IsAddOnLoaded("Blizzard_HybridMinimap") then
            SetMinimapShape(settings.shape)
        end
    end
end

local function RefreshMinimapButtonsAfterTransition()
    local settings = GetSettings()
    if not settings then return end

    if InCombatLockdown() then
        pendingMinimapRefresh = true
        return
    end

    C_Timer.After(0, function()
        local s = GetSettings()
        if s and not InCombatLockdown() then
            UpdateButtonVisibility()
            UpdateDungeonEyePosition()
        end
    end)

    C_Timer.After(1, function()
        local s = GetSettings()
        if s and not InCombatLockdown() then
            UpdateButtonVisibility()
            UpdateDungeonEyePosition()
        end
    end)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
eventFrame:RegisterEvent("UPDATE_INSTANCE_INFO")
eventFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
eventFrame:RegisterEvent("VARIABLES_LOADED")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "Blizzard_QueueStatusFrame" then
            local settings = GetSettings()
            if settings then
                UpdateDungeonEyePosition()
            end
        elseif arg1 == "Blizzard_HybridMinimap" then
            local settings = GetSettings()
            if settings then
                SetMinimapShape(settings.shape)
            end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingDrawerSetup then
            pendingDrawerSetup = false
            SetupButtonDrawer()
        end
        if pendingDatatextPanelUpdate then
            pendingDatatextPanelUpdate = false
            if not pendingMinimapRefresh then
                UpdateDatatextPanel()
            end
        end
        if pendingMinimapRefresh then
            pendingMinimapRefresh = false
            Minimap_Module:Refresh()
        end
    elseif event == "PLAYER_ENTERING_WORLD"
        or event == "ZONE_CHANGED_NEW_AREA"
        or event == "PLAYER_DIFFICULTY_CHANGED"
        or event == "UPDATE_INSTANCE_INFO" then
        RefreshMinimapButtonsAfterTransition()
        if not Minimap_Module._settleReapplyDone then
            Minimap_Module._settleReapplyDone = true
            C_Timer.After(0, function()
                if Minimap_Module.Refresh then Minimap_Module:Refresh() end
            end)
        end
    elseif event == "VARIABLES_LOADED" then
        local settings = GetSettings()
        if settings and settings.buttonDrawer and settings.buttonDrawer.enabled then
            C_Timer.After(0.5, function()
                local s = GetSettings()
                if s and s.buttonDrawer and s.buttonDrawer.enabled
                    and ScanAndCollectButtons and not InCombatLockdown() then
                    ScanAndCollectButtons()
                end
            end)
        end
    elseif event == "EDIT_MODE_LAYOUTS_UPDATED" then
        Minimap_Module._settleReapplyDone = true
        C_Timer.After(0, function()
            if Minimap_Module.Refresh then Minimap_Module:Refresh() end
        end)
    end
end)

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(function()
        C_Timer.After(0, function() Minimap_Module:InitializeOnce() end)
    end)
end

local calendarFrame = CreateFrame("Frame")
calendarFrame:RegisterEvent("CALENDAR_UPDATE_PENDING_INVITES")
calendarFrame:RegisterEvent("CALENDAR_ACTION_PENDING")
calendarFrame:SetScript("OnEvent", function()
    local settings = GetSettings()
    if not settings then return end
    if InCombatLockdown() then return end

    if settings.showCalendar and GameTimeFrame then
        if C_Calendar.GetNumPendingInvites() < 1 then
            GameTimeFrame:Hide()
        else
            GameTimeFrame:Show()
        end
    end
end)

local petBattleFrame = CreateFrame("Frame")
petBattleFrame:RegisterEvent("PET_BATTLE_OPENING_START")
petBattleFrame:RegisterEvent("PET_BATTLE_CLOSE")
petBattleFrame:SetScript("OnEvent", function(self, event)
    if event == "PET_BATTLE_OPENING_START" then
        Minimap:Hide()
        if greatVaultButton then greatVaultButton:Hide() end
        if customMailButton then customMailButton:Hide() end
    else
        Minimap:Show()
        local settings = GetSettings()
        if settings then
            C_Timer.After(0, function()
                Minimap_Module:Refresh()
            end)
        end
    end
end)

_G.QUI_RefreshMinimap = function()
    Minimap_Module:Refresh()
end

_G.QUI_RefreshMinimapButtonDrawer = function()
    RefreshButtonDrawer()
end

_G.QUI_GetDrawerButtonNames = function()
    local settings = GetSettings()
    if settings and settings.buttonDrawer and settings.buttonDrawer.enabled
        and ScanAndCollectButtons and not InCombatLockdown() then
        ScanAndCollectButtons()
    end
    local names = {}
    for name in pairs(collectedButtons) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

if Helpers and Helpers.BorderRegistry then
    Helpers.BorderRegistry.Register({
        key = "minimap", label = "Minimap", category = "HUD", prefix = "",
        db = function(p) return p.minimap end,
        refresh = function() if _G.QUI_RefreshMinimap then _G.QUI_RefreshMinimap() end end,
        legacy = { useClass = "useClassColorBorder", accent = "useAccentColorBorder" },
    })
    Helpers.BorderRegistry.Register({
        key = "buttonDrawer", label = "Minimap Button Drawer", category = "HUD", prefix = "",
        db = function(p) return p.minimap and p.minimap.buttonDrawer end,
        refresh = function() if _G.QUI_RefreshMinimap then _G.QUI_RefreshMinimap() end end,
        legacy = {},
    })
end

if ns.Registry then
    ns.Registry:Register("minimap", {
        refresh = _G.QUI_RefreshMinimap,
        priority = 55,
        group = "ui",
        importCategories = { "minimapDatatexts" },
    })
    ns.Registry:Register("minimapSkin", {
        refresh = _G.QUI_RefreshMinimap,
        priority = 55,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

if ns.QUI_Modules and ns.QUI_Modules.Subscribe then
    ns.QUI_Modules:Subscribe("QUI_Datatexts", function()
        if QUICore and QUICore.Datatexts then
            UpdateDatatextPanel()
        end
    end)
end

do
    local function RegisterLayoutModeElements()
        local um = ns.QUI_LayoutMode
        if not um then return end

        um:RegisterElement({
            key = "minimap",
            label = ns.L["Minimap"],
            group = ns.L["Display"],
            order = 1,
            setGameplayHidden = function(hide)
                if not Minimap then return end
                if hide then
                    Minimap:SetAlpha(0)
                    Minimap:EnableMouse(false)
                else
                    Minimap:SetAlpha(1)
                    Minimap:EnableMouse(true)
                end
            end,
            getFrame = function()
                return Minimap
            end,
        })

        um:RegisterElement({
            key = "datatextPanel",
            label = ns.L["Datatext Panel"],
            group = ns.L["Display"],
            order = 2,
            isOwned = true,
            getFrame = function()
                if not datatextFrame then
                    CreateDatatextPanel()
                    UpdateDatatextPanel()
                end
                return datatextFrame
            end,
            isEnabled = function()
                local dt = GetDatatextSettings()
                return dt and dt.enabled
            end,
            setEnabled = function(val)
                local dt = GetDatatextSettings()
                if dt then
                    dt.enabled = val
                    UpdateDatatextPanel()
                end
            end,
            setGameplayHidden = function(hide)
                if not datatextFrame then return end
                if hide then
                    datatextFrame:Hide()
                else
                    local dt = GetDatatextSettings()
                    if dt and dt.enabled and QUICore and QUICore.Datatexts then
                        datatextFrame:Show()
                    end
                end
            end,
        })
    end

    C_Timer.After(2, function()
        RegisterLayoutModeElements()

        local um = ns.QUI_LayoutMode
        if um and um.RegisterExitCallback then
            um:RegisterExitCallback(function()
                Minimap_Module:Refresh()
            end)
        end
    end)
end
