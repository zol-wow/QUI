local addonName, ns = ...

if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
local SkinBase = ns.SkinBase
local GetCore = ns.Helpers.GetCore
local MAP_CANVAS_FRAME_LEVEL = 100
local MAP_OVERLAY_FRAME_LEVEL = 200

local function IsSettingEnabled(key)
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings[key]
end

local function RaiseFrame(frame, frameLevel)
    if not frame then return end
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(frameLevel)
end

local function RaiseMapCanvas(frame)
    if not frame then return end

    RaiseFrame(frame.ScrollContainer, MAP_CANVAS_FRAME_LEVEL)

    if frame.overlayFrames then
        for _, overlayFrame in ipairs(frame.overlayFrames) do
            RaiseFrame(overlayFrame, MAP_OVERLAY_FRAME_LEVEL)
        end
    end

    RaiseFrame(frame.NavBar, MAP_OVERLAY_FRAME_LEVEL)
end

local function ApplyBorderBackdrop(backdrop)
    if not backdrop then return end
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetWindowColors()
    SkinBase.ApplyChromeBackdrop(backdrop, { radius = 8, withBackground = true, borderColor = { sr, sg, sb, sa }, bgColor = { bgr, bgg, bgb, bga } })
end

local function HideArt(region)
    if region then SkinBase.ClampTextureHidden(region) end
end

local function RoundSurface(owner, radius, inset, depth)
    if not owner or not owner.CreateTexture then return end
    local backdrop = SkinBase.GetBackdrop(owner)
    if not backdrop then
        local sr, sg, sb, sa, r, g, b, a = SkinBase.GetWindowColors()
        SkinBase.CreateBackdrop(owner, sr, sg, sb, sa, r, g, b, a)
        backdrop = SkinBase.GetBackdrop(owner)
    end
    if not backdrop then return end
    backdrop.ignoreInLayout = true
    if inset then
        backdrop:ClearAllPoints()
        backdrop:SetPoint("TOPLEFT", owner, "TOPLEFT", inset, -inset)
        backdrop:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", -inset, inset)
    end
    local sr, sg, sb, sa, r, g, b, a = SkinBase.GetWindowColors()
    if depth then r, g, b, a = SkinBase.GetDepthColor(depth) end
    SkinBase.ApplyChromeBackdrop(backdrop, {
        radius = radius or 5,
        withBackground = true,
        borderColor = { sr, sg, sb, sa * 0.6 },
        bgColor = { r, g, b, a },
    })
end

local function SkinControl(button)
    if not button then return end
    SkinBase.SkinButton(button, { font = true, strip = true, disabledTextColor = { 0.7, 0.7, 0.7, 1 } })
    RoundSurface(button, 5, 1, "ROW")
end

local function SkinIconControl(button, glyph)
    if not button then return end
    SkinBase.SkinButton(button, { font = false })
    RoundSurface(button, 5, 1, "ROW")
    if glyph and not SkinBase.GetFrameData(button, "mapGlyph") then
        local text = button:CreateFontString(nil, "OVERLAY")
        text:SetPoint("CENTER")
        SkinBase.SkinFontString(text, { size = 14, color = { 0.9, 0.9, 0.9, 1 } })
        text:SetText(glyph)
        SkinBase.SetFrameData(button, "mapGlyph", text)
    end
end

local function StyleNavButton(button)
    if not button then return end
    SkinControl(button)
    RoundSurface(button, 5, 2, "ROW")
    HideArt(button.arrowUp)
    HideArt(button.arrowDown)
    HideArt(button.selected)
    if button.MenuArrowButton then
        SkinBase.SkinDropdown(button.MenuArrowButton, { skinArrow = true, font = false })
        HideArt(button.MenuArrowButton.Art)
        local backdrop = SkinBase.GetBackdrop(button.MenuArrowButton)
        if backdrop then backdrop:Hide() end
    end
end

local function StyleNavigation(frame)
    local nav = frame and frame.NavBar
    if not nav or not nav.CreateTexture then return end
    if not SkinBase.GetFrameData(nav, "mapNavigationStyled") then
        SkinBase.StripTextures(nav)
        if nav.overlay then SkinBase.StripTextures(nav.overlay) end
        SkinBase.SetFrameData(nav, "mapNavigationStyled", true)
    end
    local previous = nav.overflowButton and nav.overflowButton:IsShown() and nav.overflowButton or nil
    if nav.overflowButton then nav.overflowButton.xoffset = 0 end
    for _, button in ipairs(nav.navList or {}) do
        button.xoffset = 0
        if button:IsShown() then
            if previous then
                button:ClearAllPoints()
                button:SetPoint("LEFT", previous, "RIGHT", 0, 0)
            end
            previous = button
        end
        if button == nav.homeButton and (not button.text or button.text:GetText() == "") then
            SkinIconControl(button, "<")
            HideArt(button.arrowUp)
            HideArt(button.arrowDown)
        else
            local glyph = SkinBase.GetFrameData(button, "mapGlyph")
            if glyph then glyph:Hide() end
            StyleNavButton(button)
        end
    end
    SkinIconControl(nav.overflowButton, "...")
end

local function StyleQuestHeader(frame)
    if not frame then return end
    SkinBase.ClampTextureHidden(frame.Background, frame.NextObjective and frame.Progress and true or false)
    for _, key in ipairs({ "TopFiligree", "Divider", "SelectedHighlight", "HighlightTexture" }) do
        HideArt(frame[key])
    end
    if frame.GetNormalTexture then HideArt(frame:GetNormalTexture()) end
    if frame.GetHighlightTexture then HideArt(frame:GetHighlightTexture()) end
    RoundSurface(frame, 5, 1, "ROW")
    SkinBase.ApplyButtonFontObjects(frame)
    SkinBase.SkinFontString(frame.Text, { size = 12, color = { 0.92, 0.92, 0.92, 1 } })
    SkinBase.SkinFontString(frame.Progress, { size = 11, fontOnly = true })
    if frame.NextObjective then
        local objective = frame.NextObjective
        if type(frame.UpdateNextObjective) == "function" and not SkinBase.GetFrameData(frame, "mapCampaignObjectiveHook") then
            SkinBase.SetFrameData(frame, "mapCampaignObjectiveHook", true)
            hooksecurefunc(frame, "UpdateNextObjective", StyleQuestHeader)
        end
        SkinBase.SkinFontString(objective.Text, { size = 11, fontOnly = true })
        local padding = SkinBase.GetFrameData(frame, "mapCampaignHeightPadding")
        if padding == nil then
            padding = frame.heightPadding or 0
            SkinBase.SetFrameData(frame, "mapCampaignHeightPadding", padding)
        end
        frame.heightPadding = padding
        if objective:IsShown() and objective.Text and objective.Text:GetText() ~= "" then
            frame.heightPadding = padding + 12
            if type(objective.Layout) == "function" then objective:Layout() end
            if type(frame.Layout) == "function" then frame:Layout() end
        end
    end
end

local function EachActive(pool, fn)
    if pool and pool.EnumerateActive then
        for frame in pool:EnumerateActive() do fn(frame) end
    end
end

local function StyleQuestRows()
    local sf = _G.QuestScrollFrame
    if not sf then return end
    for _, key in ipairs({ "headerFramePool", "campaignHeaderFramePool", "campaignHeaderMinimalFramePool", "covenantCallingsHeaderFramePool" }) do
        EachActive(sf[key], StyleQuestHeader)
    end
    EachActive(sf.titleFramePool, function(row)
        SkinBase.SkinFontString(row.Text, { size = 12, fontOnly = true })
        SkinBase.SkinFontString(row.ButtonText, { size = 12, fontOnly = true })
    end)
    EachActive(sf.objectiveFramePool, function(row)
        SkinBase.SkinFontString(row.Text, { size = 11, fontOnly = true })
        SkinBase.SkinFontString(row.Dash, { size = 11, fontOnly = true })
    end)
    if sf.Contents then
        if sf.Contents.StoryHeader then StyleQuestHeader(sf.Contents.StoryHeader) end
        if sf.Contents.Separator then HideArt(sf.Contents.Separator.Divider) end
    end
end

local function StyleQuestBorder(frame)
    if not frame then return end
    HideArt(frame.Border)
    HideArt(frame.TopDetail)
    HideArt(frame.Shadow)
end

local function CanStyleMapControl(control)
    local map = _G.WorldMapFrame
    if not IsSettingEnabled("skinWorldMap") or not map or not control then return false end
    local owner = control
    while owner do
        if owner.IsForbidden and owner:IsForbidden() then return false end
        if owner == map then return true end
        owner = owner.GetParent and owner:GetParent()
    end
    return false
end

local function StyleQuestTab(tab)
    if not CanStyleMapControl(tab) then return end
    HideArt(tab.Background)
    HideArt(tab.HighlightTexture)
    HideArt(tab.TabGlow)
    if tab.SelectedTexture then tab.SelectedTexture:SetAlpha(0) end
    local selected = tab.SelectedTexture and tab.SelectedTexture:IsShown()
    local sr, sg, sb, sa, r, g, b = SkinBase.GetWindowColors()
    RoundSurface(tab, 6, 0)
    SkinBase.SetBackdropColors(SkinBase.GetBackdrop(tab), { sr, sg, sb, sa * 0.6 }, { r, g, b, 1 })
    local join = SkinBase.GetFrameData(tab, "mapTabJoin")
    if not join then
        join = CreateFrame("Frame", nil, tab)
        join:SetPoint("TOPLEFT", tab, "TOPLEFT", -4, -1)
        join:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", -4, 1)
        join:SetWidth(10)
        join.Fill = join:CreateTexture(nil, "BACKGROUND")
        join.Fill:SetAllPoints()
        join.Edge = tab:CreateTexture(nil, "OVERLAY")
        join.Edge:SetPoint("TOPRIGHT", tab, "TOPRIGHT", 0, -5)
        join.Edge:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 5)
        join.Edge:SetWidth(1 / tab:GetEffectiveScale())
        SkinBase.SetFrameData(tab, "mapTabJoin", join)
    end
    join.Fill:SetColorTexture(r, g, b, 1)
    local ar, ag, ab = SkinBase.GetSkinColors()
    join.Edge:SetColorTexture(ar, ag, ab, 1)
    join.Edge:SetShown(selected and true or false)
    if not SkinBase.GetFrameData(tab, "mapTabHooked") then
        tab:HookScript("OnEnter", function(owner) StyleQuestTab(owner) end)
        tab:HookScript("OnLeave", function(owner) StyleQuestTab(owner) end)
        if type(tab.SetChecked) == "function" then
            hooksecurefunc(tab, "SetChecked", function(owner) StyleQuestTab(owner) end)
        end
        SkinBase.SetFrameData(tab, "mapTabHooked", true)
    end
end

local function StyleEventRow(row)
    if not CanStyleMapControl(row) then return end
    HideArt(row.Background)
    HideArt(row.Background2)
    HideArt(row.Highlight)
    if row.Background then RoundSurface(row, 5, 1, "ROW") end
    local data = row.GetElementData and row:GetElementData()
    if data and type(data.GetData) == "function" then data = data:GetData() end
    if data and data.date and row.Background then
        row:SetFrameLevel(row:GetParent():GetFrameLevel() + 3)
        local backdrop = SkinBase.GetBackdrop(row)
        backdrop:SetFrameLevel(row:GetFrameLevel() - 1)
        local r, g, b = SkinBase.GetDepthColor("ROW")
        SkinBase.SetBackdropColors(backdrop, nil, { r, g, b, 1 })
    end
    SkinBase.SkinFontString(row.Label, { size = 12, fontOnly = true })
    SkinBase.SkinFontString(row.Name, { size = 12, fontOnly = true })
    SkinBase.SkinFontString(row.Location, { size = 11, fontOnly = true })
end

local function StyleExtraPanes(quest)
    local events = quest.EventsFrame
    if events then
        SkinBase.StripTextures(events)
        StyleQuestBorder(events.BorderFrame)
        SkinBase.SkinFontString(events.TitleText, { size = 13 })
        SkinIconControl(events.SettingsDropdown)
        SkinBase.SkinTrimScrollBar(events.ScrollBar)
        local scroll = events.ScrollBox
        if scroll then
            HideArt(scroll.Background)
            RoundSurface(scroll, 6, 1)
            if not SkinBase.GetFrameData(scroll, "mapEventRowsHooked") then
                SkinBase.HookScrollBoxAcquired(scroll, StyleEventRow, { sync = true })
                SkinBase.SetFrameData(scroll, "mapEventRowsHooked", true)
            end
            SkinBase.ForEachScrollBoxFrame(scroll, StyleEventRow)
        end
    end
    local legend = quest.MapLegend
    if legend then
        StyleQuestBorder(legend.BorderFrame)
        SkinBase.SkinFontString(legend.TitleText, { size = 13 })
        local scroll = legend.ScrollFrame
        if scroll then
            HideArt(scroll.Background)
            RoundSurface(scroll, 6, 1)
            SkinBase.SkinTrimScrollBar(scroll.ScrollBar)
            if scroll.ScrollChild then
                SkinBase.SkinFrameText(scroll.ScrollChild, { recurse = true, fontOnly = true })
            end
        end
    end
end

local function StyleRewardRow(row)
    if not row then return end
    HideArt(row.NameFrame)
    RoundSurface(row, 4, 0, "ROW")
    SkinBase.SkinFontString(row.Name, { size = 11, fontOnly = true })
end

local detailTextColors = setmetatable({}, { __mode = "k" })

local function CaptureDetailTextColor(text)
    local current = { text:GetTextColor() }
    local state = detailTextColors[text]
    if not state or current[1] ~= state.applied[1] or current[2] ~= state.applied[2] or current[3] ~= state.applied[3] then
        state = { original = current, applied = current }
        detailTextColors[text] = state
    end
    return state
end

local function StyleOwnedDetailText(text, opts)
    local state = CaptureDetailTextColor(text)
    SkinBase.SkinFontString(text, opts)
    state.applied = { text:GetTextColor() }
end

local function RestoreDetailText()
    for text, state in pairs(detailTextColors) do
        local r, g, b = text:GetTextColor()
        if r == state.applied[1] and g == state.applied[2] and b == state.applied[3] then
            text:SetTextColor(unpack(state.original))
        end
        detailTextColors[text] = nil
    end
end

local function StyleDetailText(details)
    local contents = details.ScrollFrame and details.ScrollFrame.Contents
    if not contents then return end
    for _, key in ipairs({
        "QuestInfoTitleHeader", "QuestInfoDescriptionHeader", "QuestInfoObjectivesHeader",
        "QuestInfoDescriptionText", "QuestInfoObjectivesText", "QuestInfoGroupSize",
        "QuestInfoRewardText", "QuestInfoTimerText", "QuestInfoQuestType",
    }) do
        local text = _G[key]
        if text and text:GetParent() == contents then
            StyleOwnedDetailText(text, { size = key:find("Header") and 14 or 12, color = { 0.9, 0.9, 0.9, 1 } })
        end
    end
    local objectives = _G.QuestInfoObjectivesFrame
    if objectives and objectives:GetParent() == contents then
        for _, text in ipairs(objectives.Objectives or {}) do
            local original = CaptureDetailTextColor(text).original
            local r, g, b = unpack(original)
            local cr, cg, cb = 0.2, 0.2, 0.2
            if _G.QUEST_OBJECTIVE_COMPLETED_FONT_COLOR then
                cr, cg, cb = _G.QUEST_OBJECTIVE_COMPLETED_FONT_COLOR:GetRGB()
            end
            local color = { 0.9, 0.9, 0.9, 1 }
            if r == cr and g == cg and b == cb then
                color = { 0.65, 0.65, 0.65, 1 }
                if _G.QUEST_OBJECTIVE_COMPLETED_FONT_COLOR_DARK_BACKGROUND then
                    color = { _G.QUEST_OBJECTIVE_COMPLETED_FONT_COLOR_DARK_BACKGROUND:GetRGB() }
                    color[4] = 1
                end
            end
            StyleOwnedDetailText(text, { color = color })
        end
    end
    if not SkinBase.GetFrameData(details, "mapDetailTextHooked") then
        details:HookScript("OnHide", RestoreDetailText)
        SkinBase.SetFrameData(details, "mapDetailTextHooked", true)
    end
end

local function StyleQuestPane(frame)
    local quest = frame and frame.QuestLog
    if not quest then return end
    StyleExtraPanes(quest)
    HideArt(quest.VerticalSeparator)
    for _, key in ipairs({ "QuestsTab", "EventsTab", "MapLegendTab" }) do StyleQuestTab(quest[key]) end
    local previous
    for _, key in ipairs({ "QuestsTab", "EventsTab", "MapLegendTab" }) do
        local tab = quest[key]
        if tab and tab:IsShown() then
            tab:ClearAllPoints()
            if previous then
                tab:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, 0)
            else
                tab:SetPoint("TOPLEFT", quest, "TOPRIGHT", -1, -28)
            end
            previous = tab
        end
    end
    local list = quest.QuestsFrame
    local scroll = list and list.ScrollFrame
    if scroll then
        HideArt(scroll.Background)
        HideArt(scroll.Edge)
        StyleQuestBorder(scroll.BorderFrame)
        RoundSurface(scroll, 6, 1)
        SkinBase.SetBackdropColors(SkinBase.GetBackdrop(scroll), { 0, 0, 0, 0 })
        if scroll.SearchBox then
            SkinBase.SkinEditBox(scroll.SearchBox)
            RoundSurface(scroll.SearchBox, 5, 0, "ROW")
        end
        SkinIconControl(scroll.SettingsDropdown)
        SkinBase.SkinTrimScrollBar(scroll.ScrollBar)
    end
    local details = quest.DetailsFrame or (list and list.DetailsFrame)
    if details then
        StyleQuestBorder(details.BorderFrame)
        HideArt(details.Bg)
        HideArt(details.SealMaterialBG)
        RoundSurface(details, 6, 1)
        if details.BackFrame then
            SkinBase.StripTextures(details.BackFrame)
            SkinControl(details.BackFrame.BackButton)
        end
        StyleDetailText(details)
        for _, key in ipairs({ "AbandonButton", "ShareButton", "TrackButton" }) do SkinControl(details[key]) end
        if details.ScrollFrame then SkinBase.SkinTrimScrollBar(details.ScrollFrame.ScrollBar) end
        local rewards = details.RewardsFrameContainer and details.RewardsFrameContainer.RewardsFrame
        if rewards then
            HideArt(rewards.Top)
            HideArt(rewards.Bottom)
            HideArt(rewards.Background)
            RoundSurface(rewards, 6, 0)
            SkinBase.SkinFontString(rewards.Label, { size = 14, color = { 0.92, 0.92, 0.92, 1 } })
        end
    end
    local rewards = _G.MapQuestInfoRewardsFrame
    if rewards then
        for _, key in ipairs({ "ItemChooseText", "ItemReceiveText", "PlayerTitleText", "QuestSessionBonusReward" }) do
            SkinBase.SkinFontString(rewards[key], { size = 11 })
        end
        for _, key in ipairs({ "XPFrame", "HonorFrame", "ArtifactXPFrame", "WarModeBonusFrame", "MoneyFrame", "SkillPointFrame", "TitleFrame" }) do
            StyleRewardRow(rewards[key])
        end
        for _, row in ipairs(rewards.RewardButtons or {}) do StyleRewardRow(row) end
        for _, key in ipairs({ "spellRewardPool", "followerRewardPool", "reputationRewardPool" }) do
            EachActive(rewards[key], StyleRewardRow)
        end
    end
    StyleQuestRows()
end

local function StyleActivityControl(overlay)
    overlay:SetSize(176, 36)
    overlay:ClearAllPoints()
    overlay:SetPoint("BOTTOMLEFT", overlay:GetParent():GetCanvasContainer(), "BOTTOMLEFT", 12, 32)
    RoundSurface(overlay, 6, 0, "ROW")
    local r, g, b = SkinBase.GetDepthColor("ROW")
    SkinBase.SetBackdropColors(SkinBase.GetBackdrop(overlay), nil, { r, g, b, 1 })
    overlay.Icon:ClearAllPoints()
    overlay.Icon:SetPoint("LEFT", overlay, "LEFT", 8, 0)
    overlay.Icon:SetSize(24, 24)
    local label = SkinBase.GetFrameData(overlay, "mapActivityLabel")
    if not label then
        label = overlay:CreateFontString(nil, "OVERLAY")
        label:SetJustifyH("LEFT")
        SkinBase.SetFrameData(overlay, "mapActivityLabel", label)
    end
    label:ClearAllPoints()
    label:SetPoint("LEFT", overlay, "LEFT", overlay.selectedBounty and 38 or 12, 0)
    label:SetPoint("RIGHT", overlay, "RIGHT", -38, 0)
    local faction = overlay.selectedBounty and C_Reputation and C_Reputation.GetFactionDataByID
        and C_Reputation.GetFactionDataByID(overlay.selectedBounty.factionID)
    SkinBase.SkinFontString(label, { size = 12, color = { 0.9, 0.9, 0.9, 1 } })
    label:SetText(faction and faction.name or _G.FACTION or "Faction")
    local dropdown = overlay.BountyDropdown
    SkinBase.StripTextures(dropdown)
    SkinIconControl(dropdown, ">")
    dropdown:SetSize(28, 28)
    dropdown:ClearAllPoints()
    dropdown:SetPoint("RIGHT", overlay, "RIGHT", -4, 0)
    if not SkinBase.GetFrameData(overlay, "mapActivityHooked") then
        for _, name in ipairs({ "Refresh", "SetSelectedBounty" }) do
            if type(overlay[name]) == "function" then hooksecurefunc(overlay, name, StyleActivityControl) end
        end
        SkinBase.SetFrameData(overlay, "mapActivityHooked", true)
    end
end

local function StyleBountyBoard(board)
    if not board or not board.bountyTabPool then return end
    SkinBase.ClampTextureHidden(board.TrackerBackground, true)
    SkinBase.ClampTextureHidden(board.DesaturatedTrackerBackground, true)
    RoundSurface(board, 6, 12, "ROW")
    local backdrop = SkinBase.GetBackdrop(board)
    if backdrop then
        backdrop:ClearAllPoints()
        backdrop:SetPoint("TOPLEFT", board, "TOPLEFT", 12, -3)
        backdrop:SetPoint("BOTTOMRIGHT", board, "BOTTOMRIGHT", -12, 4)
        backdrop:SetFrameLevel(math.max(0, board:GetFrameLevel() - 1))
    end
    SkinBase.SkinFontString(board.BountyName, { color = { 0.9, 0.9, 0.9, 1 } })
    for tab in board.bountyTabPool:EnumerateActive() do
        SkinBase.SkinButton(tab, { font = false })
        local selected = not tab.isEmpty and tab.bountyIndex == board:GetSelectedBountyIndex()
        local bd = SkinBase.GetBackdrop(tab)
        bd:ClearAllPoints()
        bd:SetSize(32, 32)
        bd:SetPoint("CENTER", tab, "CENTER", 0, 1)
        local r, g, b, a = SkinBase.GetWindowColors()
        if selected then r, g, b, a = SkinBase.GetSkinColors() end
        SkinBase.SetFrameData(tab, "windowColor", { r, g, b, a })
        bd:SetBackdropBorderColor(r, g, b, a)
    end
    if not SkinBase.GetFrameData(board, "mapBountyBoardHooked") then
        for _, method in ipairs({ "Refresh", "RefreshBountyTabs", "SetSelectedBountyIndex" }) do
            if type(board[method]) == "function" then hooksecurefunc(board, method, StyleBountyBoard) end
        end
        SkinBase.SetFrameData(board, "mapBountyBoardHooked", true)
    end
end

local function StyleMapControls(frame)
    StyleNavigation(frame)
    StyleQuestPane(frame)
    local border = frame.BorderFrame
    if border then
        local title = border.TitleText or (border.TitleContainer and border.TitleContainer.TitleText)
        SkinBase.SkinFontString(title, { size = 13, color = { 0.92, 0.92, 0.92, 1 } })
        if border.Tutorial then
            SkinBase.StripTextures(border.Tutorial)
            SkinIconControl(border.Tutorial, "?")
            local backdrop = SkinBase.GetBackdrop(border.Tutorial)
            if backdrop then
                backdrop:ClearAllPoints()
                backdrop:SetSize(22, 22)
                backdrop:SetPoint("CENTER", border.Tutorial, "CENTER")
            end
        end
        local sizing = border.MaximizeMinimizeFrame
        if sizing then
            SkinIconControl(sizing.MaximizeButton, "+")
            SkinIconControl(sizing.MinimizeButton, "-")
        end
    end
    for _, overlay in ipairs(frame.overlayFrames or {}) do
        StyleBountyBoard(overlay)
        if overlay.Eye and overlay.ModelSceneBottom and overlay.ModelSceneTop then
            SkinBase.ClampTextureHidden(overlay.Background, true)
        end
        if type(overlay.RefreshMenu) == "function" and type(overlay.ShouldShowTrackingIconOnFloor) == "function" then
            SkinBase.SkinDropdown(overlay, { skinArrow = true })
            RoundSurface(overlay, 5, 1, "ROW")
        end
        if overlay.Icon and (overlay.Border or overlay.IconBorder) then
            for _, region in ipairs({ overlay:GetRegions() }) do
                if region ~= overlay.Icon and region.IsObjectType and region:IsObjectType("Texture") then HideArt(region) end
            end
            HideArt(overlay.Border)
            HideArt(overlay.IconBorder)
            HideArt(overlay.Background)
            HideArt(overlay.ActiveTexture)
            HideArt(overlay.FilterCounterBanner)
            if overlay.FilterCounter then
                HideArt(overlay.Icon)
                SkinIconControl(overlay)
                if not SkinBase.GetFrameData(overlay, "mapFilterIcon") then
                    local icon = CreateFrame("Frame", nil, overlay)
                    icon:SetSize(12, 12)
                    icon:SetPoint("CENTER", overlay, "CENTER")
                    for i, width in ipairs({ 12, 8, 4 }) do
                        local line = icon:CreateTexture(nil, "ARTWORK")
                        line:SetColorTexture(0.9, 0.9, 0.9, 1)
                        line:SetSize(width, 2)
                        line:SetPoint("TOP", icon, "TOP", 0, -(i - 1) * 4)
                    end
                    SkinBase.SetFrameData(overlay, "mapFilterIcon", icon)
                end
                RoundSurface(overlay.FilterCounter, 4, 1, "ROW")
                SkinBase.SkinFontString(overlay.FilterCounter.Count, { size = 11 })
            end
            if overlay.ResetButton then SkinIconControl(overlay.ResetButton, "x") end
            if overlay.GetHighlightTexture then HideArt(overlay:GetHighlightTexture()) end
            if overlay.BountyDropdown then
                StyleActivityControl(overlay)
            else
                RoundSurface(overlay, 6, 2, "ROW")
            end
        end
        if overlay.OpenButton and overlay.CloseButton then
            SkinIconControl(overlay.OpenButton, "<")
            SkinIconControl(overlay.CloseButton, ">")
        end
    end
end

local function HookMapControls(frame)
    if SkinBase.GetFrameData(frame, "mapControlsHooked") then return end
    local function Refresh()
        if SkinBase.IsSkinned(frame) then StyleMapControls(frame) end
    end
    for _, name in ipairs({ "Minimize", "Maximize" }) do
        if type(frame[name]) == "function" then
            hooksecurefunc(frame, name, function()
                if frame.BorderFrame then
                    SkinBase.HidePortraitFrameChrome(frame.BorderFrame)
                    ApplyBorderBackdrop(SkinBase.GetBackdrop(frame.BorderFrame))
                end
                Refresh()
            end)
        end
    end
    for _, name in ipairs({ "NavBar_AddButton", "NavBar_CheckLength" }) do
        if type(_G[name]) == "function" then
            hooksecurefunc(name, function(nav)
                if nav == frame.NavBar then StyleNavigation(frame) end
            end)
        end
    end
    for _, name in ipairs({ "QuestLogQuests_Update", "QuestMapFrame_ShowQuestDetails", "QuestMapFrame_UpdateQuestDetailsButtons" }) do
        if type(_G[name]) == "function" then hooksecurefunc(name, Refresh) end
    end
    if type(_G.QuestInfo_Display) == "function" then
        hooksecurefunc("QuestInfo_Display", function()
            Refresh()
        end)
    end
    if frame.QuestLog and type(frame.QuestLog.SetDisplayMode) == "function" then
        hooksecurefunc(frame.QuestLog, "SetDisplayMode", Refresh)
    end
    if frame.QuestLog and type(frame.QuestLog.ValidateTabs) == "function" then
        hooksecurefunc(frame.QuestLog, "ValidateTabs", Refresh)
    end
    if frame.HookScript then frame:HookScript("OnShow", Refresh) end
    SkinBase.SetFrameData(frame, "mapControlsHooked", true)
end

local function SkinWorldMap()
    if not IsSettingEnabled("skinWorldMap") then return end
    local frame = _G.WorldMapFrame
    if not frame or SkinBase.IsSkinned(frame) then return end

    if frame.BorderFrame then
        SkinBase.SkinButtonFrameTemplate(frame.BorderFrame)
        ApplyBorderBackdrop(SkinBase.GetBackdrop(frame.BorderFrame))
        if frame.BorderFrame.Underlay then frame.BorderFrame.Underlay:Hide() end
        if frame.BorderFrame.InsetBorderTop then frame.BorderFrame.InsetBorderTop:Hide() end
    end

    RaiseMapCanvas(frame)

    SkinBase.MarkSkinned(frame)
    StyleMapControls(frame)
    HookMapControls(frame)
end

local function RefreshWorldMap()
    local frame = _G.WorldMapFrame
    if not frame or not SkinBase.IsSkinned(frame) then return end
    if frame.BorderFrame then
        ApplyBorderBackdrop(SkinBase.GetBackdrop(frame.BorderFrame))
    end
    RaiseMapCanvas(frame)
    StyleMapControls(frame)
end

_G.QUI_RefreshWorldMapColors = RefreshWorldMap
if ns.Registry then
    ns.Registry:Register("skinWorldMap", {
        refresh = RefreshWorldMap,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

SkinBase.OnAddOnLoaded("Blizzard_WorldMap", SkinWorldMap, 0)

local function StyleFlightMapTitle(frame)
    if not IsSettingEnabled("skinFlightMap") or (frame.IsForbidden and frame:IsForbidden()) then return end
    local border = frame.BorderFrame
    if not border or (border.IsForbidden and border:IsForbidden()) then return end
    local container = border.TitleContainer
    if container and container.IsForbidden and container:IsForbidden() then return end
    local title = border.TitleText or (container and container.TitleText)
    local opts = { size = 13, color = { 0.92, 0.92, 0.92, 1 } }
    SkinBase.SkinFontString(title, opts)
    SkinBase.LockFontObject(title, opts)
end

local function SkinFlightMap()
    if not IsSettingEnabled("skinFlightMap") then return end
    local frame = _G.FlightMapFrame
    if not frame or (frame.IsForbidden and frame:IsForbidden()) or SkinBase.IsSkinned(frame) then return end

    if frame.BorderFrame then
        SkinBase.SkinButtonFrameTemplate(frame.BorderFrame)
        ApplyBorderBackdrop(SkinBase.GetBackdrop(frame.BorderFrame))
        if frame.BorderFrame.Underlay then frame.BorderFrame.Underlay:Hide() end
        if frame.BorderFrame.InsetBorderTop then frame.BorderFrame.InsetBorderTop:Hide() end
    end

    StyleFlightMapTitle(frame)
    RaiseMapCanvas(frame)

    SkinBase.MarkSkinned(frame)
end

local function RefreshFlightMap()
    if _G.TaxiFrame and SkinBase.IsSkinned(_G.TaxiFrame) then
        SkinBase.RefreshFrameBackdropColors(_G.TaxiFrame)
    end
    local frame = _G.FlightMapFrame
    if not frame or not SkinBase.IsSkinned(frame) then return end
    if frame.BorderFrame then
        ApplyBorderBackdrop(SkinBase.GetBackdrop(frame.BorderFrame))
    end
    StyleFlightMapTitle(frame)
    RaiseMapCanvas(frame)
end
if ns.Registry then
    ns.Registry:Register("skinFlightMap", {
        refresh = RefreshFlightMap,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

SkinBase.OnAddOnLoaded("Blizzard_FlightMap", SkinFlightMap, 0)

SkinBase.OnAddOnLoaded("Blizzard_UIPanels_Game", function()
    if not IsSettingEnabled("skinFlightMap") then return end
    local frame = _G.TaxiFrame
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinWindow(frame)
    SkinBase.MarkSkinned(frame)
end, 0)
