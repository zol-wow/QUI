local ADDON_NAME, ns = ...

local Settings = ns.Settings
local SurfaceFeatures = Settings and Settings.SurfaceFeatures
if not SurfaceFeatures or type(SurfaceFeatures.Register) ~= "function" then
    return
end

local function GetSurface()
    return ns.QUI_NameplatesSettingsSurface
end

local function GetModel()
    return ns.QUI_NameplatesSettingsModel
end

SurfaceFeatures:Register({
    id = "nameplatesPage",
    category = "frames",
    nav = {
        tileId = "nameplates",
        subPageIndex = 1,
    },
    surface = GetSurface,
    model = GetModel,
})
