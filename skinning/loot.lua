--- QUI Loot & Roll Frames
--- Custom loot window and roll frames with QUI styling
--- Replaces Blizzard's LootFrame and GroupLootFrame

local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local Helpers = ns.Helpers
local LSM = LibStub("LibSharedMedia-3.0")

local tinsert, tremove = tinsert, tremove

-- Module reference
local Loot = {}
QUICore.Loot = Loot

-- Helper to get theme colors from QUI skin system
local function GetThemeColors()
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = Helpers.GetSkinColors()
    return {bgr, bgg, bgb, bga}, {sr, sg, sb, sa}, {0.95, 0.96, 0.97, 1}
end

-- Constants
local MAX_LOOT_SLOTS = 10
local MAX_ROLL_FRAMES = 8  -- Increased from 4 to handle more simultaneous raid drops
local SLOT_HEIGHT = 32
local SLOT_WIDTH = 230
local SLOT_SPACING = 2
local HEADER_HEIGHT = 30
local LOOT_FRAME_WIDTH = 250
local LOOT_FRAME_HEIGHT = 200
local ICON_SIZE = 28
local ICON_BORDER_SIZE = 30
local ROLL_FRAME_HEIGHT = 50
local ROLL_FRAME_WIDTH = 340
local ROLL_ICON_SIZE = 32
local ROLL_BUTTON_SIZE = 26
local ROLL_TIMER_HEIGHT = 6

-- Roll button textures
local ROLL_TEXTURES = {
    pass = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
    disenchant = "Interface\\Buttons\\UI-GroupLoot-DE-Up",
    greed = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
    need = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
    transmog = "Interface\\MINIMAP\\TRACKING\\Transmogrifier",
}

-- Frame storage
local lootFrame = nil
local rollFramePool = {}
local activeRolls = {}
local rollAnchor = nil
local waitingRolls = {}  -- Queue for rolls when all frames are busy

-- Forward declarations (needed for mutual references)
local ProcessRollQueue
local StartRoll

---=================================================================================
--- UTILITY FUNCTIONS
---=================================================================================

local function GetGeneralFont()
    local db = QUICore.db and QUICore.db.profile and QUICore.db.profile.general
    return (db and db.font) or "Quazii"
end

local function GetDB()
    return QUICore.db and QUICore.db.profile or {}
end

local function IsUncollectedTransmog(itemLink)
    if not itemLink then return false end
    if not C_TransmogCollection or not C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance then
        return false
    end
    local itemID = GetItemInfoInstant(itemLink)
    if not itemID then return false end

    -- Check if it's equipment
    local _, _, _, _, _, classID = GetItemInfoInstant(itemLink)
    if classID ~= 2 and classID ~= 4 then return false end  -- Weapon or Armor

    -- Check if we can learn it
    local _, sourceID = C_TransmogCollection.GetItemInfo(itemLink)
    if sourceID then
        local _, canCollect = C_TransmogCollection.PlayerCanCollectSource(sourceID)
        if canCollect then
            local collected = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(sourceID)
            return not collected
        end
    end
    return false
end

---=================================================================================
--- LOOT WINDOW
---=================================================================================

local function CreateLootSlot(parent, index)
    local bgColor, borderColor, textColor = GetThemeColors()

    local slot = CreateFrame("Button", "QUI_LootSlot"..index, parent)
    slot:SetSize(SLOT_WIDTH, SLOT_HEIGHT)
    slot:SetPoint("TOP", parent, "TOP", 0, -HEADER_HEIGHT - ((index-1) * (SLOT_HEIGHT + SLOT_SPACING)))

    -- Icon
    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetSize(ICON_SIZE, ICON_SIZE)
    slot.icon:SetPoint("LEFT", 4, 0)
    slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Icon border (quality colored)
    slot.iconBorder = CreateFrame("Frame", nil, slot, "BackdropTemplate")
    slot.iconBorder:SetSize(ICON_BORDER_SIZE, ICON_BORDER_SIZE)
    slot.iconBorder:SetPoint("CENTER", slot.icon, "CENTER")
    slot.iconBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })

    -- Item name
    slot.name = slot:CreateFontString(nil, "OVERLAY")
    slot.name:SetFont(LSM:Fetch("font", GetGeneralFont()), 11, "OUTLINE")
    slot.name:SetPoint("LEFT", slot.icon, "RIGHT", 6, 0)
    slot.name:SetPoint("RIGHT", slot, "RIGHT", -40, 0)
    slot.name:SetJustifyH("LEFT")
    slot.name:SetWordWrap(false)

    -- Stack count
    slot.count = slot:CreateFontString(nil, "OVERLAY")
    slot.count:SetFont(LSM:Fetch("font", GetGeneralFont()), 10, "OUTLINE")
    slot.count:SetPoint("BOTTOMRIGHT", slot.icon, "BOTTOMRIGHT", -2, 2)
    slot.count:SetTextColor(1, 1, 1)

    -- Transmog marker (star icon for uncollected appearances)
    slot.transmogMarker = slot:CreateFontString(nil, "OVERLAY")
    slot.transmogMarker:SetFont(LSM:Fetch("font", GetGeneralFont()), 12, "OUTLINE")
    slot.transmogMarker:SetPoint("TOPRIGHT", slot, "TOPRIGHT", -4, -4)
    slot.transmogMarker:SetText("*")
    slot.transmogMarker:SetTextColor(1, 0.82, 0)  -- Gold
    slot.transmogMarker:Hide()

    -- Quest item indicator
    slot.questIcon = slot:CreateTexture(nil, "OVERLAY")
    slot.questIcon:SetSize(14, 14)
    slot.questIcon:SetPoint("TOPLEFT", slot.icon, "TOPLEFT", -2, 2)
    slot.questIcon:SetAtlas("QuestNormal")
    slot.questIcon:Hide()

    -- Hover highlight
    slot:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
    slot:GetHighlightTexture():SetVertexColor(borderColor[1], borderColor[2], borderColor[3], 0.2)

    -- Click to loot
    slot:SetScript("OnClick", function(self)
        if self.slotIndex then
            LootSlot(self.slotIndex)
        end
    end)

    -- Tooltip
    slot:SetScript("OnEnter", function(self)
        if self.slotIndex then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local ok = pcall(GameTooltip.SetLootItem, GameTooltip, self.slotIndex)
            if ok then
                GameTooltip:Show()
            else
                GameTooltip:Hide()
            end
        end
    end)
    slot:SetScript("OnLeave", GameTooltip_Hide)

    slot:Hide()
    return slot
end

local function CreateLootWindow()
    local bgColor, borderColor, textColor = GetThemeColors()

    local frame = CreateFrame("Frame", "QUI_LootFrame", UIParent, "BackdropTemplate")
    frame:SetSize(LOOT_FRAME_WIDTH, LOOT_FRAME_HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:Hide()

    -- QUI backdrop
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(unpack(bgColor))
    frame:SetBackdropBorderColor(unpack(borderColor))

    -- Header
    frame.header = frame:CreateFontString(nil, "OVERLAY")
    frame.header:SetFont(LSM:Fetch("font", GetGeneralFont()), 12, "OUTLINE")
    frame.header:SetPoint("TOP", 0, -8)
    frame.header:SetTextColor(unpack(textColor))
    frame.header:SetText("Loot")

    -- Dragging
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local db = GetDB()
        if db.loot then
            local point, _, relPoint, x, y = self:GetPoint()
            db.loot.position = { point = point, relPoint = relPoint, x = x, y = y }
        end
    end)

    -- Close button
    frame.closeBtn = CreateFrame("Button", nil, frame)
    frame.closeBtn:SetSize(16, 16)
    frame.closeBtn:SetPoint("TOPRIGHT", -4, -4)
    frame.closeBtn.text = frame.closeBtn:CreateFontString(nil, "OVERLAY")
    frame.closeBtn.text:SetFont(LSM:Fetch("font", GetGeneralFont()), 14, "OUTLINE")
    frame.closeBtn.text:SetAllPoints()
    frame.closeBtn.text:SetText("x")
    frame.closeBtn.text:SetTextColor(0.8, 0.8, 0.8)
    frame.closeBtn:SetScript("OnClick", function() CloseLoot() end)
    frame.closeBtn:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 0.3, 0.3) end)
    frame.closeBtn:SetScript("OnLeave", function(self) self.text:SetTextColor(0.8, 0.8, 0.8) end)

    -- Loot slots
    frame.slots = {}
    for i = 1, MAX_LOOT_SLOTS do
        frame.slots[i] = CreateLootSlot(frame, i)
    end

    return frame
end

local function OnLootOpened(autoLoot)
    local numItems = GetNumLootItems()
    if numItems == 0 then return end

    local db = GetDB()
    if not db.loot or not db.loot.enabled then return end

    -- Skip custom loot frame when fast auto loot is enabled
    -- Fast loot clears items faster than the frame can populate
    if db.general and db.general.fastAutoLoot then return end

    -- Position window
    if db.loot.lootUnderMouse then
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        lootFrame:ClearAllPoints()
        lootFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x/scale, y/scale)
    elseif db.loot.position and db.loot.position.point then
        lootFrame:ClearAllPoints()
        lootFrame:SetPoint(db.loot.position.point, UIParent, db.loot.position.relPoint or "CENTER",
                           db.loot.position.x or 0, db.loot.position.y or 100)
    else
        lootFrame:ClearAllPoints()
        lootFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    end

    -- Populate slots
    local visibleSlots = 0
    for i = 1, numItems do
        local slot = lootFrame.slots[i]
        if slot and LootSlotHasItem(i) then
            local texture, name, quantity, currencyID, quality, locked, isQuestItem,
                  questID, isActive = GetLootSlotInfo(i)

            slot.slotIndex = i
            slot.icon:SetTexture(texture)
            slot.name:SetText(name or "")

            -- Quality color
            local r, g, b = GetItemQualityColor(quality or 1)
            slot.iconBorder:SetBackdropBorderColor(r, g, b, 1)
            slot.name:SetTextColor(r, g, b)

            -- Stack count
            if quantity and quantity > 1 then
                slot.count:SetText(quantity)
                slot.count:Show()
            else
                slot.count:Hide()
            end

            -- Quest indicator
            slot.questIcon:SetShown(isQuestItem or (questID and questID > 0))

            -- Transmog marker (check if uncollected appearance)
            if db.loot.showTransmogMarker then
                local link = GetLootSlotLink(i)
                local isUncollected = IsUncollectedTransmog(link)
                slot.transmogMarker:SetShown(isUncollected)
            else
                slot.transmogMarker:Hide()
            end

            slot:Show()
            visibleSlots = visibleSlots + 1
        elseif slot then
            slot:Hide()
        end
    end

    -- Hide unused slots
    for i = numItems + 1, MAX_LOOT_SLOTS do
        if lootFrame.slots[i] then
            lootFrame.slots[i]:Hide()
        end
    end

    -- Resize window to fit items
    local height = 40 + (visibleSlots * (SLOT_HEIGHT + SLOT_SPACING))
    lootFrame:SetHeight(height)
    lootFrame:Show()
end

local function OnLootSlotCleared(slot)
    if lootFrame and lootFrame.slots[slot] then
        lootFrame.slots[slot]:Hide()
        -- Don't resize frame - just hide the slot
        -- Frame will close via LOOT_CLOSED when all items are looted
    end
end

local function OnLootClosed()
    if lootFrame then
        lootFrame:Hide()
        for i = 1, MAX_LOOT_SLOTS do
            if lootFrame.slots[i] then
                lootFrame.slots[i]:Hide()
            end
        end
    end
end

---=================================================================================
--- ROLL FRAMES
---=================================================================================

local function CreateRollButton(parent, rollType, rollValue, texture)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(ROLL_BUTTON_SIZE, ROLL_BUTTON_SIZE)

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    btn.icon:SetTexture(texture)

    -- Subtle background for button
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(0, 0, 0, 0.3)

    btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

    btn.rollValue = rollValue
    btn.rollType = rollType

    -- Click handler - call RollOnLoot and hide frame immediately
    btn:SetScript("OnClick", function(self)
        local frame = self:GetParent()
        if frame.rollID then
            local rollID = frame.rollID
            RollOnLoot(rollID, self.rollValue)
            -- Hide frame immediately after rolling (don't wait for CANCEL_LOOT_ROLL)
            frame:Hide()
            frame.rollID = nil
            frame.timer:SetScript("OnUpdate", nil)
            activeRolls[rollID] = nil
            -- Defer repositioning and queue processing
            C_Timer.After(0, ProcessRollQueue)
        end
    end)

    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(rollType)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)

    return btn
end

-- Quality background tint colors (subtle)
local QUALITY_BG_TINTS = {
    [0] = { 0.5, 0.5, 0.5, 0.08 },   -- Poor (gray)
    [1] = { 1.0, 1.0, 1.0, 0.05 },   -- Common (white)
    [2] = { 0.12, 1.0, 0.0, 0.08 },  -- Uncommon (green)
    [3] = { 0.0, 0.44, 0.87, 0.1 },  -- Rare (blue)
    [4] = { 0.64, 0.21, 0.93, 0.12 }, -- Epic (purple)
    [5] = { 1.0, 0.5, 0.0, 0.15 },   -- Legendary (orange)
}


local function CreateRollFrame(index)
    local bgColor, borderColor, textColor = GetThemeColors()

    local frame = CreateFrame("Frame", "QUI_LootRollFrame"..index, UIParent, "BackdropTemplate")
    frame:SetSize(ROLL_FRAME_WIDTH, ROLL_FRAME_HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)

    -- Minimal backdrop (very subtle border)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], 0.95)
    frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 0.3)  -- Very subtle border

    -- Quality tint overlay (set per item)
    frame.qualityTint = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    frame.qualityTint:SetAllPoints()
    frame.qualityTint:SetColorTexture(1, 1, 1, 0.1)
    frame.qualityTint:SetBlendMode("ADD")

    -- Icon (larger) - centered vertically above timer bar
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetSize(ROLL_ICON_SIZE, ROLL_ICON_SIZE)
    frame.icon:SetPoint("LEFT", 4, 4)  -- Centered above timer bar
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Icon border (quality) - thicker border
    frame.iconBorder = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.iconBorder:SetSize(ROLL_ICON_SIZE + 4, ROLL_ICON_SIZE + 4)
    frame.iconBorder:SetPoint("CENTER", frame.icon, "CENTER")
    frame.iconBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })

    -- Item name (larger font) - aligned with icon
    frame.name = frame:CreateFontString(nil, "OVERLAY")
    frame.name:SetFont(LSM:Fetch("font", GetGeneralFont()), 12, "OUTLINE")
    frame.name:SetPoint("LEFT", frame.icon, "RIGHT", 8, 0)
    frame.name:SetPoint("RIGHT", frame, "RIGHT", -120, 4)  -- More room for buttons
    frame.name:SetJustifyH("LEFT")
    frame.name:SetWordWrap(false)

    -- Timer bar (full width at very bottom)
    frame.timer = CreateFrame("StatusBar", nil, frame)
    frame.timer:SetHeight(ROLL_TIMER_HEIGHT)
    frame.timer:SetPoint("BOTTOMLEFT", 4, 4)
    frame.timer:SetPoint("BOTTOMRIGHT", -4, 4)
    frame.timer:SetStatusBarTexture(LSM:Fetch("statusbar", "Quazii") or "Interface\\TargetingFrame\\UI-StatusBar")
    frame.timer:SetStatusBarColor(borderColor[1], borderColor[2], borderColor[3], 1)  -- Accent color
    frame.timer:SetMinMaxValues(0, 1)
    frame.timer:SetValue(1)

    -- Timer background
    frame.timer.bg = frame.timer:CreateTexture(nil, "BACKGROUND")
    frame.timer.bg:SetAllPoints()
    frame.timer.bg:SetColorTexture(0, 0, 0, 0.6)

    -- Roll buttons (right to left: Pass, DE, Greed, Need) - centered vertically above timer
    local buttonY = 4  -- Centered in content area above timer
    frame.passBtn = CreateRollButton(frame, "Pass", 0, ROLL_TEXTURES.pass)
    frame.passBtn:SetPoint("RIGHT", frame, "RIGHT", -6, buttonY)

    frame.disenchantBtn = CreateRollButton(frame, "Disenchant", 3, ROLL_TEXTURES.disenchant)
    frame.disenchantBtn:SetPoint("RIGHT", frame.passBtn, "LEFT", -4, 0)

    frame.greedBtn = CreateRollButton(frame, "Greed", 2, ROLL_TEXTURES.greed)
    frame.greedBtn:SetPoint("RIGHT", frame.disenchantBtn, "LEFT", -4, 0)

    -- Transmog button (rollValue=4) - swaps with Greed when transmog available
    frame.transmogBtn = CreateRollButton(frame, TRANSMOGRIFY, 4, ROLL_TEXTURES.transmog)
    frame.transmogBtn:SetPoint("RIGHT", frame.disenchantBtn, "LEFT", -4, 0)
    frame.transmogBtn:Hide()  -- Hidden by default, shown when canTransmog

    frame.needBtn = CreateRollButton(frame, "Need", 1, ROLL_TEXTURES.need)
    frame.needBtn:SetPoint("RIGHT", frame.greedBtn, "LEFT", -4, 0)

    -- Item tooltip on hover
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        if self.rollID then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
            GameTooltip:SetLootRollItem(self.rollID)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)

    frame:Hide()
    return frame
end

local function GetAvailableRollFrame()
    local db = GetDB()
    local maxVisible = (db.lootRoll and db.lootRoll.maxFrames) or 4

    -- Count currently visible frames
    local visibleCount = 0
    for i = 1, MAX_ROLL_FRAMES do
        if rollFramePool[i] and rollFramePool[i]:IsShown() then
            visibleCount = visibleCount + 1
        end
    end

    -- If at max visible, return nil to trigger queue
    if visibleCount >= maxVisible then
        return nil
    end

    -- Find an available frame from the pool
    for i = 1, MAX_ROLL_FRAMES do
        if not rollFramePool[i] then
            rollFramePool[i] = CreateRollFrame(i)
        end
        if not rollFramePool[i]:IsShown() then
            return rollFramePool[i]
        end
    end
    return nil
end

local function PositionRollFrame(frame)
    local db = GetDB()
    local growDirection = (db.lootRoll and db.lootRoll.growDirection) or "DOWN"
    local spacing = (db.lootRoll and db.lootRoll.spacing) or 4

    local index = 0
    for _, f in pairs(activeRolls) do
        if f:IsShown() and f ~= frame then
            index = index + 1
        end
    end

    frame:ClearAllPoints()
    if growDirection == "UP" then
        frame:SetPoint("BOTTOM", rollAnchor, "TOP", 0, (index * (ROLL_FRAME_HEIGHT + spacing)))
    else
        frame:SetPoint("TOP", rollAnchor, "BOTTOM", 0, -(index * (ROLL_FRAME_HEIGHT + spacing)))
    end
end

local function RepositionAllRolls()
    local db = GetDB()
    local growDirection = (db.lootRoll and db.lootRoll.growDirection) or "DOWN"
    local spacing = (db.lootRoll and db.lootRoll.spacing) or 4

    local index = 0
    for _, frame in pairs(activeRolls) do
        if frame:IsShown() then
            frame:ClearAllPoints()
            if growDirection == "UP" then
                frame:SetPoint("BOTTOM", rollAnchor, "TOP", 0, (index * (ROLL_FRAME_HEIGHT + spacing)))
            else
                frame:SetPoint("TOP", rollAnchor, "BOTTOM", 0, -(index * (ROLL_FRAME_HEIGHT + spacing)))
            end
            index = index + 1
        end
    end
end

-- Process the waiting queue when a roll frame becomes available
ProcessRollQueue = function()
    RepositionAllRolls()
    if #waitingRolls > 0 then
        local nextRoll = tremove(waitingRolls, 1)
        -- Validate the roll is still valid before starting
        local texture = GetLootRollItemInfo(nextRoll.rollID)
        if texture then
            StartRoll(nextRoll.rollID, nextRoll.rollTime)
        elseif #waitingRolls > 0 then
            -- Roll was cancelled/expired, try next in queue
            ProcessRollQueue()
        end
    end
end

StartRoll = function(rollID, rollTime, lootHandle)
    local db = GetDB()
    if not db.lootRoll or not db.lootRoll.enabled then return end

    local texture, name, count, quality, bop, canNeed, canGreed, canDE, reason, deReason, _, _, canTransmog = GetLootRollItemInfo(rollID)
    if not texture then return end

    local frame = GetAvailableRollFrame()
    if not frame then
        -- All frames busy - queue this roll for later
        tinsert(waitingRolls, { rollID = rollID, rollTime = rollTime })
        return
    end

    -- Reset frame state from previous roll
    frame:SetAlpha(1)
    frame:SetScript("OnUpdate", nil)

    -- Reset all buttons to default state
    local buttons = { frame.needBtn, frame.greedBtn, frame.disenchantBtn, frame.passBtn, frame.transmogBtn }
    for _, btn in ipairs(buttons) do
        btn:Enable()
        btn:SetAlpha(1)
        btn.icon:SetDesaturated(false)
        btn:Show()  -- Reset visibility
    end

    frame.rollID = rollID
    frame.rollTime = rollTime
    frame.startTime = GetTime()

    frame.icon:SetTexture(texture)
    frame.name:SetText(name or "")

    -- Quality color
    local r, g, b = GetItemQualityColor(quality or 1)
    frame.iconBorder:SetBackdropBorderColor(r, g, b, 1)
    frame.name:SetTextColor(r, g, b)

    -- Quality background tint
    local tint = QUALITY_BG_TINTS[quality or 1] or QUALITY_BG_TINTS[1]
    frame.qualityTint:SetColorTexture(tint[1], tint[2], tint[3], tint[4])

    -- Enable/disable buttons based on eligibility
    frame.needBtn:SetEnabled(canNeed)
    frame.needBtn.icon:SetDesaturated(not canNeed)
    frame.needBtn:SetAlpha(canNeed and 1 or 0.4)

    frame.greedBtn:SetEnabled(canGreed)
    frame.greedBtn.icon:SetDesaturated(not canGreed)
    frame.greedBtn:SetAlpha(canGreed and 1 or 0.4)

    frame.disenchantBtn:SetEnabled(canDE)
    frame.disenchantBtn.icon:SetDesaturated(not canDE)
    frame.disenchantBtn:SetAlpha(canDE and 1 or 0.4)
    frame.disenchantBtn:SetShown(canDE)

    -- Transmog button handling (swaps with Greed)
    if canTransmog then
        -- Show transmog, hide greed
        frame.transmogBtn:SetEnabled(true)
        frame.transmogBtn.icon:SetDesaturated(false)
        frame.transmogBtn:SetAlpha(1)
        frame.transmogBtn:Show()
        frame.greedBtn:Hide()
        -- Reanchor need button to transmog
        frame.needBtn:ClearAllPoints()
        frame.needBtn:SetPoint("RIGHT", frame.transmogBtn, "LEFT", -4, 0)
    else
        -- Show greed, hide transmog
        frame.transmogBtn:Hide()
        frame.greedBtn:Show()
        -- Reanchor need button to greed
        frame.needBtn:ClearAllPoints()
        frame.needBtn:SetPoint("RIGHT", frame.greedBtn, "LEFT", -4, 0)
    end

    -- Position in stack
    PositionRollFrame(frame)

    -- Timer update
    local _, accentColor = GetThemeColors()
    frame.timer:SetStatusBarColor(accentColor[1], accentColor[2], accentColor[3], 1)
    frame.timer:SetScript("OnUpdate", function(self, elapsed)
        local remaining = frame.rollTime - (GetTime() - frame.startTime)
        if remaining > 0 then
            self:SetValue(remaining / frame.rollTime)
        else
            self:SetValue(0)
            self:SetScript("OnUpdate", nil)  -- Stop updates when timer expires
        end
    end)

    activeRolls[rollID] = frame
    frame:Show()
end

local function CancelRoll(rollID)
    -- Check if roll is in the waiting queue and remove it
    for i = #waitingRolls, 1, -1 do
        if waitingRolls[i].rollID == rollID then
            tremove(waitingRolls, i)
            return
        end
    end

    -- Check active rolls
    local frame = activeRolls[rollID]
    if frame then
        frame:Hide()
        frame.rollID = nil
        frame.timer:SetScript("OnUpdate", nil)
        activeRolls[rollID] = nil
        -- Use C_Timer to defer repositioning and queue processing
        C_Timer.After(0, ProcessRollQueue)
    end
end

---=================================================================================
--- ANCHOR FRAME (For positioning roll frames)
---=================================================================================

local function CreateRollAnchor()
    local anchor = CreateFrame("Frame", "QUI_LootRollAnchor", UIParent, "BackdropTemplate")
    anchor:SetSize(ROLL_FRAME_WIDTH, 1)
    anchor:SetPoint("TOP", UIParent, "TOP", 0, -200)
    anchor:SetMovable(true)
    anchor:EnableMouse(false)

    -- Hidden by default - only shown in config/test mode
    anchor:Hide()

    return anchor
end

---=================================================================================
--- LOOT HISTORY FRAME SKINNING (Retail GroupLootHistoryFrame)
---=================================================================================

local lootHistorySkinned = false

-- Skin individual loot history item elements
local function SkinLootHistoryElement(button)
    if button.QUISkinned then return end

    -- Strip background textures
    if button.BackgroundArtFrame then
        button.BackgroundArtFrame:SetAlpha(0)
    end

    if button.NameFrame then
        button.NameFrame:SetAlpha(0)
    end

    if button.BorderFrame then
        button.BorderFrame:SetAlpha(0)
    end

    -- Style the item icon
    local item = button.Item
    if item then
        local icon = item.icon or item.Icon
        if icon then
            -- Hide existing textures instead of setting to nil
            if item.NormalTexture then item.NormalTexture:SetAlpha(0) end
            if item.PushedTexture then item.PushedTexture:SetAlpha(0) end
            if item.HighlightTexture then item.HighlightTexture:SetAlpha(0) end

            -- Create QUI-style icon border
            if not item.quiBorder then
                item.quiBorder = CreateFrame("Frame", nil, item, "BackdropTemplate")
                item.quiBorder:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
                item.quiBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
                item.quiBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
                item.quiBorder:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
            end

            -- Apply texcoord
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            -- Hook IconBorder to update our border color
            if item.IconBorder and not item._quiBorderHooked then
                item._quiBorderHooked = true
                hooksecurefunc(item.IconBorder, "SetVertexColor", function(self, r, g, b)
                    if item.quiBorder then
                        item.quiBorder:SetBackdropBorderColor(r, g, b, 1)
                    end
                end)
                item.IconBorder:SetAlpha(0)  -- Hide Blizzard's border
            end
        end
    end

    button.QUISkinned = true
end

-- Handle scrollbox updates to skin new elements
local function HandleLootHistoryScrollUpdate(scrollBox)
    scrollBox:ForEachFrame(SkinLootHistoryElement)
end

-- Main function to skin GroupLootHistoryFrame
local function SkinGroupLootHistoryFrame()
    if lootHistorySkinned then return end

    local HistoryFrame = _G.GroupLootHistoryFrame
    if not HistoryFrame then return end

    local db = GetDB()
    local bgColor, borderColor, textColor = GetThemeColors()

    -- Strip Blizzard textures
    if HistoryFrame.NineSlice then
        HistoryFrame.NineSlice:SetAlpha(0)
    end
    if HistoryFrame.Bg then
        HistoryFrame.Bg:SetAlpha(0)
    end

    -- Apply QUI backdrop
    if not HistoryFrame.quiBackdrop then
        HistoryFrame.quiBackdrop = CreateFrame("Frame", nil, HistoryFrame, "BackdropTemplate")
        HistoryFrame.quiBackdrop:SetAllPoints()
        HistoryFrame.quiBackdrop:SetFrameLevel(HistoryFrame:GetFrameLevel())
        HistoryFrame.quiBackdrop:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
    end
    HistoryFrame.quiBackdrop:SetBackdropColor(unpack(bgColor))
    HistoryFrame.quiBackdrop:SetBackdropBorderColor(unpack(borderColor))

    -- Style the timer bar
    local Timer = HistoryFrame.Timer
    if Timer then
        if Timer.Background then Timer.Background:SetAlpha(0) end
        if Timer.Border then Timer.Border:SetAlpha(0) end

        if Timer.Fill then
            Timer.Fill:SetTexture(LSM:Fetch("statusbar", "Quazii") or "Interface\\TargetingFrame\\UI-StatusBar")
            Timer.Fill:SetVertexColor(borderColor[1], borderColor[2], borderColor[3], 1)
        end

        -- Add timer background
        if not Timer.quiBg then
            Timer.quiBg = Timer:CreateTexture(nil, "BACKGROUND")
            Timer.quiBg:SetAllPoints()
            Timer.quiBg:SetColorTexture(0, 0, 0, 0.5)
        end
    end

    -- Style the dropdown if it exists
    local Dropdown = HistoryFrame.EncounterDropdown
    if Dropdown then
        -- Basic dropdown styling
        if Dropdown.NineSlice then Dropdown.NineSlice:SetAlpha(0) end
    end

    -- Style the close button
    if HistoryFrame.ClosePanelButton then
        local closeBtn = HistoryFrame.ClosePanelButton
        -- Simplified close button styling
        if closeBtn:GetNormalTexture() then
            closeBtn:GetNormalTexture():SetVertexColor(0.8, 0.8, 0.8)
        end
    end

    -- Style the resize button
    local ResizeButton = HistoryFrame.ResizeButton
    if ResizeButton then
        if ResizeButton.NineSlice then ResizeButton.NineSlice:SetAlpha(0) end

        if not ResizeButton.quiBackdrop then
            ResizeButton.quiBackdrop = CreateFrame("Frame", nil, ResizeButton, "BackdropTemplate")
            ResizeButton.quiBackdrop:SetAllPoints()
            ResizeButton.quiBackdrop:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            ResizeButton.quiBackdrop:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], 0.8)
            ResizeButton.quiBackdrop:SetBackdropBorderColor(unpack(borderColor))

            -- Add resize text
            ResizeButton.quiText = ResizeButton:CreateFontString(nil, "OVERLAY")
            ResizeButton.quiText:SetFont(LSM:Fetch("font", GetGeneralFont()), 12, "OUTLINE")
            ResizeButton.quiText:SetPoint("CENTER")
            ResizeButton.quiText:SetText("v v v")
            ResizeButton.quiText:SetTextColor(unpack(textColor))
        end
    end

    -- Hook ScrollBox updates to skin dynamically created elements
    if HistoryFrame.ScrollBox then
        hooksecurefunc(HistoryFrame.ScrollBox, "Update", HandleLootHistoryScrollUpdate)
        -- Skin existing elements
        HandleLootHistoryScrollUpdate(HistoryFrame.ScrollBox)
    end

    -- Hook Show to re-apply theme each time frame is shown
    hooksecurefunc(HistoryFrame, "Show", function()
        Loot:ApplyLootHistoryTheme()
    end)

    lootHistorySkinned = true
end

-- Apply theme to loot history frame
function Loot:ApplyLootHistoryTheme()
    local HistoryFrame = _G.GroupLootHistoryFrame
    if not HistoryFrame then return end

    local db = GetDB()
    local enabled = db.lootResults and db.lootResults.enabled ~= false

    -- If disabled, restore Blizzard look
    if not enabled then
        if HistoryFrame.quiBackdrop then
            HistoryFrame.quiBackdrop:Hide()
        end
        if HistoryFrame.NineSlice then
            HistoryFrame.NineSlice:SetAlpha(1)
        end
        if HistoryFrame.Bg then
            HistoryFrame.Bg:SetAlpha(1)
        end
        if HistoryFrame.Timer then
            if HistoryFrame.Timer.Background then HistoryFrame.Timer.Background:SetAlpha(1) end
            if HistoryFrame.Timer.Border then HistoryFrame.Timer.Border:SetAlpha(1) end
            if HistoryFrame.Timer.quiBg then HistoryFrame.Timer.quiBg:Hide() end
        end
        if HistoryFrame.ResizeButton and HistoryFrame.ResizeButton.quiBackdrop then
            HistoryFrame.ResizeButton.quiBackdrop:Hide()
            if HistoryFrame.ResizeButton.NineSlice then
                HistoryFrame.ResizeButton.NineSlice:SetAlpha(1)
            end
            if HistoryFrame.ResizeButton.quiText then
                HistoryFrame.ResizeButton.quiText:Hide()
            end
        end
        return
    end

    -- Enabled - apply QUI skin
    if not HistoryFrame.quiBackdrop then return end

    local bgColor, borderColor, textColor = GetThemeColors()

    -- Show our backdrop, hide Blizzard's
    HistoryFrame.quiBackdrop:Show()
    if HistoryFrame.NineSlice then HistoryFrame.NineSlice:SetAlpha(0) end
    if HistoryFrame.Bg then HistoryFrame.Bg:SetAlpha(0) end

    HistoryFrame.quiBackdrop:SetBackdropColor(unpack(bgColor))
    HistoryFrame.quiBackdrop:SetBackdropBorderColor(unpack(borderColor))

    if HistoryFrame.Timer then
        if HistoryFrame.Timer.Background then HistoryFrame.Timer.Background:SetAlpha(0) end
        if HistoryFrame.Timer.Border then HistoryFrame.Timer.Border:SetAlpha(0) end
        if HistoryFrame.Timer.quiBg then HistoryFrame.Timer.quiBg:Show() end
        if HistoryFrame.Timer.Fill then
            HistoryFrame.Timer.Fill:SetVertexColor(borderColor[1], borderColor[2], borderColor[3], 1)
        end
    end

    if HistoryFrame.ResizeButton and HistoryFrame.ResizeButton.quiBackdrop then
        HistoryFrame.ResizeButton.quiBackdrop:Show()
        if HistoryFrame.ResizeButton.NineSlice then
            HistoryFrame.ResizeButton.NineSlice:SetAlpha(0)
        end
        HistoryFrame.ResizeButton.quiBackdrop:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], 0.8)
        HistoryFrame.ResizeButton.quiBackdrop:SetBackdropBorderColor(unpack(borderColor))
        if HistoryFrame.ResizeButton.quiText then
            HistoryFrame.ResizeButton.quiText:Show()
            HistoryFrame.ResizeButton.quiText:SetTextColor(unpack(textColor))
        end
    end
end

-- Legacy function name for backwards compatibility with options
function Loot:ApplyResultsTheme()
    self:ApplyLootHistoryTheme()
end

---=================================================================================
--- INITIALIZATION
---=================================================================================

local function DisableBlizzardLoot()
    local db = GetDB()

    -- Disable Blizzard Loot Frame
    if db.loot and db.loot.enabled then
        LootFrame:UnregisterAllEvents()
        LootFrame:Hide()
    end

    -- Disable Blizzard Roll Frames
    if db.lootRoll and db.lootRoll.enabled then
        -- Hide the container
        if GroupLootContainer then
            GroupLootContainer:UnregisterAllEvents()
            GroupLootContainer:Hide()
            -- Hook to keep it hidden when Blizzard tries to show frames
            if not GroupLootContainer._quiHooked then
                hooksecurefunc(GroupLootContainer, "Show", function(self)
                    self:Hide()
                end)
                GroupLootContainer._quiHooked = true
            end
        end

        -- Hide individual roll frames as they're created
        local numRollFrames = NUM_GROUP_LOOT_FRAMES or 4  -- Default to 4 if not defined
        for i = 1, numRollFrames do
            local frame = _G["GroupLootFrame"..i]
            if frame then
                frame:UnregisterAllEvents()
                frame:Hide()
                if not frame._quiHooked then
                    hooksecurefunc(frame, "Show", function(self)
                        self:Hide()
                    end)
                    frame._quiHooked = true
                end
            end
        end
    end
end

local function EnableBlizzardLoot()
    -- Re-enable Blizzard Loot Frame
    LootFrame:RegisterEvent("LOOT_OPENED")
    LootFrame:RegisterEvent("LOOT_SLOT_CLEARED")
    LootFrame:RegisterEvent("LOOT_SLOT_CHANGED")
    LootFrame:RegisterEvent("LOOT_CLOSED")

    -- Re-enable Blizzard Roll Frames
    UIParent:RegisterEvent("START_LOOT_ROLL")
    UIParent:RegisterEvent("CANCEL_LOOT_ROLL")
    if GroupLootContainer then
        GroupLootContainer:SetAlpha(1)
    end
end

function Loot:Initialize()
    local db = GetDB()

    -- Create frames
    if not lootFrame then
        lootFrame = CreateLootWindow()
    end

    if not rollAnchor then
        rollAnchor = CreateRollAnchor()
    end

    -- Position roll anchor from saved settings
    if db.lootRoll and db.lootRoll.position and db.lootRoll.position.point then
        rollAnchor:ClearAllPoints()
        rollAnchor:SetPoint(db.lootRoll.position.point, UIParent,
                           db.lootRoll.position.relPoint or "TOP",
                           db.lootRoll.position.x or 0,
                           db.lootRoll.position.y or -200)
    end

    -- Disable Blizzard frames if enabled
    DisableBlizzardLoot()

    -- Skin Blizzard's GroupLootHistoryFrame (shows roll results)
    if db.lootResults and db.lootResults.enabled ~= false then
        -- GroupLootHistoryFrame may not exist until first loot roll
        -- Check periodically until it exists, then skin it
        local function TrySkinLootHistory()
            if GroupLootHistoryFrame and not lootHistorySkinned then
                SkinGroupLootHistoryFrame()
                -- Re-apply theme after skinning to ensure correct colors
                Loot:ApplyLootHistoryTheme()
                return true
            end
            return false
        end

        -- Try immediately
        if not TrySkinLootHistory() then
            -- If frame doesn't exist yet, set up a repeating check
            local checkFrame = CreateFrame("Frame")
            checkFrame.elapsed = 0
            checkFrame:SetScript("OnUpdate", function(self, elapsed)
                self.elapsed = self.elapsed + elapsed
                if self.elapsed > 1 then  -- Check every 1 second
                    self.elapsed = 0
                    if TrySkinLootHistory() then
                        self:SetScript("OnUpdate", nil)  -- Stop checking once skinned
                    end
                end
            end)
        end
    end

    -- Event handling
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("LOOT_READY")
    eventFrame:RegisterEvent("LOOT_OPENED")
    eventFrame:RegisterEvent("LOOT_SLOT_CLEARED")
    eventFrame:RegisterEvent("LOOT_CLOSED")
    eventFrame:RegisterEvent("START_LOOT_ROLL")
    eventFrame:RegisterEvent("CANCEL_LOOT_ROLL")

    eventFrame:SetScript("OnEvent", function(self, event, ...)
        local db = GetDB()

        if event == "LOOT_READY" or event == "LOOT_OPENED" then
            if db.loot and db.loot.enabled then
                OnLootOpened(...)
            end
        elseif event == "LOOT_SLOT_CLEARED" then
            if db.loot and db.loot.enabled then
                OnLootSlotCleared(...)
            end
        elseif event == "LOOT_CLOSED" then
            if db.loot and db.loot.enabled then
                OnLootClosed()
            end
        elseif event == "START_LOOT_ROLL" then
            if db.lootRoll and db.lootRoll.enabled then
                StartRoll(...)
            end
        elseif event == "CANCEL_LOOT_ROLL" then
            if db.lootRoll and db.lootRoll.enabled then
                CancelRoll(...)
            end
        end
    end)

    self.eventFrame = eventFrame
end

function Loot:Refresh()
    local db = GetDB()

    -- Update loot frame position
    if lootFrame and db.loot and db.loot.position and db.loot.position.point then
        lootFrame:ClearAllPoints()
        lootFrame:SetPoint(db.loot.position.point, UIParent,
                          db.loot.position.relPoint or "CENTER",
                          db.loot.position.x or 0,
                          db.loot.position.y or 100)
    end

    -- Update roll anchor position
    if rollAnchor and db.lootRoll and db.lootRoll.position and db.lootRoll.position.point then
        rollAnchor:ClearAllPoints()
        rollAnchor:SetPoint(db.lootRoll.position.point, UIParent,
                           db.lootRoll.position.relPoint or "TOP",
                           db.lootRoll.position.x or 0,
                           db.lootRoll.position.y or -200)
    end

    -- Reposition active rolls
    RepositionAllRolls()

    -- Toggle Blizzard frames based on settings
    if db.loot and db.loot.enabled then
        LootFrame:UnregisterAllEvents()
        LootFrame:Hide()
    else
        EnableBlizzardLoot()
    end

    if db.lootRoll and db.lootRoll.enabled then
        UIParent:UnregisterEvent("START_LOOT_ROLL")
        UIParent:UnregisterEvent("CANCEL_LOOT_ROLL")
    else
        UIParent:RegisterEvent("START_LOOT_ROLL")
        UIParent:RegisterEvent("CANCEL_LOOT_ROLL")
    end
end

-- Apply theme colors to loot frame
function Loot:ApplyLootTheme()
    if not lootFrame then return end
    local bgColor, borderColor, textColor = GetThemeColors()

    lootFrame:SetBackdropColor(unpack(bgColor))
    lootFrame:SetBackdropBorderColor(unpack(borderColor))
    lootFrame.header:SetTextColor(unpack(textColor))

    -- Update slot highlight colors
    for i = 1, MAX_LOOT_SLOTS do
        local slot = lootFrame.slots[i]
        if slot then
            slot:GetHighlightTexture():SetVertexColor(borderColor[1], borderColor[2], borderColor[3], 0.2)
        end
    end
end

-- Apply theme colors to roll frames
function Loot:ApplyRollTheme()
    local bgColor, borderColor, textColor = GetThemeColors()

    for i = 1, MAX_ROLL_FRAMES do
        local frame = rollFramePool[i]
        if frame then
            frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], 0.95)
            frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 0.3)  -- Subtle border
            frame.timer:SetStatusBarColor(borderColor[1], borderColor[2], borderColor[3], 1)  -- Accent color
        end
    end
end

-- Refresh all loot/roll colors (called when user changes skin color pickers)
function Loot:RefreshColors()
    -- Apply to all components
    self:ApplyLootTheme()
    self:ApplyRollTheme()
    self:ApplyLootHistoryTheme()
end

-- Register global refresh function for RefreshAllSkinning()
_G.QUI_RefreshLootColors = function()
    if QUICore and QUICore.Loot then
        QUICore.Loot:RefreshColors()
    end
end

-- Preview state tracking
local lootPreviewActive = false
local rollPreviewActive = false

-- Show preview for loot window (stays until hidden)
function Loot:ShowLootPreview()
    if not lootFrame then
        lootFrame = CreateLootWindow()
    end

    local db = GetDB()

    -- Apply current theme
    self:ApplyLootTheme()

    -- Position
    if db.loot and db.loot.position and db.loot.position.point then
        lootFrame:ClearAllPoints()
        lootFrame:SetPoint(db.loot.position.point, UIParent,
                          db.loot.position.relPoint or "CENTER",
                          db.loot.position.x or 0,
                          db.loot.position.y or 100)
    else
        lootFrame:ClearAllPoints()
        lootFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    end

    -- Enable direct drag during preview (no shift required)
    lootFrame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    lootFrame._previewMode = true

    -- Show test items
    local testItems = {
        { texture = "Interface\\Icons\\INV_Misc_Gem_Diamond_02", name = "Test Epic Item", quality = 4 },
        { texture = "Interface\\Icons\\INV_Misc_Coin_02", name = "Gold Coin", quality = 1, count = 47 },
        { texture = "Interface\\Icons\\INV_Misc_Herb_Icethorn", name = "Test Herb", quality = 2, count = 5 },
    }

    for i, item in ipairs(testItems) do
        local slot = lootFrame.slots[i]
        slot.slotIndex = nil  -- Not real loot
        slot.icon:SetTexture(item.texture)
        slot.name:SetText(item.name)
        local r, g, b = GetItemQualityColor(item.quality)
        slot.iconBorder:SetBackdropBorderColor(r, g, b, 1)
        slot.name:SetTextColor(r, g, b)
        if item.count and item.count > 1 then
            slot.count:SetText(item.count)
            slot.count:Show()
        else
            slot.count:Hide()
        end
        slot.questIcon:Hide()
        slot.transmogMarker:Hide()
        slot:Show()
    end

    -- Hide unused slots
    for i = #testItems + 1, MAX_LOOT_SLOTS do
        lootFrame.slots[i]:Hide()
    end

    -- Resize
    local height = 40 + (#testItems * (SLOT_HEIGHT + SLOT_SPACING))
    lootFrame:SetHeight(height)
    lootFrame:Show()

    lootPreviewActive = true
end

-- Hide loot preview
function Loot:HideLootPreview()
    if lootFrame then
        lootFrame:Hide()
        -- Restore shift+drag for actual looting
        lootFrame:SetScript("OnDragStart", function(self)
            if IsShiftKeyDown() then
                self:StartMoving()
            end
        end)
        lootFrame._previewMode = false
    end
    lootPreviewActive = false
end

-- Check if loot preview is active
function Loot:IsLootPreviewActive()
    return lootPreviewActive
end

-- Preview test items (8 total to match MAX_ROLL_FRAMES)
local PREVIEW_ROLL_ITEMS = {
    { texture = "Interface\\Icons\\INV_Sword_39", name = "Blade of Eternal Night", quality = 4, timer = 0.85 },
    { texture = "Interface\\Icons\\INV_Helmet_25", name = "Crown of the Fallen King", quality = 4, timer = 0.7 },
    { texture = "Interface\\Icons\\INV_Chest_Chain_15", name = "Burnished Chestguard", quality = 3, timer = 0.55 },
    { texture = "Interface\\Icons\\INV_Boots_Plate_08", name = "Boots of Striding", quality = 3, timer = 0.4 },
    { texture = "Interface\\Icons\\INV_Gauntlets_29", name = "Gauntlets of the Ancients", quality = 4, timer = 0.3 },
    { texture = "Interface\\Icons\\INV_Belt_13", name = "Girdle of Fortitude", quality = 2, timer = 0.25 },
    { texture = "Interface\\Icons\\INV_Misc_Cape_18", name = "Cloak of Shadows", quality = 3, timer = 0.15 },
    { texture = "Interface\\Icons\\INV_Jewelry_Ring_36", name = "Band of Eternal Champions", quality = 4, timer = 0.1 },
}

-- Show preview for roll frame (stays until hidden)
function Loot:ShowRollPreview()
    if not rollAnchor then
        rollAnchor = CreateRollAnchor()
    end

    local db = GetDB()
    local growDirection = (db.lootRoll and db.lootRoll.growDirection) or "DOWN"
    local spacing = (db.lootRoll and db.lootRoll.spacing) or 4
    local maxFrames = (db.lootRoll and db.lootRoll.maxFrames) or 4

    -- Position anchor from saved settings
    if db.lootRoll and db.lootRoll.position and db.lootRoll.position.point then
        rollAnchor:ClearAllPoints()
        rollAnchor:SetPoint(db.lootRoll.position.point, UIParent,
                           db.lootRoll.position.relPoint or "TOP",
                           db.lootRoll.position.x or 0,
                           db.lootRoll.position.y or -200)
    end

    local bgColor, borderColor, textColor = GetThemeColors()

    -- Store current maxFrames for HideRollPreview
    self._previewMaxFrames = maxFrames

    -- Create preview frames up to maxFrames setting
    for i = 1, maxFrames do
        local item = PREVIEW_ROLL_ITEMS[i] or PREVIEW_ROLL_ITEMS[1]  -- Cycle through if needed
        -- Ensure frame exists in pool
        if not rollFramePool[i] then
            rollFramePool[i] = CreateRollFrame(i)
        end
        local frame = rollFramePool[i]

        -- Apply current theme (subtle border)
        frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], 0.95)
        frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 0.3)

        frame.rollID = nil  -- Not a real roll
        frame.icon:SetTexture(item.texture)
        frame.name:SetText(item.name)
        local r, g, b = GetItemQualityColor(item.quality)
        frame.iconBorder:SetBackdropBorderColor(r, g, b, 1)
        frame.name:SetTextColor(r, g, b)

        -- Quality background tint
        local tint = QUALITY_BG_TINTS[item.quality] or QUALITY_BG_TINTS[1]
        frame.qualityTint:SetColorTexture(tint[1], tint[2], tint[3], tint[4])

        -- Timer with accent color
        frame.timer:SetValue(item.timer)
        frame.timer:SetStatusBarColor(borderColor[1], borderColor[2], borderColor[3], 1)
        frame.timer:SetScript("OnUpdate", nil)

        -- Make first frame draggable during preview
        if i == 1 then
            frame:SetMovable(true)
            frame:EnableMouse(true)
            frame:RegisterForDrag("LeftButton")
            frame:SetScript("OnDragStart", function(self)
                self:StartMoving()
            end)
            frame:SetScript("OnDragStop", function(self)
                self:StopMovingOrSizing()
                -- Save position to rollAnchor position
                local point, _, relPoint, x, y = self:GetPoint()
                local db = GetDB()
                if db.lootRoll then
                    db.lootRoll.position = { point = point, relPoint = relPoint, x = x, y = y }
                end
                -- Update anchor to match
                if rollAnchor then
                    rollAnchor:ClearAllPoints()
                    rollAnchor:SetPoint(point, UIParent, relPoint, x, y + ROLL_FRAME_HEIGHT)
                end
                -- Reposition other frames relative to new anchor
                local previewCount = Loot._previewMaxFrames or 4
                for j = 2, previewCount do
                    if rollFramePool[j] then
                        rollFramePool[j]:ClearAllPoints()
                        if growDirection == "UP" then
                            rollFramePool[j]:SetPoint("BOTTOM", rollAnchor, "TOP", 0, ((j-1) * (ROLL_FRAME_HEIGHT + spacing)))
                        else
                            rollFramePool[j]:SetPoint("TOP", rollAnchor, "BOTTOM", 0, -((j-1) * (ROLL_FRAME_HEIGHT + spacing)))
                        end
                    end
                end
            end)
        end

        -- Position based on grow direction
        frame:ClearAllPoints()
        if growDirection == "UP" then
            frame:SetPoint("BOTTOM", rollAnchor, "TOP", 0, ((i-1) * (ROLL_FRAME_HEIGHT + spacing)))
        else
            frame:SetPoint("TOP", rollAnchor, "BOTTOM", 0, -((i-1) * (ROLL_FRAME_HEIGHT + spacing)))
        end
        frame:Show()
    end

    rollPreviewActive = true
end

-- Hide roll preview
function Loot:HideRollPreview()
    -- Hide all preview frames (up to MAX_ROLL_FRAMES since we could show that many)
    for i = 1, MAX_ROLL_FRAMES do
        if rollFramePool[i] then
            rollFramePool[i]:Hide()
            -- Remove drag handlers from first frame
            if i == 1 then
                rollFramePool[i]:SetMovable(false)
                rollFramePool[i]:RegisterForDrag()
                rollFramePool[i]:SetScript("OnDragStart", nil)
                rollFramePool[i]:SetScript("OnDragStop", nil)
            end
        end
    end
    self._previewMaxFrames = nil
    rollPreviewActive = false
end

-- Check if roll preview is active
function Loot:IsRollPreviewActive()
    return rollPreviewActive
end

---=================================================================================
--- EDIT MODE INTEGRATION
---=================================================================================

local editModeActive = false

-- Toggle movers (edit mode) for repositioning frames
function Loot:ToggleMovers()
    if editModeActive then
        self:DisableEditMode()
    else
        self:EnableEditMode()
    end
end
local EDIT_BORDER_COLOR = { 0.2, 0.8, 0.8, 1 }  -- Cyan/teal to match QUI style
local EDIT_BORDER_SIZE = 2

-- Create border highlight around a frame (matching QUI player frame style)
local function CreateEditModeBorder(frame)
    if frame.editBorder then return frame.editBorder end

    local border = {}

    -- Top border
    border.top = frame:CreateTexture(nil, "OVERLAY")
    border.top:SetColorTexture(unpack(EDIT_BORDER_COLOR))
    border.top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    border.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    border.top:SetHeight(EDIT_BORDER_SIZE)

    -- Bottom border
    border.bottom = frame:CreateTexture(nil, "OVERLAY")
    border.bottom:SetColorTexture(unpack(EDIT_BORDER_COLOR))
    border.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    border.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    border.bottom:SetHeight(EDIT_BORDER_SIZE)

    -- Left border
    border.left = frame:CreateTexture(nil, "OVERLAY")
    border.left:SetColorTexture(unpack(EDIT_BORDER_COLOR))
    border.left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    border.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    border.left:SetWidth(EDIT_BORDER_SIZE)

    -- Right border
    border.right = frame:CreateTexture(nil, "OVERLAY")
    border.right:SetColorTexture(unpack(EDIT_BORDER_COLOR))
    border.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    border.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    border.right:SetWidth(EDIT_BORDER_SIZE)

    frame.editBorder = border
    return border
end

local function ShowEditModeBorder(frame)
    if not frame.editBorder then
        CreateEditModeBorder(frame)
    end
    for _, tex in pairs(frame.editBorder) do
        tex:Show()
    end
end

local function HideEditModeBorder(frame)
    if frame.editBorder then
        for _, tex in pairs(frame.editBorder) do
            tex:Hide()
        end
    end
end

function Loot:EnableEditMode()
    if editModeActive then return end
    editModeActive = true

    -- Show loot preview with edit border
    self:ShowLootPreview()
    if lootFrame then
        -- Add edit mode border highlight
        ShowEditModeBorder(lootFrame)

        -- Add label
        if not lootFrame.editLabel then
            local label = lootFrame:CreateFontString(nil, "OVERLAY")
            label:SetFont(LSM:Fetch("font", GetGeneralFont()), 10, "OUTLINE")
            label:SetPoint("BOTTOM", lootFrame, "TOP", 0, 4)
            label:SetText("QUI Loot Window")
            label:SetTextColor(0.2, 0.8, 0.8)  -- Match border color
            lootFrame.editLabel = label
        end
        lootFrame.editLabel:Show()
    end

    -- Show roll preview with edit border
    self:ShowRollPreview()
    local rollFrame = rollFramePool[1]
    if rollFrame then
        ShowEditModeBorder(rollFrame)

        if not rollFrame.editLabel then
            local label = rollFrame:CreateFontString(nil, "OVERLAY")
            label:SetFont(LSM:Fetch("font", GetGeneralFont()), 10, "OUTLINE")
            label:SetPoint("BOTTOM", rollFrame, "TOP", 0, 4)
            label:SetText("QUI Roll Frame")
            label:SetTextColor(0.2, 0.8, 0.8)  -- Match border color
            rollFrame.editLabel = label
        end
        rollFrame.editLabel:Show()
    end
end

function Loot:DisableEditMode()
    if not editModeActive then return end
    editModeActive = false

    -- Hide borders and labels
    if lootFrame then
        HideEditModeBorder(lootFrame)
        if lootFrame.editLabel then lootFrame.editLabel:Hide() end
    end

    local rollFrame = rollFramePool[1]
    if rollFrame then
        HideEditModeBorder(rollFrame)
        if rollFrame.editLabel then rollFrame.editLabel:Hide() end
    end

    -- Hide previews
    self:HideLootPreview()
    self:HideRollPreview()
end

function Loot:IsEditModeActive()
    return editModeActive
end

-- Hook Blizzard's Edit Mode
function Loot:HookBlizzardEditMode()
    if not EditModeManagerFrame then return end
    if self._editModeHooked then return end
    self._editModeHooked = true

    -- Only hook ExitEditMode to auto-hide movers
    -- EnterEditMode intentionally NOT hooked - users toggle movers manually via Skinning options
    hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
        if InCombatLockdown() then return end
        self:DisableEditMode()
    end)
end

---=================================================================================
--- MODULE INITIALIZATION HOOK
---=================================================================================

-- Initialize when QUICore is enabled
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event)
    -- Defer initialization to let QUICore load first
    C_Timer.After(0.5, function()
        local db = GetDB()
        if db.loot or db.lootRoll then
            Loot:Initialize()
            -- Hook Edit Mode after initialization
            Loot:HookBlizzardEditMode()
        end
    end)
    self:UnregisterEvent("PLAYER_LOGIN")
end)
