local _, ns = ...
local QUICore = ns.Addon

local InfoBar = QUICore and QUICore.InfoBar
if not InfoBar then return end

local ContextMenu = InfoBar.ContextMenu

local DragReorder = {}
InfoBar.DragReorder = DragReorder

local ZONE_ORDER = { "left", "center", "right" }

function DragReorder.MoveWidget(db, widgetId, targetZone, targetGap)
    local srcKey, srcIdx = ContextMenu.FindWidget(db, widgetId)
    if not srcKey then return false end
    local zones = ContextMenu.EnsureZones(db)
    local dst = zones[targetZone]
    if not dst then return false end

    local adjGap = targetGap
    if srcKey == targetZone and srcIdx < adjGap then
        adjGap = adjGap - 1
    end

    if srcKey == targetZone and adjGap == srcIdx then return false end

    table.remove(zones[srcKey], srcIdx)
    if adjGap < 1 then adjGap = 1 end
    if adjGap > #dst + 1 then adjGap = #dst + 1 end
    table.insert(dst, adjGap, widgetId)
    return true
end

function DragReorder.ResolveArrayInsert(side, anchorArrayIdx, isRight)
    local before = (side == "left")
    if isRight then before = not before end
    return before and anchorArrayIdx or (anchorArrayIdx + 1)
end

function DragReorder.ResolveTargetZone(cursorX, spans)
    local best, bestDist
    for _, s in ipairs(spans) do
        if cursorX >= s.left and cursorX <= s.right then
            return s.key
        end
        local d = (cursorX < s.left) and (s.left - cursorX) or (cursorX - s.right)
        if not bestDist or d < bestDist then
            bestDist = d
            best = s.key
        end
    end
    return best
end

local UIKit = ns.UIKit
local Helpers = ns.Helpers

local function GetAccent()
    local QGUI = _G.QUI and _G.QUI.GUI
    if QGUI and QGUI.Colors and QGUI.Colors.accent then
        return QGUI.Colors.accent[1], QGUI.Colors.accent[2], QGUI.Colors.accent[3]
    end
    return 0.376, 0.647, 0.980
end

local function RefreshAll()
    if _G.QUI_RefreshInfoBar then _G.QUI_RefreshInfoBar() end
    local compat = ns.Settings and ns.Settings.RenderAdapters
    if compat and compat.NotifyProviderChanged then
        compat.NotifyProviderChanged("infobar", { structural = true })
    end
end

local function GetDB()
    local db = QUICore.db and QUICore.db.profile
    return db and db.infobar
end

local dragSlot
local dropLine
local updater = CreateFrame("Frame")
updater:Hide()

local function EnsureDropLine()
    local bar = _G["QUI_InfoBar"]
    if not bar then return nil end
    if not dropLine then
        dropLine = bar:CreateTexture(nil, "OVERLAY")
        dropLine:SetWidth(2)
        if UIKit and UIKit.DisablePixelSnap then
            UIKit.DisablePixelSnap(dropLine)
        end
    end
    local r, g, b = GetAccent()
    dropLine:SetColorTexture(r, g, b, 0.9)
    return dropLine
end

local function ComputeDrop()
    if InCombatLockdown() then return end
    local bar = _G["QUI_InfoBar"]
    if not bar then return end
    local scale = Helpers.SafeToNumber(bar:GetEffectiveScale(), 0)
    if scale <= 0 then return end
    local cursorX = GetCursorPosition() / scale

    local zoneFrames = InfoBar:GetZoneFrames()

    local spans = {}
    for _, key in ipairs(ZONE_ORDER) do
        local zf = zoneFrames[key]
        local l = zf and Helpers.SafeToNumber(zf:GetLeft(), 0)
        local rgt = zf and Helpers.SafeToNumber(zf:GetRight(), 0)
        if l and rgt then
            spans[#spans + 1] = { key = key, left = l, right = rgt }
        end
    end
    if #spans == 0 then return end
    local targetZone = DragReorder.ResolveTargetZone(cursorX, spans)

    local zf = zoneFrames[targetZone]
    local candidates = {}
    for _, slot in ipairs(zf.slots) do
        if slot ~= dragSlot and not slot._quiOverflowHidden and slot:IsShown() then
            local cx = Helpers.SafeToNumber(slot:GetCenter(), 0)
            candidates[#candidates + 1] = { id = slot._quiWidgetId, center = cx, slot = slot }
        end
    end

    if #candidates == 0 then
        local s
        for _, sp in ipairs(spans) do if sp.key == targetZone then s = sp end end
        local lineX = s and (s.left + s.right) / 2 or cursorX
        return targetZone, nil, "right", lineX
    end

    local best, bestDist
    for _, c in ipairs(candidates) do
        local d = math.abs(cursorX - c.center)
        if not bestDist or d < bestDist then bestDist = d; best = c end
    end
    local side = (cursorX < best.center) and "left" or "right"

    local lineX
    if side == "left" then
        lineX = Helpers.SafeToNumber(best.slot:GetLeft(), best.center)
    else
        lineX = Helpers.SafeToNumber(best.slot:GetRight(), best.center)
    end
    return targetZone, best.id, side, lineX
end

local function CancelDrag()
    updater:Hide()
    if dropLine then dropLine:Hide() end
    if dragSlot then
        dragSlot:SetAlpha(1)
        dragSlot = nil
    end
end

local function UpdateDropLine()
    if InCombatLockdown() then CancelDrag(); return end
    local bar = _G["QUI_InfoBar"]
    local line = EnsureDropLine()
    if not bar or not line then return end
    local _, _, _, lineX = ComputeDrop()
    if not lineX then line:Hide(); return end
    local barLeft = Helpers.SafeNumberOrNil(bar:GetLeft())
    if not barLeft then line:Hide(); return end
    line:ClearAllPoints()
    line:SetPoint("TOP", bar, "TOPLEFT", lineX - barLeft, 0)
    line:SetPoint("BOTTOM", bar, "BOTTOMLEFT", lineX - barLeft, 0)
    line:Show()
end

updater:SetScript("OnUpdate", UpdateDropLine)

local function BeginDrag(slot)
    dragSlot = slot
    slot:SetAlpha(0.4)
    EnsureDropLine()
    updater:Show()
end

local function EndDrag(slot)
    if dragSlot ~= slot then return end
    local targetZone, anchorId, side = ComputeDrop()
    local widgetId = slot._quiWidgetId
    CancelDrag()

    if not targetZone or not widgetId then return end

    local db = GetDB()
    if not db then return end

    local isRight = (targetZone == "right")
    local targetGap
    if anchorId then
        local _, anchorIdx = ContextMenu.FindWidget(db, anchorId)
        if not anchorIdx then return end
        targetGap = DragReorder.ResolveArrayInsert(side, anchorIdx, isRight)
    else
        targetGap = 1
    end

    if DragReorder.MoveWidget(db, widgetId, targetZone, targetGap) then
        RefreshAll()
    end
end

local function WireSlotDrag(slot)
    if slot._quiDragWired then return end
    slot._quiDragWired = true
    slot:RegisterForDrag("LeftButton")
    slot:HookScript("OnDragStart", function(self)
        if not IsShiftKeyDown() then return end
        if InCombatLockdown() then
            if UIErrorsFrame then
                UIErrorsFrame:AddMessage(ns.L["Can't reorder the Info Bar in combat."], 1, 0.3, 0.3)
            end
            return
        end
        BeginDrag(self)
    end)
    slot:HookScript("OnDragStop", EndDrag)
end

local origApplyAll = InfoBar.ApplyAll
function InfoBar:ApplyAll()
    origApplyAll(self)
    local zoneFrames = InfoBar:GetZoneFrames()
    for _, key in ipairs(ZONE_ORDER) do
        local zf = zoneFrames[key]
        if zf then
            for _, slot in ipairs(zf.slots) do
                WireSlotDrag(slot)
            end
        end
    end
end
