-- tests/unit/search_cache_audit_strict_tiles_test.lua
-- Run: lua tests/unit/search_cache_audit_strict_tiles_test.lua

local function run(command)
    local pipe = assert(io.popen(command .. " 2>&1", "r"))
    local output = pipe:read("*a") or ""
    local ok = pipe:close()
    return ok == true, output
end

local lua = (arg and arg[-1]) or os.getenv("LUA") or "lua"
local ok, output = run(lua .. " tools/audit_search_cache.lua --strict-tiles")

assert(ok, "strict search-cache tile audit should pass:\n" .. output)
assert(output:find("OK: no registered settings feature is missing from the generated cache.", 1, true),
    "strict search-cache audit did not report success:\n" .. output)

print("OK: search_cache_audit_strict_tiles_test")
