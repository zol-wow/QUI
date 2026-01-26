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

local Helpers = {}

---------------------------------------------------------------------------
-- SETUP HELPERS
---------------------------------------------------------------------------
function QUI_Anchoring:SetHelpers(helpers)
    Helpers = helpers or {}
end

-- Helper function wrappers (with fallbacks)
local function Scale(x)
    return Helpers.Scale and Helpers.Scale(x) or (QUICore and QUICore.Scale and QUICore:Scale(x) or x)
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
        local function GetBorderAdjustment(anchorPoint, borderSize)
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
        
        local sourceAdjX, sourceAdjY = GetBorderAdjustment(anchorPoint, sourceBorderSize)
        local targetAdjX, targetAdjY = GetBorderAdjustment(targetAnchorPoint, targetBorderSize)
        local netAdjX = targetAdjX - sourceAdjX
        local netAdjY = targetAdjY - sourceAdjY
        
        local scaledOffsetX = Scale(offsetX) + netAdjX
        local scaledOffsetY = math.floor(Scale(offsetY) + 0.5) + netAdjY
        
        -- Use explicit dual anchors if provided
        if useExplicitDualAnchors then
            local sourceAdjX2, sourceAdjY2 = GetBorderAdjustment(sourceAnchorPoint2, sourceBorderSize)
            local targetAdjX2, targetAdjY2 = GetBorderAdjustment(targetAnchorPoint2, targetBorderSize)
            local netAdjX2 = targetAdjX2 - sourceAdjX2
            local netAdjY2 = targetAdjY2 - sourceAdjY2
            
            local scaledOffsetX2 = Scale(offsetX) + netAdjX2
            local scaledOffsetY2 = math.floor(Scale(offsetY) + 0.5) + netAdjY2
            
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
    local function GetBorderAdjustment(anchorPoint, borderSize)
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
    
    local sourceAdjX, sourceAdjY = GetBorderAdjustment(anchorPoint, sourceBorderSize)
    local targetAdjX, targetAdjY = GetBorderAdjustment(targetAnchorPoint, targetBorderSize)
    local netAdjX = targetAdjX - sourceAdjX
    local netAdjY = targetAdjY - sourceAdjY
    
    -- offsetX and offsetY already provide the gap/padding functionality
    -- When the anchor target changes size, the offset maintains that gap
    local scaledOffsetX = Scale(offsetX) + netAdjX
    local scaledOffsetY = math.floor(Scale(offsetY) + 0.5) + netAdjY
    
    -- Use explicit dual anchors if provided
    if useExplicitDualAnchors then
        local sourceAdjX2, sourceAdjY2 = GetBorderAdjustment(sourceAnchorPoint2, sourceBorderSize)
        local targetAdjX2, targetAdjY2 = GetBorderAdjustment(targetAnchorPoint2, targetBorderSize)
        local netAdjX2 = targetAdjX2 - sourceAdjX2
        local netAdjY2 = targetAdjY2 - sourceAdjY2
        
        -- offsetX and offsetY already provide the gap/padding for both anchor points
        local scaledOffsetX2 = Scale(offsetX) + netAdjX2
        local scaledOffsetY2 = math.floor(Scale(offsetY) + 0.5) + netAdjY2
        
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
    local targetData = self:GetAnchorTarget(anchorTarget)
    if not targetData then
        if options.onFailure then
            options.onFailure("Anchor target not found: " .. tostring(anchorTarget))
        end
        return false
    end
    
    local targetFrame = targetData.frame
    
    -- Check if target is visible (if requested)
    if options.checkVisible ~= false then
        if not targetFrame:IsShown() then
            if options.onFailure then
                local displayName = targetData.options and targetData.options.displayName or anchorTarget
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
function QUI_Anchoring:UpdateAllAnchoredFrames()
    if InCombatLockdown() then 
        -- Defer update after combat
        C_Timer.After(0, function()
            self:UpdateAllAnchoredFrames()
        end)
        return 
    end
    
    for frame, config in pairs(self.anchoredFrames) do
        if frame and frame:IsShown() then
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
-- GLOBAL CALLBACKS (for backward compatibility)
---------------------------------------------------------------------------
-- Global callback for updating anchored frames (called by NCDM, resource bars, etc.)
_G.QUI_UpdateAnchoredFrames = function()
    if QUI_Anchoring then
        QUI_Anchoring:UpdateAllAnchoredFrames()
    end
end

-- Backward compatibility alias
_G.QUI_UpdateAnchoredUnitFrames = _G.QUI_UpdateAnchoredFrames
_G.QUI_UpdateCDMAnchoredUnitFrames = _G.QUI_UpdateAnchoredFrames

