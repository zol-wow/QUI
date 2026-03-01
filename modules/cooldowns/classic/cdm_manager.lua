-- cooldownmanager.lua
-- Clean Cooldown Manager functionality integrated into QUI
-- Removes padding from cooldown icons and handles icon layout
-- Note: Swipe visibility is handled by cooldownswipe.lua

local _, QUI = ...
local Helpers = QUI.Helpers
local SafeValue = Helpers.SafeValue

-- Local variables
local viewerPending = {}
local updateBucket = {}
local _iconPositions = Helpers.CreateStateTable()
local _pendingCombatViewers
-- Performance: reusable scratch table for visible children (avoids per-call allocation)
local cdm_visibleScratch = {}

-- Core function to remove padding and apply modifications
local function RemovePadding(viewer)
    -- Don't apply modifications in edit mode
    if Helpers.IsEditModeActive() then
        return
    end

    -- Don't modify protected frames during combat — defer to post-combat
    if InCombatLockdown() then
        if not _pendingCombatViewers then _pendingCombatViewers = {} end
        _pendingCombatViewers[viewer] = true
        return
    end

    -- Don't interfere if layout is currently being applied
    if viewer._layoutApplying then
        return
    end
    
    -- Performance: iterate children via select() to avoid table allocation
    local numChildren = viewer:GetNumChildren()
    -- Get the visible icons (because they're fully dynamic)
    -- Performance: reuse module-level scratch table instead of allocating per call
    local visibleChildren = cdm_visibleScratch
    wipe(visibleChildren)
    for i = 1, numChildren do
        local child = select(i, viewer:GetChildren())
        if child and child:IsShown() then
            -- Store original position for sorting
            local point, relativeTo, relativePoint, x, y = child:GetPoint(1)
            _iconPositions[child] = _iconPositions[child] or {}
            _iconPositions[child].originalX = x or 0
            _iconPositions[child].originalY = y or 0
            visibleChildren[#visibleChildren + 1] = child
        end
    end
    
    if #visibleChildren == 0 then return end
    
    -- Sort by original position to maintain Blizzard's order
    local isHorizontal = viewer.isHorizontal
    if isHorizontal then
        -- Sort left to right, then top to bottom
        table.sort(visibleChildren, function(a, b)
            local posA = _iconPositions[a] or {}
            local posB = _iconPositions[b] or {}
            if math.abs((posA.originalY or 0) - (posB.originalY or 0)) < 1 then
                return (posA.originalX or 0) < (posB.originalX or 0)
            end
            return (posA.originalY or 0) > (posB.originalY or 0)
        end)
    else
        -- Sort top to bottom, then left to right
        table.sort(visibleChildren, function(a, b)
            local posA = _iconPositions[a] or {}
            local posB = _iconPositions[b] or {}
            if math.abs((posA.originalX or 0) - (posB.originalX or 0)) < 1 then
                return (posA.originalY or 0) > (posB.originalY or 0)
            end
            return (posA.originalX or 0) < (posB.originalX or 0)
        end)
    end
    
    -- Get layout settings from the viewer
    local stride = viewer.stride or #visibleChildren

    -- CONFIGURATION OPTIONS:
    local overlap = -3 -- Icons overlap slightly to hide transparent borders
    local iconScale = 1.15 -- Scale for icons
    
    -- Scale the icons to overlap and hide the transparent borders baked into the textures
    for _, child in ipairs(visibleChildren) do
        if child.Icon then
            child.Icon:ClearAllPoints()
            child.Icon:SetPoint("CENTER", child, "CENTER", 0, 0)
            local cw = SafeValue(child:GetWidth(), 0)
            local ch = SafeValue(child:GetHeight(), 0)
            if cw > 0 and ch > 0 then
                child.Icon:SetSize(cw * iconScale, ch * iconScale)
            end
        end
        
        -- Swipe visibility is now handled by cooldownswipe.lua
    end
    
    -- Reposition buttons respecting orientation and stride
    local buttonWidth = SafeValue(visibleChildren[1]:GetWidth(), 0)
    local buttonHeight = SafeValue(visibleChildren[1]:GetHeight(), 0)
    if buttonWidth <= 0 or buttonHeight <= 0 then return end
    
    -- Calculate grid dimensions
    local numIcons = #visibleChildren
    local totalWidth, totalHeight
    
    if isHorizontal then
        local cols = math.min(stride, numIcons)
        local rows = math.ceil(numIcons / stride)
        totalWidth = cols * buttonWidth + (cols - 1) * overlap
        totalHeight = rows * buttonHeight + (rows - 1) * overlap
    else
        local rows = math.min(stride, numIcons)
        local cols = math.ceil(numIcons / stride)
        totalWidth = cols * buttonWidth + (cols - 1) * overlap
        totalHeight = rows * buttonHeight + (rows - 1) * overlap
    end
    
    -- Calculate offsets to center the grid
    local startX = -totalWidth / 2
    local startY = totalHeight / 2
    
    if isHorizontal then
        -- Horizontal layout with wrapping
        for i, child in ipairs(visibleChildren) do
            local index = i - 1
			local row = math.floor(index / stride)
			local col = index % stride

			-- Determine number of icons in this row
			local rowStart = row * stride + 1
			local rowEnd = math.min(rowStart + stride - 1, numIcons)
			local iconsInRow = rowEnd - rowStart + 1

			-- Compute the actual width of this row
			local rowWidth = iconsInRow * buttonWidth + (iconsInRow - 1) * overlap

			-- Center this row
			local rowStartX = -rowWidth / 2

			-- Column offset inside centered row
			local xOffset = rowStartX + col * (buttonWidth + overlap)
			local yOffset = startY - row * (buttonHeight + overlap)

			child:ClearAllPoints()
			child:SetPoint("CENTER", viewer, "CENTER", xOffset + buttonWidth/2, yOffset - buttonHeight/2)
        end
    else
        -- Vertical layout with wrapping
        for i, child in ipairs(visibleChildren) do
            local row = (i - 1) % stride
            local col = math.floor((i - 1) / stride)
            
            local xOffset = startX + col * (buttonWidth + overlap)
            local yOffset = startY - row * (buttonHeight + overlap)
            
            child:ClearAllPoints()
            child:SetPoint("CENTER", viewer, "CENTER", xOffset + buttonWidth/2, yOffset - buttonHeight/2)
        end
    end
end

-- Pending flag to coalesce multiple schedule calls into one timer
local updatePending = false

-- Schedule an update to apply the modifications after Blizzard is done
local function ScheduleUpdate(viewer)
    updateBucket[viewer] = true
    if updatePending then return end
    updatePending = true
    C_Timer.After(0, function()
        updatePending = false
        for v in pairs(updateBucket) do
            updateBucket[v] = nil
            RemovePadding(v)
        end
    end)
end

-- Swipe visibility is now handled centrally by cooldownswipe.lua
-- This file only handles icon layout (padding removal, scaling, positioning)

-- Post-combat retry for viewers that were scheduled during combat
local regenFrame = CreateFrame("Frame")
regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
regenFrame:SetScript("OnEvent", function()
    if not _pendingCombatViewers then return end
    local viewers = _pendingCombatViewers
    _pendingCombatViewers = nil
    for v in pairs(viewers) do
        RemovePadding(v)
    end
end)

-- Export function to QUI namespace
QUI.CooldownManager = {
    RemovePadding = RemovePadding,
    ScheduleUpdate = ScheduleUpdate,
}

