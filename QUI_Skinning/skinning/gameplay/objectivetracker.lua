local addonName, ns = ...

local Helpers = ns.Helpers
local GetCore = Helpers.GetCore
local SkinBase = ns.SkinBase

---------------------------------------------------------------------------
-- OBJECTIVE TRACKER SKINNING
-- Applies QUI color scheme with dynamic content-height backdrop
---------------------------------------------------------------------------

local GetFontFlags = Helpers.GetGeneralFontOutline

-- Debounce flag to prevent multiple concurrent backdrop updates
local pendingBackdropUpdate = false

local function RunAfterFirstFrame(callback, delay)
    if ns.RunAfterFirstFrame then
        return ns.RunAfterFirstFrame(callback, delay)
    end
    if C_Timer and C_Timer.After then
        return C_Timer.After(delay or 0, callback)
    end
    if type(callback) == "function" then
        return callback()
    end
    return nil
end

-- Get settings
local function GetSettings()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings
end

-- Safely set text color from a color table with bounds validation
local function SafeSetTextColor(fontString, colorTable)
    if not fontString or not colorTable then return end
    if type(colorTable) ~= "table" or #colorTable < 3 then return end
    fontString:SetTextColor(colorTable[1] or 1, colorTable[2] or 1, colorTable[3] or 1, colorTable[4] or 1)
end

local GetFontPath = Helpers.GetGeneralFont

-- Route the existing raw SetFont on Blizzard ObjectiveTracker FontStrings
-- through the CJK-fallback path. These FontStrings were already SetFont'd
-- (equivalent taint), so the SetFontObject family adds CJK fallback without
-- new taint exposure. Same args as the original SetFont call.
local function CJKFont(fs, path, size, flags)
    if Helpers and Helpers.ApplyFontWithFallback then
        Helpers.ApplyFontWithFallback(fs, path, size, flags)
    else
        fs:SetFont(path, size, flags)
    end
end

-- Apply font and color to a single line (objective text)
-- Returns true if line height was changed (callers use this to avoid unnecessary repositioning)
-- IMPORTANT: This function must be idempotent. Redundant SetFont calls trigger text
-- reflow which cascades into Blizzard layout updates → AddObjective fires again →
-- StyleLine again → infinite oscillation. We skip SetFont when the font is already
-- correct, and only adjust height when the font actually changed (with a 1px tolerance).
-- skipHeight: when true, skip the SetHeight call. Hook callers (AddObjective, AddBlock)
-- MUST pass true to avoid the feedback loop: SetHeight → Blizzard relayout → AddObjective
-- → StyleLine → SetHeight → repeat. Direct callers (Skin, Refresh) can pass false/nil
-- for a one-shot height adjustment that settles after one extra hook cycle.
local function StyleLine(line, fontPath, textFontSize, textColor, skipHeight)
    if not line then return false end
    local heightChanged = false
    local targetFlags = GetFontFlags()
    if line.Text then
        -- Only call SetFont when font actually needs changing
        local curFont, curSize, curFlags = line.Text:GetFont()
        local fontChanged = curFont ~= fontPath or curSize ~= textFontSize or curFlags ~= targetFlags
        if fontChanged then
            CJKFont(line.Text, fontPath, textFontSize, targetFlags)

            -- Recalculate line height after font change to handle multi-line wrapping.
            -- Only runs when font actually changed; 1px tolerance prevents sub-pixel
            -- oscillation between our height and Blizzard's layout-computed height.
            -- SKIP when called from hooks (skipHeight=true) to prevent the relayout
            -- feedback loop: SetHeight → Blizzard relayout → AddObjective → hook → repeat.
            if not skipHeight then
                local textHeight = line.Text:GetStringHeight()
                if textHeight and textHeight > 0 then
                    local currentHeight = line:GetHeight()
                    local minHeight = textHeight + 4
                    if minHeight - currentHeight > 1 then
                        line:SetHeight(minHeight)
                        heightChanged = true
                    end
                end
            end
        end
        SafeSetTextColor(line.Text, textColor)
    end
    if line.Dash then
        local curFont, curSize, curFlags = line.Dash:GetFont()
        if curFont ~= fontPath or curSize ~= textFontSize or curFlags ~= targetFlags then
            CJKFont(line.Dash, fontPath, textFontSize, targetFlags)
        end
        SafeSetTextColor(line.Dash, textColor)
    end
    return heightChanged
end

-- Apply font and color to a block (quest name header + all objective lines)
-- skipHeight: forwarded to StyleLine — see StyleLine comment for details.
-- Per-instance UpdateHighlight hook: re-assert QUI text colors on hover.
-- Blizzard's UpdateHighlight (OnHeaderEnter/Leave) swaps HeaderText + every line/dash to
-- OBJECTIVE_TRACKER_COLOR, clobbering our themed title/text colors as the cursor moves.
-- CRITICAL: XML mixin="ObjectiveTrackerBlockMixin" COPIES the mixin's functions onto each
-- block frame at creation, so hooksecurefunc on the mixin TABLE never fires for blocks that
-- already exist (e.g. quests tracked at login) — only the instance's own copy runs. Hook the
-- instance directly so coverage is timing-independent. Called from StyleBlock (covers blocks
-- present at each skin pass, e.g. login) and from the AddObjective/SetHeader hooks (cover blocks
-- created later, e.g. quests accepted in-session). Guarded so each block is hooked once.
-- TAINT: fires from mouse-hover scripts (insecure), plain SetTextColor on insecure FontStrings
-- is safe; re-assert synchronously so there is no visible flash of Blizzard's color.
local function EnsureBlockHighlightHook(block)
    if not block or SkinBase.GetFrameData(block, "highlightHooked") or not block.UpdateHighlight then return end
    SkinBase.SetFrameData(block, "highlightHooked", true)
    hooksecurefunc(block, "UpdateHighlight", function(self)
        local s = GetSettings()
        if not s or not s.skinObjectiveTracker then return end
        if self.HeaderText then
            SafeSetTextColor(self.HeaderText, s.objectiveTrackerTitleColor)
        end
        if self.usedLines then
            for _, line in pairs(self.usedLines) do
                SafeSetTextColor(line.Text, s.objectiveTrackerTextColor)
                if line.Dash then
                    SafeSetTextColor(line.Dash, s.objectiveTrackerTextColor)
                end
            end
        end
    end)
end

local function StyleBlock(block, fontPath, titleFontSize, textFontSize, titleColor, textColor, skipHeight)
    if not block then return end

    EnsureBlockHighlightHook(block)

    if titleFontSize > 0 and block.HeaderText then
        -- Idempotent guard: skip SetFont when font is already correct to prevent
        -- reflow → Blizzard relayout → AddBlock hook → StyleBlock → oscillation loop
        local curFont, curSize, curFlags = block.HeaderText:GetFont()
        local targetFlags = GetFontFlags()
        if curFont ~= fontPath or curSize ~= titleFontSize or curFlags ~= targetFlags then
            CJKFont(block.HeaderText, fontPath, titleFontSize, targetFlags)
        end
        SafeSetTextColor(block.HeaderText, titleColor)
    end

    if textFontSize > 0 and block.usedLines then
        for _, line in pairs(block.usedLines) do
            StyleLine(line, fontPath, textFontSize, textColor, skipHeight)
        end
    end
end

-- Get LibCustomGlow for quest icon glows
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

-- Style quest POI icon (glow removed - was causing indefinite glow bug BUG-003)
local function StyleQuestPOIIcon(button)
    if not button or SkinBase.IsStyled(button) then return end

    -- Style the POI button. On QuestObjectiveItemButtonTemplate only NormalTexture
    -- has a parentKey (Blizzard_ObjectiveTrackerShared.xml:34); Pushed/Highlight have
    -- none, so button.PushedTexture/.HighlightTexture were always nil — use the
    -- texture accessors instead.
    if button.NormalTexture then
        button.NormalTexture:SetAlpha(0)
    end
    local pushed = button.GetPushedTexture and button:GetPushedTexture()
    if pushed then
        pushed:SetAlpha(0)
    end
    local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
    if highlight then
        highlight:SetAlpha(0.3)
    end

    -- Stop any existing LibCustomGlow effects (cleanup from previous versions)
    if LCG and LCG.PixelGlow_Stop then
        LCG.PixelGlow_Stop(button, "_QUIQuestGlow")
    end

    SkinBase.MarkStyled(button)
end

-- Tint a line's completion-check icon with the QUI accent color. The current
-- ObjectiveTracker shows the check as each line's Icon (atlas
-- 'ui-questtracker-tracker-check', Blizzard_ObjectiveTrackerAnimTemplates.xml:6),
-- so we recolor that icon in place rather than forcing our own atlas (which would
-- mis-style incomplete lines whose Icon is hidden). Idempotent via IsStyled.
local function StyleCompletionCheck(icon)
    if not icon or SkinBase.IsStyled(icon) then return end

    local sr, sg, sb = SkinBase.GetSkinColors()
    if icon.SetDesaturated then icon:SetDesaturated(true) end
    icon:SetVertexColor(sr, sg, sb)

    SkinBase.MarkStyled(icon)
end

-- Apply full block skinning (fonts, colors, icons) to a single block
local function ApplyBlockSkinning(tracker, block)
    if not block or not block:IsShown() then return end

    local settings = GetSettings()
    if not settings or not settings.skinObjectiveTracker then return end

    local fontPath = GetFontPath()
    local titleFontSize = settings.objectiveTrackerTitleFontSize or 10
    local textFontSize = settings.objectiveTrackerTextFontSize or 10
    local titleColor = settings.objectiveTrackerTitleColor
    local textColor = settings.objectiveTrackerTextColor

    -- Style icons (POI button, completion check)
    local itemButton = block.ItemButton or block.itemButton
    if itemButton then StyleQuestPOIIcon(itemButton) end
    -- Completion check is per-line now: each used line's Icon carries the check
    -- atlas (there is no block.currentLine.Check in the current ObjectiveTracker).
    if block.usedLines then
        for _, line in pairs(block.usedLines) do
            if line.Icon then StyleCompletionCheck(line.Icon) end
        end
    end

    -- Style block header and all objective lines.
    -- skipHeight=true: this function is called from the AddBlock hook, so we must
    -- avoid SetHeight to prevent the relayout → AddObjective → hook → oscillation loop.
    StyleBlock(block, fontPath, titleFontSize, textFontSize, titleColor, textColor, true)
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
        header.Background:SetTexture(nil) -- Nilable-correct clear (SetAtlas atlas arg is Nilable=false)
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

    -- Set Blizzard's internal height so truncation happens at our max.
    -- TAINT NOTE: Direct property write to Blizzard frame — accepted/required because
    -- Blizzard's UpdateHeight() reads self.editModeHeight. All callers of SyncBlizzardHeight()
    -- are already guarded by InCombatLockdown() (ApplyLayoutSettingsSafely) or deferred to
    -- PLAYER_REGEN_ENABLED, so this write never occurs during combat.
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
            if not SkinBase.GetFrameData(minBtn, "highlightSet") and minBtn:GetHighlightTexture() then
                minBtn:GetHighlightTexture():SetAtlas("ui-questtrackerbutton-yellow-highlight")
                SkinBase.SetFrameData(minBtn, "highlightSet", true)
            end
        end

        -- Hook SetCollapsed to override atlas with secondary style
        -- (Blizzard resets to collapse-all/expand-all on state change)
        if TrackerFrame.Header.SetCollapsed and not SkinBase.GetFrameData(TrackerFrame.Header, "setCollapsedHooked") then
            -- TAINT SAFETY: Defer to break taint chain from secure context.
            hooksecurefunc(TrackerFrame.Header, "SetCollapsed", function(self, collapsed)
                C_Timer.After(0, function()
                    UpdateMinimizeButtonAtlas(self.MinimizeButton, collapsed)
                end)
            end)
            SkinBase.SetFrameData(TrackerFrame.Header, "setCollapsedHooked", true)

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
    -- ScenarioObjectiveTrackerStageMixin:UpdateStageBlock re-shows NormalBG/FinalBG/
    -- GlowTexture and re-anchors Stage/Name on every stage change; re-run the hide
    -- after it. The mixin is applied via XML mixin= (Blizzard_ScenarioObjectiveTracker
    -- .xml:231), which COPIES UpdateStageBlock onto the StageBlock INSTANCE at creation,
    -- and Blizzard calls stageBlock:UpdateStageBlock(...) on that instance (.lua:245) —
    -- so a hook on the mixin TABLE never fires. Hook the instance, per-instance guarded
    -- (mirrors EnsureBlockHighlightHook), so coverage is timing-independent.
    local scenario = _G.ScenarioObjectiveTracker
    local stageBlock = scenario and scenario.StageBlock
    if stageBlock and stageBlock.UpdateStageBlock
        and not SkinBase.GetFrameData(stageBlock, "stageHooked") then
        SkinBase.SetFrameData(stageBlock, "stageHooked", true)
        hooksecurefunc(stageBlock, "UpdateStageBlock", function()
            HideScenarioStageArtwork()
        end)
    end
end

-- Update backdrop to match content, respecting max height setting
local function UpdateBackdropAnchors()
    local TrackerFrame = _G.ObjectiveTrackerFrame
    local quiBackdrop = TrackerFrame and SkinBase.GetFrameData(TrackerFrame, "backdrop")
    if not TrackerFrame or not quiBackdrop then return end

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
    quiBackdrop:ClearAllPoints()
    quiBackdrop:SetPoint("TOPLEFT", TrackerFrame, "TOPLEFT", -15, 0)
    quiBackdrop:SetPoint("TOPRIGHT", TrackerFrame, "TOPRIGHT", 10, 0)

    if bottomModule then
        -- Calculate actual content height (guard against nil/invalid during initial layout)
        local trackerTop = TrackerFrame:GetTop()
        local contentHeight = 0
        if trackerTop and lowestBottom and trackerTop > lowestBottom then
            contentHeight = trackerTop - lowestBottom + 15  -- +15 for bottom padding
        end

        if contentHeight > maxHeight then
            -- Content exceeds max height, use fixed height
            quiBackdrop:SetHeight(maxHeight)
        else
            -- Content fits, anchor to bottommost module
            quiBackdrop:SetPoint("BOTTOM", bottomModule, "BOTTOM", 0, -15)
        end
        quiBackdrop:Show()
    else
        -- No visible modules, hide backdrop
        quiBackdrop:Hide()
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
                            -- TAINT SAFETY: Defer to break taint chain from secure context.
                            if not SkinBase.GetFrameData(block.poiButton.Glow, "hooked") then
                                Helpers.DeferredHideOnShow(block.poiButton.Glow, { combatCheck = false })
                                SkinBase.SetFrameData(block.poiButton.Glow, "hooked", true)
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

-- Lightweight width enforcement — re-applies QUI width to tracker and modules
-- without the full ApplyMaxWidth overhead (minimize button styling, hooks, etc.)
-- Called from the debounced update to catch any Blizzard width resets.
local function EnforceWidth()
    local TrackerFrame = _G.ObjectiveTrackerFrame
    if not TrackerFrame then return end

    local settings = GetSettings()
    if not settings or not settings.skinObjectiveTracker then return end

    local maxWidth
    if IsScenarioActive() then
        maxWidth = 260
    else
        maxWidth = settings.objectiveTrackerWidth or 260
    end

    -- Only set if different to avoid OnSizeChanged loops
    if math.abs(TrackerFrame:GetWidth() - maxWidth) > 0.5 then
        TrackerFrame:SetWidth(maxWidth)
    end
    if TrackerFrame.Header and math.abs(TrackerFrame.Header:GetWidth() - maxWidth) > 0.5 then
        TrackerFrame.Header:SetWidth(maxWidth)
    end
    for _, trackerName in ipairs(trackerModules) do
        local tracker = _G[trackerName]
        if tracker then
            if math.abs(tracker:GetWidth() - maxWidth) > 0.5 then
                tracker:SetWidth(maxWidth)
            end
            if tracker.Header and math.abs(tracker.Header:GetWidth() - maxWidth) > 0.5 then
                tracker.Header:SetWidth(maxWidth)
            end
        end
    end
end

local function RunObjectiveTrackerPostLayoutUpdate()
    pendingBackdropUpdate = false
    EnforceWidth()
    UpdateBackdropAnchors()
    HidePOIButtonGlows()
end

local function DeferObjectiveTrackerPostLayoutUpdate()
    if pendingBackdropUpdate then return end
    pendingBackdropUpdate = true
    -- FrameXML DirtiableMixin:MarkDirty uses RunNextFrame, and our hooks are
    -- on ObjectiveTrackerContainer:Update / module LayoutContents after layout.
    -- One frame exits protected hook stacks without a fixed 0.15s guess.
    C_Timer.After(0, RunObjectiveTrackerPostLayoutUpdate)
end

-- Debounced backdrop update to prevent multiple concurrent timers.
local function ScheduleBackdropUpdate()
    DeferObjectiveTrackerPostLayoutUpdate()
end

-- Combat-safe gate for ObjectiveTracker layout mutations (width/height/size)
local pendingProtectedLayoutUpdate = false
local protectedLayoutEventFrame = CreateFrame("Frame")
protectedLayoutEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
protectedLayoutEventFrame:SetScript("OnEvent", function()
    if not pendingProtectedLayoutUpdate then return end
    pendingProtectedLayoutUpdate = false

    local settings = GetSettings()
    if not settings or not settings.skinObjectiveTracker then return end

    SyncBlizzardHeight()
    ApplyMaxWidth(settings)
    ScheduleBackdropUpdate()
end)

local function SetupDebugInstrumentation()
    ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
    ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "ObjTracker_ProtectedLayout", frame = protectedLayoutEventFrame }
end
if ns.DebugRegister then -- gate contract: core/debug_gate.lua
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation() -- standalone test harness: no gate, run eagerly
end

local function ApplyLayoutSettingsSafely(settings)
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        pendingProtectedLayoutUpdate = true
        return false
    end

    SyncBlizzardHeight()
    ApplyMaxWidth(settings)
    return true
end

-- NOTE: Manual line repositioning (RepositionBlockLines / ScheduleLineReposition)
-- was removed because it caused an oscillation feedback loop:
--   AddObjective hook → StyleLine height change → reposition → SetHeight on block
--   → Blizzard async relayout → AddObjective fires again → repeat
-- Blizzard anchors each objective line to the previous line's BOTTOMLEFT, so
-- setting the correct line height in StyleLine is sufficient — subsequent lines
-- shift down automatically through the anchor chain.

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

-- Resolve edit-mode opacity (0 is valid = transparent, so check for nil)
local function ResolveBackdropOpacity(bga)
    local manager = _G.ObjectiveTrackerManager
    if manager and manager.backgroundAlpha ~= nil then
        return manager.backgroundAlpha
    end
    return bga or 0.95
end

-- Apply backdrop border/background colors with the hidden-border one-pixel inset
local function ApplyBackdropColors(backdrop, hideBorder, sr, sg, sb, sa, bgr, bgg, bgb, opacity)
    local borderColor = hideBorder and { 0, 0, 0, 0 } or { sr, sg, sb, sa }
    local bgColor = { bgr, bgg, bgb, opacity }
    -- ApplyPixelBackdrop seeds data.bgColor/data.borderColor and renders the
    -- backdrop (its internal manual setters also populate _quiBg*/_quiBorder*), so
    -- the prior Helpers.SetFrameBackdrop* writes here were dead: they only re-wrote
    -- _quiBg*, which data.bgColor shadows on the next scale-refresh rebuild. The
    -- colors are identical, so dropping them changes nothing visible (mirrors the
    -- SetBackgroundAlpha-hook fix below).
    SkinBase.ApplyPixelBackdrop(backdrop, hideBorder and 0 or 1, true, true, borderColor, bgColor, nil, nil, 1)
end

-- Apply QUI backdrop
local function ApplyQUIBackdrop(trackerFrame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not trackerFrame then return end

    -- Kill Blizzard's NineSlice completely
    KillNineSlice(trackerFrame.NineSlice)

    -- Hook SetBackgroundAlpha so edit mode opacity also affects our backdrop
    if trackerFrame.SetBackgroundAlpha and not SkinBase.GetFrameData(trackerFrame, "backgroundHooked") then
        -- TAINT SAFETY: Defer to break taint chain from secure context.
        hooksecurefunc(trackerFrame, "SetBackgroundAlpha", function(self, alpha)
            C_Timer.After(0, function()
                -- Keep NineSlice hidden
                if self.NineSlice then
                    self.NineSlice:Hide()
                    self.NineSlice:SetAlpha(0)
                end
                -- Apply edit mode opacity to our backdrop (get fresh colors)
                local bd = SkinBase.GetFrameData(self, "backdrop")
                if bd then
                    local _, _, _, _, currBgR, currBgG, currBgB = SkinBase.GetSkinColors()
                    -- Persist into data.bgColor so the edit-mode opacity survives the next
                    -- scale-refresh rebuild (Helpers.SetFrameBackdropColor wrote only the
                    -- _quiBg* cache, which data.bgColor shadows on rebuild).
                    SkinBase.SetBackdropColors(bd, nil, { currBgR, currBgG, currBgB, alpha })
                end
            end)
        end)
        SkinBase.SetFrameData(trackerFrame, "backgroundHooked", true)
    end

    -- Get initial opacity from edit mode (0 is valid = transparent, so check for nil)
    local opacity = ResolveBackdropOpacity(bga)

    -- Create QUI backdrop (anchors will be set by UpdateBackdropAnchors)
    local backdrop = SkinBase.GetFrameData(trackerFrame, "backdrop")
    if not backdrop then
        backdrop = CreateFrame("Frame", nil, trackerFrame, "BackdropTemplate")
        backdrop:SetFrameLevel(math.max(trackerFrame:GetFrameLevel() - 1, 0))
        backdrop:EnableMouse(false)
        SkinBase.SetFrameData(trackerFrame, "backdrop", backdrop)
    end

    local settings = GetSettings()
    local hideBorder = settings and settings.hideObjectiveTrackerBorder

    ApplyBackdropColors(backdrop, hideBorder, sr, sg, sb, sa, bgr, bgg, bgb, opacity)

    -- Set initial anchors
    UpdateBackdropAnchors()
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
                local curFont, curSize, curFlags = tracker.Header.Text:GetFont()
                local targetFlags = GetFontFlags()
                if curFont ~= fontPath or curSize ~= moduleFontSize or curFlags ~= targetFlags then
                    CJKFont(tracker.Header.Text, fontPath, moduleFontSize, targetFlags)
                end
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
            local curFont, curSize, curFlags = TrackerFrame.Header.Text:GetFont()
            local targetFlags = GetFontFlags()
            if curFont ~= fontPath or curSize ~= moduleFontSize or curFlags ~= targetFlags then
                CJKFont(TrackerFrame.Header.Text, fontPath, moduleFontSize, targetFlags)
            end
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
    -- TAINT SAFETY: Defer to break taint chain from secure context.
    if ObjectiveTrackerBlockMixin and ObjectiveTrackerBlockMixin.AddObjective and not SkinBase.GetFrameData(ObjectiveTrackerBlockMixin, "addObjectiveHooked") then
        hooksecurefunc(ObjectiveTrackerBlockMixin, "AddObjective", function(self, objectiveKey)
            local block = self
            EnsureBlockHighlightHook(block)
            C_Timer.After(0, function()
                local line = block.usedLines and block.usedLines[objectiveKey]
                if line then
                    local currentSettings = GetSettings()
                    local currentTextSize = currentSettings and currentSettings.objectiveTrackerTextFontSize or 0
                    local currentTextColor = currentSettings and currentSettings.objectiveTrackerTextColor
                    if currentTextSize > 0 then
                        -- Style the line (font + color only, NO height adjustment).
                        -- skipHeight=true prevents the oscillation feedback loop:
                        -- SetHeight → Blizzard relayout → AddObjective → hook → repeat.
                        -- Blizzard anchors each line to the previous line's bottom,
                        -- so the layout remains correct without manual height changes.
                        StyleLine(line, GetFontPath(), currentTextSize, currentTextColor, true)
                    end
                end
            end)
        end)
        SkinBase.SetFrameData(ObjectiveTrackerBlockMixin, "addObjectiveHooked", true)
    end

    -- Hook ObjectiveTrackerBlockMixin:SetHeader to style block headers (quest/achievement titles)
    -- TAINT SAFETY: Defer to break taint chain from secure context.
    if ObjectiveTrackerBlockMixin and ObjectiveTrackerBlockMixin.SetHeader and not SkinBase.GetFrameData(ObjectiveTrackerBlockMixin, "setHeaderHooked") then
        hooksecurefunc(ObjectiveTrackerBlockMixin, "SetHeader", function(self)
            local block = self
            EnsureBlockHighlightHook(block)
            C_Timer.After(0, function()
                local currentSettings = GetSettings()
                local currentTitleSize = currentSettings and currentSettings.objectiveTrackerTitleFontSize or 0
                local currentTitleColor = currentSettings and currentSettings.objectiveTrackerTitleColor
                if currentTitleSize > 0 and block.HeaderText then
                    -- Idempotent guard: skip SetFont when font is already correct to prevent
                    -- reflow → Blizzard relayout → SetHeader hook → oscillation loop
                    local curFont, curSize, curFlags = block.HeaderText:GetFont()
                    local targetFont = GetFontPath()
                    local targetFlags = GetFontFlags()
                    if curFont ~= targetFont or curSize ~= currentTitleSize or curFlags ~= targetFlags then
                        CJKFont(block.HeaderText, targetFont, currentTitleSize, targetFlags)
                    end
                    SafeSetTextColor(block.HeaderText, currentTitleColor)
                end
            end)
        end)
        SkinBase.SetFrameData(ObjectiveTrackerBlockMixin, "setHeaderHooked", true)
    end

    -- Note: the hover-color re-assert is installed per-block-instance in StyleBlock (the mixin-table
    -- hook approach does not work — XML mixin= copies functions onto each instance at creation).

    -- Note: POI button glows are hidden via HidePOIButtonGlows() called from ScheduleBackdropUpdate()
end

-- Main skinning function
local function SkinObjectiveTracker()
    local settings = GetSettings()
    if not settings or not settings.skinObjectiveTracker then return end

    local TrackerFrame = _G.ObjectiveTrackerFrame
    if not TrackerFrame then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()

    -- Sync Blizzard height/width with combat-safe deferral
    ApplyLayoutSettingsSafely(settings)

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

    -- TAINT SAFETY: ScheduleBackdropUpdate defers one frame out of hook stacks.
    local DeferredScheduleBackdropUpdate = DeferObjectiveTrackerPostLayoutUpdate

    -- Hook the main container's Update to update backdrop anchors when content changes
    if TrackerFrame.Update and not SkinBase.GetFrameData(TrackerFrame, "updateHooked") then
        hooksecurefunc(TrackerFrame, "Update", DeferredScheduleBackdropUpdate)
        SkinBase.SetFrameData(TrackerFrame, "updateHooked", true)
    end

    -- Hook main container's SetCollapsed for when entire tracker is collapsed/expanded
    if TrackerFrame.SetCollapsed and not SkinBase.GetFrameData(TrackerFrame, "collapseHooked") then
        hooksecurefunc(TrackerFrame, "SetCollapsed", DeferredScheduleBackdropUpdate)
        SkinBase.SetFrameData(TrackerFrame, "collapseHooked", true)
    end

    -- Hook each module's header minimize button, SetCollapsed, LayoutContents, and AddBlock
    for _, trackerName in ipairs(trackerModules) do
        local tracker = _G[trackerName]
        if tracker and not SkinBase.GetFrameData(tracker, "collapseHooked") then
            -- Hook the header's minimize button click
            if tracker.Header and tracker.Header.MinimizeButton then
                tracker.Header.MinimizeButton:HookScript("OnClick", DeferredScheduleBackdropUpdate)
            end

            -- Hook SetCollapsed on the module itself
            if tracker.SetCollapsed then
                hooksecurefunc(tracker, "SetCollapsed", DeferredScheduleBackdropUpdate)
            end

            -- Hook LayoutContents to catch world quest/bonus objective changes
            if tracker.LayoutContents then
                hooksecurefunc(tracker, "LayoutContents", DeferredScheduleBackdropUpdate)
            end

            -- Hook AddBlock to style new blocks
            -- TAINT SAFETY: Defer to break taint chain from secure context.
            if tracker.AddBlock and not SkinBase.GetFrameData(tracker, "addBlockHooked") then
                hooksecurefunc(tracker, "AddBlock", function(trackerSelf, block)
                    C_Timer.After(0, function()
                        ApplyBlockSkinning(trackerSelf, block)
                    end)
                end)
                SkinBase.SetFrameData(tracker, "addBlockHooked", true)
            end

            SkinBase.SetFrameData(tracker, "collapseHooked", true)
        end
    end

    -- Also update on size changes (with guard to prevent multiple hooks)
    -- TAINT SAFETY: Defer to break taint chain from secure context.
    -- EnforceWidth catches Blizzard resetting width back to 260 (template default)
    if not SkinBase.GetFrameData(TrackerFrame, "sizeChangedHooked") then
        TrackerFrame:HookScript("OnSizeChanged", function()
            C_Timer.After(0, function()
                EnforceWidth()
                UpdateBackdropAnchors()
            end)
        end)
        SkinBase.SetFrameData(TrackerFrame, "sizeChangedHooked", true)
    end

    -- Hook ObjectiveTrackerManager.SetOpacity to catch when edit mode loads saved settings
    local manager = _G.ObjectiveTrackerManager
    if manager and manager.SetOpacity and not SkinBase.GetFrameData(manager, "opacityHooked") then
        -- TAINT SAFETY: Defer to break taint chain from secure context.
        hooksecurefunc(manager, "SetOpacity", function(self, opacityPercent)
            C_Timer.After(0, function()
                local alpha = (opacityPercent or 0) / 100
                local _, _, _, _, currBgR, currBgG, currBgB = SkinBase.GetSkinColors()
                local bd = SkinBase.GetFrameData(TrackerFrame, "backdrop")
                if bd then
                    -- Persist into data.bgColor so the edit-mode opacity survives the next
                    -- scale-refresh rebuild (Helpers.SetFrameBackdropColor wrote only the
                    -- _quiBg* cache, which data.bgColor shadows on rebuild).
                    SkinBase.SetBackdropColors(bd, nil, { currBgR, currBgG, currBgB, alpha })
                end
            end)
        end)
        SkinBase.SetFrameData(manager, "opacityHooked", true)
    end

    -- Hide POI glows after delay to catch late-loading POI buttons
    -- (ScheduleBackdropUpdate also calls HidePOIButtonGlows at 0.15s)
    C_Timer.After(0.5, HidePOIButtonGlows)

    -- Click-through: make the objective tracker non-interactive so clicks pass to the game world
    if settings.objectiveTrackerClickThrough then
        TrackerFrame:EnableMouse(false)
    end

    SkinBase.SkinFrameText(TrackerFrame, { recurse = true })
    SkinBase.MarkSkinned(TrackerFrame)
end

-- Refresh/update settings (called from options panel)
local function RefreshObjectiveTracker()
    local settings = GetSettings()
    if not settings or not settings.skinObjectiveTracker then return end

    local TrackerFrame = _G.ObjectiveTrackerFrame
    if not TrackerFrame then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()

    -- Sync Blizzard height/width with combat-safe deferral
    ApplyLayoutSettingsSafely(settings)

    -- Update backdrop colors (SetBackdrop resets colors, so must re-apply both)
    local refreshBackdrop = SkinBase.GetFrameData(TrackerFrame, "backdrop")
    if refreshBackdrop then
        local hideBorder = settings.hideObjectiveTrackerBorder

        -- Get opacity from edit mode manager
        local opacity = ResolveBackdropOpacity(bga)

        -- Apply backdrop while preserving the one-pixel background inset when the border is hidden.
        ApplyBackdropColors(refreshBackdrop, hideBorder, sr, sg, sb, sa, bgr, bgg, bgb, opacity)
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

    -- Click-through toggle
    TrackerFrame:EnableMouse(not settings.objectiveTrackerClickThrough)
end

-- Expose refresh function globally
_G.QUI_RefreshObjectiveTracker = RefreshObjectiveTracker

if ns.Registry then
    ns.Registry:Register("skinObjectiveTracker", {
        refresh = _G.QUI_RefreshObjectiveTracker,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

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
frame:SetScript("OnEvent", function(self, event)
    if event == "SUPER_TRACKING_CHANGED" then
        -- Quest selection changed, hide glow immediately (with tiny delay for POI to update)
        C_Timer.After(0.01, HidePOIButtonGlows)
        ScheduleBackdropUpdate()
    elseif event == "SCENARIO_UPDATE" or event == "SCENARIO_COMPLETED" then
        -- Scenario started/ended, update width (may need to expand/shrink)
        C_Timer.After(0.2, function()
            local settings = GetSettings()
            if settings and settings.skinObjectiveTracker then
                ApplyLayoutSettingsSafely(settings)
            end
        end)
        ScheduleBackdropUpdate()
    else
        -- Content changed, update backdrop with debouncing
        ScheduleBackdropUpdate()
    end
end)

-- LOD catch-up: first PEW already fired before this module loads; the old
-- one-shot PLAYER_ENTERING_WORLD init runs via ns.WhenLoggedIn instead.
-- ns.WhenLoggedIn is nil only in the headless test harness, where the old
-- never-firing PEW registration was equally inert.
if ns.WhenLoggedIn then
    ns.WhenLoggedIn(function()
        RunAfterFirstFrame(function()
            SkinObjectiveTracker()
            -- Register for tracking events after initial skin
            for _, trackEvent in ipairs(trackingEvents) do
                frame:RegisterEvent(trackEvent)
            end
        end, 0.2)
    end)
end
