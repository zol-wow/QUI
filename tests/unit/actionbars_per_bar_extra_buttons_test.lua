-- tests/unit/actionbars_per_bar_extra_buttons_test.lua
-- Run: lua tests/unit/actionbars_per_bar_extra_buttons_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local perBarSource = readFile("modules/actionbars/settings/action_bars_per_bar.lua")
local actionBarsSource = readFile("modules/actionbars/actionbars_per_bar_builders.lua")

local function assertContains(source, needle, message)
    assert(source:find(needle, 1, true), message .. " (missing `" .. needle .. "`)")
end

assertContains(perBarSource,
    '{ value = "extraActionButton", text = "Extra Action Button" }',
    "Per-Bar selector should include the Extra Action Button")
assertContains(perBarSource,
    '{ value = "zoneAbility",       text = "Zone Ability" }',
    "Per-Bar selector should include Zone Ability")
assertContains(perBarSource,
    '"extraActionButton", "zoneAbility"',
    "Per-Bar search lookup keys should include the extra button entries")
assertContains(perBarSource,
    'local SPECIAL_BUTTON_OPTION_KEYS = { extraActionButton = true, zoneAbility = true }',
    "Per-Bar copy-all behavior should identify special button options")
assertContains(perBarSource,
    'if sourceIsSpecial == destinationIsSpecial then',
    "Apply-to-all should not copy regular bar settings into special button settings")
assertContains(perBarSource,
    'if _G.QUI_RefreshExtraButtons then',
    "Apply-to-all should refresh special button frames after copying settings")

assertContains(actionBarsSource,
    'local SPECIAL_BUTTON_BARS = { extraActionButton = true, zoneAbility = true }',
    "Per-Bar settings builder should identify special button bars")
assertContains(actionBarsSource,
    'local function BuildSpecialButtonSettings(content, barKey, barDB)',
    "Per-Bar settings builder should render special button controls")
assertContains(actionBarsSource,
    'local function ShowSpecialButtonReloadPrompt()',
    "Special button management toggles should prompt for reload")
assertContains(actionBarsSource,
    'GUI:CreateFormToggle(body, "Enabled", "enabled", barDB, RefreshSpecialButtonEnabled',
    "Special button Enabled control should use a toggle")
assertContains(actionBarsSource,
    'GUI:CreateFormToggle(body, "Hide Artwork", "hideArtwork", barDB, RefreshSpecialButton',
    "Special button Hide Artwork control should use a toggle")
assertContains(actionBarsSource,
    'GUI:CreateFormSlider(body, "Scale"',
    "Special button Scale control should use a slider")
assertContains(actionBarsSource,
    '_G.QUI_RefreshExtraButtons',
    "Special button changes should refresh the managed extra button frames")

print("OK: actionbars_per_bar_extra_buttons_test")
