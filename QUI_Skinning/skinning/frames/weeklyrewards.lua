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
--   - .HeaderFrame.HeaderDivider (evergreen-weeklyrewards-header)
--   - .SelectRewardButton.Background (evergreen-weeklyrewards-frame-selectbutton)
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
    if frame.HeaderFrame and frame.HeaderFrame.HeaderDivider then frame.HeaderFrame.HeaderDivider:Hide() end

    local bc = frame.BorderContainer
    if bc then
        if bc.Border then bc.Border:Hide() end
        if bc.TopDecor then bc.TopDecor:Hide() end
    end

    if frame.SelectRewardButton and frame.SelectRewardButton.Background then
        frame.SelectRewardButton.Background:Hide()
    end

    -- The .Blackout child is a transient dim overlay during reward selection;
    -- leave it functional (it has its own mouse capture).
end

local function ApplyWeeklyRewardsSkin(frame)
    if not frame or not IsSettingEnabled("skinWeeklyRewards") then return end

    HideWeeklyRewardsChrome(frame)
    if not SkinBase.GetBackdrop(frame) then
        local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()
        SkinBase.CreateBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end

    if frame.CloseButton then
        SkinBase.SkinCloseButton(frame.CloseButton)
    end

    SkinBase.SkinFrameText(frame, { recurse = true })
    -- Durable font lock + button font objects, matching the canonical window
    -- treatment (interaction/journals/misc_frames) so Weekly Rewards text and
    -- buttons don't revert to the Blizzard font on relayout/hover.
    SkinBase.LockFrameTextObjects(frame, 4)
    SkinBase.ApplyButtonFontObjectsDeep(frame, 4)
    -- The "Select Reward" CTA is a UIPanelButton. Give it the QUI backdrop +
    -- hover/pushed/disabled border (it otherwise renders as bare text over the
    -- parent backdrop). The engine also swaps its Highlight/Disabled font OBJECT
    -- on hover/disable WITHOUT calling a setter, so LockFontObject (setter hook)
    -- can't catch it — drive the button's font objects directly (SkinButton's
    -- own font is opt-in/off).
    if frame.SelectRewardButton then
        SkinBase.SkinButton(frame.SelectRewardButton)
        SkinBase.ApplyButtonFontObjects(frame.SelectRewardButton)
    end

    -- Reward item icons: crop + quality border. Hook the item mixin's
    -- SetDisplayedItem (self = the reward ItemFrame) so dynamically-populated
    -- rewards are skinned as they appear. Idempotent per mixin + per icon.
    if SkinBase.SkinIcon and _G.WeeklyRewardActivityItemMixin
        and not SkinBase.GetFrameData(_G.WeeklyRewardActivityItemMixin, "qRewardIconHooked") then
        hooksecurefunc(_G.WeeklyRewardActivityItemMixin, "SetDisplayedItem", function(self)
            if self and self.Icon then
                local border = SkinBase.SkinIcon(self.Icon)
                if border and self.IconBorder then
                    SkinBase.HandleIconBorder(self.IconBorder, border)
                end
            end
        end)
        SkinBase.SetFrameData(_G.WeeklyRewardActivityItemMixin, "qRewardIconHooked", true)
    end

    SkinBase.MarkSkinned(frame)
end

local function HookWeeklyRewardsLifecycle(frame)
    if not frame or SkinBase.GetFrameData(frame, "lifecycleHooks") then return end
    SkinBase.SetFrameData(frame, "lifecycleHooks", true)

    if WeeklyRewardsMixin and WeeklyRewardsMixin.Refresh then
        hooksecurefunc(WeeklyRewardsMixin, "Refresh", function(self)
            if self == _G.WeeklyRewardsFrame then
                ApplyWeeklyRewardsSkin(self)
            end
        end)
    end
end

local function SkinWeeklyRewards()
    if not IsSettingEnabled("skinWeeklyRewards") then return end
    local frame = _G.WeeklyRewardsFrame
    if not frame then return end

    HookWeeklyRewardsLifecycle(frame)
    ApplyWeeklyRewardsSkin(frame)
end

local function RefreshWeeklyRewards()
    local frame = _G.WeeklyRewardsFrame
    if not frame then return end
    local bd = SkinBase.GetBackdrop(frame)
    if not bd then return end
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()
    SkinBase.SetBackdropColors(bd, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
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
