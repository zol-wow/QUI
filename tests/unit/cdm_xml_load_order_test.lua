-- tests/unit/cdm_xml_load_order_test.lua
-- Run: lua tests/unit/cdm_xml_load_order_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return data
end

local source = readAll("modules/cdm/cdm.xml")
local optionsXml = readAll("QUI_Options/options.xml")

local iconRenderer = assert(source:find("cdm_icon_renderer.lua", 1, true),
    "cdm_icon_renderer.lua must be registered")
local barRenderer = assert(source:find("cdm_bar_renderer.lua", 1, true),
    "cdm_bar_renderer.lua must be registered")
local previewDriver = assert(optionsXml:find("composer_preview_driver.lua", 1, true),
    "composer_preview_driver.lua must be registered")
local composer = assert(optionsXml:find("composer.lua\"", 1, true),
    "composer.lua must be registered")

assert(iconRenderer < barRenderer,
    "cdm_icon_renderer.lua must load BEFORE cdm_bar_renderer.lua")
assert(previewDriver < composer,
    "composer_preview_driver.lua must load BEFORE composer.lua")

print("OK: cdm_xml_load_order_test")
