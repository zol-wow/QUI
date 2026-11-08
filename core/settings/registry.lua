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


function Registry:ResolveDestinationContext(tile, page, pageIndex, featureId)
    local context = {}
    for key, value in pairs(page.searchContext or {}) do context[key] = value end
    context.tileId, context.subPageIndex, context.featureId = tile.id, pageIndex, featureId
    context.tabName = context.tabName or tile.name
    context.subTabName = context.subTabName or page.name or tile.name
    return context
end

-- Outer destinations are registered from the same tile specs that build the UI.
-- A feature may have several homes; its default mover route is not its identity.
function Registry:RegisterTileDestinations(spec)
    self._destinationsByTile = self._destinationsByTile or {}
    self._destinationTiles = self._destinationTiles or {}
    if not self._destinationsByTile[spec.id] then
        self._destinationTiles[#self._destinationTiles + 1] = spec.id
    end
    local destinations = {}
    self._destinationsByTile[spec.id] = destinations
    local function AddPage(page, pageIndex)
        local references = page.featureIds or { page.featureId }
        for _, reference in ipairs(references) do
            local featureId = type(reference) == "table" and reference.key or reference
            if self:GetFeature(featureId) then
                local context = self:ResolveDestinationContext(spec, page, pageIndex, featureId)
                destinations[#destinations + 1] = {
                    tileId = spec.id, pageId = page.id or spec.id,
                    subPageIndex = pageIndex, featureId = featureId,
                    searchContext = context, renderOptions = page.renderOptions,
                    sectionLabel = type(reference) == "table" and reference.label or nil,
                }
            end
        end
    end
    if spec.subPages then
        for index, page in ipairs(spec.subPages) do AddPage(page, index) end
    else
        AddPage(spec, 1)
    end
end

function Registry:IterateDestinations()
    local tileIndex, pageIndex = 1, 0
    return function()
        while self._destinationTiles and self._destinationTiles[tileIndex] do
            local pages = self._destinationsByTile[self._destinationTiles[tileIndex]]
            pageIndex = pageIndex + 1
            if pages[pageIndex] then return pages[pageIndex] end
            tileIndex, pageIndex = tileIndex + 1, 0
        end
    end
end

function Registry:GetDestination(tileId, pageIndex, featureId)
    local destinations = self._destinationsByTile and self._destinationsByTile[tileId]
    for _, destination in ipairs(destinations or {}) do
        if destination.subPageIndex == (pageIndex or 1)
            and destination.featureId == featureId then
            return destination
        end
    end
end
