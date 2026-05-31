-- tests/unit/options_refresh_preserves_subpage_test.lua
-- Run: lua tests/unit/options_refresh_preserves_subpage_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local source = readFile("QUI_Options/framework.lua")
local refreshStart = assert(
    source:find("function GUI:RefreshAccentColor()", 1, true),
    "framework.lua must define GUI:RefreshAccentColor"
)
local refreshEnd = assert(
    source:find("---------------------------------------------------------------------------\n-- SCROLLBAR STYLING", refreshStart, true),
    "could not isolate GUI:RefreshAccentColor body"
)
local refreshBody = source:sub(refreshStart, refreshEnd)

assert(
    refreshBody:find("prevSubPageIndex", 1, true),
    "RefreshAccentColor must preserve the active sub-page index across rebuilds"
)
assert(
    refreshBody:find("_activeSubPageIndex", 1, true),
    "RefreshAccentColor must read the selected tile's active sub-page index before teardown"
)
assert(
    refreshBody:find("subPageIndex = prevSubPageIndex", 1, true),
    "RefreshAccentColor must pass the saved sub-page index back into SelectFeatureTile"
)

print("OK: options_refresh_preserves_subpage_test")
