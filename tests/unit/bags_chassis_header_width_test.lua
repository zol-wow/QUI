-- tests/unit/bags_chassis_header_width_test.lua
-- Run: lua tests/unit/bags_chassis_header_width_test.lua
local ns = {
    Bags = {},
    Helpers = {},
    UIKit = {},
}

(dofile("tests/helpers/locale.lua"))(ns)
local chunk = assert(loadfile("QUI_Bags/bags/views/chassis.lua"))
chunk("QUI", ns)

local Chassis = ns.Bags.Chassis
assert(Chassis and type(Chassis.MeasureHeaderWidth) == "function",
    "Chassis.MeasureHeaderWidth must be exported")
assert(type(Chassis.ClampAppearance) == "function",
    "Chassis.ClampAppearance must be exported")

local function control(width, shown)
    return {
        IsShown = function() return shown end,
        GetWidth = function() return width end,
    }
end

local measured = Chassis.MeasureHeaderWidth({
    control(40, true),
    control(500, false),
    control(140, true),
    control(20, true),
}, { leftPad = 8, rightPad = 6, gap = 8 })
assert(measured == 230, "visible controls plus padding/gaps should measure 230, got " .. tostring(measured))

local low = Chassis.ClampAppearance({
    iconSize = 5,
    spacing = -2,
    columns = 0,
    bankColumns = "bad",
})
assert(low.iconSize == 24, "iconSize should clamp to 24, got " .. tostring(low.iconSize))
assert(low.spacing == 0, "spacing should clamp to 0, got " .. tostring(low.spacing))
assert(low.columns == 1, "columns should clamp to 1, got " .. tostring(low.columns))
assert(low.bankColumns == nil, "invalid bankColumns should remain nil")

local high = Chassis.ClampAppearance({
    iconSize = 99,
    spacing = 99,
    columns = 12,
    bankColumns = 24,
})
assert(high.iconSize == 48, "iconSize should clamp to 48, got " .. tostring(high.iconSize))
assert(high.spacing == 8, "spacing should clamp to 8, got " .. tostring(high.spacing))
assert(high.columns == 12, "columns should remain 12, got " .. tostring(high.columns))
assert(high.bankColumns == 24, "bankColumns should remain 24, got " .. tostring(high.bankColumns))

print("OK: bags_chassis_header_width_test")
