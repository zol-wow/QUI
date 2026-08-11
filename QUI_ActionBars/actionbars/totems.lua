local ADDON_NAME, ns = ...
local QUI = QUI
local LSM = ns.LSM

local function CJKFont(fs, p, s, f)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fs, p, s, f)
    else
        fs:SetFont(p, s, f)
    end
end

local TotemBar = {}
ns.QUI_TotemBar = TotemBar

local QUICore = ns.Addon
local Helpers = ns.Helpers
local ApplyCooldownFromStart = Helpers.ApplyCooldownFromStart

local MAX_SLOTS = MAX_TOTEMS or 4
local BASE_CROP = 0.08

local pendingReconcile = false

local function SafeShowButton(btn)
    btn:SetAlpha(1)
    btn.active = true
end

local function SafeHideButton(btn)
    btn:SetAlpha(0)
    btn.active = false
end

local GetDB = Helpers.CreateDBGetter("totemBar")

local GetGeneralFont = Helpers.GetGeneralFont
local GetGeneralFontOutline = Helpers.GetGeneralFontOutline

local CreateFrame = CreateFrame
local UIParent = UIParent
local ipairs = ipairs
local pcall = pcall
local InCombatLockdown = InCombatLockdown
local UnitClass = UnitClass
local C_Timer = C_Timer
local math_floor = math.floor
local string_format = string.format

local STOLEN_EVENTS = {
    "PLAYER_TOTEM_UPDATE",
    "PLAYER_ENTERING_WORLD",
    "UPDATE_SHAPESHIFT_FORM",
    "PLAYER_TALENT_UPDATE",
}

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

local function FormatDuration(seconds)
    if seconds >= 60 then
        return string_format("%dm", math_floor(seconds / 60))
    elseif seconds >= 10 then
        return string_format("%d", math_floor(seconds))
    elseif seconds > 0 then
        return string_format("%.1f", seconds)
    end
    return ""
end

local function GetSlotPriorities()
    local _, class = UnitClass("player")
    -- @secret-policy: collapse-only — a restricted class token falls back to
    if Helpers.IsSecretValue(class) then class = nil end
    if class == "SHAMAN" and SHAMAN_TOTEM_PRIORITIES then
        return SHAMAN_TOTEM_PRIORITIES
    elseif STANDARD_TOTEM_PRIORITIES then
        return STANDARD_TOTEM_PRIORITIES
    end
    return {1, 2, 3, 4}
end

local function SetTotemDismissSlot(btn, slot)
    if not btn or not slot then return end
    if InCombatLockdown() then
        if btn._secureTotemSlot ~= slot then
            pendingReconcile = true
        end
        return
    end

    if btn._secureTotemSlot == slot then return end
    btn:SetAttribute("type2", "destroytotem")
    btn:SetAttribute("*type2", "destroytotem")
    btn:SetAttribute("totem-slot", slot)
    btn:SetAttribute("totem-slot2", slot)
    btn:SetAttribute("*totem-slot2", slot)
    btn._secureTotemSlot = slot
end

local container = CreateFrame("Frame", "QUI_TotemBar", UIParent)
container:SetFrameStrata("MEDIUM")
container:SetSize(1, 1)
container:SetMovable(true)
container:EnableMouse(false)
container:RegisterForDrag("LeftButton")
container:SetClampedToScreen(true)
container:SetAlpha(0)
container.visible = false

local function ShowContainer()
    container:SetAlpha(1)
    container.visible = true
    if InCombatLockdown() then
        pendingReconcile = true
        return
    end
    container:EnableMouse(true)
end

local function HideContainer()
    container:SetAlpha(0)
    container.visible = false
    if InCombatLockdown() then
        pendingReconcile = true
        return
    end
    container:EnableMouse(false)
end

TotemBar.container = container
TotemBar.buttons = {}
TotemBar.ticker = nil
TotemBar.enabled = false

for i = 1, MAX_SLOTS do
    local btn = CreateFrame("Button", "QUI_TotemBarButton" .. i, container, "SecureActionButtonTemplate")
    btn:SetSize(36, 36)
    btn:SetFrameLevel(container:GetFrameLevel() + i)
    btn:SetAlpha(0)
    btn:EnableMouse(true)
    btn:SetPassThroughButtons("LeftButton", "MiddleButton")
    btn.active = false
    btn:RegisterForClicks("RightButtonDown", "RightButtonUp")
    SetTotemDismissSlot(btn, i)

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()

    btn.cooldown = CreateFrame("Cooldown", "QUI_TotemBarCD" .. i, btn, "CooldownFrameTemplate")
    btn.cooldown:SetAllPoints()
    btn.cooldown:SetDrawEdge(false)

    btn.border = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
    btn.border:SetColorTexture(0, 0, 0, 1)

    btn.duration = btn:CreateFontString(nil, "OVERLAY")

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

    btn.slot = nil
    TotemBar.buttons[i] = btn
end

local function StyleButton(btn)
    local db = GetDB()
    if not db or not btn then return end

    local size = db.iconSize or 36
    if not InCombatLockdown() then
        btn:SetSize(size, size)
    end

    local zoom = db.zoom or 0
    local left = BASE_CROP + zoom
    local right = 1 - BASE_CROP - zoom
    btn.icon:SetTexCoord(left, right, left, right)

    local cd = btn.cooldown
    ns.SafeCall("best-effort-style", function()
        cd:SetSwipeTexture("Interface\\Buttons\\WHITE8x8")
        cd:SetUseCircularEdge(false)
        local lowTC = { x = 0, y = 0 }
        local highTC = { x = 1, y = 1 }
        cd:SetTexCoordRange(lowTC, highTC)
    end)

    if db.showSwipe ~= false then
        local swipeColor = db.swipeColor or {0, 0, 0, 0.6}
        ns.SafeCallMethod("best-effort-style", cd, "SetSwipeColor", swipeColor[1], swipeColor[2], swipeColor[3], swipeColor[4])
        ns.SafeCallMethod("best-effort-style", cd, "SetDrawSwipe", true)
    else
        ns.SafeCallMethod("best-effort-style", cd, "SetDrawSwipe", false)
    end

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

    CJKFont(btn.duration, GetGeneralFont(), db.durationSize or 13, GetGeneralFontOutline())
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

local function LayoutButtons()
    if InCombatLockdown() then
        pendingReconcile = true
        return
    end
    local db = GetDB()
    if not db then return end

    local growDir = db.growDirection or "RIGHT"
    local spacing = db.spacing or 4
    local iconSize = db.iconSize or 36

    local visibleCount = 0
    for i = 1, MAX_SLOTS do
        local btn = TotemBar.buttons[i]
        btn:SetSize(iconSize, iconSize)
        btn:ClearAllPoints()
        local offset
        if btn.active then
            visibleCount = visibleCount + 1
            offset = (visibleCount - 1) * (iconSize + spacing)
        else
            offset = (i - 1) * (iconSize + spacing)
        end
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

    if growDir == "RIGHT" or growDir == "LEFT" then
        container:SetSize(MAX_SLOTS * iconSize + (MAX_SLOTS - 1) * spacing, iconSize)
    else
        container:SetSize(iconSize, MAX_SLOTS * iconSize + (MAX_SLOTS - 1) * spacing)
    end
    local anchoring = ns.QUI_Anchoring
    if anchoring and anchoring.ApplyFrameAnchor and QUICore
       and QUICore.db and QUICore.db.profile and QUICore.db.profile.frameAnchoring then
        local settings = QUICore.db.profile.frameAnchoring.totemBar
        if settings then
            anchoring:ApplyFrameAnchor("totemBar", settings)
        end
    end
end

local function UpdateTotems()
    if TotemBar.previewing then return end
    local db = GetDB()
    if not db or not db.enabled then return end

    local priorities = GetSlotPriorities()
    local hasActive = false

    for displayIndex = 1, MAX_SLOTS do
        local slot = priorities[displayIndex] or displayIndex
        local btn = TotemBar.buttons[displayIndex]
        btn.slot = slot
        SetTotemDismissSlot(btn, slot)

        local haveTotem, name, startTime, duration, icon = GetTotemInfo(slot)
        local isActive = false
        if not InCombatLockdown() then
            local ok, val = pcall(function()
                -- @secret-safe: comparisons run INSIDE pcall — a secret value's throw is caught, ok=false falls through to inactive
                return haveTotem and icon and icon ~= 0 and duration and duration > 0
            end)
            isActive = ok and val
        else
            local tok, timeLeft = pcall(GetTotemTimeLeft, slot)
            if tok then
                if Helpers.IsSecretValue(timeLeft) then
                    isActive = true
                elseif timeLeft then
                    isActive = timeLeft > 0
                end
            end
        end

        if isActive then
            ns.SafeCallMethod("sink-forward", btn.icon, "SetTexture", icon)
            local cd = btn.cooldown
            local durObj = nil
            if GetTotemDuration then
                local dok, fetchedDurObj = ns.SafeCall("best-effort-style", GetTotemDuration, slot)
                if dok and fetchedDurObj then
                    durObj = fetchedDurObj
                end
            end
            if not ApplyCooldownFromStart(cd, durObj, startTime, duration, nil, nil) then
                cd:Clear()
            end
            StyleButton(btn)
            SafeShowButton(btn)
            hasActive = true
        else
            btn.cooldown:Clear()
            SafeHideButton(btn)
        end
    end

    LayoutButtons()

    if hasActive then
        if not container.visible then
            ShowContainer()
        end
    else
        if container.visible then
            HideContainer()
        end
    end

    if hasActive then
        if not TotemBar.ticker then
            TotemBar.ticker = C_Timer.NewTicker(0.5, function()
                local tdb = GetDB()
                if not tdb or tdb.hideDurationText then return end
                for j = 1, MAX_SLOTS do
                    local b = TotemBar.buttons[j]
                    if b.active and b.slot and b.duration then
                        local shown = false
                        if GetTotemDuration then
                            local dok, durObj = ns.SafeCall("best-effort-style", GetTotemDuration, b.slot)
                            if dok and durObj and durObj.GetRemainingDuration then
                                local rok, rem = pcall(durObj.GetRemainingDuration, durObj)
                                if rok and rem then
                                    local isSecret = Helpers.IsSecretValue(rem)
                                    if not isSecret and rem > 0 then
                                        b.duration:SetText(FormatDuration(rem))
                                    elseif isSecret then
                                        ns.SafeCallMethod("sink-forward", b.duration, "SetFormattedText", "%.0f", rem)
                                    else
                                        b.duration:SetText("")
                                    end
                                    shown = true
                                end
                            end
                        end
                        if not shown then
                            local ok, remaining = pcall(GetTotemTimeLeft, b.slot)
                            if ok then
                                if Helpers.IsSecretValue(remaining) then
                                    ns.SafeCallMethod("sink-forward", b.duration, "SetFormattedText", "%.0f", remaining)
                                elseif remaining and remaining > 0 then
                                    b.duration:SetText(FormatDuration(remaining))
                                else
                                    b.duration:SetText("")
                                end
                            else
                                b.duration:SetText("")
                            end
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

local function PositionContainer()
    if InCombatLockdown() then return end

    if _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("totemBar") then return end

    local db = GetDB()
    if not db then return end

    container:ClearAllPoints()
    local anchor = GrowAnchor(db.growDirection or "RIGHT")
    local offsetX = db.offsetX or 0
    local offsetY = db.offsetY or -200
    container:SetPoint(anchor, UIParent, "CENTER", offsetX, offsetY)
end

local function StealEvents()
    local tf = TotemFrame
    if not tf then return end
    for _, event in ipairs(STOLEN_EVENTS) do
        if event ~= "PLAYER_TOTEM_UPDATE" then
            ns.SafeCallMethod("defer-ooc", tf, "UnregisterEvent", event)
        end
    end
    tf:SetAlpha(0)
    if InCombatLockdown() then
        pendingReconcile = true
        return
    end
    tf:EnableMouse(false)
    if tf.totemButtons then
        for _, tbtn in ipairs(tf.totemButtons) do
            ns.SafeCallMethod("defer-ooc", tbtn, "EnableMouse", false)
        end
    end
end

local function RestoreEvents()
    local tf = TotemFrame
    if not tf then return end
    for _, event in ipairs(STOLEN_EVENTS) do
        ns.SafeCallMethod("defer-ooc", tf, "RegisterEvent", event)
    end
    tf:SetAlpha(1)
    if not InCombatLockdown() then
        tf:EnableMouse(true)
        if tf.totemButtons then
            for _, tbtn in ipairs(tf.totemButtons) do
                ns.SafeCallMethod("defer-ooc", tbtn, "EnableMouse", true)
            end
        end
        ns.SafeCallMethodIfPresent("defer-ooc", tf, "Update")
    else
        pendingReconcile = true
    end
    tf:Show()
end

local function Enable()
    if TotemBar.enabled then return end
    TotemBar.enabled = true

    StealEvents()
    PositionContainer()
    if not container:IsShown() then container:Show() end

    container:RegisterEvent("PLAYER_TOTEM_UPDATE")
    UpdateTotems()
end

local function Disable()
    if not TotemBar.enabled then return end
    TotemBar.enabled = false

    container:UnregisterEvent("PLAYER_TOTEM_UPDATE")
    HideContainer()

    if TotemBar.ticker then
        TotemBar.ticker:Cancel()
        TotemBar.ticker = nil
    end

    RestoreEvents()
end

container:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_TOTEM_UPDATE" then
        UpdateTotems()
    end
end)

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
            db.offsetX = math_floor(anchorX - screenX + 0.5)
            db.offsetY = math_floor(anchorY - screenY + 0.5)
        end
    end
    PositionContainer()
end)

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

local MOCK_TOTEM_ICONS = {
    136098,
    136013,
    136108,
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
            SafeShowButton(btn)
        else
            SafeHideButton(btn)
        end
    end

    LayoutButtons()
end

local function ClearMockTotems()
    for i = 1, MAX_SLOTS do
        SafeHideButton(TotemBar.buttons[i])
    end
end

function TotemBar:ShowPreview()
    self.previewing = true
    PositionContainer()
    if not container:IsShown() then container:Show() end
    ShowContainer()
    ShowMockTotems()
end

function TotemBar:HidePreview()
    if not self.previewing then return end
    self.previewing = false
    ClearMockTotems()
    if self.enabled then
        UpdateTotems()
    else
        HideContainer()
    end
end

function TotemBar:IsPreviewShown()
    return self.previewing
end

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

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
initFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if pendingReconcile and TotemBar.enabled then
            pendingReconcile = false
            UpdateTotems()
        end
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        if QUICore then
            QUICore.TotemBar = TotemBar
        end

        C_Timer.After(0.6, function()
            TotemBar:Refresh()
        end)
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        local db = GetDB()
        if db and db.enabled then
            TotemBar:Refresh()
        end
    end
end)
