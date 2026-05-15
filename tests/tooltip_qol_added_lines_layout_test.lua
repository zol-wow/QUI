-- tests/tooltip_qol_added_lines_layout_test.lua
-- Run: lua tests/tooltip_qol_added_lines_layout_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local data = fh:read("*a")
    fh:close()
    return data
end

local source = readFile("modules/qol/tooltip.lua")

assert(source:find("local function AddTooltipInfoLine", 1, true),
    "tooltip QoL additions should use a shared left-aligned wrapped line helper")

local forbiddenDoubleLines = {
    'tooltip:AddDoubleLine(label, string.format("%.1f", itemLevel)',
    'tooltip:AddDoubleLine("Target:", targetInfo.name',
    'tooltip:AddDoubleLine("Mount:", mountName',
    'tooltip:AddDoubleLine("M+ Rating:", string.format("%.1f", rating)',
    'tooltip:AddDoubleLine("Spell ID:", tostring(spellID)',
    'tooltip:AddDoubleLine("Icon ID:", tostring(iconID)',
    'tooltip:AddDoubleLine("Item ID:", tostring(itemID)',
}

for _, needle in ipairs(forbiddenDoubleLines) do
    assert(not source:find(needle, 1, true),
        "QUI-added tooltip info should not use right-column AddDoubleLine layout: " .. needle)
end

local requiredInfoLines = {
    'AddTooltipInfoLine(tooltip, label, string.format("%.1f", itemLevel)',
    'AddTooltipInfoLine(tooltip, "Target", targetInfo.name',
    'AddTooltipInfoLine(tooltip, "Mount", mountName',
    'AddTooltipInfoLine(tooltip, "M+ Rating", string.format("%.1f", rating)',
    'AddTooltipInfoLine(tooltip, "Spell ID", tostring(spellID)',
    'AddTooltipInfoLine(tooltip, "Icon ID", tostring(iconID)',
    'AddTooltipInfoLine(tooltip, "Item ID", tostring(itemID)',
}

for _, needle in ipairs(requiredInfoLines) do
    assert(source:find(needle, 1, true),
        "expected left-aligned wrapped info line call missing: " .. needle)
end

print("tooltip_qol_added_lines_layout_test.lua: ok")
