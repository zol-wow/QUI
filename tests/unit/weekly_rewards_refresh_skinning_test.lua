-- tests/unit/weekly_rewards_refresh_skinning_test.lua
-- Run: lua tests/unit/weekly_rewards_refresh_skinning_test.lua
--
-- Regression guard for WeeklyRewardsFrame one-shot skinning risk.
-- Local FrameXML shows the Great Vault frame re-enters Refresh from OnShow and
-- WEEKLY_REWARDS_UPDATE while the UI is open, so QUI must re-hide evergreen
-- atlas chrome and reapply text/button styling after Blizzard refreshes.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assertContains(text, needle, reason)
    assert(text:find(needle, 1, true), reason)
end

local weeklyRewardsLua = readFile("tests/framexml/Interface/AddOns/Blizzard_WeeklyRewards/Blizzard_WeeklyRewards.lua")
local weeklyRewardsXml = readFile("tests/framexml/Interface/AddOns/Blizzard_WeeklyRewards/Blizzard_WeeklyRewards.xml")
local source = readFile("QUI_Skinning/skinning/frames/weeklyrewards.lua")

assertContains(weeklyRewardsXml, '<Texture parentKey="Background" atlas="evergreen-weeklyrewards-frame-back">',
    "local FrameXML must expose WeeklyRewardsFrame evergreen background chrome")
assertContains(weeklyRewardsXml, '<Texture parentKey="Border" atlas="evergreen-weeklyrewards-frame">',
    "local FrameXML must expose WeeklyRewardsFrame evergreen border chrome")
assertContains(weeklyRewardsXml, '<Texture parentKey="HeaderDivider" atlas="evergreen-weeklyrewards-header"',
    "local FrameXML must expose refresh-visible header chrome")
assertContains(weeklyRewardsXml, '<Button parentKey="SelectRewardButton" inherits="UIPanelButtonTemplate"',
    "local FrameXML must expose the Select Reward UIPanelButton")

assertContains(weeklyRewardsLua, "function WeeklyRewardsMixin:OnShow()",
    "local FrameXML must expose WeeklyRewardsMixin:OnShow")
assertContains(weeklyRewardsLua, "self:FullRefresh();",
    "WeeklyRewards OnShow must still route through FullRefresh")
assertContains(weeklyRewardsLua, "function WeeklyRewardsMixin:FullRefresh()",
    "local FrameXML must expose WeeklyRewardsMixin:FullRefresh")
assertContains(weeklyRewardsLua, "self:Refresh(self.couldClaimRewardsInOnShow);",
    "WeeklyRewards FullRefresh must still route through Refresh")
assertContains(weeklyRewardsLua, 'if event == "WEEKLY_REWARDS_UPDATE" then',
    "local FrameXML must still refresh while the WeeklyRewards UI is open")
assertContains(weeklyRewardsLua, "self:Refresh(playSheenAnims);",
    "WeeklyRewards update events must still call Refresh")
assertContains(weeklyRewardsLua, "self.HeaderFrame.Text:SetText",
    "WeeklyRewards Refresh/UpdateTitle must still mutate visible text")
assertContains(weeklyRewardsLua, "self.SelectRewardButton:SetShown(canClaimRewards);",
    "WeeklyRewards Refresh must still mutate the Select Reward button")

assertContains(source, "local function ApplyWeeklyRewardsSkin(frame)",
    "WeeklyRewards skinning must have an idempotent apply path for post-refresh repair")
assertContains(source, "local function HookWeeklyRewardsLifecycle(frame)",
    "WeeklyRewards skinning must install guarded lifecycle hooks")
assertContains(source, 'SkinBase.GetFrameData(frame, "lifecycleHooks")',
    "WeeklyRewards lifecycle hook installation must be guarded in SkinBase frame state")
assertContains(source, 'hooksecurefunc(WeeklyRewardsMixin, "Refresh"',
    "WeeklyRewards skinning must post-hook WeeklyRewardsMixin:Refresh")
assertContains(source, "ApplyWeeklyRewardsSkin(self)",
    "WeeklyRewards refresh hook must reapply chrome/text/button skinning to the refreshed frame")

print("OK: weekly_rewards_refresh_skinning_test")
