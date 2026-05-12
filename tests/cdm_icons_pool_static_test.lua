-- tests/cdm_icons_pool_static_test.lua
-- Run: lua tests/cdm_icons_pool_static_test.lua

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

local src = readAll("modules/cdm/cdm_icons.lua")

assert(not src:find("iconPools%[viewerType%]%s*=%s*{}", 1),
    "ClearPool should wipe and reuse the existing viewer pool table instead of replacing it")
assert(src:find("BuildIconListSignature", 1, true),
    "BuildIcons should compute a stable icon list signature")
assert(src:find("_lastBuildSignature", 1, true),
    "BuildIcons should store the last icon list signature on the container")
assert(src:find("_lastBuildPool", 1, true),
    "BuildIcons should keep the last unchanged pool for signature hits")

print("OK: cdm_icons_pool_static_test")
