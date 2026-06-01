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
-- The skinning engine was relocated into core/uikit.lua (loaded first, exposed as
-- both ns.UIKit and ns.SkinBase); modules/skinning/base.lua is now a thin stub, so
-- the engine-content checks below read the merged kit at its new home.
assertContains(readFile("core/utils.lua"), "Helpers.CHROME", "core/utils.lua must define Helpers.CHROME")
assertContains(readFile("core/uikit.lua"), "SkinBase.CHROME = Helpers.CHROME", "uikit.lua must alias SkinBase.CHROME")
assertContains(readFile("core/uikit.lua"), "function SkinBase.GetDepthColor", "uikit.lua must define GetDepthColor")
assertContains(readFile("core/uikit.lua"), "function SkinBase.SkinFrameText", "uikit.lua must define SkinFrameText")
assertContains(readFile("core/uikit.lua"), "function SkinBase.GetChromePalette",
    "uikit.lua must define the shared chrome color policy")
assertContains(readFile("core/uikit.lua"), "function SkinBase.ApplyChromeBackdrop",
    "uikit.lua must define the shared chrome backdrop policy")
assertContains(readFile("core/uikit.lua"), "function SkinBase.SkinChromeCloseButton",
    "uikit.lua must define the shared chrome close-button policy")
assertContains(readFile("core/uikit.lua"), "function SkinBase.CreateSecretAwareStatPolicy",
    "uikit.lua must define the shared secret-aware stat policy")

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
    -- Engine relocated to core/uikit.lua; check the merged kit there.
    local base = readFile("core/uikit.lua")
    assertAbsent(base, "function SkinBase%.SafeSetBackdrop", "uikit.lua must drop the SkinBase.SafeSetBackdrop wrapper (#3)")
    assertAbsent(base, "local function ApplySafeBackdrop", "uikit.lua must drop ApplySafeBackdrop (#3)")
    assertContains(readFile("core/backdrop_deferred.lua"), "function QUICore.SafeSetBackdrop",
        "QUICore.SafeSetBackdrop must remain (shared combat-safe API)")
end

-- 8) (#2) Widget consolidation: new helper exists and the category files use it.
do
    assertContains(readFile("core/uikit.lua"), "function SkinBase.SkinCategoryButton",
        "uikit.lua must define SkinCategoryButton (#2)")
    for _, f in ipairs({ "modules/skinning/frames/auctionhouse.lua", "modules/skinning/frames/craftingorders.lua" }) do
        local src = readFile(f)
        assert(src:find("SkinCategoryButton", 1, true), f .. " must use SkinBase.SkinCategoryButton (#2)")
        assertAbsent(src, "local function StyleCategoryButton", f .. " must retire its inline StyleCategoryButton (#2)")
    end
end

-- 9) (#9) Character/inspect pane chrome and stat policy consolidation.
do
    for _, f in ipairs({ "modules/skinning/character_pane/character.lua", "modules/skinning/character_pane/inspect.lua" }) do
        local src = readFile(f)
        assertContains(src, "ApplyChromeBackdrop", f .. " must route one-pixel chrome through the shared policy (#9)")
        assertContains(src, "SetInsetPixelPoints(region, relativeTo, pixels)", f .. " must keep only a thin inset wrapper (#9)")
        assertAbsent(src, "pixelInsetState", f .. " must not keep a local pixel-inset state clone (#9)")
        assertAbsent(src, "local function RefreshInsetPixelPoints", f .. " must not keep a local inset refresh clone (#9)")
        assertAbsent(src, "skinBase.ApplyPixelBackdrop(frame, skinBase.CHROME.BORDER_PX",
            f .. " must not bypass the shared chrome policy (#9)")
    end

    local characterPane = readFile("modules/skinning/character_pane/character.lua")
    assertContains(characterPane, "CreateSecretAwareStatPolicy",
        "character pane must use the shared secret-aware stat policy (#9)")
    assertContains(characterPane, "statPolicy:ApplyTooltip",
        "character pane stat rows must route tooltip fallback/enrichment through policy (#9)")
    assertAbsent(characterPane, "local function SafeGetStat",
        "character pane must retire inline stat read helpers (#9)")
    assertAbsent(characterPane, "if not secretsOff then",
        "character pane must retire repeated rich-tooltip secret branches (#9)")
end

local _ = ALLOWLIST  -- referenced for documentation; loosen patterns only by adding entries above
print("OK: skinning_chrome_consistency_test")
