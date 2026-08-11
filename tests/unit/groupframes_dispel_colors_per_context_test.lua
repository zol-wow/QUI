local function readAll(path)
    local handle = assert(io.open(path, "rb"))
    local source = handle:read("*a")
    handle:close()
    return (source:gsub("\r\n", "\n"))
end

local source = readAll("QUI_GroupFrames/groupframes/groupframes.lua")

local failures = 0
local function check(name, ok, detail)
    if ok then
        print("  ok  " .. name)
    else
        failures = failures + 1
        print("FAIL  " .. name .. (detail and (" -- " .. detail) or ""))
    end
end

check("the color reader takes a context",
    source:find("GetDispelColors = function(isRaid)", 1, true) ~= nil
    and source:find("local hs = GetHealerSettings(isRaid)", 1, true) ~= nil)

check("the border curve builder takes a context",
    source:find("local function GetDispelColorCurve(isRaid, opacity)", 1, true) ~= nil)

local arglessColors = {}
for call in source:gmatch("GetDispelColors%(%s*%)") do
    arglessColors[#arglessColors + 1] = call
end
check("no argless GetDispelColors() call survives", #arglessColors == 0,
    #arglessColors .. " found; an argless call resolves to the PARTY db")

local arglessHealer = {}
for call in source:gmatch("GetHealerSettings%(%s*%)") do
    arglessHealer[#arglessHealer + 1] = call
end
check("no argless GetHealerSettings() call survives", #arglessHealer == 0,
    #arglessHealer .. " found")

for _, field in ipairs({ "cachedColors", "colorCurves", "auraBorderCurves" }) do
    check(field .. " is keyed, not a singleton",
        source:find(field .. "%s*=%s*{}") ~= nil
        and source:find("_dispel%." .. field .. "%[key%]") ~= nil)
end

local invalidateAt = assert(source:find("InvalidateDispelColors = function()", 1, true),
    "InvalidateDispelColors must exist")
local invalidateBody = source:sub(invalidateAt, invalidateAt + 300)
check("invalidation clears every derived cache",
    invalidateBody:find("_dispel.cachedColors = {}", 1, true) ~= nil
    and invalidateBody:find("_dispel.colorCurves = {}", 1, true) ~= nil
    and invalidateBody:find("_dispel.auraBorderCurves = {}", 1, true) ~= nil)

check("the overlay path passes the frame's own context",
    source:find("GetDispelColorCurve(frame._isRaid, opacity)", 1, true) ~= nil
    and source:find("local colors = GetDispelColors(frame._isRaid)", 1, true) ~= nil)

if failures > 0 then
    print(("%d failures"):format(failures))
    os.exit(1)
end

print("groupframes_dispel_colors_per_context_test: all checks passed")
