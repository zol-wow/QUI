-- tests/unit/damage_meter_border_apply_test.lua
-- Run: lua tests/unit/damage_meter_border_apply_test.lua
--
-- Regression: the Appearance -> Colors -> Border picker writes colors.border,
-- but the window never rendered a border or read colors.border, so changing it
-- did nothing. The window now draws a 1px border via the shared UIKit helper,
-- colored from colors.border with a QUI-accent fallback (mirrors headerText),
-- and _ApplyColors repaints it so settings changes apply live.

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end

local src = readAll("QUI_DamageMeter/damage_meter/damage_meter.lua")

-- 1. The border color resolves through the appearance schema like every other
--    color (per-window override precedence handled by ResolveAppearance).
assert(src:find('"colors", "border"', 1, true),
    "window must resolve colors.border via ResolveAppearance")

-- 2. A dedicated border-color resolver exists with a nil -> accent fallback,
--    mirroring the headerText treatment (nil = QUI accent).
local resolvePos = src:find("function Window:_ResolveBorderColor", 1, true)
assert(resolvePos, "Window:_ResolveBorderColor helper must be defined")
local afterResolve = src:find("\nfunction ", resolvePos + 1)
local resolveBody = src:sub(resolvePos, (afterResolve or #src + 1) - 1)
assert(resolveBody:find('"colors", "border"', 1, true),
    "_ResolveBorderColor must read colors.border")
assert(resolveBody:find("GetAccentColor", 1, true),
    "_ResolveBorderColor must fall back to the QUI accent when border is nil")

-- 3. Window:New creates a real window-level border via the shared UIKit helper
--    and exposes it as self.border.
assert(src:find("CreateBackdropBorder", 1, true),
    "Window:New must create a window border via UIKit.CreateBackdropBorder")
assert(src:find("self%.border", 1, false),
    "Window must expose self.border")

-- 4. _ApplyColors repaints the border so the picker applies live (RefreshAll ->
--    Refresh -> _ApplyColors). Verify border repaint happens inside _ApplyColors
--    (before _ApplyFonts), the same way the Task 10 sticky-row check is scoped.
local colorsPos = src:find("function Window:_ApplyColors", 1, true)
local fontsPos  = src:find("function Window:_ApplyFonts",  1, true)
assert(colorsPos and fontsPos, "_ApplyColors and _ApplyFonts must be defined")
local applyColorsBody = src:sub(colorsPos, fontsPos - 1)
assert(applyColorsBody:find("SetBackdropBorderColor", 1, true),
    "_ApplyColors must recolor the border via SetBackdropBorderColor")
assert(applyColorsBody:find("_ResolveBorderColor", 1, true),
    "_ApplyColors must use _ResolveBorderColor for the live border color")

-- 5. The native damage meter participates in the shared Border Coloring page.
--    That page is driven by Helpers.BorderRegistry, so the module must expose a
--    registry entry whose refresh path repaints live windows.
assert(src:find("BorderRegistry.Register", 1, true),
    "damage meter must register with Helpers.BorderRegistry")
assert(src:find('key = "damageMeter"', 1, true),
    "damage meter BorderRegistry key must be damageMeter")
assert(src:find("WindowManager:RefreshAll()", 1, true),
    "damage meter border registry refresh must repaint live windows")

print("OK: damage_meter_border_apply_test")
