-- tests/unit/options_help_content_load_order_test.lua
-- Run: lua tests/unit/options_help_content_load_order_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local source = readFile("QUI_Options/options.xml")

local function scriptPosition(path)
    local needle = '<Script file="' .. path .. '"/>'
    local pos = source:find(needle, 1, true)
    assert(pos, "options.xml should load " .. path)
    return pos
end

local helpContentPos = scriptPosition("tiles\\help_content.lua")
local helpPagePos = scriptPosition("..\\QUI\\core\\settings\\content\\help_page.lua")
local troubleshootingPagePos = scriptPosition("..\\QUI\\core\\settings\\content\\troubleshooting_page.lua")

assert(helpContentPos < helpPagePos,
    "Help content data must load before help_page.lua captures it")
assert(helpContentPos < troubleshootingPagePos,
    "Help content data must load before troubleshooting_page.lua captures it")

print("OK: options_help_content_load_order_test")
