local addonName, ns = ...

if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end

local Helpers = ns.Helpers
local GetCore = Helpers.GetCore
local SkinBase = ns.SkinBase

local GetFontFlags = Helpers.GetGeneralFontOutline

local pendingBackdropUpdate = false
local pendingProtectedLayoutUpdate = false

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

local function GetSettings()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings
end

local function SafeSetTextColor(fontString, colorTable)
    if not fontString or not colorTable then return end
    if type(colorTable) ~= "table" or #colorTable < 3 then return end
    fontString:SetTextColor(colorTable[1] or 1, colorTable[2] or 1, colorTable[3] or 1, colorTable[4] or 1)
end

-- Hooks installed on tracker mixins fire inside Blizzard's update loop
-- (e.g. QuestObjectiveTracker line updates); an error raised there aborts
-- the rest of that loop and leaves objective lines stale. Styling must
-- therefore never run inline from those hooks — queue the frame and restyle
-- on the next frame, where a failure only costs us our own skinning.
-- <<< QUI_TEST_EXTRACT deferred_style_queue
local function CreateDeferredStyleQueue(handler)
    local pending = {}
    local scheduled = false
    return function(target)
        if not target then return end
        pending[target] = true
        if scheduled then return end
        scheduled = true
        C_Timer.After(0, function()
            scheduled = false
            local batch = pending
            pending = {}
            for frame in pairs(batch) do
                ns.SafeCall("best-effort-style", handler, frame)
            end
        end)
    end
end
-- <<< QUI_TEST_EXTRACT deferred_style_queue

local GetFontPath = Helpers.GetGeneralFont

local function CJKFont(fs, path, size, flags)
    if Helpers and Helpers.ApplyFontWithFallback then
        Helpers.ApplyFontWithFallback(fs, path, size, flags)
    else
        fs:SetFont(path, size, flags)
    end
end

local function IsWidgetPoolTracker(module)
    return module ~= nil
        and (module == _G.ScenarioObjectiveTracker or module == _G.UIWidgetObjectiveTracker)
end

local function IsWidgetPoolBlock(block)
    return block ~= nil and IsWidgetPoolTracker(block.parentModule)
end

local WIDGET_POOL_TRACKER_NAMES = {
    ScenarioObjectiveTracker = true,
    UIWidgetObjectiveTracker = true,
}

-- <<< QUI_TEST_EXTRACT line_icon_style
local function StyleLineIcon(line)
    local settings = GetSettings()
    if not settings or not settings.skinObjectiveTracker or not settings.objectiveTrackerCustomIcons then return end
    if not line or IsWidgetPoolBlock(line.parentBlock) then return end

    local icon = line.Icon
    if not icon or not icon.GetAtlas then return end
    if icon.IsShown then
        local shown = icon:IsShown()
        if issecretvalue and issecretvalue(shown) then return end -- @secret-policy: reject-secret-value (never touch an icon whose visibility is unreadable)
        if not shown then return end
    end

    -- Anim lines (quest objectives) only legitimately show their check while
    -- completing/completed; never touch the icon in any other state so we
    -- can't reveal a check that Blizzard is keeping invisible.
    local animState = _G.ObjectiveTrackerAnimLineState
    if line.state ~= nil and animState then
        if line.state ~= animState.Completed and line.state ~= animState.Completing then return end
    end

    local atlas = icon:GetAtlas()
    if Helpers.IsSecretValue(atlas) then return end
    if type(atlas) ~= "string" then return end
    local normalizedAtlas = SkinBase.GetFrameData(icon, "qLineIconAtlasNormalized")
    if SkinBase.GetFrameData(icon, "qLineIconAtlasSource") ~= atlas then
        normalizedAtlas = atlas:lower()
        SkinBase.SetFrameData(icon, "qLineIconAtlasSource", atlas)
        SkinBase.SetFrameData(icon, "qLineIconAtlasNormalized", normalizedAtlas)
    end
    atlas = normalizedAtlas

    local color
    if atlas:find("check", 1, true) then
        color = settings.objectiveTrackerCheckColor
    elseif atlas:find("nub", 1, true) then
        color = settings.objectiveTrackerBulletColor
    else
        -- e.g. ui-questtracker-objective-fail keeps its native look
        return
    end
    if type(color) ~= "table" then return end

    -- Preserve the icon's current vertex alpha: recolor visible icons, but
    -- never raise alpha on one that is being kept transparent.
    local alpha = color[4] or 1
    local _, _, _, curA = icon:GetVertexColor()
    curA = Helpers.SafeNumberOrNil(curA)
    if curA and curA < alpha then
        alpha = curA
    end
    if alpha <= 0 then return end

    if icon.SetDesaturated then icon:SetDesaturated(true) end
    icon:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, alpha)
end
-- <<< QUI_TEST_EXTRACT line_icon_style

local CUSTOM_BAR_FILL_TEXTURE = "Interface\\Buttons\\WHITE8x8"

local function StyleTrackerProgressBar(pb)
    local settings = GetSettings()
    if not settings or not settings.skinObjectiveTracker or not settings.objectiveTrackerCustomBars then return end

    local bar = pb and pb.Bar
    if not bar or not bar.GetStatusBarTexture then return end

    if not SkinBase.GetFrameData(bar, "qCustomBar") then
        SkinBase.SetFrameData(bar, "qCustomBar", true)

        -- Hide native bar art (frame/border overlays, glows, sheen, navy
        -- background) but keep the fill, the label and the reward icon+ring.
        local fill = bar:GetStatusBarTexture()
        for _, region in ipairs({ bar:GetRegions() }) do
            if region ~= fill and region ~= bar.Icon and region ~= bar.IconBG
                and region.IsObjectType and region:IsObjectType("Texture") then
                region:Hide()
                region:SetAlpha(0)
            end
        end

        bar:SetStatusBarTexture(CUSTOM_BAR_FILL_TEXTURE)

        local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()
        SkinBase.CreateBackdrop(bar, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end

    local color = settings.objectiveTrackerBarColor
    local r, g, b, a = 0.26, 0.42, 1, 1
    if type(color) == "table" then
        r, g, b, a = color[1] or r, color[2] or g, color[3] or b, color[4] or a
    end
    bar:SetStatusBarColor(r, g, b, a)
end

local function StyleLine(line, fontPath, textFontSize, textColor, skipHeight)
    if not line then return false end
    local heightChanged = false
    local targetFlags = GetFontFlags()
    if line.Text then
        local curFont, curSize, curFlags = line.Text:GetFont()
        local fontChanged = curFont ~= fontPath or curSize ~= textFontSize or curFlags ~= targetFlags
        if fontChanged then
            CJKFont(line.Text, fontPath, textFontSize, targetFlags)

            if not skipHeight then
                local textHeight = Helpers.SafeNumberOrNil(line.Text:GetStringHeight())
                if textHeight and textHeight > 0 then
                    local currentHeight = Helpers.SafeNumberOrNil(line:GetHeight())
                    local minHeight = textHeight + 4
                    if currentHeight and minHeight - currentHeight > 1 then
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
    StyleLineIcon(line)
    return heightChanged
end

local function RestyleBlockAfterHighlight(block)
    local s = GetSettings()
    if not s or not s.skinObjectiveTracker then return end
    if block.HeaderText then
        SafeSetTextColor(block.HeaderText, s.objectiveTrackerTitleColor)
    end
    if block.usedLines then
        for _, line in pairs(block.usedLines) do
            SafeSetTextColor(line.Text, s.objectiveTrackerTextColor)
            if line.Dash then
                SafeSetTextColor(line.Dash, s.objectiveTrackerTextColor)
            end
            StyleLineIcon(line)
        end
    end
end

local QueueBlockHighlightRestyle = CreateDeferredStyleQueue(RestyleBlockAfterHighlight)

local function EnsureBlockHighlightHook(block)
    if not block or IsWidgetPoolBlock(block) or SkinBase.GetFrameData(block, "highlightHooked") or not block.UpdateHighlight then return end
    SkinBase.SetFrameData(block, "highlightHooked", true)
    hooksecurefunc(block, "UpdateHighlight", QueueBlockHighlightRestyle)
end

local function StyleBlock(block, fontPath, titleFontSize, textFontSize, titleColor, textColor, skipHeight)
    if not block or IsWidgetPoolBlock(block) then return end

    EnsureBlockHighlightHook(block)

    if titleFontSize > 0 and block.HeaderText then
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

local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

local function StyleQuestPOIIcon(button)
    if not button or SkinBase.IsStyled(button) then return end

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

    if LCG and LCG.PixelGlow_Stop then
        LCG.PixelGlow_Stop(button, "_QUIQuestGlow")
    end

    SkinBase.MarkStyled(button)
end

local function ApplyBlockSkinning(tracker, block)
    if not block or IsWidgetPoolBlock(block) then return end
    local shown = block:IsShown()
    if issecretvalue and issecretvalue(shown) then return end -- @secret-policy: reject-secret-value (skip styling when visibility is unreadable)
    if not shown then return end

    local settings = GetSettings()
    if not settings or not settings.skinObjectiveTracker then return end

    local fontPath = GetFontPath()
    local titleFontSize = settings.objectiveTrackerTitleFontSize or 10
    local textFontSize = settings.objectiveTrackerTextFontSize or 10
    local titleColor = settings.objectiveTrackerTitleColor
    local textColor = settings.objectiveTrackerTextColor

    local itemButton = block.ItemButton or block.itemButton
    if itemButton then StyleQuestPOIIcon(itemButton) end

    StyleBlock(block, fontPath, titleFontSize, textFontSize, titleColor, textColor, true)
end

local trackerModules = {
    "ScenarioObjectiveTracker",
    "UIWidgetObjectiveTracker",
    "CampaignQuestObjectiveTracker",
    "QuestObjectiveTracker",
    "AdventureObjectiveTracker",
    "AchievementObjectiveTracker",
    "MonthlyActivitiesObjectiveTracker",
    "InitiativeTasksObjectiveTracker",
    "ProfessionsRecipeTracker",
    "BonusObjectiveTracker",
    "WorldQuestObjectiveTracker",
}

local function StyleExistingProgressBars()
    for _, trackerName in ipairs(trackerModules) do
        local tracker = not WIDGET_POOL_TRACKER_NAMES[trackerName] and _G[trackerName] or nil
        if tracker and tracker.usedProgressBars then
            for _, pb in pairs(tracker.usedProgressBars) do
                StyleTrackerProgressBar(pb)
            end
        end
    end
end

local function SkinTrackerHeader(header)
    if not header then return end

    if header.Background then
        header.Background:SetTexture(nil)
        header.Background:SetAlpha(0)
    end

    if header.Text then
        header.Text:ClearAllPoints()
        header.Text:SetPoint("LEFT", header, "LEFT", -7, 0)
        header.Text:SetJustifyH("LEFT")
    end
end

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

local function IsScenarioActive()
    if not C_ScenarioInfo or not C_ScenarioInfo.GetScenarioInfo then return false end
    local scenarioInfo = C_ScenarioInfo.GetScenarioInfo()
    return type(scenarioInfo) ~= "nil"
end

-- <<< QUI_TEST_EXTRACT tracker_max_width
local blizzardTrackerWidths = setmetatable({}, { __mode = "k" })

local function SetTrackerWidth(frame, width)
    if not frame or not width then return false end
    local currentWidth = frame.GetWidth and Helpers.SafeNumberOrNil(frame:GetWidth())
    if not currentWidth then return false end
    if currentWidth ~= width then
        frame:SetWidth(width)
    end
    return true
end

local function ApplyTrackedWidth(frame, width)
    if not frame then return true end
    if not blizzardTrackerWidths[frame] then
        blizzardTrackerWidths[frame] = frame.GetWidth and Helpers.SafeNumberOrNil(frame:GetWidth())
    end
    return SetTrackerWidth(frame, width or blizzardTrackerWidths[frame])
end

local function ApplyAllTrackerWidths(TrackerFrame, width)
    local complete = ApplyTrackedWidth(TrackerFrame, width)
    complete = ApplyTrackedWidth(TrackerFrame.Header, width) and complete
    for _, trackerName in ipairs(trackerModules) do
        local tracker = not WIDGET_POOL_TRACKER_NAMES[trackerName] and _G[trackerName] or nil
        if tracker then
            complete = ApplyTrackedWidth(tracker, width) and complete
            complete = ApplyTrackedWidth(tracker.Header, width) and complete
        end
    end
    return complete
end

local function RestoreBlizzardTrackerWidths()
    local TrackerFrame = _G.ObjectiveTrackerFrame
    if not TrackerFrame then return false end
    return ApplyAllTrackerWidths(TrackerFrame)
end

local function ApplyMaxWidth(settings)
    local TrackerFrame = _G.ObjectiveTrackerFrame
    if not TrackerFrame then return false end

    local maxWidth = settings and settings.objectiveTrackerWidth or 260
    ApplyAllTrackerWidths(TrackerFrame, maxWidth)
    return true
end
-- <<< QUI_TEST_EXTRACT tracker_max_width

local ScheduleBackdropUpdate

local function SkinMasterHeader(trackerFrame)
    local header = trackerFrame and trackerFrame.Header
    if not header then return end

    SkinTrackerHeader(header)

    local minBtn = header.MinimizeButton
    if minBtn then
        minBtn:ClearAllPoints()
        minBtn:SetPoint("RIGHT", header, "RIGHT", 0, 0)
        minBtn:SetSize(16, 16)
        if not SkinBase.GetFrameData(minBtn, "highlightSet") and minBtn:GetHighlightTexture() then
            minBtn:GetHighlightTexture():SetAtlas("ui-questtrackerbutton-yellow-highlight")
            SkinBase.SetFrameData(minBtn, "highlightSet", true)
        end
    end

    if header.SetCollapsed and not SkinBase.GetFrameData(header, "setCollapsedHooked") then
        hooksecurefunc(header, "SetCollapsed", function(self, collapsed)
            C_Timer.After(0, function()
                UpdateMinimizeButtonAtlas(self.MinimizeButton, collapsed)
                ScheduleBackdropUpdate()
            end)
        end)
        SkinBase.SetFrameData(header, "setCollapsedHooked", true)

        local isCollapsed = false
        if type(trackerFrame.IsCollapsed) == "function" then
            isCollapsed = trackerFrame:IsCollapsed()
        end
        UpdateMinimizeButtonAtlas(minBtn, isCollapsed)
    end
end

-- <<< QUI_TEST_EXTRACT tracker_max_height
local blizzardTrackerHeight = nil

local function CaptureBlizzardTrackerHeight(trackerFrame)
    if not trackerFrame or not trackerFrame.GetHeight then return end

    local height = Helpers.SafeNumberOrNil(trackerFrame:GetHeight())
    if height and height > 0 then
        blizzardTrackerHeight = height
    end
end

local function RestoreBlizzardTrackerHeight()
    local TrackerFrame = _G.ObjectiveTrackerFrame
    if not TrackerFrame then return false end

    if not blizzardTrackerHeight then
        CaptureBlizzardTrackerHeight(TrackerFrame)
    end
    if not blizzardTrackerHeight then return false end

    local currentHeight = Helpers.SafeNumberOrNil(TrackerFrame:GetHeight())
    if not currentHeight then return false end
    if currentHeight ~= blizzardTrackerHeight then
        TrackerFrame:SetHeight(blizzardTrackerHeight)
    end
    return true
end

local function ApplyTrackerMaxHeight(settings)
    local TrackerFrame = _G.ObjectiveTrackerFrame
    if not TrackerFrame then return false end

    if not blizzardTrackerHeight then
        CaptureBlizzardTrackerHeight(TrackerFrame)
    end
    if not blizzardTrackerHeight then return false end

    local maxHeight = settings and settings.objectiveTrackerHeight or 600
    local targetHeight = math.min(maxHeight, blizzardTrackerHeight)
    local currentHeight = Helpers.SafeNumberOrNil(TrackerFrame:GetHeight())
    if currentHeight ~= targetHeight then
        TrackerFrame:SetHeight(targetHeight)
    end
    return true
end
-- <<< QUI_TEST_EXTRACT tracker_max_height

local function UpdateBackdropAnchors()
    local TrackerFrame = _G.ObjectiveTrackerFrame
    local quiBackdrop = TrackerFrame and SkinBase.GetFrameData(TrackerFrame, "backdrop")
    if not TrackerFrame or not quiBackdrop then return end

    local settings = GetSettings()
    local maxHeight = settings and settings.objectiveTrackerHeight or 600

    local bottomModule = nil
    local lowestBottom = math.huge
    local sawUnreadable = false

    for _, trackerName in ipairs(trackerModules) do
        local tracker = not WIDGET_POOL_TRACKER_NAMES[trackerName] and _G[trackerName] or nil
        if tracker then
            local shown = tracker:IsShown()
            if issecretvalue and issecretvalue(shown) then -- @secret-policy: reject-secret-value (anchor scan holds current layout below)
                shown = nil
                sawUnreadable = true
            end
            if shown then
                local contentHeight = nil
                if tracker.GetContentsHeight then
                    contentHeight = Helpers.SafeNumberOrNil(tracker:GetContentsHeight())
                end
                local frameHeight = Helpers.SafeNumberOrNil(tracker:GetHeight())
                if frameHeight == nil then
                    sawUnreadable = true
                end

                local hasContent = contentHeight ~= nil and contentHeight > 0
                if not hasContent then
                    hasContent = frameHeight ~= nil and frameHeight > 1
                end

                if hasContent then
                    local bottom = Helpers.SafeNumberOrNil(tracker:GetBottom())
                    if bottom then
                        if bottom < lowestBottom then
                            lowestBottom = bottom
                            bottomModule = tracker
                        end
                    else
                        sawUnreadable = true
                    end
                end
            end
        end
    end

    if not bottomModule and sawUnreadable then return end

    quiBackdrop:ClearAllPoints()
    quiBackdrop:SetPoint("TOPLEFT", TrackerFrame, "TOPLEFT", -15, 0)
    quiBackdrop:SetPoint("TOPRIGHT", TrackerFrame, "TOPRIGHT", 10, 0)

    if bottomModule then
        local trackerTop = Helpers.SafeNumberOrNil(TrackerFrame:GetTop())
        local contentHeight = 0
        if trackerTop and lowestBottom and trackerTop > lowestBottom then
            contentHeight = trackerTop - lowestBottom + 15
        end

        if contentHeight > maxHeight then
            quiBackdrop:SetHeight(maxHeight)
        else
            quiBackdrop:SetPoint("BOTTOM", bottomModule, "BOTTOM", 0, -15)
        end
        quiBackdrop:Show()
    else
        quiBackdrop:Hide()
    end
end

local function HidePOIButtonGlows()
    for _, trackerName in ipairs(trackerModules) do
        local tracker = not WIDGET_POOL_TRACKER_NAMES[trackerName] and _G[trackerName] or nil
        if tracker and tracker.usedBlocks then
            for template, blocks in pairs(tracker.usedBlocks) do
                if type(blocks) == "table" then
                    for id, block in pairs(blocks) do
                        if block.poiButton and block.poiButton.Glow then
                            block.poiButton.Glow:Hide()
                            block.poiButton.Glow:SetAlpha(0)
                            if not SkinBase.GetFrameData(block.poiButton.Glow, "hooked") then
                                Helpers.DeferredHideOnShow(block.poiButton.Glow, { combatCheck = false })
                                SkinBase.SetFrameData(block.poiButton.Glow, "hooked", true)
                            end
                        end
                        if LCG and LCG.PixelGlow_Stop and block.poiButton then
                            LCG.PixelGlow_Stop(block.poiButton, "_QUIQuestGlow")
                        end
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

local RefreshTrackerContent
local scenarioDimensionsRestored = false

local function ApplyLayoutSettingsSafely(settings)
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        pendingProtectedLayoutUpdate = true
        return false
    end

    if IsScenarioActive() then
        if not scenarioDimensionsRestored then
            local heightRestored = RestoreBlizzardTrackerHeight()
            local widthsRestored = RestoreBlizzardTrackerWidths()
            scenarioDimensionsRestored = heightRestored and widthsRestored
        end
        return false
    end
    scenarioDimensionsRestored = false

    local heightApplied = ApplyTrackerMaxHeight(settings)
    local widthApplied = ApplyMaxWidth(settings)
    return heightApplied or widthApplied
end

local function EnforceSize()
    local settings = GetSettings()
    if not settings or not settings.skinObjectiveTracker then return end
    ApplyLayoutSettingsSafely(settings)
end

local function RunObjectiveTrackerPostLayoutUpdate()
    pendingBackdropUpdate = false
    EnforceSize()
    if ns.SyncManagedHolderSize then
        ns.SyncManagedHolderSize("objectiveTracker")
    end
    local inCombat = type(InCombatLockdown) == "function" and InCombatLockdown()
    if RefreshTrackerContent and not inCombat then
        RefreshTrackerContent()
    end
    UpdateBackdropAnchors()
    HidePOIButtonGlows()
    StyleExistingProgressBars()
end

local function DeferObjectiveTrackerPostLayoutUpdate()
    if pendingBackdropUpdate then return end
    pendingBackdropUpdate = true
    C_Timer.After(0, RunObjectiveTrackerPostLayoutUpdate)
end

ScheduleBackdropUpdate = function()
    DeferObjectiveTrackerPostLayoutUpdate()
end

local protectedLayoutEventFrame = CreateFrame("Frame")
protectedLayoutEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
protectedLayoutEventFrame:SetScript("OnEvent", function()
    if not pendingProtectedLayoutUpdate then return end
    pendingProtectedLayoutUpdate = false

    local settings = GetSettings()
    if not settings or not settings.skinObjectiveTracker then return end

    ApplyLayoutSettingsSafely(settings)
    ScheduleBackdropUpdate()
end)

local function SetupDebugInstrumentation()
    ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
    ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "ObjTracker_ProtectedLayout", frame = protectedLayoutEventFrame }
end
if ns.DebugRegister then
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation()
end

local function ResolveBackdropOpacity(bga)
    local manager = _G.ObjectiveTrackerManager
    if manager and manager.backgroundAlpha ~= nil then
        return manager.backgroundAlpha
    end
    return bga or 0.95
end

local function ApplyBackdropColors(backdrop, hideBorder, sr, sg, sb, sa, bgr, bgg, bgb, opacity)
    local borderColor = hideBorder and { 0, 0, 0, 0 } or { sr, sg, sb, sa }
    local bgColor = { bgr, bgg, bgb, opacity }
    SkinBase.ApplyPixelBackdrop(backdrop, hideBorder and 0 or 1, true, true, borderColor, bgColor, nil, nil, 1)
end

local function ApplyQUIBackdrop(trackerFrame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not trackerFrame then return end

    SkinBase.KillNineSlice(trackerFrame.NineSlice)

    local opacity = ResolveBackdropOpacity(bga)

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

    UpdateBackdropAnchors()
end

local function ApplyFontStyles(moduleFontSize, titleFontSize, textFontSize, moduleColor, titleColor, textColor)
    local fontPath = GetFontPath()

    for _, trackerName in ipairs(trackerModules) do
        local tracker = _G[trackerName]
        if tracker then
            if moduleFontSize > 0 and tracker.Header and tracker.Header.Text then
                local curFont, curSize, curFlags = tracker.Header.Text:GetFont()
                local targetFlags = GetFontFlags()
                if curFont ~= fontPath or curSize ~= moduleFontSize or curFlags ~= targetFlags then
                    CJKFont(tracker.Header.Text, fontPath, moduleFontSize, targetFlags)
                end
                SafeSetTextColor(tracker.Header.Text, moduleColor)
            end

            if tracker.usedBlocks and not WIDGET_POOL_TRACKER_NAMES[trackerName] then
                for template, blocks in pairs(tracker.usedBlocks) do
                    for blockID, block in pairs(blocks) do
                        StyleBlock(block, fontPath, titleFontSize, textFontSize, titleColor, textColor)
                    end
                end
            end
        end
    end

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

RefreshTrackerContent = function()
    local settings = GetSettings()
    if not settings or not settings.skinObjectiveTracker then return end

    ApplyFontStyles(
        settings.objectiveTrackerModuleFontSize or 12,
        settings.objectiveTrackerTitleFontSize or 10,
        settings.objectiveTrackerTextFontSize or 10,
        settings.objectiveTrackerModuleColor,
        settings.objectiveTrackerTitleColor,
        settings.objectiveTrackerTextColor
    )
end

local function SkinObjectiveTracker()
    local settings = GetSettings()
    if not settings or not settings.skinObjectiveTracker then return end

    local TrackerFrame = _G.ObjectiveTrackerFrame
    if not TrackerFrame then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()

    if TrackerFrame.UpdateHeight and not SkinBase.GetFrameData(TrackerFrame, "updateHeightHooked") then
        hooksecurefunc(TrackerFrame, "UpdateHeight", function(self)
            CaptureBlizzardTrackerHeight(self)
            DeferObjectiveTrackerPostLayoutUpdate()
        end)
        SkinBase.SetFrameData(TrackerFrame, "updateHeightHooked", true)
    end

    ApplyLayoutSettingsSafely(settings)

    ApplyQUIBackdrop(TrackerFrame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    RefreshTrackerContent()
    StyleExistingProgressBars()

    SkinMasterHeader(TrackerFrame)

    for _, trackerName in ipairs(trackerModules) do
        local tracker = _G[trackerName]
        if tracker then
            SkinTrackerHeader(tracker.Header)
        end
    end

    local DeferredScheduleBackdropUpdate = DeferObjectiveTrackerPostLayoutUpdate

    for _, trackerName in ipairs(trackerModules) do
        local tracker = not WIDGET_POOL_TRACKER_NAMES[trackerName] and _G[trackerName] or nil
        if tracker and not SkinBase.GetFrameData(tracker, "collapseHooked") then
            if tracker.Header and tracker.Header.MinimizeButton then
                tracker.Header.MinimizeButton:HookScript("OnClick", DeferredScheduleBackdropUpdate)
            end

            if tracker.SetCollapsed then
                hooksecurefunc(tracker, "SetCollapsed", DeferredScheduleBackdropUpdate)
            end

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

    local manager = _G.ObjectiveTrackerManager
    if manager and manager.SetOpacity and not SkinBase.GetFrameData(manager, "opacityHooked") then
        hooksecurefunc(manager, "SetOpacity", function(self, opacityPercent)
            C_Timer.After(0, function()
                local alpha = (opacityPercent or 0) / 100
                local _, _, _, _, currBgR, currBgG, currBgB = SkinBase.GetSkinColors()
                local bd = SkinBase.GetFrameData(TrackerFrame, "backdrop")
                if bd then
                    SkinBase.SetBackdropColors(bd, nil, { currBgR, currBgG, currBgB, alpha })
                end
            end)
        end)
        SkinBase.SetFrameData(manager, "opacityHooked", true)
    end

    C_Timer.After(0.5, HidePOIButtonGlows)

    if settings.objectiveTrackerClickThrough then
        TrackerFrame:EnableMouse(false)
    end

    SkinBase.MarkSkinned(TrackerFrame)
end

local function RefreshObjectiveTracker()
    local settings = GetSettings()
    if not settings or not settings.skinObjectiveTracker then return end

    local TrackerFrame = _G.ObjectiveTrackerFrame
    if not TrackerFrame then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()

    ApplyLayoutSettingsSafely(settings)

    local refreshBackdrop = SkinBase.GetFrameData(TrackerFrame, "backdrop")
    if refreshBackdrop then
        local hideBorder = settings.hideObjectiveTrackerBorder

        local opacity = ResolveBackdropOpacity(bga)

        ApplyBackdropColors(refreshBackdrop, hideBorder, sr, sg, sb, sa, bgr, bgg, bgb, opacity)
    end

    UpdateBackdropAnchors()
    RefreshTrackerContent()
    StyleExistingProgressBars()

    TrackerFrame:EnableMouse(not settings.objectiveTrackerClickThrough)
end

_G.QUI_RefreshObjectiveTracker = RefreshObjectiveTracker

if ns.Registry then
    ns.Registry:Register("skinObjectiveTracker", {
        refresh = _G.QUI_RefreshObjectiveTracker,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

local trackingEvents = {
    "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED_NEW_AREA",
    "CONTENT_TRACKING_UPDATE",
    "TRACKED_ACHIEVEMENT_UPDATE",
    "TRACKED_ACHIEVEMENT_LIST_CHANGED",
    "ACHIEVEMENT_EARNED",
    "SUPER_TRACKING_CHANGED",
    "TRANSMOG_COLLECTION_SOURCE_ADDED",
    "TRACKING_TARGET_INFO_UPDATE",
    "TRACKABLE_INFO_UPDATE",
    "HOUSE_DECOR_ADDED_TO_CHEST",
    "CRITERIA_COMPLETE",
    "QUEST_TURNED_IN",
    "QUEST_LOG_UPDATE",
    "QUEST_WATCH_LIST_CHANGED",
    "SCENARIO_BONUS_VISIBILITY_UPDATE",
    "SCENARIO_CRITERIA_UPDATE",
    "SCENARIO_UPDATE",
    "QUEST_ACCEPTED",
    "QUEST_REMOVED",
    "PERKS_ACTIVITY_COMPLETED",
    "PERKS_ACTIVITIES_TRACKED_UPDATED",
    "PERKS_ACTIVITIES_TRACKED_LIST_CHANGED",
    "INITIATIVE_TASKS_TRACKED_UPDATED",
    "INITIATIVE_TASKS_TRACKED_LIST_CHANGED",
    "NEIGHBORHOOD_INITIATIVE_UPDATED",
    "CURRENCY_DISPLAY_UPDATE",
    "TRACKED_RECIPE_UPDATE",
    "BAG_UPDATE_DELAYED",
    "QUEST_AUTOCOMPLETE",
    "QUEST_POI_UPDATE",
    "SCENARIO_SPELL_UPDATE",
    "SCENARIO_COMPLETED",
    "SCENARIO_CRITERIA_SHOW_STATE_UPDATE",
}

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(self, event)
    if event == "SUPER_TRACKING_CHANGED" then
        C_Timer.After(0.01, HidePOIButtonGlows)
    end
    ScheduleBackdropUpdate()
end)

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(function()
        RunAfterFirstFrame(function()
            SkinObjectiveTracker()
            for _, trackEvent in ipairs(trackingEvents) do
                frame:RegisterEvent(trackEvent)
            end
        end, 0.2)
    end)
end
