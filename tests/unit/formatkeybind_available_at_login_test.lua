-- tests/unit/formatkeybind_available_at_login_test.lua
-- Run: lua tests/unit/formatkeybind_available_at_login_test.lua
--
-- Regression: the suite split moved FormatKeybind into QUI_QoL, a LoadOnDemand
-- ("lod") sub-addon that the loader stages ~1.2s after the first frame.
-- QUI_ActionBars is a "login" sub-addon: it builds bars and renders keybind
-- text at login -- BEFORE QoL loads -- by reading ns.FormatKeybind. With the
-- definition living only in the LOD module, ns.FormatKeybind was nil at that
-- point, UpdateKeybindText treated every binding as empty, and all hotkeys were
-- hidden even with showKeybinds enabled.
--
-- FormatKeybind now lives in core (loaded first, hard dependency of every
-- sub-addon), so a login-class sub-addon proxy resolves it without QoL present.

function LibStub() return nil end

-- 1. Core namespace: load core/utils.lua, the always-loaded-at-login path.
local coreNs = {}
assert(loadfile("core/utils.lua"))("QUI", coreNs)
assert(type(coreNs.FormatKeybind) == "function",
    "core must define ns.FormatKeybind so login-class sub-addons get it at login")

-- 2. Model a login sub-addon's bootstrap proxy (e.g. QUI_ActionBars) with the
--    LOD QoL addon NOT loaded -- exactly the state at login when bars render.
local subNs = setmetatable({}, {
    __index = coreNs,
    __newindex = function(_, k, v) coreNs[k] = v end,
})
assert(type(subNs.FormatKeybind) == "function",
    "login-class sub-addon must resolve ns.FormatKeybind via core before QoL loads")

-- 3. Formatting behaviour: abbreviation, modifier shortening, truncation.
local F = subNs.FormatKeybind
assert(F(nil) == nil, "nil keybind -> nil")
assert(F("1") == "1", "plain key passthrough")
assert(F("SHIFT-2") == "S2", "SHIFT- modifier shortened")
assert(F("CTRL-MOUSEWHEELUP") == "CWU", "mousewheel shortened before modifier strip")
assert(F("BUTTON4") == "B4", "mouse button shortened")
assert(#F("SHIFT-CTRL-ALT-NUMPAD0") <= 4, "result truncated to max 4 chars")

print("formatkeybind_available_at_login_test: OK")
