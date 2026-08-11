-- tests/unit/options_lod_theme_core_test.lua
-- Run: lua tests/unit/options_lod_theme_core_test.lua
--
-- QUI_Options is LoadOnDemand (~2.9 MB off the login path; first open pays
-- the compile cost — accepted tradeoff). Runtime consumers outside the panel
-- (core/main.lua login accent apply, layout mode, info bar drag-reorder,
-- datatext providers) read QUI.GUI.Colors / ResolveThemePreset /
-- ApplyAccentColor before the panel opens, so core/theme.lua must pre-create
-- QUI.GUI with that surface and framework.lua must MERGE into it (`or {}` /
-- `or {...}` guards), never replace it.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local optionsToc = readFile("QUI_Options/QUI_Options.toc")
assert(optionsToc:find("## LoadOnDemand: 1", 1, true),
    "QUI_Options must be LoadOnDemand")

local rootToc = readFile("QUI.toc")
assert(rootToc:find("core\\theme.lua", 1, true),
    "theme core must load with the root addon")

local theme = readFile("core/theme.lua")
for _, surface in ipairs({
    "GUI.Colors = GUI.Colors or {",
    "GUI.ThemePresets = GUI.ThemePresets or {",
    "function GUI:ResolveThemePreset(presetName)",
    "function GUI:ApplyAccentColor(r, g, b)",
}) do
    assert(theme:find(surface, 1, true),
        "core/theme.lua must provide login theme surface: " .. surface)
end

-- framework must merge into the core-created table, not replace it
local framework = readFile("QUI_Options/framework.lua")
assert(framework:find("QUI.GUI = QUI.GUI or {}", 1, true),
    "framework must adopt the core-created GUI table")
assert(framework:find("GUI.Colors = GUI.Colors or {", 1, true),
    "framework must keep the core Colors table (its literal is the headless-harness fallback)")

-- palette drift guard: every Colors key in framework's fallback exists in core
local function colorKeys(body)
    local blockStart = assert(body:find("GUI.Colors = GUI.Colors or {", 1, true))
    local blockEnd = assert(body:find("\n}", blockStart, true))
    local keys = {}
    for key in body:sub(blockStart, blockEnd):gmatch("\n%s%s%s%s(%w+)%s*=%s*{") do
        keys[key] = true
    end
    return keys
end
local themeKeys = colorKeys(theme)
for key in pairs(colorKeys(framework)) do
    assert(themeKeys[key],
        "framework Colors key missing from core/theme.lua palette: " .. key)
end

print("PASS options_lod_theme_core_test")
