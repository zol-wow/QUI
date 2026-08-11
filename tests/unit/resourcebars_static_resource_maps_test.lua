-- tests/unit/resourcebars_static_resource_maps_test.lua
-- Run: lua tests/unit/resourcebars_static_resource_maps_test.lua
--
-- GetPrimaryResource/GetSecondaryResource run on every power event
-- (OnUnitPower, OnUnitAura, OnRunePowerUpdate) and rebuilt their ~16-entry
-- nested class/spec maps per call — the module's hottest allocation. The
-- maps are immutable; they must live at file scope.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local source = readFile("QUI_ResourceBars/resourcebars/resourcebars.lua")

local primaryDecl = assert(source:find("local primaryResources = {", 1, true),
    "primaryResources map must exist")
local secondaryDecl = assert(source:find("local secondaryResources = {", 1, true),
    "secondaryResources map must exist")
local primaryFn = assert(source:find("local function GetPrimaryResource()", 1, true))
local secondaryFn = assert(source:find("local function GetSecondaryResource()", 1, true))

assert(primaryDecl < primaryFn,
    "primaryResources must be file-scope (declared before GetPrimaryResource), not rebuilt per call")
assert(secondaryDecl < secondaryFn,
    "secondaryResources must be file-scope (declared before GetSecondaryResource), not rebuilt per call")

-- no second constructor inside the getter bodies
assert(not source:find("local primaryResources = {", primaryFn, true),
    "GetPrimaryResource must not rebuild the map per call")
assert(not source:find("local secondaryResources = {", secondaryFn, true),
    "GetSecondaryResource must not rebuild the map per call")

print("PASS resourcebars_static_resource_maps_test")
