local ADDON_NAME, ns = ...

local Settings = ns.Settings or {}
ns.Settings = Settings

local Renderer = Settings.Renderer or {}
Settings.Renderer = Renderer

local function ResolveFeature(featureOrId)
    if type(featureOrId) == "table" then
        return featureOrId
    end

    local registry = Settings.Registry
    if registry and type(registry.GetFeature) == "function" then
        return registry:GetFeature(featureOrId)
    end

    return nil
end

local function ResolveRenderFunction(feature, surfaceName)
    if type(feature.render) == "function" then
        return feature.render
    end

    if type(feature.render) == "table" and type(feature.render[surfaceName]) == "function" then
        return feature.render[surfaceName]
    end

    return nil
end

function Renderer:RenderFeature(featureOrId, host, options)
    if not host then return nil end

    local feature = ResolveFeature(featureOrId)
    if not feature then
        return nil
    end

    options = options or {}
    local surfaceName = options.surface or "tile"
    local render = ResolveRenderFunction(feature, surfaceName)
    if render then
        return render(host, options, feature)
    end

    local schema = Settings.Schema
    if schema and type(schema.CanRenderFeature) == "function"
        and type(schema.RenderFeature) == "function"
        and schema:CanRenderFeature(feature, surfaceName) then
        return schema:RenderFeature(feature, host, options)
    end

    return nil
end
