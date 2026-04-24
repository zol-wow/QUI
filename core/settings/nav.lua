local ADDON_NAME, ns = ...

local Settings = ns.Settings or {}
ns.Settings = Settings

local Nav = Settings.Nav or {}
Settings.Nav = Nav

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

local function MergeRoute(baseRoute, overrideRoute)
    local merged = {}

    if type(baseRoute) == "table" then
        for key, value in pairs(baseRoute) do
            merged[key] = value
        end
    end

    if type(overrideRoute) == "table" then
        for key, value in pairs(overrideRoute) do
            merged[key] = value
        end
    end

    if next(merged) == nil then
        return nil
    end

    return merged
end

function Nav:GetRoute(featureOrId)
    local feature = ResolveFeature(featureOrId)
    if not feature or type(feature.nav) ~= "table" then
        return nil
    end
    return feature.nav
end

function Nav:GetRouteByMoverKey(moverKey)
    local registry = Settings.Registry
    local feature = registry and registry.GetFeatureByMoverKey and registry:GetFeatureByMoverKey(moverKey)
    return self:GetRoute(feature)
end

function Nav:GetLookupTarget(lookupKey)
    local registry = Settings.Registry
    local feature = registry and registry.GetFeatureByLookupKey and registry:GetFeatureByLookupKey(lookupKey)
    if not feature then
        return nil, nil
    end

    local override = type(feature.lookupRoutes) == "table" and feature.lookupRoutes[lookupKey] or nil
    return MergeRoute(feature.nav, override), feature
end

function Nav:GetRouteByLookupKey(lookupKey)
    local route = self:GetLookupTarget(lookupKey)
    return route
end
