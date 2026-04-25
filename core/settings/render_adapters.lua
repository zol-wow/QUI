local ADDON_NAME, ns = ...

local Settings = ns.Settings or {}
ns.Settings = Settings

local RenderAdapters = Settings.RenderAdapters or {}
Settings.RenderAdapters = RenderAdapters

local function GetBuilders()
    return ns.SettingsBuilders
end

function RenderAdapters.RenderLayoutRoute(host, routeKey)
    local U = ns.QUI_LayoutMode_Utils
    if not host or type(routeKey) ~= "string" or routeKey == ""
        or not U or type(U.BuildPositionCollapsible) ~= "function"
        or type(U.BuildOpenFullSettingsLink) ~= "function"
        or type(U.StandardRelayout) ~= "function" then
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

function RenderAdapters.RenderPositionOnly(host, frameKey)
    local U = ns.QUI_LayoutMode_Utils
    if not host or type(frameKey) ~= "string" or frameKey == ""
        or not U or type(U.BuildPositionCollapsible) ~= "function"
        or type(U.StandardRelayout) ~= "function" then
        return 80
    end

    local sections = {}
    local function relayout()
        U.StandardRelayout(host, sections)
    end

    U.BuildPositionCollapsible(host, frameKey, nil, sections, relayout)
    relayout()
    return host:GetHeight()
end

function RenderAdapters.RenderWithTileChrome(fn)
    if type(fn) ~= "function" then
        return nil
    end

    local builders = GetBuilders()
    if builders and type(builders.RenderWithTileChrome) == "function" then
        return builders.RenderWithTileChrome(fn)
    end

    return fn()
end

function RenderAdapters.BuildProvider(providerKey, parent, width, options)
    local builders = GetBuilders()
    if not builders or type(builders.BuildProvider) ~= "function" then
        return nil
    end

    return builders.BuildProvider(providerKey, parent, width, options)
end

function RenderAdapters.WithSuppressedPosition(includePosition, fn)
    if type(fn) ~= "function" then
        return nil
    end

    local builders = GetBuilders()
    if builders and type(builders.WithSuppressedPosition) == "function" then
        return builders.WithSuppressedPosition(includePosition, fn)
    end

    return fn()
end

function RenderAdapters.NotifyProviderChanged(providerKey, opts)
    local builders = GetBuilders()
    if builders and type(builders.NotifyProviderChanged) == "function" then
        builders.NotifyProviderChanged(providerKey, opts)
    end
end

function RenderAdapters.RegisterProviderSurface(providerKey, surfaceId, refreshFn, isVisibleFn)
    local builders = GetBuilders()
    if builders and type(builders.RegisterProviderSurface) == "function" then
        builders.RegisterProviderSurface(providerKey, surfaceId, refreshFn, isVisibleFn)
    end
end

function RenderAdapters.UnregisterProviderSurface(surfaceId)
    local builders = GetBuilders()
    if builders and type(builders.UnregisterProviderSurface) == "function" then
        builders.UnregisterProviderSurface(surfaceId)
    end
end

function RenderAdapters.WithOnlyPosition(fn)
    if type(fn) ~= "function" then
        return nil
    end

    local builders = GetBuilders()
    if builders and type(builders.WithOnlyPosition) == "function" then
        return builders.WithOnlyPosition(fn)
    end

    return fn()
end

function RenderAdapters.GetProviderLabel(providerKey, fallback)
    local builders = GetBuilders()
    local labels = builders and builders.PROVIDER_LABELS
    if type(labels) == "table" and type(labels[providerKey]) == "string" then
        return labels[providerKey]
    end

    return fallback or providerKey
end
