local addonName, ns = ...

if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end

local SkinBase = ns.SkinBase
local GetCore = ns.Helpers.GetCore

local function IsSettingEnabled(key)
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings[key]
end

local function HideAchievementChrome()
    local frame = _G.AchievementFrame
    if not frame then return end

    SkinBase.StripTextures(frame)
    local header = frame.Header
    if header then
        for _, key in ipairs({ "Left", "Right", "PointBorder", "RightDDLInset" }) do
            SkinBase.ClampTextureHidden(header[key], true)
        end
        SkinBase.SkinFontString(header.Title, { color = { 1, 1, 1, 1 } })
        SkinBase.SkinFontString(header.Points, { fontOnly = true })
    end
    if frame.Background then frame.Background:Hide() end
    if frame.BackgroundBlackCover then frame.BackgroundBlackCover:Hide() end

    local globals = {
        "AchievementFrameMetalBorderLeft", "AchievementFrameMetalBorderRight",
        "AchievementFrameMetalBorderTop",  "AchievementFrameMetalBorderBottom",
        "AchievementFrameCategoriesBG",    "AchievementFrameWaterMark",
        "AchievementFrameGuildEmblemLeft", "AchievementFrameGuildEmblemRight",
    }
    for _, name in ipairs(globals) do
        local tex = _G[name]
        if tex and tex.Hide then tex:Hide() end
    end

    ns.SafeCallMethodIfPresent("best-effort-style", frame, "SetBackdrop", nil)
end

local function StyleAchievementSurface(frame, depth)
    if not frame then return end
    SkinBase.StripTextures(frame)
    SkinBase.KillNineSlice(frame.NineSlice, true)
    if frame.SetBackdrop then frame:SetBackdrop(nil) end
    if frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do
            if not child:GetName() then
                SkinBase.KillNineSlice(child.NineSlice, true)
                if child.GetBackdrop and child:GetBackdrop() then child:SetBackdrop(nil) end
            end
        end
    end
    local sr, sg, sb, sa = SkinBase.GetWindowColors()
    local r, g, b, a = SkinBase.GetDepthColor(depth or "ROW")
    SkinBase.CreateBackdrop(frame, sr, sg, sb, sa * 0.5, r, g, b, a, 5)
end

local function StyleAchievementExpansion(row)
    local texture = row and row.PlusMinus
    if not texture then return end
    texture:SetDesaturated(true)
    texture:SetVertexColor(1, 1, 1, 1)
end

local function StyleAchievementRow(row)
    if not row then return end
    for _, key in ipairs({ "Background", "BottomLeftTsunami", "BottomRightTsunami", "TopLeftTsunami",
        "TopRightTsunami", "BottomTsunami1", "TopTsunami1", "TitleBar", "Glow", "RewardBackground", "GuildCornerL", "GuildCornerR" }) do
        SkinBase.ClampTextureHidden(row[key])
    end
    SkinBase.KillNineSlice(row.NineSlice, true)
    if row.SetBackdrop then row:SetBackdrop(nil) end
    if row.Highlight then SkinBase.StripTextures(row.Highlight) end
    local sr, sg, sb, sa = SkinBase.GetWindowColors()
    local r, g, b, a = SkinBase.GetDepthColor("ROW")
    local selected = type(row.IsSelected) == "function" and row:IsSelected()
    SkinBase.CreateBackdrop(row, sr, sg, sb, selected and sa or sa * 0.5, r, g, b, a, 5)
    SkinBase.SkinFontString(row.Label, { size = 12, color = { 1, 1, 1, 1 } })
    SkinBase.SkinFontString(row.Description, { size = 11, color = { 0.9, 0.9, 0.9, 1 } })
    SkinBase.SkinFontString(row.Reward, { size = 11, fontOnly = true })
    StyleAchievementExpansion(row)
    if row.Icon then
        SkinBase.ClampTextureHidden(row.Icon.frame)
        SkinBase.ClampTextureHidden(row.Icon.bling)
        SkinBase.RoundIconTexture(row.Icon, row.Icon.texture)
    end
    if row.Shield then
        SkinBase.ClampTextureHidden(row.Shield.Icon)
        local shield = row.Shield
        SkinBase.SkinFontString(shield.Points, { size = 12, fontOnly = true })
        SkinBase.SkinFontString(shield.DateCompleted, { size = 10, fontOnly = true })
    end
end

local function StyleAchievementStatistic(row)
    if not row then return end
    for _, key in ipairs({ "Background", "Left", "Middle", "Right" }) do
        SkinBase.ClampTextureHidden(row[key], true)
    end
    local sr, sg, sb, sa = SkinBase.GetWindowColors()
    local r, g, b, a = SkinBase.GetDepthColor(row.isHeader and "SUBPANEL" or "ROW")
    SkinBase.CreateBackdrop(row, sr, sg, sb, sa * 0.5, r, g, b, a, 4)
    SkinBase.SkinFontString(row.Title, { size = 12, color = { 1, 1, 1, 1 } })
    SkinBase.SkinFontString(row.Text or (row.GetFontString and row:GetFontString()), { size = 11, color = { 0.9, 0.9, 0.9, 1 } })
    SkinBase.SkinFontString(row.Value, { size = 11, color = { 1, 1, 1, 1 } })
end

local function StyleAchievementCategory(row)
    local button = row and row.Button
    if not button then return end
    local data = row.GetElementData and row:GetElementData()
    if data then SkinBase.SetFrameData(button, "achievementSelected", data.selected) end
    SkinBase.SkinCategoryButton(button, {
        isSelected = function(owner) return SkinBase.GetFrameData(owner, "achievementSelected") or false end,
    })
    SkinBase.RefreshWidget(button)
    if not SkinBase.GetFrameData(row, "achievementSelectionHook") and type(row.UpdateSelectionState) == "function" then
        SkinBase.SetFrameData(row, "achievementSelectionHook", true)
        hooksecurefunc(row, "UpdateSelectionState", function(_, selected)
            SkinBase.SetFrameData(button, "achievementSelected", selected)
            SkinBase.RefreshCategorySelected(button)
        end)
    end
end

local function StyleAchievementProgress(bar)
    if not bar then return end
    local name = bar:GetName()
    if name then
        for _, suffix in ipairs({ "Left", "Right", "Middle", "FillBar", "BorderLeft", "BorderRight", "BorderCenter", "BG" }) do
            SkinBase.ClampTextureHidden(_G[name .. suffix])
        end
    end
    SkinBase.SkinStatusBar(bar)
    SkinBase.ApplyChromeBackdrop(SkinBase.GetBackdrop(bar), { radius = 4, withBackground = true })
    local fill = bar:GetStatusBarTexture()
    if fill then SkinBase.RoundBarTexture(bar, fill) end
    SkinBase.SkinFontString(name and _G[name .. "Title"], { size = 11, color = { 0.9, 0.9, 0.9, 1 } })
    SkinBase.SkinFontString(bar.Label, { size = 11, color = { 0.9, 0.9, 0.9, 1 } })
    SkinBase.SkinFontString(bar.Text, { size = 11, color = { 1, 1, 1, 1 } })
end

local function StyleSummaryEmptyText()
    local empty = _G.AchievementFrameSummaryAchievementsEmptyText
    local header = _G.AchievementFrameSummaryAchievementsHeader
    if not empty or not header then return end
    empty:ClearAllPoints()
    empty:SetPoint("CENTER", header, "CENTER", 0, 0)
    SkinBase.SkinFontString(empty, { size = 11, color = { 0.85, 0.85, 0.85, 1 } })
    empty:SetDrawLayer("OVERLAY")
    local title = _G.AchievementFrameSummaryAchievementsHeaderTitle
    if title then title:SetShown(not empty:IsShown()) end
end

local function StyleAchievementContents()
    local frame = _G.AchievementFrame
    if not frame or not IsSettingEnabled("skinAchievement") then return end
    for _, name in ipairs({ "AchievementFrameCategories", "AchievementFrameSummary", "AchievementFrameAchievements", "AchievementFrameStats" }) do
        local panel = _G[name]
        StyleAchievementSurface(panel, "SUBPANEL")
        if panel then SkinBase.SkinTrimScrollBar(panel.ScrollBar) end
    end
    SkinBase.StripTextures(_G.AchievementFrameStatsBG)
    local header = frame.HeaderDetails
    if header then
        SkinBase.ClampTextureHidden(header.TopTileStreaks)
        SkinBase.SkinButton(header.Back, { strip = true })
        local filters = header.Filters
        if filters then
            SkinBase.SkinEditBox(filters.SearchBox)
            SkinBase.SkinDropdown(filters.FilterDropdown, { skinArrow = true })
            if filters.FilterDropdown then
                SkinBase.SkinFontString(filters.FilterDropdown.Text, { color = { 0.95, 0.95, 0.95, 1 } })
            end
        end
    end
    for _, name in ipairs({ "AchievementFrameSummaryAchievementsHeader", "AchievementFrameSummaryCategoriesHeader" }) do
        local summaryHeader = _G[name]
        SkinBase.StripTextures(summaryHeader)
        if summaryHeader and summaryHeader.GetRegions then
            for _, region in ipairs({ summaryHeader:GetRegions() }) do
                if region:GetObjectType() == "FontString" then
                    SkinBase.SkinFontString(region, { color = { 1, 1, 1, 1 } })
                end
            end
        end
    end
    StyleSummaryEmptyText()
    local summary = _G.AchievementFrameSummaryAchievements
    for _, row in ipairs(summary and summary.buttons or {}) do StyleAchievementRow(row) end
    StyleAchievementProgress(_G.AchievementFrameSummaryCategoriesStatusBar)
    for i = 1, 12 do StyleAchievementProgress(_G["AchievementFrameSummaryCategoriesCategory" .. i]) end
end

local achievementStatHooked
local function HookAchievementLists()
    local mixin = _G.AchievementStatTemplateMixin
    if not achievementStatHooked and mixin and type(mixin.Init) == "function" then
        hooksecurefunc(mixin, "Init", function(row)
            if IsSettingEnabled("skinAchievement") then StyleAchievementStatistic(row) end
        end)
        achievementStatHooked = true
    end
    for _, host in ipairs({ "AchievementFrameCategories", "AchievementFrameAchievements", "AchievementFrameStats" }) do
        local listFrame = _G[host]
        local scrollBox = listFrame and listFrame.ScrollBox
        if scrollBox then
            local styler = host == "AchievementFrameCategories" and StyleAchievementCategory or host == "AchievementFrameStats" and StyleAchievementStatistic or StyleAchievementRow
            if not SkinBase.GetFrameData(scrollBox, "qAchievementRowsHooked") then
                SkinBase.HookScrollBoxRowFonts(scrollBox, 3)
                SkinBase.HookScrollBoxAcquired(scrollBox, styler)
                SkinBase.SetFrameData(scrollBox, "qAchievementRowsHooked", true)
            end
            SkinBase.ForEachScrollBoxFrame(scrollBox, styler)
        end
    end
end

local achievementListColorHooked
local function RecolorAchievementRow(row)
    StyleAchievementRow(row)
    if row and row.Description then
        row.Description:SetTextColor(0.95, 0.95, 0.95, 1)
    end
end

local function HookAchievementListColors()
    local listFrame = _G.AchievementFrameAchievements
    local scrollBox = listFrame and listFrame.ScrollBox
    SkinBase.ForEachScrollBoxFrame(scrollBox, RecolorAchievementRow)

    if achievementListColorHooked then return end
    local mixin = _G.AchievementTemplateMixin
    if type(mixin) ~= "table" or type(mixin.Saturate) ~= "function" then return end
    for _, method in ipairs({ "Saturate", "Desaturate", "Init" }) do
        if type(mixin[method]) == "function" then
            hooksecurefunc(mixin, method, function(self)
                if not IsSettingEnabled("skinAchievement") then return end
                RecolorAchievementRow(self)
            end)
        end
    end
    if type(mixin.UpdatePlusMinusTexture) == "function" then
        hooksecurefunc(mixin, "UpdatePlusMinusTexture", function(row)
            if IsSettingEnabled("skinAchievement") then StyleAchievementExpansion(row) end
        end)
    end
    achievementListColorHooked = true
end

local achievementObjectiveColorHooked
local function RelightDarkObjectiveText(fs)
    if not fs or not fs.GetTextColor then return end
    local r, g, b = fs:GetTextColor()
    if type(r) == "number" and (r + g + b) < 0.3 then
        fs:SetTextColor(0.95, 0.95, 0.95, 1)
        if fs.SetShadowOffset then fs:SetShadowOffset(1, -1) end
    end
end

local function RefaceObjectiveText(fs)
    if not fs then return end
    SkinBase.SkinFontString(fs, { fontOnly = true })
    SkinBase.LockFontObject(fs, { fontOnly = true })
end

local function RecolorObjectivesFrame(objectivesFrame)
    if not objectivesFrame then return end
    if objectivesFrame.criterias then
        for _, criteria in ipairs(objectivesFrame.criterias) do
            RelightDarkObjectiveText(criteria and criteria.Name)
            RefaceObjectiveText(criteria and criteria.Name)
        end
    end
    if objectivesFrame.metas then
        for _, meta in ipairs(objectivesFrame.metas) do
            RelightDarkObjectiveText(meta and meta.Label)
            RefaceObjectiveText(meta and meta.Label)
        end
    end
end

local function HookAchievementObjectiveColors()
    if achievementObjectiveColorHooked then return end
    local hooked = false
    for _, fn in ipairs({ "AchievementObjectives_DisplayCriteria",
                          "AchievementObjectives_DisplayProgressiveAchievement" }) do
        if type(_G[fn]) == "function" then
            hooksecurefunc(fn, function(objectivesFrame)
                if not IsSettingEnabled("skinAchievement") then return end
                RecolorObjectivesFrame(objectivesFrame)
            end)
            hooked = true
        end
    end
    if hooked then achievementObjectiveColorHooked = true end
end

local achievementSummaryColorHooked
local function RecolorSummaryDescription(button)
    if button and button.isSummary and button.Description then
        button.Description:SetTextColor(0.95, 0.95, 0.95, 1)
    end
end

local function LockAchievementSummaryText()
    StyleSummaryEmptyText()
    local summary = _G.AchievementFrameSummaryAchievements
    if not summary or not summary.buttons then return end
    for _, button in ipairs(summary.buttons) do
        RecolorSummaryDescription(button)
        StyleAchievementRow(button)
    end
end

local function LockAchievementComparisonText()
    local statScrollBox = _G.AchievementFrameComparison and _G.AchievementFrameComparison.StatContainer and _G.AchievementFrameComparison.StatContainer.ScrollBox
    if statScrollBox then
        SkinBase.HookScrollBoxRowFonts(statScrollBox, 3)
    end
    local achScrollBox = _G.AchievementFrameComparison and _G.AchievementFrameComparison.AchievementContainer and _G.AchievementFrameComparison.AchievementContainer.ScrollBox
    if achScrollBox then
        SkinBase.HookScrollBoxRowFonts(achScrollBox, 3)
    end
end

local function HookSummaryAchievementColors()
    if achievementSummaryColorHooked then return end
    if type(_G.AchievementComparisonPlayerButton_Saturate) ~= "function" then return end
    hooksecurefunc("AchievementComparisonPlayerButton_Saturate", function(self)
        if not IsSettingEnabled("skinAchievement") then return end
        RecolorSummaryDescription(self)
    end)
    achievementSummaryColorHooked = true
    local summary = _G.AchievementFrameSummaryAchievements
    if summary and summary.buttons then
        for _, button in ipairs(summary.buttons) do
            RecolorSummaryDescription(button)
        end
    end
end

local achievementSummaryTextHooked
local function HookAchievementSummaryText()
    if not achievementSummaryTextHooked and type(_G.AchievementFrameSummary_UpdateAchievements) == "function" then
        hooksecurefunc("AchievementFrameSummary_UpdateAchievements", function()
            if not IsSettingEnabled("skinAchievement") then return end
            LockAchievementSummaryText()
        end)
        achievementSummaryTextHooked = true
    end
    LockAchievementSummaryText()
end

local achievementComparisonTextHooked
local function HookAchievementComparisonText()
    LockAchievementComparisonText()
    if not achievementComparisonTextHooked and type(_G.AchievementFrameComparison_UpdateStatsDataProvider) == "function" then
        hooksecurefunc("AchievementFrameComparison_UpdateStatsDataProvider", function()
            if not IsSettingEnabled("skinAchievement") then return end
            LockAchievementComparisonText()
        end)
        achievementComparisonTextHooked = true
    end
end

local function SkinAchievementBottomTabs()
    local tabs = SkinBase.CollectNumberedTabs("AchievementFrame", 3)
    SkinBase.SkinTabGroup(tabs, _G.AchievementFrame, { font = true, uniform = true, minWidth = 140, height = 28, dockBottom = true })
    for _, tab in ipairs(tabs) do
        local text = tab.Text or (tab.GetFontString and tab:GetFontString())
        if text then
            text:ClearAllPoints()
            text:SetPoint("LEFT", tab, "LEFT", 10, 0)
            text:SetPoint("RIGHT", tab, "RIGHT", -10, 0)
            text:SetWidth(0)
            text:SetJustifyH("CENTER")
        end
    end
end

local function SkinAchievement()
    if not IsSettingEnabled("skinAchievement") then return end
    local frame = _G.AchievementFrame
    if not frame or SkinBase.IsSkinned(frame) then return end

    HideAchievementChrome()
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetWindowColors()
    SkinBase.CreateBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga, 8)
    local backdrop = SkinBase.GetBackdrop(frame)
    if backdrop and frame.Header then
        backdrop:ClearAllPoints()
        backdrop:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 56)
        backdrop:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    end

    local closeButton = frame.CloseButton or _G.AchievementFrameCloseButton
    if closeButton then
        SkinBase.SkinCloseButton(closeButton)
    end

    SkinAchievementBottomTabs()
    StyleAchievementContents()
    HookAchievementLists()
    HookAchievementListColors()
    HookAchievementObjectiveColors()
    HookSummaryAchievementColors()
    HookAchievementSummaryText()
    HookAchievementComparisonText()
    frame:HookScript("OnShow", function()
        SkinAchievementBottomTabs()
        StyleAchievementContents()
    end)
    local stats = _G.AchievementFrameStats
    if stats and stats.HookScript then
        stats:HookScript("OnShow", function()
            StyleAchievementContents()
            HookAchievementLists()
        end)
    end
    for _, name in ipairs({ "AchievementFrameSummary_Update", "AchievementFrameSummary_UpdateSummaryProgressBars" }) do
        if type(_G[name]) == "function" then hooksecurefunc(name, StyleAchievementContents) end
    end
    SkinBase.MarkSkinned(frame)
end

local function RefreshAchievement()
    local frame = _G.AchievementFrame
    if not frame then return end
    if SkinBase.IsSkinned(frame) then
        SkinAchievementBottomTabs()
        StyleAchievementContents()
        HookAchievementLists()
        HookAchievementListColors()
        HookAchievementObjectiveColors()
        HookSummaryAchievementColors()
        HookAchievementSummaryText()
        HookAchievementComparisonText()
    end
    local bd = SkinBase.GetBackdrop(frame)
    if not bd then return end
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetWindowColors()
    SkinBase.SetBackdropColors(bd, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
end

_G.QUI_RefreshAchievementColors = RefreshAchievement
if ns.Registry then
    ns.Registry:Register("skinAchievement", {
        refresh = RefreshAchievement,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

SkinBase.OnAddOnLoaded("Blizzard_AchievementUI", SkinAchievement, 0)
