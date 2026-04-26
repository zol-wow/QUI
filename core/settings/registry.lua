local ADDON_NAME, ns = ...

local Settings = ns.Settings or {}
ns.Settings = Settings

local Registry = Settings.Registry or {
    _featuresById = {},
    _featuresByMoverKey = {},
    _featuresByLookupKey = {},
    _orderedIds = {},
}
Settings.Registry = Registry

local function RemoveOrderedId(orderedIds, featureId)
    for index, existingId in ipairs(orderedIds) do
        if existingId == featureId then
            table.remove(orderedIds, index)
            return
        end
    end
end

local function ClearLookupKeys(registry, spec)
    if type(spec) ~= "table" or type(spec.lookupKeys) ~= "table" then
        return
    end

    for _, lookupKey in ipairs(spec.lookupKeys) do
        if type(lookupKey) == "string" and lookupKey ~= "" then
            registry._featuresByLookupKey[lookupKey] = nil
        end
    end
end

local function EnsureLookupKeys(spec)
    if type(spec) ~= "table" then
        return nil
    end

    if type(spec.lookupKeys) ~= "table" then
        spec.lookupKeys = {}
    end

    return spec.lookupKeys
end

local function RemoveLookupKey(spec, lookupKey)
    if type(spec) ~= "table" or type(spec.lookupKeys) ~= "table" then
        return false
    end

    for index, existingKey in ipairs(spec.lookupKeys) do
        if existingKey == lookupKey then
            table.remove(spec.lookupKeys, index)
            return true
        end
    end

    return false
end

local function AddLookupKey(spec, lookupKey)
    local lookupKeys = EnsureLookupKeys(spec)
    if not lookupKeys then
        return false
    end

    for _, existingKey in ipairs(lookupKeys) do
        if existingKey == lookupKey then
            return false
        end
    end

    lookupKeys[#lookupKeys + 1] = lookupKey
    return true
end

function Registry:RegisterFeature(spec)
    if type(spec) ~= "table" or type(spec.id) ~= "string" or spec.id == "" then
        return nil
    end

    local previous = self._featuresById[spec.id]
    if previous and type(previous.moverKey) == "string" and previous.moverKey ~= "" then
        self._featuresByMoverKey[previous.moverKey] = nil
    end
    if previous then
        ClearLookupKeys(self, previous)
    end

    if not previous then
        table.insert(self._orderedIds, spec.id)
    end

    self._featuresById[spec.id] = spec

    if type(spec.moverKey) == "string" and spec.moverKey ~= "" then
        self._featuresByMoverKey[spec.moverKey] = spec.id
    end
    if type(spec.lookupKeys) == "table" then
        for _, lookupKey in ipairs(spec.lookupKeys) do
            if type(lookupKey) == "string" and lookupKey ~= "" then
                self._featuresByLookupKey[lookupKey] = spec.id
            end
        end
    end

    return spec
end

function Registry:UnregisterFeature(featureId)
    local spec = self._featuresById[featureId]
    if not spec then return nil end

    self._featuresById[featureId] = nil
    if type(spec.moverKey) == "string" and spec.moverKey ~= "" then
        self._featuresByMoverKey[spec.moverKey] = nil
    end
    ClearLookupKeys(self, spec)
    RemoveOrderedId(self._orderedIds, featureId)
    return spec
end

function Registry:GetFeature(featureId)
    if type(featureId) ~= "string" or featureId == "" then
        return nil
    end
    return self._featuresById[featureId]
end

function Registry:GetFeatureByMoverKey(moverKey)
    if type(moverKey) ~= "string" or moverKey == "" then
        return nil
    end
    local featureId = self._featuresByMoverKey[moverKey]
    return featureId and self._featuresById[featureId] or nil
end

function Registry:GetFeatureByLookupKey(lookupKey)
    if type(lookupKey) ~= "string" or lookupKey == "" then
        return nil
    end
    local featureId = self._featuresByLookupKey[lookupKey]
    return featureId and self._featuresById[featureId] or nil
end

function Registry:RegisterLookupKey(featureId, lookupKey, routeOverride)
    if type(featureId) ~= "string" or featureId == ""
        or type(lookupKey) ~= "string" or lookupKey == "" then
        return nil
    end

    local spec = self._featuresById[featureId]
    if not spec then
        return nil
    end

    local previousFeatureId = self._featuresByLookupKey[lookupKey]
    if previousFeatureId and previousFeatureId ~= featureId then
        local previous = self._featuresById[previousFeatureId]
        if previous then
            RemoveLookupKey(previous, lookupKey)
            if type(previous.lookupRoutes) == "table" then
                previous.lookupRoutes[lookupKey] = nil
            end
        end
    end

    AddLookupKey(spec, lookupKey)
    self._featuresByLookupKey[lookupKey] = featureId

    if type(routeOverride) == "table" then
        if type(spec.lookupRoutes) ~= "table" then
            spec.lookupRoutes = {}
        end
        spec.lookupRoutes[lookupKey] = routeOverride
    end

    return spec
end

function Registry:UnregisterLookupKey(featureId, lookupKey)
    if type(featureId) ~= "string" or featureId == ""
        or type(lookupKey) ~= "string" or lookupKey == "" then
        return nil
    end

    local spec = self._featuresById[featureId]
    if not spec then
        return nil
    end

    if self._featuresByLookupKey[lookupKey] == featureId then
        self._featuresByLookupKey[lookupKey] = nil
    end

    RemoveLookupKey(spec, lookupKey)

    if type(spec.lookupRoutes) == "table" then
        spec.lookupRoutes[lookupKey] = nil
    end

    return spec
end

function Registry:IterateFeatures()
    local index = 0
    return function()
        index = index + 1
        local featureId = self._orderedIds[index]
        if not featureId then
            return nil
        end
        return featureId, self._featuresById[featureId]
    end
end
