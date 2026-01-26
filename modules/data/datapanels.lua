--- QUI Datapanels
--- Creates and manages movable datatext panels

local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local LSM = LibStub("LibSharedMedia-3.0")

-- Module reference
local Datapanels = {}
QUICore.Datapanels = Datapanels

-- Active panels storage
Datapanels.activePanels = {}

---=================================================================================
--- PANEL CREATION
---=================================================================================

--- Create a movable datapanel
-- @param panelID string Unique panel identifier
-- @param config table Panel configuration
-- @return Frame The created panel frame
function Datapanels:CreatePanel(panelID, config)
    if self.activePanels[panelID] then
        print("|cffff0000QUI:|r Panel '" .. panelID .. "' already exists!")
        return self.activePanels[panelID]
    end
    
    -- Create panel frame
    local panel = CreateFrame("Frame", "QUI_Datapanel_" .. panelID, UIParent)
    panel:SetFrameStrata("LOW")
    panel:SetFrameLevel(100)
    panel:SetSize(config.width or 300, config.height or 22)
    
    -- Position
    if config.position then
        panel:SetPoint(config.position[1], UIParent, config.position[2], config.position[3], config.position[4])
    else
        panel:SetPoint("CENTER", UIParent, "CENTER", 0, 300)
    end
    
    -- Background
    panel.bg = panel:CreateTexture(nil, "BACKGROUND")
    panel.bg:SetAllPoints()
    panel.bg:SetColorTexture(0, 0, 0, (config.bgOpacity or 50) / 100)
    
    -- Borders
    local borderSize = config.borderSize or 2
    local borderColor = config.borderColor or {0, 0, 0, 1}
    panel.borderLeft = panel:CreateTexture(nil, "BORDER")
    panel.borderRight = panel:CreateTexture(nil, "BORDER")
    panel.borderTop = panel:CreateTexture(nil, "BORDER")
    panel.borderBottom = panel:CreateTexture(nil, "BORDER")

    panel.borderLeft:SetColorTexture(unpack(borderColor))
    panel.borderRight:SetColorTexture(unpack(borderColor))
    panel.borderTop:SetColorTexture(unpack(borderColor))
    panel.borderBottom:SetColorTexture(unpack(borderColor))
    
    panel.borderLeft:SetWidth(borderSize)
    panel.borderRight:SetWidth(borderSize)
    panel.borderTop:SetHeight(borderSize)
    panel.borderBottom:SetHeight(borderSize)

    -- Hide borders when borderSize is 0 (WoW enforces 1px minimum on textures)
    local showBorder = borderSize > 0
    panel.borderLeft:SetShown(showBorder)
    panel.borderRight:SetShown(showBorder)
    panel.borderTop:SetShown(showBorder)
    panel.borderBottom:SetShown(showBorder)

    panel.borderLeft:SetPoint("TOPRIGHT", panel, "TOPLEFT", 0, 0)
    panel.borderLeft:SetPoint("BOTTOMRIGHT", panel, "BOTTOMLEFT", 0, 0)
    
    panel.borderRight:SetPoint("TOPLEFT", panel, "TOPRIGHT", 0, 0)
    panel.borderRight:SetPoint("BOTTOMLEFT", panel, "BOTTOMRIGHT", 0, 0)
    
    panel.borderTop:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 0, 0)
    panel.borderTop:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", 0, 0)
    
    panel.borderBottom:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, 0)
    panel.borderBottom:SetPoint("TOPRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    
    -- Store config
    panel.panelID = panelID
    panel.config = config
    panel.slots = {}
    
    -- Setup dragging
    self:SetupDragging(panel)
    
    -- Create slots
    self:UpdateSlots(panel)
    
    -- Store panel
    self.activePanels[panelID] = panel
    
    -- Show/hide based on config AND whether any datatexts are assigned
    local hasDatatext = false
    if config.slots then
        for i = 1, (config.numSlots or 3) do
            if config.slots[i] and config.slots[i] ~= "" then
                hasDatatext = true
                break
            end
        end
    end
    
    if config.enabled and hasDatatext then
        panel:Show()
    else
        panel:Hide()
    end
    
    return panel
end

---=================================================================================
--- DRAGGING
---=================================================================================

function Datapanels:SetupDragging(panel)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetClampedToScreen(true)
    
    panel:SetScript("OnDragStart", function(self)
        if not self.config.locked then
            self:StartMoving()
        end
    end)
    
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        
        -- Save position
        local point, _, relPoint, x, y = self:GetPoint()
        self.config.position = {point, relPoint, x, y}
        
        -- Update saved variables
        local db = QUICore.db.profile.quiDatatexts
        if db and db.panels then
            for i, panelConfig in ipairs(db.panels) do
                if panelConfig.id == self.panelID then
                    db.panels[i].position = self.config.position
                    break
                end
            end
        end
    end)
end

--- Lock/unlock panel movement
function Datapanels:SetLocked(panelID, locked)
    local panel = self.activePanels[panelID]
    if not panel then return end
    
    panel.config.locked = locked
    panel:SetMovable(not locked)
    
    -- Visual feedback when unlocked
    if locked then
        panel.bg:SetColorTexture(0, 0, 0, (panel.config.bgOpacity or 50) / 100)
    else
        panel.bg:SetColorTexture(0.2, 0.2, 0.5, (panel.config.bgOpacity or 50) / 100)  -- Blue tint
    end
end

---=================================================================================
--- SLOT MANAGEMENT
---=================================================================================

function Datapanels:UpdateSlots(panel)
    -- Clear existing slots
    for _, slot in ipairs(panel.slots) do
        if QUICore.Datatexts then
            QUICore.Datatexts:DetachFromSlot(slot)
        end
        slot:Hide()
        slot:SetParent(nil)
    end
    panel.slots = {}
    
    local numSlots = panel.config.numSlots or 3
    local slotWidth = panel:GetWidth() / numSlots
    local slotHeight = panel:GetHeight()
    
    -- Apply font settings
    local generalFont = "Quazii"
    local generalOutline = "OUTLINE"
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general then
        local general = QUICore.db.profile.general
        generalFont = general.font or "Quazii"
        generalOutline = general.fontOutline or "OUTLINE"
    end
    local fontPath = LSM:Fetch("font", generalFont) or "Fonts\\FRIZQT__.TTF"
    local fontSize = panel.config.fontSize or 12
    
    for i = 1, numSlots do
        local slot = CreateFrame("Button", panel:GetName() .. "_Slot" .. i, panel)
        slot:SetSize(slotWidth, slotHeight)
        slot:SetPoint("LEFT", panel, "LEFT", (i - 1) * slotWidth, 0)
        
        -- Create text for datatext use
        slot.text = slot:CreateFontString(nil, "OVERLAY")
        QUICore:SafeSetFont(slot.text, fontPath, fontSize, generalOutline)
        -- Anchor to both edges to constrain width and enable auto-truncation
        slot.text:SetPoint("LEFT", slot, "LEFT", 1, 0)
        slot.text:SetPoint("RIGHT", slot, "RIGHT", -1, 0)
        slot.text:SetJustifyH("CENTER")
        slot.text:SetWordWrap(false)
        slot.text:SetTextColor(1, 1, 1, 1)
        
        -- Store slot index
        slot.index = i

        -- Apply per-slot shortLabel/noLabel settings (#119)
        local slotSettings = panel.config.slotSettings and panel.config.slotSettings[i]
        slot.shortLabel = slotSettings and slotSettings.shortLabel or false
        slot.noLabel = slotSettings and slotSettings.noLabel or false

        -- Forward drag events to parent
        slot:EnableMouse(true)
        slot:RegisterForDrag("LeftButton")
        slot:SetScript("OnDragStart", function()
            if not panel.config.locked then
                panel:StartMoving()
            end
        end)
        slot:SetScript("OnDragStop", function()
            panel:StopMovingOrSizing()
            
            -- Save position
            local point, _, relPoint, x, y = panel:GetPoint()
            panel.config.position = {point, relPoint, x, y}
        end)
        
        -- Attach datatext if configured
        local datatextID = panel.config.slots and panel.config.slots[i]
        if datatextID and QUICore.Datatexts then
            QUICore.Datatexts:AttachToSlot(slot, datatextID, panel.config)
        else
            -- Show placeholder for empty slots
            slot.text:SetText("|cffFFAA00Slot " .. i .. "|r")
            slot.text:Show()
        end
        
        table.insert(panel.slots, slot)
    end
end

---=================================================================================
--- PANEL MANAGEMENT
---=================================================================================

--- Update panel appearance
function Datapanels:UpdatePanel(panelID)
    local panel = self.activePanels[panelID]
    if not panel then return end
    
    -- Update size
    panel:SetSize(panel.config.width or 300, panel.config.height or 22)
    
    -- Update background opacity
    panel.bg:SetColorTexture(0, 0, 0, (panel.config.bgOpacity or 50) / 100)
    
    -- Update borders
    local borderSize = panel.config.borderSize or 2
    local borderColor = panel.config.borderColor or {0, 0, 0, 1}
    panel.borderLeft:SetWidth(borderSize)
    panel.borderRight:SetWidth(borderSize)
    panel.borderTop:SetHeight(borderSize)
    panel.borderBottom:SetHeight(borderSize)
    panel.borderLeft:SetColorTexture(unpack(borderColor))
    panel.borderRight:SetColorTexture(unpack(borderColor))
    panel.borderTop:SetColorTexture(unpack(borderColor))
    panel.borderBottom:SetColorTexture(unpack(borderColor))

    -- Hide borders when borderSize is 0 (WoW enforces 1px minimum on textures)
    local showBorder = borderSize > 0
    panel.borderLeft:SetShown(showBorder)
    panel.borderRight:SetShown(showBorder)
    panel.borderTop:SetShown(showBorder)
    panel.borderBottom:SetShown(showBorder)

    -- Update position if changed
    if panel.config.position then
        panel:ClearAllPoints()
        panel:SetPoint(panel.config.position[1], UIParent, panel.config.position[2], panel.config.position[3], panel.config.position[4])
    end
    
    -- Update slots
    self:UpdateSlots(panel)
    
    -- Show/hide
    if panel.config.enabled then
        panel:Show()
    else
        panel:Hide()
    end
end

--- Delete a panel
function Datapanels:DeletePanel(panelID)
    local panel = self.activePanels[panelID]
    if not panel then return end
    
    -- Detach all datatexts
    for _, slot in ipairs(panel.slots) do
        if QUICore.Datatexts then
            QUICore.Datatexts:DetachFromSlot(slot)
        end
    end
    
    -- Remove frame
    panel:Hide()
    panel:SetParent(nil)
    
    -- Remove from storage
    self.activePanels[panelID] = nil
end

--- Refresh all panels from saved variables
function Datapanels:RefreshAll()
    -- Clear existing panels
    for panelID, panel in pairs(self.activePanels) do
        self:DeletePanel(panelID)
    end
    
    -- Create panels from saved variables
    local db = QUICore.db.profile.quiDatatexts
    if not db or not db.panels then return end
    
    for _, panelConfig in ipairs(db.panels) do
        if panelConfig.id then
            self:CreatePanel(panelConfig.id, panelConfig)
        end
    end
end

---=================================================================================
--- GLOBAL REFRESH FUNCTION
---=================================================================================

_G.QUI_RefreshDatapanels = function()
    if QUICore and QUICore.Datapanels then
        QUICore.Datapanels:RefreshAll()
    end
end

---=================================================================================
--- INITIALIZATION
---=================================================================================

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0.5, function()
            Datapanels:RefreshAll()
            
            -- Debug: Show how many panels were created
            local count = 0
            for _ in pairs(Datapanels.activePanels) do
                count = count + 1
            end
            -- Panels created silently
        end)
        self:UnregisterAllEvents()
    end
end)

-- Debug slash command
SLASH_QUIDATAPANELS1 = "/quidp"
SlashCmdList["QUIDATAPANELS"] = function(msg)
    if msg == "show" then
        local count = 0
        for id, panel in pairs(Datapanels.activePanels) do
            count = count + 1
            print(string.format("|cff00ff00Panel %s:|r %s at %s, %dx%d, %s", 
                id, 
                panel:IsShown() and "VISIBLE" or "HIDDEN",
                tostring(panel.config.position),
                panel:GetWidth(),
                panel:GetHeight(),
                panel.config.enabled and "enabled" or "disabled"
            ))
        end
        print(string.format("|cff00ff00QUI:|r Total panels: %d", count))
    elseif msg == "refresh" then
        Datapanels:RefreshAll()
        print("|cff00ff00QUI:|r Refreshed all datapanels")
    else
        print("|cff00ff00QUI Datapanels Commands:|r")
        print("/quidp show - List all panels and their status")
        print("/quidp refresh - Refresh all panels")
    end
end

