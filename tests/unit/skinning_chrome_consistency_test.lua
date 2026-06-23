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
    ["QUI_Skinning/skinning/base.lua"] = "selected-tab +0.10 emphasis (canonical tab look)",
    ["QUI_Skinning/skinning/frames/character.lua"] = "selected-tab +0.10 emphasis (CharacterFrame tabs)",
}

-- 1) Depth literals gone from the migrated widget + button files
for _, f in ipairs({
    "QUI_Skinning/skinning/frames/craftingorders.lua",
    "QUI_Skinning/skinning/frames/professions.lua",
    "QUI_Skinning/skinning/frames/instanceframes.lua",
    "QUI_Skinning/skinning/frames/auctionhouse.lua",
    "QUI_Skinning/skinning/notifications/readycheck.lua",
    "QUI_Skinning/skinning/system/gamemenu.lua",
}) do
    local src = readFile(f)
    assertAbsent(src, "%+ 0%.02", f .. " must route +0.02 depth through GetDepthColor")
    assertAbsent(src, "%+ 0%.04", f .. " must route +0.04 depth through GetDepthColor")
    assertAbsent(src, "%+ 0%.07", f .. " must route +0.07 button boost through CHROME.BUTTON_BOOST")
end

-- 2) The 2px border outliers are normalized
for _, f in ipairs({ "QUI_Skinning/skinning/notifications/loot.lua", "QUI_Skinning/skinning/gameplay/keystone.lua" }) do
    local src = readFile(f)
    assertAbsent(src, "ApplyPixelBackdrop%([^,]+, 2,", f .. " must not hardcode a 2px border (use CHROME.BORDER_PX or allowlist)")
end

-- 3) character_pane no longer defines its own border clone
for _, f in ipairs({ "QUI_Skinning/skinning/character_pane/character.lua", "QUI_Skinning/skinning/character_pane/inspect.lua" }) do
    local src = readFile(f)
    assertAbsent(src, "local function RefreshOnePixelBorder", f .. " must retire its RefreshOnePixelBorder clone")
end

-- 4) Constants exist and are aliased
-- The skinning engine was relocated into core/uikit.lua (loaded first, exposed as
-- both ns.UIKit and ns.SkinBase); QUI_Skinning/skinning/base.lua is now a thin stub, so
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

-- 5) Every skinning module applies chrome (backdrop or a Skin* chrome helper).
-- Static text face is now owned by the global font-object override (font_system.lua
-- ApplyGlobalDefaultFont); per-file SkinFrameText/SkinFontString/ApplyButtonFontObjects
-- calls are no longer required for all files. Interactive reverts on bare-root surfaces
-- (tabs/rows/dropdowns/journals) are accepted under the new design.
--
-- Chrome contract: every skinning file must call at least one chrome helper
-- (CreateBackdrop, ApplyPixelBackdrop, ApplyFullBackdrop, SkinWindow,
--  SkinButtonFrameTemplate, or equivalent). Files that also still explicitly
-- route text are verified individually in skinning_font_reassertions_test.
for _, f in ipairs({
    "QUI_Skinning/skinning/frames/achievement.lua", "QUI_Skinning/skinning/frames/auctionhouse.lua",
    "QUI_Skinning/skinning/frames/character.lua", "QUI_Skinning/skinning/frames/craftingorders.lua",
    "QUI_Skinning/skinning/frames/inspect.lua",
    "QUI_Skinning/skinning/frames/instanceframes.lua",
    "QUI_Skinning/skinning/frames/interaction.lua", "QUI_Skinning/skinning/frames/journals.lua",
    "QUI_Skinning/skinning/frames/overrideactionbar.lua",
    "QUI_Skinning/skinning/frames/professions.lua",
    "QUI_Skinning/skinning/frames/social.lua", "QUI_Skinning/skinning/frames/statustracking.lua",
    "QUI_Skinning/skinning/frames/weeklyrewards.lua", "QUI_Skinning/skinning/frames/worldmap.lua",
    "QUI_Skinning/skinning/gameplay/keystone.lua", "QUI_Skinning/skinning/gameplay/mplus_timer.lua",
    "QUI_Skinning/skinning/gameplay/objectivetracker.lua", "QUI_Skinning/skinning/gameplay/powerbaralt.lua",
    "QUI_Skinning/skinning/notifications/alerts.lua", "QUI_Skinning/skinning/notifications/loot.lua",
    "QUI_Skinning/skinning/notifications/readycheck.lua", "QUI_Skinning/skinning/system/gamemenu.lua",
    "QUI_Skinning/skinning/system/popups.lua", "QUI_Skinning/skinning/system/tooltips.lua",
    "QUI_Skinning/skinning/character_pane/character.lua", "QUI_Skinning/skinning/character_pane/inspect.lua",
}) do
    local src = readFile(f)
    assert(
        src:find("CreateBackdrop", 1, true) or
        src:find("ApplyPixelBackdrop", 1, true) or
        src:find("ApplyFullBackdrop", 1, true) or
        src:find("ApplyTextureBackdrop", 1, true) or
        src:find("SkinWindow", 1, true) or
        src:find("SkinButtonFrameTemplate", 1, true) or
        src:find("ApplyChromeBackdrop", 1, true),
        f .. " must apply chrome (backdrop or a Skin* chrome helper)")
end

-- 6) Semantic color tokens preserved (guard against over-zealous color sweep)
assertContains(readFile("QUI_Skinning/skinning/character_pane/character.lua"), "mastery = {",
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
    for _, f in ipairs({ "QUI_Skinning/skinning/frames/auctionhouse.lua", "QUI_Skinning/skinning/frames/craftingorders.lua" }) do
        local src = readFile(f)
        assert(src:find("SkinCategoryButton", 1, true), f .. " must use SkinBase.SkinCategoryButton (#2)")
        assertAbsent(src, "local function StyleCategoryButton", f .. " must retire its inline StyleCategoryButton (#2)")
    end
end

-- 9) (#9) Character/inspect pane chrome and stat policy consolidation.
do
    for _, f in ipairs({ "QUI_Skinning/skinning/character_pane/character.lua", "QUI_Skinning/skinning/character_pane/inspect.lua" }) do
        local src = readFile(f)
        assertContains(src, "ApplyChromeBackdrop", f .. " must route one-pixel chrome through the shared policy (#9)")
        assertContains(src, "SetInsetPixelPoints(region, relativeTo, pixels)", f .. " must keep only a thin inset wrapper (#9)")
        assertAbsent(src, "pixelInsetState", f .. " must not keep a local pixel-inset state clone (#9)")
        assertAbsent(src, "local function RefreshInsetPixelPoints", f .. " must not keep a local inset refresh clone (#9)")
        assertAbsent(src, "skinBase.ApplyPixelBackdrop(frame, skinBase.CHROME.BORDER_PX",
            f .. " must not bypass the shared chrome policy (#9)")
    end

    local characterPane = readFile("QUI_Skinning/skinning/character_pane/character.lua")
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
