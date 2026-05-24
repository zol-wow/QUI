-- tests/unit/cdm_xml_load_order_test.lua
-- Run: lua tests/unit/cdm_xml_load_order_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return data
end

local source = readAll("modules/cdm/cdm.xml")

local iconRenderer = assert(source:find("cdm_icon_renderer.lua", 1, true),
    "cdm_icon_renderer.lua must be registered")
local barRenderer = assert(source:find("cdm_bar_renderer.lua", 1, true),
    "cdm_bar_renderer.lua must be registered")
local previewDriver = assert(source:find("composer_preview_driver.lua", 1, true),
    "composer_preview_driver.lua must be registered")
local composer = assert(source:find("composer.lua\"", 1, true),
    "composer.lua must be registered")

assert(iconRenderer < previewDriver,
    "cdm_icon_renderer.lua must load BEFORE composer_preview_driver.lua")
assert(barRenderer < previewDriver,
    "cdm_bar_renderer.lua must load BEFORE composer_preview_driver.lua")
assert(previewDriver < composer,
    "composer_preview_driver.lua must load BEFORE composer.lua")

print("OK: cdm_xml_load_order_test")
