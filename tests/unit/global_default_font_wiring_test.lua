-- tests/unit/global_default_font_wiring_test.lua
-- Run: lua tests/unit/global_default_font_wiring_test.lua
--
-- ApplyGlobalDefaultFont must fire wherever ApplyGlobalFont does (login +
-- RefreshAll) so STANDARD_TEXT_FONT is set at login and re-applied on settings
-- change. Booting main.lua here is impractical, so assert the wiring at both
-- sites by source inspection.

local function read(path)
    local fh = assert(io.open(path, "rb"), "open " .. path)
    local s = fh:read("*a"); fh:close(); return s
end

local src = read("core/main.lua")
local n = select(2, src:gsub("ApplyGlobalDefaultFont", ""))
assert(n >= 2, "main.lua should call ApplyGlobalDefaultFont at both apply sites (login + RefreshAll); found " .. n)

print("global_default_font_wiring_test: PASS")
