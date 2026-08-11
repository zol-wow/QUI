-- tests/unit/locale_positional_resolve_test.lua
-- Run: lua tests/unit/locale_positional_resolve_test.lua

local ns = {}
assert(loadfile("core/pack.lua"))("QUI", ns)

ns.LocaleData = {
    keys   = { "Alpha", "Beta", "Gamma" },
    active = { "Alfa",  nil,    "Gamma-DE" },
}

_G.GetLocale = function() return "deDE" end
_G.QUIDB = nil
assert(loadfile("core/locale/locale.lua"))("QUI", ns)

assert(ns.L["Alpha"] == "Alfa", "translated key must resolve to the overlay value")
assert(ns.L["Beta"] == "Beta", "untranslated key must fall back to the key itself")
assert(ns.L["Gamma"] == "Gamma-DE", "positional index must not drift")
assert(ns.L["Nonexistent"] == "Nonexistent", "unknown key must return itself")

print("OK: locale_positional_resolve_test")
