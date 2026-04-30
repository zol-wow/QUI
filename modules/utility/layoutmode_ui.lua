---------------------------------------------------------------------------
-- QUI Layout Mode — Visual Components
-- Grid overlay, snap system, arrow key nudging, HUD toolbar,
-- alignment guides, screen overlay, save/discard popup.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local UIKit = ns.UIKit
local floor = math.floor
local max = math.max
local min = math.min
local abs = math.abs

local QUI_LayoutMode_UI = {}
ns.QUI_LayoutMode_UI = QUI_LayoutMode_UI

-- Accent color: cached from GUI.Colors.accent, refreshed when layout mode opens.
local ACCENT_R, ACCENT_G, ACCENT_B = 0.376, 0.647, 0.980

function QUI_LayoutMode_UI:RefreshAccentColor()
    local GUI = _G.QUI and _G.QUI.GUI
    if GUI and GUI.Colors and GUI.Colors.accent then
        ACCENT_R = GUI.Colors.accent[1]
        ACCENT_G = GUI.Colors.accent[2]
        ACCENT_B = GUI.Colors.accent[3]
    end
end

-- Grid constants
local GRID_SPACING = 32
local GRID_DIMMED_ALPHA = 0.15
local GRID_BRIGHT_ALPHA = 0.30
local GRID_LINE_COLOR_R, GRID_LINE_COLOR_G, GRID_LINE_COLOR_B = 0.5, 0.5, 0.5

-- Snap constants
local SNAP_THRESHOLD = 6
local SNAP_THRESHOLD_ANCHOR = 8   -- slightly wider threshold when Shift held for anchoring
local SNAP_BREAKAWAY_MULT = 2     -- must move 2x threshold to break free of a snap

-- Anchor visual constants
local ANCHOR_BORDER_SIZE = 3
local ANCHOR_BORDER_R, ANCHOR_BORDER_G, ANCHOR_BORDER_B = 1.0, 0.85, 0.30  -- gold

-- Nudge constants
local NUDGE_INITIAL_DELAY = 0.35
local NUDGE_MIN_INTERVAL  = 0.015
local NUDGE_MAX_INTERVAL  = 0.08
local NUDGE_RAMP_TIME     = 2.0

-- State (loaded from DB in Show(), saved on change)
QUI_LayoutMode_UI.snapEnabled = true
QUI_LayoutMode_UI.gridMode = 0      -- 0=off, 1=dimmed, 2=bright
QUI_LayoutMode_UI.showCoords = false -- show coords on all movers
QUI_LayoutMode_UI.showOverlays = true -- show mover backgrounds

-- Forward declarations
local CreateOverlay, CreateGrid, CreateToolbar, CreateNudgeHandler
local CreateSnapGuides, CreateSaveDiscardPopup
local BuildGrid, HideGrid, ShowGrid

-- Persist snap/grid state to DB
local function GetLayoutModeDB()
    local Helpers = ns.Helpers
    local core = Helpers and Helpers.GetCore and Helpers.GetCore()
    local db = core and core.db and core.db.profile
    if not db then return nil end
    if not db.layoutMode then db.layoutMode = {} end
    return db.layoutMode
end

local function LoadPersistedState(ui)
    local db = GetLayoutModeDB()
    if not db then return end
    if db.snapEnabled ~= nil then ui.snapEnabled = db.snapEnabled end
    if db.gridMode ~= nil then ui.gridMode = db.gridMode end
end

local function SavePersistedState(ui)
    local db = GetLayoutModeDB()
    if not db then return end
    db.snapEnabled = ui.snapEnabled
    db.gridMode = ui.gridMode
end

local function GetConfigPanelScale()
    local core = Helpers and Helpers.GetCore and Helpers.GetCore()
    local db = core and core.db and core.db.profile
    local scale = db and db.configPanelScale or 1
    scale = tonumber(scale) or 1
    return max(0.8, min(1.5, scale))
end

function QUI_LayoutMode_UI:GetConfigPanelScale()
    return GetConfigPanelScale()
end

function QUI_LayoutMode_UI:ApplyConfigPanelScale(frame)
    if frame and frame.SetScale then
        frame:SetScale(GetConfigPanelScale())
    end
end

---------------------------------------------------------------------------
-- SHOW / HIDE (called by layoutmode.lua)
---------------------------------------------------------------------------

function QUI_LayoutMode_UI:Show()
    if not self._initialized then
        self:_Initialize()
    end

    -- Restore persisted snap/grid state
    LoadPersistedState(self)
    self:ApplyConfigPanelScale(self._toolbarPanel)
    self:ApplyConfigPanelScale(self._drawer)
    self:_UpdateToolbarButtons()

    if self._overlay then
        self._overlay:Show()
    end

    if self.gridMode > 0 then
        ShowGrid(self)
    end

    if self._toolbar then
        self._toolbar:Show()
    end

    -- Auto-expand panel + drawer on layout mode entry
    if self._expandToolbar then
        self._expandToolbar()
    end
    C_Timer.After(0.2, function()
        if self._drawer and not self._drawer:IsShown() then
            self:ToggleFramesDrawer()
        end
    end)

    if self._nudgeFrame then
        self._nudgeFrame:Show()
        -- Always capture keyboard for Escape; arrow nudging checks selection internally
        self._nudgeFrame:EnableKeyboard(true)
    end
end

function QUI_LayoutMode_UI:Hide()
    -- Reset expanded state so Expand() works on re-entry
    if self._resetToolbarState then
        self._resetToolbarState()
    end

    if self._overlay then
        self._overlay:Hide()
    end

    HideGrid(self)

    if self._toolbar then
        self._toolbar:Hide()
    end

    if self._toolbarPanel then
        self._toolbarPanel:Hide()
    end

    if self._nudgeFrame then
        self._nudgeFrame:EnableKeyboard(false)
        self._nudgeFrame:Hide()
    end

    self:ClearSnapGuides()

    if self._popup and self._popup:IsShown() then
        self._popup:Hide()
    end

    if self._drawer and self._drawer:IsShown() then
        self._drawer:Hide()
    end
end

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------

-- Forward declaration for drawer
local CreateFramesDrawer

function QUI_LayoutMode_UI:_Initialize()
    if self._initialized then return end
    self._initialized = true

    CreateOverlay(self)
    CreateGrid(self)
    CreateToolbar(self)
    CreateNudgeHandler(self)
    CreateSnapGuides(self)
    CreateSaveDiscardPopup(self)
    CreateFramesDrawer(self)
end

---------------------------------------------------------------------------
-- SCREEN OVERLAY
---------------------------------------------------------------------------

CreateOverlay = function(ui)
    local overlay = CreateFrame("Frame", "QUI_LayoutMode_Overlay", UIParent)
    overlay:SetFrameStrata("FULLSCREEN_DIALOG")
    overlay:SetFrameLevel(50)
    overlay:SetAllPoints()
    overlay:EnableMouse(false)
    overlay:Hide()

    local bg = overlay:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.03)

    ui._overlay = overlay
end

---------------------------------------------------------------------------
-- GRID OVERLAY
---------------------------------------------------------------------------

CreateGrid = function(ui)
    ui._gridLines = {}
    ui._gridFrame = CreateFrame("Frame", "QUI_LayoutMode_Grid", UIParent)
    ui._gridFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    ui._gridFrame:SetFrameLevel(51)
    ui._gridFrame:SetAllPoints()
    ui._gridFrame:Hide()
end

BuildGrid = function(ui)
    -- Clear existing lines
    for _, line in ipairs(ui._gridLines) do
        line:Hide()
    end

    local lines = ui._gridLines
    local idx = 0
    local parent = ui._gridFrame
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local alpha = ui.gridMode == 1 and GRID_DIMMED_ALPHA or GRID_BRIGHT_ALPHA

    local function GetLine()
        idx = idx + 1
        local line = lines[idx]
        if not line then
            line = parent:CreateTexture(nil, "ARTWORK")
            lines[idx] = line
        end
        return line
    end

    -- Vertical lines
    local cx = sw / 2
    for x = cx, sw, GRID_SPACING do
        local line = GetLine()
        line:SetColorTexture(GRID_LINE_COLOR_R, GRID_LINE_COLOR_G, GRID_LINE_COLOR_B, alpha)
        line:SetWidth(1)
        line:ClearAllPoints()
        line:SetPoint("TOP", parent, "BOTTOMLEFT", x, sh)
        line:SetPoint("BOTTOM", parent, "BOTTOMLEFT", x, 0)
        line:Show()

        -- Mirror on left side
        if x ~= cx then
            local mirrorX = cx - (x - cx)
            if mirrorX >= 0 then
                line = GetLine()
                line:SetColorTexture(GRID_LINE_COLOR_R, GRID_LINE_COLOR_G, GRID_LINE_COLOR_B, alpha)
                line:SetWidth(1)
                line:ClearAllPoints()
                line:SetPoint("TOP", parent, "BOTTOMLEFT", mirrorX, sh)
                line:SetPoint("BOTTOM", parent, "BOTTOMLEFT", mirrorX, 0)
                line:Show()
            end
        end
    end

    -- Horizontal lines
    local cy = sh / 2
    for y = cy, sh, GRID_SPACING do
        local line = GetLine()
        line:SetColorTexture(GRID_LINE_COLOR_R, GRID_LINE_COLOR_G, GRID_LINE_COLOR_B, alpha)
        line:SetHeight(1)
        line:ClearAllPoints()
        line:SetPoint("LEFT", parent, "BOTTOMLEFT", 0, y)
        line:SetPoint("RIGHT", parent, "BOTTOMLEFT", sw, y)
        line:Show()

        if y ~= cy then
            local mirrorY = cy - (y - cy)
            if mirrorY >= 0 then
                line = GetLine()
                line:SetColorTexture(GRID_LINE_COLOR_R, GRID_LINE_COLOR_G, GRID_LINE_COLOR_B, alpha)
                line:SetHeight(1)
                line:ClearAllPoints()
                line:SetPoint("LEFT", parent, "BOTTOMLEFT", 0, mirrorY)
                line:SetPoint("RIGHT", parent, "BOTTOMLEFT", sw, mirrorY)
                line:Show()
            end
        end
    end

    -- Center crosshair (accent color, slightly thicker)
    local centerV = GetLine()
    centerV:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, alpha * 2)
    centerV:SetWidth(2)
    centerV:ClearAllPoints()
    centerV:SetPoint("TOP", parent, "BOTTOMLEFT", cx, sh)
    centerV:SetPoint("BOTTOM", parent, "BOTTOMLEFT", cx, 0)
    centerV:Show()

    local centerH = GetLine()
    centerH:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, alpha * 2)
    centerH:SetHeight(2)
    centerH:ClearAllPoints()
    centerH:SetPoint("LEFT", parent, "BOTTOMLEFT", 0, cy)
    centerH:SetPoint("RIGHT", parent, "BOTTOMLEFT", sw, cy)
    centerH:Show()

    -- Hide any excess lines
    for i = idx + 1, #lines do
        lines[i]:Hide()
    end
end

ShowGrid = function(ui)
    if not ui._gridFrame then return end
    BuildGrid(ui)
    ui._gridFrame:Show()
end

HideGrid = function(ui)
    if ui._gridFrame then
        ui._gridFrame:Hide()
    end
end

function QUI_LayoutMode_UI:CycleGrid()
    self.gridMode = (self.gridMode + 1) % 3
    if self.gridMode == 0 then
        HideGrid(self)
    else
        ShowGrid(self)
    end
    self:_UpdateToolbarButtons()
end

---------------------------------------------------------------------------
-- SNAP SYSTEM
---------------------------------------------------------------------------

-- Snap guide color (amber tint, distinct from accent blue)
local SNAP_GUIDE_R, SNAP_GUIDE_G, SNAP_GUIDE_B = 0.96, 0.62, 0.04

CreateSnapGuides = function(ui)
    ui._snapGuides = {}
    for i = 1, 4 do
        local line = UIParent:CreateTexture(nil, "OVERLAY")
        line:SetColorTexture(SNAP_GUIDE_R, SNAP_GUIDE_G, SNAP_GUIDE_B, 0.6)
        line:Hide()
        ui._snapGuides[i] = line
    end

    -- Anchor indicator: accent-tinted connection line (green, distinct from blue snap guides)
    local anchorLine = UIParent:CreateTexture(nil, "OVERLAY")
    anchorLine:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.8)
    anchorLine:Hide()
    ui._anchorLine = anchorLine
end

function QUI_LayoutMode_UI:ClearSnapGuides()
    if self._snapGuides then
        for _, line in ipairs(self._snapGuides) do
            line:Hide()
        end
    end
    if self._anchorLine then
        self._anchorLine:Hide()
    end
end

--- Get edges for a handle (supports both proxy movers and child overlays).
local function GetHandleEdges(handle)
    local um = ns.QUI_LayoutMode
    if um and um.GetHandleEdges then
        return um:GetHandleEdges(handle)
    end
    return handle:GetLeft(), handle:GetRight(), handle:GetTop(), handle:GetBottom()
end

--- Reposition a handle via CENTER offsets (supports both types).
--- ox, oy are in UIParent local coord. For child overlays whose parent has
--- a custom scale, divide by the scale because SetPoint offsets are
--- interpreted in the frame's own coord space.
local function SetHandlePosition(handle, ox, oy)
    if handle._isChildOverlay and handle._parentFrame then
        local parent = handle._parentFrame
        if parent.GetScale then
            local pScale = parent:GetScale() or 1
            if pScale > 0 and pScale ~= 1 then
                ox = ox / pScale
                oy = oy / pScale
            end
        end
        pcall(parent.ClearAllPoints, parent)
        pcall(parent.SetPoint, parent, "CENTER", UIParent, "CENTER", ox, oy)
    else
        handle:ClearAllPoints()
        handle:SetPoint("CENTER", UIParent, "CENTER", ox, oy)
    end
end

--- Get center of a handle (supports both types).
local function GetHandleCenter(handle)
    if handle._isChildOverlay and handle._parentFrame then
        return handle._parentFrame:GetCenter()
    end
    return handle:GetCenter()
end

-- Edge pair index → anchor point mapping (X axis)
-- Indices correspond to the xEdges table order in ApplySnap:
--   1={dragL,oL} 2={dragL,oR} 3={dragL,oCX}
--   4={dragR,oL} 5={dragR,oR} 6={dragR,oCX}
--   7={dragCX,oL} 8={dragCX,oR} 9={dragCX,oCX}
local X_EDGE_ANCHORS = {
    [1] = {"LEFT",   "LEFT"},    -- left-aligned
    [2] = {"LEFT",   "RIGHT"},   -- frame is right-of target
    [3] = {"LEFT",   "CENTER"},  -- left to center
    [4] = {"RIGHT",  "LEFT"},    -- frame is left-of target
    [5] = {"RIGHT",  "RIGHT"},   -- right-aligned
    [6] = {"RIGHT",  "CENTER"},  -- right to center
    [7] = {"CENTER", "LEFT"},    -- center to left
    [8] = {"CENTER", "RIGHT"},   -- center to right
    [9] = {"CENTER", "CENTER"},  -- centered
}

-- Edge pair index → anchor point mapping (Y axis)
-- Same structure but with TOP/BOTTOM:
--   1={dragT,oT} 2={dragT,oB} 3={dragT,oCY}
--   4={dragB,oT} 5={dragB,oB} 6={dragB,oCY}
--   7={dragCY,oT} 8={dragCY,oB} 9={dragCY,oCY}
local Y_EDGE_ANCHORS = {
    [1] = {"TOP",    "TOP"},      -- top-aligned
    [2] = {"TOP",    "BOTTOM"},   -- frame is below target
    [3] = {"TOP",    "CENTER"},   -- top to center
    [4] = {"BOTTOM", "TOP"},      -- frame is above target
    [5] = {"BOTTOM", "BOTTOM"},   -- bottom-aligned
    [6] = {"BOTTOM", "CENTER"},   -- bottom to center
    [7] = {"CENTER", "TOP"},      -- center to top
    [8] = {"CENTER", "BOTTOM"},   -- center to bottom
    [9] = {"CENTER", "CENTER"},   -- centered
}

--- Combine X and Y anchor point parts into a single WoW anchor point.
--- e.g. ("TOP","LEFT") → "TOPLEFT", ("CENTER","CENTER") → "CENTER"
local function CombineAnchorPoint(yPart, xPart)
    if yPart == "CENTER" and xPart == "CENTER" then return "CENTER" end
    if yPart == "CENTER" then return xPart end
    if xPart == "CENTER" then return yPart end
    return yPart .. xPart
end

--- Show the anchor connection line between two handles.
local function ShowAnchorLine(ui, handle, targetHandle)
    local line = ui._anchorLine
    if not line then return end

    local cx1, cy1 = GetHandleCenter(handle)
    local cx2, cy2 = GetHandleCenter(targetHandle)
    if not cx1 or not cy1 or not cx2 or not cy2 then
        line:Hide()
        return
    end

    -- Draw a line from handle center to target center
    local dx = cx2 - cx1
    local dy = cy2 - cy1
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 1 then
        line:Hide()
        return
    end

    -- Use a rotated texture approach: position midpoint, set size
    local midX = (cx1 + cx2) / 2
    local midY = (cy1 + cy2) / 2

    line:ClearAllPoints()
    -- Approximate with horizontal or vertical line depending on dominant axis
    if math.abs(dx) >= math.abs(dy) then
        -- Mostly horizontal
        local left = math.min(cx1, cx2)
        local right = math.max(cx1, cx2)
        line:SetHeight(2)
        line:SetPoint("LEFT", UIParent, "BOTTOMLEFT", left, midY)
        line:SetPoint("RIGHT", UIParent, "BOTTOMLEFT", right, midY)
    else
        -- Mostly vertical
        local bottom = math.min(cy1, cy2)
        local top = math.max(cy1, cy2)
        line:SetWidth(2)
        line:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", midX, bottom)
        line:SetPoint("TOP", UIParent, "BOTTOMLEFT", midX, top)
    end
    line:Show()
end

--- Apply snap to a handle during drag.
--- Finds closest edges of other visible handles and snaps within threshold.
--- Tracks snap target key and edge pair index for anchor-on-snap (Shift held).
--- Uses hysteresis: once snapped, requires a larger distance to break free.
function QUI_LayoutMode_UI:ApplySnap(handle)
    local um = ns.QUI_LayoutMode
    if not um then return end

    -- Even with snapping disabled, we still run edge detection for Shift+anchor
    local snapDisabled = not self.snapEnabled
    local shiftHeld = IsShiftKeyDown()

    -- If snapping is off and Shift isn't held, nothing to do
    if snapDisabled and not shiftHeld then return end

    local dragKey = handle._barKey

    -- The handle is already at the cursor-intended position (set by OnUpdate before
    -- ApplySnap is called), so we can read edges directly. No StartMoving fighting.
    local dragL, dragR, dragT, dragB = GetHandleEdges(handle)

    if not dragL or not dragR or not dragT or not dragB then return end

    local dragCX = (dragL + dragR) / 2
    local dragCY = (dragT + dragB) / 2

    -- Use wider snap threshold when Shift is held (easier to anchor)
    local activeThreshold = shiftHeld and SNAP_THRESHOLD_ANCHOR or SNAP_THRESHOLD

    -- Hysteresis: breakaway always based on base threshold, not the Shift-inflated one
    local snap = handle._snapState or {}
    handle._snapState = snap
    local breakaway = SNAP_THRESHOLD * SNAP_BREAKAWAY_MULT
    local threshX = snap.snappedX and breakaway or activeThreshold
    local threshY = snap.snappedY and breakaway or activeThreshold

    local bestSnapX, bestDistX = nil, threshX + 1
    local bestSnapY, bestDistY = nil, threshY + 1
    local snapLineX, snapLineY

    -- Anchor-on-snap tracking: which element key and edge pair won
    local bestSnapXKey, bestSnapXEdge   -- element key + edge pair index (nil = screen center)
    local bestSnapYKey, bestSnapYEdge

    -- Snap to screen center
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local screenCX, screenCY = sw / 2, sh / 2

    local dx = math.abs(dragCX - screenCX)
    if dx < bestDistX then
        bestDistX = dx
        bestSnapX = screenCX - (dragR - dragL) / 2
        snapLineX = screenCX
        bestSnapXKey = nil  -- screen center, not an element
        bestSnapXEdge = nil
    end

    local dy = math.abs(dragCY - screenCY)
    if dy < bestDistY then
        bestDistY = dy
        bestSnapY = screenCY - (dragT - dragB) / 2
        snapLineY = screenCY
        bestSnapYKey = nil
        bestSnapYEdge = nil
    end

    -- Check against other handles (skip anchor group members that move with us)
    local anchorGroupKeys = handle._anchorGroupKeys
    for key, otherHandle in pairs(um._handles) do
        if key ~= dragKey and otherHandle:IsShown() and not (anchorGroupKeys and anchorGroupKeys[key]) then
            local oL, oR, oT, oB = GetHandleEdges(otherHandle)
            local oCX = oL and oR and (oL + oR) / 2
            local oCY = oT and oB and (oT + oB) / 2

            if oL and oR and oT and oB then
                local xEdges = {
                    {dragL, oL}, {dragL, oR}, {dragL, oCX},
                    {dragR, oL}, {dragR, oR}, {dragR, oCX},
                    {dragCX, oL}, {dragCX, oR}, {dragCX, oCX},
                }
                for idx, pair in ipairs(xEdges) do
                    local dist = math.abs(pair[1] - pair[2])
                    if dist < bestDistX then
                        bestDistX = dist
                        bestSnapX = pair[2] - (pair[1] - dragL)
                        snapLineX = pair[2]
                        bestSnapXKey = key
                        bestSnapXEdge = idx
                    end
                end

                local yEdges = {
                    {dragT, oT}, {dragT, oB}, {dragT, oCY},
                    {dragB, oT}, {dragB, oB}, {dragB, oCY},
                    {dragCY, oT}, {dragCY, oB}, {dragCY, oCY},
                }
                for idx, pair in ipairs(yEdges) do
                    local dist = math.abs(pair[1] - pair[2])
                    if dist < bestDistY then
                        bestDistY = dist
                        bestSnapY = pair[2] - (pair[1] - dragB)
                        snapLineY = pair[2]
                        bestSnapYKey = key
                        bestSnapYEdge = idx
                    end
                end
            end
        end
    end

    -- Apply snap if within threshold (only move frames when snapping is enabled)
    local snappedX, snappedY = false, false

    if not snapDisabled then
        if bestDistX <= threshX and bestSnapX then
            local newCX = bestSnapX + (dragR - dragL) / 2
            local currentCY = (dragT + dragB) / 2
            local pw, ph = UIParent:GetWidth(), UIParent:GetHeight()
            local ox = math.floor(newCX - pw / 2 + 0.5)
            local oy = math.floor(currentCY - ph / 2 + 0.5)

            SetHandlePosition(handle, ox, oy)
            snappedX = true
        end

        if bestDistY <= threshY and bestSnapY then
            local cx, cy = GetHandleCenter(handle)
            if cx and cy then
                local newCY = bestSnapY + (dragT - dragB) / 2
                local pw, ph = UIParent:GetWidth(), UIParent:GetHeight()
                local ox = math.floor(cx - pw / 2 + 0.5)
                local oy = math.floor(newCY - ph / 2 + 0.5)

                SetHandlePosition(handle, ox, oy)
                snappedY = true
            end
        end

        -- Update hysteresis state for next frame
        snap.snappedX = snappedX
        snap.snappedY = snappedY
    end

    -- Edge proximity detection for anchoring (works even with snap disabled)
    local nearX = snappedX or (bestDistX <= activeThreshold)
    local nearY = snappedY or (bestDistY <= activeThreshold)

    -- Anchor-on-snap: compute anchor points when Shift is held and near an element
    -- For anchoring, require frames to be spatially close (not just edge-aligned on one axis)
    local anchorTargetKey = nil

    if shiftHeld then
        -- Build spatial proximity check: frames must overlap or be within threshold on BOTH axes
        local function isNearby(targetKey)
            local targetHandle = um._handles[targetKey]
            if not targetHandle then return false end
            local oL, oR, oT, oB = GetHandleEdges(targetHandle)
            if not oL then return false end
            -- Gap between frames on each axis (negative = overlapping)
            local gapX = math.max(dragL - oR, oL - dragR, 0)
            local gapY = math.max(dragB - oT, oB - dragT, 0)
            return gapX <= SNAP_THRESHOLD_ANCHOR and gapY <= SNAP_THRESHOLD_ANCHOR
        end

        -- Determine which element is the anchor target (prefer X, fall back to Y)
        -- Use nearX/nearY so anchoring works even with snap disabled
        if nearX and bestSnapXKey and isNearby(bestSnapXKey) then
            anchorTargetKey = bestSnapXKey
        end
        if nearY and bestSnapYKey and not anchorTargetKey and isNearby(bestSnapYKey) then
            anchorTargetKey = bestSnapYKey
        end
    end

    if shiftHeld and anchorTargetKey then
        -- Compute anchor points from edge pair indices
        local xSelf, xTarget = "CENTER", "CENTER"
        if nearX and bestSnapXKey == anchorTargetKey and bestSnapXEdge then
            local xPair = X_EDGE_ANCHORS[bestSnapXEdge]
            if xPair then
                xSelf, xTarget = xPair[1], xPair[2]
            end
        end

        local ySelf, yTarget = "CENTER", "CENTER"
        if nearY and bestSnapYKey == anchorTargetKey and bestSnapYEdge then
            local yPair = Y_EDGE_ANCHORS[bestSnapYEdge]
            if yPair then
                ySelf, yTarget = yPair[1], yPair[2]
            end
        end

        handle._snapAnchorKey = anchorTargetKey
        handle._snapAnchorPointSelf = CombineAnchorPoint(ySelf, xSelf)
        handle._snapAnchorPointTarget = CombineAnchorPoint(yTarget, xTarget)

        -- Show anchor indicator
        local targetHandle = um._handles[anchorTargetKey]
        if targetHandle then
            ShowAnchorLine(self, handle, targetHandle)
        end

        -- Bold gold border on dragging handle to indicate active anchoring
        if handle._border then
            if handle._border.SetLineSize then
                handle._border:SetLineSize(ANCHOR_BORDER_SIZE)
            end
            if handle._border.SetColor then
                handle._border:SetColor(ANCHOR_BORDER_R, ANCHOR_BORDER_G, ANCHOR_BORDER_B, 1)
            end
        end
        -- Also highlight the target handle border
        local targetHandle2 = um._handles[anchorTargetKey]
        if targetHandle2 and targetHandle2._border then
            if targetHandle2._border.SetLineSize then
                targetHandle2._border:SetLineSize(ANCHOR_BORDER_SIZE)
            end
            if targetHandle2._border.SetColor then
                targetHandle2._border:SetColor(ANCHOR_BORDER_R, ANCHOR_BORDER_G, ANCHOR_BORDER_B, 1)
            end
            handle._anchorHighlightTarget = anchorTargetKey
        end
    else
        -- Clear anchor state
        handle._snapAnchorKey = nil
        handle._snapAnchorPointSelf = nil
        handle._snapAnchorPointTarget = nil

        if self._anchorLine then
            self._anchorLine:Hide()
        end
        -- Restore border on dragging handle
        if handle._border then
            if handle._border.SetLineSize then
                handle._border:SetLineSize(1)
            end
            if handle._border.SetColor then
                if handle._selected then
                    handle._border:SetColor(1, 1, 1, 1)
                else
                    handle._border:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
                end
            end
        end
        -- Restore border on previously highlighted target
        if handle._anchorHighlightTarget then
            local prevTarget = um._handles[handle._anchorHighlightTarget]
            if prevTarget and prevTarget._border then
                if prevTarget._border.SetLineSize then
                    local isAnchored = prevTarget._isAnchored
                    prevTarget._border:SetLineSize(isAnchored and 2 or 1)
                end
                if prevTarget._border.SetColor then
                    if prevTarget._selected then
                        prevTarget._border:SetColor(1, 1, 1, 1)
                    else
                        prevTarget._border:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
                    end
                end
            end
            handle._anchorHighlightTarget = nil
        end
    end

    -- Show/hide snap guide lines
    if self._snapGuides then
        for _, line in ipairs(self._snapGuides) do
            line:Hide()
        end
    end
    if snappedX and snapLineX and self._snapGuides then
        local guide = self._snapGuides[1]
        guide:ClearAllPoints()
        guide:SetWidth(1)
        guide:SetPoint("TOP", UIParent, "BOTTOMLEFT", snapLineX, UIParent:GetHeight())
        guide:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", snapLineX, 0)
        guide:Show()
    end
    if snappedY and snapLineY and self._snapGuides then
        local guide = self._snapGuides[2]
        guide:ClearAllPoints()
        guide:SetHeight(1)
        guide:SetPoint("LEFT", UIParent, "BOTTOMLEFT", 0, snapLineY)
        guide:SetPoint("RIGHT", UIParent, "BOTTOMLEFT", UIParent:GetWidth(), snapLineY)
        guide:Show()
    end
end

---------------------------------------------------------------------------
-- ARROW KEY NUDGE HANDLER
---------------------------------------------------------------------------

CreateNudgeHandler = function(ui)
    local nudge = CreateFrame("Frame", "QUI_LayoutMode_Nudge", UIParent)
    nudge:SetFrameStrata("TOOLTIP")
    nudge:SetFrameLevel(998)
    nudge:SetSize(1, 1)
    nudge:SetPoint("CENTER")
    nudge:EnableKeyboard(false)
    nudge:SetPropagateKeyboardInput(true)
    nudge:Hide()

    -- Acceleration state
    nudge._heldKey = nil
    nudge._holdStart = 0
    nudge._lastNudge = 0
    nudge._nudgeInterval = NUDGE_MAX_INTERVAL

    nudge:SetScript("OnKeyDown", function(self, key)
        local um = ns.QUI_LayoutMode
        if not um then
            self:SetPropagateKeyboardInput(true)
            return
        end

        -- Escape always closes layout mode, regardless of selection
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            um:Close()
            return
        end

        -- Arrow key nudging requires a selected mover
        if not um._selectedKey then
            self:SetPropagateKeyboardInput(true)
            return
        end

        local dx, dy = 0, 0
        local isShift = IsShiftKeyDown()
        local step = isShift and 10 or 1

        if key == "UP" then
            dy = step
        elseif key == "DOWN" then
            dy = -step
        elseif key == "LEFT" then
            dx = -step
        elseif key == "RIGHT" then
            dx = step
        else
            self:SetPropagateKeyboardInput(true)
            return
        end

        local focusedFrame = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() or nil
        if focusedFrame and focusedFrame:IsObjectType("EditBox") then
            self:SetPropagateKeyboardInput(true)
            return
        end

        self:SetPropagateKeyboardInput(false)

        -- Apply immediate nudge
        um:NudgeMover(um._selectedKey, dx, dy)

        -- Start hold tracking for acceleration
        self._heldKey = key
        self._holdStart = GetTime()
        self._lastNudge = GetTime()
        self._nudgeInterval = NUDGE_MAX_INTERVAL
        self._nudgeDX = dx
        self._nudgeDY = dy

        -- Enable OnUpdate for repeat
        self:SetScript("OnUpdate", function(frame, elapsed)
            if not frame._heldKey then
                frame:SetScript("OnUpdate", nil)
                return
            end

            local now = GetTime()
            local holdTime = now - frame._holdStart

            -- Initial delay before repeat starts
            if holdTime < NUDGE_INITIAL_DELAY then return end

            -- Calculate interval with acceleration ramp
            local rampProgress = math.min((holdTime - NUDGE_INITIAL_DELAY) / NUDGE_RAMP_TIME, 1)
            frame._nudgeInterval = NUDGE_MAX_INTERVAL - (NUDGE_MAX_INTERVAL - NUDGE_MIN_INTERVAL) * rampProgress

            if now - frame._lastNudge >= frame._nudgeInterval then
                frame._lastNudge = now
                local umInner = ns.QUI_LayoutMode
                if umInner and umInner._selectedKey then
                    umInner:NudgeMover(umInner._selectedKey, frame._nudgeDX, frame._nudgeDY)
                end
            end
        end)
    end)

    nudge:SetScript("OnKeyUp", function(self, key)
        if self._heldKey == key then
            self._heldKey = nil
            self:SetScript("OnUpdate", nil)
        end
        self:SetPropagateKeyboardInput(true)
    end)

    ui._nudgeFrame = nudge
end

function QUI_LayoutMode_UI:OnSelectionChanged(key)
    -- Keyboard stays enabled for Escape handling; arrow nudging checks selection internally
end

---------------------------------------------------------------------------
-- HUD TOOLBAR
---------------------------------------------------------------------------

CreateToolbar = function(ui)
    local LCG = LibStub("LibCustomGlow-1.0", true)

    local PANEL_WIDTH = 140
    local TAB_WIDTH = 26
    local TAB_HEIGHT = 160
    local BTN_HEIGHT = 28
    local BTN_SPACING = 4
    local PANEL_PAD = 8

    -- Tab handle (always visible, docked to right edge)
    local tab = CreateFrame("Button", "QUI_LayoutMode_Tab", UIParent)
    tab:SetFrameStrata("TOOLTIP")
    tab:SetFrameLevel(200)
    tab:SetSize(TAB_WIDTH, TAB_HEIGHT)
    tab:SetPoint("RIGHT", UIParent, "RIGHT", 0, 0)
    tab:Hide()

    local tabBg = tab:CreateTexture(nil, "BACKGROUND")
    tabBg:SetAllPoints()
    tabBg:SetColorTexture(0.08, 0.08, 0.10, 0.85)

    local tabBorder = tab:CreateTexture(nil, "BORDER")
    tabBorder:SetPoint("TOPLEFT", 0, 0)
    tabBorder:SetPoint("BOTTOMLEFT", 0, 0)
    tabBorder:SetWidth(1)
    tabBorder:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.6)

    -- Accent glow stripe (bright inner edge)
    local tabGlow = tab:CreateTexture(nil, "ARTWORK")
    tabGlow:SetPoint("TOPLEFT", tabBorder, "TOPLEFT", 0, 0)
    tabGlow:SetPoint("BOTTOMLEFT", tabBorder, "BOTTOMLEFT", 0, 0)
    tabGlow:SetWidth(6)
    tabGlow:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.25)

    local tabChevron = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tabChevron:SetPoint("BOTTOM", tab, "BOTTOM", 0, 8)
    tabChevron:SetText("\194\171") -- «
    tabChevron:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)

    -- "Edit Mode" label on the tab (rotated look via vertical stacking)
    local tabLabel = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tabLabel:SetPoint("TOP", tab, "TOP", 0, -8)
    tabLabel:SetText("E\nD\nI\nT\n \nM\nO\nD\nE")
    tabLabel:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.7)
    tabLabel:SetJustifyH("CENTER")
    tabLabel:SetSpacing(0)

    -- Pulse animation on the glow stripe + border
    local pulseState = { elapsed = 0, min = 0.15, max = 0.45 }
    local pulseFrame = CreateFrame("Frame")
    pulseFrame:Hide()
    pulseFrame:SetScript("OnUpdate", function(self, dt)
        pulseState.elapsed = pulseState.elapsed + dt
        -- 2-second cycle
        local t = (math.sin(pulseState.elapsed * math.pi) + 1) / 2
        local alpha = pulseState.min + (pulseState.max - pulseState.min) * t
        tabGlow:SetAlpha(alpha)
        tabBorder:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.4 + 0.5 * t)
    end)

    -- Slide-out panel (hidden by default, appears to left of tab)
    local panel = CreateFrame("Frame", "QUI_LayoutMode_Toolbar", UIParent)
    panel:SetFrameStrata("TOOLTIP")
    panel:SetFrameLevel(200)
    panel:SetSize(PANEL_WIDTH, 10) -- height set dynamically
    panel:SetPoint("TOPRIGHT", tab, "TOPLEFT", 0, 0)
    panel:Hide()

    local panelBg = panel:CreateTexture(nil, "BACKGROUND")
    panelBg:SetAllPoints()
    panelBg:SetColorTexture(0.08, 0.08, 0.10, 0.92)

    -- Panel border
    local function MakeLine(p1, r1, p2, r2, isH)
        local line = panel:CreateTexture(nil, "BORDER")
        line:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.6)
        line:ClearAllPoints()
        line:SetPoint(p1, panel, r1)
        line:SetPoint(p2, panel, r2)
        if isH then line:SetHeight(1) else line:SetWidth(1) end
        return line
    end
    MakeLine("TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT", true)
    MakeLine("BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", true)
    local panelBorderLeft = MakeLine("TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT", false)
    local panelBorderRight = MakeLine("TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT", false)

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", panel, "TOP", 0, -PANEL_PAD)
    title:SetText("|cff60A5FAEdit Mode|r")
    title:SetTextColor(1, 1, 1, 1)

    -- Buttons (vertical stack)
    ui._toolbarButtons = {}
    local btnY = -(PANEL_PAD + 18)

    local function AddButton(label, onClick, colorR, colorG, colorB)
        local btn = CreateFrame("Button", nil, panel)
        btn:SetSize(PANEL_WIDTH - (PANEL_PAD * 2), BTN_HEIGHT)
        btn:SetPoint("TOP", panel, "TOP", 0, btnY)
        btnY = btnY - BTN_HEIGHT - BTN_SPACING

        local btnBg = btn:CreateTexture(nil, "BACKGROUND")
        btnBg:SetAllPoints()
        btnBg:SetColorTexture(colorR or 0.15, colorG or 0.15, colorB or 0.18, 0.9)
        btn._bg = btnBg
        btn._colorR = colorR or 0.15
        btn._colorG = colorG or 0.15
        btn._colorB = colorB or 0.18

        local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btnText:SetPoint("CENTER")
        btnText:SetText(label)
        btnText:SetTextColor(1, 1, 1, 1)
        btn._text = btnText

        btn:SetScript("OnClick", onClick)
        btn:SetScript("OnEnter", function(self)
            self._bg:SetColorTexture(self._colorR + 0.1, self._colorG + 0.1, self._colorB + 0.1, 1)
        end)
        btn:SetScript("OnLeave", function(self)
            self._bg:SetColorTexture(self._colorR, self._colorG, self._colorB, 0.9)
        end)

        ui._toolbarButtons[#ui._toolbarButtons + 1] = btn
        btn._label = label
        return btn
    end

    -- Frames drawer toggle
    ui._framesBtn = AddButton("Frames", function()
        ui:ToggleFramesDrawer()
    end)

    -- Snap toggle
    ui._snapBtn = AddButton("Snap: On", function()
        ui.snapEnabled = not ui.snapEnabled
        ui:_UpdateToolbarButtons()
        SavePersistedState(ui)
    end)

    -- Grid cycle
    ui._gridBtn = AddButton("Grid: Off", function()
        ui:CycleGrid()
        SavePersistedState(ui)
    end)

    -- Sync All Fonts & Textures
    AddButton("Sync Fonts", function()
        local core = ns.Addon
        if not core or not core.db or not core.db.profile then return end
        local profile = core.db.profile
        local general = profile.general
        if not general then return end
        local globalFont = general.font or "Quazii"
        local globalTexture = general.texture or "Quazii v5"
        local globalOutline = general.fontOutline or "OUTLINE"

        -- Recursive walk: set every "font" key to globalFont and "texture" key to globalTexture
        local function SyncTable(t, depth)
            if depth > 10 then return end
            for k, v in pairs(t) do
                if type(v) == "table" then
                    SyncTable(v, depth + 1)
                elseif k == "font" and type(v) == "string" then
                    t[k] = globalFont
                elseif k == "fontOutline" and type(v) == "string" then
                    t[k] = globalOutline
                elseif k == "texture" and type(v) == "string"
                    and v ~= "Interface\\RaidFrame\\Shield-Fill"
                    and v ~= "Interface\\Buttons\\WHITE8x8"
                    and not v:find("^Interface\\") then
                    t[k] = globalTexture
                end
            end
        end
        SyncTable(profile, 0)

        -- Refresh all modules
        if ns.RefreshAll then ns.RefreshAll()
        elseif _G.QUI_RefreshAll then _G.QUI_RefreshAll()
        end
        -- Refresh unit frames
        local uf = ns.QUI_UnitFrames
        if uf and uf.RefreshAll then uf:RefreshAll() end
        -- Refresh group frames
        if _G.QUI_RefreshGroupFrames then _G.QUI_RefreshGroupFrames() end
        -- Refresh CDM
        if _G.QUI_RefreshCDM then _G.QUI_RefreshCDM() end

        print("|cff34D399QUI:|r Synced all fonts to \"" .. globalFont .. "\" and textures to \"" .. globalTexture .. "\"")
    end, 0.15, 0.25, 0.4)

    -- QUI Settings button
    AddButton("QUI Settings", function()
        local gui = _G.QUI and _G.QUI.GUI
        if gui and gui.Toggle then
            gui:Toggle()
            if ui._collapseToolbar then ui._collapseToolbar() end
        end
    end, 0.15, 0.25, 0.4)

    -- Save button (green)
    ui._saveBtn = AddButton("Save & Close", function()
        local um = ns.QUI_LayoutMode
        if um then um:SaveAndClose() end
    end, 0.1, 0.5, 0.3)

    -- Discard button (red)
    ui._discardBtn = AddButton("Discard", function()
        local um = ns.QUI_LayoutMode
        if um then um:DiscardAndClose() end
    end, 0.5, 0.1, 0.1)

    -- Set panel height
    local panelHeight = math.abs(btnY) + PANEL_PAD
    panel:SetHeight(panelHeight)

    -- Side and position state (persisted)
    local docked = "RIGHT"  -- "LEFT" or "RIGHT"
    local offsetY = 0

    local function LoadTabPosition()
        local dbUM = GetLayoutModeDB()
        if dbUM then
            if dbUM.tabSide then docked = dbUM.tabSide end
            if dbUM.tabOffsetY then offsetY = dbUM.tabOffsetY end
        end
    end

    local function SaveTabPosition()
        local dbUM = GetLayoutModeDB()
        if dbUM then
            dbUM.tabSide = docked
            dbUM.tabOffsetY = offsetY
        end
    end

    local function ApplyTabPosition()
        tab:ClearAllPoints()
        panel:ClearAllPoints()
        tabBorder:ClearAllPoints()
        tabGlow:ClearAllPoints()
        tabChevron:ClearAllPoints()

        if docked == "LEFT" then
            tab:SetPoint("LEFT", UIParent, "LEFT", 0, offsetY)
            panel:SetPoint("TOPLEFT", tab, "TOPRIGHT", 0, 0)
            tabBorder:SetPoint("TOPRIGHT", tab, "TOPRIGHT", 0, 0)
            tabBorder:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
            tabGlow:SetPoint("TOPRIGHT", tabBorder, "TOPLEFT", 0, 0)
            tabGlow:SetPoint("BOTTOMRIGHT", tabBorder, "BOTTOMLEFT", 0, 0)
        else
            tab:SetPoint("RIGHT", UIParent, "RIGHT", 0, offsetY)
            panel:SetPoint("TOPRIGHT", tab, "TOPLEFT", 0, 0)
            tabBorder:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, 0)
            tabBorder:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
            tabGlow:SetPoint("TOPLEFT", tabBorder, "TOPRIGHT", 0, 0)
            tabGlow:SetPoint("BOTTOMLEFT", tabBorder, "BOTTOMRIGHT", 0, 0)
        end
        tabChevron:SetPoint("BOTTOM", tab, "BOTTOM", 0, 8)

        -- Show border on the screen-facing side of panel
        if docked == "LEFT" then
            panelBorderLeft:Hide()
            panelBorderRight:Show()
        else
            panelBorderLeft:Show()
            panelBorderRight:Hide()
        end
    end

    local function UpdateChevron(isExpanded)
        if docked == "LEFT" then
            tabChevron:SetText(isExpanded and "\194\171" or "\194\187") -- expanded: « (close left), collapsed: » (open right)
        else
            tabChevron:SetText(isExpanded and "\194\187" or "\194\171") -- expanded: » (close right), collapsed: « (open left)
        end
    end

    LoadTabPosition()
    ApplyTabPosition()

    -- Slide-out state
    local expanded = false
    local ANIM_DURATION = 0.18

    -- Animation state
    local animState = nil  -- { show, elapsed, duration, fromW, toW, fromA, toA }

    local animFrame = CreateFrame("Frame")
    animFrame:Hide()
    animFrame:SetScript("OnUpdate", function(self, elapsed)
        if not animState then self:Hide(); return end

        animState.elapsed = animState.elapsed + elapsed
        local t = animState.elapsed / animState.duration
        if t > 1 then t = 1 end

        -- Smoothstep easing
        local e = t * t * (3 - 2 * t)
        local w = animState.fromW + (animState.toW - animState.fromW) * e
        local a = animState.fromA + (animState.toA - animState.fromA) * e

        panel:SetWidth(w)
        panel:SetAlpha(a)

        -- Clip children visibility during close
        for _, btn in ipairs(ui._toolbarButtons) do
            btn:SetAlpha(a)
        end

        if t >= 1 then
            if animState.show then
                panel:SetWidth(PANEL_WIDTH)
                panel:SetAlpha(1)
                for _, btn in ipairs(ui._toolbarButtons) do btn:SetAlpha(1) end
            else
                panel:SetAlpha(0)
                panel:Hide()
                panel:SetWidth(PANEL_WIDTH)
                panel:SetAlpha(1)
                for _, btn in ipairs(ui._toolbarButtons) do btn:SetAlpha(1) end
                -- Also hide drawer when panel collapses
                if ui._drawer and ui._drawer:IsShown() then
                    ui._drawer:Hide()
                end
            end
            animState = nil
            self:Hide()
        end
    end)

    local function Expand()
        if expanded then return end
        expanded = true
        UpdateChevron(true)
        -- Start slide-in animation
        panel:SetWidth(2)
        panel:SetAlpha(0)
        panel:Show()
        animState = {
            show = true,
            elapsed = 0,
            duration = ANIM_DURATION,
            fromW = 2, toW = PANEL_WIDTH,
            fromA = 0, toA = 1,
        }
        animFrame:Show()
    end

    local function Collapse()
        if not expanded then return end
        expanded = false
        UpdateChevron(false)

        -- Hide settings panel when toolbar collapses
        local settings = ns.QUI_LayoutMode_Settings
        if settings and settings.Hide then settings:Hide() end

        -- Start slide-out animation
        animState = {
            show = false,
            elapsed = 0,
            duration = ANIM_DURATION,
            fromW = PANEL_WIDTH, toW = 2,
            fromA = 1, toA = 0,
        }
        animFrame:Show()
    end

    -- Tab dragging (vertical slide + side switching)
    local isDragging = false
    local dragStartY = 0
    local dragStartOffsetY = 0

    tab:RegisterForDrag("LeftButton")

    tab:SetScript("OnDragStart", function(self)
        isDragging = true
        tab._wasDragged = true
        local _, cursorY = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        dragStartY = cursorY / scale
        dragStartOffsetY = offsetY
    end)

    tab:SetScript("OnDragStop", function(self)
        isDragging = false

        -- Check if we should switch sides
        local cursorX = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        local screenW = UIParent:GetWidth()
        local cx = cursorX / scale

        local newSide = cx < (screenW / 2) and "LEFT" or "RIGHT"
        if newSide ~= docked then
            docked = newSide
            -- Re-anchor drawer to correct side
            if ui._drawer and ui._drawer:IsShown() then
                ui._drawer:ClearAllPoints()
                if docked == "LEFT" then
                    ui._drawer:SetPoint("TOPLEFT", panel, "TOPRIGHT", 2, 0)
                else
                    ui._drawer:SetPoint("TOPRIGHT", panel, "TOPLEFT", -2, 0)
                end
            end
        end

        -- Clamp offsetY
        local halfScreen = UIParent:GetHeight() / 2
        offsetY = math.max(-halfScreen + TAB_HEIGHT, math.min(halfScreen - TAB_HEIGHT, offsetY))

        ApplyTabPosition()
        UpdateChevron(expanded)
        SaveTabPosition()
    end)

    tab:SetScript("OnUpdate", function(self)
        if not isDragging then return end
        local _, cursorY = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        local cy = cursorY / scale
        offsetY = dragStartOffsetY + (cy - dragStartY)
        ApplyTabPosition()
    end)

    -- Tab: click to toggle (no hover expand/collapse)
    tab:SetScript("OnClick", function()
        if isDragging then return end
        if tab._wasDragged then tab._wasDragged = nil; return end
        if expanded then
            Collapse()
        else
            Expand()
        end
    end)
    tab:SetScript("OnEnter", function()
        if isDragging then return end
        tabBg:SetColorTexture(0.12, 0.12, 0.15, 0.95)
        tabLabel:SetAlpha(1)
    end)
    tab:SetScript("OnLeave", function()
        tabBg:SetColorTexture(0.08, 0.08, 0.10, 0.85)
        tabLabel:SetAlpha(0.7)
    end)

    -- No-ops for backward compatibility (drawer references these)
    ui._cancelCollapseTimer = function() end
    ui._startCollapseTimer = function() end

    -- Start/stop glow and pulse when tab is shown/hidden
    tab:SetScript("OnShow", function()
        pulseFrame:Show()
        if LCG then
            LCG.PixelGlow_Start(tab, {ACCENT_R, ACCENT_G, ACCENT_B, 0.7}, 12, 0.4, nil, 2, 0, 0, false, "_QUILayoutTab")
        end
    end)
    tab:SetScript("OnHide", function()
        pulseFrame:Hide()
        if LCG then
            LCG.PixelGlow_Stop(tab, "_QUILayoutTab")
        end
    end)

    -- Store references (toolbar = tab for show/hide, panel for anchoring)
    ui._toolbar = tab
    ui._toolbarPanel = panel
    ui._tabDocked = function() return docked end
    ui._expandToolbar = Expand
    ui._collapseToolbar = Collapse
    ui._resetToolbarState = function() expanded = false end
    ui:ApplyConfigPanelScale(panel)
end

function QUI_LayoutMode_UI:_UpdateToolbarButtons()
    if self._snapBtn then
        self._snapBtn._text:SetText(self.snapEnabled and "Snap: On" or "Snap: Off")
    end
    if self._gridBtn then
        local labels = { [0] = "Grid: Off", [1] = "Grid: Dim", [2] = "Grid: Bright" }
        self._gridBtn._text:SetText(labels[self.gridMode] or "Grid: Off")
    end
end

---------------------------------------------------------------------------
-- SAVE / DISCARD POPUP
---------------------------------------------------------------------------

CreateSaveDiscardPopup = function(ui)
    local popup = CreateFrame("Frame", "QUI_LayoutMode_Popup", UIParent)
    popup:SetFrameStrata("TOOLTIP")
    popup:SetFrameLevel(300)
    popup:SetSize(300, 110)
    popup:SetPoint("CENTER")
    popup:Hide()

    -- Background
    local bg = popup:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.08, 0.10, 0.95)

    -- Border
    local function MakePopupLine(p1, r1, p2, r2, isH)
        local line = popup:CreateTexture(nil, "BORDER")
        line:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.8)
        line:ClearAllPoints()
        line:SetPoint(p1, popup, r1)
        line:SetPoint(p2, popup, r2)
        if isH then line:SetHeight(1) else line:SetWidth(1) end
    end
    MakePopupLine("TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT", true)
    MakePopupLine("BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", true)
    MakePopupLine("TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT", false)
    MakePopupLine("TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT", false)

    -- Title
    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", popup, "TOP", 0, -14)
    title:SetText("Unsaved Changes")
    title:SetTextColor(1, 1, 1, 1)

    -- Buttons
    local function MakePopupButton(label, width, anchorTo, anchorPoint, ox, oy, onClick, r, g, b)
        local btn = CreateFrame("Button", nil, popup)
        btn:SetSize(width, 28)
        btn:SetPoint("TOP", anchorTo, anchorPoint, ox, oy)

        local btnBg = btn:CreateTexture(nil, "BACKGROUND")
        btnBg:SetAllPoints()
        btnBg:SetColorTexture(r, g, b, 0.9)
        btn._bg = btnBg

        local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btnText:SetPoint("CENTER")
        btnText:SetText(label)
        btnText:SetTextColor(1, 1, 1, 1)

        btn:SetScript("OnClick", onClick)
        btn:SetScript("OnEnter", function(self)
            self._bg:SetColorTexture(r + 0.1, g + 0.1, b + 0.1, 1)
        end)
        btn:SetScript("OnLeave", function(self)
            self._bg:SetColorTexture(r, g, b, 0.9)
        end)
        return btn
    end

    -- Save & Exit (green)
    MakePopupButton("Save & Exit", 130, popup, "TOP", -70, -44, function()
        popup:Hide()
        local um = ns.QUI_LayoutMode
        if um then um:SaveAndClose() end
    end, 0.1, 0.5, 0.3)

    -- Exit Without Saving (red)
    MakePopupButton("Exit Without Saving", 130, popup, "TOP", 70, -44, function()
        popup:Hide()
        local um = ns.QUI_LayoutMode
        if um then um:DiscardAndClose() end
    end, 0.5, 0.1, 0.1)

    -- Cancel (gray)
    MakePopupButton("Cancel", 100, popup, "TOP", 0, -78, function()
        popup:Hide()
    end, 0.2, 0.2, 0.2)

    ui._popup = popup
end

function QUI_LayoutMode_UI:ShowSaveDiscardPopup()
    if not self._initialized then
        self:_Initialize()
    end
    if self._popup then
        self:ApplyConfigPanelScale(self._popup)
        self._popup:Show()
    end
end

---------------------------------------------------------------------------
-- FRAMES DRAWER
-- Slide-down panel listing all registered elements with enable/disable.
---------------------------------------------------------------------------

local DRAWER_WIDTH = 420
local DRAWER_ROW_HEIGHT = 24
local DRAWER_GROUP_HEIGHT = 22
local DRAWER_MAX_HEIGHT = 500
local DRAWER_PADDING = 8
local DRAWER_CONTROLS_HEIGHT = 24

CreateFramesDrawer = function(ui)
    local drawer = CreateFrame("Frame", "QUI_LayoutMode_Drawer", UIParent)
    drawer:SetFrameStrata("TOOLTIP")
    drawer:SetFrameLevel(201)
    drawer:SetWidth(DRAWER_WIDTH)
    drawer:SetClampedToScreen(true)
    drawer:EnableMouse(true)
    drawer:Hide()

    -- Keep slide-out panel open while drawer is hovered
    drawer:SetScript("OnEnter", function()
        if ui._cancelCollapseTimer then ui._cancelCollapseTimer() end
    end)
    drawer:SetScript("OnLeave", function()
        if ui._startCollapseTimer then ui._startCollapseTimer() end
    end)

    -- Background
    local bg = drawer:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.067, 0.094, 0.153, 0.97)

    -- Border
    local function MakeDrawerLine(p1, r1, p2, r2, isH)
        local line = drawer:CreateTexture(nil, "BORDER")
        line:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.6)
        line:ClearAllPoints()
        line:SetPoint(p1, drawer, r1)
        line:SetPoint(p2, drawer, r2)
        if isH then line:SetHeight(1) else line:SetWidth(1) end
    end
    MakeDrawerLine("TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT", true)
    MakeDrawerLine("BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", true)
    MakeDrawerLine("TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT", false)
    MakeDrawerLine("TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT", false)

    local function CreateDrawerActionButton(parent, text, width)
        local button = CreateFrame("Button", nil, parent)
        button:SetSize(width, 18)

        local bgTex = button:CreateTexture(nil, "BACKGROUND")
        bgTex:SetAllPoints()
        bgTex:SetColorTexture(0.2, 0.2, 0.2, 0.9)
        button._bg = bgTex

        local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("CENTER")
        label:SetText(text)
        label:SetTextColor(0.8, 0.82, 0.85, 1)
        button._label = label

        button:SetScript("OnEnter", function(self)
            self._bg:SetColorTexture(0.3, 0.3, 0.3, 1)
            self._label:SetTextColor(1, 1, 1, 1)
        end)
        button:SetScript("OnLeave", function(self)
            self._bg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
            self._label:SetTextColor(0.8, 0.82, 0.85, 1)
        end)

        return button
    end

    -- Search box (top of drawer). Reuses QUI.GUI:CreateSearchBox.
    local searchContainer = CreateFrame("Frame", nil, drawer)
    searchContainer:SetPoint("TOPLEFT", drawer, "TOPLEFT", DRAWER_PADDING, -DRAWER_PADDING)
    searchContainer:SetPoint("TOPRIGHT", drawer, "TOPRIGHT", -DRAWER_PADDING, -DRAWER_PADDING)
    searchContainer:SetHeight(28)

    local searchBox
    do
        local GUI = _G.QUI and _G.QUI.GUI
        if GUI and GUI.CreateSearchBox then
            searchBox = GUI:CreateSearchBox(searchContainer, "Search frames…")
            searchBox:SetAllPoints(searchContainer)
            searchBox.onSearch = function(text)
                drawer._searchFilter = (text or ""):lower()
                if ui._RebuildDrawer then ui:_RebuildDrawer() end
            end
            searchBox.onClear = function()
                drawer._searchFilter = ""
                if ui._RebuildDrawer then ui:_RebuildDrawer() end
            end
        end
    end

    drawer._searchContainer = searchContainer
    drawer._searchBox = searchBox
    drawer._searchFilter = ""

    local controls = CreateFrame("Frame", nil, drawer)
    controls:SetPoint("TOPLEFT", searchContainer, "BOTTOMLEFT", 0, -4)
    controls:SetPoint("TOPRIGHT", searchContainer, "BOTTOMRIGHT", 0, -4)
    controls:SetHeight(DRAWER_CONTROLS_HEIGHT)

    local controlsLabel = controls:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    controlsLabel:SetPoint("LEFT", 4, 0)
    controlsLabel:SetText("Layer Visibility")
    controlsLabel:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)

    local hideAllBtn = CreateDrawerActionButton(controls, "HIDE ALL", 74)
    hideAllBtn:SetPoint("RIGHT", controls, "RIGHT", -2, 0)

    local showAllBtn = CreateDrawerActionButton(controls, "SHOW ALL", 74)
    showAllBtn:SetPoint("RIGHT", hideAllBtn, "LEFT", -6, 0)

    local function UpdateGlobalButtonsVisual()
        local um = ns.QUI_LayoutMode
        if not um then return end
        local anyShown, anyHidden = false, false
        for _, key in ipairs(um._elementOrder or {}) do
            if um:IsElementEnabled(key) then
                if um:IsHandleShown(key) then
                    anyShown = true
                else
                    anyHidden = true
                end
            end
        end

        if anyShown and not anyHidden then
            showAllBtn._bg:SetColorTexture(0.15, 0.35, 0.55, 1)
            showAllBtn._label:SetTextColor(1, 1, 1, 1)
            hideAllBtn._bg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
            hideAllBtn._label:SetTextColor(0.8, 0.82, 0.85, 1)
        elseif anyHidden and not anyShown then
            hideAllBtn._bg:SetColorTexture(0.45, 0.16, 0.16, 1)
            hideAllBtn._label:SetTextColor(1, 1, 1, 1)
            showAllBtn._bg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
            showAllBtn._label:SetTextColor(0.8, 0.82, 0.85, 1)
        else
            showAllBtn._bg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
            showAllBtn._label:SetTextColor(0.8, 0.82, 0.85, 1)
            hideAllBtn._bg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
            hideAllBtn._label:SetTextColor(0.8, 0.82, 0.85, 1)
        end
    end
    drawer._updateGlobalButtons = UpdateGlobalButtonsVisual

    showAllBtn:SetScript("OnClick", function()
        local um = ns.QUI_LayoutMode
        if not um then return end
        um:SetAllHandlePreviewsVisible(true)
        if drawer._refreshLayerButtons then
            drawer._refreshLayerButtons()
        end
    end)
    showAllBtn:HookScript("OnEnter", function(self)
        self._bg:SetColorTexture(0.15, 0.35, 0.55, 1)
        self._label:SetTextColor(1, 1, 1, 1)
    end)
    showAllBtn:SetScript("OnLeave", function()
        UpdateGlobalButtonsVisual()
    end)

    hideAllBtn:SetScript("OnClick", function()
        local um = ns.QUI_LayoutMode
        if not um then return end
        um:SetAllHandlePreviewsVisible(false)
        if drawer._refreshLayerButtons then
            drawer._refreshLayerButtons()
        end
    end)
    hideAllBtn:HookScript("OnEnter", function(self)
        self._bg:SetColorTexture(0.45, 0.16, 0.16, 1)
        self._label:SetTextColor(1, 1, 1, 1)
    end)
    hideAllBtn:SetScript("OnLeave", function()
        UpdateGlobalButtonsVisual()
    end)

    drawer._controls = controls

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, drawer, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", controls, "BOTTOMLEFT", 0, -6)
    scrollFrame:SetPoint("BOTTOMRIGHT", -(DRAWER_PADDING + 20), DRAWER_PADDING)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(DRAWER_WIDTH - (DRAWER_PADDING * 2) - 20)
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)

    -- Style scrollbar
    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then
        scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 2, -16)
        scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 2, 16)
        local thumb = scrollBar:GetThumbTexture()
        if thumb then thumb:SetColorTexture(0.35, 0.45, 0.5, 0.8) end
        local scrollUp = scrollBar.ScrollUpButton or scrollBar.Back
        local scrollDown = scrollBar.ScrollDownButton or scrollBar.Forward
        if scrollUp then scrollUp:Hide(); scrollUp:SetAlpha(0) end
        if scrollDown then scrollDown:Hide(); scrollDown:SetAlpha(0) end
    end

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local ok, cur = pcall(self.GetVerticalScroll, self)
        if not ok then return end
        local ok2, max = pcall(self.GetVerticalScrollRange, self)
        if not ok2 then return end
        local newScroll = math.max(0, math.min((cur or 0) - (delta * 40), max or 0))
        pcall(self.SetVerticalScroll, self, newScroll)
    end)

    drawer._scrollFrame = scrollFrame
    drawer._content = content
    drawer._rows = {}

    drawer:HookScript("OnHide", function()
        if drawer._searchBox and drawer._searchBox:GetText() ~= "" then
            drawer._searchBox:SetText("")
            drawer._searchBox:ClearFocus()
        end
        drawer._searchFilter = ""
        drawer._activeFilter = nil
    end)

    ui._drawer = drawer
    ui:ApplyConfigPanelScale(drawer)
end

--- Rebuild the drawer content from current element list.
function QUI_LayoutMode_UI:_RebuildDrawer()
    local drawer = self._drawer
    if not drawer then return end

    local content = drawer._content
    local um = ns.QUI_LayoutMode
    if not um then return end

    -- Clear old rows
    for _, row in ipairs(drawer._rows) do
        row:Hide()
        row:SetParent(nil)
    end
    drawer._rows = {}

    -- Persist collapsed state across rebuilds (default collapsed)
    if not drawer._groupCollapsed then
        drawer._groupCollapsed = {}
    end
    local groupCollapsed = drawer._groupCollapsed

    local contentWidth = content:GetWidth()

    -- First pass: collect elements into ordered groups (filtered by search input)
    local searchFilter = drawer._searchFilter or ""
    drawer._activeFilter = (searchFilter ~= "")

    local groupOrder = {}
    local groupElements = {}
    for _, key in ipairs(um._elementOrder) do
        local def = um._elements[key]
        if not def then break end
        local group = def.group or "Other"

        local include = true
        if searchFilter ~= "" then
            local label = (def.label or key or ""):lower()
            local groupLower = group:lower()
            include = (label:find(searchFilter, 1, true) ~= nil)
                or (groupLower:find(searchFilter, 1, true) ~= nil)
        end

        if include then
            if not groupElements[group] then
                groupElements[group] = {}
                groupOrder[#groupOrder + 1] = group
            end
            groupElements[group][#groupElements[group] + 1] = { key = key, def = def }
        end
    end

    -- Second pass: build headers and rows
    local allRows = {}   -- { {frame=, group=, isHeader=bool} }
    local layerRows = {}

    for _, group in ipairs(groupOrder) do
        -- Default to collapsed
        if groupCollapsed[group] == nil then
            groupCollapsed[group] = true
        end

        local isCollapsed = groupCollapsed[group]
        if drawer._activeFilter then
            isCollapsed = false
        end

        -- Group header (clickable)
        local header = CreateFrame("Button", nil, content)
        header:SetSize(contentWidth, DRAWER_GROUP_HEIGHT)
        drawer._rows[#drawer._rows + 1] = header

        local chevron = UIKit and UIKit.CreateChevronCaret and UIKit.CreateChevronCaret(header, {
            point = "LEFT",
            relativeTo = header,
            relativePoint = "LEFT",
            xPixels = 4,
            yPixels = 0,
            sizePixels = 10,
            lineWidthPixels = 6,
            lineHeightPixels = 1,
            expanded = not isCollapsed,
            collapsedDirection = "right",
            r = ACCENT_R,
            g = ACCENT_G,
            b = ACCENT_B,
            a = 1,
        }) or header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        if not (UIKit and UIKit.CreateChevronCaret) then
            chevron:SetPoint("LEFT", 4, 0)
            chevron:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
            chevron:SetText(isCollapsed and ">" or "v")
        end
        header._chevron = chevron

        local headerText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        headerText:SetPoint("LEFT", chevron, "RIGHT", 4, 0)
        headerText:SetText(group)
        headerText:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)

        local headerLine = header:CreateTexture(nil, "ARTWORK")
        headerLine:SetPoint("BOTTOMLEFT", 0, 0)
        headerLine:SetPoint("BOTTOMRIGHT", 0, 0)
        headerLine:SetHeight(1)
        headerLine:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.3)

        header:SetScript("OnEnter", function()
            headerText:SetTextColor(1, 1, 1, 1)
            if UIKit and UIKit.SetChevronCaretColor then
                UIKit.SetChevronCaretColor(chevron, 1, 1, 1, 1)
            else
                chevron:SetTextColor(1, 1, 1, 1)
            end
        end)
        header:SetScript("OnLeave", function()
            headerText:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
            if UIKit and UIKit.SetChevronCaretColor then
                UIKit.SetChevronCaretColor(chevron, ACCENT_R, ACCENT_G, ACCENT_B, 1)
            else
                chevron:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
            end
        end)
        header:SetScript("OnClick", function()
            -- While the search filter is active, the chevron is forced expanded
            -- and clicking it is a no-op. Otherwise we'd silently mutate saved
            -- collapsed state behind a chevron whose visual ignores it.
            if drawer._activeFilter then return end
            groupCollapsed[group] = not groupCollapsed[group]
            self:_RelayoutDrawer()
        end)

        allRows[#allRows + 1] = { frame = header, group = group, isHeader = true }

        -- Element rows for this group
        for _, elem in ipairs(groupElements[group]) do
            local key = elem.key
            local def = elem.def

            local row = CreateFrame("Button", nil, content)
            row:SetSize(contentWidth, DRAWER_ROW_HEIGHT)
            drawer._rows[#drawer._rows + 1] = row

            -- Row background (hover effect)
            local rowBg = row:CreateTexture(nil, "BACKGROUND")
            rowBg:SetAllPoints()
            rowBg:SetColorTexture(0.15, 0.17, 0.22, 0)
            row._bg = rowBg

            -- Label
            local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("LEFT", 12, 0)
            label:SetText(def.label or key)

            local isEnabled = um:IsElementEnabled(key)
            local hasToggle = def.setEnabled ~= nil

            if isEnabled then
                label:SetTextColor(0.953, 0.957, 0.965, 1)
            else
                label:SetTextColor(0.4, 0.42, 0.45, 1)
            end

            -- Enable/disable toggle (only for elements with setEnabled)
            if hasToggle then
                local toggleBtn = CreateFrame("Button", nil, row)
                toggleBtn:SetSize(36, 18)
                toggleBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)

                local toggleBg = toggleBtn:CreateTexture(nil, "BACKGROUND")
                toggleBg:SetAllPoints()
                toggleBtn._bg = toggleBg

                local toggleText = toggleBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                toggleText:SetPoint("CENTER")
                toggleBtn._text = toggleText

                local function UpdateToggleVisual()
                    local en = um:IsElementEnabled(key)
                    if en then
                        toggleBg:SetColorTexture(0.1, 0.5, 0.3, 0.9)
                        toggleText:SetText("ON")
                        toggleText:SetTextColor(1, 1, 1, 1)
                        label:SetTextColor(0.953, 0.957, 0.965, 1)
                    else
                        toggleBg:SetColorTexture(0.3, 0.12, 0.12, 0.9)
                        toggleText:SetText("OFF")
                        toggleText:SetTextColor(0.6, 0.6, 0.6, 1)
                        label:SetTextColor(0.4, 0.42, 0.45, 1)
                    end
                end

                toggleBtn:SetScript("OnClick", function()
                    local newState = not um:IsElementEnabled(key)
                    if newState and um.ClearHiddenState then
                        um:ClearHiddenState(key)
                    end
                    um:SetElementEnabled(key, newState)
                    UpdateToggleVisual()
                    if drawer._refreshLayerButtons then
                        drawer._refreshLayerButtons()
                    end
                end)

                toggleBtn:SetScript("OnEnter", function(self)
                    local en = um:IsElementEnabled(key)
                    if en then
                        self._bg:SetColorTexture(0.15, 0.6, 0.35, 1)
                    else
                        self._bg:SetColorTexture(0.4, 0.15, 0.15, 1)
                    end
                end)

                toggleBtn:SetScript("OnLeave", function()
                    UpdateToggleVisual()
                end)

                UpdateToggleVisual()
                row._toggle = toggleBtn
            end

            -- Layer visibility buttons (to left of ON/OFF)
            -- Skip for master toggle rows (noHandle) — they have nothing to show/solo/reset.
            if not def.noHandle then
                local showBtn = CreateFrame("Button", nil, row)
                showBtn:SetSize(40, 18)
                if row._toggle then
                    showBtn:SetPoint("RIGHT", row._toggle, "LEFT", -4, 0)
                else
                    showBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                end

                local showBg = showBtn:CreateTexture(nil, "BACKGROUND")
                showBg:SetAllPoints()
                showBtn._bg = showBg

                local showText = showBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                showText:SetPoint("CENTER")
                showBtn._text = showText

                local soloBtn, soloBg, soloText
                local resetBtn, resetBg, resetText  -- forward refs for dimming

                local function UpdateShowVisual()
                    local en = um:IsElementEnabled(key)
                    local shown = um:IsHandleShown(key)
                    if not en then
                        showBg:SetColorTexture(0.15, 0.15, 0.15, 0.5)
                        showText:SetText("SHOW")
                        showText:SetTextColor(0.35, 0.35, 0.35, 1)
                        showBtn:EnableMouse(false)
                        if soloBtn then
                            soloBg:SetColorTexture(0.15, 0.15, 0.15, 0.5)
                            soloText:SetTextColor(0.35, 0.35, 0.35, 1)
                            soloBtn:EnableMouse(false)
                        end
                        if resetBtn then
                            resetBg:SetColorTexture(0.15, 0.15, 0.15, 0.5)
                            resetText:SetTextColor(0.35, 0.35, 0.35, 1)
                            resetBtn:EnableMouse(false)
                        end
                    else
                        showBtn:EnableMouse(true)
                        if soloBtn then soloBtn:EnableMouse(true) end
                        if resetBtn then resetBtn:EnableMouse(true) end
                        if shown then
                            showBg:SetColorTexture(0.15, 0.35, 0.55, 0.9)
                            showText:SetText("HIDE")
                            showText:SetTextColor(1, 1, 1, 1)
                        else
                            showBg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
                            showText:SetText("SHOW")
                            showText:SetTextColor(0.6, 0.6, 0.6, 1)
                        end
                        if soloBtn then
                            soloBg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
                            soloText:SetTextColor(0.6, 0.6, 0.6, 1)
                        end
                        if resetBtn then
                            resetBg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
                            resetText:SetTextColor(0.6, 0.6, 0.6, 1)
                        end
                    end
                end

                local function UpdateSoloVisual()
                    if not soloBtn then return end
                    local en = um:IsElementEnabled(key)
                    if not en then
                        soloBg:SetColorTexture(0.15, 0.15, 0.15, 0.5)
                        soloText:SetTextColor(0.35, 0.35, 0.35, 1)
                        soloBtn:EnableMouse(false)
                        return
                    end

                    soloBtn:EnableMouse(true)
                    if um.IsHandleSolo and um:IsHandleSolo(key) then
                        soloBg:SetColorTexture(0.45, 0.27, 0.08, 0.95)
                        soloText:SetTextColor(1, 0.88, 0.55, 1)
                    else
                        soloBg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
                        soloText:SetTextColor(0.6, 0.6, 0.6, 1)
                    end
                end

                showBtn:SetScript("OnClick", function()
                    um:ToggleHandlePreview(key)
                    if drawer._refreshLayerButtons then
                        drawer._refreshLayerButtons()
                    end
                end)

                showBtn:SetScript("OnEnter", function(self)
                    if not um:IsElementEnabled(key) then return end
                    local shown = um:IsHandleShown(key)
                    if shown then
                        self._bg:SetColorTexture(0.2, 0.45, 0.65, 1)
                    else
                        self._bg:SetColorTexture(0.3, 0.3, 0.3, 1)
                    end
                end)

                showBtn:SetScript("OnLeave", function()
                    if drawer._refreshLayerButtons then
                        drawer._refreshLayerButtons()
                    end
                end)

                row._showBtn = showBtn
                row._updateShowVisual = UpdateShowVisual

                soloBtn = CreateFrame("Button", nil, row)
                soloBtn:SetSize(40, 18)
                soloBtn:SetPoint("RIGHT", showBtn, "LEFT", -4, 0)

                soloBg = soloBtn:CreateTexture(nil, "BACKGROUND")
                soloBg:SetAllPoints()
                soloBtn._bg = soloBg

                soloText = soloBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                soloText:SetPoint("CENTER")
                soloText:SetText("SOLO")
                soloBtn._text = soloText

                soloBtn:SetScript("OnClick", function()
                    um:SoloHandlePreview(key)
                    if drawer._refreshLayerButtons then
                        drawer._refreshLayerButtons()
                    end
                end)

                soloBtn:SetScript("OnEnter", function(self)
                    if not um:IsElementEnabled(key) then return end
                    if um.IsHandleSolo and um:IsHandleSolo(key) then
                        self._bg:SetColorTexture(0.52, 0.31, 0.1, 1)
                    else
                        self._bg:SetColorTexture(0.35, 0.25, 0.15, 1)
                    end
                    soloText:SetTextColor(1, 0.88, 0.55, 1)
                end)

                soloBtn:SetScript("OnLeave", function()
                    if drawer._refreshLayerButtons then
                        drawer._refreshLayerButtons()
                    end
                end)

                row._soloBtn = soloBtn
                row._updateSoloVisual = UpdateSoloVisual

                -- Reset button (to left of Solo)
                resetBtn = CreateFrame("Button", nil, row)
                resetBtn:SetSize(44, 18)
                resetBtn:SetPoint("RIGHT", soloBtn, "LEFT", -4, 0)

                resetBg = resetBtn:CreateTexture(nil, "BACKGROUND")
                resetBg:SetAllPoints()
                resetBg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
                resetBtn._bg = resetBg

                resetText = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                resetText:SetPoint("CENTER")
                resetText:SetText("RESET")
                resetText:SetTextColor(0.6, 0.6, 0.6, 1)

                resetBtn:SetScript("OnClick", function()
                    um:ResetToCenter(key)
                    if drawer._refreshLayerButtons then
                        drawer._refreshLayerButtons()
                    end
                end)

                resetBtn:SetScript("OnEnter", function(self)
                    if not um:IsElementEnabled(key) then return end
                    self._bg:SetColorTexture(0.35, 0.25, 0.15, 1)
                    resetText:SetTextColor(1, 0.8, 0.4, 1)
                end)

                resetBtn:SetScript("OnLeave", function()
                    if drawer._refreshLayerButtons then
                        drawer._refreshLayerButtons()
                    end
                end)

                row._resetBtn = resetBtn

                -- Initial visual state (after all buttons created)
                UpdateShowVisual()
                UpdateSoloVisual()
            end

            -- Click row to select frame
            row:SetScript("OnClick", function()
                if um:IsElementEnabled(key) and um._handles[key] then
                    um:SelectMover(key)
                end
            end)

            row:SetScript("OnEnter", function(self)
                self._bg:SetColorTexture(0.15, 0.17, 0.22, 0.8)
            end)

            row:SetScript("OnLeave", function(self)
                self._bg:SetColorTexture(0.15, 0.17, 0.22, 0)
            end)

            allRows[#allRows + 1] = { frame = row, group = group, isHeader = false }
            layerRows[#layerRows + 1] = row
        end

        -- "Add Datapanel" button in Display group
        if group == "Display" then
            local addRow = CreateFrame("Button", nil, content)
            addRow:SetSize(contentWidth, DRAWER_ROW_HEIGHT)
            drawer._rows[#drawer._rows + 1] = addRow

            local addBg = addRow:CreateTexture(nil, "BACKGROUND")
            addBg:SetAllPoints()
            addBg:SetColorTexture(0.15, 0.17, 0.22, 0)

            local addLabel = addRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            addLabel:SetPoint("LEFT", 12, 0)
            addLabel:SetText("|cff34D399+ Add Datapanel|r")

            addRow:SetScript("OnClick", function()
                local QUICore = ns.Addon
                if not QUICore or not QUICore.db or not QUICore.db.profile then return end
                local dtDB = QUICore.db.profile.quiDatatexts
                if not dtDB then
                    QUICore.db.profile.quiDatatexts = { panels = {} }
                    dtDB = QUICore.db.profile.quiDatatexts
                end
                if not dtDB.panels then dtDB.panels = {} end

                -- Generate unique ID
                local newID = "panel" .. (#dtDB.panels + 1)
                local existing = {}
                for _, pc in ipairs(dtDB.panels) do existing[pc.id] = true end
                while existing[newID] do
                    newID = newID .. "_"
                end

                -- Add panel config
                local newConfig = {
                    id = newID,
                    name = "Datapanel " .. (#dtDB.panels + 1),
                    enabled = true,
                    width = 300,
                    height = 22,
                    numSlots = 3,
                    slots = {},
                    bgOpacity = 50,
                    borderSize = 2,
                    borderColor = {0, 0, 0, 1},
                    fontSize = 11,
                    position = {"CENTER", "CENTER", 0, 0},
                }
                table.insert(dtDB.panels, newConfig)

                -- Refresh datapanels to create the frame
                if QUICore.Datapanels then
                    QUICore.Datapanels:RefreshAll()
                end

                -- Register with layout mode and rebuild
                local um2 = ns.QUI_LayoutMode
                if um2 then
                    local elementKey = "datapanel_" .. newID
                    local Datapanels = QUICore.Datapanels

                    um2:RegisterElement({
                        key = elementKey,
                        label = newConfig.name,
                        group = "Display",
                        order = 10 + #dtDB.panels,
                        isOwned = true,
                        getFrame = function() return Datapanels and Datapanels.activePanels[newID] end,
                        isEnabled = function()
                            -- Check config enabled, not IsShown (panel hides when no slots assigned)
                            for _, pc in ipairs(dtDB.panels) do
                                if pc.id == newID then return pc.enabled end
                            end
                            return false
                        end,
                        setEnabled = function(val)
                            local p = Datapanels and Datapanels.activePanels[newID]
                            if p then
                                p.config.enabled = val
                                if val then p:Show() else p:Hide() end
                            end
                            for _, pc in ipairs(dtDB.panels) do
                                if pc.id == newID then pc.enabled = val; break end
                            end
                        end,
                        setGameplayHidden = function(hide)
                            local p = Datapanels and Datapanels.activePanels[newID]
                            if not p then return end
                            if hide then p:Hide() else p:Show() end
                        end,
                    })

                    -- Register as anchor target so other frames can anchor to this panel
                    local displayName = newConfig.name
                    if ns.FRAME_ANCHOR_INFO then
                        ns.FRAME_ANCHOR_INFO[elementKey] = {
                            displayName = displayName,
                            category = "Display",
                            order = 10 + #dtDB.panels,
                        }
                    end
                    local anchoring = ns.QUI_Anchoring
                    if anchoring and anchoring.RegisterAnchorTarget then
                        local newPanel2 = Datapanels and Datapanels.activePanels[newID]
                        if newPanel2 then
                            anchoring:RegisterAnchorTarget(elementKey, newPanel2, {
                                displayName = displayName,
                                category = "Display",
                                order = 10 + #dtDB.panels,
                            })
                        end
                    end

                    -- Register shared settings lookup for the new panel
                    if Datapanels.RegisterSettingsLookup then
                        Datapanels.RegisterSettingsLookup(newID, elementKey)
                    end

                    -- Ensure the frame is shown for layout mode even without datatexts
                    local newPanel = Datapanels and Datapanels.activePanels[newID]
                    if newPanel then
                        newPanel:Show()
                    end

                    -- Activate the new element (creates handle and shows it)
                    um2:ActivateElement(elementKey)

                    -- Rebuild drawer to include the new entry
                    local uiSelf = ns.QUI_LayoutMode_UI
                    if uiSelf and uiSelf._RebuildDrawer then
                        uiSelf:_RebuildDrawer()
                    end

                    -- Select the new panel
                    um2:SelectMover(elementKey)
                end
            end)

            addRow:SetScript("OnEnter", function(self)
                addBg:SetColorTexture(0.15, 0.17, 0.22, 0.8)
            end)
            addRow:SetScript("OnLeave", function(self)
                addBg:SetColorTexture(0.15, 0.17, 0.22, 0)
            end)

            allRows[#allRows + 1] = { frame = addRow, group = group, isHeader = false }
        end

        -- "+ Add CDM Container" button in the shared CDM / tracker group
        if group == "Cooldown Manager & Custom Tracker Bars" then
            local addTrackerRow = CreateFrame("Button", nil, content)
            addTrackerRow:SetSize(contentWidth, DRAWER_ROW_HEIGHT)
            drawer._rows[#drawer._rows + 1] = addTrackerRow

            local addTrackerBg = addTrackerRow:CreateTexture(nil, "BACKGROUND")
            addTrackerBg:SetAllPoints()
            addTrackerBg:SetColorTexture(0.15, 0.17, 0.22, 0)

            local addTrackerLabel = addTrackerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            addTrackerLabel:SetPoint("LEFT", 12, 0)
            addTrackerLabel:SetText("|cff34D399+ Add CDM Container|r")

            addTrackerRow:SetScript("OnClick", function()
                if InCombatLockdown() then return end
                if _G.QUI_ShowNewCDMContainerPopup then
                    _G.QUI_ShowNewCDMContainerPopup()
                end
            end)

            addTrackerRow:SetScript("OnEnter", function()
                addTrackerBg:SetColorTexture(0.15, 0.17, 0.22, 0.8)
            end)
            addTrackerRow:SetScript("OnLeave", function()
                addTrackerBg:SetColorTexture(0.15, 0.17, 0.22, 0)
            end)

            allRows[#allRows + 1] = { frame = addTrackerRow, group = group, isHeader = false }
        end
    end

    -- Empty-state placeholder (only when filter is active and zero rows survive)
    if not drawer._emptyStateText then
        local fs = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOP", content, "TOP", 0, -16)
        fs:SetTextColor(0.55, 0.58, 0.62, 1)
        fs:SetText("No frames match")
        fs:Hide()
        drawer._emptyStateText = fs
    end
    if drawer._activeFilter and #groupOrder == 0 then
        drawer._emptyStateText:Show()
    else
        drawer._emptyStateText:Hide()
    end

    drawer._allRows = allRows
    drawer._layerRows = layerRows
    drawer._refreshLayerButtons = function()
        if drawer._updateGlobalButtons then
            drawer._updateGlobalButtons()
        end
        for _, layerRow in ipairs(drawer._layerRows or {}) do
            if layerRow._updateShowVisual then
                layerRow._updateShowVisual()
            end
            if layerRow._updateSoloVisual then
                layerRow._updateSoloVisual()
            end
        end
    end
    drawer._refreshLayerButtons()
    self:_RelayoutDrawer()
end

function QUI_LayoutMode_UI:_RelayoutDrawer()
    local drawer = self._drawer
    if not drawer or not drawer._allRows then return end

    local savedCollapsed = drawer._groupCollapsed or {}
    local activeFilter = drawer._activeFilter
    local function isCollapsed(group)
        if activeFilter then return false end
        return savedCollapsed[group]
    end
    local y = 0

    for _, entry in ipairs(drawer._allRows) do
        if entry.isHeader then
            -- Headers always visible; update chevron
            entry.frame:ClearAllPoints()
            entry.frame:SetPoint("TOPLEFT", 0, y)
            entry.frame:Show()
            y = y - DRAWER_GROUP_HEIGHT

            -- Update chevron text
            local chevron = entry.frame._chevron or select(1, entry.frame:GetRegions())
            local collapsed = isCollapsed(entry.group)
            if UIKit and UIKit.SetChevronCaretExpanded and chevron and chevron.GetObjectType and chevron:GetObjectType() == "Frame" then
                UIKit.SetChevronCaretExpanded(chevron, not collapsed)
            elseif chevron and chevron.SetText then
                chevron:SetText(collapsed and ">" or "v")
            end
        else
            -- Element rows: show/hide based on (effective) group collapsed state
            if isCollapsed(entry.group) then
                entry.frame:Hide()
            else
                entry.frame:ClearAllPoints()
                entry.frame:SetPoint("TOPLEFT", 0, y)
                entry.frame:Show()
                y = y - DRAWER_ROW_HEIGHT
            end
        end
    end

    -- Resize content and drawer
    local totalHeight = math.abs(y) + DRAWER_PADDING
    drawer._content:SetHeight(totalHeight)

    local drawerHeight = math.min(totalHeight + (DRAWER_PADDING * 2), DRAWER_MAX_HEIGHT)
    drawer:SetHeight(drawerHeight)
end

function QUI_LayoutMode_UI:ToggleFramesDrawer()
    if not self._drawer then return end

    if self._drawer:IsShown() then
        self._drawer:Hide()
    else
        self:_RebuildDrawer()
        -- Position adjacent to the slide-out panel
        local anchor = self._toolbarPanel or self._toolbar
        if anchor then
            self._drawer:ClearAllPoints()
            local side = self._tabDocked and self._tabDocked() or "RIGHT"
            if side == "LEFT" then
                self._drawer:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 2, 0)
            else
                self._drawer:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -2, 0)
            end
        end
        self._drawer:Show()
    end
end
