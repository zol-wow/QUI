-- tests/unit/aura_theme_dispel_colors_test.lua
-- Source-text assertions for core/aura_theme.lua's LIVE API.  Per-dispel-type
-- colors are no longer defined here: the secure engine colors the dispel-border
-- overlay itself from DEBUFF_TYPE_*_COLOR (see QUI.AuraSkin SetAuraBorder), and
-- aura count/duration fonts use per-button SetFont (no shared font objects), so
-- AuraTheme exposes only BorderColor (static QUI border) + Metrics (layout).
-- Run: lua tests/unit/aura_theme_dispel_colors_test.lua
local function readAll(p) local f=assert(io.open(p,"rb")); local d=f:read("*a"); f:close(); return d end
local src = readAll("core/aura_theme.lua")
local fails = 0
local function check(name, ok) if ok then print("  ok  "..name) else fails=fails+1; print("FAIL  "..name) end end
check("exposes QUI.AuraTheme", src:find("QUI.AuraTheme", 1, true) ~= nil)
for _, fn in ipairs({"Metrics", "BorderColor"}) do
    check("defines "..fn, src:find("function AuraTheme."..fn, 1, true) ~= nil)
end
-- The dead per-dispel-color / font-object API must stay removed (engine-side now).
for _, fn in ipairs({"DispelColor", "ApplyBorder", "GetCountFontObject", "GetDurationFontObject", "RefreshFonts"}) do
    check("dead API removed: "..fn, src:find("function AuraTheme."..fn, 1, true) == nil)
end
if fails > 0 then error(fails.." failures") end
print("OK: aura_theme_dispel_colors_test")
