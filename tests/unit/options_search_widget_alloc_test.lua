-- tests/unit/options_search_widget_alloc_test.lua
-- Regression: building a setting widget must NOT construct a search-widget
-- descriptor (or its entry table / builder closure) once the generated search
-- cache is present. Those allocations are pure waste at runtime -- the search
-- registry short-circuits on HasGeneratedSearchCache -- yet they ran for every
-- widget on every options page (re)build, which happens on every tab switch.
-- Skipping them at the call site removes that per-widget allocation churn.
--
-- Loads the REAL framework headlessly via the search-cache generator's WoW-API
-- stub preamble, then drives a real widget builder.
-- Run: lua tests/unit/options_search_widget_alloc_test.lua

local GEN_PATH = "tools/generate_search_cache.lua"
local CUT_MARKER = 'local frame = create_stub_node("Frame", nil, false)'
local fh = assert(io.open(GEN_PATH, "rb"), "cannot open " .. GEN_PATH)
local src = fh:read("*a"); fh:close()
local cut = assert(src:find(CUT_MARKER, 1, true),
    "generator preamble cut marker not found -- update CUT_MARKER")
assert((loadstring or load)(src:sub(1, cut - 1), "@gen-preamble"))()

local GUI = assert(_G.QUI and _G.QUI.GUI, "framework did not initialize QUI.GUI")
assert(type(GUI.CreateFormToggle) == "function", "framework must expose CreateFormToggle")
assert(type(GUI.HasGeneratedSearchCache) == "function", "framework must expose HasGeneratedSearchCache")

-- Spy on descriptor construction without changing behaviour.
local descriptorCalls = 0
local realBuild = GUI.BuildSearchWidgetDescriptor
GUI.BuildSearchWidgetDescriptor = function(self, ...)
    descriptorCalls = descriptorCalls + 1
    return realBuild(self, ...)
end

local function buildToggle()
    local parent = _G.CreateFrame("Frame")
    local dbTable = { myToggle = false }
    return GUI:CreateFormToggle(parent, "My Toggle", "myToggle", dbTable)
end

-- Sanity / false-pass guard: with NO generated cache, the widget path SHOULD
-- still build a search descriptor (search must keep working pre-cache).
assert(not GUI:HasGeneratedSearchCache(), "precondition: no generated cache yet")
descriptorCalls = 0
buildToggle()
assert(descriptorCalls >= 1,
    "sanity: with no search cache present, building a widget should construct a search descriptor")

-- Now simulate the runtime state after the generated cache has loaded.
GUI._generatedSearchCacheVersion = 1
assert(GUI:HasGeneratedSearchCache(), "cache flag should report present")

descriptorCalls = 0
buildToggle()
assert(descriptorCalls == 0,
    "building a widget must not construct a search descriptor when the generated cache "
    .. "is present (got " .. descriptorCalls .. " descriptor build(s) per widget)")

print("OK: options_search_widget_alloc_test")
