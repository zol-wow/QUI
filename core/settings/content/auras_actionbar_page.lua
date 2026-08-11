local ADDON_NAME, ns = ...
local QUI = QUI
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema
if not Registry or type(Registry.RegisterFeature) ~= "function"
    or not Schema or type(Schema.Feature) ~= "function"
    or type(Schema.Section) ~= "function" then
    return
end

local function BuildAurasActionBarContent(host, ctx, section)
    local AB = ns.QUI_BuffDebuffOptions
    local SearchRoute = Settings and Settings.SearchRoute

    local HUB_ROUTE = {
        tabIndex = 21,
        tabName = ns.L["Auras"],
        subTabIndex = 4,
        subTabName = ns.L["Buff/Debuff Frames"],
        tileId = "auras",
        subPageIndex = 4,
        featureId = "aurasActionBarPage",
    }

    if AB and type(AB.BuildBuffDebuffTab) == "function" then
        if SearchRoute and type(SearchRoute.With) == "function" then
            SearchRoute.With(HUB_ROUTE, AB.BuildBuffDebuffTab, host)
        else
            AB.BuildBuffDebuffTab(host)
        end
    end

    return host:GetHeight() or 80
end

Registry:RegisterFeature(Schema.Feature({
    id = "aurasActionBarPage",
    category = "frames",
    nav = { tileId = "auras", subPageIndex = 4 },
    noSearch = true,
    sections = {
        Schema.Section({
            id = "settings",
            kind = "page",
            minHeight = 80,
            build = BuildAurasActionBarContent,
        }),
    },
}))
