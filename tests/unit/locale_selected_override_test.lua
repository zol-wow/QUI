-- tests/unit/locale_selected_override_test.lua
-- Verifies a generated locale file honors QUIDB.global.selectedLocale over the
-- client GetLocale(), and falls back to GetLocale() when unset.
-- Run: lua tests/unit/locale_selected_override_test.lua

dofile("tools/_addon_env.lua")  -- defines GetLocale() honoring _G.QUI_TEST_LOCALE

local failures = 0
local function check(name, ok, detail)
    if ok then print(("  ok  %s"):format(name))
    else failures = failures + 1; print(("FAIL  %s  %s"):format(name, detail or "")) end
end

-- Load a single generated locale file in a controlled env. Returns whether the
-- file populated ns.LocaleData.active (i.e. the guard passed).
local function loadLocale(file, clientLocale, selected)
    _G.QUI_TEST_LOCALE = clientLocale
    _G.QUIDB = selected and { global = { selectedLocale = selected } } or { global = {} }
    local ns = { LocaleData = {} }
    local chunk = assert(loadfile(file))
    chunk("QUI", ns)
    return ns.LocaleData.active ~= nil
end

-- selectedLocale overrides the client locale
check("selected overrides client",
    loadLocale("core/locale/frFR.lua", "deDE", "frFR") == true,
    "frFR.lua should load when selectedLocale=frFR on a deDE client")

-- a non-matching selectedLocale keeps other files out
check("non-match stays out",
    loadLocale("core/locale/deDE.lua", "deDE", "frFR") == false,
    "deDE.lua should NOT load when selectedLocale=frFR")

-- nil selectedLocale falls back to client locale
check("nil falls back to client",
    loadLocale("core/locale/deDE.lua", "deDE", nil) == true,
    "deDE.lua should load via GetLocale() fallback when selectedLocale is nil")

_G.QUI_TEST_LOCALE, _G.QUIDB = nil, nil
if failures > 0 then print(("\n%d FAILED"):format(failures)); os.exit(1) end
print("\nall passed")
