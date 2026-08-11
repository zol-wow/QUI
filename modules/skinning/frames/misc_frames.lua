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

SkinBase.OnAddOnLoaded("Blizzard_UIPanels_Game", function()
    SkinStandardFrame(_G.DressUpFrame, "skinDressUp")
    SkinStandardFrame(_G.TradeFrame, "skinTrade")
    SkinStandardFrame(_G.TabardFrame, "skinTabard")
    SkinStandardFrame(_G.GuildRegistrarFrame, "skinGuildRegistrar")
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
