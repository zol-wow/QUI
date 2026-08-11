local ADDON_NAME, ns = ...
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema
if not Registry or type(Registry.RegisterFeature) ~= "function"
    or not Schema or type(Schema.Feature) ~= "function"
    or type(Schema.Section) ~= "function" then
    return
end

local function BuildAurasDisplaysContent(host, ctx, section)
    local Page = ns.QUI_AuraDisplaysOptions
    local SearchRoute = Settings and Settings.SearchRoute

    local HUB_ROUTE = {
        tabIndex = 21,
        tabName = ns.L["Auras"],
        subTabIndex = 6,
        subTabName = ns.L["Aura Displays"],
        tileId = "auras",
        subPageIndex = 6,
        featureId = "aurasDisplaysPage",
    }

    if Page and type(Page.BuildAuraDisplaysContent) == "function" then
        if SearchRoute and type(SearchRoute.With) == "function" then
            SearchRoute.With(HUB_ROUTE, Page.BuildAuraDisplaysContent, host, ctx)
        else
            Page.BuildAuraDisplaysContent(host, ctx)
        end
    end

    return host:GetHeight() or 80
end

Registry:RegisterFeature(Schema.Feature({
    id = "aurasDisplaysPage",
    category = "frames",
    nav = { tileId = "auras", subPageIndex = 6 },
    sections = {
        Schema.Section({
            id = "settings",
            kind = "page",
            minHeight = 80,
            build = BuildAurasDisplaysContent,
        }),
    },
}))
