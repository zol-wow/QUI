local M = {}

M.SEPARATOR = "\31"

local function part(value)
    if value == nil then
        return ""
    end
    return tostring(value)
end

function M.ResolveSurfaceTypeKey(widget_descriptor, surface_type_key)
    local db_path
    if type(widget_descriptor) == "table" then
        db_path = widget_descriptor.dbPath
    end
    if db_path == nil then
        return nil
    end
    return surface_type_key
end

function M.Build(label, widget_descriptor, source)
    source = source or {}

    local db_path, db_key
    if type(widget_descriptor) == "table" then
        db_path = widget_descriptor.dbPath
        db_key = widget_descriptor.dbKey
    end

    return table.concat({
        part(label),
        part(source.tileId),
        part(source.subPageIndex),
        part(source.tabName),
        part(source.subTabName),
        part(source.sectionName),
        part(db_path),
        part(db_key),
        part(source.providerKey),
        part(source.surfaceUnitKey),
        part(M.ResolveSurfaceTypeKey(widget_descriptor, source.surfaceTypeKey)),
    }, M.SEPARATOR)
end

function M.OfCacheEntry(entry)
    if type(entry) ~= "table" then
        return M.Build(nil, nil, nil)
    end
    return M.Build(entry.label, entry.widgetDescriptor, entry)
end

return M
