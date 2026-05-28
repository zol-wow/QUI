-- tests/unit/damage_meter_row_background_test.lua
-- Run: lua tests/unit/damage_meter_row_background_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return data:gsub("\r\n", "\n")
end

local defaultsSrc = readAll("core/defaults.lua")
assert(defaultsSrc:find("showRowBackground%s*=%s*true", 1, false),
    "damage meter defaults must keep row backgrounds visible by default")

local contentSrc = readAll("modules/damage_meter/settings/damage_meter_content.lua")
assert(contentSrc:find("showRowBackground", 1, true),
    "damage meter settings must wire showRowBackground")
assert(contentSrc:find("Show Row Background", 1, true),
    "damage meter settings must expose a Show Row Background control")

local coreSrc = readAll("modules/damage_meter/damage_meter.lua")
assert(coreSrc:find("local function ApplyRowBackgroundVisibility", 1, true),
    "damage meter runtime must centralize row background visibility")
assert(coreSrc:find('ResolveAppearance(windowID, "showRowBackground") ~= false', 1, true),
    "row background visibility must default on and only hide for explicit false")
assert(coreSrc:find("row.BarBg:SetShown", 1, true),
    "row background visibility must use the C-side SetShown sink")

local _, mainCalls = coreSrc:gsub("ApplyRowBackgroundVisibility%(row, windowID%)", "")
assert(mainCalls >= 1,
    "_SetRowSource must apply row background visibility for pooled and sticky rows")

local _, breakdownCalls = coreSrc:gsub("ApplyRowBackgroundVisibility%(row, self%.parentWindowID%)", "")
assert(breakdownCalls >= 2,
    "spell and target breakdown rows must apply row background visibility")

print("OK: damage_meter_row_background_test")
