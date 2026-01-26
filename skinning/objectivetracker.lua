local addonName, ns = ...

---------------------------------------------------------------------------
-- OBJECTIVE TRACKER SKINNING
-- Applies QUI color scheme with dynamic content-height backdrop
---------------------------------------------------------------------------

local FONT_FLAGS = "OUTLINE"

-- Debounce flag to prevent multiple concurrent backdrop updates
local pendingBackdropUpdate = false

-- Get settings
local function GetSettings()
    local QUICore = _G.QUI and _G.QUI.QUICore
    local settings = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general
    return settings
end

-- Get skinning colors
local function GetColors()
    local QUI = _G.QUI
    local sr, sg, sb, sa = 0.2, 1.0, 0.6, 1
    local bgr, bgg, bgb, bga = 0.05, 0.05, 0.05, 0.95

    if QUI and QUI.GetSkinColor then
        sr, sg, sb, sa = QUI:GetSkinColor()
    end
    if QUI and QUI.GetSkinBgColor then
        bgr, bgg, bgb, bga = QUI:GetSkinBgColor()
    end

    return sr, sg, sb, sa, bgr, bgg, bgb, bga
end

-- Safely set text color from a color table with bounds validation
local function SafeSetTextColor(fontString, colorTable)
    if not fontString or not colorTable then return end
    if type(colorTable) ~= "table" or #colorTable < 3 then return end
    fontString:SetTextColor(colorTable[1] or 1, colorTable[2] or 1, colorTable[3] or 1, colorTable[4] or 1)
end

-- Get LibCustomGlow for quest icon glows
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

-- Style quest POI icon (glow removed - was causing indefinite glow bug BUG-003)
local function StyleQuestPOIIcon(button)
    if not button or button.quiStyled then return end

    -- Style the POI button
    if button.NormalTexture then
        button.NormalTexture:SetAlpha(0)
    end
    if button.PushedTexture then
        button.PushedTexture:SetAlpha(0)
    end
    if button.HighlightTexture then
        button.HighlightTexture:SetAlpha(0.3)
    end

    -- Stop any existing LibCustomGlow effects (cleanup from previous versions)
    if LCG and LCG.PixelGlow_Stop then
        LCG.PixelGlow_Stop(button, "_QUIQuestGlow")
    end

    button.quiStyled = true
end

-- Style completion checkmark with QUI color
local function StyleCompletionCheck(check)
    if not check or check.quiStyled then return end

    local sr, sg, sb = GetColors()
    check:SetAtlas("checkmark-minimal")
    check:SetDesaturated(true)
    check:SetVertexColor(sr, sg, sb)

    check.quiStyled = true
end

-- Handle quest block icons (called when blocks are added)
local function HandleQuestBlockIcons(tracker, block)
    if not block then return end

    -- Style quest item button (the clickable item icon)
    local itemButton = block.ItemButton or block.itemButton
    if itemButton then
        StyleQuestPOIIcon(itemButton)
    end

    -- Style completion checkmark
    local check = block.currentLine and block.currentLine.Check
    if check then
        StyleCompletionCheck(check)
    end
    -- Note: POI button glow is hidden via HidePOIButtonGlows() called from ScheduleBackdropUpdate
end

-- List of tracker modules
local trackerModules = {
    "ScenarioObjectiveTracker",
    "UIWidgetObjectiveTracker",
    "CampaignQuestObjectiveTracker",
    "QuestObjectiveTracker",
    "AdventureObjectiveTracker",
    "AchievementObjectiveTracker",
    "MonthlyActivitiesObjectiveTracker",
    "ProfessionsRecipeTracker",
    "BonusObjectiveTracker",
    "WorldQuestObjectiveTracker",
}

-- Skin header: hide background atlas, left-justify text flush to edge
local function SkinTrackerHeader(header)
    if not header then return end

    -- Hide background atlas
    if header.Background then
        header.Background:SetAtlas(nil)
        header.Background:SetAlpha(0)
    end

    -- Left-justify header text flush to edge (Blizzard default is x=7)
    -- Use negative offset to align with quest POI icons which sit at ~x=13 from module
    if header.Text then
        header.Text:ClearAllPoints()
        header.Text:SetPoint("LEFT", header, "LEFT", -7, 0)
        header.Text:SetJustifyH("LEFT")
    end
end

-- Sync QUI max height with Blizzard's editModeHeight so truncation matches backdrop
local function SyncBlizzardHeight()
    local TrackerFrame = _G.ObjectiveTrackerFrame
    if not TrackerFrame then return end

    local settings = GetSettings()
    local maxHeight = settings and settings.objectiveTrackerHeight or 600

    -- Set Blizzard's internal height so truncation happens at our max
    TrackerFrame.editModeHeight = maxHeight
    if TrackerFrame.UpdateHeight then
        TrackerFrame:UpdateHeight()
    end
end

-- Hide scenario stage block artwork (dungeon banner) for narrower widths
-- Called on every width update since ScenarioObjectiveTracker may not exist initially
local function HideScenarioStageArtwork()
    local scenario = _G.ScenarioObjectiveTracker
    if not scenario then return end

    local stageBlock = scenario.StageBlock
    if not stageBlock then return end

    -- Hide the banner artwork textures (safe to call repeatedly)
    if stageBlock.NormalBG then
        stageBlock.NormalBG:Hide()
        stageBlock.NormalBG:SetAlpha(0)
    end
    if stageBlock.FinalBG then
        stageBlock.FinalBG:Hide()
        stageBlock.FinalBG:SetAlpha(0)
    end
    if stageBlock.GlowTexture then
        stageBlock.GlowTexture:Hide()
        stageBlock.GlowTexture:SetAlpha(0)
    end

    -- Reposition text to left edge (was indented for the banner)
    -- Name anchors to Stage, so nest inside Stage check for safety
    if stageBlock.Stage then
        stageBlock.Stage:ClearAllPoints()
        stageBlock.Stage:SetPoint("TOPLEFT", stageBlock, "TOPLEFT", 0, -5)
        if stageBlock.Name then
            stageBlock.Name:ClearAllPoints()
            stageBlock.Name:SetPoint("TOPLEFT", stageBlock.Stage, "BOTTOMLEFT", 0, -2)
        end
    end
end

-- Helper to update minimize button atlas based on collapsed state
-- Extracted to avoid duplication between hook and immediate application
local function UpdateMinimizeButtonAtlas(btn, collapsed)
    if not btn then return end
    local normalTex = btn:GetNormalTexture()
    local pushedTex = btn:GetPushedTexture()
    if collapsed then
        if normalTex then normalTex:SetAtlas("ui-questtrackerbutton-secondary-expand") end
        if pushedTex then pushedTex:SetAtlas("ui-questtrackerbutton-secondary-expand-pressed") end
    else
        if normalTex then normalTex:SetAtlas("ui-questtrackerbutton-secondary-collapse") end
        if pushedTex then pushedTex:SetAtlas("ui-questtrackerbutton-secondary-collapse-pressed") end
    end
end

-- Check if scenario tracker has visible content (M+, dungeons, etc.)
local function IsScenarioActive()
    local scenario = _G.ScenarioObjectiveTracker
    if not scenario or not scenario:IsShown() then return false end
    -- Check if module has actual content
    if scenario.GetContentsHeight then
        local height = scenario:GetContentsHeight()
        if height and height > 0 then return true end
    end
    return false
end

-- Apply max width to tracker and all modules (shared by Skin and Refresh)
local function ApplyMaxWidth(settings)
    local TrackerFrame = _G.ObjectiveTrackerFrame
    if not TrackerFrame then return end

    -- Skip width restriction when in scenario/M+ to avoid display issues
    local maxWidth
    if IsScenarioActive() then
        maxWidth = 260  -- Use default width in scenarios
    else
        maxWidth = settings and settings.objectiveTrackerWidth or 260
    end
    TrackerFrame:SetWidth(maxWidth)

    -- Set main header width and style minimize button to match module headers
    if TrackerFrame.Header then
        TrackerFrame.Header:SetWidth(maxWidth)
        local minBtn = TrackerFrame.Header.MinimizeButton
        if minBtn then
            -- Reposition to stay within frame
            minBtn:ClearAllPoints()
            minBtn:SetPoint("RIGHT", TrackerFrame.Header, "RIGHT", 0, 0)
            -- Resize to match module buttons (16x16 vs default 18x19)
            minBtn:SetSize(16, 16)
            -- Set highlight to yellow (only once)
            if not minBtn.quiHighlightSet and minBtn:GetHighlightTexture() then
                minBtn:GetHighlightTexture():SetAtlas("ui-questtrackerbutton-yellow-highlight")
                minBtn.quiHighlightSet = true
            end
        end

        -- Hook SetCollapsed to override atlas with secondary style
        -- (Blizzard resets to collapse-all/expand-all on state change)
        if TrackerFrame.Header.SetCollapsed and not TrackerFrame.Header.quiSetCollapsedHooked then
            hooksecurefunc(TrackerFrame.Header, "SetCollapsed", function(self, collapsed)
                UpdateMinimizeButtonAtlas(self.MinimizeButton, collapsed)
            end)
            TrackerFrame.Header.quiSetCollapsedHooked = true

            -- Apply immediately for current state
            local isCollapsed = false
            if type(TrackerFrame.IsCollapsed) == "function" then
                isCollapsed = TrackerFrame:IsCollapsed()
            end
            UpdateMinimizeButtonAtlas(minBtn, isCollapsed)
        end
    end

    -- Set width on each module so text wraps correctly
    for _, trackerName in ipairs(trackerModules) do
        local tracker = _G[trackerName]
        if tracker then
            tracker:SetWidth(maxWidth)
            if tracker.Header then
                tracker.Header:SetWidth(maxWidth)
            end
        end
    end

    -- Hide scenario stage artwork for narrower display
    HideScenarioStageArtwork()
end

-- Update backdrop to match content, respecting max height setting
local function UpdateBackdropAnchors()
    local TrackerFrame = _G.ObjectiveTrackerFrame
    if not TrackerFrame or not TrackerFrame.quiBackdrop then return end

    local settings = GetSettings()
    local maxHeight = settings and settings.objectiveTrackerHeight or 600

    -- Find the module with the lowest bottom (furthest down on screen)
    local bottomModule = nil
    local lowestBottom = math.huge

    for _, trackerName in ipairs(trackerModules) do
        local tracker = _G[trackerName]
        if tracker and tracker:IsShown() then
            -- Check if module has content (try GetContentsHeight first, fall back to GetHeight)
            local hasContent = false
            if tracker.GetContentsHeight then
                local contentHeight = tracker:GetContentsHeight()
                hasContent = contentHeight and contentHeight > 0
            end
            -- Fallback: check actual frame height if GetContentsHeight didn't work
            if not hasContent then
                local frameHeight = tracker:GetHeight()
                hasContent = frameHeight and frameHeight > 1
            end

            if hasContent then
                local bottom = tracker:GetBottom()
                if bottom and bottom < lowestBottom then
                    lowestBottom = bottom
                    bottomModule = tracker
                end
            end
        end
    end

    -- Re-anchor backdrop to match content bounds
    TrackerFrame.quiBackdrop:ClearAllPoints()
    TrackerFrame.quiBackdrop:SetPoint("TOPLEFT", TrackerFrame, "TOPLEFT", -15, 0)
    TrackerFrame.quiBackdrop:SetPoint("TOPRIGHT", TrackerFrame, "TOPRIGHT", 10, 0)

    if bottomModule then
        -- Calculate actual content height (guard against nil/invalid during initial layout)
        local trackerTop = TrackerFrame:GetTop()
        local contentHeight = 0
        if trackerTop and lowestBottom and trackerTop > lowestBottom then
            contentHeight = trackerTop - lowestBottom + 15  -- +15 for bottom padding
        end

        if contentHeight > maxHeight then
            -- Content exceeds max height, use fixed height
            TrackerFrame.quiBackdrop:SetHeight(maxHeight)
        else
            -- Content fits, anchor to bottommost module
            TrackerFrame.quiBackdrop:SetPoint("BOTTOM", bottomModule, "BOTTOM", 0, -15)
        end
        TrackerFrame.quiBackdrop:Show()
    else
        -- No visible modules, hide backdrop
        TrackerFrame.quiBackdrop:Hide()
    end
end

-- Hide glow on all POI buttons in the objective tracker
-- Called after tracker updates to ensure glows are hidden
local function HidePOIButtonGlows()
    for _, trackerName in ipairs(trackerModules) do
        local tracker = _G[trackerName]
        if tracker and tracker.usedBlocks then
            for template, blocks in pairs(tracker.usedBlocks) do
                if type(blocks) == "table" then
                    for id, block in pairs(blocks) do
                        -- Permanently hide Blizzard's native glow (BUG-003)
                        if block.poiButton and block.poiButton.Glow then
                            block.poiButton.Glow:Hide()
                            block.poiButton.Glow:SetAlpha(0)
                            -- Hook Show to prevent Blizzard from re-showing
                            if not block.poiButton.Glow.quiHooked then
                                hooksecurefunc(block.poiButton.Glow, "Show", function(self)
                                    self:Hide()
                                end)
                                block.poiButton.Glow.quiHooked = true
                            end
                        end
                        -- Stop any LibCustomGlow effects (cleanup)
                        if LCG and LCG.PixelGlow_Stop and block.poiButton then
                            LCG.PixelGlow_Stop(block.poiButton, "_QUIQuestGlow")
                        end
                        -- Also check ItemButton which StyleQuestPOIIcon targets
                        local itemButton = block.ItemButton or block.itemButton
                        if LCG and LCG.PixelGlow_Stop and itemButton then
                            LCG.PixelGlow_Stop(itemButton, "_QUIQuestGlow")
                        end
                    end
                end
            end
        end
    end
end

-- Debounced backdrop update to prevent multiple concurrent timers
-- 0.15s delay allows Blizzard's layout pass to complete before we measure
local function ScheduleBackdropUpdate()
    if pendingBackdropUpdate then return end
    pendingBackdropUpdate = true
    C_Timer.After(0.15, function()
        pendingBackdropUpdate = false
        UpdateBackdropAnchors()
        HidePOIButtonGlows()
    end)
end

-- Reposition all lines within a block based on their actual heights
-- This fixes overlap caused by font changes affecting text wrapping
local function RepositionBlockLines(block)
    if not block or not block.usedLines then return end

    -- Get all lines and sort them by their original order (using objectiveKey or creation order)
    local lines = {}
    for key, line in pairs(block.usedLines) do
        if line and line:IsShown() then
            table.insert(lines, line)
        end
    end

    -- Sort by current Y position (top to bottom)
    table.sort(lines, function(a, b)
        local topA = a:GetTop() or 0
        local topB = b:GetTop() or 0
        return topA > topB
    end)

    -- Reposition each line based on actual heights
    local yOffset = 0
    local headerHeight = 0
    if block.HeaderText then
        headerHeight = block.HeaderText:GetStringHeight() or 0
        yOffset = -(headerHeight + 5)  -- Start below header with padding
    end

    for i, line in ipairs(lines) do
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", block, "TOPLEFT", 0, yOffset)
        line:SetPoint("RIGHT", block, "RIGHT", 0, 0)

        local lineHeight = line:GetHeight() or 14
        yOffset = yOffset - lineHeight - 2  -- Move down by line height + small gap
    end

    -- Update block height to fit all content
    local totalHeight = math.abs(yOffset) + 5
    block:SetHeight(totalHeight)
end

-- Debounced line repositioning for all visible blocks
local pendingLineReposition = false
local function ScheduleLineReposition()
    if pendingLineReposition then return end
    pendingLineReposition = true
    -- Small delay to batch multiple style changes
    C_Timer.After(0.05, function()
        pendingLineReposition = false

        for _, trackerName in ipairs(trackerModules) do
            local tracker = _G[trackerName]
            if tracker and tracker:IsShown() and tracker.usedBlocks then
                for template, blocks in pairs(tracker.usedBlocks) do
                    for blockID, block in pairs(blocks) do
                        if block:IsShown() then
                            RepositionBlockLines(block)
                        end
                    end
                end
            end
        end

        -- Also update backdrop after repositioning
        ScheduleBackdropUpdate()
    end)
end

-- Kill all textures in a NineSlice frame
local function KillNineSlice(nineSlice)
    if not nineSlice then return end

    -- Hide the frame
    nineSlice:Hide()
    nineSlice:SetAlpha(0)

    -- Kill all child textures (corners, edges, center)
    for _, region in ipairs({nineSlice:GetRegions()}) do
        if region:IsObjectType("Texture") then
            region:SetTexture(nil)
            region:SetAtlas(nil)
            region:Hide()
        end
    end

    -- Kill known NineSlice parts
    local parts = {"TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
                   "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center"}
    for _, part in ipairs(parts) do
        local tex = nineSlice[part]
        if tex then
            tex:SetTexture(nil)
            tex:SetAtlas(nil)
            tex:Hide()
        end
    end
end

-- Apply QUI backdrop
local function ApplyQUIBackdrop(trackerFrame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not trackerFrame then return end

    -- Kill Blizzard's NineSlice completely
    KillNineSlice(trackerFrame.NineSlice)

    -- Hook SetBackgroundAlpha so edit mode opacity also affects our backdrop
    if trackerFrame.SetBackgroundAlpha and not trackerFrame.quiBackgroundHooked then
        hooksecurefunc(trackerFrame, "SetBackgroundAlpha", function(self, alpha)
            -- Keep NineSlice hidden
            if self.NineSlice then
                self.NineSlice:Hide()
                self.NineSlice:SetAlpha(0)
            end
            -- Apply edit mode opacity to our backdrop (get fresh colors)
            if self.quiBackdrop then
                local _, _, _, _, currBgR, currBgG, currBgB = GetColors()
                self.quiBackdrop:SetBackdropColor(currBgR, currBgG, currBgB, alpha)
            end
        end)
        trackerFrame.quiBackgroundHooked = true
    end

    -- Get initial opacity from edit mode (0 is valid = transparent, so check for nil)
    local manager = _G.ObjectiveTrackerManager
    local opacity
    if manager and manager.backgroundAlpha ~= nil then
        opacity = manager.backgroundAlpha
    else
        opacity = bga or 0.95
    end

    -- Create QUI backdrop (anchors will be set by UpdateBackdropAnchors)
    if not trackerFrame.quiBackdrop then
        trackerFrame.quiBackdrop = CreateFrame("Frame", nil, trackerFrame, "BackdropTemplate")
        trackerFrame.quiBackdrop:SetFrameLevel(math.max(trackerFrame:GetFrameLevel() - 1, 0))
        trackerFrame.quiBackdrop:EnableMouse(false)
    end

    local settings = GetSettings()
    local hideBorder = settings and settings.hideObjectiveTrackerBorder

    trackerFrame.quiBackdrop:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = hideBorder and 0 or 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    trackerFrame.quiBackdrop:SetBackdropColor(bgr, bgg, bgb, opacity)
    if hideBorder then
        trackerFrame.quiBackdrop:SetBackdropBorderColor(0, 0, 0, 0)
    else
        trackerFrame.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
    end

    -- Set initial anchors
    UpdateBackdropAnchors()
end

-- Get font path
local function GetFontPath()
    local QUI = _G.QUI
    return QUI and QUI.GetGlobalFont and QUI:GetGlobalFont() or STANDARD_TEXT_FONT
end

-- Apply font and color to a single line (objective text)
local function StyleLine(line, fontPath, textFontSize, textColor)
    if not line then return end
    if line.Text then
        line.Text:SetFont(fontPath, textFontSize, FONT_FLAGS)
        SafeSetTextColor(line.Text, textColor)

        -- Recalculate line height after font change to handle multi-line wrapping
        -- GetStringHeight returns the actual rendered height including wrapped lines
        local textHeight = line.Text:GetStringHeight()
        if textHeight and textHeight > 0 then
            local currentHeight = line:GetHeight()
            local minHeight = textHeight + 4  -- Add small padding
            if currentHeight < minHeight then
                line:SetHeight(minHeight)
            end
        end
    end
    if line.Dash then
        line.Dash:SetFont(fontPath, textFontSize, FONT_FLAGS)
        SafeSetTextColor(line.Dash, textColor)
    end
end

-- Apply font and color to a block (quest name header + all objective lines)
local function StyleBlock(block, fontPath, titleFontSize, textFontSize, titleColor, textColor)
    if not block then return end

    -- Style block header (quest/achievement title)
    if titleFontSize > 0 and block.HeaderText then
        block.HeaderText:SetFont(fontPath, titleFontSize, FONT_FLAGS)
        SafeSetTextColor(block.HeaderText, titleColor)
    end

    -- Style all lines in the block (objectives)
    if textFontSize > 0 and block.usedLines then
        for _, line in pairs(block.usedLines) do
            StyleLine(line, fontPath, textFontSize, textColor)
        end
    end
end

-- Apply font sizes and colors to all tracker elements
-- moduleFontSize: module headers (QUESTS, ACHIEVEMENTS, etc.)
-- titleFontSize: quest/achievement titles
-- textFontSize: objective text lines (- Kill 5 boars: 3/5)
-- moduleColor, titleColor, textColor: optional color tables {r, g, b, a}
local function ApplyFontStyles(moduleFontSize, titleFontSize, textFontSize, moduleColor, titleColor, textColor)
    local fontPath = GetFontPath()

    for _, trackerName in ipairs(trackerModules) do
        local tracker = _G[trackerName]
        if tracker then
            -- Style module header text (e.g., "QUESTS", "ACHIEVEMENTS")
            if moduleFontSize > 0 and tracker.Header and tracker.Header.Text then
                tracker.Header.Text:SetFont(fontPath, moduleFontSize, FONT_FLAGS)
                SafeSetTextColor(tracker.Header.Text, moduleColor)
            end

            -- Style all blocks in this module
            if tracker.usedBlocks then
                for template, blocks in pairs(tracker.usedBlocks) do
                    for blockID, block in pairs(blocks) do
                        StyleBlock(block, fontPath, titleFontSize, textFontSize, titleColor, textColor)
                    end
                end
            end
        end
    end

    -- Main objective tracker header
    local TrackerFrame = _G.ObjectiveTrackerFrame
    if TrackerFrame and TrackerFrame.Header and TrackerFrame.Header.Text then
        if moduleFontSize > 0 then
            TrackerFrame.Header.Text:SetFont(fontPath, moduleFontSize, FONT_FLAGS)
            SafeSetTextColor(TrackerFrame.Header.Text, moduleColor)
        end
    end
end

-- Hook to style newly created lines
local function HookLineCreation()
    local settings = GetSettings()
    if not settings then return end

    local textFontSize = settings.objectiveTrackerTextFontSize or 0
    if textFontSize <= 0 then return end

    local fontPath = GetFontPath()

    -- Hook ObjectiveTrackerBlockMixin:AddObjective to style lines as they're created
    if ObjectiveTrackerBlockMixin and ObjectiveTrackerBlockMixin.AddObjective and not ObjectiveTrackerBlockMixin.quiAddObjectiveHooked then
        hooksecurefunc(ObjectiveTrackerBlockMixin, "AddObjective", function(self, objectiveKey, text, template, useFullHeight, dashStyle, colorStyle, adjustForNoText, overrideHeight)
            local line = self.usedLines and self.usedLines[objectiveKey]
            if line then
                local currentSettings = GetSettings()
                local currentTextSize = currentSettings and currentSettings.objectiveTrackerTextFontSize or 0
                local currentTextColor = currentSettings and currentSettings.objectiveTrackerTextColor
                if currentTextSize > 0 then
                    StyleLine(line, GetFontPath(), currentTextSize, currentTextColor)
                    -- Schedule line repositioning to fix overlap from text wrapping
                    ScheduleLineReposition()
                end
            end
        end)
        ObjectiveTrackerBlockMixin.quiAddObjectiveHooked = true
    end

    -- Hook ObjectiveTrackerBlockMixin:SetHeader to style block headers (quest/achievement titles)
    if ObjectiveTrackerBlockMixin and ObjectiveTrackerBlockMixin.SetHeader and not ObjectiveTrackerBlockMixin.quiSetHeaderHooked then
        hooksecurefunc(ObjectiveTrackerBlockMixin, "SetHeader", function(self, text)
            local currentSettings = GetSettings()
            local currentTitleSize = currentSettings and currentSettings.objectiveTrackerTitleFontSize or 0
            local currentTitleColor = currentSettings and currentSettings.objectiveTrackerTitleColor
            if currentTitleSize > 0 and self.HeaderText then
                self.HeaderText:SetFont(GetFontPath(), currentTitleSize, FONT_FLAGS)
                SafeSetTextColor(self.HeaderText, currentTitleColor)
            end
        end)
        ObjectiveTrackerBlockMixin.quiSetHeaderHooked = true
    end

    -- Note: POI button glows are hidden via HidePOIButtonGlows() called from ScheduleBackdropUpdate()
end

-- Main skinning function
local function SkinObjectiveTracker()
    local settings = GetSettings()
    if not settings or not settings.skinObjectiveTracker then return end

    local TrackerFrame = _G.ObjectiveTrackerFrame
    if not TrackerFrame then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetColors()

    -- Sync Blizzard's height with our max height setting
    SyncBlizzardHeight()

    -- Apply max width setting
    ApplyMaxWidth(settings)

    -- Apply QUI backdrop with our colors/opacity
    ApplyQUIBackdrop(TrackerFrame, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    -- Apply font size and color settings
    local moduleFontSize = settings.objectiveTrackerModuleFontSize or 12
    local titleFontSize = settings.objectiveTrackerTitleFontSize or 10
    local textFontSize = settings.objectiveTrackerTextFontSize or 10
    local moduleColor = settings.objectiveTrackerModuleColor
    local titleColor = settings.objectiveTrackerTitleColor
    local textColor = settings.objectiveTrackerTextColor
    ApplyFontStyles(moduleFontSize, titleFontSize, textFontSize, moduleColor, titleColor, textColor)

    -- Hook line creation to style new lines dynamically
    HookLineCreation()

    -- Skin main header (minimize button repositioned in ApplyMaxWidth)
    if TrackerFrame.Header then
        SkinTrackerHeader(TrackerFrame.Header)
    end

    -- Skin all tracker module headers
    for _, trackerName in ipairs(trackerModules) do
        local tracker = _G[trackerName]
        if tracker then
            SkinTrackerHeader(tracker.Header)
        end
    end

    -- Hook the main container's Update to update backdrop anchors when content changes
    if TrackerFrame.Update and not TrackerFrame.quiUpdateHooked then
        hooksecurefunc(TrackerFrame, "Update", ScheduleBackdropUpdate)
        TrackerFrame.quiUpdateHooked = true
    end

    -- Hook main container's SetCollapsed for when entire tracker is collapsed/expanded
    if TrackerFrame.SetCollapsed and not TrackerFrame.quiCollapseHooked then
        hooksecurefunc(TrackerFrame, "SetCollapsed", ScheduleBackdropUpdate)
        TrackerFrame.quiCollapseHooked = true
    end

    -- Hook each module's header minimize button, SetCollapsed, LayoutContents, and AddBlock
    for _, trackerName in ipairs(trackerModules) do
        local tracker = _G[trackerName]
        if tracker and not tracker.quiCollapseHooked then
            -- Hook the header's minimize button click
            if tracker.Header and tracker.Header.MinimizeButton then
                tracker.Header.MinimizeButton:HookScript("OnClick", ScheduleBackdropUpdate)
            end

            -- Hook SetCollapsed on the module itself
            if tracker.SetCollapsed then
                hooksecurefunc(tracker, "SetCollapsed", ScheduleBackdropUpdate)
            end

            -- Hook LayoutContents to catch world quest/bonus objective changes
            if tracker.LayoutContents then
                hooksecurefunc(tracker, "LayoutContents", ScheduleBackdropUpdate)
            end

            -- Hook AddBlock to style quest icons with glows (#65)
            if tracker.AddBlock and not tracker.quiAddBlockHooked then
                hooksecurefunc(tracker, "AddBlock", HandleQuestBlockIcons)
                tracker.quiAddBlockHooked = true
            end

            tracker.quiCollapseHooked = true
        end
    end

    -- Also update on size changes (with guard to prevent multiple hooks)
    if not TrackerFrame.quiSizeChangedHooked then
        TrackerFrame:HookScript("OnSizeChanged", UpdateBackdropAnchors)
        TrackerFrame.quiSizeChangedHooked = true
    end

    -- Hook ObjectiveTrackerManager.SetOpacity to catch when edit mode loads saved settings
    local manager = _G.ObjectiveTrackerManager
    if manager and manager.SetOpacity and not manager.quiOpacityHooked then
        hooksecurefunc(manager, "SetOpacity", function(self, opacityPercent)
            local alpha = (opacityPercent or 0) / 100
            local _, _, _, _, currBgR, currBgG, currBgB = GetColors()
            if TrackerFrame.quiBackdrop then
                TrackerFrame.quiBackdrop:SetBackdropColor(currBgR, currBgG, currBgB, alpha)
            end
        end)
        manager.quiOpacityHooked = true
    end

    -- Hide POI glows after delay to catch late-loading POI buttons
    -- (ScheduleBackdropUpdate also calls HidePOIButtonGlows at 0.15s)
    C_Timer.After(0.5, HidePOIButtonGlows)

    TrackerFrame.quiSkinned = true
end

-- Refresh/update settings (called from options panel)
local function RefreshObjectiveTracker()
    local settings = GetSettings()
    if not settings or not settings.skinObjectiveTracker then return end

    local TrackerFrame = _G.ObjectiveTrackerFrame
    if not TrackerFrame then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetColors()

    -- Sync Blizzard's height with our max height setting
    SyncBlizzardHeight()

    -- Update max width setting
    ApplyMaxWidth(settings)

    -- Update backdrop colors (SetBackdrop resets colors, so must re-apply both)
    if TrackerFrame.quiBackdrop then
        local hideBorder = settings.hideObjectiveTrackerBorder

        -- Get opacity from edit mode manager
        local manager = _G.ObjectiveTrackerManager
        local opacity
        if manager and manager.backgroundAlpha ~= nil then
            opacity = manager.backgroundAlpha
        else
            opacity = bga or 0.95
        end

        -- Apply backdrop (edgeSize 0 hides border, 1 shows it)
        TrackerFrame.quiBackdrop:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = hideBorder and 0 or 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        TrackerFrame.quiBackdrop:SetBackdropColor(bgr, bgg, bgb, opacity)
        if hideBorder then
            TrackerFrame.quiBackdrop:SetBackdropBorderColor(0, 0, 0, 0)
        else
            TrackerFrame.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
        end
    end

    -- Update anchors
    UpdateBackdropAnchors()

    -- Update font sizes and colors
    local moduleFontSize = settings.objectiveTrackerModuleFontSize or 12
    local titleFontSize = settings.objectiveTrackerTitleFontSize or 10
    local textFontSize = settings.objectiveTrackerTextFontSize or 10
    local moduleColor = settings.objectiveTrackerModuleColor
    local titleColor = settings.objectiveTrackerTitleColor
    local textColor = settings.objectiveTrackerTextColor
    ApplyFontStyles(moduleFontSize, titleFontSize, textFontSize, moduleColor, titleColor, textColor)

    -- Ensure hooks are in place
    HookLineCreation()
end

-- Expose refresh function globally
_G.QUI_RefreshObjectiveTracker = RefreshObjectiveTracker
_G.QUI_RefreshObjectiveTrackerColors = RefreshObjectiveTracker

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------

-- All events used by objective tracker modules (from Blizzard source)
local trackingEvents = {
    -- Achievement tracker
    "CONTENT_TRACKING_UPDATE",
    "TRACKED_ACHIEVEMENT_UPDATE",
    "TRACKED_ACHIEVEMENT_LIST_CHANGED",
    "ACHIEVEMENT_EARNED",
    -- Adventure tracker + super tracking (also used for hiding POI glow)
    "SUPER_TRACKING_CHANGED",
    "TRANSMOG_COLLECTION_SOURCE_ADDED",
    "TRACKING_TARGET_INFO_UPDATE",
    "TRACKABLE_INFO_UPDATE",
    "HOUSE_DECOR_ADDED_TO_CHEST",
    -- Bonus objective tracker
    "CRITERIA_COMPLETE",
    "QUEST_TURNED_IN",
    "QUEST_LOG_UPDATE",
    "QUEST_WATCH_LIST_CHANGED",
    "SCENARIO_BONUS_VISIBILITY_UPDATE",
    "SCENARIO_CRITERIA_UPDATE",
    "SCENARIO_UPDATE",
    "QUEST_ACCEPTED",
    "QUEST_REMOVED",
    -- Campaign quest tracker
    -- (uses QUEST_LOG_UPDATE, QUEST_WATCH_LIST_CHANGED - already listed)
    -- Monthly activities tracker
    "PERKS_ACTIVITY_COMPLETED",
    "PERKS_ACTIVITIES_TRACKED_UPDATED",
    "PERKS_ACTIVITIES_TRACKED_LIST_CHANGED",
    -- UI Widget tracker
    "ZONE_CHANGED_NEW_AREA",
    "ZONE_CHANGED_INDOORS",  -- BUG-003: cleanup glows on building transitions
    -- Professions recipe tracker
    "CURRENCY_DISPLAY_UPDATE",
    "TRACKED_RECIPE_UPDATE",
    "BAG_UPDATE_DELAYED",
    -- Quest tracker
    "QUEST_AUTOCOMPLETE",
    "QUEST_POI_UPDATE",
    -- Scenario tracker
    "SCENARIO_SPELL_UPDATE",
    "SCENARIO_COMPLETED",
    "SCENARIO_CRITERIA_SHOW_STATE_UPDATE",
    -- World quest tracker
    -- (uses events already listed above)
}

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Delay to ensure ObjectiveTrackerFrame is ready
        C_Timer.After(1, function()
            SkinObjectiveTracker()
            -- Register for tracking events after initial skin
            for _, trackEvent in ipairs(trackingEvents) do
                self:RegisterEvent(trackEvent)
            end
        end)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    elseif event == "SUPER_TRACKING_CHANGED" then
        -- Quest selection changed, hide glow immediately (with tiny delay for POI to update)
        C_Timer.After(0.01, HidePOIButtonGlows)
        ScheduleBackdropUpdate()
    elseif event == "SCENARIO_UPDATE" or event == "SCENARIO_COMPLETED" then
        -- Scenario started/ended, update width (may need to expand/shrink)
        C_Timer.After(0.2, function()
            local settings = GetSettings()
            if settings and settings.skinObjectiveTracker then
                ApplyMaxWidth(settings)
            end
        end)
        ScheduleBackdropUpdate()
    else
        -- Content changed, update backdrop with debouncing
        ScheduleBackdropUpdate()
    end
end)
