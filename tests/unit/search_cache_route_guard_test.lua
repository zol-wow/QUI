-- tests/unit/search_cache_route_guard_test.lua
-- Regression test for the route-liveness guard ITSELF (tools/audit_search_cache.lua),
-- not for the search cache.
--
-- collect_live_tab_keys scans a module's TAB_DEFINITIONS block as raw text
-- (it is a source scanner, not a loader -- see its docstring). The first cut
-- of that scanner did not strip comments before matching `key = "..."`, so
-- `-- { key = "auras", ... }` still yielded "auras" as a LIVE key. Concrete
-- failure this let through: someone comments out a TAB_DEFINITIONS entry to
-- temporarily disable a tab -- an entirely ordinary thing to do -- and ships
-- it. The tab is gone from the UI, cache rows still carry its surfaceTabKey,
-- and --strict-routes reported clean anyway: the exact failure the guard
-- exists to catch, in the one shape it could not see.
--
-- This test exercises collect_live_tab_keys directly against two throwaway
-- fixture files (one live entry, one commented out) so the guard's comment
-- handling is pinned without touching any real source file. The function is
-- local to tools/audit_search_cache.lua; rather than leave it untested, the
-- tool now recognizes a sentinel first argument
-- (loadfile(path)("__AUDIT_SEARCH_CACHE_LIB_MODE__")) that short-circuits to
-- a small library table before any CLI behavior (arg parsing, file
-- discovery, cache loading, os.exit) runs -- see the seam's docstring in
-- tools/audit_search_cache.lua immediately above `local args = { ... }`.
--
-- Run: lua tests/unit/search_cache_route_guard_test.lua

local AUDIT_TOOL_PATH = "tools/audit_search_cache.lua"
local LIB_MODE_SENTINEL = "__AUDIT_SEARCH_CACHE_LIB_MODE__"

local lib = assert(loadfile(AUDIT_TOOL_PATH), "could not load " .. AUDIT_TOOL_PATH)(LIB_MODE_SENTINEL)
assert(type(lib) == "table" and type(lib.collect_live_tab_keys) == "function",
    AUDIT_TOOL_PATH .. " did not honor the " .. LIB_MODE_SENTINEL .. " test seam -- " ..
    "expected a table with collect_live_tab_keys")

local failures = 0
local function check(name, ok, detail)
    if ok then
        print("  ok  " .. name)
    else
        failures = failures + 1
        print("FAIL  " .. name .. (detail and (" -- " .. detail) or ""))
    end
end

-- Fixture bodies mirror the shape of a real *_model.lua TAB_DEFINITIONS
-- block closely enough to exercise the %b{} match and the key%s*=%s*"..."
-- capture, without needing a real ns/render function environment.
local LIVE_FIXTURE_BODY = [[
local TAB_DEFINITIONS = {
    { key = "general", label = "General" },
    { key = "auras", label = "Auras" },
}
]]

local COMMENTED_FIXTURE_BODY = [[
local TAB_DEFINITIONS = {
    { key = "general", label = "General" },
    -- { key = "auras", label = "Auras" },
}
]]

-- os.tmpname() (not the hand-off's suggested session scratchpad path): this
-- test ships in the repo and runs via `bash tools/test.sh` on any machine or
-- CI box, none of which have this session's /tmp/claude-*/ directory. A
-- portable per-run temp file is the only form of "scratch fixture" that
-- survives being committed.
local function write_temp_fixture(body)
    local path = os.tmpname()
    local handle = assert(io.open(path, "w"))
    handle:write(body)
    handle:close()
    return path
end

local live_path = write_temp_fixture(LIVE_FIXTURE_BODY)
local commented_path = write_temp_fixture(COMMENTED_FIXTURE_BODY)

local function cleanup()
    os.remove(live_path)
    os.remove(commented_path)
end

local function protected_check()
    local live_keys, live_err = lib.collect_live_tab_keys(live_path)
    check("live fixture: collect_live_tab_keys succeeds",
        type(live_keys) == "table", tostring(live_err))
    if type(live_keys) == "table" then
        check("live fixture: 'auras' key IS present (not commented out)",
            live_keys.auras == true)
        check("live fixture: 'general' key is present",
            live_keys.general == true)
    end

    local commented_keys, commented_err = lib.collect_live_tab_keys(commented_path)
    check("commented fixture: collect_live_tab_keys succeeds",
        type(commented_keys) == "table", tostring(commented_err))
    if type(commented_keys) == "table" then
        check("commented fixture: 'auras' key is ABSENT (commented out, must read as dead)",
            commented_keys.auras == nil,
            "got auras=" .. tostring(commented_keys.auras) ..
            " -- a commented-out TAB_DEFINITIONS entry registered as a live tab")
        check("commented fixture: 'general' key is still present",
            commented_keys.general == true)
    end
end

local ok, err = pcall(protected_check)
cleanup()
if not ok then
    error(err, 0)
end

if failures > 0 then
    print("FAIL: search_cache_route_guard_test (" .. failures .. " failure(s))")
    os.exit(1)
end

print("OK: search_cache_route_guard_test")
