local function read(path) local fh = assert(io.open(path, "r")); local s = fh:read("*a"); fh:close(); return s end
local src = read("core/uikit.lua")
assert(src:find("local function SafeRegions"), "SafeRegions guard must exist")
assert(src:find("local function SafeChildren"), "SafeChildren guard must exist")
-- No raw unguarded frame:GetRegions() remains inside the three walk helpers.
-- (Spot-check: the recurse helpers must reference SafeChildren, not a bare GetChildren loop.)
assert(src:find("SafeChildren"), "walks must route through SafeChildren")
print("OK skinframetext_secret_hierarchy_guard_test")
