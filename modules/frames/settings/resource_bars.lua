local ADDON_NAME, ns = ...

local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema
if not Registry or type(Registry.RegisterFeature) ~= "function"
    or not Schema or type(Schema.Feature) ~= "function"
    or type(Schema.Section) ~= "function" then
    return
end

local function GetProfile()
    local core = ns.Helpers and ns.Helpers.GetCore and ns.Helpers.GetCore()
    return core and core.db and core.db.profile or nil
end

local function ApplyPrimaryPower()
    local profile = GetProfile()
    local core = ns.Addon
    if core and type(core.UpdatePowerBar) == "function" and profile and profile.powerBar then
        core:UpdatePowerBar()
    end
end

local function ApplySecondaryPower()
    local profile = GetProfile()
    local core = ns.Addon
    if core and type(core.UpdateSecondaryPowerBar) == "function" and profile and profile.secondaryPowerBar then
        core:UpdateSecondaryPowerBar()
    end
end

local function RenderBuilder(host, builderName, routeKey)
    local builders = ns.QUI_ResourceBarsSettingsBuilders
    local render = builders and builders[builderName]
    if type(render) ~= "function" then
        return 80
    end
    local height = render(host, routeKey)
    if type(height) == "number" then
        return height
    end
    return host and host.GetHeight and host:GetHeight() or 80
end

local function RenderLayoutRoute(host, options, fallbackKey)
    local U = ns.QUI_LayoutMode_Utils
    if not host or not U or type(U.BuildPositionCollapsible) ~= "function"
        or type(U.BuildOpenFullSettingsLink) ~= "function"
        or type(U.StandardRelayout) ~= "function" then
        return 80
    end

    local routeKey = options and options.providerKey or fallbackKey
    if type(routeKey) ~= "string" or routeKey == "" then
        routeKey = fallbackKey
    end
    if type(routeKey) ~= "string" or routeKey == "" then
        return 80
    end

    local sections = {}
    local function relayout()
        U.StandardRelayout(host, sections)
    end

    U.BuildPositionCollapsible(host, routeKey, { autoWidth = true }, sections, relayout)
    U.BuildOpenFullSettingsLink(host, routeKey, sections, relayout)
    relayout()
    return host:GetHeight()
end

Registry:RegisterFeature(Schema.Feature({
    id = "primaryPower",
    moverKey = "primaryPower",
    category = "frames",
    nav = {
        tileId = "resource_bars",
        subPageIndex = 1,
    },
    getDB = function(profile)
        return profile and profile.powerBar
    end,
    apply = ApplyPrimaryPower,
    sections = {
        Schema.Section({
            id = "settings",
            kind = "page",
            minHeight = 80,
            build = function(host)
                return RenderBuilder(host, "BuildPrimaryPowerSettings", "primaryPower")
            end,
        }),
    },
    render = {
        layout = function(host, options)
            return RenderLayoutRoute(host, options, "primaryPower")
        end,
    },
}))

Registry:RegisterFeature(Schema.Feature({
    id = "secondaryPower",
    moverKey = "secondaryPower",
    category = "frames",
    nav = {
        tileId = "resource_bars",
        subPageIndex = 2,
    },
    getDB = function(profile)
        return profile and profile.secondaryPowerBar
    end,
    apply = ApplySecondaryPower,
    sections = {
        Schema.Section({
            id = "settings",
            kind = "page",
            minHeight = 80,
            build = function(host)
                return RenderBuilder(host, "BuildSecondaryPowerSettings", "secondaryPower")
            end,
        }),
    },
    render = {
        layout = function(host, options)
            return RenderLayoutRoute(host, options, "secondaryPower")
        end,
    },
}))
