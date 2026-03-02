--[[
    QUI Anchoring Module
    Unified anchoring system for castbars, unit frames, and custom frames
    Supports 9-point anchoring with X/Y offsets and dynamic anchor target registration
]]

local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local UIKit = ns.UIKit
local nsHelpers = ns.Helpers

---------------------------------------------------------------------------
-- MODULE TABLE
---------------------------------------------------------------------------
local QUI_Anchoring = {}
ns.QUI_Anchoring = QUI_Anchoring

-- Anchor target registry: { name = { frame = frame, options = {...} } }
QUI_Anchoring.anchorTargets = {}

-- Category registry: { categoryName = { order = number } }
QUI_Anchoring.categories = {}

-- Anchored frame registry: { frame = { anchorTarget = name, anchorPoint = point, offsetX = x, offsetY = y, parentFrame = frame } }
QUI_Anchoring.anchoredFrames = {}

-- Frames with active anchoring overrides — module positioning is blocked for these
QUI_Anchoring.overriddenFrames = {}

local Helpers = {}

-- Forward-declared tables (populated later, referenced by ResolveFrameForKey)
local CDM_LOGICAL_SIZE_KEYS = {}

-- Edit Mode hook state (declared early so ApplyFrameAnchor can set the guard)
local _editModeReapplyGuard = false  -- prevents recursive reapply during QUI's own SetPoint
local _editModeTickerSilent = false  -- suppress per-tick debug after first pass

-- Debug helper — only prints when /qui debug is active
local function AnchorDebug(msg)
    if QUI and QUI.DebugPrint then
        QUI:DebugPrint("|cffFFAA00Anchor|r " .. msg)
    end
end

-- Position-match check: returns true if the frame already has exactly one
-- anchor point matching the desired values.  Used by the Edit Mode ticker
-- to skip ClearAllPoints+SetPoint when Blizzard hasn't moved the frame,
-- preventing visual flashing on objective tracker, minimap children, etc.
local function FrameAlreadyAtPosition(frame, pt, relativeTo, relPt, x, y)
    if not frame or not frame.GetNumPoints then return false end
    if frame:GetNumPoints() ~= 1 then return false end
    local cp, crt, crp, cx, cy = frame:GetPoint(1)
    if cp ~= pt or crt ~= relativeTo or crp ~= relPt then return false end
    return math.abs((cx or 0) - (x or 0)) < 0.1 and math.abs((cy or 0) - (y or 0)) < 0.1
end

---------------------------------------------------------------------------
-- SECURE TAINT CLEANER for Edit Mode system frames
-- When addon code calls ClearAllPoints/SetPoint on Blizzard Edit Mode
-- system frames (action bars, etc.), the frame's position data becomes
-- tainted.  This taint persists and causes ADDON_ACTION_BLOCKED when
-- Edit Mode's secureexecuterange calls SetPointBase during combat.
--
-- Solution: Track positions of overridden Edit Mode system frames, then
-- use a SecureHandlerStateTemplate to re-stamp those same positions
-- through secure code, clearing the taint.  Two triggers:
--   1. Combat enter (state driver) — clears taint before combat APIs run.
--   2. Edit Mode exit (hooksecurefunc on ExitEditMode) — clears taint
--      synchronously before Blizzard's UpdateLayoutInfo/InitSystemAnchors
--      re-layouts, which is the primary scenario that hits the block.
-- Normal (non-combat) positioning still uses the direct pcall(SetPoint)
-- path — only the taint is cleaned up.
---------------------------------------------------------------------------
local secureTaintCleaner = CreateFrame("Frame", "QUI_SecureTaintCleaner", UIParent, "SecureHandlerStateTemplate")

-- Shared secure snippet: re-stamp all tracked positions through secure code
-- to clear taint left by addon-side ClearAllPoints/SetPoint calls.
local SECURE_RESTAMP_SNIPPET = [[
    local count = self:GetAttribute("frameCount") or 0
    for i = 1, count do
        local bar = self:GetFrameRef("bar" .. i)
        local parent = self:GetFrameRef("parent" .. i)
        if bar and parent then
            local point = self:GetAttribute("point" .. i) or "CENTER"
            local relPoint = self:GetAttribute("relPoint" .. i) or "CENTER"
            local offsetX = self:GetAttribute("offsetX" .. i) or 0
            local offsetY = self:GetAttribute("offsetY" .. i) or 0
            bar:ClearAllPoints()
            bar:SetPoint(point, parent, relPoint, offsetX, offsetY)
        end
    end
]]

RegisterStateDriver(secureTaintCleaner, "combat", "[combat]1;0")
secureTaintCleaner:SetAttribute("_onstate-combat", [[
    if newstate ~= "1" then return end
]] .. SECURE_RESTAMP_SNIPPET)

-- Allow manual trigger via SetAttribute("clean-now", value).
-- hooksecurefunc on ExitEditMode (below) uses this to clean taint
-- synchronously before Blizzard's InitSystemAnchors re-layouts.
secureTaintCleaner:SetAttribute("_onattributechanged", [[
    if name == "clean-now" then
]] .. SECURE_RESTAMP_SNIPPET .. [[
    end
]])

-- Hook EditModeManagerFrame.ExitEditMode to clean taint before
-- Blizzard's UpdateLayoutInfo -> InitSystemAnchors hits tainted
-- SetPointBase.  hooksecurefunc fires right after ExitEditMode
-- returns, and SetAttribute triggers _onattributechanged synchronously
-- in secure context — so positions are re-stamped before any
-- subsequent layout re-apply reads the anchor data.
if EditModeManagerFrame then
    hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
        if not InCombatLockdown() then
            secureTaintCleaner:SetAttribute("clean-now", GetTime())
        end
    end)
end

local _trackedSecureFrames = {}  -- frame -> index
local _trackedCount = 0

-- Track (or update) an Edit Mode system frame's position for secure
-- re-stamping on combat enter.  Must be called outside combat.
local function TrackSecureFramePosition(frame, parentFrame, point, relPoint, offsetX, offsetY)
    if InCombatLockdown() then return end

    local idx = _trackedSecureFrames[frame]
    if not idx then
        _trackedCount = _trackedCount + 1
        idx = _trackedCount
        _trackedSecureFrames[frame] = idx
        secureTaintCleaner:SetAttribute("frameCount", _trackedCount)
    end

    secureTaintCleaner:SetFrameRef("bar" .. idx, frame)
    secureTaintCleaner:SetFrameRef("parent" .. idx, parentFrame)
    secureTaintCleaner:SetAttribute("point" .. idx, point)
    secureTaintCleaner:SetAttribute("relPoint" .. idx, relPoint)
    secureTaintCleaner:SetAttribute("offsetX" .. idx, offsetX)
    secureTaintCleaner:SetAttribute("offsetY" .. idx, offsetY)
end

---------------------------------------------------------------------------
-- SETUP HELPERS
---------------------------------------------------------------------------
function QUI_Anchoring:SetHelpers(helpers)
    Helpers = helpers or {}
end

-- Helper function wrappers (with fallbacks)
local function Scale(x, frame)
    return Helpers.Scale and Helpers.Scale(x, frame) or (QUICore and QUICore.Scale and QUICore:Scale(x, frame) or x)
end

local function PixelRound(frame, value)
    if value == 0 then return 0 end
    if QUICore and QUICore.PixelRound then
        return QUICore:PixelRound(value, frame)
    end
    return value
end

-- frame param reserved for future frame-aware border calculations
local function GetBorderAdjustment(frame, anchorPoint, borderSize)
    if not borderSize or borderSize == 0 then return 0, 0 end
    
    local adjX, adjY = 0, 0
    if anchorPoint == "TOPLEFT" then
        adjX = borderSize
        adjY = -borderSize
    elseif anchorPoint == "TOP" then
        adjY = -borderSize
    elseif anchorPoint == "TOPRIGHT" then
        adjX = -borderSize
        adjY = -borderSize
    elseif anchorPoint == "LEFT" then
        adjX = borderSize
    elseif anchorPoint == "RIGHT" then
        adjX = -borderSize
    elseif anchorPoint == "BOTTOMLEFT" then
        adjX = borderSize
        adjY = borderSize
    elseif anchorPoint == "BOTTOM" then
        adjY = borderSize
    elseif anchorPoint == "BOTTOMRIGHT" then
        adjX = -borderSize
        adjY = borderSize
    end
    return adjX, adjY
end

---------------------------------------------------------------------------
-- ANCHOR TARGET REGISTRY
---------------------------------------------------------------------------
-- Register a frame as an anchor target with a custom name
-- options can include: displayName, category, categoryOrder (for category sorting), order (for item sorting within category), and other custom properties
function QUI_Anchoring:RegisterAnchorTarget(name, frame, options)
    if not name or not frame then
        return false
    end
    
    options = options or {}
    self.anchorTargets[name] = {
        frame = frame,
        options = options
    }
    
    -- Register category with its order if provided
    local category = options.category
    if category then
        if not self.categories[category] then
            self.categories[category] = {
                order = options.categoryOrder or 999
            }
        end
    end
    
    return true
end

-- Unregister an anchor target
function QUI_Anchoring:UnregisterAnchorTarget(name)
    if not name then return false end
    self.anchorTargets[name] = nil
    return true
end

-- Get an anchor target by name
function QUI_Anchoring:GetAnchorTarget(name)
    if not name then return nil end
    
    -- Check registry only
    local registered = self.anchorTargets[name]
    if registered then
        return registered.frame
    end
    
    return nil
end

-- Get list of registered anchor targets for options dropdowns
-- Parameters:
--   include: optional table of anchor values to include (if provided, only these are included)
--   exclude: optional table of anchor values to exclude (if provided, these are filtered out)
--   excludeSelf: optional anchor target name to exclude (prevents self-anchoring)
-- Returns array of {value = name, text = displayName}
function QUI_Anchoring:GetAnchorTargetList(include, exclude, excludeSelf)
    include = include or {}
    exclude = exclude or {}
    
    -- Convert include/exclude to lookup tables for faster checking
    local includeLookup = {}
    local excludeLookup = {}
    
    if type(include) == "table" and #include > 0 then
        for _, value in ipairs(include) do
            includeLookup[value] = true
        end
    elseif type(include) == "table" then
        -- Empty table means include all
        includeLookup = nil
    end
    
    if type(exclude) == "table" then
        for _, value in ipairs(exclude) do
            excludeLookup[value] = true
        end
    end
    
    -- Helper to check if an anchor should be included
    local function ShouldInclude(value)
        -- Check exclude first
        if excludeLookup[value] then
            return false
        end
        -- Check excludeSelf (prevents self-anchoring)
        if excludeSelf and value == excludeSelf then
            return false
        end
        -- If include list is provided, check it
        if includeLookup then
            return includeLookup[value] == true
        end
        -- Otherwise include all
        return true
    end
    
    local list = {}
    
    -- Add special anchor targets (always check include/exclude)
    if ShouldInclude("disabled") then
        table.insert(list, {value = "disabled", text = "Disabled"})
    end
    if ShouldInclude("screen") then
        table.insert(list, {value = "screen", text = "Screen Center"})
    end
    
    -- Group registered anchor targets by category
    local categorized = {}
    local uncategorized = {}
    
    for name, data in pairs(self.anchorTargets) do
        if ShouldInclude(name) then
            local displayName = data.options and data.options.displayName or name
            -- Capitalize first letter and add spaces before capitals
            displayName = displayName:gsub("^%l", string.upper)
            displayName = displayName:gsub("([a-z])([A-Z])", "%1 %2")
            
            local category = data.options and data.options.category
            local order = data.options and data.options.order or 999
            local item = {value = name, text = displayName, category = category, order = order}
            
            if category then
                if not categorized[category] then
                    categorized[category] = {}
                end
                table.insert(categorized[category], item)
            else
                table.insert(uncategorized, item)
            end
        end
    end
    
    -- Sort categories by order (from category registry), then alphabetically
    local sortedCategories = {}
    for category, items in pairs(categorized) do
        local categoryInfo = self.categories[category] or {}
        local categoryOrder = categoryInfo.order or 999
        table.insert(sortedCategories, {name = category, order = categoryOrder})
        -- Sort items within category by order, then by text
        table.sort(items, function(a, b)
            if a.order ~= b.order then
                return a.order < b.order
            end
            return a.text < b.text
        end)
    end
    table.sort(sortedCategories, function(a, b)
        if a.order ~= b.order then
            return a.order < b.order
        end
        return a.name < b.name
    end)
    
    -- Sort uncategorized items
    table.sort(uncategorized, function(a, b)
        if a.order ~= b.order then
            return a.order < b.order
        end
        return a.text < b.text
    end)
    
    -- Build final list: special values, then categorized items, then uncategorized
    -- Add categorized items with headers
    for _, catInfo in ipairs(sortedCategories) do
        local category = catInfo.name
        -- Add category header (non-clickable, value is nil)
        table.insert(list, {value = nil, text = category, isHeader = true})
        -- Add items in this category
        for _, item in ipairs(categorized[category]) do
            table.insert(list, item)
        end
    end
    
    -- Add uncategorized items (only if there are any)
    if #uncategorized > 0 then
        -- Only add "Other" header if we have categorized items above
        if #sortedCategories > 0 then
            table.insert(list, {value = nil, text = "Other", isHeader = true})
        end
        for _, item in ipairs(uncategorized) do
            table.insert(list, item)
        end
    end
    
    return list
end

---------------------------------------------------------------------------
-- ANCHOR DIMENSIONS HELPER
---------------------------------------------------------------------------
-- Get anchor frame dimensions and position data
function QUI_Anchoring:GetAnchorDimensions(anchorFrame, anchorTargetName)
    if not anchorFrame then return nil end
    
    local registered = self.anchorTargets[anchorTargetName]
    local options = registered and registered.options or {}
    
    local width, height
    if options.customWidth then
        width = type(options.customWidth) == "function" and options.customWidth(anchorFrame) or options.customWidth
    else
        width = anchorFrame:GetWidth()
    end
    
    if options.customHeight then
        height = type(options.customHeight) == "function" and options.customHeight(anchorFrame) or options.customHeight
    else
        height = anchorFrame:GetHeight()
    end
    
    -- Special handling for CDM viewers (backward compatibility)
    if anchorTargetName == "essential" or anchorTargetName == "utility" then
        local vs = _G.QUI_GetCDMViewerState and _G.QUI_GetCDMViewerState(anchorFrame)
        width = (vs and vs.row1Width) or width
        height = (vs and vs.totalHeight) or height
    end
    
    local centerX, centerY = anchorFrame:GetCenter()
    if not centerX or not centerY then return nil end
    
    return {
        width = width,
        height = height,
        centerX = centerX,
        centerY = centerY,
        top = centerY + (height / 2),
        bottom = centerY - (height / 2),
        left = centerX - (width / 2),
        right = centerX + (width / 2),
    }
end

---------------------------------------------------------------------------
-- BORDER HELPER
---------------------------------------------------------------------------
-- Get border size from a frame's backdrop
local function GetBorderSize(frame)
    if not frame or not frame.GetBackdrop then
        return 0
    end
    
    local backdrop = frame:GetBackdrop()
    if not backdrop or not backdrop.edgeSize then
        return 0
    end
    
    return backdrop.edgeSize or 0
end

---------------------------------------------------------------------------
-- 9-POINT ANCHORING API
---------------------------------------------------------------------------
-- Valid anchor points
local VALID_ANCHOR_POINTS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

-- Position a frame using 9-point anchoring system
-- Supports explicit dual anchor points or auto-detection based on source and target anchor point alignment
-- Parameters:
--   frame: Frame to position
--   anchorTarget: Name of anchor target or "none"/"disabled"/"screen"/"unitframe"
--   anchorPoint: Primary source anchor point (TOPLEFT, TOP, TOPRIGHT, LEFT, CENTER, RIGHT, BOTTOMLEFT, BOTTOM, BOTTOMRIGHT)
--   offsetX: X offset in pixels (this IS the gap/padding - maintains spacing when anchor target changes size)
--   offsetY: Y offset in pixels (this IS the gap/padding - maintains spacing when anchor target changes size)
--   parentFrame: Optional parent frame (for "unitframe" anchor type)
--   options: Optional table with:
--     - targetAnchorPoint: Primary target anchor point (defaults to source anchorPoint)
--     - sourceAnchorPoint2: Secondary source anchor point for dual anchors (e.g., "TOPRIGHT")
--     - targetAnchorPoint2: Secondary target anchor point for dual anchors (e.g., "BOTTOMRIGHT")
function QUI_Anchoring:PositionFrame(frame, anchorTarget, anchorPoint, offsetX, offsetY, parentFrame, options)
    if not frame then return false end

    -- Skip module positioning if this frame has an active anchoring override
    if self.overriddenFrames[frame] then return true end

    -- Defer positioning if in combat or secure context to avoid taint
    if InCombatLockdown() then
        pendingAnchoredFrameUpdateAfterCombat = true
        return false
    end
    
    options = options or {}
    offsetX = offsetX or 0
    offsetY = offsetY or 0
    
    -- Validate anchor point
    anchorPoint = anchorPoint or "CENTER"
    if not VALID_ANCHOR_POINTS[anchorPoint] then
        anchorPoint = "CENTER"
    end
    
    -- Get target anchor point from options (defaults to source anchor point for backward compatibility)
    local targetAnchorPoint = options.targetAnchorPoint or anchorPoint
    if not VALID_ANCHOR_POINTS[targetAnchorPoint] then
        targetAnchorPoint = anchorPoint
    end
    
    -- Check if explicit dual anchor points are provided
    local sourceAnchorPoint2 = options.sourceAnchorPoint2
    local targetAnchorPoint2 = options.targetAnchorPoint2
    local useExplicitDualAnchors = sourceAnchorPoint2 and targetAnchorPoint2 and
                                   VALID_ANCHOR_POINTS[sourceAnchorPoint2] and
                                   VALID_ANCHOR_POINTS[targetAnchorPoint2]
    
    -- Safely clear points (use pcall to handle secure frames)
    local success = pcall(function()
        frame:ClearAllPoints()
    end)
    if not success then
        -- Frame is secure/managed - defer the call
        C_Timer.After(0, function()
            if InCombatLockdown() then
                pendingAnchoredFrameUpdateAfterCombat = true
                return
            end
            if frame and frame.ClearAllPoints then
                pcall(frame.ClearAllPoints, frame)
            end
        end)
        return false
    end

    -- Handle "none", "disabled", or "screen" anchor targets (absolute positioning to screen center)
    -- "none" is kept for backward compatibility with existing castbar settings
    if not anchorTarget or anchorTarget == "none" or anchorTarget == "disabled" or anchorTarget == "screen" then
        frame:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
        return true
    end
    
    -- Handle "unitframe" anchor type (special case for castbars)
    if anchorTarget == "unitframe" and parentFrame then
        -- Get border sizes for pixel-perfect positioning
        local sourceBorderSize = GetBorderSize(frame)
        local targetBorderSize = GetBorderSize(parentFrame)
        
        -- Calculate border adjustments
        local sourceAdjX, sourceAdjY = GetBorderAdjustment(frame, anchorPoint, sourceBorderSize)
        local targetAdjX, targetAdjY = GetBorderAdjustment(frame, targetAnchorPoint, targetBorderSize)
        local netAdjX = targetAdjX - sourceAdjX
        local netAdjY = targetAdjY - sourceAdjY
        
        local scaledOffsetX = PixelRound(frame, Scale(offsetX, frame) + netAdjX)
        local scaledOffsetY = PixelRound(frame, Scale(offsetY, frame) + netAdjY)

        -- Use explicit dual anchors if provided
        if useExplicitDualAnchors then
            local sourceAdjX2, sourceAdjY2 = GetBorderAdjustment(frame, sourceAnchorPoint2, sourceBorderSize)
            local targetAdjX2, targetAdjY2 = GetBorderAdjustment(frame, targetAnchorPoint2, targetBorderSize)
            local netAdjX2 = targetAdjX2 - sourceAdjX2
            local netAdjY2 = targetAdjY2 - sourceAdjY2

            local scaledOffsetX2 = PixelRound(frame, Scale(offsetX, frame) + netAdjX2)
            local scaledOffsetY2 = PixelRound(frame, Scale(offsetY, frame) + netAdjY2)

            frame:SetPoint(anchorPoint, parentFrame, targetAnchorPoint, scaledOffsetX, scaledOffsetY)
            frame:SetPoint(sourceAnchorPoint2, parentFrame, targetAnchorPoint2, scaledOffsetX2, scaledOffsetY2)
            return true
        end

        -- Use source and target anchor points for single anchor positioning
        frame:SetPoint(anchorPoint, parentFrame, targetAnchorPoint, scaledOffsetX, scaledOffsetY)
        return true
    end
    
    -- Get anchor target frame
    local anchorFrame = self:GetAnchorTarget(anchorTarget)
    if not anchorFrame then
        return false
    end
    
    if not anchorFrame:IsShown() then
        return false
    end
    
    -- Get border sizes for pixel-perfect positioning
    local sourceBorderSize = GetBorderSize(frame)
    local targetBorderSize = GetBorderSize(anchorFrame)
    
    -- Calculate border adjustments
    local sourceAdjX, sourceAdjY = GetBorderAdjustment(frame, anchorPoint, sourceBorderSize)
    local targetAdjX, targetAdjY = GetBorderAdjustment(frame, targetAnchorPoint, targetBorderSize)
    local netAdjX = targetAdjX - sourceAdjX
    local netAdjY = targetAdjY - sourceAdjY
    
    -- offsetX and offsetY already provide the gap/padding functionality
    -- When the anchor target changes size, the offset maintains that gap
    local scaledOffsetX = PixelRound(frame, Scale(offsetX, frame) + netAdjX)
    local scaledOffsetY = PixelRound(frame, Scale(offsetY, frame) + netAdjY)

    -- Use explicit dual anchors if provided
    if useExplicitDualAnchors then
        local sourceAdjX2, sourceAdjY2 = GetBorderAdjustment(frame, sourceAnchorPoint2, sourceBorderSize)
        local targetAdjX2, targetAdjY2 = GetBorderAdjustment(frame, targetAnchorPoint2, targetBorderSize)
        local netAdjX2 = targetAdjX2 - sourceAdjX2
        local netAdjY2 = targetAdjY2 - sourceAdjY2

        -- offsetX and offsetY already provide the gap/padding for both anchor points
        local scaledOffsetX2 = PixelRound(frame, Scale(offsetX, frame) + netAdjX2)
        local scaledOffsetY2 = PixelRound(frame, Scale(offsetY, frame) + netAdjY2)

        frame:SetPoint(anchorPoint, anchorFrame, targetAnchorPoint, scaledOffsetX, scaledOffsetY)
        frame:SetPoint(sourceAnchorPoint2, anchorFrame, targetAnchorPoint2, scaledOffsetX2, scaledOffsetY2)
        return true
    end

    -- For single anchor point positioning, use direct SetPoint with source and target anchor points
    frame:SetPoint(anchorPoint, anchorFrame, targetAnchorPoint, scaledOffsetX, scaledOffsetY)
    
    return true
end

---------------------------------------------------------------------------
-- ANCHORED FRAME REGISTRATION
---------------------------------------------------------------------------
-- Get anchor target name for a given frame (reverse lookup)
function QUI_Anchoring:GetAnchorTargetName(frame)
    if not frame then return nil end
    
    for name, data in pairs(self.anchorTargets) do
        if data.frame == frame then
            return name
        end
    end
    
    return nil
end

-- Check for circular anchoring dependencies
-- This works at registration time by checking the CURRENT state of already-registered frames.
-- Example: If Frame A → Frame B → Frame C are already registered, and Frame C tries to anchor to Frame A,
-- we follow the chain: Frame C → Frame A → Frame B → Frame C, detecting the cycle.
-- Returns true if circular dependency would be created, false otherwise
function QUI_Anchoring:CheckCircularDependency(frame, anchorTarget)
    if not frame or not anchorTarget then return false end
    
    -- Skip check for special anchor targets
    if anchorTarget == "disabled" or anchorTarget == "screen" or anchorTarget == "none" then
        return false
    end
    
    -- Get the anchor target frame
    local targetFrame = self:GetAnchorTarget(anchorTarget)
    if not targetFrame then return false end
    
    -- Check if the target frame is the same as the source frame (self-anchoring)
    if targetFrame == frame then
        return true -- Self-anchoring detected
    end
    
    -- Check if target frame is anchored to anything (must be already registered)
    local targetConfig = self.anchoredFrames[targetFrame]
    if not targetConfig then 
        -- Target frame is not yet anchored to anything, so no cycle possible
        return false 
    end
    
    -- Recursively follow the anchor chain to see if we eventually loop back to the starting frame
    -- visited tracks frames we've seen to prevent infinite loops in case of malformed data
    local visited = {}
    local function CheckCycle(currentFrame, startFrame)
        -- If we've reached the starting frame again, we have a cycle
        if currentFrame == startFrame then
            return true -- Cycle detected
        end
        
        -- If we've already visited this frame in this traversal, skip it (prevents infinite loops)
        if visited[currentFrame] then
            return false -- Already visited, no cycle through this path
        end
        visited[currentFrame] = true
        
        -- Get the anchor configuration for the current frame
        local config = self.anchoredFrames[currentFrame]
        if not config then 
            -- This frame is not anchored to anything, chain ends here, no cycle
            return false 
        end
        
        -- Skip special anchor targets (they don't create cycles)
        if config.anchorTarget == "disabled" or config.anchorTarget == "screen" or config.anchorTarget == "none" then
            return false
        end
        
        -- Get the next frame in the chain
        local nextTargetFrame = self:GetAnchorTarget(config.anchorTarget)
        if not nextTargetFrame then 
            -- Anchor target doesn't exist or isn't registered, chain ends, no cycle
            return false 
        end
        
        -- Recursively check the next frame in the chain
        return CheckCycle(nextTargetFrame, startFrame)
    end
    
    -- Start checking from the target frame, looking for a path back to the starting frame
    return CheckCycle(targetFrame, frame)
end

-- Register a frame for automatic updates when anchor targets move
function QUI_Anchoring:RegisterAnchoredFrame(frame, config)
    if not frame or not config then return false end
    
    -- Check for circular dependencies
    if config.anchorTarget and config.anchorTarget ~= "disabled" and config.anchorTarget ~= "screen" and config.anchorTarget ~= "none" then
        if self:CheckCircularDependency(frame, config.anchorTarget) then
            -- Circular dependency detected - don't register
            return false
        end
    end
    
    -- Store anchors array if provided, otherwise use legacy anchorPoint/targetAnchorPoint
    local anchors = config.anchors
    if not anchors or #anchors == 0 then
        -- Backward compatibility: convert old format to new anchors array
        local sourceAnchorPoint = config.anchorPoint or "CENTER"
        local targetAnchorPoint = config.targetAnchorPoint or sourceAnchorPoint
        anchors = {
            {source = sourceAnchorPoint, target = targetAnchorPoint}
        }
    end
    
    self.anchoredFrames[frame] = {
        anchorTarget = config.anchorTarget,
        anchors = anchors,
        offsetX = config.offsetX or 0,  -- X offset (gap/padding) - maintains spacing when anchor target changes size
        offsetY = config.offsetY or 0,  -- Y offset (gap/padding) - maintains spacing when anchor target changes size
        parentFrame = config.parentFrame,
    }

    -- Skip immediate positioning if this frame has an active anchoring override
    if self.overriddenFrames[frame] then return true end

    -- Position immediately using multi-anchor system
    -- Defer if in combat or secure context
    if InCombatLockdown() then
        pendingAnchoredFrameUpdateAfterCombat = true
        return true
    end
    
    -- Safely clear points (use pcall to handle secure frames)
    local success = pcall(function()
        frame:ClearAllPoints()
    end)
    if not success then
        -- Frame is secure/managed - defer the call
        C_Timer.After(0, function()
            if InCombatLockdown() then
                pendingAnchoredFrameUpdateAfterCombat = true
                return
            end
            if frame and frame.ClearAllPoints then
                pcall(frame.ClearAllPoints, frame)
                -- Retry registration after clearing
                C_Timer.After(0.1, function()
                    self:RegisterAnchoredFrame(frame, config)
                end)
            end
        end)
        return true
    end
    
    if #anchors == 1 then
        -- Single anchor point
        local anchorPair = anchors[1]
        local source = anchorPair.source or "CENTER"
        local target = anchorPair.target or "CENTER"
        
        self:PositionFrame(
            frame,
            config.anchorTarget,
            source,
            config.offsetX or 0,
            config.offsetY or 0,
            config.parentFrame,
            {
                targetAnchorPoint = target,
            }
        )
    elseif #anchors == 2 then
        -- Dual anchor points
        local anchorPair1 = anchors[1]
        local anchorPair2 = anchors[2]
        local source1 = anchorPair1.source or "CENTER"
        local target1 = anchorPair1.target or "CENTER"
        local source2 = anchorPair2.source or "CENTER"
        local target2 = anchorPair2.target or "CENTER"
        
        self:PositionFrame(
            frame,
            config.anchorTarget,
            source1,
            config.offsetX or 0,
            config.offsetY or 0,
            config.parentFrame,
            {
                targetAnchorPoint = target1,
                sourceAnchorPoint2 = source2,
                targetAnchorPoint2 = target2,
            }
        )
    end
    
    -- Re-register state drivers for unit frames after positioning (ClearAllPoints breaks them)
    if frame._quiReRegisterStateDriver then
        C_Timer.After(0, function()
            if frame and frame._quiReRegisterStateDriver then
                frame._quiReRegisterStateDriver()
            end
        end)
    end
    
    return true
end

-- Unregister an anchored frame
function QUI_Anchoring:UnregisterAnchoredFrame(frame)
    if not frame then return false end
    self.anchoredFrames[frame] = nil
    return true
end

-- Snap a frame to an anchor target
-- Parameters:
--   frame: The frame to snap
--   anchorTarget: Name of the anchor target to snap to
--   anchorPoint: Anchor point (default: "BOTTOMLEFT" for most, "CENTER" for screen/disabled)
--   offsetX: X offset (default: 0)
--   offsetY: Y offset (default: 0)
--   options: Optional table with:
--     - checkVisible: If true, only snap if target is visible (default: true)
--     - setWidth: If true, set frame width to match target (default: false)
--     - clearWidth: If true, clear width setting (default: false)
--     - onSuccess: Callback function called on successful snap
--     - onFailure: Callback function called if snap fails
-- Returns: true if successful, false otherwise
function QUI_Anchoring:SnapTo(frame, anchorTarget, anchorPoint, offsetX, offsetY, options)
    if not frame or not anchorTarget then
        return false
    end
    
    options = options or {}
    offsetX = offsetX or 0
    offsetY = offsetY or 0
    
    -- Get anchor target frame
    local targetFrame = self:GetAnchorTarget(anchorTarget)
    if not targetFrame then
        if options.onFailure then
            options.onFailure("Anchor target not found: " .. tostring(anchorTarget))
        end
        return false
    end

    -- Check if target is visible (if requested)
    if options.checkVisible ~= false then
        if not targetFrame:IsShown() then
            if options.onFailure then
                local registered = self.anchorTargets and self.anchorTargets[anchorTarget]
                local displayName = registered and registered.options and registered.options.displayName or anchorTarget
                options.onFailure(displayName .. " not visible.")
            end
            return false
        end
    end
    
    -- Determine anchor point
    if not anchorPoint then
        if anchorTarget == "screen" or anchorTarget == "disabled" or anchorTarget == "none" then
            anchorPoint = "CENTER"
        else
            anchorPoint = "BOTTOMLEFT"
        end
    end
    
    -- Position the frame (dual anchors auto-detected based on anchor points)
    local positionOptions = {
        targetAnchorPoint = options.targetAnchorPoint,
    }
    local success = self:PositionFrame(frame, anchorTarget, anchorPoint, offsetX, offsetY, nil, positionOptions)
    
    -- Re-register state drivers for unit frames after positioning (ClearAllPoints breaks them)
    if success and frame._quiReRegisterStateDriver then
        C_Timer.After(0, function()
            if frame and frame._quiReRegisterStateDriver then
                frame._quiReRegisterStateDriver()
            end
        end)
    end
    
    if success and options.onSuccess then
        options.onSuccess()
    end
    
    return success
end

-- Update all registered anchored frames
local pendingAnchoredFrameUpdateAfterCombat = false

function QUI_Anchoring:UpdateAllAnchoredFrames()
    if InCombatLockdown() then
        -- Avoid hot-loop requeueing during combat; process once on PLAYER_REGEN_ENABLED.
        pendingAnchoredFrameUpdateAfterCombat = true
        return
    end

    pendingAnchoredFrameUpdateAfterCombat = false

    local hasOverriddenFrames = false
    for frame, config in pairs(self.anchoredFrames) do
        -- Skip frames with active anchoring overrides — collect and reapply once after loop
        if self.overriddenFrames[frame] then
            hasOverriddenFrames = true
        elseif frame and frame:IsShown() then
            local anchors = config.anchors
            if not anchors or #anchors == 0 then
                -- Backward compatibility: use old anchorPoint format
                local sourceAnchorPoint = config.anchorPoint or "CENTER"
                local targetAnchorPoint = config.targetAnchorPoint or sourceAnchorPoint
                anchors = {
                    {source = sourceAnchorPoint, target = targetAnchorPoint}
                }
            end
            
            -- Safely clear points (use pcall to handle secure frames)
            local success = pcall(function()
                frame:ClearAllPoints()
            end)
            if not success then
                -- Frame is secure/managed - skip this frame
                C_Timer.After(0, function()
                    if InCombatLockdown() then
                        pendingAnchoredFrameUpdateAfterCombat = true
                        return
                    end
                    if frame and frame:IsShown() then
                        pcall(frame.ClearAllPoints, frame)
                        -- Retry positioning after clearing
                        local anchorPair = anchors[1]
                        if anchorPair then
                            local source = anchorPair.source or "CENTER"
                            local target = anchorPair.target or "CENTER"
                            self:PositionFrame(
                                frame,
                                config.anchorTarget,
                                source,
                                config.offsetX or 0,
                                config.offsetY or 0,
                                config.parentFrame,
                                {
                                    targetAnchorPoint = target,
                                }
                            )
                        end
                    end
                end)
                -- Skip to next frame - frame is secure/managed
            else
                -- Successfully cleared points, continue with positioning
                if #anchors == 1 then
                    -- Single anchor point
                    local anchorPair = anchors[1]
                    local source = anchorPair.source or "CENTER"
                    local target = anchorPair.target or "CENTER"
                    
                    self:PositionFrame(
                        frame,
                        config.anchorTarget,
                        source,
                        config.offsetX or 0,
                        config.offsetY or 0,
                        config.parentFrame,
                        {
                            targetAnchorPoint = target,
                        }
                    )
                elseif #anchors == 2 then
                    -- Dual anchor points
                    local anchorPair1 = anchors[1]
                    local anchorPair2 = anchors[2]
                    local source1 = anchorPair1.source or "CENTER"
                    local target1 = anchorPair1.target or "CENTER"
                    local source2 = anchorPair2.source or "CENTER"
                    local target2 = anchorPair2.target or "CENTER"
                    
                    self:PositionFrame(
                        frame,
                        config.anchorTarget,
                        source1,
                        config.offsetX or 0,
                        config.offsetY or 0,
                        config.parentFrame,
                        {
                            targetAnchorPoint = target1,
                            sourceAnchorPoint2 = source2,
                            targetAnchorPoint2 = target2,
                        }
                    )
                end
            end
        end
    end

    -- Reapply overrides once (not inside the loop) if any overridden frames were found
    if hasOverriddenFrames then
        self:ApplyAllFrameAnchors()
    end
end

-- If an anchoring update was requested during combat, apply it once combat ends.
local anchoredFramesCombatFrame = CreateFrame("Frame")
anchoredFramesCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
anchoredFramesCombatFrame:SetScript("OnEvent", function()
    if not pendingAnchoredFrameUpdateAfterCombat then return end

    pendingAnchoredFrameUpdateAfterCombat = false
    C_Timer.After(0.05, function()
        if InCombatLockdown() then
            pendingAnchoredFrameUpdateAfterCombat = true
            return
        end
        if QUI_Anchoring then
            QUI_Anchoring:UpdateAllAnchoredFrames()
        end
    end)
end)

-- Update frames anchored to a specific anchor target
function QUI_Anchoring:UpdateFramesForTarget(anchorTargetName)
    if InCombatLockdown() then
        -- Defer update after combat
        pendingAnchoredFrameUpdateAfterCombat = true
        return
    end
    
    for frame, config in pairs(self.anchoredFrames) do
        if frame and frame:IsShown() and config.anchorTarget == anchorTargetName then
            local anchors = config.anchors
            if not anchors or #anchors == 0 then
                -- Backward compatibility: use old anchorPoint format
                local sourceAnchorPoint = config.anchorPoint or "CENTER"
                local targetAnchorPoint = config.targetAnchorPoint or sourceAnchorPoint
                anchors = {
                    {source = sourceAnchorPoint, target = targetAnchorPoint}
                }
            end
            
            -- Safely clear points (use pcall to handle secure frames)
            local success = pcall(function()
                frame:ClearAllPoints()
            end)
            if not success then
                -- Frame is secure/managed - defer the call
                C_Timer.After(0, function()
                    if InCombatLockdown() then
                        pendingAnchoredFrameUpdateAfterCombat = true
                        return
                    end
                    if frame and frame:IsShown() then
                        pcall(frame.ClearAllPoints, frame)
                        -- Retry positioning after clearing
                        local anchorPair = anchors[1]
                        if anchorPair then
                            local source = anchorPair.source or "CENTER"
                            local target = anchorPair.target or "CENTER"
                            self:PositionFrame(
                                frame,
                                config.anchorTarget,
                                source,
                                config.offsetX or 0,
                                config.offsetY or 0,
                                config.parentFrame,
                                {
                                    targetAnchorPoint = target,
                                }
                            )
                        end
                    end
                end)
                -- Skip to next frame - frame is secure/managed
            else
                -- Successfully cleared points, continue with positioning
                if #anchors == 1 then
                    -- Single anchor point
                    local anchorPair = anchors[1]
                    local source = anchorPair.source or "CENTER"
                    local target = anchorPair.target or "CENTER"
                    
                    self:PositionFrame(
                        frame,
                        config.anchorTarget,
                        source,
                        config.offsetX or 0,
                        config.offsetY or 0,
                        config.parentFrame,
                        {
                            targetAnchorPoint = target,
                        }
                    )
                elseif #anchors == 2 then
                    -- Dual anchor points
                    local anchorPair1 = anchors[1]
                    local anchorPair2 = anchors[2]
                    local source1 = anchorPair1.source or "CENTER"
                    local target1 = anchorPair1.target or "CENTER"
                    local source2 = anchorPair2.source or "CENTER"
                    local target2 = anchorPair2.target or "CENTER"
                    
                    self:PositionFrame(
                        frame,
                        config.anchorTarget,
                        source1,
                        config.offsetX or 0,
                        config.offsetY or 0,
                        config.parentFrame,
                        {
                            targetAnchorPoint = target1,
                            sourceAnchorPoint2 = source2,
                            targetAnchorPoint2 = target2,
                        }
                    )
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- FRAME ANCHORING SYSTEM (centralized override positioning)
-- Forward declarations (defined below)
local DebouncedReapplyOverrides
local ComputeAnchorApplyOrder
---------------------------------------------------------------------------
-- Lazy resolver functions for all controllable frames
local FRAME_RESOLVERS = {
    -- CDM Viewers
    cdmEssential = function() return _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("essential") end,
    cdmUtility = function() return _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("utility") end,
    buffIcon = function() return _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("buffIcon") end,
    buffBar = function() return _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("buffBar") end,
    -- Resource Bars
    primaryPower = function() return QUICore and QUICore.powerBar end,
    secondaryPower = function() return QUICore and QUICore.secondaryPowerBar end,
    -- Unit Frames
    playerFrame = function() return ns.QUI_UnitFrames and ns.QUI_UnitFrames.frames and ns.QUI_UnitFrames.frames.player end,
    targetFrame = function() return ns.QUI_UnitFrames and ns.QUI_UnitFrames.frames and ns.QUI_UnitFrames.frames.target end,
    totFrame = function() return ns.QUI_UnitFrames and ns.QUI_UnitFrames.frames and ns.QUI_UnitFrames.frames.targettarget end,
    focusFrame = function() return ns.QUI_UnitFrames and ns.QUI_UnitFrames.frames and ns.QUI_UnitFrames.frames.focus end,
    petFrame = function() return ns.QUI_UnitFrames and ns.QUI_UnitFrames.frames and ns.QUI_UnitFrames.frames.pet end,
    bossFrames = function()
        -- Returns array of boss frames for iteration
        local frames = {}
        if ns.QUI_UnitFrames and ns.QUI_UnitFrames.frames then
            for i = 1, 5 do
                local f = ns.QUI_UnitFrames.frames["boss" .. i]
                if f then table.insert(frames, f) end
            end
        end
        return #frames > 0 and frames or nil
    end,
    -- Castbars
    playerCastbar = function() return ns.QUI_Castbar and ns.QUI_Castbar.castbars and ns.QUI_Castbar.castbars["player"] end,
    targetCastbar = function() return ns.QUI_Castbar and ns.QUI_Castbar.castbars and ns.QUI_Castbar.castbars["target"] end,
    focusCastbar = function() return ns.QUI_Castbar and ns.QUI_Castbar.castbars and ns.QUI_Castbar.castbars["focus"] end,
    -- Action Bars (MainMenuBar was renamed to MainActionBar in Midnight 12.0)
    bar1 = function() return _G["MainActionBar"] or _G["MainMenuBar"] end,
    bar2 = function() return _G["MultiBarBottomLeft"] end,
    bar3 = function() return _G["MultiBarBottomRight"] end,
    bar4 = function() return _G["MultiBarRight"] end,
    bar5 = function() return _G["MultiBarLeft"] end,
    bar6 = function() return _G["MultiBar5"] end,
    bar7 = function() return _G["MultiBar6"] end,
    bar8 = function() return _G["MultiBar7"] end,
    petBar = function() return _G["PetActionBar"] end,
    stanceBar = function() return _G["StanceBar"] end,
    microMenu = function() return _G["MicroMenuContainer"] end,
    bagBar = function() return _G["BagsBar"] end,
    extraActionButton = function() return _G["ExtraActionBarFrame"] end,
    zoneAbility = function() return _G["ZoneAbilityFrame"] end,
    -- QoL
    brezCounter = function() return _G["QUI_BrezCounter"] end,
    combatTimer = function() return _G["QUI_CombatTimer"] end,
    rangeCheck = function() return _G["QUI_RangeCheckFrame"] end,
    actionTracker = function() return _G["QUI_ActionTracker"] end,
    xpTracker = function() return _G["QUI_XPTracker"] end,
    skyriding = function() return _G["QUI_Skyriding"] end,
    petWarning = function() return _G["QUI_PetWarningFrame"] end,
    focusCastAlert = function() return _G["QUI_FocusCastAlertFrame"] end,
    missingRaidBuffs = function() return _G["QUI_MissingRaidBuffs"] end,
    mplusTimer = function() return _G["QUI_MPlusTimerFrame"] end,
    -- Display
    minimap = function() return _G["Minimap"] end,
    objectiveTracker = function() return _G["ObjectiveTrackerFrame"] end,
    buffFrame = function() return _G["BuffFrame"] end,
    debuffFrame = function() return _G["DebuffFrame"] end,
    chatFrame1 = function() return _G["ChatFrame1"] end,
    -- External (DandersFrames)
    dandersParty = function()
        if ns.QUI_DandersFrames and ns.QUI_DandersFrames:IsAvailable() then
            local frames = ns.QUI_DandersFrames:GetContainerFrames("party")
            return frames and frames[1]
        end
    end,
    dandersRaid = function()
        if ns.QUI_DandersFrames and ns.QUI_DandersFrames:IsAvailable() then
            local frames = ns.QUI_DandersFrames:GetContainerFrames("raid")
            return frames and frames[1]
        end
    end,
}

-- Blizzard-managed right-side frames are controlled by UIParentPanelManager.
-- Previously objectiveTracker, buffFrame, and debuffFrame were blocked here,
-- but the existing combat deferral and SecureHandlerStateTemplate taint cleaner
-- already handle taint safety for Edit Mode system frames, so they now use the
-- normal ApplyFrameAnchor path.
local UNSAFE_BLIZZARD_MANAGED_OVERRIDES = {
}

-- Frame display info for anchor target registration
local FRAME_ANCHOR_INFO = {
    cdmEssential    = { displayName = "CDM Essential Viewer",  category = "Cooldown Manager",  order = 1 },
    cdmUtility      = { displayName = "CDM Utility Viewer",    category = "Cooldown Manager",  order = 2 },
    buffIcon        = { displayName = "CDM Buff Icons",        category = "Cooldown Manager",  order = 3 },
    buffBar         = { displayName = "CDM Buff Bars",         category = "Cooldown Manager",  order = 4 },
    primaryPower    = { displayName = "Primary Power Bar",     category = "Resource Bars",     order = 1 },
    secondaryPower  = { displayName = "Secondary Power Bar",   category = "Resource Bars",     order = 2 },
    playerFrame     = { displayName = "Player Frame",          category = "Unit Frames",       order = 1 },
    targetFrame     = { displayName = "Target Frame",          category = "Unit Frames",       order = 2 },
    totFrame        = { displayName = "Target of Target",      category = "Unit Frames",       order = 3 },
    focusFrame      = { displayName = "Focus Frame",           category = "Unit Frames",       order = 4 },
    petFrame        = { displayName = "Pet Frame",             category = "Unit Frames",       order = 5 },
    bossFrames      = { displayName = "Boss Frames",           category = "Unit Frames",       order = 6 },
    playerCastbar   = { displayName = "Player Castbar",        category = "Castbars",          order = 1 },
    targetCastbar   = { displayName = "Target Castbar",        category = "Castbars",          order = 2 },
    focusCastbar    = { displayName = "Focus Castbar",         category = "Castbars",          order = 3 },
    bar1            = { displayName = "Action Bar 1",          category = "Action Bars",       order = 1 },
    bar2            = { displayName = "Action Bar 2",          category = "Action Bars",       order = 2 },
    bar3            = { displayName = "Action Bar 3",          category = "Action Bars",       order = 3 },
    bar4            = { displayName = "Action Bar 4",          category = "Action Bars",       order = 4 },
    bar5            = { displayName = "Action Bar 5",          category = "Action Bars",       order = 5 },
    bar6            = { displayName = "Action Bar 6",          category = "Action Bars",       order = 6 },
    bar7            = { displayName = "Action Bar 7",          category = "Action Bars",       order = 7 },
    bar8            = { displayName = "Action Bar 8",          category = "Action Bars",       order = 8 },
    petBar          = { displayName = "Pet Action Bar",        category = "Action Bars",       order = 9 },
    stanceBar       = { displayName = "Stance Bar",            category = "Action Bars",       order = 10 },
    microMenu       = { displayName = "Micro Menu",            category = "Action Bars",       order = 11 },
    bagBar          = { displayName = "Bag Bar",               category = "Action Bars",       order = 12 },
    extraActionButton = { displayName = "Extra Action Button", category = "Action Bars",       order = 13 },
    zoneAbility     = { displayName = "Zone Ability Button",   category = "Action Bars",       order = 14 },
    brezCounter     = { displayName = "Brez Counter",          category = "QoL",               order = 1 },
    combatTimer     = { displayName = "Combat Timer",          category = "QoL",               order = 2 },
    rangeCheck      = { displayName = "Target Distance Bracket Display", category = "QoL",      order = 3 },
    actionTracker   = { displayName = "Action Tracker",        category = "QoL",               order = 4 },
    xpTracker       = { displayName = "XP Tracker",            category = "QoL",               order = 5 },
    skyriding       = { displayName = "Skyriding",             category = "QoL",               order = 6 },
    petWarning      = { displayName = "Pet Warning",           category = "QoL",               order = 7 },
    focusCastAlert  = { displayName = "Focus Cast Alert",      category = "QoL",               order = 8 },
    missingRaidBuffs = { displayName = "Missing Raid Buffs",   category = "QoL",               order = 9 },
    mplusTimer      = { displayName = "M+ Timer",              category = "QoL",               order = 10 },
    minimap         = { displayName = "Minimap",               category = "Display",           order = 1 },
    objectiveTracker = { displayName = "Objective Tracker",    category = "Display",           order = 2 },
    buffFrame       = { displayName = "Buff Frame",            category = "Display",           order = 3 },
    debuffFrame     = { displayName = "Debuff Frame",          category = "Display",           order = 4 },
    chatFrame1      = { displayName = "Chat Frame",            category = "Display",           order = 5 },
    dandersParty    = { displayName = "DandersFrames Party",   category = "External",          order = 1 },
    dandersRaid     = { displayName = "DandersFrames Raid",    category = "External",          order = 2 },
}

-- Virtual anchor proxy parents.
-- Lightweight proxy frames we can safely resize in combat so frame anchoring
-- can still respect configured min-width even when source frames are protected.
-- CDM viewers use viewer-state sizing; other frames mirror size directly.
local ANCHOR_PROXY_SOURCES = {
    cdmEssential   = { resolver = function() return _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("essential") end, cdm = true },
    cdmUtility     = { resolver = function() return _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("utility") end,   cdm = true },
    buffIcon       = { resolver = function() return _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("buffIcon") end,  cdm = true },
    buffBar        = { resolver = function() return _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("buffBar") end,   cdm = true },
    primaryPower   = { resolver = function() return QUICore and QUICore.powerBar end },
    secondaryPower = { resolver = function() return QUICore and QUICore.secondaryPowerBar end },
}
local cdmAnchorProxies = {}
local cdmAnchorProxyPendingAfterCombat = {}
local HUD_MIN_WIDTH_DEFAULT = (ns.Helpers and ns.Helpers.HUD_MIN_WIDTH_DEFAULT) or 200

local function GetHUDMinWidthSettings()
    local profile = QUICore and QUICore.db and QUICore.db.profile
    local coreHelpers = ns and ns.Helpers
    if coreHelpers and coreHelpers.GetHUDMinWidthSettingsFromProfile then
        return coreHelpers.GetHUDMinWidthSettingsFromProfile(profile)
    end
    return false, HUD_MIN_WIDTH_DEFAULT
end

local function IsHUDAnchoredToCDM()
    local profile = QUICore and QUICore.db and QUICore.db.profile
    local coreHelpers = ns and ns.Helpers
    if not (coreHelpers and coreHelpers.IsHUDAnchoredToCDM) then
        return false
    end
    return coreHelpers.IsHUDAnchoredToCDM(profile)
end

-- CDM viewers use viewer-state sizing with min-width enforcement;
-- non-CDM sources use the factory default (mirror GetWidth/GetHeight).
local function CDMSizeResolver(source)
    local isEditMode = nsHelpers.IsEditModeActive()
    local vs = _G.QUI_GetCDMViewerState and _G.QUI_GetCDMViewerState(source)
    local width, height
    if isEditMode then
        width = (vs and vs.iconWidth) or 0
        height = (vs and vs.totalHeight) or 0
        if width < 2 or height < 2 then
            width = source:GetWidth() or 0
            height = source:GetHeight() or 0
        end
    else
        width = (vs and vs.iconWidth) or source:GetWidth() or 0
        height = (vs and vs.totalHeight) or source:GetHeight() or 0
    end
    -- Viewer state stores logical (un-scaled) dimensions.  Return
    -- source-local values so proxy Sync's effective-scale conversion
    -- produces the correct visual-space proxy size.
    -- Min-width is in visual (UIParent) space, so compare there.
    local scale = source:GetScale() or 1
    if scale <= 0 then scale = 1 end
    local minWidthEnabled, minWidth = GetHUDMinWidthSettings()
    if minWidthEnabled and IsHUDAnchoredToCDM() then
        local visualW = width * scale
        if visualW < minWidth then
            width = minWidth / scale
        end
    end
    return width, height
end

-- Anchor resolver for CDM proxies: offsets the proxy vertically so it
-- covers icons shifted by per-row yOffset settings.  Without this the
-- proxy is centered on the viewer, but the icon bounding box may be
-- shifted upward/downward.
local function IsFrameProtectedSafe(frame)
    if not (frame and frame.IsProtected) then return false end
    local ok, protected = pcall(frame.IsProtected, frame)
    return ok and protected == true
end

local function CDMAnchorResolver(proxy, source)
    local vs = _G.QUI_GetCDMViewerState and _G.QUI_GetCDMViewerState(source)
    local yOff = (vs and vs.proxyYOffset) or 0

    -- Some Blizzard CDM frames can become protected in combat, which propagates
    -- protection to anchored proxies. Mutating points in that state triggers
    -- ADDON_ACTION_BLOCKED on ClearAllPoints/SetPoint.
    if InCombatLockdown() and (IsFrameProtectedSafe(proxy) or IsFrameProtectedSafe(source)) then
        return
    end

    -- Avoid redundant point churn.
    if proxy:GetNumPoints() == 1 then
        local pt, relTo, relPt, ox, oy = proxy:GetPoint(1)
        if pt == "CENTER" and relTo == source and relPt == "CENTER"
            and math.abs((ox or 0) - 0) < 0.1
            and math.abs((oy or 0) - (yOff or 0)) < 0.1
        then
            return
        end
    end

    proxy:ClearAllPoints()
    proxy:SetPoint("CENTER", source, "CENTER", 0, yOff)
end

local function GetCDMAnchorProxy(parentKey)
    if parentKey == "essential" then
        parentKey = "cdmEssential"
    elseif parentKey == "utility" then
        parentKey = "cdmUtility"
    end

    local sourceInfo = ANCHOR_PROXY_SOURCES[parentKey]
    if not sourceInfo then return nil end

    local sourceFrame = sourceInfo.resolver()
    if not sourceFrame then return nil end

    local proxy = cdmAnchorProxies[parentKey]
    if proxy then
        proxy:SetSourceFrame(sourceFrame)
    else
        proxy = UIKit.CreateAnchorProxy(sourceFrame, {
            deferCreation = true,
            -- CDM + HUD proxy frames are addon-owned and safe to resize/anchor in combat.
            -- Keeping them live avoids stale bounds when CDM reflows during combat.
            combatFreeze = false,
            sizeResolver = sourceInfo.cdm and CDMSizeResolver or nil,
            anchorResolver = sourceInfo.cdm and CDMAnchorResolver or nil,
        })
        if not proxy then
            cdmAnchorProxyPendingAfterCombat[parentKey] = true
            return nil
        end
        cdmAnchorProxies[parentKey] = proxy
    end

    proxy:Sync()
    if proxy:NeedsCombatRefresh() then
        cdmAnchorProxyPendingAfterCombat[parentKey] = true
    end

    -- Debug overlay: show a colored border on the proxy when debug mode is active
    local debugActive = QUI and QUI.DEBUG_MODE
    if debugActive then
        if not proxy._debugBorder then
            proxy._debugBorder = CreateFrame("Frame", nil, proxy, "BackdropTemplate")
            proxy._debugBorder:SetAllPoints(proxy)
            proxy._debugBorder:SetFrameStrata("TOOLTIP")
            proxy._debugBorder:SetFrameLevel(999)
            proxy._debugBorder:SetBackdrop({
                bgFile = "Interface\\BUTTONS\\WHITE8X8",
                edgeFile = "Interface\\BUTTONS\\WHITE8X8",
                edgeSize = 2,
            })
            local colors = {
                cdmEssential    = { 0.2, 1.0, 0.6 },
                cdmUtility      = { 1.0, 0.6, 0.2 },
                primaryPower    = { 0.2, 0.6, 1.0 },
                secondaryPower  = { 1.0, 0.2, 0.6 },
            }
            local c = colors[parentKey] or { 1, 1, 0 }
            proxy._debugBorder:SetBackdropBorderColor(c[1], c[2], c[3], 1)
            proxy._debugBorder:SetBackdropColor(c[1], c[2], c[3], 0.15)
            local label = proxy._debugBorder:CreateFontString(nil, "OVERLAY")
            label:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
            label:SetPoint("CENTER")
            label:SetTextColor(c[1], c[2], c[3], 1)
            local labels = {
                cdmEssential    = "Essential Proxy",
                cdmUtility      = "Utility Proxy",
                primaryPower    = "Primary Power Proxy",
                secondaryPower  = "Secondary Power Proxy",
            }
            label:SetText(labels[parentKey] or parentKey)
        end
        proxy._debugBorder:Show()
    elseif proxy._debugBorder then
        proxy._debugBorder:Hide()
    end

    return proxy
end

-- Refresh all anchor proxy parents (safe in combat).
-- Order follows the anchor dependency graph when available so upstream
-- proxies are ready before downstream ones regardless of how the user
-- has configured the anchor chain.
local ANCHOR_PROXY_DEFAULT_ORDER = {
    "cdmEssential",
    "primaryPower",
    "secondaryPower",
    "cdmUtility",
    "buffIcon",
    "buffBar",
}
local function UpdateCDMAnchorProxies()
    -- Try to derive order from the anchor configuration so that proxy
    -- parents used by other proxied frames are refreshed first.
    local anchoringDB = QUICore and QUICore.db and QUICore.db.profile
        and QUICore.db.profile.frameAnchoring
    if anchoringDB then
        local sorted = ComputeAnchorApplyOrder(anchoringDB)
        -- Refresh proxied frames in dependency order, then any remaining
        -- proxy sources not present in the override system.
        local refreshed = {}
        for _, key in ipairs(sorted) do
            if ANCHOR_PROXY_SOURCES[key] then
                GetCDMAnchorProxy(key)
                refreshed[key] = true
            end
        end
        for _, key in ipairs(ANCHOR_PROXY_DEFAULT_ORDER) do
            if not refreshed[key] then
                GetCDMAnchorProxy(key)
            end
        end
    else
        -- Early init fallback before profile is loaded
        for _, key in ipairs(ANCHOR_PROXY_DEFAULT_ORDER) do
            GetCDMAnchorProxy(key)
        end
    end
end

-- Fallback anchor targets for when a resolved frame is unavailable (nil or hidden).
-- e.g. classes without a secondary resource should fall back to the primary bar.
local FRAME_ANCHOR_FALLBACKS = {
    secondaryPower = "primaryPower",
}

-- Helper: resolve a single key to a visible frame (nil if unavailable)
local function ResolveFrameForKey(key)
    -- Always use CDM proxy frames — GetViewerFrame returns QUI containers
    -- both in and out of Edit Mode, so proxies work identically.
    do
        local cdmProxy = GetCDMAnchorProxy(key)
        if cdmProxy then return cdmProxy end
    end

    -- Frame resolver
    local resolver = FRAME_RESOLVERS[key]
    if resolver then
        local frame = resolver()
        -- Boss frames resolver returns an array, take the first
        if type(frame) == "table" and not frame.GetObjectType then
            frame = frame[1]
        end
        if frame then return frame end
    end

    -- Anchor target registry
    local registered = QUI_Anchoring.anchorTargets[key]
    if registered then return registered.frame end

    return nil
end

-- Resolve an anchor parent key to a frame.
-- Follows the FRAME_ANCHOR_FALLBACKS chain when the resolved frame is nil or
-- hidden (e.g. secondary resource bar on a class with no secondary resource
-- falls back to the primary resource bar).
local function ResolveParentFrame(parentKey)
    if not parentKey or parentKey == "screen" or parentKey == "disabled" then
        return UIParent
    end

    local key = parentKey
    local visited = {}  -- guard against circular fallback chains

    while key do
        if visited[key] then break end
        visited[key] = true

        local frame = ResolveFrameForKey(key)

        -- Frame exists and is shown (or at least alpha-shown) → use it
        if frame and frame.IsShown and frame:IsShown() then
            return frame
        end

        -- Frame exists but is hidden → try fallback
        local fallback = FRAME_ANCHOR_FALLBACKS[key]
        if fallback then
            key = fallback
        else
            -- No fallback defined; return the frame if it exists (even if hidden)
            -- so that anchored frames keep their reference, or UIParent as last resort
            return frame or UIParent
        end
    end

    return UIParent
end

-- Expose proxy refresh for CDM layout module.
_G.QUI_UpdateCDMAnchorProxyFrames = UpdateCDMAnchorProxies
_G.QUI_GetCDMAnchorProxyFrame = GetCDMAnchorProxy

-- Re-sync frozen proxy anchors after combat ends.
local cdmProxyCombatFrame = CreateFrame("Frame")
cdmProxyCombatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
cdmProxyCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
local function ReanchorCombatCastbarOverrides()
    local anchoringDB = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.frameAnchoring
    if not anchoringDB or not QUI_Anchoring then return end

    local castbarKeys = { "playerCastbar", "targetCastbar", "focusCastbar" }
    for _, key in ipairs(castbarKeys) do
        local settings = anchoringDB[key]
        if type(settings) == "table" and settings.enabled then
            -- Normalize legacy aliases (settings.parent may store the short form)
            local parent = settings.parent
            if parent == "essential" then parent = "cdmEssential"
            elseif parent == "utility" then parent = "cdmUtility" end
            if parent == "cdmEssential" or parent == "cdmUtility" or parent == "buffIcon" or parent == "buffBar" then
                QUI_Anchoring:ApplyFrameAnchor(key, settings)
            end
        end
    end
end

cdmProxyCombatFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- Combat start: force a live proxy sync and re-apply castbar overrides
        -- anchored to CDM, then repeat briefly as CDM state settles.
        UpdateCDMAnchorProxies()
        ReanchorCombatCastbarOverrides()
        C_Timer.After(0.05, function()
            if InCombatLockdown() then
                UpdateCDMAnchorProxies()
                ReanchorCombatCastbarOverrides()
            end
        end)
        C_Timer.After(0.20, function()
            if InCombatLockdown() then
                UpdateCDMAnchorProxies()
                ReanchorCombatCastbarOverrides()
            end
        end)
        return
    end

    local needsRefresh = false
    for key, pending in pairs(cdmAnchorProxyPendingAfterCombat) do
        if pending then
            needsRefresh = true
            cdmAnchorProxyPendingAfterCombat[key] = nil
        end
    end
    -- Clear combat-pending state on all factory proxies
    for _, proxy in pairs(cdmAnchorProxies) do
        if proxy.ClearCombatPending then
            proxy:ClearCombatPending()
        end
    end
    if not needsRefresh then
        return
    end
    C_Timer.After(0.05, function()
        if InCombatLockdown() then
            for key in pairs(ANCHOR_PROXY_SOURCES) do
                cdmAnchorProxyPendingAfterCombat[key] = true
            end
            return
        end
        UpdateCDMAnchorProxies()
        DebouncedReapplyOverrides()
    end)
end)

-- Register all controllable frames as anchor targets (for dropdown lists)
function QUI_Anchoring:RegisterAllFrameTargets()
    for key, resolver in pairs(FRAME_RESOLVERS) do
        local frame = resolver()
        -- Boss frames return an array; register the first one
        if type(frame) == "table" and not frame.GetObjectType then
            frame = frame[1]
        end
        if frame then
            local info = FRAME_ANCHOR_INFO[key] or {}
            self:RegisterAnchorTarget(key, frame, {
                displayName = info.displayName or key,
                category = info.category,
                categoryOrder = info.order,
                order = info.order,
            })
        end
    end
end

-- Helper: mark a frame as overridden (blocks module positioning via PositionFrame/RegisterAnchoredFrame)
-- Stores the frame key (e.g. "playerFrame") so callers can do targeted reapply
local function SetFrameOverride(frame, active, key)
    if not frame then return end
    -- Boss frames resolver returns an array
    if type(frame) == "table" and not frame.GetObjectType then
        for _, f in ipairs(frame) do
            QUI_Anchoring.overriddenFrames[f] = active and key or nil
        end
        -- Also mark BossTargetFrameContainer so QUI_IsFrameLocked checks
        -- on the container (used by Edit Mode overlay/nudge systems) work
        if BossTargetFrameContainer then
            QUI_Anchoring.overriddenFrames[BossTargetFrameContainer] = active and key or nil
        end
    else
        QUI_Anchoring.overriddenFrames[frame] = active and key or nil
    end
end

-- Track which parent frames have been hooked for OnSizeChanged
local hookedParentFrames = {}

CDM_LOGICAL_SIZE_KEYS.cdmEssential = true
CDM_LOGICAL_SIZE_KEYS.cdmUtility = true
CDM_LOGICAL_SIZE_KEYS.buffIcon = true
CDM_LOGICAL_SIZE_KEYS.buffBar = true
local CASTBAR_ANCHOR_KEYS = {
    playerCastbar = true,
    targetCastbar = true,
    focusCastbar = true,
}

local function GetPointOffsetForRect(point, width, height)
    local halfW = (width or 0) * 0.5
    local halfH = (height or 0) * 0.5
    if point == "TOPLEFT" then
        return -halfW, halfH
    elseif point == "TOP" then
        return 0, halfH
    elseif point == "TOPRIGHT" then
        return halfW, halfH
    elseif point == "LEFT" then
        return -halfW, 0
    elseif point == "RIGHT" then
        return halfW, 0
    elseif point == "BOTTOMLEFT" then
        return -halfW, -halfH
    elseif point == "BOTTOM" then
        return 0, -halfH
    elseif point == "BOTTOMRIGHT" then
        return halfW, -halfH
    end
    return 0, 0
end

local function GetFrameAnchorRect(frame, key)
    if not frame then return 1, 1 end

    local width, height

    -- CDM viewers can briefly report Blizzard-sized dimensions in combat during
    -- morph/layout churn. Prefer logical layout dimensions when available.
    if CDM_LOGICAL_SIZE_KEYS[key] then
        local vs = _G.QUI_GetCDMViewerState and _G.QUI_GetCDMViewerState(frame)
        if vs then
            width = vs.row1Width or vs.iconWidth
            height = vs.totalHeight
        end
    end

    if not width or width <= 0 then
        width = frame.GetWidth and frame:GetWidth() or 1
    end
    if not height or height <= 0 then
        height = frame.GetHeight and frame:GetHeight() or 1
    end

    -- SetPoint offsets are in the parent's coordinate space.  The child frame's
    -- GetWidth/GetHeight return dimensions in its own coordinate space.  Multiply
    -- by the child's scale to get the visual extent in the parent's coordinate
    -- space so center-offset math correctly accounts for scaled frames (e.g.
    -- Minimap at scale 1.2).  CDM logical dimensions are already in parent space.
    if not CDM_LOGICAL_SIZE_KEYS[key] and frame.GetScale then
        local fScale = frame:GetScale() or 1
        if fScale > 0 and fScale ~= 1 then
            width = width * fScale
            height = height * fScale
        end
    end

    return math.max(1, width), math.max(1, height)
end

local function GetParentAnchorRect(frame, parentKey)
    if not frame then return 1, 1 end

    local width, height
    local usedLogical = false

    -- CDM parent proxies are frozen during combat, but the source viewer's
    -- logical layout state is always current.  Read through the proxy to the
    -- source frame so center-offset math uses live dimensions.
    if parentKey then
        -- Normalize aliases (settings.parent may store the short form)
        if parentKey == "essential" then parentKey = "cdmEssential"
        elseif parentKey == "utility" then parentKey = "cdmUtility" end

        if CDM_LOGICAL_SIZE_KEYS[parentKey] then
            local source = ANCHOR_PROXY_SOURCES[parentKey]
            if source then
                local sourceFrame = source.resolver()
                if sourceFrame then
                    local vs = _G.QUI_GetCDMViewerState and _G.QUI_GetCDMViewerState(sourceFrame)
                    if vs then
                        width = vs.row1Width or vs.iconWidth
                        height = vs.totalHeight
                        usedLogical = true
                    end
                end
            end
        end
    end

    if not width or width <= 0 then
        width = frame.GetWidth and frame:GetWidth() or 1
    end
    if not height or height <= 0 then
        height = frame.GetHeight and frame:GetHeight() or 1
    end

    -- SetPoint offsets are in the parent's coordinate space.  The parent's
    -- GetWidth/GetHeight already return dimensions in its own coordinate space,
    -- so no scale multiplication is needed here.  (Previously this multiplied by
    -- the parent's scale, converting to screen pixels, which caused offsets to
    -- fall short of the intended edge positions.)
    -- CDM logical dimensions are already in the correct space — no adjustment.

    return math.max(1, width), math.max(1, height)
end

local function ComputeCenterOffsetsForAnchor(frame, key, parentFrame, sourcePoint, targetPoint, offsetX, offsetY, parentKey)
    local frameW, frameH = GetFrameAnchorRect(frame, key)
    local parentW, parentH = GetParentAnchorRect(parentFrame, parentKey)

    local targetX, targetY = GetPointOffsetForRect(targetPoint or "CENTER", parentW, parentH)
    local sourceX, sourceY = GetPointOffsetForRect(sourcePoint or "CENTER", frameW, frameH)

    return (targetX + (offsetX or 0) - sourceX), (targetY + (offsetY or 0) - sourceY)
end

local function IsSizeStableAnchoringEnabled(settings)
    if type(settings) ~= "table" then
        return true
    end
    -- Default ON for all frame anchoring overrides.
    return settings.sizeStable ~= false
end

-- Apply auto-width and auto-height to a frame
local function ApplyAutoSizing(frame, settings, parentFrame, key)
    if not frame then return end

    -- Auto-width: match anchor target width
    if settings.autoWidth and parentFrame and parentFrame ~= UIParent then
        local ok, parentWidth = pcall(function() return parentFrame:GetWidth() end)
        if ok and parentWidth and parentWidth > 0 then
            local adjustedWidth = parentWidth + (settings.widthAdjust or 0)
            if adjustedWidth > 0 then
                pcall(function() frame:SetWidth(adjustedWidth) end)
            end
        end

        -- Hook parent OnSizeChanged so auto-width stays in sync when parent resizes
        if not hookedParentFrames[parentFrame] then
            hookedParentFrames[parentFrame] = true
            pcall(function()
                parentFrame:HookScript("OnSizeChanged", function()
                    DebouncedReapplyOverrides()
                end)
            end)
        end
    end

    -- Auto-height: match CDM Essential row 1 icon height (player/target only)
    if settings.autoHeight then
        local viewer = _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("essential")
        if viewer then
            local vs = _G.QUI_GetCDMViewerState and _G.QUI_GetCDMViewerState(viewer)
            local iconHeight = vs and vs.row1IconHeight
            if iconHeight and iconHeight > 0 then
                local adjustedHeight = iconHeight + (settings.heightAdjust or 0)
                if adjustedHeight > 0 then
                    pcall(function() frame:SetHeight(adjustedHeight) end)
                end
            end

            -- Hook viewer OnSizeChanged so auto-height stays in sync when CDM resizes
            if not hookedParentFrames[viewer] then
                hookedParentFrames[viewer] = true
                pcall(function()
                    viewer:HookScript("OnSizeChanged", function()
                        DebouncedReapplyOverrides()
                    end)
                end)
            end
        end
    end
end

-- Apply a single frame anchor override
function QUI_Anchoring:ApplyFrameAnchor(key, settings)
    local inEditMode = nsHelpers.IsEditModeActive()
    local editDbg = inEditMode and not _editModeTickerSilent
    if type(settings) ~= "table" then return end

    local resolver = FRAME_RESOLVERS[key]
    if not resolver then
        if editDbg then AnchorDebug(format("ApplyFrameAnchor(%s): NO RESOLVER", key)) end
        return
    end

    local resolved = resolver()

    -- If override is disabled, unblock module positioning and let modules reclaim the frame
    if not settings.enabled then
        if editDbg then AnchorDebug(format("ApplyFrameAnchor(%s): DISABLED", key)) end
        SetFrameOverride(resolved, false)
        return
    end

    if not resolved then
        if editDbg then AnchorDebug(format("ApplyFrameAnchor(%s): RESOLVED=nil", key)) end
        return
    end

    -- Never anchor UIParent-managed right-side frames from addon code.
    -- Keep them on Blizzard defaults to avoid protected layout taint.
    -- Still mark them overridden so QUI_IsFrameLocked returns true and
    -- the Edit Mode overlay shows "(Locked)" / blocks drag.
    if UNSAFE_BLIZZARD_MANAGED_OVERRIDES[key] then
        if editDbg then AnchorDebug(format("ApplyFrameAnchor(%s): UNSAFE_BLIZZARD_MANAGED", key)) end
        SetFrameOverride(resolved, true, key)
        return
    end

    -- Detect Blizzard Edit Mode system frames early (needed for CDM guards below).
    local isBlizzEditModeSystem = resolved.system ~= nil or resolved.systemIndex ~= nil

    -- During Edit Mode, free-floating CDM viewers (screen/disabled parent) are
    -- entirely handled by Blizzard's native drag system.  Don't mark them as
    -- overridden (keeps them "unlocked" and draggable) and don't call SetPoint.
    if isBlizzEditModeSystem and inEditMode
        and CDM_LOGICAL_SIZE_KEYS[key]
        and (not settings.parent or settings.parent == "screen" or settings.parent == "disabled") then
        if editDbg then AnchorDebug(format("ApplyFrameAnchor(%s): SKIP free-floating CDM viewer in EditMode", key)) end
        return
    end

    -- Mark frame as overridden FIRST — blocks any module positioning from this point on
    SetFrameOverride(resolved, true, key)

    -- ClearAllPoints on hidden Blizzard Edit Mode system frames triggers
    -- OnSystemPositionChange which reads GetPoint() and errors on nil offsetY.
    -- Still mark them overridden (above) so QUI_IsFrameLocked returns true and
    -- the Edit Mode overlay shows "(Locked)", but skip the actual repositioning.
    if isBlizzEditModeSystem and resolved.IsShown and not resolved:IsShown() then
        if editDbg then AnchorDebug(format("ApplyFrameAnchor(%s): HIDDEN system frame (system=%s sysIdx=%s)", key, tostring(resolved.system), tostring(resolved.systemIndex))) end
        return
    end

    -- During Edit Mode, anchored CDM viewers are marked overridden above so
    -- nudge overlays show "(Locked)", but we skip ClearAllPoints/SetPoint.
    -- Calling these on Blizzard's secure CDM viewer frames from addon code
    -- taints their geometry; HideSystemSelections reads the tainted position
    -- via secureexecuterange on exit, propagating taint and triggering
    -- ADDON_ACTION_FORBIDDEN on ClearTarget().
    if isBlizzEditModeSystem and inEditMode
        and CDM_LOGICAL_SIZE_KEYS[key] then
        if editDbg then AnchorDebug(format("ApplyFrameAnchor(%s): SKIP anchored CDM viewer in EditMode (taint safety)", key)) end
        return
    end

    -- Defer in combat for most frames.
    -- CDM viewers are allowed to attempt re-anchoring in combat so morph/layout
    -- churn can be corrected immediately instead of waiting for combat end.
    local allowCombatApply = (
        key == "cdmEssential" or key == "cdmUtility" or key == "buffIcon" or key == "buffBar"
        or key == "playerCastbar" or key == "targetCastbar" or key == "focusCastbar"
    )
    if InCombatLockdown() and allowCombatApply then
        -- CDM viewers are normally safe to reposition in combat, but if the
        -- resolved frame is actually protected (e.g. Blizzard's secure CDM
        -- container), attempting ClearAllPoints/SetPoint will taint.  Defer
        -- to PLAYER_REGEN_ENABLED instead.
        if resolved.IsProtected and resolved:IsProtected() then
            pendingAnchoredFrameUpdateAfterCombat = true
            return
        end
        -- Frame is not protected — safe to proceed in combat
    elseif InCombatLockdown() then
        C_Timer.After(0.5, function()
            if not InCombatLockdown() then
                self:ApplyFrameAnchor(key, settings)
            end
        end)
        return
    end

    local parentFrame = ResolveParentFrame(settings.parent)

    if editDbg then
        local parentName = settings.parent or "nil"
        local parentExists = parentFrame and true or false
        local parentIsSystem = parentFrame and (parentFrame.system ~= nil or parentFrame.systemIndex ~= nil) or false
        local parentShown = parentFrame and parentFrame.IsShown and parentFrame:IsShown() or false
        AnchorDebug(format("ApplyFrameAnchor(%s): parent=%s exists=%s isSystem=%s shown=%s isSysFrame=%s",
            key, parentName, tostring(parentExists), tostring(parentIsSystem), tostring(parentShown), tostring(isBlizzEditModeSystem)))
    end

    -- Skip repositioning when the parent is a hidden Blizzard Edit Mode system
    -- frame (e.g. StanceBar anchored to PetActionBar when there is no pet).
    -- Anchoring a secure frame to a hidden secure frame via SetPoint from addon
    -- code taints the anchor chain; when Edit Mode reads it in the secure context
    -- the taint propagates and causes "secret number tainted by QUI" errors.
    -- Leave the frame at Blizzard's default position instead.
    if parentFrame and parentFrame ~= UIParent then
        local parentIsBlizzSystem = parentFrame.system ~= nil or parentFrame.systemIndex ~= nil
        if parentIsBlizzSystem and parentFrame.IsShown and not parentFrame:IsShown() then
            if editDbg then AnchorDebug(format("ApplyFrameAnchor(%s): SKIP hidden system parent=%s", key, settings.parent or "nil")) end
            return
        end
    end

    local point = settings.point or "CENTER"
    local relative = settings.relative or "CENTER"
    local offsetX = settings.offsetX or 0
    local offsetY = settings.offsetY or 0
    local useSizeStable = IsSizeStableAnchoringEnabled(settings)
    if CASTBAR_ANCHOR_KEYS[key] then
        -- Castbars should preserve the explicit point relation (e.g. TOP->BOTTOM)
        -- so they track parent edge movement automatically in combat.
        -- Center-converted size-stable mode requires re-apply on parent size changes
        -- and can drift when combat-safe reapply paths are constrained.
        useSizeStable = false
    end

    -- Boss frames: single setting applied to all with stacking Y offset
    if key == "bossFrames" and type(resolved) == "table" and not resolved.GetObjectType then
        for i, frame in ipairs(resolved) do
            local stackOffsetY = offsetY - ((i - 1) * 50)
            if useSizeStable then
                ApplyAutoSizing(frame, settings, parentFrame, key)
            end
            -- TAINT SAFETY: Track position for secure re-stamping on combat enter
            local frameIsEditMode = frame.system ~= nil or frame.systemIndex ~= nil
            -- Compute target position first so we can skip if already correct
            local targetPt, targetRelPt, targetX, targetY
            if useSizeStable then
                local centerX, centerY = ComputeCenterOffsetsForAnchor(
                    frame, key, parentFrame, point, relative, offsetX, stackOffsetY, settings.parent
                )
                targetPt, targetRelPt, targetX, targetY = "CENTER", "CENTER", centerX, centerY
            else
                targetPt, targetRelPt, targetX, targetY = point, relative, offsetX, stackOffsetY
            end
            -- Skip ClearAllPoints+SetPoint if frame is already at the right position
            if not FrameAlreadyAtPosition(frame, targetPt, parentFrame, targetRelPt, targetX, targetY) then
                _editModeReapplyGuard = true
                pcall(function()
                    frame:ClearAllPoints()
                    frame:SetPoint(targetPt, parentFrame, targetRelPt, targetX, targetY)
                end)
                _editModeReapplyGuard = false
            end
            if frameIsEditMode then
                if useSizeStable then
                    local centerX, centerY = ComputeCenterOffsetsForAnchor(
                        frame, key, parentFrame, point, relative, offsetX, stackOffsetY, settings.parent
                    )
                    TrackSecureFramePosition(frame, parentFrame, "CENTER", "CENTER", centerX, centerY)
                else
                    TrackSecureFramePosition(frame, parentFrame, point, relative, offsetX, stackOffsetY)
                end
            end
        end
        -- Legacy path: apply auto-sizing after placement when size-stable mode is off
        if not useSizeStable then
            ApplyAutoSizing(resolved[1], settings, parentFrame, key)
            for i = 2, #resolved do
                ApplyAutoSizing(resolved[i], settings, parentFrame, key)
            end
        end
        return
    end

    -- Normal single-frame case
    if useSizeStable then
        -- Size-stable anchoring: solve requested point->point relation into a
        -- center anchor. This prevents visual drift when frame dimensions mutate.
        --
        -- For CDM viewers, ComputeCenterOffsetsForAnchor uses logical layout size
        -- so transient Blizzard combat sizes do not skew the result.
        ApplyAutoSizing(resolved, settings, parentFrame, key)
        local centerX, centerY = ComputeCenterOffsetsForAnchor(
            resolved, key, parentFrame, point, relative, offsetX, offsetY, settings.parent
        )
        -- Skip if already at the right position (prevents flash during Edit Mode ticker)
        if FrameAlreadyAtPosition(resolved, "CENTER", parentFrame, "CENTER", centerX, centerY) then
            if editDbg then
                AnchorDebug(format("ApplyFrameAnchor(%s): SKIP (already at position)", key))
            end
        else
            _editModeReapplyGuard = true
            local ok = pcall(function()
                resolved:ClearAllPoints()
                resolved:SetPoint("CENTER", parentFrame, "CENTER", centerX, centerY)
            end)
            _editModeReapplyGuard = false
            if editDbg then
                AnchorDebug(format("ApplyFrameAnchor(%s): SET CENTER parent=%s cx=%.1f cy=%.1f ok=%s",
                    key, settings.parent or "nil", centerX, centerY, tostring(ok)))
            end
        end
        -- TAINT SAFETY: Track for secure re-stamping on combat enter so
        -- Edit Mode's secureexecuterange won't hit tainted SetPointBase.
        if isBlizzEditModeSystem then
            TrackSecureFramePosition(resolved, parentFrame, "CENTER", "CENTER", centerX, centerY)
        end
    else
        -- Skip if already at the right position (prevents flash during Edit Mode ticker)
        if FrameAlreadyAtPosition(resolved, point, parentFrame, relative, offsetX, offsetY) then
            if editDbg then
                AnchorDebug(format("ApplyFrameAnchor(%s): SKIP (already at position)", key))
            end
        else
            _editModeReapplyGuard = true
            local ok = pcall(function()
                resolved:ClearAllPoints()
                resolved:SetPoint(point, parentFrame, relative, offsetX, offsetY)
            end)
            _editModeReapplyGuard = false
            if editDbg then
                AnchorDebug(format("ApplyFrameAnchor(%s): SET %s->%s parent=%s ox=%.1f oy=%.1f ok=%s",
                    key, point, relative, settings.parent or "nil", offsetX, offsetY, tostring(ok)))
            end
        end
        if isBlizzEditModeSystem then
            TrackSecureFramePosition(resolved, parentFrame, point, relative, offsetX, offsetY)
        end
        -- Legacy path: auto-size after placement
        ApplyAutoSizing(resolved, settings, parentFrame, key)
    end
end

-- Compute dependency-ordered apply sequence for frame anchoring overrides.
-- Uses Kahn's algorithm (topological sort) so that parent frames are
-- positioned before their children, preventing transient jumps when frames
-- are anchored in arbitrary chains (e.g. buffIcon → primaryPower → cdmEssential).
ComputeAnchorApplyOrder = function(anchoringDB)
    -- 1. Collect all enabled override keys
    local enabledSet = {}
    local enabledList = {}
    for key, settings in pairs(anchoringDB) do
        if type(settings) == "table" and FRAME_RESOLVERS[key] and settings.enabled then
            enabledSet[key] = true
            enabledList[#enabledList + 1] = key
        end
    end

    if #enabledList == 0 then return enabledList end

    -- 2. Build dependency edges (key depends on parent when parent is also overridden)
    local inDegree  = {}
    local childrenOf = {}
    for _, key in ipairs(enabledList) do
        inDegree[key] = 0
        childrenOf[key] = {}
    end

    for _, key in ipairs(enabledList) do
        local parent = anchoringDB[key].parent
        -- Normalize aliases used by GetCDMAnchorProxy
        if parent == "essential" then parent = "cdmEssential" end
        if parent == "utility"  then parent = "cdmUtility"   end

        if parent and enabledSet[parent] then
            inDegree[key] = inDegree[key] + 1
            childrenOf[parent][#childrenOf[parent] + 1] = key
        end
    end

    -- 3. Kahn's BFS — roots (no in-system parent) first
    local sorted = {}
    local queue  = {}
    for _, key in ipairs(enabledList) do
        if inDegree[key] == 0 then
            queue[#queue + 1] = key
        end
    end

    local head = 1
    while head <= #queue do
        local key = queue[head]
        head = head + 1
        sorted[#sorted + 1] = key
        for _, child in ipairs(childrenOf[key]) do
            inDegree[child] = inDegree[child] - 1
            if inDegree[child] == 0 then
                queue[#queue + 1] = child
            end
        end
    end

    -- 4. Cycle fallback — append any remaining keys so they still get applied
    if #sorted < #enabledList then
        for _, key in ipairs(enabledList) do
            if inDegree[key] > 0 then
                sorted[#sorted + 1] = key
            end
        end
    end

    return sorted
end

-- Apply all saved frame anchor overrides (dependency-ordered)
function QUI_Anchoring:ApplyAllFrameAnchors()
    if not QUICore or not QUICore.db or not QUICore.db.profile then return end
    local anchoringDB = QUICore.db.profile.frameAnchoring
    if not anchoringDB then
        AnchorDebug("ApplyAllFrameAnchors: NO anchoringDB")
        return
    end

    local sorted = ComputeAnchorApplyOrder(anchoringDB)
    local inEditMode = nsHelpers.IsEditModeActive()
    if inEditMode and not _editModeTickerSilent then
        AnchorDebug(format("ApplyAllFrameAnchors: %d keys in order: %s", #sorted, table.concat(sorted, ", ")))
    end
    for _, key in ipairs(sorted) do
        self:ApplyFrameAnchor(key, anchoringDB[key])
    end
end

---------------------------------------------------------------------------
-- GLOBAL CALLBACKS (for backward compatibility)
---------------------------------------------------------------------------
-- Global callbacks for frame anchoring overrides
-- Check if a frame has an active anchoring override (blocks module positioning)
_G.QUI_IsFrameOverridden = function(frame)
    return QUI_Anchoring and QUI_Anchoring.overriddenFrames and QUI_Anchoring.overriddenFrames[frame] or false
end

-- Alias used by nudge, Edit Mode, resource bars, etc. to check if a frame
-- should be locked in place (same underlying check as IsFrameOverridden).
_G.QUI_IsFrameLocked = _G.QUI_IsFrameOverridden

_G.QUI_ApplyAllFrameAnchors = function()
    if QUI_Anchoring then
        QUI_Anchoring:ApplyAllFrameAnchors()
    end
end

_G.QUI_ApplyFrameAnchor = function(key)
    if not QUI_Anchoring or not QUICore or not QUICore.db or not QUICore.db.profile then return end
    local anchoringDB = QUICore.db.profile.frameAnchoring
    local settings = anchoringDB and anchoringDB[key]
    if type(settings) == "table" and FRAME_RESOLVERS[key] then
        QUI_Anchoring:ApplyFrameAnchor(key, settings)
    end
end

-- Position-only re-anchor for Edit Mode: repositions a frame to its configured
-- parent without calling ApplyAutoSizing (which would fight the user's manual
-- resize during Edit Mode).
_G.QUI_ReanchorFramePositionOnly = function(key)
    if not key or InCombatLockdown() then return end
    if not QUI_Anchoring or not QUICore or not QUICore.db or not QUICore.db.profile then return end
    local anchoringDB = QUICore.db.profile.frameAnchoring
    if not anchoringDB then return end
    local settings = anchoringDB[key]
    if type(settings) ~= "table" or not settings.enabled then return end

    local resolver = FRAME_RESOLVERS[key]
    if not resolver then return end
    local resolved = resolver()
    if not resolved then return end

    local parentFrame = ResolveParentFrame(settings.parent)
    if not parentFrame then return end

    local point = settings.point or "CENTER"
    local relative = settings.relative or "CENTER"
    local offsetX = settings.offsetX or 0
    local offsetY = settings.offsetY or 0
    local useSizeStable = IsSizeStableAnchoringEnabled(settings)

    pcall(function()
        resolved:ClearAllPoints()
        if useSizeStable then
            local centerX, centerY = ComputeCenterOffsetsForAnchor(
                resolved, key, parentFrame, point, relative, offsetX, offsetY, settings.parent
            )
            resolved:SetPoint("CENTER", parentFrame, "CENTER", centerX, centerY)
        else
            resolved:SetPoint(point, parentFrame, relative, offsetX, offsetY)
        end
    end)
end

-- Anchor an arbitrary overlay frame to a key's configured parent.
-- Used during Edit Mode to position QUI overlays at the correct anchored
-- location without touching the protected Blizzard system frame itself.
-- overlayFrame: the QUI overlay to position
-- key: frame anchoring key (e.g. "buffIcon")
-- overlayW, overlayH: explicit size for center offset math (icon content area)
_G.QUI_AnchorOverlayToParent = function(overlayFrame, key, overlayW, overlayH)
    if not overlayFrame or not key then return end
    if not QUI_Anchoring or not QUICore or not QUICore.db or not QUICore.db.profile then return end
    local anchoringDB = QUICore.db.profile.frameAnchoring
    if not anchoringDB then return end
    local settings = anchoringDB[key]
    if type(settings) ~= "table" or not settings.enabled then return end

    local parentFrame = ResolveParentFrame(settings.parent)
    if not parentFrame then return end

    local point = settings.point or "CENTER"
    local relative = settings.relative or "CENTER"
    local offsetX = settings.offsetX or 0
    local offsetY = settings.offsetY or 0
    local useSizeStable = IsSizeStableAnchoringEnabled(settings)

    overlayFrame:ClearAllPoints()
    if overlayW and overlayW > 0 then overlayFrame:SetWidth(overlayW) end
    if overlayH and overlayH > 0 then overlayFrame:SetHeight(overlayH) end
    if useSizeStable then
        -- Compute center offsets using the overlay's dimensions and parent rect
        local parentW, parentH = GetParentAnchorRect(parentFrame, settings.parent)
        local targetX, targetY = GetPointOffsetForRect(relative or "CENTER", parentW, parentH)
        local sourceX, sourceY = GetPointOffsetForRect(point or "CENTER", overlayW or 1, overlayH or 1)
        local centerX = (targetX + (offsetX or 0) - sourceX)
        local centerY = (targetY + (offsetY or 0) - sourceY)
        overlayFrame:SetPoint("CENTER", parentFrame, "CENTER", centerX, centerY)
    else
        overlayFrame:SetPoint(point, parentFrame, relative, offsetX, offsetY)
    end
end

-- Debounced reapply of frame anchoring overrides after module repositioning
local pendingOverrideReapply = nil

DebouncedReapplyOverrides = function()
    if pendingOverrideReapply then return end
    pendingOverrideReapply = true
    C_Timer.After(0.15, function()
        pendingOverrideReapply = nil
        -- During Edit Mode this still runs — ApplyFrameAnchor now skips
        -- CDM viewer keys (Blizzard controls those) but repositions all
        -- other overridden frames so the anchor chain stays correct.
        local inEditMode = nsHelpers.IsEditModeActive()
        if inEditMode and not _editModeTickerSilent then
            AnchorDebug("DebouncedReapplyOverrides: firing ApplyAllFrameAnchors in EditMode")
        end
        if QUI_Anchoring then
            QUI_Anchoring:ApplyAllFrameAnchors()
        end
    end)
end

-- Hook module refresh globals to reapply overrides after modules reposition frames.
-- These globals are defined by modules that load before this file in modules.xml.
local function HookRefreshGlobal(name)
    local original = _G[name]
    if not original then return end
    _G[name] = function(...)
        original(...)
        DebouncedReapplyOverrides()
    end
end

HookRefreshGlobal("QUI_RefreshCastbars")
HookRefreshGlobal("QUI_RefreshUnitFrames")
HookRefreshGlobal("QUI_RefreshNCDM")
HookRefreshGlobal("QUI_RefreshBuffBar")

-- Global callback for updating anchored frames (called by NCDM, resource bars, etc.)
-- Preserve any existing unit-frame updater to avoid breaking legacy anchoring.
local previousUpdateAnchoredFrames = _G.QUI_UpdateAnchoredFrames
local previousUpdateAnchoredUnitFrames = _G.QUI_UpdateAnchoredUnitFrames
local previousUpdateCDMAnchoredUnitFrames = _G.QUI_UpdateCDMAnchoredUnitFrames

_G.QUI_UpdateAnchoredFrames = function(...)
    if QUI_Anchoring then
        QUI_Anchoring:UpdateAllAnchoredFrames()
    end
    if previousUpdateAnchoredFrames and previousUpdateAnchoredFrames ~= _G.QUI_UpdateAnchoredFrames then
        previousUpdateAnchoredFrames(...)
    end
    -- Reapply frame anchoring overrides after modules finish repositioning
    DebouncedReapplyOverrides()
end

-- Backward compatibility aliases that also honor any pre-existing unit-frame updater
_G.QUI_UpdateAnchoredUnitFrames = function(...)
    if previousUpdateAnchoredUnitFrames and previousUpdateAnchoredUnitFrames ~= _G.QUI_UpdateAnchoredUnitFrames and previousUpdateAnchoredUnitFrames ~= previousUpdateAnchoredFrames then
        previousUpdateAnchoredUnitFrames(...)
    end
    _G.QUI_UpdateAnchoredFrames(...)
end

_G.QUI_UpdateCDMAnchoredUnitFrames = function(...)
    if previousUpdateCDMAnchoredUnitFrames and previousUpdateCDMAnchoredUnitFrames ~= _G.QUI_UpdateCDMAnchoredUnitFrames and previousUpdateCDMAnchoredUnitFrames ~= previousUpdateAnchoredFrames then
        previousUpdateCDMAnchoredUnitFrames(...)
    end
    _G.QUI_UpdateAnchoredFrames(...)
end

-- Targeted anchor update: only update frames anchored to a specific target.
-- Accepts a string key (e.g. "minimap") or a frame object (resolved via reverse lookup).
-- Updates both legacy anchored frames and frame anchoring overrides.
_G.QUI_UpdateFramesAnchoredTo = function(targetKeyOrFrame)
    if not targetKeyOrFrame then return end

    -- Resolve frame object to key via reverse lookup
    local targetKey = targetKeyOrFrame
    if type(targetKeyOrFrame) ~= "string" then
        targetKey = nil
        if QUI_Anchoring and QUI_Anchoring.anchorTargets then
            for name, entry in pairs(QUI_Anchoring.anchorTargets) do
                if entry.frame == targetKeyOrFrame then
                    targetKey = name
                    break
                end
            end
        end
        if not targetKey then return end
    end

    -- In combat, only process CDM-driven targets. ApplyFrameAnchor keeps its own
    -- safety checks and will defer unsafe frame types automatically.
    if InCombatLockdown() then
        if targetKey ~= "cdmEssential" and targetKey ~= "cdmUtility" and targetKey ~= "buffIcon" and targetKey ~= "buffBar" then
            return
        end
    end

    local anchoringDB = QUICore and QUICore.db and QUICore.db.profile
        and QUICore.db.profile.frameAnchoring

    -- Walk the anchor chain: update direct dependents, then their dependents, etc.
    -- Use a BFS queue to avoid infinite loops from circular configs.
    local queue = { targetKey }
    local visited = { [targetKey] = true }

    while #queue > 0 do
        local currentTarget = table.remove(queue, 1)

        -- 1. Update legacy anchored frames for this target
        if QUI_Anchoring then
            QUI_Anchoring:UpdateFramesForTarget(currentTarget)
        end

        -- 2. Reapply frame anchoring overrides whose parent matches this target
        -- and enqueue the updated keys so their dependents are also updated
        if anchoringDB and QUI_Anchoring then
            for key, settings in pairs(anchoringDB) do
                if type(settings) == "table" and settings.enabled and settings.parent == currentTarget then
                    QUI_Anchoring:ApplyFrameAnchor(key, settings)
                    -- Enqueue this key so frames anchored to IT also update
                    if not visited[key] then
                        visited[key] = true
                        queue[#queue + 1] = key
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- EDIT MODE: keep non-CDM anchored system frames at QUI positions
--
-- During Edit Mode, Blizzard's layout system repositions system frames
-- to their default positions on layout events (enter, move, resize).
-- A 50ms C_Timer ticker reapplies QUI's anchor overrides fast enough
-- that any Blizzard override is corrected within ~3 render frames.
--
-- Why not OnUpdate?  Blizzard's C++ layout pass runs AFTER all Lua
-- OnUpdate handlers in the same render frame, so OnUpdate-based
-- reapply gets immediately overridden — causing per-frame oscillation.
-- A timer fires independently at the START of a frame, and since
-- Blizzard only re-layouts on specific events (not every frame),
-- QUI's positions persist between layout events.
--
-- CDM viewer keys are already skipped by ApplyFrameAnchor.
---------------------------------------------------------------------------

local _editModeTicker = nil
-- Track CDM viewer bounds to detect Blizzard's deferred Edit Mode layout changes.
-- Blizzard's slider (icon size, etc.) triggers internal layout passes that don't
-- fire SetScale or OnSizeChanged on the viewer, so we must poll for changes.
local _editModeLastBounds = {}

local function StopEditModeTicker()
    if _editModeTicker then
        _editModeTicker:Cancel()
        _editModeTicker = nil
    end
    _editModeLastBounds = {}
end

-- Helper: check if a child frame looks like a cooldown icon
local function IsIconChild(child)
    if not child then return false end
    return (child.Icon or child.icon) and (child.Cooldown or child.cooldown)
end

-- Measure the visual bounding box of icon children inside a CDM viewer.
-- Returns boundsW, boundsH, iconCount (all in screen-space UIParent coords).
-- Falls back to viewer frame bounds if no icons found.
local function MeasureCDMIconBounds(viewer)
    local boundsL, boundsR, boundsT, boundsB
    local iconCount = 0
    local sel = viewer.Selection

    for i = 1, viewer:GetNumChildren() do
        local child = select(i, viewer:GetChildren())
        if child and child ~= sel and IsIconChild(child) and child:IsShown() then
            local cl, cr, ct, cb = child:GetLeft(), child:GetRight(), child:GetTop(), child:GetBottom()
            if cl and cr and ct and cb then
                iconCount = iconCount + 1
                boundsL = boundsL and math.min(boundsL, cl) or cl
                boundsR = boundsR and math.max(boundsR, cr) or cr
                boundsT = boundsT and math.max(boundsT, ct) or ct
                boundsB = boundsB and math.min(boundsB, cb) or cb
            end
        end
    end

    if iconCount > 0 and boundsL and boundsR and boundsT and boundsB then
        return boundsR - boundsL, boundsT - boundsB, iconCount
    end

    -- Fallback: use viewer frame bounds
    local l, r, t, b = viewer:GetLeft(), viewer:GetRight(), viewer:GetTop(), viewer:GetBottom()
    if l and r and t and b then
        return r - l, t - b, 0
    end

    return 0, 0, 0
end

-- Check if a CDM viewer's icon bounds have changed, and if so, update
-- viewer state, proxies, power bars, and anchored frames.
local function CheckCDMViewerBoundsChanged(viewer, viewerKey, proxyKey)
    if not viewer or not viewer:IsShown() then return end

    local iconBoundsW, iconBoundsH, iconCount = MeasureCDMIconBounds(viewer)
    -- Use LOGICAL size (from Blizzard's slider) so the state tracks the
    -- slider in real-time.  Icon bounds are stale from QUI's previous
    -- LayoutViewer and create a dead zone when sliding down.
    local logW, logH = viewer:GetWidth() or 0, viewer:GetHeight() or 0
    local boundsW = logW
    local boundsH = logH
    if boundsW < 2 or boundsH < 2 then return end

    -- Also track viewer center for position changes (drag)
    local cx, cy = viewer:GetCenter()

    local isBuffViewer = viewerKey == "buffIcon" or viewerKey == "buffBar"
    local last = _editModeLastBounds[viewerKey]
    -- For buffIcon/buffBar, also check if icon bounds changed.  Blizzard's
    -- slider may change icon scale without resizing the viewer frame, so the
    -- viewer size stays constant while the visual icon extent changes.
    local ibMatch = true
    if isBuffViewer and last then
        ibMatch = math.abs((last.ibW or 0) - (iconBoundsW or 0)) < 0.5
             and math.abs((last.ibH or 0) - (iconBoundsH or 0)) < 0.5
    end
    if last and ibMatch and math.abs(last.w - boundsW) < 0.5 and math.abs(last.h - boundsH) < 0.5
           and math.abs((last.cx or 0) - (cx or 0)) < 0.5
           and math.abs((last.cy or 0) - (cy or 0)) < 0.5 then
        return  -- No change
    end

    -- Bounds changed — update everything
    _editModeLastBounds[viewerKey] = {
        w = boundsW, h = boundsH, cx = cx, cy = cy,
        ibW = iconBoundsW, ibH = iconBoundsH,
    }

    if QUI and QUI.DebugPrint then
        local scale = viewer.GetScale and viewer:GetScale() or 1
        QUI:DebugPrint(format("|cffFF8800CDM BoundsChanged|r %s: used=%.0fx%.0f iconBounds=%.0fx%.0f logical=%.0fx%.0f icons=%d scale=%.3f",
            viewerKey, boundsW, boundsH, iconBoundsW or 0, iconBoundsH or 0, logW, logH, iconCount, scale))
    end

    -- Update the viewer state so downstream consumers use the correct dimensions.
    -- cdm_viewer.lua exposes QUI_SetCDMViewerBounds for this purpose.
    if _G.QUI_SetCDMViewerBounds then
        _G.QUI_SetCDMViewerBounds(viewer, boundsW, boundsH)
    end

    -- For buffIcon/buffBar, sync the Edit Mode overlay to the measured
    -- icon bounds.  The overlay starts with SetAllPoints (= viewer size)
    -- but during Edit Mode the viewer's logical size includes Blizzard's
    -- slider padding, which is larger than the actual icon extent.
    -- Convert from UIParent coordinate space to overlay local space by
    -- dividing by the viewer's own scale.
    if isBuffViewer and iconCount > 0 then
        local viewerFrame = _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame(viewerKey)
        local viewerName = viewerFrame and viewerFrame:GetName()
        local overlay = viewerName and _G.QUI_GetCDMViewerOverlay and _G.QUI_GetCDMViewerOverlay(viewerName)
        if overlay and iconBoundsW > 1 and iconBoundsH > 1 then
            local vScale = viewer:GetScale() or 1
            if vScale <= 0 then vScale = 1 end
            overlay:ClearAllPoints()
            overlay:SetPoint("CENTER", viewer, "CENTER", 0, 0)
            overlay:SetSize(iconBoundsW / vScale, iconBoundsH / vScale)
        end
    end

    -- Update proxies (they read viewer state or frame bounds)
    UpdateCDMAnchorProxies()

    -- Update power bars locked to this CDM viewer
    if viewerKey == "essential" then
        if _G.QUI_UpdateLockedPowerBar then _G.QUI_UpdateLockedPowerBar() end
        if _G.QUI_UpdateLockedSecondaryPowerBar then _G.QUI_UpdateLockedSecondaryPowerBar() end
    elseif viewerKey == "utility" then
        if _G.QUI_UpdateLockedPowerBarToUtility then _G.QUI_UpdateLockedPowerBarToUtility() end
        if _G.QUI_UpdateLockedSecondaryPowerBarToUtility then _G.QUI_UpdateLockedSecondaryPowerBarToUtility() end
    end

    -- Update unit frames anchored to CDM
    if _G.QUI_UpdateAnchoredUnitFrames then
        _G.QUI_UpdateAnchoredUnitFrames()
    end

    -- Update frames anchored via the anchoring system
    if _G.QUI_UpdateFramesAnchoredTo then
        _G.QUI_UpdateFramesAnchoredTo(proxyKey)
    end
end

local function StartEditModeTicker()
    if _editModeTicker then return end
    _editModeTickerSilent = false
    _editModeLastBounds = {}

    -- Immediate reapply on Edit Mode enter
    if not InCombatLockdown() and QUI_Anchoring then
        QUI_Anchoring:ApplyAllFrameAnchors()
    end

    _editModeTicker = C_Timer.NewTicker(0.05, function()
        if not nsHelpers.IsEditModeActive() then
            StopEditModeTicker()
            return
        end
        if InCombatLockdown() then return end
        if QUI_Anchoring then
            QUI_Anchoring:ApplyAllFrameAnchors()
        end

        -- Poll CDM viewer bounds for changes (Blizzard's slider doesn't fire
        -- SetScale or OnSizeChanged, so we detect changes via bounds polling)
        CheckCDMViewerBoundsChanged(_G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("essential"), "essential", "cdmEssential")
        CheckCDMViewerBoundsChanged(_G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("utility"), "utility", "cdmUtility")
        CheckCDMViewerBoundsChanged(_G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("buffIcon"), "buffIcon", "buffIcon")
        CheckCDMViewerBoundsChanged(_G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("buffBar"), "buffBar", "buffBar")

        _editModeTickerSilent = true
    end)
end

if QUICore and QUICore.RegisterEditModeEnter then
    QUICore:RegisterEditModeEnter(function()
        AnchorDebug("EditMode ENTER — starting 50ms anchor ticker")
        StartEditModeTicker()
    end)
end

if QUICore and QUICore.RegisterEditModeExit then
    QUICore:RegisterEditModeExit(function()
        AnchorDebug("EditMode EXIT — stopping ticker, final reapply")
        StopEditModeTicker()
        _editModeTickerSilent = false
        -- Final reapply outside Edit Mode (no guards, all frames including CDM viewers)
        if not InCombatLockdown() and QUI_Anchoring then
            QUI_Anchoring:ApplyAllFrameAnchors()
        end
    end)
end
