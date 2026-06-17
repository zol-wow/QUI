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
-- Close button lives at AchievementFrameHeader.CloseButton.
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

    -- The Blizzard backdrop also draws a BackdropTemplate frame border —
    -- zero its colors so it doesn't peek through the QUI backdrop.
    if frame.SetBackdrop then
        pcall(frame.SetBackdrop, frame, nil)
    end
end

-- Category / achievement / stat rows are ScrollBox-pooled and Blizzard swaps
-- their font OBJECT on hover / selection / re-bind, so the one-shot
-- SkinFrameText above reverts. Lock each acquired row's fontstrings (and the
-- initial pass) so the QUI font survives. Idempotent (HookScrollBoxAcquired
-- guards with qScrollHooked, LockFontObject with qFontLocked).
local function HookAchievementLists()
    for _, host in ipairs({ "AchievementFrameCategories", "AchievementFrameAchievements", "AchievementFrameStats" }) do
        local listFrame = _G[host]
        local scrollBox = listFrame and listFrame.ScrollBox
        if scrollBox then
            SkinBase.HookScrollBoxAcquired(scrollBox, function(row)
                SkinBase.LockFrameTextObjects(row, 3)
            end)
        end
    end
end

local function SkinAchievement()
    if not IsSettingEnabled("skinAchievement") then return end
    local frame = _G.AchievementFrame
    if not frame or SkinBase.IsSkinned(frame) then return end

    HideAchievementChrome()
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()
    SkinBase.CreateBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    local header = _G.AchievementFrameHeader
    if header and header.CloseButton then
        SkinBase.SkinCloseButton(header.CloseButton)
    end

    SkinBase.SkinFrameText(frame, { recurse = true })
    HookAchievementLists()
    SkinBase.MarkSkinned(frame)
end

local function RefreshAchievement()
    local frame = _G.AchievementFrame
    if not frame then return end
    if SkinBase.IsSkinned(frame) then HookAchievementLists() end
    local bd = SkinBase.GetBackdrop(frame)
    if not bd then return end
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()
    bd:SetBackdropColor(bgr, bgg, bgb, bga)
    bd:SetBackdropBorderColor(sr, sg, sb, sa)
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

SkinBase.OnAddOnLoaded("Blizzard_AchievementUI", SkinAchievement, 0.1)
