-- tests/unit/addon_chrome_consistency_test.lua
-- Run: lua tests/unit/addon_chrome_consistency_test.lua
-- Phase-1 structural gate: no incidental chrome literal survives the sweep
-- in damage_meter.lua and minimap.lua.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path); local t = fh:read("*a"); fh:close(); return t
end
local function assertAbsent(text, patt, why) assert(not text:find(patt), why) end
local function assertContains(text, needle, why) assert(text:find(needle, 1, true), why) end

-- ===========================================================================
-- damage_meter.lua
-- ===========================================================================
do
    local src = readFile("QUI_DamageMeter/damage_meter/damage_meter.lua")

    -- Row-bg hardcoded dark gone; must route through GetDepthColor("ROW")
    assertAbsent(src, "0%.05, 0%.05, 0%.05, 0%.55",
        "damage_meter.lua: row BarBg literal 0.05,0.05,0.05,0.55 must use GetDepthColor(\"ROW\")")

    -- Window-bg fallback literal gone; must source RGB from GetSkinBgColor()
    assertAbsent(src, "{ 0, 0, 0, 0%.85 }",
        "damage_meter.lua: window-bg fallback { 0, 0, 0, 0.85 } must source RGB from GetSkinBgColor()")

    -- Confirm the skinning API is now referenced
    assertContains(src, "GetDepthColor",
        "damage_meter.lua: must reference GetDepthColor for row chrome")
    assertContains(src, "GetSkinBgColor",
        "damage_meter.lua: must reference GetSkinBgColor for window-bg fallback")

    -- Semantic guard: class-color path must remain untouched
    assertContains(src, "RAID_CLASS_COLORS",
        "damage_meter.lua: semantic RAID_CLASS_COLORS must not be removed")
end

-- ===========================================================================
-- minimap.lua
-- ===========================================================================
do
    local src = readFile("QUI_Minimap/minimap/minimap.lua")

    -- Great-vault button: raw backdrop with hardcoded 0,0,0,0.8 gone
    assertAbsent(src, "SetBackdropColor%(0, 0, 0, 0%.8%)",
        "minimap.lua: great-vault button SetBackdropColor(0,0,0,0.8) must use GetSkinBgColor()")

    -- Datatext panel bg: hardcoded 0,0,0 rgb (with settings alpha) gone;
    -- must now source RGB from GetSkinBgColor()
    assertAbsent(src, "SetColorTexture%(0, 0, 0, bgAlpha%)",
        "minimap.lua: datatext bg SetColorTexture(0,0,0,bgAlpha) must source RGB from GetSkinBgColor()")

    -- Drawer toggle button overlay: hardcoded 0.05,0.05,0.05,0.9 gone
    assertAbsent(src, "SetColorTexture%(0%.05, 0%.05, 0%.05, 0%.9%)",
        "minimap.lua: drawer overlay 0.05,0.05,0.05,0.9 must source RGB from GetSkinBgColor()/GetDepthColor")

    -- Confirm the skinning API is now referenced in minimap
    assertContains(src, "GetSkinBgColor",
        "minimap.lua: must reference GetSkinBgColor")

    -- Semantic guard: existing live-theme minimap border path must remain
    assertContains(src, "GetSkinBorderColor",
        "minimap.lua: GetSkinBorderColor theme path must not be removed")
end

-- ===========================================================================
-- petwarning.lua
-- ===========================================================================
do
    local src = readFile("QUI_QoL/qol/petwarning.lua")

    -- Migrated dark bg literal must be gone
    assertAbsent(src, "SetBackdropColor%(0%.1, 0%.1, 0%.1, 0%.9%)",
        "petwarning.lua: raw SetBackdropColor(0.1,0.1,0.1,0.9) must use GetSkinBgColor()")

    -- Skin bg API must now be referenced
    assertContains(src, "GetSkinBgColor",
        "petwarning.lua: must reference GetSkinBgColor for bg color")

    -- Semantic guard: red warning border must remain
    assertContains(src, "1, 0.3, 0.3",
        "petwarning.lua: semantic red warning border literal 1,0.3,0.3 must not be removed")
end

-- ===========================================================================
-- consumablecheck.lua
-- ===========================================================================
do
    local src = readFile("QUI_QoL/qol/consumablecheck.lua")

    -- Migrated dark bg literal must be gone (the raw SetBackdropColor call)
    assertAbsent(src, "SetBackdropColor%(0%.05, 0%.05, 0%.05, 0%.95%)",
        "consumablecheck.lua: raw SetBackdropColor(0.05,0.05,0.05,0.95) must use GetSkinBgColor()")

    -- Skin bg and border APIs must now be referenced
    assertContains(src, "GetSkinBgColor",
        "consumablecheck.lua: must reference GetSkinBgColor for picker bg")
    assertContains(src, "GetSkinBorderColor",
        "consumablecheck.lua: must reference GetSkinBorderColor for picker border")
end

-- ===========================================================================
-- combattimer.lua
-- ===========================================================================
do
    local src = readFile("QUI_QoL/qol/combattimer.lua")

    -- Migrated hardcoded initial bg literal must be gone
    assertAbsent(src, "SetBackdropColor%(0, 0, 0, 0%.6%)",
        "combattimer.lua: raw SetBackdropColor(0,0,0,0.6) must use GetSkinBgColor()")

    -- Skin bg API must now be referenced
    assertContains(src, "GetSkinBgColor",
        "combattimer.lua: must reference GetSkinBgColor for initial backdrop bg")
end

-- ===========================================================================
-- combattext.lua  (batch c)
-- ===========================================================================
do
    local src = readFile("QUI_QoL/combat/combattext.lua")

    -- Hardcoded font path must be gone
    assertAbsent(src, "Fonts\\\\FRIZQT__%.TTF",
        "combattext.lua: hardcoded FRIZQT__.TTF font path must use GetGeneralFont()")

    -- GetGeneralFont must now be referenced
    assertContains(src, "GetGeneralFont",
        "combattext.lua: must reference GetGeneralFont()")

    -- Semantic guard: sky-blue combat indicator color must remain
    assertContains(src, "0.376, 0.647, 0.980",
        "combattext.lua: semantic sky-blue text color 0.376,0.647,0.980 must not be removed")
end

-- ===========================================================================
-- rotationassist.lua  (batch c)
-- ===========================================================================
do
    local src = readFile("QUI_QoL/combat/rotationassist.lua")

    -- STANDARD_TEXT_FONT at the initial keybind-create site must be gone
    -- (the fallback in the LSM fetch is also migrated)
    assertAbsent(src, "STANDARD_TEXT_FONT",
        "rotationassist.lua: STANDARD_TEXT_FONT must be replaced with GetGeneralFont()")

    -- GetGeneralFont must now be referenced
    assertContains(src, "GetGeneralFont",
        "rotationassist.lua: must reference GetGeneralFont()")

    -- GetSkinBgColor must now be referenced for the transparent bg guard
    assertContains(src, "GetSkinBgColor",
        "rotationassist.lua: must reference GetSkinBgColor() for bg color guard")

    -- Semantic guards: SafeSetBackdrop usage and green ready-state border must remain
    assertContains(src, "SafeSetBackdrop",
        "rotationassist.lua: SafeSetBackdrop usage must not be removed")
    assertContains(src, "0, 1, 0, 1",
        "rotationassist.lua: semantic green ready-state border 0,1,0,1 must not be removed")
end

-- ===========================================================================
-- atonement_counter.lua  (batch c)
-- ===========================================================================
do
    local src = readFile("QUI_QoL/trackers/atonement_counter.lua")

    -- GetGeneralFontOutline must now be referenced (replaces hardcoded "OUTLINE")
    assertContains(src, "GetGeneralFontOutline",
        "atonement_counter.lua: must reference GetGeneralFontOutline()")

    -- GetSkinBgColor must now be referenced
    assertContains(src, "GetSkinBgColor",
        "atonement_counter.lua: must reference GetSkinBgColor() for transparent bg guard")

    -- Semantic guards: SafeSetBackdrop and charge-state colors must remain
    assertContains(src, "SafeSetBackdrop",
        "atonement_counter.lua: SafeSetBackdrop usage must not be removed")
end

-- ===========================================================================
-- preytracker.lua  (batch c)
-- ===========================================================================
do
    local src = readFile("QUI_QoL/trackers/preytracker.lua")

    -- Hardcoded gray border literal must be gone from the CreateHuntPanel area
    assertAbsent(src, "0%.3, 0%.3, 0%.3",
        "preytracker.lua: hardcoded gray border 0.3,0.3,0.3 must use GetSkinBorderColor()")

    -- STANDARD_TEXT_FONT in the hunt-panel section must be replaced
    -- (other STANDARD_TEXT_FONT usages outside the migrated block are not in scope)
    assertContains(src, "GetGeneralFont",
        "preytracker.lua: must reference GetGeneralFont() for hunt panel fonts")

    -- GetSkinBorderColor must now be referenced
    assertContains(src, "GetSkinBorderColor",
        "preytracker.lua: must reference GetSkinBorderColor() for hunt panel border")

    -- Semantic guard: orange hunt-title color must remain
    assertContains(src, "1, 0.82, 0",
        "preytracker.lua: semantic orange hunt-title color 1,0.82,0 must not be removed")
end

-- ===========================================================================
-- resourcebars.lua  (batch c)
-- ===========================================================================
do
    local src = readFile("QUI_ResourceBars/resourcebars/resourcebars.lua")

    -- Raw SetBackdrop dict on charged overlay must be gone
    -- (the only non-semantic SetBackdrop in the charged-overlay path)
    assertAbsent(src, 'overlay:SetBackdrop%(',
        "resourcebars.lua: raw overlay:SetBackdrop() must use SkinBase.ApplyPixelBackdrop")

    -- SkinBase.ApplyPixelBackdrop must now be referenced
    assertContains(src, "SkinBase.ApplyPixelBackdrop",
        "resourcebars.lua: must reference SkinBase.ApplyPixelBackdrop for charged overlay border")

    -- Semantic guard: chargedColor must remain
    assertContains(src, "chargedColor",
        "resourcebars.lua: semantic chargedColor must not be removed")
end

-- ===========================================================================
-- composer.lua  (batch d)
-- ===========================================================================
do
    local src = readFile("QUI_CDM/cdm/settings/composer.lua")

    -- Main panel bg literal must be gone from SetSimpleBackdrop / SetColorTexture callers
    assertAbsent(src, "SetSimpleBackdrop%(container, 0%.08, 0%.08, 0%.1",
        "composer.lua: hardcoded 0.08,0.08,0.1 panel bg in SetSimpleBackdrop must use GetSkinBgColor/GetDepthColor")
    assertAbsent(src, "SetSimpleBackdrop%(container, 0%.06, 0%.06, 0%.08",
        "composer.lua: hardcoded 0.06,0.06,0.08 panel bg in SetSimpleBackdrop must use GetDepthColor(PANEL)")
    assertAbsent(src, "SetSimpleBackdrop%(container, 0%.04, 0%.04, 0%.06",
        "composer.lua: hardcoded 0.04,0.04,0.06 subpanel bg in SetSimpleBackdrop must use GetDepthColor(SUBPANEL)")

    -- Main frame bg SetColorTexture literal must be gone
    assertAbsent(src, "SetColorTexture%(0%.06, 0%.06, 0%.08, 0%.97%)",
        "composer.lua: main frame bg SetColorTexture(0.06,0.06,0.08,0.97) must use GetChromeBgPanel/GetDepthColor")

    -- Generic gray border literals in SetSimpleBackdrop must be gone
    assertAbsent(src, "SetSimpleBackdrop%(btn, 0%.12, 0%.12, 0%.15, 0%.9, 0%.3, 0%.3, 0%.3, 1%)",
        "composer.lua: small button SetSimpleBackdrop with 0.3 border must use GetSkinBorderColor")
    assertAbsent(src, "SetSimpleBackdrop%(box, 0%.06, 0%.06, 0%.08, 1, 0%.25, 0%.25, 0%.25, 1%)",
        "composer.lua: search box SetSimpleBackdrop with 0.25 border must use GetSkinBorderColor")

    -- Popup bg literals must be gone
    assertAbsent(src, "SetBackdropColor%(0%.08, 0%.08, 0%.1, 0%.98%)",
        "composer.lua: popup SetBackdropColor(0.08,0.08,0.1,0.98) must use GetSkinBgColor/GetDepthColor")

    -- Nav bg literal must be gone
    assertAbsent(src, "SetColorTexture%(0%.04, 0%.04, 0%.06, 1%)",
        "composer.lua: nav bg SetColorTexture(0.04,0.04,0.06,1) must use GetDepthColor(SUBPANEL)")

    -- Skin APIs must now be referenced
    assertContains(src, "GetSkinBgColor",
        "composer.lua: must reference GetSkinBgColor for panel chrome bg")
    assertContains(src, "GetSkinBorderColor",
        "composer.lua: must reference GetSkinBorderColor for panel chrome border")
    assertContains(src, "GetGeneralFont",
        "composer.lua: must reference GetGeneralFont for font chrome")

    -- Semantic guard: accent-multiplier pattern must remain (button highlight/selected states)
    assertContains(src, "ACCENT_R * 0.",
        "composer.lua: accent-multiplier pattern (ACCENT_R * 0.x) must not be removed — semantic button colors")
end

-- ===========================================================================
-- chat/chat.lua  (Phase 3 batch a — chat window chrome)
-- ===========================================================================
do
    local src = readFile("QUI_Chat/chat/chat.lua")

    -- Old hardcoded palette fallback for bg must be gone from GetChatSurfaceColors;
    -- the function now sources bg RGB from the skin API.
    assertAbsent(src, "glass and glass%.bgColor%) or {0, 0, 0}",
        "chat.lua: GetChatSurfaceColors must not use the old glass.bgColor/{0,0,0} fallback — source from GetSkinBgColorWithOverride")

    -- Skin bg API must now be referenced in chat.lua chrome path.
    assertContains(src, "GetSkinBgColorWithOverride",
        "chat.lua: must reference GetSkinBgColorWithOverride for chat window bg")
    assertContains(src, "GetSkinBgColor",
        "chat.lua: must reference GetSkinBgColor as fallback in GetChatSurfaceColors")

    -- Skin border API must now be referenced in chat.lua chrome path.
    assertContains(src, "GetSkinBorderColor",
        "chat.lua: must reference GetSkinBorderColor for chat window border")

    -- Semantic guard: sender class coloring lives in message_format.lua now
    -- (the rendered-path class_colors modifier was excised with the takeover).
    local fmt = readFile("QUI_Chat/chat/message_format.lua")
    assertContains(fmt, "RAID_CLASS_COLORS",
        "message_format.lua: semantic RAID_CLASS_COLORS sender coloring must not be removed")
end

-- ===========================================================================
-- mplus_timer.lua  (Phase 3 batch b)
-- ===========================================================================
do
    local src = readFile("QUI_QoL/dungeon/mplus_timer.lua")

    -- Hardcoded FRIZQT font path in GetForcesFont fallback must be gone
    assertAbsent(src, "Fonts\\\\FRIZQT__%.TTF",
        "mplus_timer.lua: hardcoded FRIZQT__.TTF fallback in GetForcesFont must use Helpers.GetGeneralFont()")

    -- GetGeneralFont must now be referenced (for GetGlobalFont + GetForcesFont fallback)
    assertContains(src, "GetGeneralFont",
        "mplus_timer.lua: must reference GetGeneralFont()")

    -- Skin bg API must now be referenced for progress bar and sleek bar backdrops
    assertContains(src, "GetSkinBgColor",
        "mplus_timer.lua: must reference GetSkinBgColor() for progress bar / sleek bar backdrop bg")

    -- SkinBase.CreateBackdrop must now be referenced
    assertContains(src, "SkinBase.CreateBackdrop",
        "mplus_timer.lua: must reference SkinBase.CreateBackdrop for bar container and sleek bar frames")

    -- Semantic guard: M+ tier segment colors must remain untouched
    assertContains(src, "0.2, 0.85, 0.4",
        "mplus_timer.lua: semantic +3 green tier color 0.2,0.85,0.4 must not be removed")
    assertContains(src, "0.95, 0.75, 0.2",
        "mplus_timer.lua: semantic +2 yellow tier color 0.95,0.75,0.2 must not be removed")
    assertContains(src, "0.4, 0.7, 0.9",
        "mplus_timer.lua: semantic +1 blue tier color 0.4,0.7,0.9 must not be removed")
end

-- ===========================================================================
-- groupframes (Phase 4 batch a — TAINT-SENSITIVE: value-only border migration)
-- The migrated neutral black chrome-border literals SetBackdropBorderColor(0,0,0,1)
-- must be gone from the listed spots and routed through GetSkinBorderColor().
-- The secure SetBackdropFillColor / frame.Center forwarder and all semantic
-- dispel/debuff colors must remain byte-for-byte.
-- ===========================================================================
-- NOTE: groupframes_indicators.lua and groupframes_pinned_auras.lua were
-- deleted when the unified aura element renderer became the sole aura consumer,
-- and groupframes_auras.lua's icon-creation/dispel-color code (which the chrome
-- guard covered) moved to groupframes_aura_render.lua. Those file-specific
-- chrome assertions were removed with the code they guarded.

do
    -- groupframes_layout.lua: decorated-frame chrome border + portrait chrome border migrated
    local layoutSrc = readFile("QUI_GroupFrames/groupframes/groupframes_layout.lua")
    assertAbsent(layoutSrc, "SetBackdropBorderColor%(0, 0, 0, 1%)",
        "groupframes_layout.lua: black chrome borders SetBackdropBorderColor(0,0,0,1) must use GetSkinBorderColor()")
    assertContains(layoutSrc, "GetSkinBorderColor",
        "groupframes_layout.lua: must reference GetSkinBorderColor() for frame/portrait chrome border")

    -- Secure taint-mitigation forwarder must remain byte-for-byte (mechanism, not value)
    local parentSrc = readFile("QUI_GroupFrames/groupframes/groupframes.lua")
    assertContains(parentSrc, "local function SetBackdropFillColor(frame, r, g, b, a)",
        "groupframes.lua: secure SetBackdropFillColor forwarder definition must not be altered")
    assertContains(parentSrc, "center:SetVertexColor(r, g, b, a)",
        "groupframes.lua: secure forwarder frame.Center:SetVertexColor mechanism must not be altered")
    assertContains(layoutSrc, "SetBackdropFillColor(frame, bgColor[1], bgColor[2], bgColor[3], bgAlpha)",
        "groupframes_layout.lua: secure fill forwarder call (bgColor) must not be altered")
end

do
    -- groupframes_editmode.lua: edit-mode preview frame border migrated (0.15 gray gone)
    local src = readFile("QUI_GroupFrames/groupframes/groupframes_editmode.lua")
    assertAbsent(src, "SetBackdropBorderColor%(0%.15, 0%.15, 0%.15, 1%)",
        "groupframes_editmode.lua: preview frame border 0.15,0.15,0.15,1 must use GetSkinBorderColor()")
    assertContains(src, "GetSkinBorderColor",
        "groupframes_editmode.lua: must reference GetSkinBorderColor() for preview frame border")
end

-- ===========================================================================
-- raidbuffs.lua (Phase 4 batch a — fonts + bg value-only migration + refresh wiring)
-- ===========================================================================
do
    local src = readFile("QUI_GroupFrames/groupframes/raidbuffs.lua")

    -- Migrated STANDARD_TEXT_FONT spots (countText create, label create, label reflow)
    -- must be gone; they now use Helpers.GetGeneralFont()/GetGeneralFontOutline().
    -- (The user-configurable buff-count font LSM fallback is out of scope.)
    assertAbsent(src, "SetFont%(STANDARD_TEXT_FONT, 10, \"OUTLINE\"%)",
        "raidbuffs.lua: migrated SetFont(STANDARD_TEXT_FONT, 10, \"OUTLINE\") must use GetGeneralFont()/GetGeneralFontOutline()")
    assertAbsent(src, "SetFont%(STANDARD_TEXT_FONT, fontSize, \"OUTLINE\"%)",
        "raidbuffs.lua: migrated label reflow SetFont(STANDARD_TEXT_FONT, fontSize, ...) must use GetGeneralFont()/GetGeneralFontOutline()")

    -- Migrated hardcoded backdrop bg literals must be gone (RGB now from GetSkinBgColor).
    assertAbsent(src, "SetBackdropColor%(0, 0, 0, 0%.8%)",
        "raidbuffs.lua: backdrop bg SetBackdropColor(0,0,0,0.8) must source RGB from GetSkinBgColor()")
    assertAbsent(src, "SetBackdropColor%(0%.05, 0%.05, 0%.05, 0%.95%)",
        "raidbuffs.lua: label bar bg SetBackdropColor(0.05,0.05,0.05,0.95) must source RGB from GetSkinBgColor()")

    -- Skin/font APIs must now be referenced.
    assertContains(src, "GetGeneralFont",
        "raidbuffs.lua: must reference GetGeneralFont() for buff/label fonts")
    assertContains(src, "GetGeneralFontOutline",
        "raidbuffs.lua: must reference GetGeneralFontOutline() for buff/label fonts")
    assertContains(src, "GetSkinBgColor",
        "raidbuffs.lua: must reference GetSkinBgColor() for backdrop bg RGB")

    -- Live-refresh wiring: a skinning-group Registry registration must exist so a
    -- global skin/font change (RefreshAll(\"skinning\")) re-applies the buff display.
    assertContains(src, "\"raidbuffsSkin\"",
        "raidbuffs.lua: must register a distinct skinning-group refresh (raidbuffsSkin)")
    assertContains(src, "group = \"skinning\"",
        "raidbuffs.lua: skinning-group refresh registration must use group = \"skinning\"")
end

-- ===========================================================================
-- unitframes.lua (Phase 4 batch b — MOST TAINT-SENSITIVE: value-only migration)
-- Neutral chrome bg fallback {0.1, 0.1, 0.1, 0.9} and neutral black chrome
-- border SetFrameBackdropBorderColor(0,0,0,1) must be gone from the migrated
-- secure-frame backdrop spots; RGB now sourced from GetSkinBgColor() /
-- GetSkinBorderColor(). The SetBackdrop mechanism, SetFrameBackdropColor
-- forwarder, darkMode/defaultBgColor user values, and all semantic
-- class/portrait/target-highlight colors must remain.
-- ===========================================================================
do
    local src = readFile("QUI_UnitFrames/unitframes/unitframes.lua")

    -- Migrated neutral chrome bg fallback literal must be gone (all 4 spots).
    assertAbsent(src, "{ 0%.1, 0%.1, 0%.1, 0%.9 }",
        "unitframes.lua: neutral chrome bg fallback { 0.1, 0.1, 0.1, 0.9 } must source RGB from GetSkinBgColor()")

    -- Migrated neutral black chrome border literal must be gone from the
    -- SetFrameBackdropBorderColor frame-outline calls.
    assertAbsent(src, "SetFrameBackdropBorderColor%(frame, 0, 0, 0, 1%)",
        "unitframes.lua: neutral black chrome border SetFrameBackdropBorderColor(frame,0,0,0,1) must use GetSkinBorderColor()")

    -- Skin APIs must now be referenced for chrome bg/border.
    assertContains(src, "GetSkinBgColor",
        "unitframes.lua: must reference GetSkinBgColor() for frame chrome bg fallback")
    assertContains(src, "GetSkinBorderColor",
        "unitframes.lua: must reference GetSkinBorderColor() for frame chrome border")

    -- Mechanism guard: the secure SetBackdrop call shape and the
    -- SetFrameBackdropColor forwarder must remain (not restructured).
    assertContains(src, "frame:SetBackdrop({",
        "unitframes.lua: secure frame:SetBackdrop({...}) mechanism must not be removed/restructured")
    assertContains(src, "Helpers.SetFrameBackdropColor(frame, bgColor[1], bgColor[2], bgColor[3]",
        "unitframes.lua: SetFrameBackdropColor forwarder call (bgColor) must not be altered")

    -- User-value guard: darkMode bg user override path must remain byte-for-byte.
    assertContains(src, "general.darkModeBgColor or { 0.25, 0.25, 0.25, 1 }",
        "unitframes.lua: user darkModeBgColor override (and { 0.25,0.25,0.25,1 } default) must not be removed")

    -- Semantic guards: class-color path and secret-value health handling must remain.
    assertContains(src, "RAID_CLASS_COLORS",
        "unitframes.lua: semantic RAID_CLASS_COLORS class coloring must not be removed")
    assertContains(src, "GetUnitClassColor",
        "unitframes.lua: semantic GetUnitClassColor helper must not be removed")
end

-- ===========================================================================
-- chat/chat.lua — regression: user glass.bgColor override must be honoured
-- ===========================================================================
-- Phase 3 skinning consolidation changed GetChatSurfaceColors to source bg RGB
-- from GetSkinBgColorWithOverride(settings,"chat") only — silently dropping any
-- user colour set via the Background Color picker (which wrote glass.bgColor).
-- The minimal fix: GetChatSurfaceColors reads glass.bgColor and, when it is a
-- non-black value (i.e. the user explicitly picked a color), uses it directly
-- for the RGB; otherwise it falls through to GetSkinBgColorWithOverride so the
-- skin theme default still applies.  No schema migration, no new defaults keys.
-- This block verifies:
--   (a) chat.lua reads glass.bgColor and implements the userSet guard
--   (b) chat.lua still references GetSkinBgColorWithOverride (skin-default path)
do
    local chatSrc = readFile("QUI_Chat/chat/chat.lua")

    -- (a) The inline fix: glass.bgColor is read and a userSet guard decides
    --     whether to use it or fall back to the skin.
    assertContains(chatSrc, "glass.bgColor",
        "chat.lua: GetChatSurfaceColors must read glass.bgColor for the user-override path")
    assertContains(chatSrc, "userSet",
        "chat.lua: GetChatSurfaceColors must use a userSet guard to detect a non-black glass.bgColor")

    -- (b) Skin-default path must still be present (consolidation win preserved).
    assertContains(chatSrc, "GetSkinBgColorWithOverride",
        "chat.lua: GetSkinBgColorWithOverride must still be the skin-default bg RGB source")
    assertContains(chatSrc, "GetSkinBgColor",
        "chat.lua: GetSkinBgColor fallback must still be present for older Helpers API")
    -- (chatTab border machinery was excised with the takeover: Blizzard tabs
    -- are hidden; the QUI display's tab bar colors from theme text + accent.)
end

print("OK: addon_chrome_consistency_test")
