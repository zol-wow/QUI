--[[
    QUI Anchoring Module
    Unified anchoring system for castbars, unit frames, and custom frames
    Supports 9-point anchoring with X/Y offsets and dynamic anchor target registration
]]

local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local nsHelpers = ns.Helpers

---------------------------------------------------------------------------
-- MODULE TABLE
---------------------------------------------------------------------------
local QUI_Anchoring = {}
ns.QUI_Anchoring = QUI_Anchoring

-- During early init, UIParent dimensions haven't settled (UI scale not fully
-- applied). Size-stable CENTER offset computation produces wrong values.
-- Force raw-point anchoring until dimensions are stable.
local _forceRawPointMode = true
C_Timer.After(0.5, function() _forceRawPointMode = false end)

-- Anchor target registry: { name = { frame = frame, options = {...} } }
QUI_Anchoring.anchorTargets = {}

-- Category registry: { categoryName = { order = number } }
QUI_Anchoring.categories = {}

-- Anchored frame registry: { frame = { anchorTarget = name, anchorPoint = point, offsetX = x, offsetY = y, parentFrame = frame } }
QUI_Anchoring.anchoredFrames = {}

-- Frames with active anchoring overrides — module positioning is blocked for these
QUI_Anchoring.layoutOwnedFrames = {}

local Helpers = {}

-- Forward-declared tables (populated later, referenced by ResolveFrameForKey)
local CDM_LOGICAL_SIZE_KEYS = {}

-- Edit Mode hook state (declared early so ApplyFrameAnchor can set the guard)
local _editModeReapplyGuard = false  -- prevents recursive reapply during QUI's own SetPoint

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

-- Smooth SetPoint: update an existing anchor in place when the point name
-- matches, avoiding the ClearAllPoints→SetPoint gap that causes a single-
-- frame visual "jiggle" (frame has no position between clear and set).
-- Falls back to ClearAllPoints+SetPoint when the point name differs or the
-- frame has multiple anchors.
local function SmoothSetPoint(frame, pt, relativeTo, relPt, x, y)
    local numPts = frame:GetNumPoints()
    if numPts == 1 then
        local cp = frame:GetPoint(1)
        if cp == pt then
            -- Same point name — update in place, no ClearAllPoints needed
            frame:SetPoint(pt, relativeTo, relPt, x, y)
            return
        end
    end
    frame:ClearAllPoints()
    frame:SetPoint(pt, relativeTo, relPt, x, y)
end

---------------------------------------------------------------------------
-- SECURE TAINT CLEANER — REMOVED (Unlock Mode replaced Edit Mode dependency)
-- Proxy-based positioning eliminated; all frame positioning defers to
-- PLAYER_REGEN_ENABLED when in combat. No taint to clean.
---------------------------------------------------------------------------

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
    if self.layoutOwnedFrames[frame] then return true end

    -- Defer positioning if in combat or secure context to avoid taint.
    -- Allow during ADDON_LOADED / PEW safe window (ns._inInitSafeWindow).
    if InCombatLockdown() and not ns._inInitSafeWindow then
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
    if self.layoutOwnedFrames[frame] then return true end

    -- Position immediately using multi-anchor system.
    -- Defer if in combat (unless in the ADDON_LOADED / PEW safe window).
    if InCombatLockdown() and not ns._inInitSafeWindow then
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
    if InCombatLockdown() and not ns._inInitSafeWindow then
        -- Avoid hot-loop requeueing during combat; process once on PLAYER_REGEN_ENABLED.
        pendingAnchoredFrameUpdateAfterCombat = true
        return
    end

    pendingAnchoredFrameUpdateAfterCombat = false

    local hasOverriddenFrames = false
    for frame, config in pairs(self.anchoredFrames) do
        -- Skip frames with active anchoring overrides — collect and reapply once after loop
        if self.layoutOwnedFrames[frame] then
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

-- Re-apply QUI anchors when Blizzard re-applies its Edit Mode layout.
-- This fires on spec change (Blizzard swaps per-spec Edit Mode layouts),
-- login, and any other scenario where Blizzard repositions system frames.
-- Without this, Blizzard's layout pass can override QUI's frame positions.
local layoutUpdateFrame = CreateFrame("Frame")
layoutUpdateFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
local _layoutUpdatePending = false
layoutUpdateFrame:SetScript("OnEvent", function()
    if _layoutUpdatePending then return end
    _layoutUpdatePending = true
    -- Delay to let Blizzard finish its full layout pass before we re-stamp
    C_Timer.After(0.3, function()
        _layoutUpdatePending = false
        if InCombatLockdown() then
            pendingAnchoredFrameUpdateAfterCombat = true
            return
        end
        if not nsHelpers.IsEditModeActive() then
            if QUI_Anchoring then
                QUI_Anchoring:ApplyAllFrameAnchors()
            end
            -- Also re-position unit frames and group frames — Blizzard's per-spec
            -- layout pass overwrites QUI's positions for frames not in the
            -- anchoring system
            local RefreshUnitFrames = _G.QUI_RefreshUnitFrames
            if RefreshUnitFrames then pcall(RefreshUnitFrames) end
            local RefreshGroupFrames = _G.QUI_RefreshGroupFrames
            if RefreshGroupFrames then pcall(RefreshGroupFrames) end
        end
    end)
end)

---------------------------------------------------------------------------
-- EDIT MODE ANCHOR GUARD (3-layer defense)
-- Prevents Blizzard Edit Mode from overwriting QUI's frame positions.
--
-- Layer 1: ApplySystemAnchor post-hooks on each managed Blizzard frame
--          (catches individual frame repositioning during layout apply)
-- Layer 2: EditModeManagerFrame ExitEditMode hook
--          (full reapply when the Edit Mode panel closes)
-- Layer 3: EDIT_MODE_LAYOUTS_UPDATED event (above)
--          (catches spec changes, login, and other layout swaps)
---------------------------------------------------------------------------

-- Forward declarations (defined later after FRAME_RESOLVERS table)
local HasFrameResolverForKey
local ResolveApplyFrameForKey

local _anchorGuardedFrames = {}  -- [frame] = true, prevents double-hooking

-- Layer 1: Hook ApplySystemAnchor on a single Blizzard frame
local function InstallAnchorGuard(frame, key)
    if _anchorGuardedFrames[frame] then return end
    if not frame.ApplySystemAnchor then return end
    _anchorGuardedFrames[frame] = true
    hooksecurefunc(frame, "ApplySystemAnchor", function()
        if _editModeReapplyGuard then return end
        -- Defer to escape Blizzard's secure execution context
        C_Timer.After(0, function()
            if InCombatLockdown() then
                pendingAnchoredFrameUpdateAfterCombat = true
                return
            end
            local anchoringDB = QUICore.db and QUICore.db.profile
                and QUICore.db.profile.frameAnchoring
            if anchoringDB and anchoringDB[key] then
                QUI_Anchoring:ApplyFrameAnchor(key, anchoringDB[key])
            end
        end)
    end)
end

-- Install anchor guards on all currently-resolvable managed frames
local function InstallAllAnchorGuards()
    local anchoringDB = QUICore.db and QUICore.db.profile
        and QUICore.db.profile.frameAnchoring
    if not anchoringDB then return end
    for key, settings in pairs(anchoringDB) do
        if type(settings) == "table" and HasFrameResolverForKey(key) then
            local frame = ResolveApplyFrameForKey(key)
            if frame then
                InstallAnchorGuard(frame, key)
            end
        end
    end
end

-- Layer 2: Reapply all positions when Edit Mode panel closes
if EditModeManagerFrame then
    hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
        C_Timer.After(0, function()
            if InCombatLockdown() then
                pendingAnchoredFrameUpdateAfterCombat = true
                return
            end
            InstallAllAnchorGuards()
            if QUI_Anchoring then
                QUI_Anchoring:ApplyAllFrameAnchors()
            end
            local RefreshUnitFrames = _G.QUI_RefreshUnitFrames
            if RefreshUnitFrames then pcall(RefreshUnitFrames) end
        end)
    end)
end

-- Install guards after initial anchoring pass and on PLAYER_ENTERING_WORLD
-- (all Blizzard frames exist by then)
local anchorGuardInitFrame = CreateFrame("Frame")
anchorGuardInitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
anchorGuardInitFrame:SetScript("OnEvent", function(f)
    f:UnregisterAllEvents()
    -- Delay to ensure ApplyAllFrameAnchors has run at least once
    C_Timer.After(1, InstallAllAnchorGuards)
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
    rotationAssistIcon = function()
        local frame = _G.QUI_RotationAssistIcon
        if frame then
            return frame
        end

        if _G.QUI and _G.QUI.RotationAssistIcon and _G.QUI.RotationAssistIcon.GetFrame then
            frame = _G.QUI.RotationAssistIcon.GetFrame()
            if frame then
                return frame
            end
        end

        -- Lazy-create if the module hasn't built it yet.
        if _G.QUI_RefreshRotationAssistIcon then
            _G.QUI_RefreshRotationAssistIcon()
            return _G.QUI_RotationAssistIcon
        end

        return nil
    end,
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
    petCastbar = function() return ns.QUI_Castbar and ns.QUI_Castbar.castbars and ns.QUI_Castbar.castbars["pet"] end,
    totCastbar = function() return ns.QUI_Castbar and ns.QUI_Castbar.castbars and ns.QUI_Castbar.castbars["targettarget"] end,
    -- Action Bars — engine-aware: owned containers when mirror engine is active,
    -- Blizzard frames otherwise (MainMenuBar renamed to MainActionBar in 12.0)
    bar1 = function()
        local owned = ns.ActionBarsOwned and ns.ActionBarsOwned.containers and ns.ActionBarsOwned.containers["bar1"]
        if owned then return owned end
        return _G["MainActionBar"] or _G["MainMenuBar"]
    end,
    bar2 = function()
        local owned = ns.ActionBarsOwned and ns.ActionBarsOwned.containers and ns.ActionBarsOwned.containers["bar2"]
        if owned then return owned end
        return _G["MultiBarBottomLeft"]
    end,
    bar3 = function()
        local owned = ns.ActionBarsOwned and ns.ActionBarsOwned.containers and ns.ActionBarsOwned.containers["bar3"]
        if owned then return owned end
        return _G["MultiBarBottomRight"]
    end,
    bar4 = function()
        local owned = ns.ActionBarsOwned and ns.ActionBarsOwned.containers and ns.ActionBarsOwned.containers["bar4"]
        if owned then return owned end
        return _G["MultiBarRight"]
    end,
    bar5 = function()
        local owned = ns.ActionBarsOwned and ns.ActionBarsOwned.containers and ns.ActionBarsOwned.containers["bar5"]
        if owned then return owned end
        return _G["MultiBarLeft"]
    end,
    bar6 = function()
        local owned = ns.ActionBarsOwned and ns.ActionBarsOwned.containers and ns.ActionBarsOwned.containers["bar6"]
        if owned then return owned end
        return _G["MultiBar5"]
    end,
    bar7 = function()
        local owned = ns.ActionBarsOwned and ns.ActionBarsOwned.containers and ns.ActionBarsOwned.containers["bar7"]
        if owned then return owned end
        return _G["MultiBar6"]
    end,
    bar8 = function()
        local owned = ns.ActionBarsOwned and ns.ActionBarsOwned.containers and ns.ActionBarsOwned.containers["bar8"]
        if owned then return owned end
        return _G["MultiBar7"]
    end,
    petBar = function()
        local owned = ns.ActionBarsOwned and ns.ActionBarsOwned.containers and ns.ActionBarsOwned.containers["pet"]
        if owned then return owned end
        return _G["PetActionBar"]
    end,
    stanceBar = function()
        local owned = ns.ActionBarsOwned and ns.ActionBarsOwned.containers and ns.ActionBarsOwned.containers["stance"]
        if owned then return owned end
        return _G["StanceBar"]
    end,
    microMenu = function()
        local owned = ns.ActionBarsOwned and ns.ActionBarsOwned.containers and ns.ActionBarsOwned.containers["microbar"]
        if owned then return owned end
        return _G["MicroMenuContainer"]
    end,
    bagBar = function()
        local owned = ns.ActionBarsOwned and ns.ActionBarsOwned.containers and ns.ActionBarsOwned.containers["bags"]
        if owned then return owned end
        return _G["BagsBar"]
    end,
    extraActionButton = function()
        return _G["QUI_extraActionButtonHolder"] or _G["ExtraActionBarFrame"]
    end,
    zoneAbility = function()
        return _G["QUI_zoneAbilityHolder"] or _G["ZoneAbilityFrame"]
    end,
    -- QoL
    brezCounter = function() return _G["QUI_BrezCounter"] end,
    atonementCounter = function() return _G["QUI_AtonementCounter"] end,
    combatTimer = function() return _G["QUI_CombatTimer"] end,
    rangeCheck = function() return _G["QUI_RangeCheckFrame"] end,
    actionTracker = function() return _G["QUI_ActionTracker"] end,
    xpTracker = function() return _G["QUI_XPTracker"] end,
    skyriding = function() return _G["QUI_Skyriding"] end,
    petWarning = function() return _G["QUI_PetWarningFrame"] end,
    focusCastAlert = function() return _G["QUI_FocusCastAlertFrame"] end,
    missingRaidBuffs = function() return _G["QUI_MissingRaidBuffs"] end,
    mplusTimer = function() return _G["QUI_MPlusTimerFrame"] end,
    preyTracker = function() return _G["QUI_PreyTracker"] end,
    crosshair = function() return _G["QUI_Crosshair"] end,
    totemBar = function()
        local owned = ns.QUI_TotemBar and ns.QUI_TotemBar.container
        if owned then return owned end
        return _G["TotemFrame"]
    end,
    readyCheck = function() return _G["ReadyCheckFrame"] end,
    consumables = function() return _G["QUI_ConsumablesFrame"] end,
    alertAnchor = function() return _G["QUI_AlertFrameHolder"] end,
    toastAnchor = function() return _G["QUI_EventToastHolder"] end,
    bnetToastAnchor = function() return _G["QUI_BNetToastHolder"] end,
    tooltipAnchor = function() return _G["QUI_TooltipAnchor"] end,
    powerBarAlt = function() return _G["QUI_AltPowerBar"] end,
    lootFrame = function() return _G["QUI_LootFrame"] end,
    lootRollAnchor = function() return _G["QUI_LootRollAnchor"] end,
    partyKeystones = function() return _G["QUIKeyTrackerFrame"] end,
    -- Group Frames
    -- During edit/test mode the headers are hidden and re-parented to the mover;
    -- return the mover/test container so anchoring works with preview frames.
    partyFrames = function()
        local GFEM = ns.QUI_GroupFrameEditMode
        if GFEM then
            local active = GFEM:GetActiveFrame("party")
            if active then return active end
        end
        -- Return the anchor root frame so ApplyFrameAnchor positions the root.
        -- Headers are arranged within the root by UpdateAnchorRoot.
        local GF = ns.QUI_GroupFrames
        if GF and GF.anchorFrames and GF.anchorFrames.party then
            return GF.anchorFrames.party
        end
        return GF and GF.headers and GF.headers.party
    end,
    raidFrames = function()
        local GFEM = ns.QUI_GroupFrameEditMode
        if GFEM then
            local active = GFEM:GetActiveFrame("raid")
            if active then return active end
        end
        -- Return the anchor root frame so ApplyFrameAnchor positions the root.
        -- Headers are arranged within the root by UpdateAnchorRoot.
        local GF = ns.QUI_GroupFrames
        if GF and GF.anchorFrames and GF.anchorFrames.raid then
            return GF.anchorFrames.raid
        end
        return GF and GF.headers and GF.headers.raid
    end,
    -- Display
    minimap = function() return _G["Minimap"] end,
    datatextPanel = function() return _G["QUI_DatatextPanel"] end,
    objectiveTracker = function() return _G["ObjectiveTrackerFrame"] end,
    topCenterWidgets = function() return _G["UIWidgetTopCenterContainerFrame"] end,
    belowMinimapWidgets = function() return _G["UIWidgetBelowMinimapContainerFrame"] end,
    buffFrame = function() return _G["QUI_BuffIconContainer"] or _G["BuffFrame"] end,
    debuffFrame = function() return _G["QUI_DebuffIconContainer"] or _G["DebuffFrame"] end,
    chatFrame1 = function() return _G["ChatFrame1"] end,
    -- External (DandersFrames, AbilityTimeline)
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
    abilityTimelineTimeline = function()
        return _G["AbilityTimelineFrame"]
    end,
    abilityTimelineBigIcon = function()
        return _G["AbilityTimelineBigIconFrame"]
    end,
}

local CUSTOM_TRACKER_ANCHOR_PREFIX = "customTracker:"
local CUSTOM_TRACKER_ANCHOR_CATEGORY = "Cooldown Manager & Custom Tracker Bars"
local CUSTOM_TRACKER_ANCHOR_CATEGORY_ORDER = 90

local function GetCustomTrackerBarIDFromAnchorKey(key)
    if type(key) ~= "string" then return nil end
    if key:sub(1, #CUSTOM_TRACKER_ANCHOR_PREFIX) ~= CUSTOM_TRACKER_ANCHOR_PREFIX then
        return nil
    end
    local barID = key:sub(#CUSTOM_TRACKER_ANCHOR_PREFIX + 1)
    if barID == "" then
        return nil
    end
    return barID
end

local function ResolveCustomTrackerFrameForKey(key)
    local barID = GetCustomTrackerBarIDFromAnchorKey(key)
    if not barID then
        return nil
    end
    local trackerModule = QUICore and QUICore.CustomTrackers
    local activeBars = trackerModule and trackerModule.activeBars
    if not activeBars then
        return nil
    end
    return activeBars[barID]
end

HasFrameResolverForKey = function(key)
    if FRAME_RESOLVERS[key] then
        return true
    end
    return GetCustomTrackerBarIDFromAnchorKey(key) ~= nil
end

-- Resolve a frame for direct anchoring apply.
-- Important: keep static keys on their original resolver path (no proxy substitution),
-- and only use dynamic resolution for custom tracker keys.
ResolveApplyFrameForKey = function(key)
    local resolver = FRAME_RESOLVERS[key]
    if resolver then
        local frame = resolver()
        if type(frame) == "table" and not frame.GetObjectType then
            frame = frame[1]
        end
        return frame
    end
    return ResolveCustomTrackerFrameForKey(key)
end

-- Blizzard-managed right-side frames are controlled by UIParentPanelManager.
-- Previously objectiveTracker, buffFrame, and debuffFrame were blocked here,
-- but the existing combat deferral and SecureHandlerStateTemplate taint cleaner
-- already handle taint safety for Edit Mode system frames, so they now use the
-- normal ApplyFrameAnchor path.
local UNSAFE_BLIZZARD_MANAGED_OVERRIDES = {
}

-- Frame display info for anchor target registration
local FRAME_ANCHOR_INFO = {
    cdmEssential    = { displayName = "CDM Essential Viewer",  category = "Cooldown Manager & Custom Tracker Bars",  order = 1 },
    cdmUtility      = { displayName = "CDM Utility Viewer",    category = "Cooldown Manager & Custom Tracker Bars",  order = 2 },
    buffIcon        = { displayName = "CDM Buff Icons",        category = "Cooldown Manager & Custom Tracker Bars",  order = 3 },
    buffBar         = { displayName = "CDM Buff Bars",         category = "Cooldown Manager & Custom Tracker Bars",  order = 4 },
    rotationAssistIcon = { displayName = "CDM Rotation Assist Icon", category = "Cooldown Manager & Custom Tracker Bars", order = 5 },
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
    petCastbar      = { displayName = "Pet Castbar",           category = "Castbars",          order = 4 },
    totCastbar      = { displayName = "Target of Target Castbar", category = "Castbars",       order = 5 },
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
    atonementCounter = { displayName = "Atonement Counter",    category = "QoL",               order = 2 },
    combatTimer     = { displayName = "Combat Timer",          category = "QoL",               order = 3 },
    rangeCheck      = { displayName = "Target Distance Bracket Display", category = "QoL",      order = 4 },
    actionTracker   = { displayName = "Action Tracker",        category = "QoL",               order = 5 },
    xpTracker       = { displayName = "XP Tracker",            category = "QoL",               order = 6 },
    skyriding       = { displayName = "Skyriding",             category = "QoL",               order = 7 },
    petWarning      = { displayName = "Pet Warning",           category = "QoL",               order = 8 },
    focusCastAlert  = { displayName = "Focus Cast Alert",      category = "QoL",               order = 9 },
    missingRaidBuffs = { displayName = "Missing Raid Buffs",   category = "QoL",               order = 10 },
    mplusTimer      = { displayName = "M+ Timer",              category = "QoL",               order = 11 },
    readyCheck      = { displayName = "Ready Check",           category = "QoL",               order = 12 },
    preyTracker     = { displayName = "Prey Tracker",          category = "QoL",               order = 13 },
    partyFrames     = { displayName = "Party Frames",           category = "Group Frames",      order = 1 },
    raidFrames      = { displayName = "Raid Frames",            category = "Group Frames",      order = 2 },
    minimap         = { displayName = "Minimap",               category = "Display",           order = 1 },
    objectiveTracker = { displayName = "Objective Tracker",    category = "Display",           order = 2 },
    topCenterWidgets = { displayName = "Top Center Widgets",  category = "Display",           order = 3 },
    belowMinimapWidgets = { displayName = "Below Minimap Widgets", category = "Display",      order = 4 },
    buffFrame       = { displayName = "Buff Frame",            category = "Display",           order = 5 },
    debuffFrame     = { displayName = "Debuff Frame",          category = "Display",           order = 6 },
    chatFrame1      = { displayName = "Chat Frame",            category = "Display",           order = 7 },
    datatextPanel   = { displayName = "Datatext Panel",        category = "Display",           order = 8 },
    dandersParty    = { displayName = "DandersFrames Party",   category = "External",          order = 1 },
    dandersRaid     = { displayName = "DandersFrames Raid",    category = "External",          order = 2 },
    abilityTimelineTimeline = { displayName = "AbilityTimeline Timeline", category = "External", order = 3 },
    abilityTimelineBigIcon = { displayName = "AbilityTimeline Big Icon", category = "External", order = 4 },
}
ns.FRAME_ANCHOR_INFO = FRAME_ANCHOR_INFO

-- Phase G: Global hook for dynamic frame resolver registration from CDM containers.
-- Called by CDMContainers when creating custom containers.
_G.QUI_RegisterFrameResolver = function(key, info)
    if not key then return end
    if info.resolver then
        FRAME_RESOLVERS[key] = info.resolver
    end
    if info.displayName then
        FRAME_ANCHOR_INFO[key] = {
            displayName = info.displayName,
            category = info.category or "Cooldown Manager & Custom Tracker Bars",
            order = info.order or 100,
        }
    end
    -- CDM containers use logical sizing from viewerState
    if info.category == "Cooldown Manager & Custom Tracker Bars" and CDM_LOGICAL_SIZE_KEYS then
        CDM_LOGICAL_SIZE_KEYS[key] = true
    end
    -- Immediately register as anchor target so it appears in dropdowns
    -- even if RegisterAllFrameTargets already ran at init.
    if info.resolver and QUI_Anchoring and QUI_Anchoring.RegisterAnchorTarget then
        local frame = info.resolver()
        if frame then
            QUI_Anchoring:RegisterAnchorTarget(key, frame, {
                displayName = info.displayName or key,
                category = info.category or "Cooldown Manager & Custom Tracker Bars",
                categoryOrder = info.order or 100,
                order = info.order or 100,
            })
        end
    end
end

-- Phase G: Global hook to unregister a dynamic frame resolver.
_G.QUI_UnregisterFrameResolver = function(key)
    if not key then return end
    FRAME_RESOLVERS[key] = nil
    FRAME_ANCHOR_INFO[key] = nil
    if CDM_LOGICAL_SIZE_KEYS then
        CDM_LOGICAL_SIZE_KEYS[key] = nil
    end
end

local hideWithParentHidden = {}  -- keys hidden because their anchor parent is hidden
local _visibilityHooked = {}    -- [frame] = true — prevents double-hooking OnShow/OnHide
local FRAME_ANCHOR_FALLBACKS    -- forward-declared; table populated below
local HUD_MIN_WIDTH_DEFAULT = (ns.Helpers and ns.Helpers.HUD_MIN_WIDTH_DEFAULT) or 200

---------------------------------------------------------------------------
-- ANCHOR PROXY SYSTEM REMOVED (Unlock Mode replaced Edit Mode dependency)
-- Proxy-based positioning eliminated; all frame positioning defers to
-- PLAYER_REGEN_ENABLED when in combat for protected frames.
---------------------------------------------------------------------------



-- Fallback anchor targets for when a resolved frame is unavailable (nil or hidden).
-- e.g. classes without a secondary resource should fall back to the primary bar.
FRAME_ANCHOR_FALLBACKS = {
    secondaryPower = "primaryPower",
    petFrame = "playerFrame",
    totFrame = "targetFrame",
}

-- Helper: resolve a single key to a visible frame (nil if unavailable)
local function ResolveFrameForKey(key)
    -- Dynamic custom tracker bars (customTracker:<barID>)
    do
        local customTrackerFrame = ResolveCustomTrackerFrameForKey(key)
        if customTrackerFrame then return customTrackerFrame end
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

-- Hook OnShow/OnHide on a frame so that when its visibility changes,
-- ApplyAllFrameAnchors re-runs. This lets children that were chain-walked
-- to a grandparent snap back when the intermediate parent reappears (and
-- vice versa when it hides again).
-- Also hooks SetAlpha: some frames (e.g. unit frames controlled by HUD
-- visibility) fade to alpha 0 instead of calling Hide(). We detect when
-- the effective alpha crosses the ~0 threshold and re-evaluate anchors.
local function InstallVisibilityHook(frame)
    if not frame or _visibilityHooked[frame] then return end
    if not frame.HookScript then return end
    _visibilityHooked[frame] = true
    local function onVisibilityChanged()
        if QUI_Anchoring then
            QUI_Anchoring:ApplyAllFrameAnchors()
        end
    end
    frame:HookScript("OnShow", onVisibilityChanged)
    frame:HookScript("OnHide", onVisibilityChanged)
    -- Detect alpha-based visibility changes (HUD fade system)
    if frame.SetAlpha then
        local curAlpha = frame:GetAlpha()
        local wasAlphaHidden = type(curAlpha) == "number" and curAlpha < 0.01
        hooksecurefunc(frame, "SetAlpha", function(self, alpha)
            if type(alpha) ~= "number" then return end  -- secret value, ignore
            local isAlphaHidden = alpha < 0.01
            if isAlphaHidden ~= wasAlphaHidden then
                wasAlphaHidden = isAlphaHidden
                onVisibilityChanged()
            end
        end)
    end
end

-- Resolve an anchor parent key to a frame.
-- Follows the FRAME_ANCHOR_FALLBACKS chain first, then walks up the user's
-- configured anchor chain when the resolved frame is nil or hidden
-- (e.g. Objective Tracker → Data Text Panel → Minimap: if the Data Text Panel
-- is disabled, follows Data Text Panel's own parent to reach Minimap).
--
-- Returns: frame, chainSettings
--   frame         — the resolved visible parent frame (or UIParent)
--   chainSettings — when a chain walk occurred via the user's anchoring config,
--                   contains the anchor settings of the last hidden link so the
--                   caller can adopt its anchor points (replacing the hidden
--                   frame in the chain rather than using the child's own points).
--                   nil when no chain walk happened or only hardcoded fallbacks
--                   were used.
local function ResolveParentFrame(parentKey)
    if not parentKey or parentKey == "screen" or parentKey == "disabled" then
        return UIParent, nil
    end

    local key = parentKey
    local visited = {}  -- guard against circular fallback chains

    -- Grab the user's anchoring config for dynamic chain walking
    local anchoringDB = QUICore and QUICore.db and QUICore.db.profile
        and QUICore.db.profile.frameAnchoring

    -- Track the last hidden link's settings when walking the user's config chain
    local lastChainSettings = nil

    while key do
        if visited[key] then break end
        visited[key] = true

        local frame = ResolveFrameForKey(key)

        -- Frame exists and is shown (or at least alpha-shown) → use it
        if frame and frame.IsShown and frame:IsShown() then
            return frame, lastChainSettings
        end

        -- In Layout Mode, treat hidden-but-enabled frames as valid anchor
        -- targets. The mover overlay is visible even when the actual frame is
        -- hidden (e.g. pet bar on a class with no pet), so dependents should
        -- still anchor to it rather than walking up the chain.
        if frame and ns.QUI_LayoutMode and ns.QUI_LayoutMode.isActive then
            return frame, lastChainSettings
        end

        -- Frame exists but hidden — hook its visibility so that when it
        -- reappears, children that chain-walked past it get re-anchored back.
        if frame then
            InstallVisibilityHook(frame)
        end

        -- Frame unavailable → try hardcoded fallback first
        local fallback = FRAME_ANCHOR_FALLBACKS[key]
        if fallback then
            key = fallback
        else
            -- No hardcoded fallback — walk up the user's configured anchor chain.
            -- If key itself has an anchor override with a parent, try that parent
            -- (e.g. datatextPanel is anchored to minimap → use minimap).
            local chainEntry = anchoringDB and anchoringDB[key]
            local chainParent = chainEntry and chainEntry.parent
            if chainParent and chainParent ~= "screen" and chainParent ~= "disabled" then
                -- Remember this hidden link's anchor settings so the child can
                -- adopt them (replacing the hidden frame in the visual chain).
                lastChainSettings = chainEntry
                key = chainParent
            else
                -- End of the chain; return the frame if it exists (even if hidden)
                -- so that anchored frames keep their reference, or UIParent as last resort
                return frame or UIParent, lastChainSettings
            end
        end
    end

    return UIParent, lastChainSettings
end

-- No-op stubs: proxy system removed (Unlock Mode replaced Edit Mode dependency)
_G.QUI_UpdateCDMAnchorProxyFrames = function() end
_G.QUI_GetCDMAnchorProxyFrame = function() return nil end

local function ClearCustomTrackerAnchorTargets()
    for name in pairs(QUI_Anchoring.anchorTargets) do
        if GetCustomTrackerBarIDFromAnchorKey(name) then
            QUI_Anchoring.anchorTargets[name] = nil
        end
    end
end

local function RegisterCustomTrackerAnchorTargets(self)
    ClearCustomTrackerAnchorTargets()

    local profile = QUICore and QUICore.db and QUICore.db.profile
    local bars = profile and profile.customTrackers and profile.customTrackers.bars
    if type(bars) ~= "table" then
        return
    end

    for index, barConfig in ipairs(bars) do
        local barID = barConfig and barConfig.id
        if type(barID) == "string" and barID ~= "" then
            local anchorKey = CUSTOM_TRACKER_ANCHOR_PREFIX .. barID
            local frame = ResolveCustomTrackerFrameForKey(anchorKey)
            if frame then
                local displayName = barConfig.name
                if type(displayName) ~= "string" or displayName == "" then
                    displayName = ("CDM Bar %d"):format(index)
                end
                self:RegisterAnchorTarget(anchorKey, frame, {
                    displayName = displayName,
                    category = CUSTOM_TRACKER_ANCHOR_CATEGORY,
                    categoryOrder = CUSTOM_TRACKER_ANCHOR_CATEGORY_ORDER,
                    order = index,
                })
            end
        end
    end
end

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
    RegisterCustomTrackerAnchorTargets(self)
end

-- Helper: mark a frame as layout-owned (blocks module positioning)
-- Stores the layout key (e.g. "playerFrame") so callers can do targeted reapply
local function SetFrameOverride(frame, active, key)
    if not frame then return end
    -- Boss frames resolver returns an array
    if type(frame) == "table" and not frame.GetObjectType then
        for _, f in ipairs(frame) do
            QUI_Anchoring.layoutOwnedFrames[f] = active and key or nil
        end
        -- Also mark BossTargetFrameContainer so internal anchoring checks
        -- on the container (used by Edit Mode overlay/nudge systems) work
        if BossTargetFrameContainer then
            QUI_Anchoring.layoutOwnedFrames[BossTargetFrameContainer] = active and key or nil
        end
    else
        QUI_Anchoring.layoutOwnedFrames[frame] = active and key or nil
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
    petCastbar = true,
    totCastbar = true,
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

    -- CDM viewers: prefer logical layout dimensions when available.
    if parentKey then
        -- Normalize aliases (settings.parent may store the short form)
        if parentKey == "essential" then parentKey = "cdmEssential"
        elseif parentKey == "utility" then parentKey = "cdmUtility" end

        if CDM_LOGICAL_SIZE_KEYS[parentKey] then
            local resolver = FRAME_RESOLVERS[parentKey]
            local sourceFrame = resolver and resolver()
            if sourceFrame then
                local vs = _G.QUI_GetCDMViewerState and _G.QUI_GetCDMViewerState(sourceFrame)
                if vs then
                    width = vs.row1Width or vs.iconWidth
                    height = vs.totalHeight
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

    return math.max(1, width), math.max(1, height)
end

-- Layout mode handles enforce a minimum size of 20px. Offsets saved in
-- layout mode are computed relative to handle edges, so anchor-point math
-- here must use the same inflated dimensions for very small anchor markers.
-- Only inflate dimensions that are clearly positioning-only anchors (≤ 2px),
-- not real UI elements like thin power bars (4px+) whose saved offsets were
-- tuned against real frame dimensions.
local LAYOUT_HANDLE_MIN = 20
local TINY_ANCHOR_THRESHOLD = 3

local function ComputeCenterOffsetsForAnchor(frame, key, parentFrame, sourcePoint, targetPoint, offsetX, offsetY, parentKey)
    local frameW, frameH = GetFrameAnchorRect(frame, key)
    local parentW, parentH = GetParentAnchorRect(parentFrame, parentKey)

    -- Inflate very small dimensions (≤ 2px anchor markers) to the layout
    -- mode handle minimum. These are positioning-only frames whose handles
    -- were inflated to 20px — saved offsets reference the handle edges, not
    -- the real 1-2px frame edges. Applies to both parent (anchor target)
    -- and child (frame being positioned) when they're tiny markers.
    if parentFrame and parentFrame ~= UIParent then
        if parentW < TINY_ANCHOR_THRESHOLD then parentW = LAYOUT_HANDLE_MIN end
        if parentH < TINY_ANCHOR_THRESHOLD then parentH = LAYOUT_HANDLE_MIN end
    end
    if frameW < TINY_ANCHOR_THRESHOLD then frameW = LAYOUT_HANDLE_MIN end
    if frameH < TINY_ANCHOR_THRESHOLD then frameH = LAYOUT_HANDLE_MIN end

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
            -- Resource bars size to the actual source frame, not the proxy.
            -- The proxy min-width floor is meant for player/target only.
            local isResourceBar = (key == "primaryPower" or key == "secondaryPower")
            if isResourceBar then
                local parentKey = settings.parent
                if parentKey == "essential" then parentKey = "cdmEssential"
                elseif parentKey == "utility" then parentKey = "cdmUtility" end
                -- Resource bars should size to the actual icon content width.
                -- For CDM sources, prefer viewer state rawContentWidth (the
                -- pre-inflation icon row width). For non-CDM sources (e.g.
                -- another resource bar), use the source frame's GetWidth.
                local resolver = parentKey and FRAME_RESOLVERS[parentKey]
                local sourceFrame = resolver and resolver()
                if sourceFrame then
                    local contentWidth
                    if CDM_LOGICAL_SIZE_KEYS[parentKey] then
                        local vs = _G.QUI_GetCDMViewerState and _G.QUI_GetCDMViewerState(sourceFrame)
                        contentWidth = vs and vs.rawContentWidth
                    end
                    if not contentWidth or contentWidth <= 0 then
                        local frameOk, frameWidth = pcall(function() return sourceFrame:GetWidth() end)
                        if frameOk and frameWidth and frameWidth > 0 then
                            contentWidth = frameWidth
                        end
                    end
                    if contentWidth and contentWidth > 0 then
                        parentWidth = contentWidth
                    end
                end
            end
            local adjustedWidth = parentWidth + (settings.widthAdjust or 0)
            if adjustedWidth > 0 then
                pcall(function() frame:SetWidth(adjustedWidth) end)
                -- Resource bars use fragmented power displays (runes, essence)
                -- that size from bar:GetWidth(). Trigger a module refresh so
                -- fragments re-layout to match the new width.
                if isResourceBar then
                    C_Timer.After(0, function()
                        if key == "primaryPower" then
                            if QUICore and QUICore.UpdatePowerBar then QUICore:UpdatePowerBar() end
                        elseif key == "secondaryPower" then
                            if QUICore and QUICore.UpdateSecondaryPowerBar then QUICore:UpdateSecondaryPowerBar() end
                        end
                    end)
                end
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
    if type(settings) ~= "table" then return end

    if not HasFrameResolverForKey(key) then
        return
    end

    local resolved = ResolveApplyFrameForKey(key)
    if not resolved then
        return
    end

    -- Never anchor UIParent-managed right-side frames from addon code.
    -- Keep them on Blizzard defaults to avoid protected layout taint.
    -- Still mark them overridden so internal anchoring checks work.
    if UNSAFE_BLIZZARD_MANAGED_OVERRIDES[key] then
        SetFrameOverride(resolved, true, key)
        return
    end

    -- Mark frame as overridden FIRST — blocks any module positioning from this point on
    SetFrameOverride(resolved, true, key)

    -- Defer protected frames to combat end; non-protected addon frames can
    -- still be repositioned during combat. Skip the bail during the
    -- ADDON_LOADED / PLAYER_ENTERING_WORLD safe window where protected calls
    -- are allowed even in combat (ns._inInitSafeWindow).
    if InCombatLockdown() and not ns._inInitSafeWindow then
        local isProtected = false
        if type(resolved) == "table" and not resolved.GetObjectType then
            -- Boss frames array — check first frame
            local first = resolved[1]
            isProtected = first and first.IsProtected and first:IsProtected()
        else
            isProtected = resolved.IsProtected and resolved:IsProtected()
        end
        if isProtected then
            pendingAnchoredFrameUpdateAfterCombat = true
            return
        end
    end

    -- hideWithParent: skip fallback chain, hide child when direct parent is hidden
    local parentFrame
    if settings.hideWithParent then
        local directParent = ResolveFrameForKey(settings.parent)
        -- Hook visibility so we re-evaluate when the parent shows/hides
        if directParent then
            InstallVisibilityHook(directParent)
        end
        local directVisible = directParent and directParent.IsShown and directParent:IsShown()
        -- Also treat alpha ≈ 0 as hidden (HUD visibility fades frames
        -- to alpha 0 instead of calling Hide, so IsShown stays true).
        if directVisible and directParent.GetAlpha then
            local parentAlpha = directParent:GetAlpha()
            if type(parentAlpha) == "number" and parentAlpha < 0.01 then
                directVisible = false
            end
        end
        if not directVisible then
            -- Parent hidden/missing — hide the child frame
            local canMutate = not InCombatLockdown()
                or not (resolved.IsProtected and resolved:IsProtected())
            if canMutate then
                if type(resolved) == "table" and not resolved.GetObjectType then
                    for _, frame in ipairs(resolved) do pcall(frame.Hide, frame) end
                else
                    pcall(resolved.Hide, resolved)
                end
            end
            hideWithParentHidden[key] = true
            return
        end
        -- Direct parent visible — restore child if we previously hid it
        if hideWithParentHidden[key] then
            local canMutate = not InCombatLockdown()
                or not (resolved.IsProtected and resolved:IsProtected())
            if canMutate then
                if type(resolved) == "table" and not resolved.GetObjectType then
                    for _, frame in ipairs(resolved) do pcall(frame.Show, frame) end
                else
                    pcall(resolved.Show, resolved)
                end
            end
            hideWithParentHidden[key] = nil
        end
        parentFrame = directParent
    elseif settings.keepInPlace then
        -- Keep In Place: anchor directly to the parent frame even if hidden.
        -- WoW's SetPoint works on hidden frames, so the child stays at the
        -- correct relative position. No chain walk, no settings adoption.
        local directParent = ResolveFrameForKey(settings.parent)
        if directParent then
            InstallVisibilityHook(directParent)
        end
        parentFrame = directParent or UIParent
    elseif CASTBAR_ANCHOR_KEYS[key] then
        -- Castbars use alpha-based visibility and are always :Show(). Skip
        -- chain walk entirely — always anchor to the direct parent even when
        -- it is hidden. Chain walking would override point/relative with the
        -- intermediate parent's settings (e.g. CENTER/CENTER), losing the
        -- castbar's explicit relation (e.g. TOP→BOTTOM).
        parentFrame = ResolveFrameForKey(settings.parent) or UIParent
    else
        local chainSettings
        parentFrame, chainSettings = ResolveParentFrame(settings.parent)

        -- When a chain walk occurred (hidden intermediate frame), adopt the
        -- last hidden link's anchor points so the child "replaces" it visually.
        -- e.g. stance bar (BL→TL of pet bar) falls back to bar 6 — should use
        -- pet bar's anchor points (BL→BR of bar 6), not stance bar's own.
        if chainSettings then
            settings = {
                point = chainSettings.point or settings.point,
                relative = chainSettings.relative or settings.relative,
                offsetX = chainSettings.offsetX or settings.offsetX,
                offsetY = chainSettings.offsetY or settings.offsetY,
                sizeStableAnchoring = settings.sizeStableAnchoring,
            }
        end
    end

    -- If parent is hidden, anchor directly to it — when it becomes visible
    -- and gets repositioned, the child follows automatically.
    -- (No chain walk needed without proxy system.)

    local point = settings.point or "CENTER"
    local relative = settings.relative or "CENTER"
    local offsetX = settings.offsetX or 0
    local offsetY = settings.offsetY or 0
    local useSizeStable = IsSizeStableAnchoringEnabled(settings)
    -- During early init, UIParent dimensions haven't settled — CENTER offset
    -- computation produces wrong values. Use raw point instead; deferred
    -- timers will reapply with correct CENTER offsets later.
    if _forceRawPointMode then
        useSizeStable = false
    end
    if CASTBAR_ANCHOR_KEYS[key] then
        -- Castbars should preserve the explicit point relation (e.g. TOP->BOTTOM)
        -- so they track parent edge movement automatically in combat.
        useSizeStable = false
    end
    if key == "buffBar" or key == "buffFrame" or key == "debuffFrame" then
        -- Buff/debuff containers change size dynamically as auras appear/disappear.
        -- Raw point anchoring keeps the growth edge fixed.
        useSizeStable = false
    end

    -- Boss frames: single setting applied to all with stacking Y offset
    if key == "bossFrames" and type(resolved) == "table" and not resolved.GetObjectType then
        for i, frame in ipairs(resolved) do
            local stackOffsetY = offsetY - ((i - 1) * 50)
            if useSizeStable then
                ApplyAutoSizing(frame, settings, parentFrame, key)
            end
            local targetPt, targetRelPt, targetX, targetY
            if useSizeStable then
                local centerX, centerY = ComputeCenterOffsetsForAnchor(
                    frame, key, parentFrame, point, relative, offsetX, stackOffsetY, settings.parent
                )
                targetPt, targetRelPt, targetX, targetY = "CENTER", "CENTER", centerX, centerY
            else
                targetPt, targetRelPt, targetX, targetY = point, relative, offsetX, stackOffsetY
            end
            if not FrameAlreadyAtPosition(frame, targetPt, parentFrame, targetRelPt, targetX, targetY) then
                _editModeReapplyGuard = true
                pcall(SmoothSetPoint, frame, targetPt, parentFrame, targetRelPt, targetX, targetY)
                _editModeReapplyGuard = false
            end
        end
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
        ApplyAutoSizing(resolved, settings, parentFrame, key)
        local centerX, centerY = ComputeCenterOffsetsForAnchor(
            resolved, key, parentFrame, point, relative, offsetX, offsetY, settings.parent
        )
        if not FrameAlreadyAtPosition(resolved, "CENTER", parentFrame, "CENTER", centerX, centerY) then
            _editModeReapplyGuard = true
            pcall(SmoothSetPoint, resolved, "CENTER", parentFrame, "CENTER", centerX, centerY)
            _editModeReapplyGuard = false
        end
    else
        -- When parent or child frame is a tiny anchor marker (≤ 2px),
        -- saved offsets were computed against inflated handle edges. Raw
        -- SetPoint uses real frame edges, so convert to CENTER→CENTER with
        -- inflated dimensions to match the visual position from layout mode.
        -- Skip for dynamically-sized containers (buff/debuff) — they start
        -- at 1x1 intentionally and grow as icons appear; converting to
        -- CENTER would break the growth-edge anchoring that LayoutIcons
        -- depends on.
        local skipInflation = key == "buffFrame" or key == "debuffFrame" or key == "buffBar"
        local needsInflation = false
        if not skipInflation and parentFrame and parentFrame ~= UIParent and parentFrame.GetSize then
            local ok, pw, ph = pcall(parentFrame.GetSize, parentFrame)
            if ok and pw and ph and (pw < TINY_ANCHOR_THRESHOLD or ph < TINY_ANCHOR_THRESHOLD) then
                needsInflation = true
            end
        end
        if not skipInflation and not needsInflation and resolved and resolved.GetSize then
            local ok, rw, rh = pcall(resolved.GetSize, resolved)
            if ok and rw and rh and (rw < TINY_ANCHOR_THRESHOLD or rh < TINY_ANCHOR_THRESHOLD) then
                needsInflation = true
            end
        end
        if needsInflation then
            local centerX, centerY = ComputeCenterOffsetsForAnchor(
                resolved, key, parentFrame, point, relative, offsetX, offsetY, settings.parent
            )
            if not FrameAlreadyAtPosition(resolved, "CENTER", parentFrame, "CENTER", centerX, centerY) then
                _editModeReapplyGuard = true
                pcall(SmoothSetPoint, resolved, "CENTER", parentFrame, "CENTER", centerX, centerY)
                _editModeReapplyGuard = false
            end
        else
            if not FrameAlreadyAtPosition(resolved, point, parentFrame, relative, offsetX, offsetY) then
                _editModeReapplyGuard = true
                pcall(SmoothSetPoint, resolved, point, parentFrame, relative, offsetX, offsetY)
                _editModeReapplyGuard = false
            end
        end
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
        if type(settings) == "table" and HasFrameResolverForKey(key) then
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
        -- Normalize legacy aliases
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
-- Throttle: prevent ApplyAllFrameAnchors from running more than once per frame.
-- CDM bounds changes and PowerBar updates can trigger cascading re-anchor calls.
local _anchorThrottleFrame = nil
local _anchorThrottlePending = false

function QUI_Anchoring:ApplyAllFrameAnchors(force)
    if not QUICore or not QUICore.db or not QUICore.db.profile then return end
    local anchoringDB = QUICore.db.profile.frameAnchoring
    if not anchoringDB then return end

    -- Throttle: if already applied this frame, defer to next frame
    if not force and _anchorThrottlePending then return end
    _anchorThrottlePending = true
    if not _anchorThrottleFrame then
        _anchorThrottleFrame = CreateFrame("Frame")
        _anchorThrottleFrame:SetScript("OnUpdate", function(self)
            _anchorThrottlePending = false
            self:Hide()
        end)
    end
    _anchorThrottleFrame:Show()

    -- Clear all runtime state before re-applying from current profile.
    -- Prevents stale overrides and anchor relationships from a previous
    -- profile leaking across profile/spec switches.
    wipe(self.layoutOwnedFrames)
    wipe(self.anchoredFrames)

    local sorted = ComputeAnchorApplyOrder(anchoringDB)
    for _, key in ipairs(sorted) do
        self:ApplyFrameAnchor(key, anchoringDB[key])
    end

    -- Ensure ApplySystemAnchor guards are installed for any newly resolved frames
    InstallAllAnchorGuards()
end

---------------------------------------------------------------------------
-- GLOBAL CALLBACKS
---------------------------------------------------------------------------
-- Check if a frame-anchoring key has a saved position in the DB.
-- Modules call this to skip self-positioning when the anchoring system manages the frame.
_G.QUI_HasFrameAnchor = function(key)
    if not key then return false end
    local core = QUICore
    local db = core and core.db and core.db.profile
    return db and db.frameAnchoring and type(db.frameAnchoring[key]) == "table" or false
end

-- Returns true when the anchoring system has hidden a frame because its
-- anchor parent is hidden (hideWithParent).  Other systems (CDM layout,
-- hud_visibility) should respect this and avoid re-showing the frame.
_G.QUI_IsFrameHiddenByAnchor = function(key)
    return hideWithParentHidden[key] or false
end

_G.QUI_ApplyAllFrameAnchors = function(force)
    if QUI_Anchoring then
        QUI_Anchoring:ApplyAllFrameAnchors(force)
    end
end

_G.QUI_ApplyFrameAnchor = function(key)
    if not QUI_Anchoring or not QUICore or not QUICore.db or not QUICore.db.profile then
        return
    end
    local anchoringDB = QUICore.db.profile.frameAnchoring
    local settings = anchoringDB and anchoringDB[key]
    if type(settings) == "table" and HasFrameResolverForKey(key) then
        QUI_Anchoring:ApplyFrameAnchor(key, settings)
    end
end

-- Force re-apply: clears the frame's existing anchors first so the
-- anchor chain is definitely re-established. Used when a parent frame
-- moves and we need children to follow regardless of FrameAlreadyAtPosition.
_G.QUI_ForceReapplyFrameAnchor = function(key)
    if not QUI_Anchoring or not QUICore or not QUICore.db or not QUICore.db.profile then
        return
    end
    local anchoringDB = QUICore.db.profile.frameAnchoring
    local settings = anchoringDB and anchoringDB[key]
    if type(settings) ~= "table" or not HasFrameResolverForKey(key) then return end
    local resolved = ResolveApplyFrameForKey(key)
    if resolved then
        if type(resolved) == "table" and not resolved.GetObjectType then
            for _, frame in ipairs(resolved) do pcall(frame.ClearAllPoints, frame) end
        else
            pcall(resolved.ClearAllPoints, resolved)
        end
    end
    QUI_Anchoring:ApplyFrameAnchor(key, settings)
end

-- Position-only re-anchor: repositions a frame to its configured
-- parent without calling ApplyAutoSizing.
_G.QUI_ReanchorFramePositionOnly = function(key)
    if not key or InCombatLockdown() then return end
    if not QUI_Anchoring or not QUICore or not QUICore.db or not QUICore.db.profile then return end
    local anchoringDB = QUICore.db.profile.frameAnchoring
    if not anchoringDB then return end
    local settings = anchoringDB[key]
    if type(settings) ~= "table" then return end

    if not HasFrameResolverForKey(key) then return end
    local resolved = ResolveApplyFrameForKey(key)
    if not resolved then return end

    local parentFrame = ResolveParentFrame(settings.parent)
    if not parentFrame then return end

    local point = settings.point or "CENTER"
    local relative = settings.relative or "CENTER"
    local offsetX = settings.offsetX or 0
    local offsetY = settings.offsetY or 0
    local useSizeStable = IsSizeStableAnchoringEnabled(settings)
    if CASTBAR_ANCHOR_KEYS[key] or key == "buffBar" or key == "buffFrame" or key == "debuffFrame" then
        useSizeStable = false
    end

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
    if type(settings) ~= "table" then return end

    local parentFrame = ResolveParentFrame(settings.parent)
    if not parentFrame then return end

    local point = settings.point or "CENTER"
    local relative = settings.relative or "CENTER"
    local offsetX = settings.offsetX or 0
    local offsetY = settings.offsetY or 0
    local useSizeStable = IsSizeStableAnchoringEnabled(settings)
    if CASTBAR_ANCHOR_KEYS[key] or key == "buffBar" or key == "buffFrame" or key == "debuffFrame" then
        useSizeStable = false
    end

    overlayFrame:ClearAllPoints()
    if overlayW and overlayW > 0 then overlayFrame:SetWidth(overlayW) end
    if overlayH and overlayH > 0 then overlayFrame:SetHeight(overlayH) end
    if useSizeStable then
        -- Compute center offsets using the overlay's dimensions and parent rect
        local parentW, parentH = GetParentAnchorRect(parentFrame, settings.parent)
        -- Inflate very small parent dims (see ComputeCenterOffsetsForAnchor)
        if parentFrame ~= UIParent then
            if parentW < TINY_ANCHOR_THRESHOLD then parentW = LAYOUT_HANDLE_MIN end
            if parentH < TINY_ANCHOR_THRESHOLD then parentH = LAYOUT_HANDLE_MIN end
        end
        -- Also inflate tiny overlay dims
        local ow = (overlayW or 1) < TINY_ANCHOR_THRESHOLD and LAYOUT_HANDLE_MIN or (overlayW or 1)
        local oh = (overlayH or 1) < TINY_ANCHOR_THRESHOLD and LAYOUT_HANDLE_MIN or (overlayH or 1)
        local targetX, targetY = GetPointOffsetForRect(relative or "CENTER", parentW, parentH)
        local sourceX, sourceY = GetPointOffsetForRect(point or "CENTER", ow, oh)
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

HookRefreshGlobal("QUI_RefreshCastbar")
HookRefreshGlobal("QUI_RefreshCastbars")
HookRefreshGlobal("QUI_RefreshUnitFrames")
HookRefreshGlobal("QUI_RefreshGroupFrames")
HookRefreshGlobal("QUI_RefreshNCDM")
HookRefreshGlobal("QUI_RefreshBuffBar")
HookRefreshGlobal("QUI_RefreshRaidBuffs")

-- Modules that load after utility (trackers, qol, dungeon) need deferred hooking
-- since their globals don't exist yet at file-load time.
C_Timer.After(0, function()
    HookRefreshGlobal("QUI_RefreshCustomTrackers")
    HookRefreshGlobal("QUI_RefreshBrezCounter")
    HookRefreshGlobal("QUI_RefreshAtonementCounter")
    HookRefreshGlobal("QUI_RefreshCombatTimer")
    HookRefreshGlobal("QUI_RefreshRangeCheck")
    HookRefreshGlobal("QUI_RefreshXPTracker")
    HookRefreshGlobal("QUI_RefreshActionTracker")
    HookRefreshGlobal("QUI_RefreshSkyriding")
    HookRefreshGlobal("QUI_RefreshPetWarning")
    HookRefreshGlobal("QUI_RefreshFocusCastAlert")
end)

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
                if type(settings) == "table" and settings.parent == currentTarget then
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

if ns.Registry then
    ns.Registry:Register("anchoring", {
        refresh = _G.QUI_ApplyAllFrameAnchors,
        priority = 70,
        group = "anchoring",
        importCategories = { "layout" },
    })
end

