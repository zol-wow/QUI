-- tests/unit/options_safecall_migration_test.lua
-- Source-text contract pins for the Task 1a QUI_Options pcall->SafeCall
-- migration (own-widget pcalls unwrapped; registered-callback pcalls routed
-- through ns.SafeCall). Run: lua5.1 tests/unit/options_safecall_migration_test.lua
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

local framework = readAll("QUI_Options/framework.lua")
local sharedSrc = readAll("QUI_Options/shared.lua")
local auraSpellList = readAll("QUI_Options/aura_spell_list.lua")
local initSrc = readAll("QUI_Options/init.lua")

---------------------------------------------------------------------------
-- Registered/feature callbacks route through ns.SafeCall("bulkhead", ...)
---------------------------------------------------------------------------
check("pin: feature.apply routed through ns.SafeCall bulkhead",
    framework:find('ns.SafeCall("bulkhead", feature.apply', 1, true) ~= nil)

check("pin: _quiTooltipAugment routed through ns.SafeCall bulkhead",
    framework:find('ns.SafeCallMethod("bulkhead", self, "_quiTooltipAugment", GameTooltip)', 1, true) ~= nil)

check("pin: feature.searchNavigate routed through ns.SafeCall bulkhead, ok/handled preserved",
    framework:find('local ok, handled = ns.SafeCall("bulkhead", feature.searchNavigate, entry, {', 1, true) ~= nil
    and framework:find("return ok and handled ~= false", 1, true) ~= nil)

---------------------------------------------------------------------------
-- Own-widget SetVerticalScroll pcalls fully unwrapped (framework, shared,
-- aura_spell_list) — the setter only; getters are a later task.
---------------------------------------------------------------------------
check("pin: NO pcall(self.SetVerticalScroll remains in framework.lua",
    framework:find("pcall(self.SetVerticalScroll", 1, true) == nil)
check("pin: NO pcall(scroll.SetVerticalScroll remains in framework.lua",
    framework:find("pcall(scroll.SetVerticalScroll", 1, true) == nil)
check("pin: NO pcall(scrollFrame.SetVerticalScroll remains in framework.lua",
    framework:find("pcall(scrollFrame.SetVerticalScroll", 1, true) == nil)
check("pin: NO pcall(dropdown.SetBackdropBorderColor remains in framework.lua",
    framework:find("pcall(dropdown.SetBackdropBorderColor", 1, true) == nil)
check("pin: NO pcall(swatch.SetBackdropBorderColor remains in framework.lua",
    framework:find("pcall(swatch.SetBackdropBorderColor", 1, true) == nil)
check("pin: NO pcall(self.SetBackdropBorderColor remains in framework.lua",
    framework:find("pcall(self.SetBackdropBorderColor", 1, true) == nil)

check("pin: NO pcall(self.SetVerticalScroll remains in shared.lua",
    sharedSrc:find("pcall(self.SetVerticalScroll", 1, true) == nil)

check("pin: NO pcall(self.SetVerticalScroll remains in aura_spell_list.lua",
    auraSpellList:find("pcall(self.SetVerticalScroll", 1, true) == nil)
check("pin: NO pcall(scroll.SetVerticalScroll remains in aura_spell_list.lua",
    auraSpellList:find("pcall(scroll.SetVerticalScroll", 1, true) == nil)
check("pin: NO pcall(popup._scroll.SetVerticalScroll remains in aura_spell_list.lua",
    auraSpellList:find("pcall(popup._scroll.SetVerticalScroll", 1, true) == nil)

---------------------------------------------------------------------------
-- GUI.Hide pcalls fully unwrapped (framework + init duplicate)
---------------------------------------------------------------------------
check("pin: NO pcall(GUI.Hide remains in framework.lua",
    framework:find("pcall(GUI.Hide", 1, true) == nil)
check("pin: NO pcall(GUI.Hide remains in init.lua",
    initSrc:find("pcall(GUI.Hide", 1, true) == nil)
check("pin: framework.lua GUI.Hide call site still exists (existence-guarded, direct call)",
    framework:find("if GUI and GUI.Hide then GUI:Hide() end", 1, true) ~= nil)
check("pin: init.lua GUI.Hide call site still exists (existence-guarded, direct call)",
    initSrc:find("if GUI and GUI.Hide then GUI:Hide() end", 1, true) ~= nil)

---------------------------------------------------------------------------
-- box.HighlightText unwrapped, existence guard kept
---------------------------------------------------------------------------
check("pin: box.HighlightText direct call, existence guard kept",
    framework:find("if box.HighlightText then box:HighlightText() end", 1, true) ~= nil)

---------------------------------------------------------------------------
-- Task 2: GetSafeVerticalScroll(Range) getters no longer double-wrap the
-- pure-arithmetic step in its own pcall (the raw Blizzard scroll-getter call
-- is still pcall-guarded; only the redundant math.max/min/+0 wrap on the
-- already-fetched plain number was removed). Guard against re-introducing
-- the arithmetic-wrap AND against deleting the getters entirely.
---------------------------------------------------------------------------
check("pin: GetSafeVerticalScroll(Range) getters still present and direct (no arithmetic pcall)",
    sharedSrc:find('local function GetSafeVerticalScrollRange(scrollFrame)', 1, true) ~= nil
    and sharedSrc:find('local function GetSafeVerticalScroll(scrollFrame)', 1, true) ~= nil
    and sharedSrc:find('return math.max(0, maxScroll or 0)', 1, true) ~= nil
    and sharedSrc:find('return currentScroll + 0', 1, true) ~= nil)

check("pin: NO pcall(function() wrapping the scroll arithmetic remains in shared.lua",
    sharedSrc:find('pcall(function() return math.max(0, maxScroll or 0) end)', 1, true) == nil
    and sharedSrc:find('pcall(function() return currentScroll + 0 end)', 1, true) == nil
    and sharedSrc:find('local okNewScroll, newScroll = pcall(function()', 1, true) == nil)

if fails > 0 then error(fails .. " failure(s) in options_safecall_migration_test") end
print("OK: options_safecall_migration_test (all checks passed)")
