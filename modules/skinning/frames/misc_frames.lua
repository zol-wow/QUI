local addonName, ns = ...

if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
local SkinBase = ns.SkinBase
local GetCore = ns.Helpers.GetCore

local function IsSettingEnabled(key)
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings[key]
end

local function SkinStandardFrame(frame, settingKey)
    if not IsSettingEnabled(settingKey) then return end
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinWindow(frame)
    SkinBase.MarkSkinned(frame)
end

local function register(key, getFrame)
    if ns.Registry then
        ns.Registry:Register(key, {
            refresh = function() SkinBase.RefreshFrameBackdropColors(getFrame()) end,
            priority = 80,
            group = "skinning",
            importCategories = { "skinning", "theme" },
        })
    end
end

register("skinDressUp", function() return _G.DressUpFrame end)
register("skinTrade", function() return _G.TradeFrame end)
register("skinItemUpgrade", function() return _G.ItemUpgradeFrame end)
register("skinSocket", function() return _G.ItemSocketingFrame end)
register("skinTabard", function() return _G.TabardFrame end)
register("skinGuildRegistrar", function() return _G.GuildRegistrarFrame end)
register("skinPetition", function() return _G.PetitionFrame end)

local function SkinLegacyText(frame)
    if not frame then return end
    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.LockFrameTextObjects(frame, 6)
end

local function SkinLegacySystem()
    local frame = _G.LegacySystemFrame
    if not IsSettingEnabled("skinLegacySystem") or not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinWindow(frame, { tabs = frame.Tabs, depth = 6 })
    for _, page in ipairs(frame.Pages or {}) do SkinLegacyText(page) end
    local rewards = frame.RewardTrackPage
    if rewards and type(rewards.SetupRewardTrack) == "function" then
        hooksecurefunc(rewards, "SetupRewardTrack", SkinLegacyText)
    end
    local challenges = frame.ChallengesPage
    if challenges then
        for _, key in ipairs({ "CategoryList", "DetailPane" }) do
            local list = challenges[key]
            if list then
                SkinBase.HookScrollBoxRowFonts(list.ScrollBox, 5)
                SkinBase.SkinTrimScrollBar(list.ScrollBar)
            end
        end
        if challenges.CategoryList then
            SkinBase.SkinEditBox(challenges.CategoryList.SearchBox)
            SkinBase.SkinDropdown(challenges.CategoryList.FilterDropdown)
        end
    end
    local tree = frame.TreePage and frame.TreePage.LegacyTreeTraitPanel
    if tree then
        SkinBase.SkinButton(tree.ApplyButton, { font = true })
        SkinBase.SkinEditBox(tree.SearchBox)
        local event = TalentFrameBaseMixin and TalentFrameBaseMixin.Event
            and TalentFrameBaseMixin.Event.TalentButtonAcquired
        if tree.RegisterCallback and event then
            tree:RegisterCallback(event, function(_, button) SkinLegacyText(button) end, frame)
        end
    end
    SkinBase.MarkSkinned(frame)
end

if ns.Registry then
    ns.Registry:Register("skinLegacySystem", {
        refresh = function()
            local frame = _G.LegacySystemFrame
            if not frame or not SkinBase.IsSkinned(frame) then return end
            SkinBase.RefreshFrameBackdropColors(frame)
            SkinBase.RefreshTabGroup(frame.Tabs, frame)
            for _, page in ipairs(frame.Pages or {}) do SkinLegacyText(page) end
            local category = frame.ChallengesPage and frame.ChallengesPage.CategoryList
            if category then
                SkinBase.RefreshWidget(category.SearchBox)
                SkinBase.RefreshWidget(category.FilterDropdown)
            end
            local tree = frame.TreePage and frame.TreePage.LegacyTreeTraitPanel
            if tree then
                SkinBase.RefreshWidget(tree.ApplyButton)
                SkinBase.RefreshWidget(tree.SearchBox)
            end
        end,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

SkinBase.OnAddOnLoaded("Blizzard_LegacySystem", SkinLegacySystem, 0)

local function SkinStable()
    if not (ns.Client and ns.Client.isForever) then return end
    local frame = _G.PetStableFrame
    if not IsSettingEnabled("skinStable") or not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinWindow(frame)
    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.LockFrameTextObjects(frame, 4)
    SkinBase.SkinButton(frame.purchaseButton, { font = true })
    if frame.modelScene and frame.modelScene.Inset then
        SkinBase.KillNineSlice(frame.modelScene.Inset.NineSlice, true)
    end
    SkinBase.MarkSkinned(frame)
end

if ns.Registry then
    ns.Registry:Register("skinStable", {
        refresh = function()
            local frame = _G.PetStableFrame
            if not frame or not SkinBase.IsSkinned(frame) then return end
            SkinBase.RefreshFrameBackdropColors(frame)
            SkinBase.RefreshWidget(frame.purchaseButton)
        end,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

SkinBase.OnAddOnLoaded("Blizzard_StableUI", SkinStable, 0)

SkinBase.OnAddOnLoaded("Blizzard_UIPanels_Game", function()
    SkinStandardFrame(_G.DressUpFrame, "skinDressUp")
    SkinStandardFrame(_G.TradeFrame, "skinTrade")
    SkinStandardFrame(_G.TabardFrame, "skinTabard")
    SkinStandardFrame(_G.GuildRegistrarFrame, "skinGuildRegistrar")
    SkinStandardFrame(_G.PetitionFrame, "skinGuildRegistrar")
end, 0)

SkinBase.OnAddOnLoaded("Blizzard_ItemUpgradeUI", function()
    SkinStandardFrame(_G.ItemUpgradeFrame, "skinItemUpgrade")
end, 0)

SkinBase.OnAddOnLoaded("Blizzard_ItemSocketingUI", function()
    SkinStandardFrame(_G.ItemSocketingFrame, "skinSocket")
end, 0)

SkinBase.OnAddOnLoaded("Blizzard_MirrorTimer", function()
    if _G.MirrorTimerMixin and _G.MirrorTimerMixin.Setup
        and not SkinBase.GetFrameData(_G.MirrorTimerMixin, "qMirrorHooked") then
        hooksecurefunc(_G.MirrorTimerMixin, "Setup", function(self)
            if IsSettingEnabled("skinMirrorTimers") and self and self.StatusBar then
                SkinBase.SkinStatusBar(self.StatusBar, { backdrop = false })
            end
        end)
        SkinBase.SetFrameData(_G.MirrorTimerMixin, "qMirrorHooked", true)
    end
end, 0)
if ns.Registry then
    ns.Registry:Register("skinMirrorTimers", {
        refresh = function() end,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end
