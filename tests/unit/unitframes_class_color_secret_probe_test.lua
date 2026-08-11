-- tests/unit/unitframes_class_color_secret_probe_test.lua
-- Run: lua tests/unit/unitframes_class_color_secret_probe_test.lua
local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local data = f:read("*a"); f:close()
    return (data:gsub("\r\n", "\n"))
end
local src = readAll("QUI_UnitFrames/unitframes/unitframes.lua")
local anchor = src:find("useClassColor and UnitIsPlayer(unit)", 1, true)
assert(anchor, "class-color branch not found")
local window = src:sub(anchor, anchor + 900)
local probe = window:find("issecretvalue and issecretvalue(class)", 1, true)
local use = window:find("RAID_CLASS_COLORS[class]", 1, true)
assert(probe, "unitframes class-color branch must probe class (binary guard)")
assert(use and probe < use, "probe must precede RAID_CLASS_COLORS[class]")
print("OK unitframes_class_color_secret_probe_test")
