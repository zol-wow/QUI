-- tests/unit/utils_unit_class_color_secret_probe_test.lua
-- Run: lua tests/unit/utils_unit_class_color_secret_probe_test.lua
local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local data = f:read("*a"); f:close()
    return (data:gsub("\r\n", "\n"))
end

local src = readAll("core/utils.lua")

-- Isolate the GetUnitClassColor body (up to the next function decl).
local body = src:match("function Helpers%.GetUnitClassColor.-\nend")
assert(body, "GetUnitClassColor not found")

-- PTR7: UnitClass returns a secret classFile on secret-identity units. The
-- probe must be the binary analyzer-recognized shape and must run BEFORE any
-- use of `class`.
assert(body:find("issecretvalue and issecretvalue(class)", 1, true),
    "GetUnitClassColor must probe class with the binary issecretvalue guard")
local probePos = body:find("issecretvalue and issecretvalue(class)", 1, true)
local usePos = body:find("GetClassColorTable(class)", 1, true)
assert(usePos and probePos and probePos < usePos,
    "probe must precede GetClassColorTable(class)")
-- type(class) gate must be conjoined with the secret probe result.
assert(body:find("if not classIsSecret and type(class)", 1, true),
    "type(class) gate must be conjoined with the secret probe result")
print("OK utils_unit_class_color_secret_probe_test")
