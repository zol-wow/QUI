-- tests/unit/global_default_font_standard_text_font_test.lua
-- Run: lua tests/unit/global_default_font_standard_text_font_test.lua
--
-- The taint-safe "global font" lever is the engine path-string global
-- STANDARD_TEXT_FONT (NOT root font-object SetFont, which taints secure UI).
-- This pins: enabled + Latin locale sets it to the QUI font and captures the
-- original; CJK locale leaves the Blizzard default; toggling off restores it.

function LibStub() return nil end

-- Real Helpers (provides GetLocaleGlyphFallback + CreateStateTable used at load).
local utilsNs = {}
assert(loadfile("core/utils.lua"))("QUI", utilsNs)
local Helpers = utilsNs.Helpers

local QUII = [[Interface\AddOns\QUI\assets\Quazii.ttf]]
local QUICore = {}
QUICore.db = { profile = { general = { applyGlobalFontToBlizzard = true, font = "Quazii" } } }

local ns = {
    Addon = QUICore,
    LSM = { Fetch = function(_, _, name) return QUII end },
    Helpers = Helpers,
}
assert(loadfile("core/font_system.lua"))("QUI", ns)
assert(type(QUICore.ApplyGlobalDefaultFont) == "function",
    "QUICore:ApplyGlobalDefaultFont should be defined")

local function setLocale(code) _G.GetLocale = function() return code end end

-- Latin client, enabled: sets STANDARD_TEXT_FONT to the QUI font, captures orig.
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
setLocale("enUS")
QUICore:ApplyGlobalDefaultFont()
assert(_G.STANDARD_TEXT_FONT == QUII, "enUS+enabled should set the QUI font")

-- Disabled: restores the original captured path.
QUICore.db.profile.general.applyGlobalFontToBlizzard = false
QUICore:ApplyGlobalDefaultFont()
assert(_G.STANDARD_TEXT_FONT == "Fonts\\FRIZQT__.TTF", "disabled should restore original")

-- CJK client, enabled: must NOT override (leave Blizzard default).
QUICore.db.profile.general.applyGlobalFontToBlizzard = true
_G.STANDARD_TEXT_FONT = "Fonts\\ARKai_T.ttf"
setLocale("zhCN")
QUICore:ApplyGlobalDefaultFont()
assert(_G.STANDARD_TEXT_FONT == "Fonts\\ARKai_T.ttf", "zhCN should leave Blizzard default")

print("global_default_font_standard_text_font_test: PASS")
