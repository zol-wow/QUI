-- tests/unit/locale_glyph_fallback_test.lua
-- Run: lua tests/unit/locale_glyph_fallback_test.lua
--
-- The global default font (STANDARD_TEXT_FONT) must NOT point at the Latin-only
-- QUI font on CJK clients. This pins the locale gate: only koKR/zhCN/zhTW return
-- a system glyph font; Latin + ruRU return nil (Quazii covers their glyphs).

function LibStub() return nil end
local ns = {}
assert(loadfile("core/utils.lua"))("QUI", ns)
local H = ns.Helpers
local f = assert(H.GetLocaleGlyphFallback, "Helpers.GetLocaleGlyphFallback should be exported")

local function withLocale(code, fn)
    local prev = _G.GetLocale
    _G.GetLocale = function() return code end
    local ok, err = pcall(fn)
    _G.GetLocale = prev
    assert(ok, err)
end

withLocale("koKR", function() assert(f() == "Fonts\\2002.TTF", "koKR -> 2002") end)
withLocale("zhCN", function() assert(f() == "Fonts\\ARKai_T.ttf", "zhCN -> ARKai_T") end)
withLocale("zhTW", function() assert(f() == "Fonts\\blei00d.TTF", "zhTW -> blei00d") end)
withLocale("enUS", function() assert(f() == nil, "enUS -> nil (Quazii covers Latin)") end)
withLocale("deDE", function() assert(f() == nil, "deDE -> nil") end)
withLocale("ruRU", function() assert(f() == nil, "ruRU -> nil (Quazii has Cyrillic)") end)

print("locale_glyph_fallback_test: PASS")
