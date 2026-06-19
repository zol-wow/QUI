---------------------------------------------------------------------------
-- WEEKLY REWARDS FRAME SKINNING (Great Vault)
--
-- WeeklyRewardsFrame uses bespoke evergreen-atlas chrome
-- (Blizzard_WeeklyRewards/Blizzard_WeeklyRewards.xml:496-) instead of
-- the standard NineSlice/Bg/TopTileStreaks template family:
--   - .Background           (evergreen-weeklyrewards-frame-back)
--   - .BorderShadow         (evergreen-weeklyrewards-frame-back-shadow)
--   - .Divider1 / .Divider2 (evergreen-weeklyrewards-divider)
--   - .BorderContainer.Border    (evergreen-weeklyrewards-frame)
--   - .BorderContainer.TopDecor  (evergreen-weeklyrewards-frame-topdecor)
--   - .Blackout.Texture     (semi-transparent dim during transitions)
-- Close button lives at WeeklyRewardsFrame.CloseButton.
---------------------------------------------------------------------------

local addonName, ns = ...
local SkinBase = ns.SkinBase
local GetCore = ns.Helpers.GetCore

local function IsSettingEnabled(key)
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings[key]
end

local function HideWeeklyRewardsChrome(frame)
    if frame.Background then frame.Background:Hide() end
    if frame.BorderShadow then frame.BorderShadow:Hide() end
    if frame.Divider1 then frame.Divider1:Hide() end
    if frame.Divider2 then frame.Divider2:Hide() end

    local bc = frame.BorderContainer
    if bc then
        if bc.Border then bc.Border:Hide() end
        if bc.TopDecor then bc.TopDecor:Hide() end
    end

    -- The .Blackout child is a transient dim overlay during reward selection;
    -- leave it functional (it has its own mouse capture).
end

local function SkinWeeklyRewards()
    if not IsSettingEnabled("skinWeeklyRewards") then return end
    local frame = _G.WeeklyRewardsFrame
    if not frame or SkinBase.IsSkinned(frame) then return end

    HideWeeklyRewardsChrome(frame)
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()
    SkinBase.CreateBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    if frame.CloseButton then
        SkinBase.SkinCloseButton(frame.CloseButton)
    end

    SkinBase.SkinFrameText(frame, { recurse = true })
    -- The "Select Reward" CTA is a UIPanelButton: the engine swaps its Highlight/
    -- Disabled font OBJECT on hover/disable WITHOUT calling a setter, so LockFontObject
    -- (setter hook) can't catch it. Drive the button's font objects instead.
    if frame.SelectRewardButton then
        SkinBase.ApplyButtonFontObjects(frame.SelectRewardButton)
    end
    SkinBase.MarkSkinned(frame)
end

local function RefreshWeeklyRewards()
    local frame = _G.WeeklyRewardsFrame
    if not frame then return end
    local bd = SkinBase.GetBackdrop(frame)
    if not bd then return end
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()
    bd:SetBackdropColor(bgr, bgg, bgb, bga)
    bd:SetBackdropBorderColor(sr, sg, sb, sa)
end

_G.QUI_RefreshWeeklyRewardsColors = RefreshWeeklyRewards
if ns.Registry then
    ns.Registry:Register("skinWeeklyRewards", {
        refresh = RefreshWeeklyRewards,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

SkinBase.OnAddOnLoaded("Blizzard_WeeklyRewards", SkinWeeklyRewards, 0)
