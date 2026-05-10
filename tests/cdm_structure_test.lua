-- tests/cdm_structure_test.lua
-- Headless verification of CDM load-manifest structure. Run: lua tests/cdm_structure_test.lua

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

local function indexOf(text, needle)
    local first = string.find(text, needle, 1, true)
    return first
end

local xml = readAll("modules/cdm/cdm.xml")

local shared = indexOf(xml, 'file="cdm_shared.lua"')
local provider = indexOf(xml, 'file="cdm_provider.lua"')
local visibility = indexOf(xml, 'file="hud_visibility.lua"')
local effects = indexOf(xml, 'file="cdm_effects.lua"')

assert(provider, "cdm_provider.lua should be loaded")
assert(shared, "cdm_shared.lua should be loaded")
assert(visibility, "hud_visibility.lua should be loaded")
assert(provider < shared, "cdm_shared.lua should load after provider")
assert(shared < visibility, "cdm_shared.lua should load before runtime consumers")

assert(effects, "cdm_effects.lua should be loaded")
assert(not indexOf(xml, 'file="glows.lua"'), "glows.lua should be consolidated into cdm_effects.lua")
assert(not indexOf(xml, 'file="swipe.lua"'), "swipe.lua should be consolidated into cdm_effects.lua")
assert(not indexOf(xml, 'file="highlighter.lua"'), "highlighter.lua should be consolidated into cdm_effects.lua")

print("OK: cdm_structure_test")
