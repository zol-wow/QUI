local _, ns = ...
local QUICore = ns.Addon
local Helpers = ns.Helpers
local UIKit = ns.UIKit
local LSM = ns.LSM

local max = math.max
local floor = math.floor

local InfoBar = {}
QUICore.InfoBar = InfoBar

local ZONES = { "left", "center", "right" }

local bar
local zoneFrames = {}
local fadeTicker

local function GetDB()
    local db = QUICore.db and QUICore.db.profile
    return db and db.infobar
end

local reflowPendingCombat = false
local applyPendingCombat = false

local reflowQueued = false
local function QueueReflow()
    if reflowQueued then return end
    reflowQueued = true
    C_Timer.After(0, function()
        reflowQueued = false
        InfoBar:ReflowAll()
    end)
end

local regenWatcher = CreateFrame("Frame")
regenWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
regenWatcher:SetScript("OnEvent", function()
    if applyPendingCombat then
        applyPendingCombat = false
        InfoBar:ApplyAll()
    end
    if reflowPendingCombat then
        reflowPendingCombat = false
        QueueReflow()
    end
end)

local function ApplyBackdrop()
    local db = GetDB()
    if not db then return end

    bar.bg:SetColorTexture(0, 0, 0, (db.bgOpacity or 85) / 100)
    if UIKit and UIKit.DisablePixelSnap then
        UIKit.DisablePixelSnap(bar.bg)
    end

    local borderSize = db.borderSize or 1
    local bR, bG, bB, bA = Helpers.GetSkinBorderColor(db, "")
    local edge = bar.borderEdge
    edge:SetColorTexture(bR, bG, bB, bA)
    if UIKit and UIKit.DisablePixelSnap then
        UIKit.DisablePixelSnap(edge)
    end
    edge:SetHeight(max(1, borderSize))
    edge:SetShown(borderSize > 0)
    edge:ClearAllPoints()
    if db.position == "BOTTOM" then
        edge:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 0)
        edge:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 0)
    else
        edge:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
        edge:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    end
end

local function ApplyPosition()
    local db = GetDB()
    if not db then return end
    bar:ClearAllPoints()
    if db.position == "BOTTOM" then
        bar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
        bar:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)
    else
        bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
        bar:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
    end
    bar:SetHeight(db.height or 22)
end

local function CreateBar()
    if bar then return end
    bar = CreateFrame("Frame", "QUI_InfoBar", UIParent)
    bar:SetFrameStrata("HIGH")

    bar:SetScript("OnSizeChanged", QueueReflow)

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()

    bar.borderEdge = bar:CreateTexture(nil, "BORDER")

    for _, key in ipairs(ZONES) do
        local zf = CreateFrame("Frame", "QUI_InfoBarZone_" .. key, bar)
        zf.slots = {}
        zoneFrames[key] = zf
    end

    if UIKit and UIKit.RegisterScaleRefresh then
        UIKit.RegisterScaleRefresh(bar, "infobarBackdrop", function()
            if GetDB() then ApplyBackdrop() end
        end)
    end

    if ns.FRAME_ANCHOR_INFO and not ns.FRAME_ANCHOR_INFO.infoBar then
        ns.FRAME_ANCHOR_INFO.infoBar = {
            displayName = ns.L["Info Bar"], category = "Display", order = 11,
        }
    end
    local anchoring = ns.QUI_Anchoring
    if anchoring and anchoring.RegisterAnchorTarget then
        anchoring:RegisterAnchorTarget("infoBar", bar, {
            displayName = ns.L["Info Bar"], category = "Display", order = 11,
        })
        if anchoring.ApplyAllFrameAnchors then
            anchoring:ApplyAllFrameAnchors()
        end
    end
end

local slotPool = {}
local SLOT_POOL_CAP = 32

local function ReleaseSlots(zf)
    for _, slot in ipairs(zf.slots) do
        if QUICore.Datatexts then
            QUICore.Datatexts:DetachFromSlot(slot)
        end
        slot._quiWidgetId = nil
        slot._quiMinWidth = nil
        slot._quiXOffset = nil
        slot._quiFixedWidth = nil
        slot._quiOverflowHidden = nil
        slot._quiOnWidthDirty = nil
        slot._quiLdbName = nil
        slot.shortLabel = nil
        slot.noLabel = nil
        slot.hideIcon = nil
        slot.hideText = nil
        slot.text._quiHideText = nil
        slot.clickThrough = nil
        slot.text:SetText("")
        slot:SetAlpha(1)
        slot:Hide()
        if #slotPool < SLOT_POOL_CAP then
            slotPool[#slotPool + 1] = slot
        else
            slot:SetParent(nil)
        end
    end
    wipe(zf.slots)
end

local function CreateSlot(zf, widgetId)
    local db = GetDB()
    local slot = table.remove(slotPool)
    if slot then
        slot:SetParent(zf)
        slot:Show()
    else
        slot = CreateFrame("Button", nil, zf)
        slot.text = slot:CreateFontString(nil, "OVERLAY")
        slot.text:SetPoint("LEFT", slot, "LEFT", 4, 0)
        slot.text:SetJustifyH("LEFT")
        slot.text:SetWordWrap(false)
        local origSetText = slot.text.SetText
        local origSetFormatted = slot.text.SetFormattedText
        local function IconsOnly(s)
            local icons = ""
            for esc in string.gmatch(s, "|T.-|t") do icons = icons .. esc end
            return icons
        end
        slot.text.SetText = function(self, s, ...)
            if self._quiHideText and type(s) == "string" then
                local ok, stripped = pcall(IconsOnly, s)
                if ok then return origSetText(self, stripped) end
            end
            return origSetText(self, s, ...)
        end
        slot.text.SetFormattedText = function(self, fmt, ...)
            if self._quiHideText then
                local ok, s = pcall(string.format, fmt, ...)
                if ok then
                    local ok2, stripped = pcall(IconsOnly, s)
                    if ok2 then return origSetText(self, stripped) end
                end
            end
            return origSetFormatted(self, fmt, ...)
        end
    end
    slot:SetHeight(db.height or 22)
    slot:EnableMouse(true)

    local general = QUICore.db.profile.general or {}
    local fontPath = LSM:Fetch("font", general.font or "Quazii") or "Fonts\\FRIZQT__.TTF"
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(slot.text, fontPath, db.fontSize or 12, general.fontOutline or "OUTLINE")
    else
        QUICore:SafeSetFont(slot.text, fontPath, db.fontSize or 12, general.fontOutline or "OUTLINE")
    end
    slot.text:SetTextColor(1, 1, 1, 1)

    local ws = db.widgetSettings and db.widgetSettings[widgetId]
    slot.shortLabel = ws and ws.shortLabel or false
    slot.noLabel = ws and ws.noLabel or false
    slot.hideIcon = ws and ws.hideIcon or false
    slot.hideText = ws and ws.hideText or false
    slot.text._quiHideText = slot.hideText
    slot.clickThrough = ws and ws.clickThrough or false
    slot._quiMinWidth = ws and ws.minWidth or 0
    slot._quiXOffset = ws and ws.xOffset or 0
    slot._quiWidgetId = widgetId
    slot._quiOnWidthDirty = QueueReflow

    return slot
end

local function SlotNaturalWidth(slot)
    local w = slot._quiFixedWidth
    if not w then
        w = (slot.text and slot.text:GetStringWidth() or 0) + 8
    end
    return max(w, slot._quiMinWidth or 0)
end

local function ReflowZone(key)
    local db = GetDB()
    if not db then return end
    local zf = zoneFrames[key]
    local spacing = db.widgetSpacing or 12
    local x = 0
    for _, slot in ipairs(zf.slots) do
        if not slot._quiOverflowHidden then
            local w = SlotNaturalWidth(slot)
            slot:SetWidth(max(1, floor(w + 0.5)))
            slot:SetHeight(db.height or 22)
            slot:ClearAllPoints()
            local off = slot._quiXOffset or 0
            if key == "right" then
                slot:SetPoint("RIGHT", zf, "RIGHT", -x + off, 0)
            else
                slot:SetPoint("LEFT", zf, "LEFT", x + off, 0)
            end
            x = x + slot:GetWidth() + spacing
            slot:Show()
        else
            slot:Hide()
        end
    end
    zf:SetWidth(max(1, x > 0 and (x - spacing) or 1))
    zf:SetHeight(db.height or 22)
end

local function ResolveOverflow()
    local db = GetDB()
    if not db then return end
    local pad = db.zonePadding or 8
    local spacing = db.widgetSpacing or 12
    local barW = bar:GetWidth()
    if not barW or barW <= 0 then return end

    local function zoneW(key) return zoneFrames[key]:GetWidth() end
    local function trimTrailing(key)
        local slots = zoneFrames[key].slots
        for i = #slots, 1, -1 do
            if not slots[i]._quiOverflowHidden then
                slots[i]._quiOverflowHidden = true
                return true
            end
        end
        return false
    end

    local guard = 0
    while guard < 100 do
        guard = guard + 1
        local leftEnd = pad + zoneW("left")
        local rightStart = barW - pad - zoneW("right")
        local cW = zoneW("center")
        local cStart = (barW - cW) / 2
        local cEnd = cStart + cW
        local collide
        if cW > 1 then
            collide = (leftEnd + spacing > cStart and trimTrailing("left"))
                or (cEnd + spacing > rightStart and trimTrailing("right"))
                or ((leftEnd + spacing > cStart or cEnd + spacing > rightStart)
                    and trimTrailing("center"))
        else
            collide = (leftEnd + spacing > rightStart)
                and (trimTrailing("left") or trimTrailing("right"))
        end
        if not collide then break end
        for _, key in ipairs(ZONES) do ReflowZone(key) end
    end
end

function InfoBar:GetZoneFrames()
    return zoneFrames
end

function InfoBar:ReflowAll()
    if not bar then return end
    if InCombatLockdown() and not ns._inInitSafeWindow then
        reflowPendingCombat = true
        return
    end
    if not bar:IsShown() then return end
    for _, key in ipairs(ZONES) do
        for _, slot in ipairs(zoneFrames[key].slots) do
            slot._quiOverflowHidden = nil
        end
        ReflowZone(key)
    end
    ResolveOverflow()
end

local function ApplyVisibilityRules()
    local db = GetDB()
    if not db then return end

    if db.hideInCombat then
        RegisterStateDriver(bar, "visibility", "[combat] hide; show")
    else
        UnregisterStateDriver(bar, "visibility")
        bar:Show()
    end

    if fadeTicker then fadeTicker:Cancel(); fadeTicker = nil end
    if db.mouseoverFade then
        local rest = (db.fadeRestOpacity or 0) / 100
        local settledAt = nil
        fadeTicker = C_Timer.NewTicker(0.1, function()
            local target = bar:IsMouseOver() and 1 or rest
            if settledAt == target then return end
            local cur = bar:GetAlpha()
            if math.abs(cur - target) < 0.02 then
                if cur ~= target then bar:SetAlpha(target) end
                settledAt = target
            else
                bar:SetAlpha(cur + (target - cur) * 0.35)
                settledAt = nil
            end
        end)
    else
        bar:SetAlpha(1)
    end
end

local function SeedDefaultZones(db)
    if db.zonesSeeded then return end
    db.zones = db.zones or {}
    for _, key in ipairs(ZONES) do
        local list = db.zones[key]
        if list and #list > 0 then
            db.zonesSeeded = true
            return
        end
    end
    db.zones.left   = { "micromenu" }
    db.zones.center = { "time" }
    db.zones.right  = { "durability", "latency", "fps", "gold" }
    db.zonesSeeded = true
end

function InfoBar:ApplyAll()
    local db = GetDB()
    if not db then return end

    SeedDefaultZones(db)

    if InCombatLockdown() and not ns._inInitSafeWindow then
        applyPendingCombat = true
        return
    end

    CreateBar()

    if not db.enabled then
        UnregisterStateDriver(bar, "visibility")
        if fadeTicker then fadeTicker:Cancel(); fadeTicker = nil end
        if QUICore.Datatexts then
            QUICore.Datatexts:UnregisterSharedTicker(bar)
        end
        for _, key in ipairs(ZONES) do ReleaseSlots(zoneFrames[key]) end
        bar:Hide()
        return
    end

    ApplyPosition()
    ApplyBackdrop()

    local pad = db.zonePadding or 8
    local zl, zc, zr = zoneFrames.left, zoneFrames.center, zoneFrames.right
    zl:ClearAllPoints(); zl:SetPoint("LEFT", bar, "LEFT", pad, 0)
    zc:ClearAllPoints(); zc:SetPoint("CENTER", bar, "CENTER", 0, 0)
    zr:ClearAllPoints(); zr:SetPoint("RIGHT", bar, "RIGHT", -pad, 0)

    local Datatexts = QUICore.Datatexts
    for _, key in ipairs(ZONES) do
        local zf = zoneFrames[key]
        ReleaseSlots(zf)
        local list = db.zones and db.zones[key] or {}
        for _, widgetId in ipairs(list) do
            local slot = CreateSlot(zf, widgetId)
            if Datatexts then
                Datatexts:AttachToSlot(slot, widgetId, db)
            end
            if slot.clickThrough then slot:EnableMouse(false) end
            zf.slots[#zf.slots + 1] = slot
        end
    end

    bar:Show()
    ApplyVisibilityRules()
    InfoBar:ReflowAll()
    QueueReflow()

    if Datatexts then
        Datatexts:RegisterSharedTicker(bar, function()
            if bar:IsShown() then InfoBar:ReflowAll() end
        end)
    end
end

_G.QUI_RefreshInfoBar = function()
    InfoBar:ApplyAll()
end

if ns.Registry then
    ns.Registry:Register("infobar", {
        refresh = _G.QUI_RefreshInfoBar,
        priority = 41,
        group = "data",
        importCategories = { "infobar" },
    })
    ns.Registry:Register("infobarSkin", {
        refresh = function()
            if bar and GetDB() then ApplyBackdrop() end
        end,
        priority = 41,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(function()
        C_Timer.After(0, function() InfoBar:ApplyAll() end)
    end)
end
