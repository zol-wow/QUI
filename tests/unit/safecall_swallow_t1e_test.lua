-- tests/unit/safecall_swallow_t1e_test.lua
-- Source-text contract pins for Task 1e: 11 swallow-pcall sites converted to
-- ns.SafeCall (policy-classified "bulkhead") or existence-guarded loud direct
-- calls, across core/uikit.lua, modules/layout/layoutmode_settings.lua and
-- modules/layout/layoutmode_utils.lua. Pins the converted shape present, the
-- old bare-pcall shape absent (exact strings), the hot-path no-closure
-- constraint at uikit.lua site 1, the retained fallback branch at
-- layoutmode_settings.lua site 7, and the existence-guarded direct calls at
-- layoutmode_utils.lua sites 10-11.
-- Run: lua5.1 tests/unit/safecall_swallow_t1e_test.lua
local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return (d:gsub("\r\n", "\n"))
end

local fails = 0
local function check(name, ok)
    if ok then print("  ok  " .. name)
    else fails = fails + 1; print("FAIL  " .. name) end
end

---------------------------------------------------------------------------
-- File 1: core/uikit.lua
---------------------------------------------------------------------------
local uk = readAll("core/uikit.lua")

-- Site 1: animationDriverOnUpdate, state.onUpdate tick. PER-FRAME HOT PATH:
-- must be a direct function-ref pass, never a closure allocation.
check('site1: ns.SafeCall("bulkhead", state.onUpdate, owner, value, progress)',
    uk:find('ns.SafeCall("bulkhead", state.onUpdate, owner, value, progress)', 1, true) ~= nil)
check("site1: old bare pcall(state.onUpdate, owner, value, progress) gone",
    uk:find("pcall(state.onUpdate, owner, value, progress)", 1, true) == nil)
do
    local site1Line = uk:match('([^\n]*ns%.SafeCall%("bulkhead", state%.onUpdate[^\n]*)')
    check("site1: no-closure hot-path pin (no 'function(' on the statement line)",
        site1Line ~= nil and not site1Line:find("function(", 1, true))
end

-- Site 2: animationDriverOnUpdate, state.onFinish on tween completion.
check('site2: ns.SafeCall("bulkhead", state.onFinish, owner, state.toValue)',
    uk:find('ns.SafeCall("bulkhead", state.onFinish, owner, state.toValue)', 1, true) ~= nil)
check("site2: old bare pcall(state.onFinish, owner, state.toValue) gone",
    uk:find("pcall(state.onFinish, owner, state.toValue)", 1, true) == nil)

-- Site 3: AnimateValue initial tick.
check('site3: ns.SafeCall("bulkhead", options.onUpdate, owner, options.fromValue or 0, 0)',
    uk:find('ns.SafeCall("bulkhead", options.onUpdate, owner, options.fromValue or 0, 0)', 1, true) ~= nil)
check("site3: old bare pcall(options.onUpdate, owner, options.fromValue or 0, 0) gone",
    uk:find("pcall(options.onUpdate, owner, options.fromValue or 0, 0)", 1, true) == nil)

-- Site 4: RefreshScaleBoundWidgets registry walk.
check('site4: ns.SafeCall("bulkhead", refreshFn, owner)',
    uk:find('ns.SafeCall("bulkhead", refreshFn, owner)', 1, true) ~= nil)
check("site4: old bare pcall(refreshFn, owner) gone",
    uk:find("pcall(refreshFn, owner)", 1, true) == nil)

-- Site 5: ApplyTooltip rich-tooltip builder.
check('site5: ns.SafeCall("bulkhead", richBuilder, row, self)',
    uk:find('ns.SafeCall("bulkhead", richBuilder, row, self)', 1, true) ~= nil)
check("site5: old bare pcall(richBuilder, row, self) gone",
    uk:find("pcall(richBuilder, row, self)", 1, true) == nil)

---------------------------------------------------------------------------
-- File 2: modules/layout/layoutmode_settings.lua
---------------------------------------------------------------------------
local ls = readAll("modules/layout/layoutmode_settings.lua")

-- Site 6: BuildContent, feature.onNavigate — result discarded.
check('site6: ns.SafeCall("bulkhead", feature.onNavigate, key, nil, {',
    ls:find('ns.SafeCall("bulkhead", feature.onNavigate, key, nil, {', 1, true) ~= nil)
check("site6: old bare pcall(feature.onNavigate, key, nil, { gone",
    ls:find("pcall(feature.onNavigate, key, nil, {", 1, true) == nil)

-- Site 7: renderSharedFeature, Renderer.RenderFeature — ok IS checked;
-- failure branch (ClearContent + rebuild) must survive byte-equivalent.
check('site7: ns.SafeCallMethod("bulkhead", Renderer, "RenderFeature", feature, content, {',
    ls:find('ns.SafeCallMethod("bulkhead", Renderer, "RenderFeature", feature, content, {', 1, true) ~= nil)
check("site7: old bare pcall(Renderer.RenderFeature, ...) gone",
    ls:find("pcall(Renderer.RenderFeature, Renderer, feature, content, {", 1, true) == nil)
check("site7: fallback branch retained (else ClearContent(panel) rebuild)",
    ls:find("else\n            ClearContent(panel)\n            content = panel._content", 1, true) ~= nil)

-- Site 8: anchoring-details, feature.getAnchorStatus — nil-fallback kept.
check('site8: ns.SafeCall("bulkhead", feature.getAnchorStatus, key)',
    ls:find('ns.SafeCall("bulkhead", feature.getAnchorStatus, key)', 1, true) ~= nil)
check("site8: old bare pcall(feature.getAnchorStatus, key) gone",
    ls:find("pcall(feature.getAnchorStatus, key)", 1, true) == nil)
check("site8: nil-fallback flow retained (ok and type(result) == \"table\")",
    ls:find('if ok and type(result) == "table" then', 1, true) ~= nil)

---------------------------------------------------------------------------
-- File 3: modules/layout/layoutmode_utils.lua
---------------------------------------------------------------------------
local lu = readAll("modules/layout/layoutmode_utils.lua")

-- Site 9: row OnClick, feature.onNavigate.
check('site9: ns.SafeCall("bulkhead", feature.onNavigate, providerKey, route, {',
    lu:find('ns.SafeCall("bulkhead", feature.onNavigate, providerKey, route, {', 1, true) ~= nil)
check("site9: old bare pcall(feature.onNavigate, providerKey, route, { gone",
    lu:find("pcall(feature.onNavigate, providerKey, route, {", 1, true) == nil)

-- Site 10: our own SlashCommandOpen — existence-guarded, loud direct call.
check('site10: existence-guarded direct call QUI:SlashCommandOpen("")',
    lu:find('QUI:SlashCommandOpen("")', 1, true) ~= nil)
check("site10: old pcall(QUI.SlashCommandOpen, QUI, \"\") gone",
    lu:find('pcall(QUI.SlashCommandOpen, QUI, "")', 1, true) == nil)
check("site10: existence guard preserved (if QUI and QUI.SlashCommandOpen then)",
    lu:find("if QUI and QUI.SlashCommandOpen then", 1, true) ~= nil)

-- Site 11: our own GUI.Toggle — existence-guarded, loud direct call.
check("site11: existence-guarded direct call GUI:Toggle()",
    lu:find("GUI:Toggle()", 1, true) ~= nil)
check("site11: old pcall(GUI.Toggle, GUI) gone",
    lu:find("pcall(GUI.Toggle, GUI)", 1, true) == nil)
check("site11: existence guard preserved (elseif GUI and GUI.Toggle then)",
    lu:find("elseif GUI and GUI.Toggle then", 1, true) ~= nil)

if fails > 0 then error(fails .. " failure(s) in safecall_swallow_t1e_test") end
print("OK: safecall_swallow_t1e_test (all checks passed)")
