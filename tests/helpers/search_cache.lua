-- tests/helpers/search_cache.lua
-- Load the generated settings search index as FIELD-KEYED records.
--
-- QUI_Options/search_cache.lua ships POSITIONAL rows packed into a
-- long-bracket string (ns.QUI_SearchCachePacked) beside a field-order header
-- (ns.QUI_SearchCacheSchema): row[i] is the field named schema[i]. An absent
-- field is `false`, never a hole, so #row always equals the schema's arity --
-- tools/lib/pack_emit.lua raises rather than write a literal `false` into a
-- slot, which is exactly what makes the inversion below lossless.
--
-- The runtime performs this same rehydration inside
-- GUI:ApplyGeneratedSearchCache (QUI_Options/framework.lua). This helper is
-- for tests that want the cache as plain data without standing up the whole
-- options framework.
--
-- Usage (cwd = repo root):
--   local cache = dofile("tests/helpers/search_cache.lua")()
--   -- cache.settings, cache.navigation: arrays of field-keyed records
--   -- cache.version

local CACHE_PATH = "QUI_Options/search_cache.lua"

return function(path)
    path = path or CACHE_PATH

    -- core/pack.lua is the single place that compiles a packed payload, and it
    -- raises unless the result is a table.
    local packNS = {}
    assert(loadfile("core/pack.lua"), "could not load core/pack.lua")("QUI", packNS)

    local ns = {}
    assert(loadfile(path), "could not load " .. path)("QUI_Options", ns)
    assert(type(ns.QUI_SearchCachePacked) == "string",
        path .. " must define ns.QUI_SearchCachePacked as a string")
    local schema = ns.QUI_SearchCacheSchema
    assert(type(schema) == "table",
        path .. " must define ns.QUI_SearchCacheSchema")

    local packed = packNS.Unpack(ns.QUI_SearchCachePacked, "@" .. path)

    local cache = { version = packed.version }
    for _, group in ipairs({ "settings", "navigation" }) do
        local order = schema[group]
        assert(type(order) == "table" and #order > 0,
            ("%s: schema.%s is missing or empty"):format(path, group))
        local rows = packed[group]
        assert(type(rows) == "table",
            ("%s: %s is not an array of rows"):format(path, group))

        local records = {}
        for index = 1, #rows do
            local row = rows[index]
            assert(type(row) == "table",
                ("%s: %s row %d is not a table"):format(path, group, index))
            assert(#row == #order,
                ("%s: %s row %d has arity %d, schema declares %d")
                    :format(path, group, index, #row, #order))
            local record = {}
            for slot = 1, #order do
                local value = row[slot]
                if value ~= false then
                    record[order[slot]] = value
                end
            end
            records[index] = record
        end
        cache[group] = records
    end

    return cache
end
