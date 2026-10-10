local addonName, ns = ...

if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
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

end

local function SkinWeeklyRewardsTile(tile)
    if not tile then return end
    SkinBase.ClampTextureHidden(tile.Background)
    SkinBase.ClampTextureHidden(tile.Border)
    local selected = tile.SelectedTexture and tile.SelectedTexture:IsShown()
    SkinBase.ClampTextureHidden(tile.SelectedTexture, true)
    if tile.UnselectedFrame then SkinBase.StripTextures(tile.UnselectedFrame) end
    if not SkinBase.GetBackdrop(tile) then
        SkinBase.CreateBackdrop(tile, nil, nil, nil, nil, nil, nil, nil, nil, 6)
    end
    SkinBase.ApplyChromeBackdrop(SkinBase.GetBackdrop(tile), {
        radius = 6, withBackground = true,
        borderColor = selected and { unpack(SkinBase.GetChromePalette().accent) } or nil,
    })
    if tile.Threshold then
        if not tile.qVaultLock then
            tile.qVaultLock = tile:CreateTexture(nil, "ARTWORK")
            tile.qVaultLock:SetAtlas("Forge-Lock")
            tile.qVaultLock:SetSize(38, 38)
            tile.qVaultLock:SetPoint("LEFT", tile, "LEFT", 36, -12)
        end
        tile.qVaultLock:SetShown(not tile.unlocked and not tile.hasRewards)
    end
    if tile.RewardsFrame then
        SkinBase.SkinFrameText(tile.RewardsFrame, { chrome = true })
    end
    if not SkinBase.GetFrameData(tile, "qVaultTileHooked") then
        SkinBase.SetFrameData(tile, "qVaultTileHooked", true)
        for _, method in ipairs({ "Refresh", "SetSelectionState" }) do
            if tile[method] then hooksecurefunc(tile, method, SkinWeeklyRewardsTile) end
        end
    end
end

local function SkinWeeklyRewardsContents(frame)
    for _, key in ipairs({ "RaidFrame", "MythicFrame", "PVPFrame", "WorldFrame" }) do
        local category = frame[key]
        if category then
            SkinBase.ClampTextureHidden(category.Border)
            SkinBase.SkinFrameText(category, { chrome = true })
        end
    end
    for _, tile in ipairs(frame.Activities or {}) do SkinWeeklyRewardsTile(tile) end
    if frame.ConcessionsFrame then
        SkinBase.SkinFrameText(frame.ConcessionsFrame, { chrome = true })
    end
end

local function ApplyWeeklyRewardsSkin(frame)
    if not frame or not IsSettingEnabled("skinWeeklyRewards") then return end

    HideWeeklyRewardsChrome(frame)
    if not SkinBase.GetBackdrop(frame) then
        local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetWindowColors()
        SkinBase.CreateBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga, 8)
    end

    if frame.CloseButton then
        SkinBase.SkinCloseButton(frame.CloseButton)
    end

    SkinBase.ApplyButtonFontObjectsDeep(frame, 4)
    if frame.SelectRewardButton then
        SkinBase.SkinButton(frame.SelectRewardButton)
        SkinBase.ApplyButtonFontObjects(frame.SelectRewardButton)
    end

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

    SkinWeeklyRewardsContents(frame)
    SkinBase.MarkSkinned(frame)
end

local function HookWeeklyRewardsLifecycle(frame)
    if not frame or SkinBase.GetFrameData(frame, "lifecycleHooks") then return end
    SkinBase.SetFrameData(frame, "lifecycleHooks", true)
    if frame.Refresh then hooksecurefunc(frame, "Refresh", ApplyWeeklyRewardsSkin) end
    frame:HookScript("OnShow", ApplyWeeklyRewardsSkin)


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
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetWindowColors()
    SkinBase.SetBackdropColors(bd, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
    SkinWeeklyRewardsContents(frame)
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
