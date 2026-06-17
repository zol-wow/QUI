-- tests/unit/icon_glow_test.lua
-- Run: lua5.1 tests/unit/icon_glow_test.lua
-- icon_glow: provider registry, source list filtering, start/stop dispatch
-- with correct per-button provider tracking. No LibCustomGlow in harness, so
-- we register a fake provider to exercise dispatch.

local ns = {}
local IconGlow = assert(loadfile("core/icon_glow.lua"))("QUI", ns)
assert(IconGlow == ns.IconGlow, "module must publish ns.IconGlow")

-- 1. "Off" is always present in the source list.
local function has(list, name) for _, n in ipairs(list) do if n == name then return true end end end
assert(has(IconGlow.GetSourceList(), "Off"), "Off always available")

-- 2. Register a fake provider; it appears only while isAvailable() is true.
local avail = true
local calls = {}
IconGlow.RegisterProvider({
    name = "Fake",
    isAvailable = function() return avail end,
    start = function(button, opts) calls[#calls + 1] = { "start", button, opts and opts.style } end,
    stop  = function(button) calls[#calls + 1] = { "stop", button } end,
})
assert(has(IconGlow.GetSourceList(), "Fake"), "available provider listed")
avail = false
assert(not has(IconGlow.GetSourceList(), "Fake"), "unavailable provider hidden")
avail = true

-- 3. Start dispatches to the selected provider and Stop calls the SAME one,
--    even if the surface's configured source changed in between.
local btn = {}
IconGlow.Start(btn, { source = "Fake", style = "Pixel" })
assert(calls[1][1] == "start" and calls[1][3] == "Pixel", "start dispatched with style")
IconGlow.Stop(btn)  -- no source arg → uses tracked provider
assert(calls[2][1] == "stop" and calls[2][2] == btn, "stop routed to tracked provider")

-- 4. source = "Off" stops any active glow and starts nothing.
IconGlow.Start(btn, { source = "Fake", style = "Button" })
IconGlow.Start(btn, { source = "Off" })
assert(calls[#calls][1] == "stop", "switching to Off stops the active glow")

print("icon_glow_test OK")
