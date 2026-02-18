--[[
    QUI Anchoring Module
    Unified anchoring system for castbars, unit frames, and custom frames
    Supports 9-point anchoring with X/Y offsets and dynamic anchor target registration
]]

local ADDON_NAME, ns = ...
local QUICore = ns.Addon

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
        width = anchorFrame.__cdmRow1Width or width
        height = anchorFrame.__cdmTotalHeight or height
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
        C_Timer.After(0, function()
            self:PositionFrame(frame, anchorTarget, anchorPoint, offsetX, offsetY, parentFrame, options)
        end)
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
        C_Timer.After(0, function()
            self:RegisterAnchoredFrame(frame, config)
        end)
        return true
    end
    
    -- Safely clear points (use pcall to handle secure frames)
    local success = pcall(function()
        frame:ClearAllPoints()
    end)
    if not success then
        -- Frame is secure/managed - defer the call
        C_Timer.After(0, function()
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

    for frame, config in pairs(self.anchoredFrames) do
        -- Skip frames with active anchoring overrides — reapply override instead
        -- (callers may have called ClearAllPoints before triggering this update)
        if self.overriddenFrames[frame] then
            self:ApplyAllFrameAnchors()
            -- ApplyAllFrameAnchors handles all overridden frames, so we can continue
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
        C_Timer.After(0, function()
            self:UpdateFramesForTarget(anchorTargetName)
        end)
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
-- Forward declaration (defined below in global callbacks section)
local DebouncedReapplyOverrides
---------------------------------------------------------------------------
-- Lazy resolver functions for all controllable frames
local FRAME_RESOLVERS = {
    -- CDM Viewers
    cdmEssential = function() return _G["EssentialCooldownViewer"] end,
    cdmUtility = function() return _G["UtilityCooldownViewer"] end,
    buffIcon = function() return _G["BuffIconCooldownViewer"] end,
    buffBar = function() return _G["BuffBarCooldownViewer"] end,
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
    -- Display
    minimap = function() return _G["Minimap"] end,
    objectiveTracker = function() return _G["ObjectiveTrackerFrame"] end,
    buffFrame = function() return _G["BuffFrame"] end,
    debuffFrame = function() return _G["DebuffFrame"] end,
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
    minimap         = { displayName = "Minimap",               category = "Display",           order = 1 },
    objectiveTracker = { displayName = "Objective Tracker",    category = "Display",           order = 2 },
    buffFrame       = { displayName = "Buff Frame",            category = "Display",           order = 3 },
    debuffFrame     = { displayName = "Debuff Frame",          category = "Display",           order = 4 },
    dandersParty    = { displayName = "DandersFrames Party",   category = "External",          order = 1 },
    dandersRaid     = { displayName = "DandersFrames Raid",    category = "External",          order = 2 },
}

-- Virtual CDM anchor parents.
-- These are lightweight proxy frames we can safely resize in combat so frame
-- anchoring can still respect configured min-width even when Blizzard's CDM
-- viewer frame is protected.
local CDM_PROXY_VIEWER_BY_KEY = {
    cdmEssential = "EssentialCooldownViewer",
    cdmUtility = "UtilityCooldownViewer",
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

local function GetCDMAnchorProxy(parentKey)
    if parentKey == "essential" then
        parentKey = "cdmEssential"
    elseif parentKey == "utility" then
        parentKey = "cdmUtility"
    end

    local viewerName = CDM_PROXY_VIEWER_BY_KEY[parentKey]
    if not viewerName then return nil end

    local viewer = _G[viewerName]
    if not viewer then return nil end

    local proxy = cdmAnchorProxies[parentKey]
    if not proxy then
        proxy = CreateFrame("Frame", nil, UIParent)
        proxy:SetClampedToScreen(false)
        proxy:Show()
        cdmAnchorProxies[parentKey] = proxy
    end

    -- Combat-stable behavior:
    -- Keep the proxy frozen during combat once initialized, then refresh after
    -- combat ends. This prevents children anchored to edge points (TOP/BOTTOM)
    -- from drifting when Blizzard mutates protected CDM frame size in combat.
    local inCombat = InCombatLockdown()
    if inCombat and proxy.__quiCDMProxyInitialized then
        cdmAnchorProxyPendingAfterCombat[parentKey] = true
        return proxy
    end

    local width = viewer.__cdmIconWidth or viewer:GetWidth() or 0
    local height = viewer.__cdmTotalHeight or viewer:GetHeight() or 0
    local minWidthEnabled, minWidth = GetHUDMinWidthSettings()
    if minWidthEnabled and IsHUDAnchoredToCDM() then
        width = math.max(width, minWidth)
    end
    width = math.max(1, width)
    height = math.max(1, height)

    local viewerX, viewerY = viewer:GetCenter()
    local screenX, screenY = UIParent:GetCenter()
    if viewerX and viewerY and screenX and screenY then
        proxy:ClearAllPoints()
        proxy:SetPoint("CENTER", UIParent, "CENTER", viewerX - screenX, viewerY - screenY)
    end
    proxy:SetSize(width, height)
    proxy.__quiCDMProxyInitialized = true
    if inCombat then
        cdmAnchorProxyPendingAfterCombat[parentKey] = true
    end

    return proxy
end

-- Refresh both CDM proxy parents (safe in combat).
local function UpdateCDMAnchorProxies()
    GetCDMAnchorProxy("cdmEssential")
    GetCDMAnchorProxy("cdmUtility")
end

-- Fallback anchor targets for when a resolved frame is unavailable (nil or hidden).
-- e.g. classes without a secondary resource should fall back to the primary bar.
local FRAME_ANCHOR_FALLBACKS = {
    secondaryPower = "primaryPower",
}

-- Helper: resolve a single key to a visible frame (nil if unavailable)
local function ResolveFrameForKey(key)
    -- CDM proxy check
    local cdmProxy = GetCDMAnchorProxy(key)
    if cdmProxy then return cdmProxy end

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
cdmProxyCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
cdmProxyCombatFrame:SetScript("OnEvent", function()
    local needsRefresh = false
    for key, pending in pairs(cdmAnchorProxyPendingAfterCombat) do
        if pending then
            needsRefresh = true
            cdmAnchorProxyPendingAfterCombat[key] = nil
        end
    end
    if not needsRefresh then
        return
    end
    C_Timer.After(0.05, function()
        if InCombatLockdown() then
            cdmAnchorProxyPendingAfterCombat.cdmEssential = true
            cdmAnchorProxyPendingAfterCombat.cdmUtility = true
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
    else
        QUI_Anchoring.overriddenFrames[frame] = active and key or nil
    end
end

-- Track which parent frames have been hooked for OnSizeChanged
local hookedParentFrames = {}

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
        local viewer = _G["EssentialCooldownViewer"]
        if viewer then
            local iconHeight = viewer.__cdmRow1IconHeight
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

    local resolver = FRAME_RESOLVERS[key]
    if not resolver then return end

    local resolved = resolver()

    -- If override is disabled, unblock module positioning and let modules reclaim the frame
    if not settings.enabled then
        SetFrameOverride(resolved, false)
        return
    end

    if not resolved then return end

    -- Mark frame as overridden FIRST — blocks any module positioning from this point on
    SetFrameOverride(resolved, true, key)

    -- Defer if in combat
    if InCombatLockdown() then
        C_Timer.After(0.5, function()
            if not InCombatLockdown() then
                self:ApplyFrameAnchor(key, settings)
            end
        end)
        return
    end

    local parentFrame = ResolveParentFrame(settings.parent)
    local point = settings.point or "CENTER"
    local relative = settings.relative or "CENTER"
    local offsetX = settings.offsetX or 0
    local offsetY = settings.offsetY or 0

    -- Boss frames: single setting applied to all with stacking Y offset
    if key == "bossFrames" and type(resolved) == "table" and not resolved.GetObjectType then
        for i, frame in ipairs(resolved) do
            local stackOffsetY = offsetY - ((i - 1) * 50)
            pcall(function()
                frame:ClearAllPoints()
                frame:SetPoint(point, parentFrame, relative, offsetX, stackOffsetY)
            end)
        end
        -- Apply auto-sizing to each boss frame
        ApplyAutoSizing(resolved[1], settings, parentFrame, key)
        for i = 2, #resolved do
            ApplyAutoSizing(resolved[i], settings, parentFrame, key)
        end
        return
    end

    -- Normal single-frame case
    pcall(function()
        resolved:ClearAllPoints()
        resolved:SetPoint(point, parentFrame, relative, offsetX, offsetY)
    end)

    -- Apply auto-width / auto-height
    ApplyAutoSizing(resolved, settings, parentFrame, key)
end

-- Apply all saved frame anchor overrides
function QUI_Anchoring:ApplyAllFrameAnchors()
    if not QUICore or not QUICore.db or not QUICore.db.profile then return end
    local anchoringDB = QUICore.db.profile.frameAnchoring
    if not anchoringDB then return end

    for key, settings in pairs(anchoringDB) do
        if type(settings) == "table" and FRAME_RESOLVERS[key] and settings.enabled then
            self:ApplyFrameAnchor(key, settings)
        end
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
