--- QUI Info Bar — Shift+left-drag widget reorder on the LIVE bar. Companion to
--- contextmenu.lua: pure db.zones helpers (headlessly unit-tested in
--- tests/unit/infobar_dragreorder_test.lua) plus an in-game wiring layer that
--- attaches Shift-drag handlers to each slot after every ApplyAll. Loads last
--- in the TOC so InfoBar.ContextMenu (FindWidget/EnsureZones) is available.

local _, ns = ...
local QUICore = ns.Addon

local InfoBar = QUICore and QUICore.InfoBar
if not InfoBar then return end

local ContextMenu = InfoBar.ContextMenu  -- pure helpers, loaded earlier in TOC

local DragReorder = {}
InfoBar.DragReorder = DragReorder

local ZONE_ORDER = { "left", "center", "right" }

---------------------------------------------------------------------------
-- PURE HELPERS (headlessly unit-tested; nothing in-game below this block)
---------------------------------------------------------------------------

-- Move widgetId so it lands at array index `targetGap` (1..#dst+1, computed
-- against the CURRENT lists, i.e. BEFORE removal) in `targetZone`. Returns
-- true if the layout actually changed. Mirrors the settings-panel drag
-- (remove-then-insert) generalized across zones.
function DragReorder.MoveWidget(db, widgetId, targetZone, targetGap)
    local srcKey, srcIdx = ContextMenu.FindWidget(db, widgetId)
    if not srcKey then return false end
    local zones = ContextMenu.EnsureZones(db)
    local dst = zones[targetZone]
    if not dst then return false end

    -- Same-zone: removing an element BEFORE the insertion point shifts the
    -- list left, so the gap index drops by one (identical to the settings
    -- drag's `gap > curIdx and gap-1` adjustment).
    local adjGap = targetGap
    if srcKey == targetZone and srcIdx < adjGap then
        adjGap = adjGap - 1
    end

    -- No-op: dropping a widget back into its own slot.
    if srcKey == targetZone and adjGap == srcIdx then return false end

    table.remove(zones[srcKey], srcIdx)
    if adjGap < 1 then adjGap = 1 end
    if adjGap > #dst + 1 then adjGap = #dst + 1 end
    table.insert(dst, adjGap, widgetId)
    return true
end

-- Map a screen side relative to an anchor slot ("left"/"right" of its center)
-- to a db.zones array insertion index. The right zone renders array order
-- right-to-left (ReflowZone anchors RIGHT with a negated accumulator), so its
-- mapping is mirrored: screen-left of the anchor = a LATER array index.
function DragReorder.ResolveArrayInsert(side, anchorArrayIdx, isRight)
    local before = (side == "left")
    if isRight then before = not before end
    return before and anchorArrayIdx or (anchorArrayIdx + 1)
end

-- spans: array of { key=, left=, right= } in screen coords (one per zone).
-- Returns the key of the zone whose span contains cursorX; for a cursor in a
-- between-zone gap (or outside all zones), the nearest zone by edge distance.
-- Empty zones still participate (left==right) so a widget can be dropped into
-- an empty zone.
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

---------------------------------------------------------------------------
-- IN-GAME WIRING (no headless test below this line)
---------------------------------------------------------------------------

local UIKit = ns.UIKit
local Helpers = ns.Helpers

local function GetAccent()
    local QGUI = _G.QUI and _G.QUI.GUI
    if QGUI and QGUI.Colors and QGUI.Colors.accent then
        return QGUI.Colors.accent[1], QGUI.Colors.accent[2], QGUI.Colors.accent[3]
    end
    return 0.376, 0.647, 0.980 -- fallback: Sky Blue
end

local function RefreshAll()
    if _G.QUI_RefreshInfoBar then _G.QUI_RefreshInfoBar() end
    -- Keep an open options page in sync (same structural notify the context
    -- menu and settings page fire). The settings layer may not be loaded.
    local compat = ns.Settings and ns.Settings.RenderAdapters
    if compat and compat.NotifyProviderChanged then
        compat.NotifyProviderChanged("infobar", { structural = true })
    end
end

local function GetDB()
    local db = QUICore.db and QUICore.db.profile
    return db and db.infobar
end

-- Drag state (single drag at a time).
local dragSlot          -- the slot Button currently being dragged
local dropLine          -- vertical insertion-marker texture (lazy, on the bar)
local updater = CreateFrame("Frame")
updater:Hide()

-- Lazily create the insertion line parented to the bar. Returns nil until the
-- bar frame exists (it always does by the time a drag can start).
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

-- Compute the drop target for the current cursor position.
-- Returns: targetZone, anchorWidgetId|nil, side ("left"/"right"), lineX (screen)
-- anchorWidgetId is nil when the target zone has no other visible slot (drop
-- into an empty/own-only zone -> insert at index 1).
local function ComputeDrop()
    -- Combat bail: a placed secure-child widget (travel's hearthstone) makes the
    -- bar/zone/slot geometry SecretWhenAnchoringSecret in combat, and the bar is
    -- an anchor target. Reading those returns secret values whose arithmetic
    -- THROWS. The drag is blocked at start in combat; this also covers combat
    -- STARTING mid-drag (the OnUpdate keeps calling here). SafeToNumber below is
    -- belt-and-suspenders for the one frame before InCombatLockdown flips true.
    if InCombatLockdown() then return end
    local bar = _G["QUI_InfoBar"]
    if not bar then return end
    -- A secret scale maps to 0 here and bails cleanly via the guard below.
    local scale = Helpers.SafeToNumber(bar:GetEffectiveScale(), 0)
    if scale <= 0 then return end
    local cursorX = GetCursorPosition() / scale  -- GetCursorPosition is never secret

    local zoneFrames = InfoBar:GetZoneFrames()

    -- Zone spans from live geometry.
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

    -- Visible slots of the target zone (exclude the dragged slot and any
    -- overflow-hidden slot), with screen centers.
    local zf = zoneFrames[targetZone]
    local candidates = {}
    for _, slot in ipairs(zf.slots) do
        if slot ~= dragSlot and not slot._quiOverflowHidden and slot:IsShown() then
            local cx = Helpers.SafeToNumber(slot:GetCenter(), 0)
            candidates[#candidates + 1] = { id = slot._quiWidgetId, center = cx, slot = slot }
        end
    end

    if #candidates == 0 then
        -- Empty (or own-only) zone: line at zone center, insert at index 1.
        local s
        for _, sp in ipairs(spans) do if sp.key == targetZone then s = sp end end
        local lineX = s and (s.left + s.right) / 2 or cursorX
        return targetZone, nil, "right", lineX
    end

    -- Nearest visible slot by center distance; side = which side of its center.
    local best, bestDist
    for _, c in ipairs(candidates) do
        local d = math.abs(cursorX - c.center)
        if not bestDist or d < bestDist then bestDist = d; best = c end
    end
    local side = (cursorX < best.center) and "left" or "right"

    -- Line sits on the chosen side of the anchor slot.
    local lineX
    if side == "left" then
        lineX = Helpers.SafeToNumber(best.slot:GetLeft(), best.center)
    else
        lineX = Helpers.SafeToNumber(best.slot:GetRight(), best.center)
    end
    return targetZone, best.id, side, lineX
end

-- Idempotent teardown: stop the OnUpdate, hide the line, un-dim the dragged
-- slot. Safe to call from the combat bail AND a later OnDragStop (dragSlot is
-- cleared so the second call is a no-op).
local function CancelDrag()
    updater:Hide()
    if dropLine then dropLine:Hide() end
    if dragSlot then
        dragSlot:SetAlpha(1)
        dragSlot = nil
    end
end

local function UpdateDropLine()
    -- Combat started mid-drag: tear down rather than touch secret geometry.
    if InCombatLockdown() then CancelDrag(); return end
    local bar = _G["QUI_InfoBar"]
    local line = EnsureDropLine()
    if not bar or not line then return end
    local _, _, _, lineX = ComputeDrop()
    if not lineX then line:Hide(); return end
    local barLeft = Helpers.SafeToNumber(bar:GetLeft(), nil)
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
    -- Compute the drop WHILE dragSlot is still set: ComputeDrop excludes the
    -- dragged slot from anchor candidates, so it must run before teardown nils
    -- it. ComputeDrop returns nil if combat started mid-drag (secret geometry).
    local targetZone, anchorId, side = ComputeDrop()
    local widgetId = slot._quiWidgetId
    -- Tear down the visual + clear dragSlot (also un-dims via dragSlot == slot).
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
        targetGap = 1 -- empty/own-only zone
    end

    if DragReorder.MoveWidget(db, widgetId, targetZone, targetGap) then
        RefreshAll()
    end
end

-- Attach Shift-drag to a slot exactly once. Scripts survive pool reuse, and
-- the handlers read slot._quiWidgetId live (re-stamped each CreateSlot), so a
-- once-wired slot keeps working after rebuilds. Note: a clickThrough widget has
-- EnableMouse(false), so it receives no OnDragStart and can't be dragged on the
-- live bar — reorder those via the settings panel or right-click context menu.
local function WireSlotDrag(slot)
    if slot._quiDragWired then return end
    slot._quiDragWired = true
    slot:RegisterForDrag("LeftButton")
    -- HookScript: never clobber a provider-set OnDragStart/Stop (none today,
    -- but compose defensively). A non-Shift left-drag is a no-op here, leaving
    -- the provider's plain-click datatext action intact.
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

-- Wire after each ApplyAll: slots are (re)built by the original ApplyAll, then
-- we walk them. Composes with contextmenu.lua's own ApplyAll wrap (load order:
-- contextmenu wraps first, this wraps it). Insecure script on insecure slots;
-- combat is handled at drag-start, and the drop's RefreshAll rides ApplyAll's
-- own combat deferral.
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
