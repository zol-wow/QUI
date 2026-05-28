-- tests/unit/cdm_icon_duration_font_style_test.lua
-- Run: lua tests/unit/cdm_icon_duration_font_style_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return data:gsub("\r\n", "\n")
end

local source = readAll("modules/cdm/cdm_icon_renderer.lua")

local configureStart = assert(source:find("local function ConfigureIcon(icon, rowConfig)", 1, true),
    "ConfigureIcon must exist")
local configureEnd = assert(source:find("-- Per-spell overrides", configureStart, true),
    "ConfigureIcon duration/stack styling section must be locatable")
local configureBody = source:sub(configureStart, configureEnd)

assert(configureBody:find("GetCountdownFontString", 1, true),
    "ConfigureIcon must style the Cooldown frame's official countdown " ..
    "FontString so duration font settings apply in runtime and preview")

print("OK: cdm_icon_duration_font_style_test")
