-- Behavioral regression for Aura Display outline geometry (Lua 5.1).
local ns = {}
assert(loadfile("core/aura_elements.lua"))("QUI", ns)
assert(loadfile("core/aura_glue.lua"))("QUI", ns)
assert(loadfile("modules/trackers/aura_displays.lua"))("QUI", ns)
local AD = ns.QUI_AuraDisplays

local function check(grow, perRow, rowSpacing, width, height, preview)
    local element = {
        mode = "filterStrip", maxIcons = 5, iconSize = 20,
        spacing = 3, rowSpacing = rowSpacing, iconsPerRow = perRow,
        growDirection = grow,
    }
    local layout = AD.ResolveDisplayLayout({ layout = {
        direction = "RIGHT", alignment = "CENTER", spacing = 2,
    } }, { element }, preview)
    assert(layout.width == width and layout.height == height,
        string.format("%s outline: expected %dx%d, got %dx%d",
            grow, width, height, layout.width, layout.height))
    assert(layout.placements[element], "the aura strip must remain renderable")
end

-- Layout Mode and live layout share this extent calculation.
for _, preview in ipairs({ false, true }) do
    for _, grow in ipairs({ "UP", "DOWN" }) do
        check(grow, 0, 0, 20, 112, preview)
        check(grow, 3, 0, 43, 66, preview)
        check(grow, 3, 7, 47, 66, preview)
    end
    for _, grow in ipairs({ "RIGHT", "LEFT", "CENTER" }) do
        check(grow, 0, 0, 112, 20, preview)
        check(grow, 3, 0, 66, 43, preview)
        check(grow, 3, 7, 66, 47, preview)
    end
end
print("Aura Display outline geometry regression: ok")
