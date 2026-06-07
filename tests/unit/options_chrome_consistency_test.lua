-- tests/unit/options_chrome_consistency_test.lua
-- Run: lua tests/unit/options_chrome_consistency_test.lua
-- Phase-2 batch-a structural gate: options UI internal chrome consolidation.
-- Asserts that GUI.* constants are defined in framework.lua and that
-- the migrated hardcoded literals are gone (replaced by the constants).

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path); local t = fh:read("*a"); fh:close(); return t
end
local function assertAbsent(text, patt, why) assert(not text:find(patt), why) end
local function assertContains(text, needle, why) assert(text:find(needle, 1, true), why) end

-- ===========================================================================
-- QUI_Options/framework.lua
-- ===========================================================================
do
    local src = readFile("QUI_Options/framework.lua")

    -- Constants must be defined
    assertContains(src, "GUI.DIALOG_BUTTON_BG",
        "framework.lua: GUI.DIALOG_BUTTON_BG constant must be defined")
    assertContains(src, "GUI.CHECKBOX_BG",
        "framework.lua: GUI.CHECKBOX_BG constant must be defined")
    assertContains(src, "GUI.SLIDER_BG",
        "framework.lua: GUI.SLIDER_BG constant must be defined")
    assertContains(src, "GUI.GRID_BG",
        "framework.lua: GUI.GRID_BG constant must be defined")
    assertContains(src, "GUI.BORDER_INACTIVE",
        "framework.lua: GUI.BORDER_INACTIVE constant must be defined")
    assertContains(src, "GUI.BORDER_SWATCH",
        "framework.lua: GUI.BORDER_SWATCH constant must be defined")
    assertContains(src, "GUI.ERROR_TEXT",
        "framework.lua: GUI.ERROR_TEXT constant must be defined")
    assertContains(src, "GUI.DESCRIPTION_TEXT",
        "framework.lua: GUI.DESCRIPTION_TEXT constant must be defined")

    -- Hardcoded 0.15,0.15,0.15,1 dialog-button bg must be gone from framework.lua
    assertAbsent(src, "SetBackdropColor%(0%.15, 0%.15, 0%.15, 1%)",
        "framework.lua: SetBackdropColor(0.15,0.15,0.15,1) must be replaced by GUI.DIALOG_BUTTON_BG")

    -- Hardcoded 0.3,0.3,0.3,1 inactive border must be gone from framework.lua
    assertAbsent(src, "SetBackdropBorderColor%(0%.3, 0%.3, 0%.3, 1%)",
        "framework.lua: SetBackdropBorderColor(0.3,0.3,0.3,1) must be replaced by GUI.BORDER_INACTIVE")

    -- Hardcoded 0.1,0.1,0.1,1 checkbox/slider bg must be gone from framework.lua
    -- (the 0.1,0.2,0.15,1 hover variant is semantic and must remain)
    assertAbsent(src, "SetBackdropColor%(0%.1, 0%.1, 0%.1, 1%)",
        "framework.lua: SetBackdropColor(0.1,0.1,0.1,1) must be replaced by GUI.CHECKBOX_BG / GUI.SLIDER_BG")

    -- Hardcoded 0.4,0.4,0.4,1 swatch border must be gone from framework.lua
    assertAbsent(src, "SetBackdropBorderColor%(0%.4, 0%.4, 0%.4, 1%)",
        "framework.lua: SetBackdropBorderColor(0.4,0.4,0.4,1) must be replaced by GUI.BORDER_SWATCH")

    -- GUI.Colors block must remain (options surface stays separate from skin)
    assertContains(src, "GUI.Colors = GUI.Colors or {",
        "framework.lua: GUI.Colors block must not be removed (options surface is separate from skin)")

    -- Must reference the constants via unpack() or spread (not the raw literals)
    assertContains(src, "GUI.DIALOG_BUTTON_BG",
        "framework.lua: must reference GUI.DIALOG_BUTTON_BG")
    assertContains(src, "GUI.BORDER_INACTIVE",
        "framework.lua: must reference GUI.BORDER_INACTIVE")
end

-- ===========================================================================
-- core/settings/content/anchoring_shared_content.lua
-- ===========================================================================
do
    local src = readFile("core/settings/content/anchoring_shared_content.lua")

    -- Hardcoded 0.15,0.15,0.15,1 dialog-button bg must be gone
    assertAbsent(src, "SetBackdropColor%(0%.15, 0%.15, 0%.15, 1%)",
        "anchoring_shared_content.lua: SetBackdropColor(0.15,0.15,0.15,1) must be replaced by GUI.DIALOG_BUTTON_BG")

    -- Hardcoded 0.1,0.1,0.1,1 grid bg must be gone
    assertAbsent(src, "SetBackdropColor%(0%.1, 0%.1, 0%.1, 1%)",
        "anchoring_shared_content.lua: SetBackdropColor(0.1,0.1,0.1,1) must be replaced by GUI.GRID_BG")

    -- Must reference GUI.DIALOG_BUTTON_BG and GUI.GRID_BG
    assertContains(src, "GUI.DIALOG_BUTTON_BG",
        "anchoring_shared_content.lua: must reference GUI.DIALOG_BUTTON_BG")
    assertContains(src, "GUI.GRID_BG",
        "anchoring_shared_content.lua: must reference GUI.GRID_BG")
end

-- ===========================================================================
-- core/settings/content/import_export_content.lua
-- ===========================================================================
do
    local src = readFile("core/settings/content/import_export_content.lua")

    -- Hardcoded FRIZQT__ fallback must be gone; must use GetFontPath()
    assertAbsent(src, 'GUI%.FONT_PATH or "Fonts\\\\FRIZQT',
        "import_export_content.lua: GUI.FONT_PATH or FRIZQT fallback must use GUI:GetFontPath()")

    -- Must reference GetFontPath
    assertContains(src, "GetFontPath",
        "import_export_content.lua: must reference GUI:GetFontPath()")
end

-- ===========================================================================
-- core/settings/content/profiles_content.lua
-- ===========================================================================
do
    local src = readFile("core/settings/content/profiles_content.lua")

    -- Hardcoded error red 0.9,0.3,0.3 must be gone
    assertAbsent(src, "SetTextColor%(0%.9, 0%.3, 0%.3, 1%)",
        "profiles_content.lua: SetTextColor(0.9,0.3,0.3,1) must be replaced by GUI.ERROR_TEXT")

    -- Must reference GUI.ERROR_TEXT
    assertContains(src, "GUI.ERROR_TEXT",
        "profiles_content.lua: must reference GUI.ERROR_TEXT")
end

-- ===========================================================================
-- core/settings/content/modules_page.lua
-- ===========================================================================
do
    local src = readFile("core/settings/content/modules_page.lua")

    -- Hardcoded near-white 0.953,0.957,0.965 must be gone; use C.text
    assertAbsent(src, "SetTextColor%(0%.953, 0%.957, 0%.965, 1%)",
        "modules_page.lua: SetTextColor(0.953,0.957,0.965,1) must use C.text")

    -- C.text must be referenced (it already exists, so this guards against removal)
    assertContains(src, "C.text",
        "modules_page.lua: must reference C.text for name label color")
end

-- ===========================================================================
-- QUI_UnitFrames/unitframes/settings/unit_frames_schema.lua
-- ===========================================================================
do
    local src = readFile("QUI_UnitFrames/unitframes/settings/unit_frames_schema.lua")

    -- The local DESCRIPTION_TEXT_COLOR constant must still exist (the
    -- table definition uses 0.5,0.5,0.5 — that's fine as it's a local const)
    assertContains(src, "DESCRIPTION_TEXT_COLOR",
        "unit_frames_schema.lua: DESCRIPTION_TEXT_COLOR local must remain")

    -- The two stray inline SetTextColor(0.5,0.5,0.5,1) calls must be gone
    -- (they should reference DESCRIPTION_TEXT_COLOR, not inline the literal)
    assertAbsent(src, "label:SetTextColor%(0%.5, 0%.5, 0%.5, 1%)",
        "unit_frames_schema.lua: inline label:SetTextColor(0.5,0.5,0.5,1) must use DESCRIPTION_TEXT_COLOR")
end

-- ===========================================================================
-- QUI_ActionBars/actionbars/settings/action_bars_preview_driver.lua
-- ===========================================================================
do
    local src = readFile("QUI_ActionBars/actionbars/settings/action_bars_preview_driver.lua")

    -- Hardcoded FRIZQT__ literal must be gone from GetPreviewFontSettings
    assertAbsent(src, '"Fonts\\\\FRIZQT',
        "action_bars_preview_driver.lua: hardcoded FRIZQT__.TTF must use GUI:GetFontPath() fallback")

    -- Must reference GetFontPath
    assertContains(src, "GetFontPath",
        "action_bars_preview_driver.lua: must reference GetFontPath for font fallback")
end

-- ===========================================================================
-- Phase-2 batch-b: GUI:OnFontChanged wiring
-- ===========================================================================
do
    local fw  = readFile("QUI_Options/framework.lua")
    local fnt = readFile("core/font_system.lua")

    -- framework.lua must define the OnFontChanged method
    assert(
        fw:find("function GUI:OnFontChanged") or fw:find("GUI%.OnFontChanged%s*="),
        "framework.lua: must define function GUI:OnFontChanged"
    )

    -- The wiring must exist: either font_system.lua calls OnFontChanged, or
    -- framework.lua registers it with ns.Registry for font/skin group changes.
    local wiredInFontSystem  = fnt:find("OnFontChanged", 1, true)
    local wiredInFramework   = fw:find("OnFontChanged.*Registry", 1, false)
                            or fw:find("Registry.*OnFontChanged", 1, false)
    assert(
        wiredInFontSystem or wiredInFramework,
        "OnFontChanged must be wired: font_system.lua must reference it, " ..
        "or framework.lua must register it with ns.Registry"
    )
end

-- ===========================================================================
-- QUI_GroupFrames/groupframes/settings/click_cast_content.lua
-- ===========================================================================
do
    local src = readFile("QUI_GroupFrames/groupframes/settings/click_cast_content.lua")

    assertContains(src, 'UIKit.RegisterScaleRefresh(content, "clickCastPixelFrames", RefreshClickCastPixelFrames)',
        "click_cast_content.lua: click-cast scale refresh should only refresh existing pixel frames")

    local callbackBody = src:match('UIKit%.RegisterScaleRefresh%(%s*content%s*,%s*"clickCastPixelFrames"%s*,%s*function%b()%s*(.-)%s*end%s*%)')
    assert(not callbackBody or not callbackBody:find("RefreshBindingList", 1, true),
        "click_cast_content.lua: click-cast scale refresh must not rebuild binding rows")

    assertContains(src, "content._quiClickCastCleanupHooked",
        "click_cast_content.lua: click-cast hide cleanup hook should guard duplicate registration")
end

-- ===========================================================================
-- QUI_GroupFrames/groupframes/settings/group_frames_aura_indicators_editor.lua
-- ===========================================================================
do
    local src = readFile("QUI_GroupFrames/groupframes/settings/group_frames_aura_indicators_editor.lua")

    assertContains(src, "local function RebuildAuraList(ctx)",
        "group_frames_aura_indicators_editor.lua: aura rebuild should live in a file-level helper")
    assertContains(src, "RebuildAuraList(editor)",
        "group_frames_aura_indicators_editor.lua: local rebuild wrapper should delegate to the helper")
    assertAbsent(src, "\n%s*selectedAuraIndex%s*=%s*math%.max",
        "group_frames_aura_indicators_editor.lua: bare selectedAuraIndex assignments must use editor/ctx state")
    assertAbsent(src, "\n%s*selectedIndicatorIndex%s*=%s*math%.max",
        "group_frames_aura_indicators_editor.lua: bare selectedIndicatorIndex assignments must use editor/ctx state")
end

print("OK: options_chrome_consistency_test")
