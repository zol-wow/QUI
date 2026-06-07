-- tests/unit/cdm_structure_test.lua
-- Headless verification of CDM load order in QUI.toc. Run: lua tests/unit/cdm_structure_test.lua

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

local xml = readAll("QUI_CDM/QUI_CDM.toc")

local expectedOrder = {
    "cdm_shared.lua",
    "cdm_index.lua",
    "cdm_catalog.lua",
    "hud_visibility.lua",
    "cdm_scheduler.lua",
    "cdm_sources.lua",
    "cdm_runtime_store.lua",
    "cdm_runtime_queries.lua",
    "cdm_resolvers.lua",
    "cdm_frame_writes.lua",
    "cdm_effects.lua",
    "cdm_aura_catalog.lua",
    "cdm_aura_runtime.lua",
    "cdm_spelldata.lua",
    "cdm_blizz_mirror.lua",
    "cdm_icon_factory.lua",
    "cdm_icon_stack_text.lua",
    "cdm_icon_stack_policy.lua",
    "cdm_icon_mirror_index.lua",
    "cdm_icon_runtime_refresh.lua",
    "cdm_icon_update_scheduler.lua",
    "cdm_icon_refresh_batch.lua",
    "cdm_icon_refresh_walker.lua",
    "cdm_icon_item_visual_policy.lua",
    "cdm_icon_visibility_policy.lua",
    "cdm_icon_range_policy.lua",
    "cdm_icon_cooldown_policy.lua",
    "cdm_icon_custom_bar_policy.lua",
    "cdm_icon_renderer.lua",
    "cdm_bar_renderer.lua",
    "cdm_layout.lua",
    "cdm_buff_layout.lua",
    "cdm_containers.lua",
    "cdm_layout_mode.lua",
    "cdm_container_border_registry.lua",
}

local positions = {}
for _, fileName in ipairs(expectedOrder) do
    local pos = indexOf(xml, "cdm\\" .. fileName)
    assert(pos, fileName .. " should be loaded")
    positions[fileName] = pos
end

for i = 2, #expectedOrder do
    local before = expectedOrder[i - 1]
    local after = expectedOrder[i]
    assert(positions[before] < positions[after],
        before .. " should load before " .. after)
end

local removedAggregateFiles = {
    "cdm_domain.lua",
    "cdm_runtime.lua",
}

for _, fileName in ipairs(removedAggregateFiles) do
    assert(not indexOf(xml, "cdm\\" .. fileName),
        fileName .. " should not be registered after the layer split")
end

assert(not indexOf(xml, "cdm\\glows.lua"), "glows.lua should remain consolidated")
assert(not indexOf(xml, "cdm\\swipe.lua"), "swipe.lua should remain consolidated")
assert(not indexOf(xml, "cdm\\highlighter.lua"), "highlighter.lua should remain consolidated")

local optionsXml = readAll("QUI_Options/QUI_Options.toc")
local expectedOptionsOrder = {
    "..\\QUI_CDM\\cdm\\settings\\containers_page.lua",
    "..\\QUI_CDM\\cdm\\settings\\composer_preview_driver.lua",
    "..\\QUI_CDM\\cdm\\settings\\composer.lua",
}
local optionPositions = {}
for _, fileName in ipairs(expectedOptionsOrder) do
    local pos = indexOf(optionsXml, fileName)
    assert(pos, fileName .. " should load on demand")
    optionPositions[fileName] = pos
end
for i = 2, #expectedOptionsOrder do
    local before = expectedOptionsOrder[i - 1]
    local after = expectedOptionsOrder[i]
    assert(optionPositions[before] < optionPositions[after],
        before .. " should load before " .. after)
end

print("OK: cdm_structure_test")
