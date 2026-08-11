-- tests/unit/packed_payload_shape_test.lua
-- Run: lua tests/unit/packed_payload_shape_test.lua
--
-- Packing a generated payload into a long-bracket string removes it from
-- `luac -p` coverage: the compiler sees one string token and validates
-- nothing inside. This test is that lost coverage.

local ns = {}
assert(loadfile("core/pack.lua"))("QUI", ns)

assert(type(ns.Unpack) == "function", "core/pack.lua must export ns.Unpack")

local ok, result = pcall(ns.Unpack, '{ ["a"] = 1, ["b"] = 2 }', "@test")
assert(ok, "Unpack must accept a well-formed table body: " .. tostring(result))
assert(type(result) == "table", "Unpack must return a table")
assert(result.a == 1 and result.b == 2, "Unpack must preserve contents")

local bad = pcall(ns.Unpack, "{ this is not lua", "@test")
assert(not bad, "Unpack must raise on a malformed payload")

-- Unpack must guarantee a table or raise -- a syntactically valid payload
-- that evaluates to nil or a scalar is data loss, not success.
local emptyOk = pcall(ns.Unpack, "", "@test")
assert(not emptyOk, "Unpack must raise on an empty payload (evaluates to nil)")

local commentOnlyOk = pcall(ns.Unpack, "-- oops", "@test")
assert(not commentOnlyOk, "Unpack must raise on a comment-only payload (evaluates to nil)")

local scalarOk = pcall(ns.Unpack, "5", "@test")
assert(not scalarOk, "Unpack must raise on a bare scalar payload (evaluates to a number, not a table)")

-- search_cache: packed payload must unpack to the declared schema
local sc = {}
assert(loadfile("QUI_Options/search_cache.lua"))("QUI_Options", sc)

assert(type(sc.QUI_SearchCachePacked) == "string",
    "search_cache must export the payload as a STRING, not a table")
assert(type(sc.QUI_SearchCacheSchema) == "table",
    "search_cache must export a schema")

local schema = sc.QUI_SearchCacheSchema
assert(type(schema.settings) == "table" and #schema.settings > 0,
    "schema.settings must be a non-empty field-order array")
assert(type(schema.navigation) == "table" and #schema.navigation > 0,
    "schema.navigation must be a non-empty field-order array")

-- The schema is DERIVED from the keys present across rows, so a field vanishing
-- from EVERY row shrinks the schema with it and each row's arity still matches
-- the (now shorter) declaration. That loss is structurally invisible to the
-- arity assertion below. Pin the expected shape so it fails loudly instead.
--
-- If a legitimate settings change alters the field count, updating these numbers
-- is the correct response -- but it must be a deliberate edit, not a silent pass.
assert(#schema.settings == 18,
    ("settings schema has %d fields, expected 18"):format(#schema.settings))
assert(#schema.navigation == 16,
    ("navigation schema has %d fields, expected 16"):format(#schema.navigation))

local function hasField(list, name)
    for i = 1, #list do if list[i] == name then return true end end
    return false
end
for _, required in ipairs({ "featureId", "category", "label", "widgetDescriptor" }) do
    assert(hasField(schema.settings, required),
        "settings schema lost required field: " .. required)
end
for _, required in ipairs({ "featureId", "category", "label", "navType" }) do
    assert(hasField(schema.navigation, required),
        "navigation schema lost required field: " .. required)
end

local cache = ns.Unpack(sc.QUI_SearchCachePacked, "@search_cache")
assert(type(cache.settings) == "table" and #cache.settings > 0, "settings rows missing")
assert(type(cache.navigation) == "table" and #cache.navigation > 0, "navigation rows missing")

-- Arity is PINNED: a short row means a trailing nil truncated the record and
-- every field after it silently reads as nil.
for i = 1, #cache.settings do
    assert(#cache.settings[i] == #schema.settings,
        ("settings row %d has arity %d, schema declares %d")
            :format(i, #cache.settings[i], #schema.settings))
end
for i = 1, #cache.navigation do
    assert(#cache.navigation[i] == #schema.navigation,
        ("navigation row %d has arity %d, schema declares %d")
            :format(i, #cache.navigation[i], #schema.navigation))
end

print("OK: packed_payload_shape_test")
