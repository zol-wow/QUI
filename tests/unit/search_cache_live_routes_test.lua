-- tests/unit/search_cache_live_routes_test.lua
-- Run: lua tests/unit/search_cache_live_routes_test.lua
--
-- Every cache row's surfaceTabKey must name a tab that still exists in the
-- owning module's TAB_DEFINITIONS. The generator walks HAND-MAINTAINED
-- per-module capture lists (GROUP_FRAMES_SEARCH_CAPTURE_TABS and friends), so
-- deleting a tab from a surface without deleting its capture row leaves rows
-- pointing at a page that is not there. The existing --strict-tiles audit
-- checks only the inverse (features MISSING from the cache) and passes such a
-- row cleanly.

local function run(command)
    local pipe = assert(io.popen(command .. " 2>&1", "r"))
    local output = pipe:read("*a") or ""
    local ok = pipe:close()
    return ok == true, output
end

local lua = (arg and arg[-1]) or os.getenv("LUA") or "lua"
local ok, output = run(lua .. " tools/audit_search_cache.lua --strict-routes")

assert(ok, "search-cache route audit should pass:\n" .. output)
assert(not output:find("dead surface route:", 1, true),
    "search cache contains rows pointing at deleted surface tabs:\n" .. output)
assert(output:find("route check:", 1, true),
    "audit did not report route-check coverage:\n" .. output)

print("OK: search_cache_live_routes_test")
