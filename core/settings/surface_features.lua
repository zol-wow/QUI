local ADDON_NAME, ns = ...

local Settings = ns.Settings or {}
ns.Settings = Settings

local SurfaceFeatures = Settings.SurfaceFeatures or {}
Settings.SurfaceFeatures = SurfaceFeatures

local function CopyTable(source)
    local copy = {}
    if type(source) ~= "table" then
        return copy
    end

    for key, value in pairs(source) do
        copy[key] = value
    end

    return copy
end

local function ResolveSurface(spec)
    local surface = spec and spec.surface
    if type(surface) == "function" then
        return surface()
    end
    if type(surface) == "table" then
        return surface
    end
    return nil
end

local function ResolvePreview(spec)
    if type(spec.preview) == "table" then
        return spec.preview
    end

    local build = function(host)
        local surface = ResolveSurface(spec)
        local preview = surface and surface.preview
        local previewBuild = preview and preview.build
        if type(previewBuild) ~= "function" then
            return nil
        end
        return previewBuild(host, spec)
    end

    if type(spec.previewHeight) ~= "number" then
        return nil
    end

    return {
        height = spec.previewHeight,
        build = build,
    }
end

local function ResolveRenderMethod(spec, surfaceName)
    local methods = spec and spec.surfaceRenderMethods
    if type(methods) == "table" then
        local method = methods[surfaceName]
        if type(method) == "string" and method ~= "" then
            return method
        end
    end

    local method = spec and spec.surfaceRenderMethod
    if type(method) == "string" and method ~= "" then
        return method
    end

    return "RenderPage"
end

local function BuildRenderProxy(spec, surfaceName)
    return function(host, options)
        local surface = ResolveSurface(spec)
        local render = surface and surface[ResolveRenderMethod(spec, surfaceName)]
        if type(render) ~= "function" then
            return nil
        end
        return render(host, options, surfaceName, spec)
    end
end

local function BuildNavigateProxy(spec)
    if type(spec.onNavigate) == "function" then
        return spec.onNavigate
    end

    local navigate = spec.navigate
    if type(navigate) ~= "table" then
        return nil
    end

    return function(lookupKey)
        local resolvedValue = lookupKey
        if type(navigate.resolve) == "function" then
            resolvedValue = navigate.resolve(lookupKey, spec)
        end

        if resolvedValue == nil then
            return
        end

        local surface = ResolveSurface(spec)
        if not surface then
            return
        end

        if type(navigate.set) == "function" then
            return navigate.set(surface, resolvedValue, lookupKey, spec)
        end

        local setter = navigate.method and surface[navigate.method] or nil
        if type(setter) ~= "function" then
            return
        end

        return setter(resolvedValue, "lookup-nav", lookupKey, spec)
    end
end

function SurfaceFeatures:Register(spec)
    local registry = Settings.Registry
    if not registry or type(registry.RegisterFeature) ~= "function" then
        return nil
    end

    if type(spec) ~= "table" or type(spec.id) ~= "string" or spec.id == "" then
        return nil
    end

    local feature = CopyTable(spec)
    feature.surface = nil
    feature.previewHeight = nil
    feature.surfaceRenderMethod = nil
    feature.surfaceRenderMethods = nil
    feature.navigate = nil

    if type(feature.preview) ~= "table" then
        feature.preview = ResolvePreview(spec)
    end

    if type(feature.render) == "table" then
        feature.render = CopyTable(feature.render)
        if type(feature.render.full) ~= "function" then
            feature.render.full = BuildRenderProxy(spec, "full")
        end
        if type(feature.render.tile) ~= "function" then
            feature.render.tile = BuildRenderProxy(spec, "tile")
        end
    elseif type(feature.render) ~= "function" then
        feature.render = {
            full = BuildRenderProxy(spec, "full"),
            tile = BuildRenderProxy(spec, "tile"),
        }
    end

    if type(feature.onNavigate) ~= "function" then
        feature.onNavigate = BuildNavigateProxy(spec)
    end

    return registry:RegisterFeature(feature)
end
