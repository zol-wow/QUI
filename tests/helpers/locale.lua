-- tests/helpers/locale.lua
-- Install the production ns.L metatable onto a test's ns table.
--
-- Settings/options modules index ns.L["..."] at file scope (post-i18n). In the
-- game, core/locale/locale.lua builds ns.L before any string consumer loads.
-- Isolated unit tests build their own ns and never run the locale chain, so
-- ns.L is nil and `ns.L["..."]` errors on load.
--
-- We load the real locale.lua (not a bespoke stub) so tests resolve strings
-- exactly as the game does. With no locale data seeded, L falls back to the
-- key itself, i.e. ns.L["Always"] == "Always" -- the English source string.
--
-- Usage (from a test, cwd = repo root):
--   local installLocale = dofile("tests/helpers/locale.lua")
--   installLocale(ns)
return function(ns)
    assert(loadfile("core/locale/locale.lua"))("QUI", ns)
    return ns
end
