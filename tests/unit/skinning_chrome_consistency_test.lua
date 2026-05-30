-- tests/unit/skinning_chrome_consistency_test.lua
-- Run: lua tests/unit/skinning_chrome_consistency_test.lua
-- Big-bang completeness gate: no incidental chrome literal survives the sweep.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path); local t = fh:read("*a"); fh:close(); return t
end
local function assertAbsent(text, patt, why) assert(not text:find(patt), why) end
local function assertContains(text, needle, why) assert(text:find(needle, 1, true), why) end

-- Deliberate, documented overrides — the ONLY places a raw border-px literal or
-- depth boost may remain. Add { file, why } entries here (never silence the test
-- by weakening a pattern).
local ALLOWLIST = {
    ["modules/skinning/base.lua"] = "selected-tab +0.10 emphasis (canonical tab look)",
    ["modules/skinning/frames/character.lua"] = "selected-tab +0.10 emphasis (CharacterFrame tabs)",
}

-- 1) Depth literals gone from the migrated widget + button files
for _, f in ipairs({
    "modules/skinning/frames/craftingorders.lua",
    "modules/skinning/frames/professions.lua",
    "modules/skinning/frames/instanceframes.lua",
    "modules/skinning/frames/auctionhouse.lua",
    "modules/skinning/notifications/readycheck.lua",
    "modules/skinning/system/gamemenu.lua",
}) do
    local src = readFile(f)
    assertAbsent(src, "%+ 0%.02", f .. " must route +0.02 depth through GetDepthColor")
    assertAbsent(src, "%+ 0%.04", f .. " must route +0.04 depth through GetDepthColor")
    assertAbsent(src, "%+ 0%.07", f .. " must route +0.07 button boost through CHROME.BUTTON_BOOST")
end

-- 2) The 2px border outliers are normalized
for _, f in ipairs({ "modules/skinning/notifications/loot.lua", "modules/skinning/gameplay/keystone.lua" }) do
    local src = readFile(f)
    assertAbsent(src, "ApplyPixelBackdrop%([^,]+, 2,", f .. " must not hardcode a 2px border (use CHROME.BORDER_PX or allowlist)")
end

-- 3) character_pane no longer defines its own border clone
for _, f in ipairs({ "modules/skinning/character_pane/character.lua", "modules/skinning/character_pane/inspect.lua" }) do
    local src = readFile(f)
    assertAbsent(src, "local function RefreshOnePixelBorder", f .. " must retire its RefreshOnePixelBorder clone")
end

-- 4) Constants exist and are aliased
assertContains(readFile("core/utils.lua"), "Helpers.CHROME", "core/utils.lua must define Helpers.CHROME")
assertContains(readFile("modules/skinning/base.lua"), "SkinBase.CHROME = Helpers.CHROME", "base.lua must alias SkinBase.CHROME")
assertContains(readFile("modules/skinning/base.lua"), "function SkinBase.GetDepthColor", "base.lua must define GetDepthColor")
assertContains(readFile("modules/skinning/base.lua"), "function SkinBase.SkinFrameText", "base.lua must define SkinFrameText")

-- 5) Every skinning module routes text through the sweep helper
for _, f in ipairs({
    "modules/skinning/frames/achievement.lua", "modules/skinning/frames/auctionhouse.lua",
    "modules/skinning/frames/character.lua", "modules/skinning/frames/craftingorders.lua",
    "modules/skinning/frames/inspect.lua", "modules/skinning/frames/instanceframes.lua",
    "modules/skinning/frames/interaction.lua", "modules/skinning/frames/journals.lua",
    "modules/skinning/frames/overrideactionbar.lua", "modules/skinning/frames/professions.lua",
    "modules/skinning/frames/social.lua", "modules/skinning/frames/statustracking.lua",
    "modules/skinning/frames/weeklyrewards.lua", "modules/skinning/frames/worldmap.lua",
    "modules/skinning/gameplay/keystone.lua", "modules/skinning/gameplay/mplus_timer.lua",
    "modules/skinning/gameplay/objectivetracker.lua", "modules/skinning/gameplay/powerbaralt.lua",
    "modules/skinning/notifications/alerts.lua", "modules/skinning/notifications/loot.lua",
    "modules/skinning/notifications/readycheck.lua", "modules/skinning/system/gamemenu.lua",
    "modules/skinning/system/popups.lua", "modules/skinning/system/tooltips.lua",
    "modules/skinning/character_pane/character.lua", "modules/skinning/character_pane/inspect.lua",
}) do
    local src = readFile(f)
    assert(src:find("SkinFrameText", 1, true) or src:find("SkinFontString", 1, true),
        f .. " must route text through SkinFrameText/SkinFontString")
end

-- 6) Semantic color tokens preserved (guard against over-zealous color sweep)
assertContains(readFile("modules/skinning/character_pane/character.lua"), "mastery = {",
    "character pane must keep its semantic stat-bar colors")

-- 7) (#3) Render path unified: the SkinBase.SafeSetBackdrop wrapper + ApplySafeBackdrop
-- are gone; QUICore.SafeSetBackdrop (shared combat-safe API) is untouched.
do
    local base = readFile("modules/skinning/base.lua")
    assertAbsent(base, "function SkinBase%.SafeSetBackdrop", "base.lua must drop the SkinBase.SafeSetBackdrop wrapper (#3)")
    assertAbsent(base, "local function ApplySafeBackdrop", "base.lua must drop ApplySafeBackdrop (#3)")
    assertContains(readFile("core/backdrop_deferred.lua"), "function QUICore.SafeSetBackdrop",
        "QUICore.SafeSetBackdrop must remain (shared combat-safe API)")
end

-- 8) (#2) Widget consolidation: new helper exists and the category files use it.
do
    assertContains(readFile("modules/skinning/base.lua"), "function SkinBase.SkinCategoryButton",
        "base.lua must define SkinCategoryButton (#2)")
    for _, f in ipairs({ "modules/skinning/frames/auctionhouse.lua", "modules/skinning/frames/craftingorders.lua" }) do
        local src = readFile(f)
        assert(src:find("SkinCategoryButton", 1, true), f .. " must use SkinBase.SkinCategoryButton (#2)")
        assertAbsent(src, "local function StyleCategoryButton", f .. " must retire its inline StyleCategoryButton (#2)")
    end
end

local _ = ALLOWLIST  -- referenced for documentation; loosen patterns only by adding entries above
print("OK: skinning_chrome_consistency_test")
