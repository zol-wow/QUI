--[[
    QUI Totem Bar
    Shaman-only: hooks into Blizzard's TotemFrame and reskins it
    Provides custom styling while preserving native right-click dismiss
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local LSM = LibStub("LibSharedMedia-3.0")

---------------------------------------------------------------------------
-- CLASS GUARD: Shaman only
---------------------------------------------------------------------------
local _, playerClass = UnitClass("player")
if playerClass ~= "SHAMAN" then return end

---------------------------------------------------------------------------
-- MODULE NAMESPACE
---------------------------------------------------------------------------
local TotemBar = {}
TotemBar.hooked = false
TotemBar.ticker = nil

local QUICore
local BASE_CROP = 0.08

---------------------------------------------------------------------------
-- DATABASE ACCESS
---------------------------------------------------------------------------
-- DB accessor using shared helpers
local GetDB = Helpers.CreateDBGetter("totemBar")

---------------------------------------------------------------------------
-- FONT HELPERS (uses shared helpers)
---------------------------------------------------------------------------
local Helpers = ns.Helpers
local GetGeneralFont = Helpers.GetGeneralFont
local GetGeneralFontOutline = Helpers.GetGeneralFontOutline

---------------------------------------------------------------------------
-- GROW DIRECTION → ANCHOR POINT
-- The anchor is the origin edge the bar grows FROM
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
-- RESKIN A SINGLE TOTEM BUTTON
---------------------------------------------------------------------------
local function ReskinTotemButton(button)
    local db = GetDB()
    if not button or not db then return end

    local size = db.iconSize or 36

    -- Resize button
    button:SetSize(size, size)

    -- Hide Blizzard circular border
    if button.Border then
        button.Border:Hide()
    end

    -- Expand Icon container to fill button (remove circular constraint)
    if button.Icon then
        button.Icon:ClearAllPoints()
        button.Icon:SetAllPoints(button)
        button.Icon:SetSize(size, size)

        -- Remove circular mask
        if button.Icon.TextureMask then
            button.Icon.TextureMask:Hide()
            -- Remove the mask from the texture
            if button.Icon.Texture and button.Icon.Texture.RemoveMaskTexture then
                pcall(button.Icon.Texture.RemoveMaskTexture, button.Icon.Texture, button.Icon.TextureMask)
            end
        end

        -- Apply texcoord crop
        if button.Icon.Texture then
            local zoom = db.zoom or 0
            local left = BASE_CROP + zoom
            local right = 1 - BASE_CROP - zoom
            button.Icon.Texture:SetTexCoord(left, right, left, right)
            button.Icon.Texture:SetAllPoints(button.Icon)
        end

        -- Fix cooldown to fill square and remove circular swipe
        if button.Icon.Cooldown then
            button.Icon.Cooldown:ClearAllPoints()
            button.Icon.Cooldown:SetAllPoints(button.Icon)

            -- Reset swipe to square texture
            pcall(function()
                button.Icon.Cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8x8")
                button.Icon.Cooldown:SetUseCircularEdge(false)
                local lowTC = { x = 0, y = 0 }
                local highTC = { x = 1, y = 1 }
                button.Icon.Cooldown:SetTexCoordRange(lowTC, highTC)
            end)

            -- Swipe visibility and color
            if db.showSwipe ~= false then
                local swipeColor = db.swipeColor or {0, 0, 0, 0.6}
                pcall(button.Icon.Cooldown.SetSwipeColor, button.Icon.Cooldown,
                    swipeColor[1], swipeColor[2], swipeColor[3], swipeColor[4])
                pcall(button.Icon.Cooldown.SetDrawSwipe, button.Icon.Cooldown, true)
            else
                pcall(button.Icon.Cooldown.SetDrawSwipe, button.Icon.Cooldown, false)
            end
        end
    end

    -- Add our border (create once per button)
    if not button.quiBorder then
        button.quiBorder = button:CreateTexture(nil, "BACKGROUND", nil, -8)
        button.quiBorder:SetColorTexture(0, 0, 0, 1)
    end
    local bs = db.borderSize or 2
    if bs > 0 then
        button.quiBorder:Show()
        button.quiBorder:ClearAllPoints()
        button.quiBorder:SetPoint("TOPLEFT", -bs, bs)
        button.quiBorder:SetPoint("BOTTOMRIGHT", bs, -bs)
    else
        button.quiBorder:Hide()
    end

    -- Restyle duration text
    if button.Duration then
        button.Duration:SetFont(GetGeneralFont(), db.durationSize or 13, GetGeneralFontOutline())
        local dColor = db.durationColor or {1, 1, 1, 1}
        button.Duration:SetTextColor(dColor[1], dColor[2], dColor[3], dColor[4] or 1)
        button.Duration:ClearAllPoints()
        button.Duration:SetPoint(
            db.durationAnchor or "CENTER",
            button,
            db.durationAnchor or "CENTER",
            db.durationOffsetX or 0,
            db.durationOffsetY or 0
        )
        button.Duration:SetDrawLayer("OVERLAY")
        if db.hideDurationText then
            button.Duration:Hide()
        else
            button.Duration:Show()
        end
    end
end

---------------------------------------------------------------------------
-- CUSTOM LAYOUT (override Blizzard's HorizontalLayoutFrame)
---------------------------------------------------------------------------
local function LayoutTotemButtons()
    local tf = TotemFrame
    if not tf or not tf.totemPool then return end

    local db = GetDB()
    if not db then return end

    local growDir = db.growDirection or "RIGHT"
    local spacing = db.spacing or 4
    local iconSize = db.iconSize or 36

    -- Collect active buttons sorted by layoutIndex
    local activeButtons = {}
    for button in tf.totemPool:EnumerateActive() do
        table.insert(activeButtons, button)
    end
    table.sort(activeButtons, function(a, b)
        return (a.layoutIndex or 0) < (b.layoutIndex or 0)
    end)

    -- Position each active button
    for i, button in ipairs(activeButtons) do
        button:ClearAllPoints()
        local offset = (i - 1) * (iconSize + spacing)
        if growDir == "RIGHT" then
            button:SetPoint("LEFT", tf, "LEFT", offset, 0)
        elseif growDir == "LEFT" then
            button:SetPoint("RIGHT", tf, "RIGHT", -offset, 0)
        elseif growDir == "DOWN" then
            button:SetPoint("TOP", tf, "TOP", 0, -offset)
        elseif growDir == "UP" then
            button:SetPoint("BOTTOM", tf, "BOTTOM", 0, offset)
        end
    end

    -- Resize TotemFrame to fit
    local count = #activeButtons
    if count > 0 then
        if growDir == "RIGHT" or growDir == "LEFT" then
            tf:SetSize(count * iconSize + (count - 1) * spacing, iconSize)
        else
            tf:SetSize(iconSize, count * iconSize + (count - 1) * spacing)
        end
    else
        tf:SetSize(1, 1)
    end
end

---------------------------------------------------------------------------
-- DURATION TEXT TICKER (custom format, avoids hooking OnUpdate)
---------------------------------------------------------------------------
local function UpdateDurationTexts()
    local tf = TotemFrame
    if not tf or not tf.totemPool then return end

    local db = GetDB()
    if not db or db.hideDurationText then return end

    for button in tf.totemPool:EnumerateActive() do
        if button.slot and button.Duration then
            local ok, text = pcall(function()
                local remaining = GetTotemTimeLeft(button.slot)
                if remaining > 0 then
                    return FormatDuration(remaining)
                end
                return nil
            end)
            if ok and text then
                button.Duration:SetText(text)
                button.Duration:Show()
            else
                button.Duration:SetText("")
            end
        end
    end
end

---------------------------------------------------------------------------
-- POST-HOOK: Runs after Blizzard's TotemFrame:Update()
---------------------------------------------------------------------------
local function PostUpdate()
    local db = GetDB()
    if not db or not db.enabled then return end

    local tf = TotemFrame
    if not tf or not tf.totemPool then return end

    -- Reskin all active buttons
    for button in tf.totemPool:EnumerateActive() do
        ReskinTotemButton(button)
    end

    -- Apply our custom layout
    LayoutTotemButtons()

    -- Manage ticker for duration updates
    local hasActive = false
    for _ in tf.totemPool:EnumerateActive() do
        hasActive = true
        break
    end

    if hasActive then
        if not TotemBar.ticker then
            TotemBar.ticker = C_Timer.NewTicker(0.1, UpdateDurationTexts)
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
local function PositionTotemFrame()
    local tf = TotemFrame
    if not tf then return end

    local db = GetDB()
    if not db then return end

    tf:ClearAllPoints()
    local anchor = GrowAnchor(db.growDirection or "RIGHT")
    local offsetX = db.offsetX or 0
    local offsetY = db.offsetY or -200
    tf:SetPoint(anchor, UIParent, "CENTER", offsetX, offsetY)
end

---------------------------------------------------------------------------
-- HOOK SETUP
---------------------------------------------------------------------------
local function HookTotemFrame()
    if TotemBar.hooked then return end
    local tf = TotemFrame
    if not tf then return end

    TotemBar.hooked = true

    -- Detach from PlayerFrame and reparent to UIParent
    tf:SetParent(UIParent)
    tf:SetFrameStrata("MEDIUM")

    -- Satisfy the managed frame system with a no-op layout parent
    -- (UIParent.lua Show/Hide hooks call self.layoutParent:MarkDirty())
    tf.layoutParent = {
        MarkDirty = function() end,
        MarkClean = function() end,
        AddManagedFrame = function() end,
        RemoveManagedFrame = function() end,
        Layout = function() end,
    }

    -- Position
    PositionTotemFrame()

    -- Make draggable
    tf:SetMovable(true)
    tf:EnableMouse(true)
    tf:RegisterForDrag("LeftButton")
    tf:SetClampedToScreen(true)

    tf:HookScript("OnDragStart", function(self)
        local db = GetDB()
        if db and not db.locked then
            self:StartMoving()
        end
    end)

    tf:HookScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local db = GetDB()
        if not db then return end

        local anchor = GrowAnchor(db.growDirection or "RIGHT")
        local anchorX, anchorY = GetAnchorPosition(self, anchor)
        local screenX, screenY = UIParent:GetCenter()
        if anchorX and anchorY and screenX and screenY then
            db.offsetX = math.floor(anchorX - screenX + 0.5)
            db.offsetY = math.floor(anchorY - screenY + 0.5)
        end
        PositionTotemFrame()
    end)

    -- Hook Update to reskin after each pool cycle
    hooksecurefunc(tf, "Update", PostUpdate)

    -- Hook Layout to override with our custom layout
    hooksecurefunc(tf, "Layout", function()
        local db = GetDB()
        if db and db.enabled then
            LayoutTotemButtons()
        end
    end)

    -- Override show/hide behavior based on our enabled setting
    hooksecurefunc(tf, "Show", function(self)
        local db = GetDB()
        if not db or not db.enabled then
            self:Hide()
        end
    end)
end

---------------------------------------------------------------------------
-- PUBLIC API
---------------------------------------------------------------------------
function TotemBar:Refresh()
    local db = GetDB()
    if not db or not db.enabled then
        if TotemFrame then
            -- Restore to default hidden behavior
            TotemFrame:Hide()
        end
        if self.ticker then
            self.ticker:Cancel()
            self.ticker = nil
        end
        return
    end

    if not self.hooked then
        HookTotemFrame()
    end

    if not TotemFrame then return end

    PositionTotemFrame()

    -- Trigger a full update to apply our styling
    if TotemFrame.Update then
        TotemFrame:Update()
    end
end

function TotemBar:Hide()
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
    if TotemFrame then
        TotemFrame:Hide()
    end
end

---------------------------------------------------------------------------
-- PREVIEW FRAME (mock totems for positioning in options)
---------------------------------------------------------------------------
local previewFrame = nil
local MOCK_TOTEM_ICONS = {
    136098, -- Healing Stream Totem
    136013, -- Capacitor Totem
    136108, -- Tremor Totem
}

local function CreatePreviewFrame()
    if previewFrame then return previewFrame end

    local frame = CreateFrame("Frame", "QUI_TotemBarPreview", UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetSize(1, 1)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)

    frame:SetScript("OnDragStart", function(self)
        local db = GetDB()
        if db then
            self:StartMoving()
        end
    end)

    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local db = GetDB()
        if not db then return end

        local anchor = GrowAnchor(db.growDirection or "RIGHT")
        local anchorX, anchorY = GetAnchorPosition(self, anchor)
        local screenX, screenY = UIParent:GetCenter()
        if anchorX and anchorY and screenX and screenY then
            db.offsetX = math.floor(anchorX - screenX + 0.5)
            db.offsetY = math.floor(anchorY - screenY + 0.5)
        end

        -- Reposition to snap to saved offset
        self:ClearAllPoints()
        self:SetPoint(anchor, UIParent, "CENTER", db.offsetX, db.offsetY)

        -- Also update the real totem frame position
        if TotemBar.hooked then
            PositionTotemFrame()
        end
    end)

    -- Create mock icon frames
    frame.icons = {}
    for i = 1, #MOCK_TOTEM_ICONS do
        local icon = CreateFrame("Frame", nil, frame)
        icon:SetSize(36, 36)

        icon.border = icon:CreateTexture(nil, "BACKGROUND", nil, -8)
        icon.border:SetColorTexture(0, 0, 0, 1)

        icon.tex = icon:CreateTexture(nil, "ARTWORK")
        icon.tex:SetTexture(MOCK_TOTEM_ICONS[i])

        icon.durationText = icon:CreateFontString(nil, "OVERLAY")
        icon.durationText:SetFont(GetGeneralFont(), 13, GetGeneralFontOutline())
        icon.durationText:SetPoint("CENTER")

        -- Forward drag to parent
        icon:EnableMouse(true)
        icon:RegisterForDrag("LeftButton")
        icon:SetScript("OnDragStart", function(self)
            self:GetParent():StartMoving()
        end)
        icon:SetScript("OnDragStop", function(self)
            local bar = self:GetParent()
            local handler = bar:GetScript("OnDragStop")
            if handler then handler(bar) end
        end)

        frame.icons[i] = icon
    end

    previewFrame = frame
    return frame
end

local function StylePreviewFrame()
    if not previewFrame then return end

    local db = GetDB()
    if not db then return end

    local size = db.iconSize or 36
    local spacing = db.spacing or 4
    local growDir = db.growDirection or "RIGHT"
    local bs = db.borderSize or 2
    local zoom = db.zoom or 0
    local left = BASE_CROP + zoom
    local right = 1 - BASE_CROP - zoom

    -- Mock durations
    local mockDurations = {"42", "1:15", "8.2"}

    for i, icon in ipairs(previewFrame.icons) do
        icon:SetSize(size, size)

        -- Border
        if bs > 0 then
            icon.border:Show()
            icon.border:ClearAllPoints()
            icon.border:SetPoint("TOPLEFT", -bs, bs)
            icon.border:SetPoint("BOTTOMRIGHT", bs, -bs)
        else
            icon.border:Hide()
        end

        -- Texcoord
        icon.tex:SetAllPoints()
        icon.tex:SetTexCoord(left, right, left, right)

        -- Duration text
        icon.durationText:SetFont(GetGeneralFont(), db.durationSize or 13, GetGeneralFontOutline())
        local dColor = db.durationColor or {1, 1, 1, 1}
        icon.durationText:SetTextColor(dColor[1], dColor[2], dColor[3], dColor[4] or 1)
        icon.durationText:ClearAllPoints()
        icon.durationText:SetPoint(
            db.durationAnchor or "CENTER",
            icon,
            db.durationAnchor or "CENTER",
            db.durationOffsetX or 0,
            db.durationOffsetY or 0
        )
        if db.hideDurationText then
            icon.durationText:Hide()
        else
            icon.durationText:SetText(mockDurations[i] or "")
            icon.durationText:Show()
        end

        -- Position
        icon:ClearAllPoints()
        local offset = (i - 1) * (size + spacing)
        if growDir == "RIGHT" then
            icon:SetPoint("LEFT", previewFrame, "LEFT", offset, 0)
        elseif growDir == "LEFT" then
            icon:SetPoint("RIGHT", previewFrame, "RIGHT", -offset, 0)
        elseif growDir == "DOWN" then
            icon:SetPoint("TOP", previewFrame, "TOP", 0, -offset)
        elseif growDir == "UP" then
            icon:SetPoint("BOTTOM", previewFrame, "BOTTOM", 0, offset)
        end

        icon:Show()
    end

    -- Resize frame to fit
    local count = #previewFrame.icons
    if growDir == "RIGHT" or growDir == "LEFT" then
        previewFrame:SetSize(count * size + (count - 1) * spacing, size)
    else
        previewFrame:SetSize(size, count * size + (count - 1) * spacing)
    end

    -- Position (anchor based on grow direction)
    local anchor = GrowAnchor(growDir)
    previewFrame:ClearAllPoints()
    previewFrame:SetPoint(anchor, UIParent, "CENTER", db.offsetX or 0, db.offsetY or -200)
end

function TotemBar:ShowPreview()
    CreatePreviewFrame()
    StylePreviewFrame()
    previewFrame:Show()
end

function TotemBar:HidePreview()
    if previewFrame then
        previewFrame:Hide()
    end
end

function TotemBar:IsPreviewShown()
    return previewFrame and previewFrame:IsShown()
end

-- Expose globally for refresh callbacks from options
_G.QUI_RefreshTotemBar = function()
    TotemBar:Refresh()
    -- Also update preview if visible
    if TotemBar:IsPreviewShown() then
        StylePreviewFrame()
    end
end

_G.QUI_ToggleTotemBarPreview = function()
    if TotemBar:IsPreviewShown() then
        TotemBar:HidePreview()
    else
        TotemBar:ShowPreview()
    end
end

_G.QUI_HideTotemBarPreview = function()
    TotemBar:HidePreview()
end

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        QUICore = QUI.QUICore
        if QUICore then
            QUICore.TotemBar = TotemBar
        end

        C_Timer.After(0.6, function()
            TotemBar:Refresh()
        end)
    end
end)
