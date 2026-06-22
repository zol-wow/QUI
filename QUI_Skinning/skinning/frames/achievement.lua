---------------------------------------------------------------------------
-- ACHIEVEMENT FRAME SKINNING
--
-- AchievementFrame doesn't use PortraitFrameTemplate / ButtonFrameTemplate
-- (per Blizzard_AchievementUI/Mainline/Blizzard_AchievementUI.xml:1505 —
-- inherits BackdropTemplate with the global BACKDROP_ACHIEVEMENTS_0_64
-- KeyValue). Its chrome is bespoke achievement-themed artwork:
--   - .Background              (UI-Achievement-AchievementBackground)
--   - .BackgroundBlackCover    (dark cover overlay)
--   - AchievementFrameMetalBorder{Left,Right,Top,Bottom}  ($parent-prefixed globals)
--   - AchievementFrameCategoriesBG  (parchment for the left category column)
--   - AchievementFrameWaterMark     (watermark dragon)
--   - AchievementFrameGuildEmblem{Left,Right}  (hidden by default)
-- Close button is the named global AchievementFrameCloseButton (Mainline).
---------------------------------------------------------------------------

local addonName, ns = ...
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

    -- $parent-named globals (Texture without parentKey, accessed via _G).
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

    -- The Blizzard backdrop also draws a BackdropTemplate frame border — remove it
    -- entirely (SkinAchievement gives AchievementFrame its own CreateBackdrop child)
    -- so it doesn't peek through the QUI backdrop. pcall-guarded; SetBackdrop(nil)
    -- reads no width/height, so no secret-value/combat throw.
    if frame.SetBackdrop then
        pcall(frame.SetBackdrop, frame, nil)
    end
end

-- Category / achievement / stat rows are ScrollBox-pooled and Blizzard swaps
-- their font OBJECT on hover / selection / re-bind, so the one-shot
-- SkinFrameText reverts. HookScrollBoxRowFonts locks each pooled row's
-- fontstrings ONCE (guarded per row) — re-walking the recursive font pass on
-- every acquire is the open-window hitch; the LockFontObject hooks it installs
-- re-assert the QUI face on every later revert.
local function HookAchievementLists()
    for _, host in ipairs({ "AchievementFrameCategories", "AchievementFrameAchievements", "AchievementFrameStats" }) do
        local listFrame = _G[host]
        local scrollBox = listFrame and listFrame.ScrollBox
        if scrollBox then
            SkinBase.HookScrollBoxRowFonts(scrollBox, 3)
        end
    end
end

-- Blizzard's AchievementTemplateMixin:Saturate (Blizzard_AchievementUI.lua,
-- earned/completed main-list rows) hardcodes the row Description to BLACK
-- (0,0,0) — meant for the light parchment, but unreadable on the QUI theme.
-- Desaturate (unearned) already uses white, so only the earned path needs the
-- fix. Re-assert a readable light color after each Saturate, and recolor any
-- rows already earned before the hook installed (runtime skin-enable). Gated on
-- skinAchievement; hooksecurefunc is permanent -> guard once.
local achievementListColorHooked
local function RecolorAchievementRow(row)
    if row and row.Description then
        row.Description:SetTextColor(0.95, 0.95, 0.95, 1)
    end
end

local function HookAchievementListColors()
    local listFrame = _G.AchievementFrameAchievements
    local scrollBox = listFrame and listFrame.ScrollBox
    if scrollBox and scrollBox.ForEachFrame then
        pcall(scrollBox.ForEachFrame, scrollBox, RecolorAchievementRow)
    end

    if achievementListColorHooked then return end
    local mixin = _G.AchievementTemplateMixin
    if type(mixin) ~= "table" or type(mixin.Saturate) ~= "function" then return end
    hooksecurefunc(mixin, "Saturate", function(self)
        if not IsSettingEnabled("skinAchievement") then return end
        RecolorAchievementRow(self)
    end)
    achievementListColorHooked = true
end

-- Expanding a COMPLETED achievement renders its criteria/objective rows into a
-- pooled objectivesFrame. Blizzard hardcodes those to BLACK when both the
-- achievement and the criterion are completed: AchievementObjectives_DisplayCriteria
-- sets criteria.Name:SetTextColor(0,0,0) and metaCriteria.Label:SetTextColor(0,0,0)
-- (Blizzard_AchievementUI.lua), meant for the light parchment -> black-on-dark on
-- the QUI theme. Other states (in-progress green 0,1,0 / locked grey .6) read
-- fine, so only re-light the near-black rows. Post-hook the two display funcs and
-- sweep the objectivesFrame's criteria/meta pools after Blizzard colors them.
local achievementObjectiveColorHooked
local function RelightDarkObjectiveText(fs)
    if not fs or not fs.GetTextColor then return end
    local r, g, b = fs:GetTextColor()
    if type(r) == "number" and (r + g + b) < 0.3 then
        fs:SetTextColor(0.95, 0.95, 0.95, 1)
        if fs.SetShadowOffset then fs:SetShadowOffset(1, -1) end
    end
end

-- The criteria/meta rows are framepool-acquired on expand (after the one-shot
-- recurse) and never under a hooked ScrollBox, so their stock font face is never
-- replaced. Apply the QUI font here too (lock so it survives later SetFontObject).
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

-- Blizzard hardcodes the achievement Description to BLACK (0,0,0) in its
-- saturate paths (Blizzard_AchievementUI.lua AchievementComparisonPlayerButton_
-- Saturate :2998) because it expects the light parchment row background. The
-- Summary tab's "Latest Unlocked Achievements" rows are earned -> saturated, so
-- their description goes black; on QUI's dark theme that reads as black-on-black.
-- Post-hook the summary saturate and re-assert a readable light color (matches
-- Blizzard's own Desaturate white variant). Scoped to summary rows (isSummary)
-- so the main achievement list -- which keeps a visible parchment -- is left
-- with Blizzard's intended colors. Gated on skinAchievement so disabling the
-- skin restores stock behavior. hooksecurefunc is permanent -> guard once.
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
        -- Font lock runs once per pooled button (AchievementFrameSummary_Update-
        -- Achievements re-fires this every summary refresh; re-walking the
        -- recurse pass each time is wasted). The LockFrameTextObjects hooks keep
        -- the face; only the color must re-assert each refresh.
        if not SkinBase.GetFrameData(button, "qListRowFonted") then
            SkinBase.SkinFrameText(button, { recurse = true })
            SkinBase.LockFrameTextObjects(button, 3)
            SkinBase.SetFrameData(button, "qListRowFonted", true)
        end
        RecolorSummaryDescription(button)
    end
end

local function LockAchievementComparisonText()
    local statScrollBox = _G.AchievementFrameComparison and _G.AchievementFrameComparison.StatContainer and _G.AchievementFrameComparison.StatContainer.ScrollBox
    if statScrollBox then
        -- Guarded per-row font lock (runs the recursive pass once); no manual
        -- ForEachFrame sweep — HookScrollBoxRowFonts already does the initial pass.
        SkinBase.HookScrollBoxRowFonts(statScrollBox, 3)
    end
    -- The comparison ACHIEVEMENT list (left side) is a separate pooled ScrollBox
    -- whose rows (AchievementComparisonTemplate) only SetText/Saturate — never
    -- SetFontObject — so lazily-acquired rows keep the stock template font face.
    -- Hook it too so every cold-acquired comparison row gets the QUI font.
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
    -- Recolor any rows already saturated before the hook existed (summary open
    -- when the skin is enabled at runtime).
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

-- Bottom tabs (Achievements / Guild / Statistics) — AchievementFrameTab1..3,
-- PanelTemplates tabs. Route through the canonical SkinBase.SkinTabGroup so they
-- match EVERY other frame's tabs (QUI backdrop box + selected/unselected tint +
-- durable font across hover/select), instead of the former font-only treatment
-- that left the stock parchment tab art and made these the lone divergent tab
-- strip. SkinTabGroup is idempotent, so re-calling on refresh is cheap.
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

    -- Mainline AchievementFrame's close button is the named global
    -- AchievementFrameCloseButton (XML name="$parentCloseButton",
    -- Blizzard_AchievementUI/Mainline:2309). There is no AchievementFrameHeader
    -- global (that was Cata) and AchievementFrame.Header (parentKey, :1660) has no
    -- CloseButton child, so the old _G.AchievementFrameHeader.CloseButton lookup
    -- was always nil-guarded dead and the close X was never skinned.
    local closeButton = frame.CloseButton or _G.AchievementFrameCloseButton
    if closeButton then
        SkinBase.SkinCloseButton(closeButton)
    end

    SkinBase.SkinFrameText(frame, { recurse = true })
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

-- delay 0 = skin synchronously inside the ADDON_LOADED handler, BEFORE the
-- frame's first paint, so the window doesn't flash Blizzard FRIZQT before the
-- QUI font lands.
SkinBase.OnAddOnLoaded("Blizzard_AchievementUI", SkinAchievement, 0)
