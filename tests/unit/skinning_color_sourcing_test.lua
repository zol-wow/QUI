-- tests/unit/skinning_color_sourcing_test.lua
-- Run: lua tests/unit/skinning_color_sourcing_test.lua
--
-- Structural guard for the skinning consistency-hardening round:
--  (1) the character pane sources its frame chrome from the standard skin
--      colors (Helpers.GetSkinBorderColor / GetSkinBgColorWithOverride) rather
--      than the addon-accent path (QUI:GetSkinColor) or hardcoded chrome darks;
--  (2) tooltips and status-tracking bars register in ns.Registry under the
--      "skinning" group so a global skin-color change refreshes them.
-- The settings-popout panels (options-surface #0d1117) are intentionally NOT
-- unified, so this test does not assert their darks are gone.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assertContains(text, needle, reason)
    assert(text:find(needle, 1, true), reason)
end

local function assertAbsent(text, needle, reason)
    assert(not text:find(needle, 1, true), reason)
end

local character = readFile("QUI_Skinning/skinning/character_pane/character.lua")
local uikit = readFile("core/uikit.lua")
local tooltips = readFile("QUI_Skinning/skinning/system/tooltips.lua")
local statusTracking = readFile("QUI_Skinning/skinning/frames/statustracking.lua")

-- (1) Character-pane frame chrome unified onto the standard skin colors
assertContains(character, "GetChromePalette",
    "character pane must source border/accent/background through the shared chrome policy")
assertContains(uikit, "Helpers.GetSkinBorderColor",
    "shared chrome policy must source border/accent from Helpers.GetSkinBorderColor")
assertContains(uikit, "Helpers.GetSkinBgColorWithOverride",
    "shared chrome policy must source backgrounds from Helpers.GetSkinBgColorWithOverride")
assertContains(character, "local function GetCharacterBgColor",
    "character pane must expose a GetCharacterBgColor helper")
assertAbsent(character, "QUI:GetSkinColor(",
    "character pane chrome must not use the addon-accent QUI:GetSkinColor path")

-- The skinning-group refresh must re-apply the chrome that reads skin colors
-- (close button + sidebar tabs), not only the slot borders, so a live
-- skin-color change recolors all of it without reopening the pane.
local refreshBody = character:match("_G%.QUI_RefreshCharacterPane = function%(%)%s*(.-)\nend")
assert(refreshBody and refreshBody:find("StyleSidebarTabs", 1, true)
    and refreshBody:find("StyleCloseButton", 1, true),
    "QUI_RefreshCharacterPane must re-apply close button + sidebar tab chrome on refresh")
assertAbsent(character, "0.08, 0.10, 0.14",
    "character pane close-button background must use the skin bg, not a hardcoded dark")

-- Semantic stat-bar colors must remain (guard against over-zealous replacement)
assertContains(character, "mastery = {",
    "character pane must keep its semantic stat-bar colors")

-- Refresh wiring: a skinning-group registration so RefreshAll(\"skinning\") reaches it
assertContains(character, '"characterSkin"',
    "character pane must register a skinning-group refresh entry")

-- (2) Tooltips + status tracking register in ns.Registry under group skinning
assertContains(tooltips, 'ns.Registry:Register("tooltips"',
    "tooltips must register in ns.Registry")
assertContains(statusTracking, 'ns.Registry:Register("statusTracking"',
    "status tracking must register in ns.Registry")
for _, pair in ipairs({ { tooltips, "tooltips" }, { statusTracking, "status tracking" } }) do
    assertContains(pair[1], 'group = "skinning"',
        pair[2] .. " registry registration must be in the skinning group")
end

print("OK: skinning_color_sourcing_test")
