-- tests/unit/test_form_slider_init.lua
-- Regression: building a slider widget must NOT write the DB. framework.lua
-- used to call the local SetValue(GetValue(), true) at construction time,
-- which both clamps the stored value to the widget's min/max (silently
-- rewriting stored values outside the widget's range on every options-panel
-- open) and seeds absent keys with the widget's min (violating the raw-SV
-- absent-key-means-default convention aura element stores rely on). Init
-- must be display-only; only user interaction (drag, nudge, editbox enter,
-- sibling broadcast from a user action) may write dbTable[dbKey].
--
-- Loads the REAL framework headlessly via the search-cache generator's WoW-API
-- stub preamble, then drives the real GUI:CreateFormSlider constructor.
-- Run: lua tests/unit/test_form_slider_init.lua

local GEN_PATH = "tools/generate_search_cache.lua"
local CUT_MARKER = 'local frame = create_stub_node("Frame", nil, false)'
local fh = assert(io.open(GEN_PATH, "rb"), "cannot open " .. GEN_PATH)
local src = fh:read("*a"); fh:close()
local cut = assert(src:find(CUT_MARKER, 1, true),
    "generator preamble cut marker not found -- update CUT_MARKER")
assert((loadstring or load)(src:sub(1, cut - 1), "@gen-preamble"))()

local GUI = assert(_G.QUI and _G.QUI.GUI, "framework did not initialize QUI.GUI")
assert(type(GUI.CreateFormSlider) == "function", "framework must expose CreateFormSlider")

-- The generator's stub CreateFrame has no GetThumbTexture handler -- the
-- generator itself never builds a real slider (CreateFormSlider is
-- monkey-patched to a capture stub before any page walk runs), so this gap
-- never surfaces there. A real Slider widget calls slider:GetThumbTexture()
-- during construction, so give Slider stubs a thumb-texture handle.
local realCreateFrame = _G.CreateFrame
_G.CreateFrame = function(frameType, name, parent, ...)
    local node = realCreateFrame(frameType, name, parent, ...)
    if frameType == "Slider" then
        node.GetThumbTexture = function() return realCreateFrame("Texture", nil, node) end
    end
    return node
end

local parent = _G.CreateFrame("Frame")

-- Case A: a stored value above the widget's max must survive widget creation
-- (the display clamps to the widget range; the store does not).
local store = { maxIcons = 40 }
GUI:CreateFormSlider(parent, "Max Icons", 0, 10, 1, "maxIcons", store, nil, {}, {})
assert(store.maxIcons == 40,
    "widget init clamped store: " .. tostring(store.maxIcons))

-- Case B: an absent key must stay absent (raw-SV absent-key-means-default).
local store2 = {}
GUI:CreateFormSlider(parent, "Max Icons", 0, 10, 1, "maxIcons", store2, nil, {}, {})
assert(store2.maxIcons == nil,
    "widget init seeded absent key: " .. tostring(store2.maxIcons))

print("OK: test_form_slider_init")
