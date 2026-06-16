-- tests/unit/actionbars_cooldown_duration_text_options_test.lua
-- Run: lua tests/unit/actionbars_cooldown_duration_text_options_test.lua

local function readFile(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text:gsub("\r\n", "\n")
end

local actionBars = table.concat({
    readFile("QUI_ActionBars/actionbars/actionbars_skinning.lua"),
    readFile("QUI_ActionBars/actionbars/actionbars_per_bar_builders.lua"),
}, "\n")
local defaults = readFile("core/defaults.lua")
local preview = readFile("QUI_ActionBars/actionbars/settings/action_bars_preview_driver.lua")

local function assertContains(text, needle, message)
    assert(text:find(needle, 1, true), message .. " (missing " .. needle .. ")")
end

for _, field in ipairs({
    "showCooldownText",
    "cooldownTextFontSize",
    "cooldownTextColor",
    "cooldownTextAnchor",
    "cooldownTextOffsetX",
    "cooldownTextOffsetY",
}) do
    assertContains(defaults, field .. " =", "action bar defaults must define " .. field)
    assertContains(actionBars, '"' .. field .. '"', "copy-settings list or form controls must include " .. field)
end

assertContains(actionBars, "function UpdateCooldownText(button, settings)",
    "runtime must have a dedicated cooldown countdown text styler")
assertContains(actionBars, "cooldown:GetCountdownFontString()",
    "runtime styler must use Blizzard's native cooldown countdown FontString")
assertContains(actionBars, "SetHideCountdownNumbers",
    "runtime styler must control C-side countdown visibility")
assertContains(actionBars, "UpdateCooldownText(button, settings)",
    "button text refresh must apply cooldown duration text settings")
assertContains(actionBars, 'CreateCollapsible(content, ns.L["Cooldown Duration Text"]',
    "per-bar options must expose a Cooldown Duration Text section")

assertContains(preview, "local function SetPreviewCooldownTextStyle",
    "preview driver must style cooldown duration text")
assertContains(preview, "cooldown:GetCountdownFontString()",
    "preview driver must style the native preview cooldown countdown FontString")
assertContains(preview, "settings.showCooldownText",
    "preview driver must honor the cooldown duration text visibility setting")

print("OK: actionbars_cooldown_duration_text_options_test")
