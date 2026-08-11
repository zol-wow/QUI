-- tests/unit/search_cache_no_duplicate_rows_test.lua
-- Run: lua tests/unit/search_cache_no_duplicate_rows_test.lua

local cache = dofile("tests/helpers/search_cache.lua")()
local settings = assert(cache.settings, "cache must have a settings section")

local row_identity = dofile("tools/lib/search_row_identity.lua")
local IDENTITY_SEPARATOR = row_identity.SEPARATOR

local function field(value)
    if value == nil then
        return ""
    end
    return tostring(value)
end

local identity_of = row_identity.OfCacheEntry

local function describe(entry)
    return ("label=%q tileId=%s subPageIndex=%s tabName=%s subTabName=%s sectionName=%s featureId=%s"):format(
        tostring(entry.label), field(entry.tileId), field(entry.subPageIndex),
        field(entry.tabName), field(entry.subTabName), field(entry.sectionName),
        field(entry.featureId))
end

local seen = {}
local collisions = {}

for _, entry in ipairs(settings) do
    local identity = identity_of(entry)
    local prior = seen[identity]
    if prior then
        collisions[#collisions + 1] = { identity = identity, a = prior, b = entry }
    else
        seen[identity] = entry
    end
end

if #collisions > 0 then
    print(("FAIL: %d duplicate settings row(s) found"):format(#collisions))
    for _, collision in ipairs(collisions) do
        print("  duplicate identity: " .. collision.identity:gsub(IDENTITY_SEPARATOR, "|"))
        print("    " .. describe(collision.a))
        print("    " .. describe(collision.b))
    end
    error(("search_cache_no_duplicate_rows_test: %d duplicate row(s) (see identities above)")
        :format(#collisions), 0)
end

print(("OK: search_cache_no_duplicate_rows_test (%d settings rows, no duplicate identities)")
    :format(#settings))
