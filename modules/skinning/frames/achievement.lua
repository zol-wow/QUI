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

local function HookAchievementLists()
    for _, host in ipairs({ "AchievementFrameCategories", "AchievementFrameAchievements", "AchievementFrameStats" }) do
        local listFrame = _G[host]
        local scrollBox = listFrame and listFrame.ScrollBox
        if scrollBox then
            SkinBase.HookScrollBoxRowFonts(scrollBox, 3)
        end
    end
end

local achievementListColorHooked
local function RecolorAchievementRow(row)
    if row and row.Description then
        row.Description:SetTextColor(0.95, 0.95, 0.95, 1)
    end
end

local function HookAchievementListColors()
    local listFrame = _G.AchievementFrameAchievements
    local scrollBox = listFrame and listFrame.ScrollBox
    ns.SafeCallMethodIfPresent("best-effort-style", scrollBox, "ForEachFrame", RecolorAchievementRow)

    if achievementListColorHooked then return end
    local mixin = _G.AchievementTemplateMixin
    if type(mixin) ~= "table" or type(mixin.Saturate) ~= "function" then return end
    hooksecurefunc(mixin, "Saturate", function(self)
        if not IsSettingEnabled("skinAchievement") then return end
        RecolorAchievementRow(self)
    end)
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
    local summary = _G.AchievementFrameSummaryAchievements
    if not summary or not summary.buttons then return end
    for _, button in ipairs(summary.buttons) do
        RecolorSummaryDescription(button)
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
    SkinBase.SkinTabGroup(SkinBase.CollectNumberedTabs("AchievementFrame", 3), _G.AchievementFrame, { font = true })
end

local function SkinAchievement()
    if not IsSettingEnabled("skinAchievement") then return end
    local frame = _G.AchievementFrame
    if not frame or SkinBase.IsSkinned(frame) then return end

    HideAchievementChrome()
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()
    SkinBase.CreateBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    local closeButton = frame.CloseButton or _G.AchievementFrameCloseButton
    if closeButton then
        SkinBase.SkinCloseButton(closeButton)
    end

    SkinAchievementBottomTabs()
    HookAchievementLists()
    HookAchievementListColors()
    HookAchievementObjectiveColors()
    HookSummaryAchievementColors()
    HookAchievementSummaryText()
    HookAchievementComparisonText()
    SkinBase.MarkSkinned(frame)
end

local function RefreshAchievement()
    local frame = _G.AchievementFrame
    if not frame then return end
    if SkinBase.IsSkinned(frame) then
        SkinAchievementBottomTabs()
        HookAchievementLists()
        HookAchievementListColors()
        HookAchievementObjectiveColors()
        HookSummaryAchievementColors()
        HookAchievementSummaryText()
        HookAchievementComparisonText()
    end
    local bd = SkinBase.GetBackdrop(frame)
    if not bd then return end
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()
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
