--[[
    QUI Totem Bar — Owned Engine
    Creates addon-owned totem buttons instead of hooking Blizzard's TotemFrame.
    Steals events from TotemFrame to prevent it from updating, then drives
    our own icons via GetTotemInfo / GetTotemTimeLeft.
    Container + preview exist on all classes; event handling is Shaman-only.
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local LSM = ns.LSM

---------------------------------------------------------------------------
-- CLASS CHECK
---------------------------------------------------------------------------
local _, playerClass = UnitClass("player")
local IS_SHAMAN = (playerClass == "SHAMAN")

---------------------------------------------------------------------------
-- MODULE NAMESPACE
---------------------------------------------------------------------------
local TotemBar = {}
ns.QUI_TotemBar = TotemBar

local QUICore = ns.Addon
local Helpers = ns.Helpers

local MAX_SLOTS = MAX_TOTEMS or 4
local BASE_CROP = 0.08

---------------------------------------------------------------------------
-- DATABASE ACCESS
---------------------------------------------------------------------------
local GetDB = Helpers.CreateDBGetter("totemBar")

---------------------------------------------------------------------------
-- FONT HELPERS
---------------------------------------------------------------------------
local GetGeneralFont = Helpers.GetGeneralFont
local GetGeneralFontOutline = Helpers.GetGeneralFontOutline

---------------------------------------------------------------------------
-- EVENTS TO STEAL FROM BLIZZARD'S TotemFrame
---------------------------------------------------------------------------
local STOLEN_EVENTS = {
    "PLAYER_TOTEM_UPDATE",
    "PLAYER_ENTERING_WORLD",
    "UPDATE_SHAPESHIFT_FORM",
    "PLAYER_TALENT_UPDATE",
}

---------------------------------------------------------------------------
-- GROW DIRECTION HELPERS
---------------------------------------------------------------------------
local function GrowAnchor(growDir)
    if growDir == "RIGHT" then return "LEFT"
    elseif growDir == "LEFT" then return "RIGHT"
    elseif growDir == "DOWN" then return "TOP"
    elseif growDir == "UP" then return "BOTTOM"
    end
    return "LEFT"
end

local function GetAnchorPosition(frame, anchor)
    local x, y = frame:GetCenter()
    if anchor == "LEFT" then
        x = frame:GetLeft()
    elseif anchor == "RIGHT" then
        x = frame:GetRight()
    elseif anchor == "TOP" then
        y = frame:GetTop()
    elseif anchor == "BOTTOM" then
        y = frame:GetBottom()
    end
    return x, y
end

---------------------------------------------------------------------------
-- DURATION FORMATTING
---------------------------------------------------------------------------
local function FormatDuration(seconds)
    if seconds >= 60 then
        return string.format("%dm", math.floor(seconds / 60))
    elseif seconds >= 10 then
        return string.format("%d", math.floor(seconds))
    elseif seconds > 0 then
        return string.format("%.1f", seconds)
    end
    return ""
end

---------------------------------------------------------------------------
-- TOTEM SLOT PRIORITIES
---------------------------------------------------------------------------
local function GetSlotPriorities()
    if SHAMAN_TOTEM_PRIORITIES then
        return SHAMAN_TOTEM_PRIORITIES
    elseif STANDARD_TOTEM_PRIORITIES then
        return STANDARD_TOTEM_PRIORITIES
    end
    return {1, 2, 3, 4}
end

---------------------------------------------------------------------------
-- CONTAINER + BUTTON CREATION
---------------------------------------------------------------------------
local container = CreateFrame("Frame", "QUI_TotemBar", UIParent)
container:SetFrameStrata("MEDIUM")
container:SetSize(1, 1)
container:SetMovable(true)
container:EnableMouse(true)
container:RegisterForDrag("LeftButton")
container:SetClampedToScreen(true)
container:Hide()

TotemBar.container = container
TotemBar.buttons = {}
TotemBar.ticker = nil
TotemBar.enabled = false

-- Create one button per totem slot
for i = 1, MAX_SLOTS do
    local btn = CreateFrame("Button", "QUI_TotemBarButton" .. i, container)
    btn:SetSize(36, 36)
    btn:RegisterForClicks("RightButtonUp")
    btn:Hide()

    -- Icon texture
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()

    -- Cooldown frame
    btn.cooldown = CreateFrame("Cooldown", "QUI_TotemBarCD" .. i, btn, "CooldownFrameTemplate")
    btn.cooldown:SetAllPoints()
    btn.cooldown:SetDrawEdge(false)

    -- Border (behind icon)
    btn.border = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
    btn.border:SetColorTexture(0, 0, 0, 1)

    -- Duration text
    btn.duration = btn:CreateFontString(nil, "OVERLAY")

    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        if self.slot then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetTotem(self.slot)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Right-click dismiss
    btn:SetScript("OnClick", function(self, button)
        if button == "RightButton" and self.slot then
            DestroyTotem(self.slot)
        end
    end)

    btn.slot = nil
    TotemBar.buttons[i] = btn
end

---------------------------------------------------------------------------
-- STYLE A SINGLE BUTTON
---------------------------------------------------------------------------
local function StyleButton(btn)
    local db = GetDB()
    if not db or not btn then return end

    local size = db.iconSize or 36
    btn:SetSize(size, size)

    -- Icon texcoord crop + zoom
    local zoom = db.zoom or 0
    local left = BASE_CROP + zoom
    local right = 1 - BASE_CROP - zoom
    btn.icon:SetTexCoord(left, right, left, right)

    -- Cooldown swipe
    local cd = btn.cooldown
    pcall(function()
        cd:SetSwipeTexture("Interface\\Buttons\\WHITE8x8")
        cd:SetUseCircularEdge(false)
        local lowTC = { x = 0, y = 0 }
        local highTC = { x = 1, y = 1 }
        cd:SetTexCoordRange(lowTC, highTC)
    end)

    if db.showSwipe ~= false then
        local swipeColor = db.swipeColor or {0, 0, 0, 0.6}
        pcall(cd.SetSwipeColor, cd, swipeColor[1], swipeColor[2], swipeColor[3], swipeColor[4])
        pcall(cd.SetDrawSwipe, cd, true)
    else
        pcall(cd.SetDrawSwipe, cd, false)
    end

    -- Border
    local bs = db.borderSize or 2
    if bs > 0 then
        local bpx = (QUICore and QUICore.Pixels) and QUICore:Pixels(bs, btn) or bs
        btn.border:Show()
        btn.border:ClearAllPoints()
        btn.border:SetPoint("TOPLEFT", -bpx, bpx)
        btn.border:SetPoint("BOTTOMRIGHT", bpx, -bpx)
    else
        btn.border:Hide()
    end

    -- Duration text
    btn.duration:SetFont(GetGeneralFont(), db.durationSize or 13, GetGeneralFontOutline())
    local dColor = db.durationColor or {1, 1, 1, 1}
    btn.duration:SetTextColor(dColor[1], dColor[2], dColor[3], dColor[4] or 1)
    btn.duration:ClearAllPoints()
    btn.duration:SetPoint(
        db.durationAnchor or "CENTER",
        btn,
        db.durationAnchor or "CENTER",
        db.durationOffsetX or 0,
        db.durationOffsetY or 0
    )
    if db.hideDurationText then
        btn.duration:Hide()
    else
        btn.duration:Show()
    end
end

---------------------------------------------------------------------------
-- LAYOUT VISIBLE BUTTONS
---------------------------------------------------------------------------
local function LayoutButtons()
    local db = GetDB()
    if not db then return end

    local growDir = db.growDirection or "RIGHT"
    local spacing = db.spacing or 4
    local iconSize = db.iconSize or 36

    local visibleCount = 0
    for i = 1, MAX_SLOTS do
        local btn = TotemBar.buttons[i]
        if btn:IsShown() then
            visibleCount = visibleCount + 1
            btn:ClearAllPoints()
            local offset = (visibleCount - 1) * (iconSize + spacing)
            if growDir == "RIGHT" then
                btn:SetPoint("LEFT", container, "LEFT", offset, 0)
            elseif growDir == "LEFT" then
                btn:SetPoint("RIGHT", container, "RIGHT", -offset, 0)
            elseif growDir == "DOWN" then
                btn:SetPoint("TOP", container, "TOP", 0, -offset)
            elseif growDir == "UP" then
                btn:SetPoint("BOTTOM", container, "BOTTOM", 0, offset)
            end
        end
    end

    -- Resize container to fit
    if visibleCount > 0 then
        if growDir == "RIGHT" or growDir == "LEFT" then
            container:SetSize(visibleCount * iconSize + (visibleCount - 1) * spacing, iconSize)
        else
            container:SetSize(iconSize, visibleCount * iconSize + (visibleCount - 1) * spacing)
        end
    else
        container:SetSize(1, 1)
    end
end

---------------------------------------------------------------------------
-- UPDATE ALL TOTEM SLOTS (Shaman only)
---------------------------------------------------------------------------
local function UpdateTotems()
    if not IS_SHAMAN then return end
    if TotemBar.previewing then return end
    local db = GetDB()
    if not db or not db.enabled then return end

    local priorities = GetSlotPriorities()
    local hasActive = false

    for displayIndex = 1, MAX_SLOTS do
        local slot = priorities[displayIndex] or displayIndex
        local btn = TotemBar.buttons[displayIndex]
        btn.slot = slot

        local haveTotem, name, startTime, duration, icon = GetTotemInfo(slot)
        if haveTotem and icon and icon ~= 0 and duration > 0 then
            btn.icon:SetTexture(icon)
            -- Pass secret values directly to C-side SetCooldown
            pcall(btn.cooldown.SetCooldown, btn.cooldown, startTime, duration)
            StyleButton(btn)
            btn:Show()
            hasActive = true
        else
            btn:Hide()
        end
    end

    LayoutButtons()

    -- Blizzard normally manages visibility, but ensure active totems are not
    -- left hidden after combat-safe deferred updates.
    if hasActive and not tf:IsShown() then
        tf:Show()
    end

    -- Manage duration ticker
    if hasActive then
        if not TotemBar.ticker then
            TotemBar.ticker = C_Timer.NewTicker(0.5, function()
                local tdb = GetDB()
                if not tdb or tdb.hideDurationText then return end
                for j = 1, MAX_SLOTS do
                    local b = TotemBar.buttons[j]
                    if b:IsShown() and b.slot and b.duration then
                        local ok, remaining = pcall(GetTotemTimeLeft, b.slot)
                        if ok and remaining and remaining > 0 then
                            b.duration:SetText(FormatDuration(remaining))
                        else
                            b.duration:SetText("")
                        end
                    end
                end
            end)
        end
    else
        if TotemBar.ticker then
            TotemBar.ticker:Cancel()
            TotemBar.ticker = nil
        end
    end
end

---------------------------------------------------------------------------
-- POSITIONING
---------------------------------------------------------------------------
local function PositionContainer()
    if InCombatLockdown() then return end

    -- Skip if anchoring engine manages this frame
    if _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("totemBar") then return end

    local db = GetDB()
    if not db then return end

    container:ClearAllPoints()
    local anchor = GrowAnchor(db.growDirection or "RIGHT")
    local offsetX = db.offsetX or 0
    local offsetY = db.offsetY or -200
    container:SetPoint(anchor, UIParent, "CENTER", offsetX, offsetY)
end

---------------------------------------------------------------------------
-- ENABLE / DISABLE — EVENT STEALING (Shaman only)
---------------------------------------------------------------------------
local function StealEvents()
    if not IS_SHAMAN then return end
    local tf = TotemFrame
    if not tf then return end
    for _, event in ipairs(STOLEN_EVENTS) do
        pcall(tf.UnregisterEvent, tf, event)
    end
    tf:Hide()
end

local function RestoreEvents()
    if not IS_SHAMAN then return end
    local tf = TotemFrame
    if not tf then return end
    for _, event in ipairs(STOLEN_EVENTS) do
        pcall(tf.RegisterEvent, tf, event)
    end
    tf:Show()
    -- Trigger Blizzard's own update so it catches up
    if tf.Update then
        pcall(tf.Update, tf)
    end
end

local function Enable()
    if TotemBar.enabled then return end
    TotemBar.enabled = true

    StealEvents()
    PositionContainer()
    container:Show()

    -- Register our own event handler (Shaman only)
    if IS_SHAMAN then
        container:RegisterEvent("PLAYER_TOTEM_UPDATE")
    end
    UpdateTotems()
end

local function Disable()
    if not TotemBar.enabled then return end
    TotemBar.enabled = false

    container:UnregisterEvent("PLAYER_TOTEM_UPDATE")
    container:Hide()

    if TotemBar.ticker then
        TotemBar.ticker:Cancel()
        TotemBar.ticker = nil
    end

    RestoreEvents()
end

-- Event handler on our container
container:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_TOTEM_UPDATE" then
        UpdateTotems()
    end
end)

-- Drag handlers on the container
container:SetScript("OnDragStart", function(self)
    local db = GetDB()
    if db and not db.locked then
        self:StartMoving()
    end
end)

container:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local db = GetDB()
    if not db then return end

    local anchor = GrowAnchor(db.growDirection or "RIGHT")
    local anchorX, anchorY = GetAnchorPosition(self, anchor)
    local screenX, screenY = UIParent:GetCenter()
    if anchorX and anchorY and screenX and screenY then
        if QUICore and QUICore.PixelRound then
            db.offsetX = QUICore:PixelRound(anchorX - screenX)
            db.offsetY = QUICore:PixelRound(anchorY - screenY)
        else
            db.offsetX = math.floor(anchorX - screenX + 0.5)
            db.offsetY = math.floor(anchorY - screenY + 0.5)
        end
    end
    PositionContainer()
end)

---------------------------------------------------------------------------
-- PUBLIC API
---------------------------------------------------------------------------
function TotemBar:Refresh()
    local db = GetDB()
    if not db or not db.enabled then
        Disable()
        return
    end

    Enable()
    PositionContainer()
    UpdateTotems()
end

function TotemBar:Hide()
    Disable()
end

---------------------------------------------------------------------------
-- PREVIEW (mock totems shown on the container's own buttons)
---------------------------------------------------------------------------
local MOCK_TOTEM_ICONS = {
    136098, -- Healing Stream Totem
    136013, -- Capacitor Totem
    136108, -- Tremor Totem
}
local MOCK_DURATIONS = {"42", "1:15", "8.2"}

TotemBar.previewing = false

local function ShowMockTotems()
    local db = GetDB()
    if not db then return end

    for i = 1, MAX_SLOTS do
        local btn = TotemBar.buttons[i]
        btn.slot = i
        if i <= #MOCK_TOTEM_ICONS then
            btn.icon:SetTexture(MOCK_TOTEM_ICONS[i])
            btn.cooldown:Hide()
            StyleButton(btn)
            if not db.hideDurationText then
                btn.duration:SetText(MOCK_DURATIONS[i] or "")
                btn.duration:Show()
            end
            btn:Show()
        else
            btn:Hide()
        end
    end

    LayoutButtons()
end

local function ClearMockTotems()
    for i = 1, MAX_SLOTS do
        TotemBar.buttons[i]:Hide()
    end
end

function TotemBar:ShowPreview()
    self.previewing = true
    -- Ensure container is visible and positioned even if disabled
    PositionContainer()
    container:Show()
    ShowMockTotems()
end

function TotemBar:HidePreview()
    if not self.previewing then return end
    self.previewing = false
    ClearMockTotems()
    -- Restore real state
    if self.enabled then
        UpdateTotems()
    else
        container:Hide()
    end
end

function TotemBar:IsPreviewShown()
    return self.previewing
end

---------------------------------------------------------------------------
-- GLOBAL CALLBACKS (for options / layout mode)
---------------------------------------------------------------------------
_G.QUI_RefreshTotemBar = function()
    TotemBar:Refresh()
    if TotemBar:IsPreviewShown() then
        ShowMockTotems()
    end
end

_G.QUI_ShowTotemBarPreview = function()
    TotemBar:ShowPreview()
end


_G.QUI_HideTotemBarPreview = function()
    TotemBar:HidePreview()
end

if ns.Registry then
    ns.Registry:Register("totemBar", {
        refresh = _G.QUI_RefreshTotemBar,
        priority = 20,
        group = "frames",
        importCategories = { "actionBars" },
    })
end

---------------------------------------------------------------------------
-- INITIALIZATION (Shaman only — non-shamans still get the container for
-- layout mode preview but never steal events or register for updates)
---------------------------------------------------------------------------
if IS_SHAMAN then
    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    initFrame:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_ENTERING_WORLD" then
            if QUICore then
                QUICore.TotemBar = TotemBar
            end

            C_Timer.After(0.6, function()
                TotemBar:Refresh()
            end)
        end
    end)
end
