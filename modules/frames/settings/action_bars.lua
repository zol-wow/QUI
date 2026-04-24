local ADDON_NAME, ns = ...

local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema
if not Registry or type(Registry.RegisterFeature) ~= "function"
    or not Schema or type(Schema.Feature) ~= "function"
    or type(Schema.Section) ~= "function" then
    return
end

local function RenderBuilder(host, ownerName, fnName)
    local owner = ns[ownerName]
    local render = owner and owner[fnName]
    if type(render) ~= "function" then
        return nil
    end
    local result = render(host)
    if type(result) == "number" then
        return result
    end
    return host and host.GetHeight and host:GetHeight() or nil
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

    U.BuildPositionCollapsible(host, routeKey, nil, sections, relayout)
    U.BuildOpenFullSettingsLink(host, routeKey, sections, relayout)
    relayout()
    return host:GetHeight()
end

Registry:RegisterFeature(Schema.Feature({
    id = "actionBarsGeneral",
    moverKey = "bar1",
    lookupKeys = { "extraActionButton", "zoneAbility", "totemBar" },
    category = "frames",
    nav = {
        tileId = "action_bars",
        subPageIndex = 1,
    },
    sections = {
        Schema.Section({
            id = "settings",
            kind = "custom",
            minHeight = 80,
            render = function(host)
                return RenderBuilder(host, "QUI_ActionBarsOptions", "BuildMasterSettingsTab")
            end,
        }),
    },
    render = {
        layout = function(host, options)
            return RenderLayoutRoute(host, options, "extraActionButton")
        end,
    },
}))

Registry:RegisterFeature(Schema.Feature({
    id = "actionBarsBuffDebuff",
    moverKey = "buffDebuff",
    lookupKeys = { "buffFrame", "debuffFrame" },
    category = "frames",
    nav = {
        tileId = "action_bars",
        subPageIndex = 2,
    },
    sections = {
        Schema.Section({
            id = "settings",
            kind = "custom",
            minHeight = 80,
            render = function(host)
                return RenderBuilder(host, "QUI_BuffDebuffOptions", "BuildBuffDebuffTab")
            end,
        }),
    },
    render = {
        layout = function(host, options)
            return RenderLayoutRoute(host, options, "buffFrame")
        end,
    },
}))
