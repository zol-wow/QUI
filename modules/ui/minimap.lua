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
local middleClickMenuFrame
local middleClickMenuBlocker
local middleClickMenuRows = {}

-- Datatext panel (3-slot architecture using QUICore.Datatexts registry)
local datatextFrame

-- Performance: Cached settings and tickers (avoid per-frame GetSettings calls)
local cachedSettings = nil
local clockTicker = nil
local coordsTicker = nil

-- Combat-deferred refresh flag
local pendingMinimapRefresh = false
local pendingDrawerSetup = false
local middleClickMenuHooked = false
local microMenuShowHooked = false
local bagsBarShowHooked = false
local originalMicroMenuParent = nil
local originalBagsBarParent = nil
local minimapOriginalOnMouseUp = nil

-- External HUD overlay detection
local externalHudActive = false
local quiUpdatingMinimap = false

---=================================================================================
--- BLIZZARD LAYOUT NO-OPS
--- Blizzard's Minimap.lua calls self:Layout() internally (line ~479).
--- Minimap does not have a Layout method by default — it expects the layout
--- system or a mixin to provide one. Writing a no-op here prevents the nil
--- call error. Minimap is NOT in the Edit Mode secure execution chain, so
--- this does not cause taint for EnterEditMode/CompactUnitFrame paths.
---
--- MinimapCluster.IndicatorFrame subframes (MailFrame, CraftingOrderFrame)
--- are NOT given no-op Layout — they are reparented to hiddenButtonParent
--- which provides its own Layout. See BUTTON VISIBILITY section below.
---=================================================================================
-- TAINT NOTE: Direct method override on Blizzard frame to suppress unwanted Layout calls.
-- Minimap is reparented to UIParent by QUI and is not in the Edit Mode secure chain.
if not InCombatLockdown() then
    if Minimap and not Minimap.Layout then
        Minimap.Layout = function() end
    end
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

local function TryOpenSpellbookTab()
    local function FindAndClickSpellbookTabButton(parent, maxDepth, depth)
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
                    if label and label ~= "" then
                        if (SPELLBOOK and label == SPELLBOOK)
                            or (SPELLBOOK_ABILITIES_BUTTON and label == SPELLBOOK_ABILITIES_BUTTON)
                            or (SPELLBOOK and label:find(SPELLBOOK, 1, true)) then
                            child:Click()
                            return true
                        end
                    end
                end

                if FindAndClickSpellbookTabButton(child, maxDepth, depth + 1) then
                    return true
                end
            end
        end
        return false
    end

    local function ActivatePlayerSpellsSpellbookTab()
        local frame = _G.PlayerSpellsFrame
        if not frame or (frame.IsShown and not frame:IsShown()) then
            return false
        end

        if frame.SpellBookFrame then
            if frame.SpellBookFrame.TabButton and frame.SpellBookFrame.TabButton.Click then
                frame.SpellBookFrame.TabButton:Click()
                return true
            end
            if frame.SpellBookFrame.Show then
                frame.SpellBookFrame:Show()
            end
        end

        local tabButtonCandidates = {
            "PlayerSpellsFrameSpellBookFrameTabButton",
            "PlayerSpellsFrameSpellBookTabButton",
            "PlayerSpellsSpellBookTabButton",
        }
        if ClickMicroButton(unpack(tabButtonCandidates)) then
            return true
        end

        if FindAndClickSpellbookTabButton(frame, 4, 0) then
            return true
        end

        return false
    end

    local opened = false
    if ClickMicroButton("SpellbookMicroButton") then
        opened = true
    elseif SafeExecute(function() ToggleSpellBook(BOOKTYPE_SPELL) end) then
        opened = true
    else
        opened = SafeExecute(TogglePlayerSpellsFrame) and true or false
    end

    local activated = ActivatePlayerSpellsSpellbookTab()
    if not activated then
        -- Frame tabs can initialize a tick later; retry briefly.
        C_Timer.After(0, ActivatePlayerSpellsSpellbookTab)
        C_Timer.After(0.05, ActivatePlayerSpellsSpellbookTab)
        C_Timer.After(0.15, ActivatePlayerSpellsSpellbookTab)
    end

    return opened or activated
end

local function TryOpenTalentsTab()
    local function FindAndClickTalentsTabButton(parent, maxDepth, depth)
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
                    if label and label ~= "" then
                        if (TALENTS and label == TALENTS)
                            or (TALENTS and label:find(TALENTS, 1, true)) then
                            child:Click()
                            return true
                        end
                    end
                end

                if FindAndClickTalentsTabButton(child, maxDepth, depth + 1) then
                    return true
                end
            end
        end
        return false
    end

    local function ActivatePlayerSpellsTalentsTab()
        local frame = _G.PlayerSpellsFrame
        if not frame or (frame.IsShown and not frame:IsShown()) then
            return false
        end

        if frame.TalentsFrame then
            if frame.TalentsFrame.TabButton and frame.TalentsFrame.TabButton.Click then
                frame.TalentsFrame.TabButton:Click()
                return true
            end
            if frame.TalentsFrame.Show then
                frame.TalentsFrame:Show()
            end
        end

        local tabButtonCandidates = {
            "PlayerSpellsFrameTalentsFrameTabButton",
            "PlayerSpellsFrameTalentsTabButton",
            "PlayerSpellsTalentsTabButton",
        }
        if ClickMicroButton(unpack(tabButtonCandidates)) then
            return true
        end

        if FindAndClickTalentsTabButton(frame, 4, 0) then
            return true
        end

        return false
    end

    local opened = false
    if ClickMicroButton("TalentMicroButton", "PlayerSpellsMicroButton") then
        opened = true
    elseif SafeExecute(ToggleTalentFrame) then
        opened = true
    else
        opened = SafeExecute(TogglePlayerSpellsFrame) and true or false
    end

    local activated = ActivatePlayerSpellsTalentsTab()
    if not activated then
        C_Timer.After(0, ActivatePlayerSpellsTalentsTab)
        C_Timer.After(0.05, ActivatePlayerSpellsTalentsTab)
        C_Timer.After(0.15, ActivatePlayerSpellsTalentsTab)
    end

    return opened or activated
end

local function TryOpenSpecializationTab()
    local function FindAndClickSpecTabButton(parent, maxDepth, depth)
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
                    if label and label ~= "" then
                        if (SPECIALIZATION and label == SPECIALIZATION)
                            or (SPECIALIZATION and label:find(SPECIALIZATION, 1, true))
                            or (SPECIALIZATIONS and label:find(SPECIALIZATIONS, 1, true)) then
                            child:Click()
                            return true
                        end
                    end
                end

                if FindAndClickSpecTabButton(child, maxDepth, depth + 1) then
                    return true
                end
            end
        end
        return false
    end

    local function ActivatePlayerSpellsSpecializationTab()
        local frame = _G.PlayerSpellsFrame
        if not frame or (frame.IsShown and not frame:IsShown()) then
            return false
        end

        if frame.SpecFrame then
            if frame.SpecFrame.TabButton and frame.SpecFrame.TabButton.Click then
                frame.SpecFrame.TabButton:Click()
                return true
            end
            if frame.SpecFrame.Show then
                frame.SpecFrame:Show()
            end
        end

        local tabButtonCandidates = {
            "PlayerSpellsFrameSpecFrameTabButton",
            "PlayerSpellsFrameSpecTabButton",
            "PlayerSpellsFrameSpecializationTabButton",
            "PlayerSpellsSpecializationTabButton",
        }
        if ClickMicroButton(unpack(tabButtonCandidates)) then
            return true
        end

        if FindAndClickSpecTabButton(frame, 4, 0) then
            return true
        end

        return false
    end

    local opened = false
    if ClickMicroButton("PlayerSpellsMicroButton", "TalentMicroButton") then
        opened = true
    else
        opened = SafeExecute(TogglePlayerSpellsFrame) and true or false
    end

    local activated = ActivatePlayerSpellsSpecializationTab()
    if not activated then
        C_Timer.After(0, ActivatePlayerSpellsSpecializationTab)
        C_Timer.After(0.05, ActivatePlayerSpellsSpecializationTab)
        C_Timer.After(0.15, ActivatePlayerSpellsSpecializationTab)
    end

    return opened or activated
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
    elseif settings.useAccentColorBorder then
        local QUI = _G.QUI
        if QUI and QUI.GetAddonAccentColor then
            r, g, b, a = QUI:GetAddonAccentColor()
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

local UpdateZoneTextDisplay  -- forward declaration (defined after CreateZoneText/UpdateZoneText)

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

UpdateZoneTextDisplay = function()
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

local hiddenActionBarParent = CreateFrame("Frame")
hiddenActionBarParent:Hide()
hiddenActionBarParent.Layout = function() end

-- Hook Show() on zoom buttons to prevent Blizzard from re-showing them
-- Use local guard variables instead of writing properties to Blizzard frames
local zoomInShowHooked = false
local zoomOutShowHooked = false

if Minimap.ZoomIn and not zoomInShowHooked then
    zoomInShowHooked = true
    -- TAINT SAFETY: Defer to break taint chain from secure context.
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
    -- TAINT SAFETY: Defer to break taint chain from secure context.
    hooksecurefunc(Minimap.ZoomOut, "Show", function(self)
        C_Timer.After(0, function()
            local s = GetSettings()
            if s and not s.showZoomButtons then
                self:Hide()
            end
        end)
    end)
end

-- Hook ExpansionLandingPageMinimapButton: when Blizzard's event system
-- initializes the button (sets title via UpdateIconForGarrison), reposition
-- it on the minimap and re-apply QUI's positioning. Also hook SetParent to
-- prevent other addons from reparenting it away from Minimap.
local expansionButtonHooked = false
local expansionButtonReparenting = false  -- guard against SetParent hook recursion
if ExpansionLandingPageMinimapButton and not expansionButtonHooked then
    expansionButtonHooked = true
    hooksecurefunc(ExpansionLandingPageMinimapButton, "SetParent", function()
        if expansionButtonReparenting then return end
        C_Timer.After(0, function()
            local s = GetSettings()
            if not s or not s.enabled then return end
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
            if not s or not s.enabled or not s.showMissions then return end
            if InCombatLockdown() then return end
            ExpansionLandingPageMinimapButton:ClearAllPoints()
            ExpansionLandingPageMinimapButton:SetPoint("LEFT", Minimap, "LEFT", -5, 0)
        end)
    end)
end

local function UpdateButtonVisibility()
    if InCombatLockdown() then return end
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

        -- NOTE: Removed direct `mailFrame.Layout = function() end` write which taints
        -- the Blizzard frame. hiddenButtonParent already has Layout defined on it,
        -- and when mailFrame is reparented there, Blizzard's Layout calls on the
        -- child frame itself should be safe since MailFrame typically has its own Layout.

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

        -- NOTE: Removed direct `craftingFrame.Layout = function() end` write which
        -- taints the Blizzard frame. See mailFrame comment above.

        if settings.showCraftingOrder then
            craftingFrame:SetParent(Minimap)
            craftingFrame:ClearAllPoints()
            craftingFrame:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", 28, 2)  -- Offset from mail
            craftingFrame:SetScale(0.8)
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
    
    -- Expansion landing page button (garrison/missions) - position at left side
    -- In WoW 12.0+, Blizzard only shows this button for characters with old
    -- expansion garrison content (WoD-Shadowlands). For Midnight, the landing
    -- page uses a different system. Respect Blizzard's visibility — only
    -- reposition the button if Blizzard has initialized it (self.title ~= nil),
    -- and allow the user setting to hide it.
    if ExpansionLandingPageMinimapButton then
        if settings.showMissions and ExpansionLandingPageMinimapButton.title then
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

local function SetupMicroBagVisibilityHooks()
    local microMenu = MicroMenuContainer or MicroMenu
    if microMenu and not microMenuShowHooked then
        microMenuShowHooked = true
        hooksecurefunc(microMenu, "Show", function(self)
            C_Timer.After(0, function()
                local settings = GetSettings()
                if settings and settings.hideMicroMenu then
                    self:Hide()
                end
            end)
        end)
    end

    local bagsBar = BagsBar
    if bagsBar and not bagsBarShowHooked then
        bagsBarShowHooked = true
        hooksecurefunc(bagsBar, "Show", function(self)
            C_Timer.After(0, function()
                local settings = GetSettings()
                if settings and settings.hideBagBar then
                    self:Hide()
                end
            end)
        end)
    end
end

local function UpdateMicroAndBagVisibility()
    if InCombatLockdown() then
        pendingMinimapRefresh = true
        return
    end
    local settings = GetSettings()
    if not settings or not settings.enabled then return end

    local microMenu = MicroMenuContainer or MicroMenu
    if microMenu then
        originalMicroMenuParent = originalMicroMenuParent or microMenu:GetParent()
        if settings.hideMicroMenu then
            microMenu:SetParent(hiddenActionBarParent)
            microMenu:Hide()
        else
            microMenu:SetParent(originalMicroMenuParent or UIParent)
            microMenu:Show()
        end
    end

    local bagsBar = BagsBar
    if bagsBar then
        originalBagsBarParent = originalBagsBarParent or bagsBar:GetParent()
        if settings.hideBagBar then
            bagsBar:SetParent(hiddenActionBarParent)
            bagsBar:Hide()
        else
            bagsBar:SetParent(originalBagsBarParent or UIParent)
            bagsBar:Show()
        end
    end
end

local function BuildMiddleClickMenu()
    local settings = GetSettings() or {}

    return {
        { text = "QUI Menu", isTitle = true, notCheckable = true },
        { text = "Achievements", notCheckable = true, func = function()
            if not SafeExecute(ToggleAchievementFrame) then
                ClickMicroButton("AchievementMicroButton")
            end
        end },
        { text = "Calendar", notCheckable = true, func = function() SafeExecute(ToggleCalendar) end },
        { text = "Character Info", notCheckable = true, func = function()
            if not SafeExecute(function() ToggleCharacter("PaperDollFrame") end) then
                ClickMicroButton("CharacterMicroButton")
            end
        end },
        { text = "Chat Channels", notCheckable = true, func = function()
            if not SafeExecute(ToggleChannelFrame) then
                ClickMicroButton("ChatFrameChannelButton")
            end
        end },
        { text = "Clock", notCheckable = true, func = function()
            if not SafeExecute(TimeManager_Toggle) then
                SafeExecute(function()
                    if TimeManagerFrame then
                        if TimeManagerFrame:IsShown() then TimeManagerFrame:Hide() else TimeManagerFrame:Show() end
                    end
                end)
            end
        end },
        { text = "Dungeon Journal", notCheckable = true, func = function()
            if not SafeExecute(ToggleEncounterJournal) then
                ClickMicroButton("EJMicroButton")
            end
        end },
        { text = "Guild", notCheckable = true, func = function()
            if not SafeExecute(ToggleGuildFrame) then
                ClickMicroButton("GuildMicroButton")
            end
        end },
        { text = "Looking For Group", notCheckable = true, func = function()
            if not SafeExecute(PVEFrame_ToggleFrame) then
                ClickMicroButton("LFDMicroButton")
            end
        end },
        { text = "Professions", notCheckable = true, func = function()
            if not SafeExecute(ToggleProfessionsBook) then
                ClickMicroButton("ProfessionMicroButton")
            end
        end },
        { text = "Quest Log", notCheckable = true, func = function() SafeExecute(ToggleQuestLog) end },
        { text = "Shop", notCheckable = true, func = function()
            if not SafeExecute(StoreMicroButton_OnClick) then
                ClickMicroButton("StoreMicroButton")
            end
        end },
        { text = "Social", notCheckable = true, func = function()
            if not SafeExecute(ToggleFriendsFrame) then
                ClickMicroButton("SocialsMicroButton")
            end
        end },
        { text = "Specialization", notCheckable = true, func = function() TryOpenSpecializationTab() end },
        { text = "Talents", notCheckable = true, func = function() TryOpenTalentsTab() end },
        { text = "Spellbook", notCheckable = true, func = function()
            TryOpenSpellbookTab()
        end },
        { text = "Warband Collections", notCheckable = true, func = function()
            if not SafeExecute(ToggleCollectionsJournal) then
                ClickMicroButton("CollectionsMicroButton")
            end
        end },
        { text = "Game Menu", notCheckable = true, func = function()
            if InCombatLockdown() then return end

            -- Prefer UIPanel flow (ESC-equivalent path used by skin watcher).
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

                -- Last-resort fallback if client blocks the above from this context.
                if GameMenuFrame and GameMenuFrame.Show then
                    GameMenuFrame:Show()
                    -- Kick UIPanel hook once so skin watcher can still attach.
                    if ShowUIPanel then
                        ShowUIPanel(GameMenuFrame)
                    end
                end
                return GameMenuFrame and GameMenuFrame:IsShown()
            end

            SafeExecute(OpenGameMenu)
        end },
        { text = "Customer Support", notCheckable = true, func = function()
            if not SafeExecute(ToggleHelpFrame) then
                ClickMicroButton("HelpMicroButton")
            end
        end },
        { text = "", disabled = true, notCheckable = true },
        { text = "Hide Micro Menu", keepShownOnClick = true, checked = settings.hideMicroMenu and true or false, func = function()
            settings.hideMicroMenu = not settings.hideMicroMenu
            UpdateMicroAndBagVisibility()
        end },
        { text = "Hide Bag Bar", keepShownOnClick = true, checked = settings.hideBagBar and true or false, func = function()
            settings.hideBagBar = not settings.hideBagBar
            UpdateMicroAndBagVisibility()
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
    local QUI = _G.QUI
    local fontPath = QUI and QUI.GetGlobalFont and QUI:GetGlobalFont() or STANDARD_TEXT_FONT
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

    local px = (QUI and QUI.GetPixelSize and QUI:GetPixelSize(middleClickMenuFrame)) or 1
    middleClickMenuFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
        insets = { left = px, right = px, top = px, bottom = px },
    })
    middleClickMenuFrame:SetBackdropColor(bgR, bgG, bgB, bgA)
    middleClickMenuFrame:SetBackdropBorderColor(borderR, borderG, borderB, borderA)

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
            row.text:SetFont(fontPath, fontSize, "OUTLINE")
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

    if EasyMenu then
        -- noop: keep variable reference to avoid lint false-positives in mixed client APIs.
    end
end

local function SetupMiddleClickMenu()
    if middleClickMenuHooked then return end
    middleClickMenuHooked = true

    -- TAINT SAFETY: Use HookScript instead of SetScript so Blizzard's
    -- original OnMouseUp handler keeps running in secure context.
    -- SetScript would replace the handler, causing PingLocation() to
    -- execute in QUI's addon context → ADDON_ACTION_FORBIDDEN.
    Minimap:HookScript("OnMouseUp", function(self, button)
        local settings = GetSettings()
        if settings and settings.enabled and settings.middleClickMenuEnabled and button == "MiddleButton" then
            ShowMiddleClickMenu()
        end
    end)
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

    -- Reset scale and strata
    btn:SetScale(1.0)
    btn:SetFrameStrata("MEDIUM")
end

local function UpdateDungeonEyePosition()
    if InCombatLockdown() then return end
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
        btn:SetFrameStrata("MEDIUM")
        -- Do NOT call btn:Show() - let Blizzard control visibility based on queue status
    else
        -- Restore original position
        RestoreDungeonEye()
    end
end

local function SetupDungeonEyeHook()
    if dungeonEyeHooked then return end
    if not QueueStatusButton then return end

    -- TAINT SAFETY: Defer ALL addon logic to break taint chain from secure context.
    -- Hook UpdatePosition to re-apply our positioning after Blizzard resets it
    if QueueStatusButton.UpdatePosition then
        hooksecurefunc(QueueStatusButton, "UpdatePosition", function()
            C_Timer.After(0, function()
                local settings = GetSettings()
                if settings and settings.dungeonEye and settings.dungeonEye.enabled then
                    UpdateDungeonEyePosition()
                end
            end)
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
    -- When the button drawer is enabled, it manages buttons instead
    if settings.buttonDrawer and settings.buttonDrawer.enabled then return end

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
--- BUTTON DRAWER
---=================================================================================

local DRAWER_BLACKLIST = {
    ["MiniMapMailFrame"] = true,
    ["MinimapZoomIn"] = true,
    ["MinimapZoomOut"] = true,
    ["MiniMapTracking"] = true,
    ["MinimapBackdrop"] = true,
    ["GameTimeFrame"] = true,
    ["TimeManagerClockButton"] = true,
    ["QueueStatusMinimapButton"] = true,
    ["GarrisonLandingPageMinimapButton"] = true,
    ["ExpansionLandingPageMinimapButton"] = true,
    ["AddonCompartmentFrame"] = true,
    ["QUI_MinimapBackdrop"] = true,
    ["QUI_MinimapButtonDrawer"] = true,
    ["QUI_DrawerToggle"] = true,
}

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

local function IsMinimapButton(frame)
    if not frame or not frame.IsObjectType then return false end
    if not (frame:IsObjectType("Frame") or frame:IsObjectType("Button")) then return false end
    local name = frame:GetName()
    if not name or DRAWER_BLACKLIST[name] then return false end
    -- Skip Blizzard-owned secure frames
    if issecurevariable(_G, name) then return false end
    -- LibDBIcon buttons
    if name:match("^LibDBIcon10_") then return true end
    -- Common minimap button naming patterns
    if name:match("MinimapButton") or name:match("MinimapFrame") or name:match("MinimapIcon") then return true end
    if name:match("Minimap$") then return true end
    -- Reject names ending in digits (pin/node/tracking frames)
    if name:match("%d$") then return false end
    -- Accept if it has click handlers and is a child of Minimap
    local parent = frame:GetParent()
    if parent and (parent == Minimap or parent == MinimapBackdrop) then
        local ok, hasClick = pcall(function() return frame:HasScript("OnClick") and frame:GetScript("OnClick") end)
        local ok2, hasMouseUp = pcall(function() return frame:HasScript("OnMouseUp") and frame:GetScript("OnMouseUp") end)
        local ok3, hasMouseDown = pcall(function() return frame:HasScript("OnMouseDown") and frame:GetScript("OnMouseDown") end)
        if (ok and hasClick) or (ok2 and hasMouseUp) or (ok3 and hasMouseDown) then
            return true
        end
    end
    return false
end

local function ShouldSkipDrawerButton(name)
    if not name then return true end
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
    -- Find the icon texture for square conversion
    local iconTex = frame.icon  -- LibDBIcon buttons always have .icon
    if not iconTex then
        pcall(function()
            for _, region in ipairs({ frame:GetRegions() }) do
                if region:IsObjectType("Texture") and region:GetTexture() and region:GetDrawLayer() == "ARTWORK" then
                    iconTex = region
                    break
                end
            end
        end)
    end
    local origOnDragStart, origOnDragStop
    pcall(function()
        if frame:HasScript("OnDragStart") then origOnDragStart = frame:GetScript("OnDragStart") end
        if frame:HasScript("OnDragStop") then origOnDragStop = frame:GetScript("OnDragStop") end
    end)
    collectedButtons[name] = {
        frame = frame,
        origParent = frame:GetParent(),
        origPoints = points,
        origOnDragStart = origOnDragStart,
        origOnDragStop = origOnDragStop,
        wasShown = frame:IsShown(),
        iconTex = iconTex,
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

        -- Smoothstep easing for a soft open/close.
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
    -- Auto-hide the toggle button if setting is enabled, but not while mouse is over it
    local settings = GetSettings()
    if settings and settings.buttonDrawer and settings.buttonDrawer.autoHideToggle and drawerToggleButton then
        if not drawerToggleButton:IsMouseOver() then
            drawerToggleButton:SetAlpha(0)
        end
    end
end

local function ShowDrawer()
    if drawerFrame and (not drawerVisible or not drawerFrame:IsShown()) then
        drawerVisible = true
        StartDrawerAnimation(true)
    end
    -- Ensure toggle button is visible when drawer opens
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
    if drawerVisible then return end  -- Don't hide while drawer is open
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

    local ok = pcall(function()
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
                    if region.SetMask then pcall(region.SetMask, region, "") end
                elseif layer == "HIGHLIGHT" then
                    -- skip highlight texture
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

    -- Collect and sort visible buttons (skip filtered ones)
    local sorted = {}
    for name, data in pairs(collectedButtons) do
        if hiddenButtons[name] or ShouldSkipDrawerButton(name) then
            -- Hide filtered buttons
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

    -- For horizontal growth, treat "Columns" as number of rows (lanes).
    -- This preserves vertical wrapping control while allowing the common
    -- case (Columns = 1) to grow horizontally as expected.
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
        else -- UP
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

    -- Layout in grid, force visibility and square icons
    for _, entry in ipairs(sorted) do
        local f = entry.frame
        local centerX = padding + (entry.centerX - minX)
        local centerY = padding + (entry.centerY - minY)
        f:ClearAllPoints()
        f:SetPoint("CENTER", drawerFrame, "BOTTOMLEFT", centerX, centerY)
        f:SetSize(bSize, bSize)

        -- Force visible via metatable (bypasses our overrides)
        local mt = getmetatable(f)
        if mt and mt.__index then
            mt.__index.SetAlpha(f, 1)
            mt.__index.Show(f)
        end

        -- Make icons square
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
        borderR, borderG, borderB, borderA = Helpers.GetSkinBorderColor()
    elseif _G.QUI and _G.QUI.GetAddonAccentColor then
        borderR, borderG, borderB, borderA = _G.QUI:GetAddonAccentColor()
    end
    borderA = borderA or 1

    if Helpers and Helpers.GetSkinBgColor then
        bgR, bgG, bgB, bgA = Helpers.GetSkinBgColor()
    end

    if drawerSettings and type(drawerSettings.borderColor) == "table" then
        local c = drawerSettings.borderColor
        borderR = c[1] or borderR
        borderG = c[2] or borderG
        borderB = c[3] or borderB
        borderA = c[4] or borderA
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

    local px = (_G.QUI and _G.QUI.GetPixelSize and _G.QUI:GetPixelSize(drawerFrame)) or 1
    local borderSize = 1
    if drawerSettings and drawerSettings.borderSize ~= nil then
        borderSize = drawerSettings.borderSize
    end
    borderSize = math.max(0, borderSize)
    local edgeSize = px * borderSize
    local hasBorder = borderSize > 0

    drawerFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = hasBorder and "Interface\\Buttons\\WHITE8x8" or nil,
        edgeSize = hasBorder and edgeSize or 0,
        insets = hasBorder and { left = edgeSize, right = edgeSize, top = edgeSize, bottom = edgeSize } or { left = 0, right = 0, top = 0, bottom = 0 },
    })
    drawerFrame:SetBackdropColor(bgR, bgG, bgB, bgA)
    drawerFrame:SetBackdropBorderColor(borderR, borderG, borderB, hasBorder and borderA or 0)
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

local function UpdateToggleIcon()
    if not drawerToggleButton then return end
    local s = GetSettings()
    local icon = (s and s.buttonDrawer and s.buttonDrawer.toggleIcon) or "hammer"
    local showHammer = (icon == "hammer")
    if drawerToggleButton._hammerIcon then
        drawerToggleButton._hammerIcon:SetShown(showHammer)
    end
    if drawerToggleButton._gridDots then
        for _, dot in ipairs(drawerToggleButton._gridDots) do
            dot:SetShown(not showHammer)
        end
    end
end

local function CreateDrawerToggleButton()
    if drawerToggleButton then return end
    drawerToggleButton = CreateFrame("Button", "QUI_DrawerToggle", Minimap)
    drawerToggleButton:SetSize(DEFAULT_TOGGLE_SIZE, DEFAULT_TOGGLE_SIZE)
    drawerToggleButton:SetFrameStrata("HIGH")
    drawerToggleButton:SetFrameLevel(Minimap:GetFrameLevel() + 5)

    -- Background
    local bg = drawerToggleButton:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.9)

    -- Hammer icon texture
    local hammer = drawerToggleButton:CreateTexture(nil, "ARTWORK")
    hammer:SetPoint("TOPLEFT", 2, -2)
    hammer:SetPoint("BOTTOMRIGHT", -2, 2)
    hammer:SetTexture("Interface\\AddOns\\QUI\\assets\\quazii_hammer")
    drawerToggleButton._hammerIcon = hammer

    -- Grid icon: 4 small squares (2x2 grid) — store refs for resizing
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

    -- Show/hide the correct icon based on settings
    UpdateToggleIcon()

    -- Border
    local border = drawerToggleButton:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints()
    border:SetColorTexture(1, 1, 1, 0.15)
    local inner = drawerToggleButton:CreateTexture(nil, "OVERLAY", nil, 1)
    inner:SetPoint("TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", -1, 1)
    inner:SetColorTexture(0, 0, 0, 0)  -- Transparent inner to create border effect
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
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Addon Button Drawer")
        GameTooltip:AddLine("|cffFFFFFFMouseover:|r Open drawer", 0.2, 1, 0.2)
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
        -- If drawer is closed and auto-hide is on, fade the toggle button
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

    -- Rescale grid dots proportionally (base: 5px dots, 2px gap, 4px offset at size 20)
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

    -- Update hammer icon insets proportionally
    if drawerToggleButton._hammerIcon then
        local inset = math.max(1, math.floor(2 * scale + 0.5))
        drawerToggleButton._hammerIcon:ClearAllPoints()
        drawerToggleButton._hammerIcon:SetPoint("TOPLEFT", inset, -inset)
        drawerToggleButton._hammerIcon:SetPoint("BOTTOMRIGHT", -inset, inset)
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

    drawerToggleButton:ClearAllPoints()

    -- Anchor toggle to minimap side/corner.
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

    -- Anchor drawer relative to the toggle so growth direction is honored
    -- from the toggle/button origin instead of being locked to minimap edge.
    drawerFrame:ClearAllPoints()
    if centerGrowth then
        drawerFrame:SetPoint("CENTER", drawerToggleButton, "CENTER", ofsX, ofsY)
    elseif direction == "LEFT" then
        drawerFrame:SetPoint("RIGHT", drawerToggleButton, "LEFT", -gap + ofsX, ofsY)
    elseif direction == "RIGHT" then
        drawerFrame:SetPoint("LEFT", drawerToggleButton, "RIGHT", gap + ofsX, ofsY)
    elseif direction == "UP" then
        drawerFrame:SetPoint("BOTTOM", drawerToggleButton, "TOP", ofsX, gap + ofsY)
    else -- DOWN
        drawerFrame:SetPoint("TOP", drawerToggleButton, "BOTTOM", ofsX, -gap + ofsY)
    end
end

local function CollectButton(frame, name)
    if collectedButtons[name] then return end
    if InCombatLockdown() then
        pendingDrawerSetup = true
        return
    end
    SaveOriginalState(frame, name)
    local data = collectedButtons[name]

    -- Undo LibDBIcon ShowOnEnter (uses SetAlpha(0), not Hide)
    if LibDBIcon and name:match("^LibDBIcon10_") then
        local buttonName = name:gsub("^LibDBIcon10_", "")
        LibDBIcon:ShowOnEnter(buttonName, false)
        -- Stop any fadeOut animation group
        pcall(function()
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

    -- Override Hide, SetShown, AND SetAlpha so nothing can re-hide
    -- LibDBIcon uses SetAlpha(0) + fadeOut animation, not Hide()
    local mt = getmetatable(frame)
    local mtSetAlpha = mt and mt.__index and mt.__index.SetAlpha
    frame.Hide = function() end
    frame.SetShown = function(self, shown)
        if shown and mt and mt.__index then
            mt.__index.Show(self)
        end
    end
    frame.SetAlpha = function(self, alpha)
        -- Only allow full opacity while in drawer
        if mtSetAlpha then
            mtSetAlpha(self, 1)
        end
    end
    -- Force visible using metatable methods (bypass our overrides for initial set)
    if mtSetAlpha then mtSetAlpha(frame, 1) end
    if mt and mt.__index then mt.__index.Show(frame) end

    -- Disable dragging
    if frame:HasScript("OnDragStart") then
        frame:SetScript("OnDragStart", nil)
    end
    if frame:HasScript("OnDragStop") then
        frame:SetScript("OnDragStop", nil)
    end
    -- Hook enter/leave for auto-hide
    if frame:HasScript("OnEnter") then
        frame:HookScript("OnEnter", function() CancelAutoHide() end)
    end
    if frame:HasScript("OnLeave") then
        frame:HookScript("OnLeave", OnDrawerLeave)
    end
end

local function ScanAndCollectButtons()
    if InCombatLockdown() then
        pendingDrawerSetup = true
        return
    end
    if not drawerFrame then return end

    -- Scan Minimap children
    for _, child in ipairs({ Minimap:GetChildren() }) do
        if IsMinimapButton(child) then
            local name = child:GetName()
            if name and not ShouldSkipDrawerButton(name) then
                CollectButton(child, name)
            end
        end
    end
    -- Scan MinimapBackdrop children (if exists)
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

    LayoutDrawerButtons()
end

local function ReleaseAllButtons()
    if InCombatLockdown() then
        pendingDrawerSetup = true
        return
    end
    for name, data in pairs(collectedButtons) do
        local frame = data.frame
        if frame then
            -- Remove our overrides (fall back to metatable methods)
            frame.Hide = nil
            frame.SetShown = nil
            frame.SetAlpha = nil
            -- Restore hidden overlay/border textures for LibDBIcon buttons
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
            pcall(function()
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

    if InCombatLockdown() then
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

    -- Auto-hide toggle button: show on minimap hover, hide on leave
    if settings.buttonDrawer.autoHideToggle then
        drawerToggleButton:SetAlpha(0)  -- Start hidden
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

    -- Hook LibDBIcon for late-loading buttons (use distinct owner to avoid conflict with SetupAddonButtonHiding)
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

    -- Delayed rescan to catch async button creation
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
        SetupButtonDrawer()  -- Will clean up
        return
    end
    if drawerFrame then
        ResizeDrawerToggle()
        StyleDrawerFrame()
        LayoutDrawerButtons()
        UpdateDrawerAnchor()
    else
        SetupButtonDrawer()
    end
end

---=================================================================================
--- MINIMAP SIZE AND POSITION
---=================================================================================

local function UpdateMinimapSize()
    if InCombatLockdown() then return end
    local settings = GetSettings()
    if not settings or not settings.enabled then return end
    
    -- Set minimap size (guard flag prevents external HUD false positives)
    quiUpdatingMinimap = true
    Minimap:SetSize(settings.size, settings.size)
    Minimap:SetScale(settings.scale or 1.0)
    quiUpdatingMinimap = false

    -- Force render update by toggling zoom.
    -- Use SetZoom API instead of ZoomIn/ZoomOut:Click() — clicking protected
    -- Blizzard buttons from addon code spreads taint into the secure context.
    local z = Minimap:GetZoom()
    if z < 5 then
        Minimap:SetZoom(z + 1)
        Minimap:SetZoom(z)
    else
        Minimap:SetZoom(z - 1)
        Minimap:SetZoom(z)
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
    if InCombatLockdown() then return end
    local settings = GetSettings()
    if not settings or not settings.enabled then return end
    
    -- Reparent minimap to UIParent for proper positioning
    Minimap:SetParent(UIParent)
    Minimap:SetFrameStrata("LOW")
    Minimap:SetFrameLevel(2)
    Minimap:SetFixedFrameStrata(true)
    Minimap:SetFixedFrameLevel(true)
    
    -- Reparent MinimapCluster to a hidden frame — QUI manages the minimap
    -- independently. This makes MinimapCluster permanently invisible
    -- regardless of Blizzard alpha resets during Edit Mode, eliminating
    -- the need for a secure proxy to keep it hidden.
    if MinimapCluster then
        local hiddenCluster = CreateFrame("Frame")
        hiddenCluster:Hide()
        MinimapCluster:SetParent(hiddenCluster)
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
        local point, _, relPoint, x, y = QUICore:SnapFramePosition(self)
        if point then
            settings.position = {point, relPoint, x, y}
        end
    end)

    -- Skip position application if the frame anchoring system owns this frame
    if _G.QUI_IsFrameOverridden and _G.QUI_IsFrameOverridden(Minimap) then
        return
    end

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
--- EXTERNAL HUD DETECTION
--- Detects when an external addon scales up / fades out the Minimap for a
--- full-screen HUD overlay, and hides all QUI decorations so they don't
--- appear as opaque artifacts on top of the transparent overlay.
---=================================================================================

local function HideAllDecorations()
    if backdropFrame then backdropFrame:Hide() end
    if clockFrame then clockFrame:Hide() end
    if coordsFrame then coordsFrame:Hide() end
    if zoneTextFrame then zoneTextFrame:Hide() end
    if datatextFrame then datatextFrame:Hide() end
    if drawerToggleButton then drawerToggleButton:Hide() end
    if drawerFrame then drawerFrame:Hide() end
    StopUpdateTickers()
end

local function CheckExternalHud()
    if quiUpdatingMinimap then return end

    local settings = GetSettings()
    if not settings or not settings.enabled then return end

    local currentScale = Minimap:GetScale()
    local currentAlpha = Minimap:GetEffectiveAlpha()
    local expectedScale = settings.scale or 1.0
    local expectedSize = settings.size or 140
    local currentWidth = Minimap:GetWidth()

    local hudDetected = (currentScale > expectedScale * 2.0)
        or (currentAlpha < 0.5)
        or (currentWidth > expectedSize * 2.0)
        or (Minimap:GetParent() ~= MinimapCluster)

    if hudDetected and not externalHudActive then
        externalHudActive = true
        HideAllDecorations()
    elseif not hudDetected and externalHudActive then
        externalHudActive = false
        Minimap_Module:Refresh()
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

    -- Block movement if minimap is locked by the anchoring system
    if _G.QUI_IsFrameLocked and _G.QUI_IsFrameLocked(Minimap) then
        Minimap:SetMovable(false)
        return
    end

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

    -- TAINT SAFETY: Defer to break taint chain from secure Blizzard context.
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
    SetupMicroBagVisibilityHooks()
    UpdateMicroAndBagVisibility()
    SetupAddonButtonHiding()
    SetupButtonDrawer()
    SetupDungeonEyeHook()
    UpdateDungeonEyePosition()
    SetupMouseWheelZoom()
    SetupMiddleClickMenu()
    SetupAutoZoom()

    -- Detect external HUD overlays that scale up / fade out / resize the Minimap
    hooksecurefunc(Minimap, "SetScale", function()
        C_Timer.After(0, CheckExternalHud)
    end)
    hooksecurefunc(Minimap, "SetAlpha", function()
        C_Timer.After(0, CheckExternalHud)
    end)
    hooksecurefunc(Minimap, "SetSize", function()
        C_Timer.After(0, CheckExternalHud)
    end)
    hooksecurefunc(Minimap, "SetParent", function()
        C_Timer.After(0, CheckExternalHud)
    end)

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
    if InCombatLockdown() then
        pendingMinimapRefresh = true
        return
    end

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
        if backdropFrame then
            backdropFrame:Hide()
        end
        if datatextFrame then
            datatextFrame:Hide()
        end
        -- Ensure minimap is still visible
        Minimap:Show()
        return
    end

    -- If an external HUD overlay is active, keep decorations hidden
    if externalHudActive then
        HideAllDecorations()
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
    SetupMicroBagVisibilityHooks()
    UpdateMicroAndBagVisibility()
    SetupAddonButtonHiding()
    RefreshButtonDrawer()
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
        local point, _, relPoint, x, y = QUICore:SnapFramePosition(self)
        if point then
            settings.position = {point, relPoint, x, y}
        end
    end)

    -- Restore saved position from profile — skip if the frame anchoring system owns this frame
    if not (_G.QUI_IsFrameOverridden and _G.QUI_IsFrameOverridden(Minimap)) then
        if settings.position and settings.position[1] and settings.position[2] then
            Minimap:ClearAllPoints()
            Minimap:SetPoint(settings.position[1], UIParent, settings.position[2], settings.position[3] or 0, settings.position[4] or 0)
        end
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
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            Minimap_Module:Initialize()
        elseif arg1 == "Blizzard_HybridMinimap" then
            -- Handle HybridMinimap loading (Delves/scenarios)
            local settings = GetSettings()
            if settings and settings.enabled then
                SetMinimapShape(settings.shape)
            end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Combat ended: run deferred drawer setup if one was requested during combat
        if pendingDrawerSetup then
            pendingDrawerSetup = false
            SetupButtonDrawer()
        end
        -- Combat ended: run deferred refresh if one was requested during combat
        if pendingMinimapRefresh then
            pendingMinimapRefresh = false
            Minimap_Module:Refresh()
        end
    end
end)

-- Calendar pending invites handling
local calendarFrame = CreateFrame("Frame")
calendarFrame:RegisterEvent("CALENDAR_UPDATE_PENDING_INVITES")
calendarFrame:RegisterEvent("CALENDAR_ACTION_PENDING")
calendarFrame:SetScript("OnEvent", function()
    local settings = GetSettings()
    if not settings or not settings.enabled then return end
    if InCombatLockdown() then return end

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

-- Expose refresh globals for options panel (matches pattern used by all other modules)
_G.QUI_RefreshMinimap = function()
    Minimap_Module:Refresh()
end

_G.QUI_RefreshMinimapButtonDrawer = function()
    RefreshButtonDrawer()
end

-- Expose collected button names for the options panel
_G.QUI_GetDrawerButtonNames = function()
    local names = {}
    for name in pairs(collectedButtons) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

