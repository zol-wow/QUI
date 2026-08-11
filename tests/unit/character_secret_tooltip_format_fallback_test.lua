-- tests/unit/character_secret_tooltip_format_fallback_test.lua
-- Run: lua tests/unit/character_secret_tooltip_format_fallback_test.lua

local function readAll(path)
    local f = assert(io.open(path, "rb"), "failed to open " .. path)
    local data = f:read("*a")
    f:close()
    return data:gsub("\r\n", "\n")
end

local function has(source, needle, message)
    assert(source:find(needle, 1, true), message)
end

local uikit = readAll("core/uikit.lua")
local character = readAll("modules/skinning/character_pane/character.lua")

has(uikit, "local function TooltipTextHasPrintfPlaceholder(text)",
    "shared stat policy must detect printf-style tooltip format templates")
has(uikit, "local withoutLiteralPercents = text:gsub(\"%%%%\", \"\")",
    "tooltip sanitizer must ignore literal percent escapes before detecting format placeholders")
has(uikit, "row.tooltip2 = SanitizeSecretRestrictedTooltipText(body)",
    "restricted stat tooltips must not pass raw formatted body templates to GameTooltip")
has(uikit, "row.tooltip3 = SanitizeSecretRestrictedTooltipText(extraBody)",
    "restricted stat tooltip extra bodies must use the same template guard")

has(character, "_G[\"DEFAULT_STAT\"..stat.statIndex..\"_TOOLTIP\"]",
    "character pane attributes still pass Blizzard stat tooltip globals through the shared policy")
has(character, "tooltipBody = STAT_MASTERY_TOOLTIP",
    "character pane mastery fallback still routes through the shared policy")
has(character, "statPolicy:ApplyTooltip",
    "character pane stat tooltip fallback must remain policy-owned")

print("OK: character_secret_tooltip_format_fallback_test")
