-- tests/unit/framework_dead_widget_builders_removed_test.lua
-- Run: lua tests/unit/framework_dead_widget_builders_removed_test.lua
--
-- QUI_Options/framework.lua carried a set of legacy GUI:Create* widget builders
-- that were fully superseded by the Form-prefixed variants (CreateFormCheckbox,
-- etc., 600+ call sites). The legacy builders had ZERO callers (verified by grep:
-- no :Method( calls, no string-key access, not in search_cache.lua or XML) and
-- were removed. This test guards that they stay gone and that the live siblings
-- interleaved among them (CreateAccentCheckbox, PositionDropdownMenu,
-- CreateDropdownScrollBody) remain.

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return (data:gsub("\r\n", "\n"))
end

local src = readAll("QUI_Options/framework.lua")

-- The "(" disambiguates prefixes (e.g. CreateCheckbox vs CreateCheckboxCentered).
local deadDefs = {
    "function GUI:CreateColorPicker(",
    "function GUI:CreateColorPickerCentered(",
    "function GUI:CreateSubTabs(",
    "function GUI:CreateDescription(",
    "function GUI:CreateCheckbox(",
    "function GUI:CreateCheckboxCentered(",
    "function GUI:CreateCheckboxInverted(",
    "function GUI:CreateSlider(",
    "function GUI:CreateDropdown(",
    "function GUI:CreateDropdownFullWidth(",
}
for _, def in ipairs(deadDefs) do
    assert(not src:find(def, 1, true),
        "dead legacy builder must be removed: " .. def)
end

-- Live siblings that were interleaved among the dead builders must survive.
for _, live in ipairs({
    "function GUI:CreateAccentCheckbox(",   -- 3 callers
    "local function PositionDropdownMenu(", -- used by the live form dropdown
    "local function CreateDropdownScrollBody(", -- used by the live form dropdown
}) do
    assert(src:find(live, 1, true), "live function must remain: " .. live)
end

-- The replacement Form variants must still be present.
assert(src:find("CreateFormCheckbox", 1, true), "CreateFormCheckbox (live replacement) must remain")

print("framework_dead_widget_builders_removed_test: OK")
